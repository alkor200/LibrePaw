import Foundation
import ScentrailKit

/// Adds a new home, or edits one already in `existingHome`, the same
/// screen either way (see ``SetHomeView``), distinguished only by whether a
/// home was passed in from ``HomesView`` (see ADR-0016).
@Observable
@MainActor
final class SetHomeViewModel {
    let pet: Pet
    let locationService: LocationService
    let isEditingExistingHome: Bool

    var name: String
    /// The pin's current position, editable by dragging the map underneath
    /// it. Starts at the existing home's center when editing, otherwise at
    /// the owner's current location once that becomes available.
    var homeCoordinate: Coordinate?
    var radiusMeters: Double
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var didSave = false
    private(set) var isShowingDeleteConfirmation = false
    private(set) var isDeleting = false
    private(set) var didDelete = false
    /// `nil` until ``loadPermissionContext()`` resolves, see
    /// `HomesViewModel`'s equivalent; `SetHomeView` only shows its
    /// visibility notice (and decides whether editing is allowed at all)
    /// once this is known (see ADR-0019, ADR-0021).
    private(set) var isAdministrator: Bool?
    private(set) var currentUserID: Int?

    private let existingHomeID: Int?
    private let existingHomeOwnerID: Int?
    private let petRepository: PetRepository

    init(pet: Pet, existingHome: HomeGeofence?, petRepository: PetRepository, locationService: LocationService) {
        self.pet = pet
        self.isEditingExistingHome = existingHome != nil
        self.existingHomeID = existingHome?.id
        self.existingHomeOwnerID = existingHome?.ownerUserID
        self.name = existingHome?.name ?? localized("Home")
        self.homeCoordinate = existingHome?.center
        self.radiusMeters = existingHome?.radiusMeters ?? 50
        self.petRepository = petRepository
        self.locationService = locationService
    }

    /// Whether the signed-in account is allowed to change anything here at
    /// all: always true when adding a new home (the creator always manages
    /// their own), for an existing one only an admin or whoever created it
    /// can (see `HomesViewModel.canManage(_:)` and ADR-0021, including why
    /// an untracked legacy owner defaults to "no"). `nil`, same as
    /// ``isAdministrator``, until the permission context has loaded.
    var canManage: Bool? {
        guard isEditingExistingHome else { return true }
        guard let isAdministrator else { return nil }
        if isAdministrator { return true }
        guard let currentUserID, let existingHomeOwnerID else { return false }
        return existingHomeOwnerID == currentUserID
    }

    /// Defaults the pin to the owner's current location, but only before
    /// there's anything else to show it at, never overrides an existing
    /// home or a position the owner already dragged the pin to.
    func useCurrentLocationIfUnset() {
        guard homeCoordinate == nil, let coordinate = locationService.coordinate else { return }
        homeCoordinate = coordinate
    }

    /// Best-effort, same reasoning as `HomesViewModel`'s equivalent: this
    /// just gates the visibility notice and (via ``canManage``) whether
    /// editing is allowed, not something worth surfacing an error for.
    func loadPermissionContext() async {
        async let administrator = petRepository.isCurrentUserAdministrator()
        async let userID = petRepository.currentUserID()
        isAdministrator = try? await administrator
        currentUserID = try? await userID
    }

    func save() async {
        guard canManage == true else {
            errorMessage = localized("Only an admin can edit a home you didn't create.")
            return
        }
        guard let coordinate = homeCoordinate else {
            errorMessage = localized("Drag the map to choose a location first.")
            return
        }
        let trimmedName = name.trimmed
        guard !trimmedName.isEmpty else {
            errorMessage = localized("Give this home a name.")
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if let existingHomeID {
                try await petRepository.updateHomeGeofence(existingHomeID, forPetID: pet.id, name: trimmedName, center: coordinate, radiusMeters: radiusMeters)
            } else {
                try await petRepository.addHomeGeofence(forPetID: pet.id, name: trimmedName, center: coordinate, radiusMeters: radiusMeters)
            }
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestDelete() {
        isShowingDeleteConfirmation = true
    }

    func cancelDelete() {
        isShowingDeleteConfirmation = false
    }

    /// Only reachable when editing (the toolbar button that calls this is
    /// hidden while adding, or while `canManage` isn't `true`), so
    /// `existingHomeID` is always set here.
    func confirmDelete() async {
        guard let existingHomeID, canManage == true else { return }
        isShowingDeleteConfirmation = false
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await petRepository.deleteHomeGeofence(existingHomeID)
            didDelete = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
