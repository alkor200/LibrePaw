import Foundation
import Testing
@testable import ScentrailKit

@Suite("TraccarPetRepository.concurrentMap")
struct ConcurrentMapTests {
    @Test("Results preserve input order regardless of completion order")
    func preservesOrder() async throws {
        // Earlier elements deliberately take longer, so without index-based
        // reassembly the results would come back out of order.
        let delaysMs: [UInt64] = [30, 20, 10, 5, 1]

        let results = try await TraccarPetRepository.concurrentMap(Array(delaysMs.enumerated()), maxConcurrent: 5) { index, delay in
            try await Task.sleep(nanoseconds: delay * 1_000_000)
            return index
        }

        #expect(results == [0, 1, 2, 3, 4])
    }

    @Test("Never runs more than maxConcurrent transforms at once")
    func respectsConcurrencyLimit() async throws {
        let inFlight = Counter()
        let maxObserved = Counter()

        _ = try await TraccarPetRepository.concurrentMap(Array(0..<50), maxConcurrent: 5) { _ in
            let current = await inFlight.increment()
            await maxObserved.recordMax(current)
            try await Task.sleep(nanoseconds: 1_000_000)
            await inFlight.decrement()
            return 0
        }

        let observed = await maxObserved.value
        #expect(observed <= 5)
        #expect(observed > 0)
    }

    @Test("Propagates an error from any single transform")
    func propagatesErrors() async throws {
        struct TestError: Error {}

        await #expect(throws: TestError.self) {
            _ = try await TraccarPetRepository.concurrentMap(Array(0..<10), maxConcurrent: 3) { value in
                if value == 7 { throw TestError() }
                return value
            }
        }
    }

    @Test("Empty input returns empty output without scheduling anything")
    func handlesEmptyInput() async throws {
        let results: [Int] = try await TraccarPetRepository.concurrentMap([Int](), maxConcurrent: 5) { $0 }
        #expect(results.isEmpty)
    }
}

private actor Counter {
    private var current = 0
    private var max = 0

    func increment() -> Int {
        current += 1
        return current
    }

    func decrement() {
        current -= 1
    }

    func recordMax(_ value: Int) {
        max = Swift.max(max, value)
    }

    var value: Int { max }
}
