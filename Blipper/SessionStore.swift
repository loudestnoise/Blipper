//
//  SessionStore.swift
//  Blipper
//

import Foundation
import Observation
import OSLog

/// Holds the signed-in Tidepool login, the account it is viewing, and the matching data provider.
@Observable
@MainActor
final class SessionStore {
    private(set) var credentials: TidepoolCredentials?
    /// The login's own account first, then accounts shared with it. Empty until loaded.
    private(set) var accounts: [ViewableAccount] = []
    /// Clinics the login is a clinician of; their patients are fetched on demand, never kept.
    private(set) var clinics: [ClinicSummary] = []
    /// The clinic the last patient was picked from, so going back lands on its patient list.
    private(set) var lastClinic: ClinicSummary?
    /// The account being viewed; `nil` while signed out or until one is picked.
    private(set) var account: ViewableAccount?
    /// The account opened at launch without asking; `nil` asks each time there is a choice.
    private(set) var defaultAccount: ViewableAccount?
    /// Data source for the viewed account; `nil` until there is one.
    private(set) var provider: TidepoolGlucoseProvider?
    private(set) var isSigningIn = false
    private(set) var isLoadingAccounts = false
    private(set) var errorMessage: String?
    /// Why the account list could not be loaded, when there is no account to fall back on.
    private(set) var accountsError: String?

    private let client = TidepoolClient()
    private static let log = Logger(subsystem: "com.PickleTron.blipper", category: "session")

    init() {
        let saved = CredentialStore.load()
        credentials = saved
        if saved != nil, let preferred = CredentialStore.loadDefaultAccount() {
            defaultAccount = preferred
            account = preferred
        }
        rebuildProvider()
        Self.log.notice("session: saved credentials \(saved == nil ? "absent" : "present", privacy: .public), default account \(self.defaultAccount == nil ? "absent" : "present", privacy: .public)")
    }

    var isSignedIn: Bool { credentials != nil }
    var email: String? { credentials?.email }
    var sharedAccounts: [ViewableAccount] { accounts.filter { !$0.isOwn } }
    /// Whether there is anything to choose between besides the login's own account.
    var hasAccountChoice: Bool { !sharedAccounts.isEmpty || !clinics.isEmpty }

    /// Verifies the login against Tidepool before storing it, then finds the accounts it can view.
    func signIn(email: String, password: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your Tidepool email and password."
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let session = try await client.login(email: trimmed, password: password)
            let credentials = TidepoolCredentials(email: trimmed, password: password)
            try CredentialStore.save(credentials)
            self.credentials = credentials
            errorMessage = nil
            await loadAccounts(session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        CredentialStore.clear()
        credentials = nil
        accounts = []
        clinics = []
        lastClinic = nil
        apiSession = nil
        account = nil
        defaultAccount = nil
        accountsError = nil
        errorMessage = nil
        rebuildProvider()
    }

    /// Reloads the accounts this login can view. With only its own, that one is opened; with
    /// shared ones and nothing picked yet, `account` stays `nil` so the picker can ask.
    func refreshAccounts() async {
        guard let credentials, !isLoadingAccounts else { return }
        accountsError = nil
        do {
            let session = try await client.login(email: credentials.email, password: credentials.password)
            await loadAccounts(session: session)
        } catch {
            if account == nil { accountsError = error.localizedDescription }
        }
    }

    /// Views `account`. From the first-run picker `makeDefault` says whether to remember it;
    /// `nil` (switching in Settings) leaves the remembered account alone.
    func select(_ account: ViewableAccount, makeDefault: Bool? = nil) {
        self.account = account
        if let makeDefault { setDefault(makeDefault ? account : nil) }
        rebuildProvider()
    }

    /// Views a clinic patient. Patients are never remembered across launches.
    func select(_ patient: ClinicPatient, in clinic: ClinicSummary) {
        lastClinic = clinic
        select(ViewableAccount(id: patient.id, name: patient.fullName, isOwn: false, clinicName: clinic.name))
    }

    /// One page of a clinic's patients, logging in again once if the session has expired.
    func patients(in clinic: ClinicSummary, search: String, offset: Int, limit: Int) async throws -> ClinicPatientPage {
        guard let credentials else { throw TidepoolError.invalidCredentials }
        func page(_ session: TidepoolSession) async throws -> ClinicPatientPage {
            try await client.patients(session: session, clinicID: clinic.id, search: search, offset: offset, limit: limit)
        }
        if let session = apiSession {
            do { return try await page(session) } catch TidepoolError.invalidCredentials { apiSession = nil }
        }
        let fresh = try await client.login(email: credentials.email, password: credentials.password)
        apiSession = fresh
        return try await page(fresh)
    }

    /// Stops viewing the current account and returns to the picker (a clinic's patient list, when
    /// the account was one of its patients).
    func leaveAccount() {
        if account?.isClinicPatient != true { lastClinic = nil }
        account = nil
        rebuildProvider()
    }

    func setDefault(_ account: ViewableAccount?) {
        defaultAccount = account
        CredentialStore.saveDefaultAccount(account)
    }

    // MARK: Private

    private func loadAccounts(session: TidepoolSession) async {
        guard let credentials else { return }
        isLoadingAccounts = true
        defer { isLoadingAccounts = false }
        apiSession = session
        do {
            let shared = try await client.sharedAccounts(session: session)
            // Most logins are not clinicians; a failure here must not block their own data.
            clinics = (try? await client.clinicsForClinician(session: session)) ?? []
            Self.log.notice("session: \(shared.count) shared accounts, \(self.clinics.count) clinics")
            let own = ViewableAccount(id: session.userID, name: credentials.email, isOwn: true)
            accounts = [own] + shared
            accountsError = nil

            // Drop a remembered or current account whose share has since been withdrawn.
            if let preferred = defaultAccount {
                setDefault(accounts.first { $0.id == preferred.id })
            }
            if let current = account, !current.isClinicPatient {
                account = accounts.first { $0.id == current.id }
            }
            if account == nil, !hasAccountChoice {
                account = own
            }
            rebuildProvider()
        } catch {
            if account == nil { accountsError = error.localizedDescription }
        }
    }

    /// Keeps the existing provider (and its session) unless the viewed account changed.
    private func rebuildProvider() {
        guard let credentials, let account else {
            provider = nil
            providerAccountID = nil
            return
        }
        guard provider == nil || providerAccountID != account.id else { return }
        provider = TidepoolGlucoseProvider(
            credentials: credentials, client: client, subjectID: account.isOwn ? nil : account.id
        )
        providerAccountID = account.id
    }

    @ObservationIgnored private var providerAccountID: String?
    /// Session for the store's own lookups (accounts, clinics, patients).
    @ObservationIgnored private var apiSession: TidepoolSession?
}
