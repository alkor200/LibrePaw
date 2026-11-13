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
        let liveFrom = now.addingTimeInterval(-20_000)
        let fresh = [
            excursion(id: 2, startTime: now.addingTimeInterval(-1_000), endTime: nil), // still ongoing
            excursion(id: 1, startTime: now.addingTimeInterval(-10_000), endTime: now.addingTimeInterval(-9_000))
        ]

        let (all, newCache) = TraccarPetRepository.mergeExcursions(cached: nil, freshExcursions: fresh, liveFrom: liveFrom)

        #expect(Set(all.map(\.id)) == [1, 2])
        #expect(newCache.excursions.map(\.id) == [1])
        #expect(newCache.cachedThroughEndTime == fresh[1].endTime)
        #expect(newCache.coveredFrom == liveFrom)
    }

    @Test("A later run adds a newly-closed excursion alongside what was already cached")
    func laterRunAddsNewlyClosedExcursion() {
        let now = Date.now
        let coveredFrom = now.addingTimeInterval(-20_000)
        let watermark = now.addingTimeInterval(-9_000)
        let cached = CachedExcursions(
            excursions: [excursion(id: 1, startTime: now.addingTimeInterval(-10_000), endTime: watermark)],
            coveredFrom: coveredFrom,
            cachedThroughEndTime: watermark
        )
        let fresh = [excursion(id: 2, startTime: now.addingTimeInterval(-500), endTime: now.addingTimeInterval(-100))]

        let (all, newCache) = TraccarPetRepository.mergeExcursions(cached: cached, freshExcursions: fresh, liveFrom: watermark)

        #expect(Set(all.map(\.id)) == [1, 2])
        #expect(Set(newCache.excursions.map(\.id)) == [1, 2])
        #expect(newCache.cachedThroughEndTime == fresh[0].endTime)
        #expect(newCache.coveredFrom == coveredFrom) // unchanged, still the earliest known point
    }

    @Test("Re-fetching an already-cached excursion overwrites rather than duplicating it")
    func refetchedExcursionDoesNotDuplicate() {
        let now = Date.now
        let endTime = now.addingTimeInterval(-9_000)
        let coveredFrom = now.addingTimeInterval(-20_000)
        let cached = CachedExcursions(
            excursions: [excursion(id: 1, startTime: now.addingTimeInterval(-10_000), endTime: endTime, distanceMeters: 100)],
            coveredFrom: coveredFrom,
            cachedThroughEndTime: endTime
        )
        // Same excursion, re-fetched because its exit event still fell
        // inside the query window, with a (hypothetically) corrected value.
        let fresh = [excursion(id: 1, startTime: now.addingTimeInterval(-10_000), endTime: endTime, distanceMeters: 150)]

        let (all, newCache) = TraccarPetRepository.mergeExcursions(cached: cached, freshExcursions: fresh, liveFrom: endTime)

        #expect(all.count == 1)
        #expect(all.first?.distanceMeters == 150)
        #expect(newCache.excursions.count == 1)
        #expect(newCache.excursions.first?.distanceMeters == 150)
    }

    @Test("An ongoing excursion is returned but never cached, and never advances the watermark")
    func ongoingExcursionIsNeverCached() {
        let now = Date.now
        let liveFrom = now.addingTimeInterval(-600)
        let cached = CachedExcursions(excursions: [], coveredFrom: nil, cachedThroughEndTime: nil)
        let fresh = [excursion(id: 1, startTime: liveFrom, endTime: nil)]

        let (all, newCache) = TraccarPetRepository.mergeExcursions(cached: cached, freshExcursions: fresh, liveFrom: liveFrom)

        #expect(all.map(\.id) == [1])
        #expect(newCache.excursions.isEmpty)
        #expect(newCache.cachedThroughEndTime == nil)
    }

    @Test("No fresh excursions leaves the cache and its watermark untouched")
    func noFreshExcursionsLeavesCacheUnchanged() {
        let now = Date.now
        let coveredFrom = now.addingTimeInterval(-20_000)
        let watermark = now.addingTimeInterval(-9_000)
        let cached = CachedExcursions(
            excursions: [excursion(id: 1, startTime: now.addingTimeInterval(-10_000), endTime: watermark)],
            coveredFrom: coveredFrom,
            cachedThroughEndTime: watermark
        )

        // liveFetchStart would return `to` itself here (nothing left to
        // fetch), mergeExcursions doesn't need to know that, just that
        // liveFrom is already >= the cache's own prior coverage.
        let (all, newCache) = TraccarPetRepository.mergeExcursions(cached: cached, freshExcursions: [], liveFrom: watermark)

        #expect(all.map(\.id) == [1])
        #expect(newCache == cached)
    }

    @Test("A live fetch starting after the watermark restarts coverage there instead of claiming the gap")
    func liveFetchAfterWatermarkRestartsCoverage() {
        let now = Date.now
        let coveredFrom = now.addingTimeInterval(-30 * 86_400)
        let watermark = now.addingTimeInterval(-4 * 86_400)
        let cached = CachedExcursions(
            excursions: [excursion(id: 1, startTime: watermark.addingTimeInterval(-3_600), endTime: watermark)],
            coveredFrom: coveredFrom,
            cachedThroughEndTime: watermark
        )
        // E.g. a 24-hour Trail window opened four days after the cache was
        // last updated: liveFetchStart returns `from` itself, so the three
        // days between the watermark and `liveFrom` were never fetched.
        let liveFrom = now.addingTimeInterval(-86_400)
        let fresh = [excursion(id: 2, startTime: now.addingTimeInterval(-7_200), endTime: now.addingTimeInterval(-3_600))]

        let (_, newCache) = TraccarPetRepository.mergeExcursions(cached: cached, freshExcursions: fresh, liveFrom: liveFrom)

        #expect(newCache.coveredFrom == liveFrom)
        #expect(newCache.cachedThroughEndTime == fresh[0].endTime)
        // And so a later, wider request re-fetches the gap instead of
        // trusting the advanced watermark.
        #expect(TraccarPetRepository.liveFetchStart(cached: newCache, from: coveredFrom) == coveredFrom)
    }

    @Test("A live fetch starting before the cache's own coverage extends coverage back to it")
    func liveFetchBeforeCoverageExtendsIt() {
        let now = Date.now
        let coveredFrom = now.addingTimeInterval(-86_400)
        let watermark = now.addingTimeInterval(-3_600)
        let cached = CachedExcursions(excursions: [], coveredFrom: coveredFrom, cachedThroughEndTime: watermark)
        let liveFrom = now.addingTimeInterval(-7 * 86_400)

        let (_, newCache) = TraccarPetRepository.mergeExcursions(cached: cached, freshExcursions: [], liveFrom: liveFrom)

        #expect(newCache.coveredFrom == liveFrom)
    }
}

