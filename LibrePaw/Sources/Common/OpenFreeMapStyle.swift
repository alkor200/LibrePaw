import Foundation
import SwiftUI

/// OpenFreeMap serves openly-licensed, OSM-based vector tiles with no API
/// key, no account, and no published rate limit on its public instance,
/// unlike `tile.openstreetmap.org` (meant for light/demo use only) or any
/// commercial provider (MapTiler, Stadia, ...), which all require signing
/// up for a key. MIT-licensed and fully self-hostable if the public
/// instance ever goes away, see openfreemap.org. See ADR-0028 for why this
/// replaced MapKit.
enum OpenFreeMapStyle {
    /// The "liberty" style: a general-purpose, colorful street style,
    /// OpenFreeMap's closest equivalent to Apple's own `.standard` map
    /// style. OpenFreeMap doesn't offer a satellite/hybrid style, free
    /// satellite imagery isn't readily available the same way vector
    /// street data is, so `MapLayerPicker`'s satellite/hybrid options have
    /// no equivalent here.
    static let liberty = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    /// OpenFreeMap's "fiord" style, confirmed live (`curl`, 200):
    /// `https://tiles.openfreemap.org/styles/fiord`. Used in dark mode so
    /// switching appearance doesn't jump straight from a light green map to
    /// the system's dark chrome around it, the same jarring gap Apple Maps
    /// avoids by shipping its own dark basemap. OpenFreeMap's plain "dark"
    /// style was tried first but felt too stark a jump in practice; "fiord"
    /// is a softer, muted dark style, closer to Apple Maps' own dark mode.
    static let fiord = URL(string: "https://tiles.openfreemap.org/styles/fiord")!

    /// The style to use for the given system appearance, matching Apple
    /// Maps' own light/dark basemap switch.
    static func url(for colorScheme: ColorScheme) -> URL {
        colorScheme == .dark ? fiord : liberty
    }
}
