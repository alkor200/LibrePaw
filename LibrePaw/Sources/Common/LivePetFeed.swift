import Foundation
import LibrePawKit

/// Runs ``PetRepository/livePetUpdates()`` for as long as the calling task
/// isn't cancelled, shared by every screen that follows the live feed
/// (ADR-0013).
///
/// The stream reconnects on its own after a drop *once it's running*, but
/// it finishes with an error if its very first snapshot can't be fetched
/// (e.g. launching while offline). Each screen used to just stop there, a
/// map showing an error capsule forever, or a pet list frozen on a REST
/// snapshot, even after the network came back. This restarts the stream
/// after `retryDelay` instead, except for `invalidCredentials`, which ends
/// the whole session anyway (see `SessionExpiryDetectingPetRepository`).
///
/// `onUpdate` returns whether to keep going, so a caller holding itself
/// weakly can stop the feed once it's gone, rather than keeping the
/// connection alive for nobody.
enum LivePetFeed {
    @MainActor
    static func run(
        _ petRepository: PetRepository,
        retryDelay: Duration = .seconds(5),
        onUpdate: ([Pet]) -> Bool,
        onError: (Error) -> Void = { _ in }
    ) async {
        while !Task.isCancelled {
            do {
                for try await pets in petRepository.livePetUpdates() {
                    guard onUpdate(pets) else { return }
                }
                // Only a cancelled (or, in previews, a finite) stream ends
                // without an error, either way there's nothing to restart.
                return
            } catch {
                guard !Task.isCancelled else { return }
                onError(error)
                if case LibrePawError.invalidCredentials = error { return }
                try? await Task.sleep(for: retryDelay)
            }
        }
    }
}
