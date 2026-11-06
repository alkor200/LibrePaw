import Foundation

@Observable
@MainActor
final class LoginViewModel {
    var serverURLString = ""
    var email = ""
    var password = ""
    private(set) var isLoggingIn = false
    var errorMessage: String?

    private let appSession: AppSession

    init(appSession: AppSession) {
        self.appSession = appSession
    }

    var usesInsecureConnection: Bool {
        serverURLString.trimmed.lowercased().hasPrefix("http://")
    }

    var canSubmit: Bool {
        !serverURLString.trimmed.isEmpty && !email.trimmed.isEmpty && !password.isEmpty && !isLoggingIn
    }

    func logIn() async {
        errorMessage = nil

        guard let url = normalizedServerURL() else {
            errorMessage = "Enter a valid server address, e.g. traccar.example.com"
            return
        }

        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            try await appSession.logIn(serverURL: url, email: email.trimmed, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedServerURL() -> URL? {
        var raw = serverURLString.trimmed
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") {
            raw = "https://" + raw
        }
        guard let url = URL(string: raw), url.host != nil else { return nil }
        return url
    }
}
