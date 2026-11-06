import SwiftUI
import ScentrailKit

/// Presentation details for `Pet.Status` shared across the Pets list and
/// pet detail screens.
extension Pet.Status {
    var label: String {
        switch self {
        case .online: "Online"
        case .offline: "Offline"
        case .unknown: "Unknown"
        }
    }

    var tintColor: Color {
        switch self {
        case .online: .green
        case .offline: .secondary
        case .unknown: .orange
        }
    }
}
