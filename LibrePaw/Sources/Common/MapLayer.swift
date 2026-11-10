import SwiftUI

/// Chrome for a custom floating map control, sized to match the MapKit-era
/// `MapUserLocationButton`'s own fixed 44x44pt frame exactly (measured live
/// via a `GeometryReader`, since that size isn't documented anywhere), so
/// custom controls placed alongside it read as one consistent set.
///
/// This file used to also define `MapLayer`/`MapLayerPicker` for switching
/// between Apple's standard/satellite/hybrid map styles. OpenFreeMap only
/// offers general-purpose vector styles for free, with no satellite
/// imagery equivalent (see ADR-0028), so that picker has nothing left to
/// pick between and was removed rather than kept around disabled.
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
