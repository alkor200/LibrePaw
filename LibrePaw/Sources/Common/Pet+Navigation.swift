import MapKit
import LibrePawKit

extension Pet {
    /// Opens Apple Maps with directions to this pet's last known position,
    /// letting the user pick walking/driving/transit there themselves. A
    /// `nil` here (no position yet) is a caller bug: every call site only
    /// offers this action once `lastPosition` is known to be set.
    func openDirectionsInMaps() {
        guard let coordinate = lastPosition?.coordinate.clLocationCoordinate2D else { return }
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}
