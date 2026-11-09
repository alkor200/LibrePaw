import MapKit
import SwiftUI

/// The map layers a user can switch between, mirrors the choices in
/// Apple's own Maps app.
enum MapLayer: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: localized("Standard")
        case .satellite: localized("Satellite")
        case .hybrid: localized("Hybrid")
        }
    }

    var systemImage: String {
        switch self {
        case .standard: "map"
        case .satellite: "globe.americas.fill"
        case .hybrid: "square.stack.3d.up.fill"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .standard: .standard
        case .satellite: .imagery
        case .hybrid: .hybrid
        }
    }
}

/// Chrome for a custom floating map control, sized to match
/// `MapUserLocationButton`'s own fixed 44x44pt frame exactly (measured live
/// via a `GeometryReader`, since that size isn't documented anywhere), so
/// custom controls placed alongside it read as one consistent set.
struct MapControlButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 18))
            .frame(width: 44, height: 44)
            .background(.thinMaterial, in: Circle())
    }
}

extension View {
    func mapControlButtonStyle() -> some View {
        modifier(MapControlButtonStyle())
    }
}

/// A layers menu button matching Apple Maps' own control for switching map
/// type, for use inside a `Map`'s `.mapControls`.
struct MapLayerPicker: View {
    @Binding var selection: MapLayer

    var body: some View {
        Menu {
            Picker("Map Layer", selection: $selection) {
                ForEach(MapLayer.allCases) { layer in
                    Label(layer.label, systemImage: layer.systemImage).tag(layer)
                }
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .mapControlButtonStyle()
        }
        .menuStyle(.borderlessButton)
    }
}
