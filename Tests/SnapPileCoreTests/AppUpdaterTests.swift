import Foundation
import XCTest

@testable import SnapPileCore

@MainActor
final class AppUpdaterTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "SnapPileUpdaterTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func release(
        tag: String = "v0.3.0", asset: String = "SnapPile-0.3.0.dmg", digest: String? = "sha256:ABC",
        prerelease: Bool = false
    ) -> Data {
        var file: [String: Any] = [
            "name": asset, "browser_download_url": "https://example.com/\(asset)",
        ]
        if let digest { file["digest"] = digest }
        return try! JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "html_url": "https://example.com/release", "draft": false, "prerelease": prerelease,
            "assets": [file],
        ])
    }

    func testVersionComparison() {
        XCTAssertTrue(AppVersion.isNewer("v0.2.1", than: "0.2.0"))
        XCTAssertTrue(AppVersion.isNewer("0.10.0", than: "0.9.9"))
        XCTAssertFalse(AppVersion.isNewer("0.2", than: "0.2.0"))
        XCTAssertFalse(AppVersion.isNewer("0.2.0-beta", than: "0.2.0"))
        XCTAssertFalse(AppVersion.isNewer("0.1.9", than: "0.2.0"))
    }

    func testParsesOnlyInstallableReleases() {
        XCTAssertEqual(
            AvailableUpdate.parse(release()),
            AvailableUpdate(
                version: "0.3.0", pageURL: URL(string: "https://example.com/release")!,
                downloadURL: URL(string: "https://example.com/SnapPile-0.3.0.dmg")!, sha256: "abc"))
        XCTAssertNil(AvailableUpdate.parse(release(digest: nil)), "Unverifiable downloads are not installed")
        XCTAssertNil(AvailableUpdate.parse(release(asset: "SnapPile-macOS.zip")))
        XCTAssertNil(AvailableUpdate.parse(release(prerelease: true)))
        XCTAssertNil(AvailableUpdate.parse(Data("{}".utf8)))
    }

    func testChecksReportUpToDateAndRejectDamagedDownloads() async throws {
        let work = directory()
        defer { try? FileManager.default.removeItem(at: work) }
        let installer = UpdateInstaller(bundleID: "de.example", teamID: "TEAM", workDirectory: work)

        let current = AppUpdater(
            currentVersion: "0.3.0", appURL: work, installer: installer, load: { _ in self.release() },
            download: { _ in
                XCTFail("No download expected")
                throw URLError(.cancelled)
            })
        await current.checkNow()
        XCTAssertEqual(current.state, .upToDate)

        let damaged = AppUpdater(
            currentVersion: "0.2.0", appURL: work, installer: installer, load: { _ in self.release() },
            download: { _ in
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try Data("not the release".utf8).write(to: file)
                return file
            })
        await damaged.checkNow()
        XCTAssertEqual(damaged.state, .failed(UpdateError.checksumMismatch.localizedDescription))
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.path), "Failed downloads are discarded")
        XCTAssertFalse(damaged.installPrepared())
    }

    func testOfflineCheckStaysQuiet() async {
        let updater = AppUpdater(
            currentVersion: "0.2.0", appURL: directory(),
            installer: UpdateInstaller(bundleID: "de.example", teamID: "TEAM", workDirectory: directory()),
            load: { _ in throw URLError(.notConnectedToInternet) })
        await updater.checkNow()
        XCTAssertEqual(updater.state, .idle)
    }

    func testInstallSwapsTheBundleAndCleansUp() throws {
        let base = directory()
        defer { try? FileManager.default.removeItem(at: base) }
        let work = base.appendingPathComponent("work", isDirectory: true)
        let target = base.appendingPathComponent("Apps/SnapPile.app", isDirectory: true)
        let staged = work.appendingPathComponent("SnapPile.app", isDirectory: true)
        for (bundle, version) in [(target, "old"), (staged, "new")] {
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            try Data(version.utf8).write(to: bundle.appendingPathComponent("version"))
        }

        try UpdateInstaller(bundleID: "de.example", teamID: "TEAM", workDirectory: work).install(staged, over: target)
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("version"), encoding: .utf8), "new")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path),
            ["SnapPile.app"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.path))
    }

    func testRejectsAppsWithoutTheDeveloperSignature() throws {
        let base = directory()
        defer { try? FileManager.default.removeItem(at: base) }
        let app = base.appendingPathComponent("Fake.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let installer = UpdateInstaller(bundleID: "de.example", teamID: "TEAM", workDirectory: base)
        XCTAssertThrowsError(try installer.verify(app.deletingLastPathComponent(), version: "1.0")) {
            XCTAssertEqual($0 as? UpdateError, .invalidSignature)
        }
    }
}
