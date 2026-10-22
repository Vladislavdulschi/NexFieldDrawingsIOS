import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: DrawingsViewModel

    @State private var serverUrl: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var showSavedAccounts: Bool = false

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.09, blue: 0.16)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Spacer().frame(height: 24)

                    // Logo / Header
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.18))
                                .frame(width: 72, height: 72)
                            Text("📐")
                                .font(.system(size: 36))
                        }
                        Text("NexField Drawings")
                            .font(.system(size: 26, weight: .black))
                            .foregroundColor(.white)
                        Text("Native iOS Blueprint & Markup Suite")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.gray)
                    }

                    // Login Card
                    VStack(alignment: .leading, spacing: 14) {
                        let accounts = viewModel.getSavedAccounts()
                        if !accounts.isEmpty {
                            Menu {
                                ForEach(accounts) { acc in
                                    Button("\(acc.userName.isEmpty ? acc.email : acc.userName) (\(acc.email))") {
                                        serverUrl = acc.serverUrl
                                        email = acc.email
                                        password = acc.password
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("👤 Saved Accounts (\(accounts.count))")
                                        .font(.system(size: 13, weight: .bold))
                                    Spacer()
                                    Text("▼")
                                }
                                .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))
                                .padding(10)
                                .background(Color(red: 0.12, green: 0.16, blue: 0.23))
                                .cornerRadius(10)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("SERVER URL")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                            TextField("https://nexfield.co.uk", text: $serverUrl)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(Color(red: 0.07, green: 0.09, blue: 0.15))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("EMAIL")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                            TextField("engineer@nexfield.co.uk", text: $email)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(Color(red: 0.07, green: 0.09, blue: 0.15))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("PASSWORD")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                            SecureField("••••••••", text: $password)
                                .padding(12)
                                .background(Color(red: 0.07, green: 0.09, blue: 0.15))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }

                        if let msg = viewModel.statusBannerMessage {
                            Text(msg)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(red: 0.98, green: 0.45, blue: 0.45))
                                .padding(.top, 4)
                        }

                        Button {
                            Task {
                                await viewModel.login(serverUrl: serverUrl, email: email, password: password)
                            }
                        } label: {
                            HStack {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .tint(.black)
                                }
                                Text(viewModel.isLoading ? "Signing In..." : "Sign In to NexField")
                                    .font(.system(size: 15, weight: .black))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(red: 0.96, green: 0.62, blue: 0.04))
                            .foregroundColor(Color(red: 0.07, green: 0.09, blue: 0.15))
                            .cornerRadius(12)
                        }
                        .disabled(viewModel.isLoading)

                        Button {
                            viewModel.enterOfflineMode()
                        } label: {
                            Text("📂 Work Offline (Open Saved iPhone Blueprints)")
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(red: 0.12, green: 0.16, blue: 0.23))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .padding(20)
                    .background(Color(red: 0.10, green: 0.14, blue: 0.21))
                    .cornerRadius(18)
                    .padding(.horizontal, 18)
                }
            }
        }
        .onAppear {
            serverUrl = viewModel.baseUrl
            email = viewModel.savedEmail
            password = viewModel.savedPassword
        }
    }
}
