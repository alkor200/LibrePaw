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

/// The SF Symbol matching a battery charge level, shared by every screen
/// that shows a pet's tracker battery (pet detail's stat tile, the pets
/// grid's badge).
func batteryIcon(for percent: Double) -> String {
    switch percent {
    case ..<13: "battery.0"
    case ..<38: "battery.25"
    case ..<63: "battery.50"
    case ..<88: "battery.75"
    default: "battery.100"
    }
}
