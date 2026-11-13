import Foundation
import Testing
import LibrePawKit
@testable import LibrePaw

@Suite("PetRepository.currentUserPermissionsRetrying")
struct PermissionsRetryTests {
    @Test("A transient failure is retried until it succeeds")
    func retriesTransientFailure() async {
        let repository = FakePetRepository(permissionFailuresBeforeSuccess: 2)
        let permissions = await repository.currentUserPermissionsRetrying(initialDelay: .milliseconds(1))
        #expect(permissions != nil)
    }

    @Test("Gives up after the last attempt")
    func givesUp() async {
        let repository = FakePetRepository(permissionFailuresBeforeSuccess: 10)
        let permissions = await repository.currentUserPermissionsRetrying(attempts: 3, initialDelay: .milliseconds(1))
        #expect(permissions == nil)
    }
}
