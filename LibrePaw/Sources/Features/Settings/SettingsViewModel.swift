import Foundation
import LibrePawKit

@Observable
@MainActor
final class SettingsViewModel {
    let session: StoredSession
    private(set) var isShowingLogOutConfirmation = false
    private let onLogOut: () -> Void

    init(session: StoredSession, onLogOut: @escaping () -> Void) {
        self.session = session
        self.onLogOut = onLogOut
    }

    func requestLogOut() {
        isShowingLogOutConfirmation = true
    }

    func cancelLogOut() {
        isShowingLogOutConfirmation = false
    }

    func confirmLogOut() {
        isShowingLogOutConfirmation = false
        onLogOut()
    }
}
