import SwiftUI
import LibrePawKit

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @Environment(LanguageSettings.self) private var languageSettings
    @Environment(AppearanceSettings.self) private var appearanceSettings

    init(session: StoredSession, onLogOut: @escaping () -> Void) {
        _viewModel = State(initialValue: SettingsViewModel(session: session, onLogOut: onLogOut))
    }

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Server", value: viewModel.session.serverURL.host ?? viewModel.session.serverURL.absoluteString)
                LabeledContent("Email", value: viewModel.session.email)
            }
            .listRowBackground(Color.appSurface)

            Section {
                Picker("Language", selection: Binding(
                    get: { languageSettings.language },
                    set: { languageSettings.language = $0 }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
            } footer: {
                Text("Automatic follows your iPhone's own language setting.")
            }
            .listRowBackground(Color.appSurface)

            Section {
                Picker("Appearance", selection: Binding(
                    get: { appearanceSettings.appearance },
                    set: { appearanceSettings.appearance = $0 }
                )) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
            } footer: {
                Text("Automatic follows your iPhone's own appearance setting.")
            }
            .listRowBackground(Color.appSurface)

            Section {
                Button("Log Out", role: .destructive) {
                    viewModel.requestLogOut()
                }
            }
            .listRowBackground(Color.appSurface)

            Section {
                LabeledContent("Version", value: appVersion)
            } footer: {
                Text("LibrePaw is open source software and is not affiliated with Traccar.")
            }
            .listRowBackground(Color.appSurface)
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Settings")
        .confirmationDialog(
            "Log Out?",
            isPresented: Binding(
                get: { viewModel.isShowingLogOutConfirmation },
                set: { isPresented in if !isPresented { viewModel.cancelLogOut() } }
            )
        ) {
            Button("Log Out", role: .destructive) { viewModel.confirmLogOut() }
            Button("Cancel", role: .cancel) { viewModel.cancelLogOut() }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }
}

#Preview {
    NavigationStack {
        SettingsView(
            session: StoredSession(serverURL: URL(string: "https://traccar.example.com")!, email: "owner@example.com", password: "x"),
            onLogOut: {}
        )
    }
    .environment(LanguageSettings())
    .environment(AppearanceSettings())
}
