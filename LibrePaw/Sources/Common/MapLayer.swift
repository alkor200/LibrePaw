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
///
/// An opaque surface with a soft shadow and the darker primary green, not a
/// translucent material with the light accent: in light mode that blended
/// into OpenFreeMap's own pale greens and beiges until the button was hard
/// to find at all.
struct MapControlButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.appPrimaryDark)
            .frame(width: 44, height: 44)
            .background(.appSurface, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}

extension View {
    func mapControlButtonStyle() -> some View {
        modifier(MapControlButtonStyle())
    }
}
