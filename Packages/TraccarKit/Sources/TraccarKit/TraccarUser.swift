import Foundation

/// A user as returned by `/api/users`, only the fields Scentrail needs to
/// identify "the currently authenticated user" and what Traccar itself
/// lets that account do (see ADR-0017, ADR-0018, ADR-0023).
public struct TraccarUser: Decodable, Sendable, Equatable {
    public let id: Int
    public let email: String
    public let administrator: Bool
    /// Blocks every write (devices, geofences, everything), confirmed
    /// against a live server: `administrator` bypasses it, anyone else with
    /// this set gets `SecurityException: Write access denied` from every
    /// `POST`/`PUT`/`DELETE` (see ADR-0023).
    public let readonly: Bool
    /// Blocks writes to devices specifically (editing one, uploading its
    /// photo), independent of ``readonly``, geofences are unaffected
    /// (confirmed against a live server, see ADR-0023).
    public let deviceReadonly: Bool
    /// Blocks `GET /api/reports/events`, which excursions and the trail are
    /// built from (confirmed against a live server, see ADR-0023).
    public let disableReports: Bool

    public init(id: Int, email: String, administrator: Bool, readonly: Bool = false, deviceReadonly: Bool = false, disableReports: Bool = false) {
        self.id = id
        self.email = email
        self.administrator = administrator
        self.readonly = readonly
        self.deviceReadonly = deviceReadonly
        self.disableReports = disableReports
    }
}
