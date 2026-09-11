import AppKit
import Darwin

public struct ScreenshotDragFile {
    public let url: URL
    fileprivate let itemID: UUID
    fileprivate let leaseID: UUID
}

public enum ScreenshotDragError: LocalizedError {
    case capacityExceeded
    case preparationFailed

    public var errorDescription: String? {
        switch self {
        case .capacityExceeded:
            return "Der temporäre Bildspeicher ist voll. Speichere das Bild oder versuche es später erneut."
        case .preparationFailed:
            return "Das Bild konnte nicht zum Ziehen vorbereitet werden. Kopieren oder Speichern ist weiterhin möglich."
        }
    }
}

/// Creates a real file only when a drag starts. A completed drag does not imply
/// that its recipient has finished reading, so exports get a 30-minute lease.
@MainActor
public final class TemporaryScreenshotFiles {
    public static let shared = TemporaryScreenshotFiles()

    private struct Entry {
        let url: URL
        let byteCount: Int
        var expiresAt: Date
        var activeLeases: Set<UUID>
    }

    private let baseDirectory: URL
    private let sessionDirectory: URL
    private let retention: TimeInterval
    private let byteLimit: Int
    private let fileLimit: Int
    private let now: () -> Date
    private var entries: [UUID: Entry] = [:]
    private var checkedStaleSessions = false
    private let files = FileManager.default

    public init(baseDirectory: URL? = nil, retention: TimeInterval = 30 * 60,
                byteLimit: Int = 256 * 1024 * 1024, fileLimit: Int = 50,
                now: @escaping () -> Date = Date.init) {
        precondition(retention > 0 && byteLimit >= 0 && fileLimit > 0)
        let identifier = Bundle.main.bundleIdentifier ?? "de.wdnhfr.snappile"
        let base = baseDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("\(identifier)-drag", isDirectory: true)
        self.baseDirectory = base
        sessionDirectory = base.appendingPathComponent("\(getpid())-\(UUID().uuidString)", isDirectory: true)
        self.retention = retention
        self.byteLimit = byteLimit
        self.fileLimit = fileLimit
        self.now = now
    }

    public func beginDrag(for item: ScreenshotItem) throws -> ScreenshotDragFile {
        removeExpired()
        let leaseID = UUID()
        if var entry = entries[item.id], files.fileExists(atPath: entry.url.path) {
            entry.activeLeases.insert(leaseID)
            entry.expiresAt = now().addingTimeInterval(retention)
            entries[item.id] = entry
            return ScreenshotDragFile(url: entry.url, itemID: item.id, leaseID: leaseID)
        }
        removeEntry(item.id)
        guard entries.count < fileLimit,
              item.pngData.count <= byteLimit - entries.values.reduce(0, { $0 + $1.byteCount }) else {
            throw ScreenshotDragError.capacityExceeded
        }

        let directory = sessionDirectory.appendingPathComponent(item.id.uuidString, isDirectory: true)
        let url = directory.appendingPathComponent(item.suggestedFilename)
        do {
            try createPrivateDirectory(baseDirectory)
            try createPrivateDirectory(sessionDirectory)
            try createPrivateDirectory(directory)
            try item.pngData.write(to: url, options: .atomic)
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            try? files.removeItem(at: directory)
            throw ScreenshotDragError.preparationFailed
        }
        entries[item.id] = Entry(url: url, byteCount: item.pngData.count,
                                 expiresAt: now().addingTimeInterval(retention), activeLeases: [leaseID])
        return ScreenshotDragFile(url: url, itemID: item.id, leaseID: leaseID)
    }

    public func finishDrag(_ file: ScreenshotDragFile) {
        guard var entry = entries[file.itemID], entry.activeLeases.remove(file.leaseID) != nil else { return }
        entry.expiresAt = now().addingTimeInterval(retention)
        entries[file.itemID] = entry
    }

    public func removeExpired() {
        if !checkedStaleSessions {
            removeStaleSessions()
            checkedStaleSessions = true
        }
        let date = now()
        for id in entries.keys.filter({ entries[$0]!.activeLeases.isEmpty && entries[$0]!.expiresAt <= date }) {
            removeEntry(id)
        }
    }

    public func removeAll() {
        for id in Array(entries.keys) { removeEntry(id) }
        if entries.isEmpty { try? files.removeItem(at: sessionDirectory) }
    }

    private func removeEntry(_ id: UUID) {
        guard let entry = entries[id] else { return }
        let directory = entry.url.deletingLastPathComponent()
        do {
            if files.fileExists(atPath: directory.path) { try files.removeItem(at: directory) }
            entries.removeValue(forKey: id)
        } catch {
            // Retain the entry and its byte budget so the next cleanup can retry.
        }
    }

    private func createPrivateDirectory(_ url: URL) throws {
        if !files.fileExists(atPath: url.path) {
            try files.createDirectory(at: url, withIntermediateDirectories: false,
                                      attributes: [.posixPermissions: 0o700])
        }
        let attributes = try files.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid() else {
            throw ScreenshotDragError.preparationFailed
        }
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func removeStaleSessions() {
        guard let attributes = try? files.attributesOfItem(atPath: baseDirectory.path),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
              let children = try? files.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil) else { return }
        for directory in children {
            let parts = directory.lastPathComponent.split(separator: "-", maxSplits: 1)
            guard parts.count == 2, let pid = Int32(parts[0]), pid > 0,
                  UUID(uuidString: String(parts[1])) != nil,
                  let info = try? files.attributesOfItem(atPath: directory.path),
                  info[.type] as? FileAttributeType == .typeDirectory else { continue }
            // Never clean another running instance's export directory.
            if kill(pid, 0) == -1 && errno == ESRCH { try? files.removeItem(at: directory) }
        }
    }
}

/// One drag item with a normal file URL for file-oriented targets and original
/// PNG bytes for targets that accept image pasteboard data directly.
@MainActor
enum ScreenshotDragPasteboard {
    static func item(pngData: Data, fileURL: URL) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)
        item.setData(pngData, forType: .png)
        return item
    }
}
