import Foundation
import LibrePawKit

/// Grants another Traccar account access to this pet, by email, admin-only
/// server-side (see ADR-0018).
@Observable
@MainActor
final class SharePetViewModel {
    let pet: Pet
    var email = ""
    private(set) var isSharing = false
    private(set) var errorMessage: String?
    private(set) var didShare = false

    private let petRepository: PetRepository

    init(pet: Pet, petRepository: PetRepository) {
        self.pet = pet
        self.petRepository = petRepository
    }

    func share() async {
        let trimmedEmail = email.trimmed
        guard !trimmedEmail.isEmpty else {
            errorMessage = localized("Enter the email address of the Traccar account to share %@ with.", pet.name)
            return
        }

        isSharing = true
        errorMessage = nil
        defer { isSharing = false }

        do {
            try await petRepository.sharePet(forPetID: pet.id, withEmail: trimmedEmail)
            didShare = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
