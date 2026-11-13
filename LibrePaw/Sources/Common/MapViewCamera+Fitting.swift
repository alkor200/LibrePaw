import CoreLocation
import MapLibre
import MapLibreSwiftUI
import UIKit

extension MapViewCamera {
    /// A camera showing all of `coordinates`, `nil` when there are none.
    ///
    /// A single coordinate is centered on directly instead: it's a
    /// zero-size bounding box, a degenerate case for `.showcase()`'s
    /// fit-bounds math (confirmed live: with only one pet, the map got
    /// stuck requesting tiles forever and never rendered anything past
    /// the initial background color).
    static func fitting(_ coordinates: [CLLocationCoordinate2D], edgePadding: UIEdgeInsets) -> MapViewCamera? {
        guard let first = coordinates.first else { return nil }
        guard coordinates.count > 1 else {
            return .center(first, zoom: 16)
        }
        let shapeCollection = MLNShapeCollection(shapes: [MLNPointCollectionFeature(coordinates: coordinates, count: UInt(coordinates.count))])
        return .showcase(shapeCollection: shapeCollection, edgePadding: edgePadding)
    }
}
