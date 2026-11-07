import MapKit

extension MKCoordinateRegion {
    /// A region that bounds all the given coordinates, with padding so the
    /// content doesn't touch the map's edges, and a minimum span so a
    /// single point (or a tiny cluster) still shows its neighborhood rather
    /// than zooming in uselessly tight.
    static func fitting(
        _ coordinates: [CLLocationCoordinate2D],
        paddingFactor: Double = 1.6,
        minimumSpan: Double = 0.01
    ) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (latitudes.min()! + latitudes.max()!) / 2,
            longitude: (longitudes.min()! + longitudes.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((latitudes.max()! - latitudes.min()!) * paddingFactor, minimumSpan),
            longitudeDelta: max((longitudes.max()! - longitudes.min()!) * paddingFactor, minimumSpan)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
