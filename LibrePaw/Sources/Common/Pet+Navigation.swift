import SwiftUI
import MapKit
import LibrePawKit

/// A maps app a "Navigate to <Pet>" action can hand directions off to.
/// Offered as a chooser rather than always going straight to Apple Maps:
/// most people have a navigation app they actually use day to day, and it
/// isn't necessarily Apple's own.
enum NavigationApp: CaseIterable, Identifiable {
    case apple
    case googleMaps
    case waze

    var id: Self { self }

    var label: String {
        switch self {
        case .apple: "Apple Maps"
        case .googleMaps: "Google Maps"
        case .waze: "Waze"
        }
    }

    /// `nil` for Apple Maps, it's always available, no scheme check needed.
    private var schemeURL: URL? {
        switch self {
        case .apple: nil
        case .googleMaps: URL(string: "comgooglemaps://")
        case .waze: URL(string: "waze://")
        }
    }

    /// `canOpenURL` always returns `false` for a scheme not declared in
    /// `LSApplicationQueriesSchemes` (see project.yml's `info.properties`),
    /// regardless of whether the app is actually installed.
    @MainActor
    var isInstalled: Bool {
        schemeURL.map(UIApplication.shared.canOpenURL) ?? true
    }

    /// Every case still installed, in a fixed, predictable order. Always
    /// contains at least `.apple`.
    @MainActor
    static var installed: [NavigationApp] {
        allCases.filter(\.isInstalled)
    }

    /// If exactly one navigation app is installed, there's nothing to
    /// choose between: opens directions in it directly and returns `true`.
    /// Otherwise does nothing and returns `false`, the caller's cue to
    /// present a chooser over `installed` instead.
    @MainActor
    static func openIfOnlyOneInstalled(for pet: Pet) -> Bool {
        guard installed.count == 1, let only = installed.first else { return false }
        only.openDirections(to: pet)
        return true
    }

    /// Opens directions to `pet`'s last known position in this app, or does
    /// nothing if there's no position yet.
    @MainActor
    func openDirections(to pet: Pet) {
        guard let coordinate = pet.lastPosition?.coordinate.clLocationCoordinate2D else { return }
        switch self {
        case .apple:
            let placemark = MKPlacemark(coordinate: coordinate)
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = pet.name
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
        case .googleMaps:
            open(scheme: "comgooglemaps://", queryItems: [
                URLQueryItem(name: "daddr", value: "\(coordinate.latitude),\(coordinate.longitude)")
            ])
        case .waze:
            open(scheme: "waze://", queryItems: [
                URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
                URLQueryItem(name: "navigate", value: "yes")
            ])
        }
    }

    @MainActor
    private func open(scheme: String, queryItems: [URLQueryItem]) {
        var components = URLComponents(string: scheme)
        components?.queryItems = queryItems
        guard let url = components?.url else { return }
        UIApplication.shared.open(url)
    }
}