@Suite("TraccarPetRepository.liveFetchStart")
struct LiveFetchStartTests {
    @Test("No cache at all means fetch the whole requested range")
    func noCacheFetchesWholeRange() {
        let from = Date.now.addingTimeInterval(-100_000)
        #expect(TraccarPetRepository.liveFetchStart(cached: nil, from: from) == from)
    }

    @Test("Cache coverage reaching back to (or before) `from` narrows to the watermark")
    func coverageReachingBackNarrowsToWatermark() {
        let now = Date.now
        let from = now.addingTimeInterval(-10_000)
        let watermark = now.addingTimeInterval(-5_000)
        let cached = CachedExcursions(excursions: [], coveredFrom: now.addingTimeInterval(-20_000), cachedThroughEndTime: watermark)

        #expect(TraccarPetRepository.liveFetchStart(cached: cached, from: from) == watermark)
    }

    @Test(
        "A gap between the true start of history and the cache's own coverage always forces a full re-fetch, confirmed live regression"
    )
    func gapBeforeCoverageForcesFullRefetch() {
        let now = Date.now
        // Reproduces the exact bug: `loadTodaysExcursions()` is the first
        // call to ever populate the cache, with a narrow `from: startOfDay`
        // range, long after some much older excursion already happened.
        let startOfToday = Calendar.current.startOfDay(for: now)
        let cached = CachedExcursions(excursions: [], coveredFrom: startOfToday, cachedThroughEndTime: startOfToday)

        // A later, much wider request (e.g. ExcursionsView's own window)
        // must not trust the watermark here, there's a real gap between
        // `sevenDaysAgo` and `coveredFrom` this cache never actually saw.
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        #expect(TraccarPetRepository.liveFetchStart(cached: cached, from: sevenDaysAgo) == sevenDaysAgo)
    }

    @Test("Requesting exactly the cache's own coverage start narrows to the watermark, not a gap")
    func requestingExactCoverageStartNarrows() {
        let now = Date.now
        let coveredFrom = now.addingTimeInterval(-20_000)
        let watermark = now.addingTimeInterval(-5_000)
        let cached = CachedExcursions(excursions: [], coveredFrom: coveredFrom, cachedThroughEndTime: watermark)

        #expect(TraccarPetRepository.liveFetchStart(cached: cached, from: coveredFrom) == watermark)
    }
}

@Suite("TraccarPetRepository.isDegenerate")
struct IsDegenerateExcursionTests {
    private func excursion(startTime: Date, endTime: Date?) -> Excursion {
        Excursion(id: 1, startTime: startTime, endTime: endTime, startCoordinate: nil, endCoordinate: nil, distanceMeters: nil)
    }

    @Test("An excursion still ongoing is never degenerate, there's nothing to judge yet")
    func ongoingExcursionIsNeverDegenerate() {
        let excursion = excursion(startTime: .now, endTime: nil)
        #expect(!TraccarPetRepository.isDegenerate(excursion))
    }

    @Test(
        "An exit immediately followed by an enter is degenerate, confirmed live: a \"0 min\" excursion with no route at all"
    )
    func nearInstantExitThenEnterIsDegenerate() {
        let now = Date.now
        let excursion = excursion(startTime: now, endTime: now.addingTimeInterval(5))
        #expect(TraccarPetRepository.isDegenerate(excursion))
    }

    @Test("Exactly the minimum duration is not degenerate, only strictly shorter is")
    func exactlyMinimumDurationIsNotDegenerate() {
        let now = Date.now
        let excursion = excursion(startTime: now, endTime: now.addingTimeInterval(TraccarPetRepository.minimumExcursionDuration))
        #expect(!TraccarPetRepository.isDegenerate(excursion))
    }

    @Test("An ordinary excursion well above the minimum duration is not degenerate")
    func ordinaryExcursionIsNotDegenerate() {
        let now = Date.now
        let excursion = excursion(startTime: now, endTime: now.addingTimeInterval(30 * 60))
        #expect(!TraccarPetRepository.isDegenerate(excursion))
    }
}
