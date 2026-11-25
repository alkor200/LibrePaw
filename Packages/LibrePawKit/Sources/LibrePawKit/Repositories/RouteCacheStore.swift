import Foundation

/// Keeps the position history of time ranges that are over, so the Trail
/// screen doesn't fetch every excursion's route from the server again on
/// each visit: one `/api/positions` request per excursion, up to 20 at a
/// time, which over a 30-day window took a good while (see
/// `TraccarPetRepository.fetchTrail`).
protocol RouteCacheStore: Sendable {
    func load(forPetID petID: Int, serverHost: String, from: Date, to: Date) -> [PetPosition]?
    func save(_ positions: [PetPosition], forPetID petID: Int, serverHost: String, from: Date, to: Date)
    /// Every route cached for this pet.
    func clear(forPetID petID: Int, serverHost: String)
}

/// One JSON file per route in the Caches directory, not `UserDefaults`
/// like the excursions cache: a single route can hold hundreds of
/// positions, and the system may purge Caches under storage pressure,
/// which only costs a refetch.
struct FileRouteCacheStore: RouteCacheStore {
    /// Shared with ``LocalCaches``, which removes it on logout and login.
    static let defaultDirectory: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("org.librepaw.routes", isDirectory: true)

    let directory: URL

    init(directory: URL = Self.defaultDirectory) {
        self.directory = directory
    }

    func load(forPetID petID: Int, serverHost: String, from: Date, to: Date) -> [PetPosition]? {
        guard let data = try? Data(contentsOf: fileURL(forPetID: petID, serverHost: serverHost, from: from, to: to)) else { return nil }
        return try? JSONDecoder().decode([PetPosition].self, from: data)
    }

    func save(_ positions: [PetPosition], forPetID petID: Int, serverHost: String, from: Date, to: Date) {
        let url = fileURL(forPetID: petID, serverHost: serverHost, from: from, to: to)
        guard let data = try? JSONEncoder().encode(positions) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func clear(forPetID petID: Int, serverHost: String) {
        try? FileManager.default.removeItem(at: petDirectory(forPetID: petID, serverHost: serverHost))
    }

    private func petDirectory(forPetID petID: Int, serverHost: String) -> URL {
        directory
            .appendingPathComponent(serverHost, isDirectory: true)
            .appendingPathComponent(String(petID), isDirectory: true)
    }

    /// Millisecond timestamps, the precision Traccar's event and position
    /// times come with, so the same excursion always maps to the same file.
    private func fileURL(forPetID petID: Int, serverHost: String, from: Date, to: Date) -> URL {
        let name = "\(Int64(from.timeIntervalSince1970 * 1_000))-\(Int64(to.timeIntervalSince1970 * 1_000)).json"
        return petDirectory(forPetID: petID, serverHost: serverHost).appendingPathComponent(name)
    }
}
