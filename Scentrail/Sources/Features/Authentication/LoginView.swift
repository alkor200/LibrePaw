import SwiftUI

struct LoginView: View {
    @State private var viewModel: LoginViewModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case server, email, password
    }

    init(appSession: AppSession) {
        _viewModel = State(initialValue: LoginViewModel(appSession: appSession))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "pawprint.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.tint)
                        Text("Scentrail")
                            .font(.title2.bold())
                        Text("Sign in with your Traccar account to see where your pets are.")
                            .font(.subheadline)
                            .foregroundStyle(.appSecondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section("Server") {
                    TextField("traccar.example.com", text: $viewModel.serverURLString)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .server)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .email }

                    if viewModel.usesInsecureConnection {
                        // iOS blocks plain-http connections outright (App
                        // Transport Security) — there's no insecure-but-
                        // working path, so say so plainly rather than
                        // implying the login will proceed unprotected.
                        Label(
                            "http addresses aren't supported — iOS blocks unencrypted connections. Use https instead.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                }
                .listRowBackground(Color.appSurface)

                Section("Account") {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }

                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await viewModel.logIn() } }
                }
                .listRowBackground(Color.appSurface)

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(Color.appSurface)
                }

                Section {
                    Button {
                        focusedField = nil
                        Task { await viewModel.logIn() }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isLoggingIn {
                                ProgressView()
                            } else {
                                Text("Log In")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                }
                .listRowBackground(Color.appSurface)
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
