//
//  TidepoolClient+Clinics.swift
//  Blipper
//
//  What a clinician login needs to pick a patient: the clinics it works in and each clinic's
//  patient list. Paths are the clinic service's, as Tidepool Web's clinic workspace uses them.
//

import Foundation

/// A patient of a clinic, as listed for its clinicians. Held in memory only; never stored or logged.
nonisolated struct ClinicPatient: Identifiable, Sendable, Equatable {
    /// Tidepool user ID.
    let id: String
    let fullName: String
    /// `yyyy-MM-dd`, as the clinic recorded it.
    let birthDate: String?
    let mrn: String?
}

nonisolated struct ClinicPatientPage: Sendable {
    let patients: [ClinicPatient]
    /// How many patients match the search in all, across pages.
    let matching: Int
}

extension TidepoolClient {
    /// GET /v1/clinicians/{userId}/clinics — clinics this login is a clinician of.
    func clinicsForClinician(session: TidepoolSession) async throws -> [ClinicSummary] {
        let data: Data
        do {
            data = try await send(session: session, method: "GET", path: "v1/clinicians/\(session.userID)/clinics")
        } catch TidepoolError.notFound {
            return []
        }
        return try JSONDecoder().decode([WireMembership].self, from: data)
            .map { ClinicSummary(id: $0.clinic.id, name: $0.clinic.name, shareCode: $0.clinic.shareCode ?? "") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// GET /v1/clinics/{clinicId}/patients, by name. `search` matches part of a name, an MRN, or
    /// a birth date written `yyyy-MM-dd`; the server does the matching.
    func patients(
        session: TidepoolSession, clinicID: String, search: String?, offset: Int, limit: Int
    ) async throws -> ClinicPatientPage {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
            // The service refuses a sort without a sortType, even for a field that is not a statistic.
            URLQueryItem(name: "sort", value: "+fullName"),
            URLQueryItem(name: "sortType", value: "cgm"),
        ]
        if let search, !search.isEmpty {
            query.append(URLQueryItem(name: "search", value: search))
        }
        let data = try await send(session: session, method: "GET", path: "v1/clinics/\(clinicID)/patients", query: query)
        let wire = try JSONDecoder().decode(WirePatients.self, from: data)
        let patients = (wire.data ?? []).map {
            ClinicPatient(
                id: $0.id,
                fullName: $0.fullName?.nilIfEmpty ?? "Unnamed patient",
                birthDate: $0.birthDate?.nilIfEmpty,
                mrn: $0.mrn?.nilIfEmpty
            )
        }
        return ClinicPatientPage(patients: patients, matching: wire.meta?.count ?? patients.count)
    }

    // MARK: Wire formats

    private struct WireMembership: Decodable {
        struct Clinic: Decodable {
            let id: String
            let name: String
            let shareCode: String?
        }
        let clinic: Clinic
    }

    private struct WirePatients: Decodable {
        struct Patient: Decodable {
            let id: String
            let fullName: String?
            let birthDate: String?
            let mrn: String?
        }
        struct Meta: Decodable {
            /// Patients matching the search; `totalCount` is the whole clinic.
            let count: Int?
        }
        let data: [Patient]?
        let meta: Meta?
    }
}
