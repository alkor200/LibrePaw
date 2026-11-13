import Foundation
import Testing
import LibrePawKit
@testable import LibrePaw

// Serialized because the language override is process-wide state.
@Suite("Formatting", .serialized)
struct FormattingTests {
    @Test("Distances use the app language's decimal separator")
    func distanceFollowsAppLanguage() {
        LocalizationBundle.setLanguageOverride("de")
        defer { LocalizationBundle.setLanguageOverride(nil) }
        #expect(Formatting.distance(1_240) == "1,2 km")
        #expect(Formatting.distance(850) == "850 m")

        LocalizationBundle.setLanguageOverride("en")
        #expect(Formatting.distance(1_240) == "1.2 km")
    }

    @Test("Durations pick minutes, hours or days")
    func durationRanges() {
        LocalizationBundle.setLanguageOverride("en")
        defer { LocalizationBundle.setLanguageOverride(nil) }
        #expect(Formatting.duration(42 * 60) == "42 min")
        #expect(Formatting.duration(3 * 3_600 + 5 * 60) == "3h 5m")
        #expect(Formatting.duration(26 * 3_600) == "1d 2h")
    }

    @Test("Errors are shown in the app language, not LibrePawKit's English fallback")
    func errorMessagesFollowAppLanguage() {
        LocalizationBundle.setLanguageOverride("de")
        defer { LocalizationBundle.setLanguageOverride(nil) }
        #expect(LibrePawError.invalidCredentials.userFacingMessage == "E-Mail oder Passwort ist falsch.")
        #expect(LibrePawError.server(statusCode: 502).userFacingMessage == "Der Server hat mit einem unerwarteten Status geantwortet (502).")
    }
}
