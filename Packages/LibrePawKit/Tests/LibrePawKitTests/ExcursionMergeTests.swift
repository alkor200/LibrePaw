import Foundation
import Testing
@testable import LibrePawKit

@Suite("TraccarPetRepository.mergeExcursions")
struct ExcursionMergeTests {
    private func excursion(id: Int, startTime: Date, endTime: Date?, distanceMeters: Double? = nil) -> Excursion {
        Excursion(
            id: id,
            startTime: startTime,
            endTime: endTime,
            startCoordinate: nil,
            endCoordinate: nil,
            distanceMeters: distanceMeters
        )
    }

    @Test("First-ever run folds every closed excursion into the cache, not the ongoing one")
    func firstRunCachesOnlyClosedExcursions() {
        let now = Date.now
        let fresh = [
            excursion(id: 2, startTime: now.addingTimeInterval(-1_000), endTime: nil), // still ongoing
            excursion(id: 1, startTime: now.addingTimeInterval(-10_000), endTime: now.addingTimeInterval(-9_000))
        ]

        let (all, newCache) = TraccarPetRepository.mergeExcursions(cached: nil, freshExcursions: fresh)

        #expect(Set(all.map(\.id)) == [1, 2])
        #expect(newCache.excursions.map(\.id) == [1])
        #expect(newCache.cachedThroughEndTime == fresh[1].endTime)
    }

    @Test("A later run adds a newly-closed excursion alongside what was already cached")
    func laterRunAddsNewlyClosedExcursion() {
        let now = Date.now
        let watermark = now.addingTimeInterval(-9_000)
        let cached = CachedExcursions(
            excursions: [excursion(id: 1, startTime: now.addingTimeInterval(-10_000), endTime: watermark)],
            cachedThroughEndTime: watermark
        )
        let fresh = [excursion(id: 2, startTime: now.addingTimeInterval(-500), endTime: now.addingTimeInterval(-100))]

        let (all, newCache) = TraccarPetRepository.mergeExcursions(cached: cached, freshExcursions: fresh)

        #expect(Set(all.map(\.id)) == [1, 2])
        #expect(Set(newCache.excursions.map(\.id)) == [1, 2])
        #expect(newCache.cachedThroughEndTime == fresh[0].endTime)
    }

    @Test("Re-fetching an already-cached excursion overwrites rather than duplicating it")
    func refetchedExcursionDoesNotDuplicate() {
        let now = Date.now
        let endTime = now.addingTimeInterval(-9_000)
        let cached = CachedExcursions(
            excursions: [excursion(id: 1, startTime: now.addingTimeInterval(-10_000), endTime: endTime, distanceMeters: 100)],
            cachedThroughEndTime: endTime
        )
        // Same excursion, re-fetched because its exit event still fell
        // inside the query window, with a (hypothetically) corrected value.
        let fresh = [excursion(id: 1, startTime: now.addingTimeInterval(-10_000), endTime: endTime, distanceMeters: 150)]

        let (all, newCache) = TraccarPetRepository.mergeExcursions(cached: cached, freshExcursions: fresh)

        #expect(all.count == 1)
        #expect(all.first?.distanceMeters == 150)
        #expect(newCache.excursions.count == 1)
        #expect(newCache.excursions.first?.distanceMeters == 150)
    }

    @Test("An ongoing excursion is returned but never cached, and never advances the watermark")
    func ongoingExcursionIsNeverCached() {
        let now = Date.now
        let cached = CachedExcursions(excursions: [], cachedThroughEndTime: nil)
        let fresh = [excursion(id: 1, startTime: now.addingTimeInterval(-600), endTime: nil)]

        let (all, newCache) = TraccarPetRepository.mergeExcursions(cached: cached, freshExcursions: fresh)

        #expect(all.map(\.id) == [1])
        #expect(newCache.excursions.isEmpty)
        #expect(newCache.cachedThroughEndTime == nil)
    }

    @Test("No fresh excursions leaves the cache and its watermark untouched")
    func noFreshExcursionsLeavesCacheUnchanged() {
        let now = Date.now
        let watermark = now.addingTimeInterval(-9_000)
        let cached = CachedExcursions(
            excursions: [excursion(id: 1, startTime: now.addingTimeInterval(-10_000), endTime: watermark)],
            cachedThroughEndTime: watermark
        )

        let (all, newCache) = TraccarPetRepository.mergeExcursions(cached: cached, freshExcursions: [])

        #expect(all.map(\.id) == [1])
        #expect(newCache == cached)
    }
}
