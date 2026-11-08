import Foundation

/// What the signed-in Traccar account can actually do, derived straight
/// from Traccar's own `administrator`/`readonly`/`deviceReadonly`/
/// `disableReports` flags on the user (see ADR-0023). Scentrail shows
/// exactly what this says is possible and nothing it says isn't, there's no
/// separate app-level restriction layered on top.
public struct AccountPermissions: Sendable, Equatable {
    public let isAdministrator: Bool
    /// Add, edit, or delete a home geofence. `false` only when the account
    /// is `readonly` (an admin always can).
    public let canManageHomes: Bool
    /// Edit a device, including uploading a pet's photo. `false` when the
    /// account is `readonly` or `deviceReadonly` (an admin always can).
    public let canManageDevicePhoto: Bool
    /// View excursions and the trail, both built from
    /// `GET /api/reports/events`. `false` only when the account has
    /// `disableReports` set (an admin always can).
    public let canViewExcursions: Bool

    public init(isAdministrator: Bool, canManageHomes: Bool, canManageDevicePhoto: Bool, canViewExcursions: Bool) {
        self.isAdministrator = isAdministrator
        self.canManageHomes = canManageHomes
        self.canManageDevicePhoto = canManageDevicePhoto
        self.canViewExcursions = canViewExcursions
    }
}
