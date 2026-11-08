import Foundation
import Testing
@testable import ScentrailKit

@Suite("TraccarPetRepository.mergeLifetimeStats")
struct LifetimeStatsMergeTests {
    private func excursion(id: Int, startTime: Date, endTime: Date?, distanceMeters: Double?) -> Excursion {
        Excursion(
            id: id,
            startTime: startTime,
            endTime: endTime,
            startCoordinate: nil,
            endCoordinate: nil,
            distanceMeters: distanceMeters
        )
    }

    @Test("First-ever run folds in every completed excursion, not just the newest")
    func firstRunCountsAllCompletedExcursions() {
        let now = Date.now
        // fetchExcursions returns most-recent-first, the exact order that
        // broke this before: a newer excursion's end time must not make an
        // older one in the same batch look "already counted".
        let excursions = [
            excursion(id: 3, startTime: now.addingTimeInterval(-1_000), endTime: nil, distanceMeters: nil), // ongoing
            excursion(id: 2, startTime: now.addingTimeInterval(-10_000), endTime: now.addingTimeInterval(-9_000), distanceMeters: 629),
            excursion(id: 1, startTime: now.addingTimeInterval(-20_000), endTime: now.addingTimeInterval(-18_000), distanceMeters: 1_200)
        ]

        let (stats, newCache) = TraccarPetRepository.mergeLifetimeStats(cached: nil, recentExcursions: excursions)

        #expect(stats.totalDistanceMeters == 1_829) // 629 + 1200, ongoing excursion has no distance here
        #expect(newCache.totalDistanceMeters == 1_829)
        #expect(newCache.cachedThroughEndTime == excursions[1].endTime) // the newest *completed* excursion's end time
    }

    @Test("A later run only adds excursions that ended after the cached watermark")
    func laterRunOnlyAddsNewExcursions() {
        let now = Date.now
        let watermark = now.addingTimeInterval(-9_000)
        let cached = CachedLifetimeStats(totalDistanceMeters: 1_829, totalDurationSeconds: 2_000, cachedThroughEndTime: watermark)

        // The server returns the already-counted excursion again (its exit
        // event still falls inside the query window) alongside one genuinely
        // new one, the old one must not be double-counted.
        let excursions = [
            excursion(id: 4, startTime: now.addingTimeInterval(-500), endTime: now.addingTimeInterval(-100), distanceMeters: 300),
            excursion(id: 2, startTime: now.addingTimeInterval(-10_000), endTime: watermark, distanceMeters: 629)
        ]

        let (stats, newCache) = TraccarPetRepository.mergeLifetimeStats(cached: cached, recentExcursions: excursions)

        #expect(stats.totalDistanceMeters == 2_129) // 1829 + 300, the 629 one is not re-added
        #expect(newCache.cachedThroughEndTime == excursions[0].endTime)
    }

    @Test("A likely car/train ride is excluded from totals but still advances the watermark")
    func vehicleTripIsExcludedButStillAdvancesWatermark() {
        let now = Date.now
        let excursions = [
            // 10km in 12 minutes ≈ 50 km/h, unmistakably a car, not a walk.
            excursion(id: 1, startTime: now.addingTimeInterval(-1_200), endTime: now, distanceMeters: 10_000),
            // A genuine walk right before it.
            excursion(id: 2, startTime: now.addingTimeInterval(-10_000), endTime: now.addingTimeInterval(-9_000), distanceMeters: 629)
        ]

        let (stats, newCache) = TraccarPetRepository.mergeLifetimeStats(cached: nil, recentExcursions: excursions)

        #expect(stats.totalDistanceMeters == 629) // the 10km drive is not folded in
        #expect(newCache.cachedThroughEndTime == excursions[0].endTime) // but it's still marked as "seen"
    }

    @Test("An ongoing excursion contributes to the displayed total but is never cached")
    func ongoingExcursionIsDisplayedButNotCached() {
        let now = Date.now
        let excursions = [
            excursion(id: 1, startTime: now.addingTimeInterval(-600), endTime: nil, distanceMeters: 150)
        ]

        let (stats, newCache) = TraccarPetRepository.mergeLifetimeStats(cached: nil, recentExcursions: excursions)

        #expect(stats.totalDistanceMeters == 150)
        #expect(newCache.totalDistanceMeters == 0)
        #expect(newCache.cachedThroughEndTime == nil)
    }
}
