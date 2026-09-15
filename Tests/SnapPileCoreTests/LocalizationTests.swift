import Foundation
import XCTest

@testable import SnapPileCore

final class LocalizationTests: XCTestCase {
    /// English values equal their keys, so a lookup is only proven by a value that is not the key.
    private let missing = "\u{0}missing"

    func testEnglishCatalogResolvesKeysAndPluralForms() throws {
        let bundle = try XCTUnwrap(L10n.resourceBundleForTesting)
        XCTAssertEqual(bundle.localizedString(forKey: "Save Screenshot", value: missing, table: nil), "Save Screenshot")
        XCTAssertEqual(L10n.format("%ld images", 1), "1 image")
        XCTAssertEqual(L10n.format("%ld images", 3), "3 images")
        XCTAssertEqual(L10n.format("SnapPile, %ld screenshots", 1), "SnapPile, 1 screenshot")
        XCTAssertEqual(L10n.format("After %ld minutes", 5), "After 5 minutes")
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

    func testKeysUsedInSourcesMatchTheCatalog() throws {
        let bundle = try XCTUnwrap(L10n.resourceBundleForTesting)
        var catalog = Set<String>()
        for fileExtension in ["strings", "stringsdict"] {
            let url = try XCTUnwrap(
                bundle.url(forResource: "Localizable", withExtension: fileExtension, subdirectory: "en.lproj"))
            catalog.formUnion(try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: Any]).keys)
        }

        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let call = try NSRegularExpression(pattern: #"L10n\.(?:text|format)\(\s*"((?:[^"\\]|\\.)*)""#)
        let anyCall = try NSRegularExpression(pattern: #"L10n\.(?:text|format)\("#)
        var used = Set<String>()
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let file as URL in files where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            let matches = call.matches(in: source, range: range)
            // Keys passed as variables cannot be checked here.
            XCTAssertEqual(
                matches.count, anyCall.numberOfMatches(in: source, range: range),
                "\(file.lastPathComponent) uses a non-literal L10n key")
            for match in matches {
                used.insert(unescape(String(source[Range(match.range(at: 1), in: source)!])))
            }
        }

        XCTAssertFalse(used.isEmpty)
        XCTAssertEqual(used.subtracting(catalog).sorted(), [], "Keys missing from the catalog")
        XCTAssertEqual(catalog.subtracting(used).sorted(), [], "Catalog keys no longer used")
    }

    private func unescape(_ literal: String) -> String {
        var result = ""
        var escaped = false
        for character in literal {
            if escaped {
                result.append(character == "n" ? "\n" : character == "t" ? "\t" : character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }
}
