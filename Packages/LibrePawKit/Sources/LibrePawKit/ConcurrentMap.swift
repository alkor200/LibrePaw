import Foundation

/// Like `elements.map(transform)`, but running at most `maxConcurrent`
/// transforms at once instead of either one at a time or all of them at
/// once. Order of `results` matches `elements`.
///
/// Public so the app can bound its own fan-outs the same way (e.g.
/// `TrailViewModel` fetching one route per excursion).
public func concurrentMap<Element: Sendable, Result: Sendable>(
    _ elements: [Element],
    maxConcurrent: Int,
    transform: @escaping @Sendable (Element) async throws -> Result
) async throws -> [Result] {
    guard !elements.isEmpty else { return [] }

    var results = [Result?](repeating: nil, count: elements.count)
    var nextIndex = 0

    try await withThrowingTaskGroup(of: (Int, Result).self) { group in
        func scheduleNext() {
            guard nextIndex < elements.count else { return }
            let index = nextIndex
            let element = elements[index]
            nextIndex += 1
            group.addTask { (index, try await transform(element)) }
        }

        for _ in 0..<min(maxConcurrent, elements.count) {
            scheduleNext()
        }
        while let (index, result) = try await group.next() {
            results[index] = result
            scheduleNext()
        }
    }

    return results.map { $0! }
}
