import MapKit
import SwiftUI

/// The map layers a user can switch between - mirrors the choices in
/// Apple's own Maps app.
enum MapLayer: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .satellite: "Satellite"
        case .hybrid: "Hybrid"
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
                .padding(8)
                .background(.thinMaterial, in: Circle())
        }
        .menuStyle(.borderlessButton)
    }
}
