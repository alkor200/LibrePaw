import CoreLocation
import ScentrailKit

/// `ScentrailKit`'s `Coordinate` deliberately avoids importing CoreLocation
/// so the domain layer has no mapping-framework dependency (see ADR-0005).
/// This bridges it to `CLLocationCoordinate2D` for MapKit-based views.
extension Coordinate {
    var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
