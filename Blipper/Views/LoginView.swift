//
//  LoginView.swift
//  Blipper
//

import SwiftUI

struct LoginView: View {
    @Bindable var session: SessionStore

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Blipper")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                } header: {
                    Text("Tidepool account")
                } footer: {
                    Text("Your login is stored in the device Keychain and used only to fetch your CGM data from api.tidepool.org.")
                }

                if let errorMessage = session.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if session.isSigningIn {
                                ProgressView()
                            } else {
                                Text("Sign In")
                            }
                            Spacer()
                        }
                    }
                    .disabled(session.isSigningIn || email.isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { focus = .email }
        }
    }

    private func submit() {
        guard !session.isSigningIn else { return }
        Task { await session.signIn(email: email, password: password) }
    }
}

#Preview {
    LoginView(session: SessionStore())
}
