import LibrePawKit

extension Excursion {
    /// "Home → Cabin" when the excursion started and ended at two
    /// different known homes (see ADR-0016), `nil` for an ordinary round
    /// trip or when either home isn't known (anymore).
    ///
    /// Compares home ids, not names: two homes can share a name, and a
    /// trip between them is still a trip between two places.
    func routeText(homeName: (Int) -> String?) -> String? {
        guard let startID = startHomeID, let endID = endHomeID, startID != endID,
              let start = homeName(startID), let end = homeName(endID) else { return nil }
        return "\(start) → \(end)"
    }
}
