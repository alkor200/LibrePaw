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
        if let expiredSession = appSession.expiredSession {
            serverURLString = expiredSession.serverURL.absoluteString
            email = expiredSession.email
            errorMessage = localized("The server no longer accepts this account's password, e.g. because it was changed. Please sign in again.")
        }
    }

    var usesInsecureConnection: Bool {
        serverURLString.trimmed.lowercased().hasPrefix("http://")
    }

    var canSubmit: Bool {
        !serverURLString.trimmed.isEmpty && !email.trimmed.isEmpty && !password.isEmpty && !isLoggingIn && !usesInsecureConnection
    }

    func logIn() async {
        // The Log In button is disabled while this is false, but pressing
        // Return in the password field calls this directly.
        guard canSubmit else { return }
        errorMessage = nil

        guard let url = normalizedServerURL() else {
            errorMessage = localized("Enter a valid server address, e.g. traccar.example.com")
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
        // https only: http is rejected up front (see `usesInsecureConnection`)
        // and blocked by App Transport Security anyway, and anything else
        // (ftp://, ws://, ...) isn't a Traccar web address at all.
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }
}
