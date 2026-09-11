import Foundation

/// Rendered PNGs for manual inspection go to the user's temp directory, not into the repository.
enum TestOutput {
    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SnapPileTests", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
