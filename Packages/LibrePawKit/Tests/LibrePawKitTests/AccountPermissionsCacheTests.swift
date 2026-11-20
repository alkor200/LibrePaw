import Foundation
import Testing
@testable import LibrePawKit

@Suite("AccountPermissionsCache")
struct AccountPermissionsCacheTests {
    private let permissions = AccountPermissions(isAdministrator: false, canManageHomes: true, canManageDevice: true, canViewExcursions: true)

    @Test("Loads once, every later and concurrent caller gets the remembered value")
    func loadsOnce() async throws {
        let cache = AccountPermissionsCache()
        let loads = LoadCounter()
        let permissions = permissions

        try await withThrowingTaskGroup(of: AccountPermissions.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try await cache.value {
                        await loads.increment()
                        try await Task.sleep(for: .milliseconds(20))
                        return permissions
                    }
                }
            }
            for try await value in group { #expect(value == permissions) }
        }
        _ = try await cache.value { await loads.increment(); return permissions }

        #expect(await loads.count == 1)
    }

    @Test("A failed load isn't remembered, the next caller tries again")
    func failureIsRetried() async throws {
        let cache = AccountPermissionsCache()

        await #expect(throws: LibrePawError.self) {
            try await cache.value { throw LibrePawError.network("offline") }
        }
        let value = try await cache.value { self.permissions }

        #expect(value == permissions)
    }
}

private actor LoadCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
