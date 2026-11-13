import SwiftUI
import LibrePawKit

/// Explains who can actually see, and do anything with, a pet's homes:
/// visibility follows admin status (the one thing ADR-0019 asks for in
/// exchange for showing homes to everyone), while whether the account can
/// add/edit/delete at all follows Traccar's own `readonly` flag (see
/// ADR-0023). Shared by the homes list and the single-home editor, which
/// word it for their own context but must never disagree on which of the
/// three cases applies.
struct HomeVisibilityNotice: View {
    enum Context {
        /// `HomesView`: about every home, including ones not added yet.
        case homesList
        /// `SetHomeView`: about the one home being viewed or edited.
        case singleHome
    }

    let permissions: AccountPermissions
    let petName: String
    let context: Context

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.footnote)
        .foregroundStyle(.appSecondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var text: LocalizedStringKey {
        switch (context, permissions.isAdministrator, permissions.canManageHomes) {
        case (.homesList, true, _):
            "As an admin, homes you add here are visible to everyone with access to \(petName)."
        case (.homesList, false, false):
            "You have read-only access to this account. You can see homes here, but can't add, edit, or delete them."
        case (.homesList, false, true):
            "Homes you add here, and the excursions they create, are only visible to you. Ask an admin to add a home if it should apply to everyone."
        case (.singleHome, true, _):
            "Visible to everyone with access to \(petName)."
        case (.singleHome, false, false):
            "You have read-only access to this account. You can view this, but not edit or delete it."
        case (.singleHome, false, true):
            "Only visible to you. Ask an admin to add this if it should apply to everyone."
        }
    }

    private var systemImage: String {
        if permissions.isAdministrator {
            "person.3.fill"
        } else if !permissions.canManageHomes {
            "lock.fill"
        } else {
            "eye.slash.fill"
        }
    }
}
