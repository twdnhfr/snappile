import Foundation
import XCTest

@testable import SnapPileCore

final class LocalizationTests: XCTestCase {
    func testEnglishResourceIsAvailable() {
        let bundle = try! XCTUnwrap(L10n.resourceBundleForTesting)
        XCTAssertNotNil(bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: "en.lproj"))
        XCTAssertEqual(L10n.text("Save Screenshot"), "Save Screenshot")
    }

    func testUnsupportedLocaleFallsBackToEnglishKey() {
        let bundle = try! XCTUnwrap(L10n.resourceBundleForTesting)
        XCTAssertEqual(Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: ["fr-FR"]), ["en"])
    }

    func testFormattingAndLocalizedErrorsUseEnglishText() {
        XCTAssertEqual(
            L10n.format("Screenshot %@", "Screenshot_2026-09-11.png"), "Screenshot Screenshot_2026-09-11.png")
        XCTAssertEqual(
            ScreenshotStoreError.invalidPNG.errorDescription,
            "The file is not a valid PNG image.")
        XCTAssertEqual(
            HotKeyError.registrationFailed(-50).errorDescription,
            "The keyboard shortcut could not be registered (OSStatus -50).")
    }
}
