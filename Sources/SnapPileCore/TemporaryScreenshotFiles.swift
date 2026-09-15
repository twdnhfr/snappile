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
            return L10n.text("Temporary image storage is full. Save the image or try again later.")
        case .preparationFailed:
            return L10n.text("The image could not be prepared for dragging. Copying or saving is still available.")
        }
    }
}

/// Creates a real file only when a drag starts. A completed drag does not imply
/// that its recipient has finished reading, so exports get a 30-minute lease.
@MainActor
public final class TemporaryScreenshotFiles {
    public static let shared = TemporaryScreenshotFiles()
    public static let defaultRetention: TimeInterval = 30 * 60

    private struct Entry {
        let url: URL
        let byteCount: Int
        let modifiedAt: Date?
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
    private var dragPasteboard: (itemID: UUID, pasteboard: NSPasteboard, changeCount: Int)?
    // Only mutated on the main actor; unsafe so that deinit can close it.
    nonisolated(unsafe) private var sessionLock: Int32 = -1
    private let files = FileManager.default

    public init(
        baseDirectory: URL? = nil, retention: TimeInterval = defaultRetention,
        byteLimit: Int = 256 * 1024 * 1024, fileLimit: Int = 50,
        now: @escaping () -> Date = Date.init
    ) {
        precondition(retention > 0 && byteLimit >= 0 && fileLimit > 0)
        let identifier = Bundle.main.bundleIdentifier ?? "de.wdnhfr.snappile"
        let base =
            baseDirectory
            ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("\(identifier)-drag", isDirectory: true)
        self.baseDirectory = base
        sessionDirectory = base.appendingPathComponent("\(getpid())-\(UUID().uuidString)", isDirectory: true)
        self.retention = retention
        self.byteLimit = byteLimit
        self.fileLimit = fileLimit
        self.now = now
    }

    deinit {
        if sessionLock >= 0 { close(sessionLock) }
    }

    public func beginDrag(for item: ScreenshotItem) throws -> ScreenshotDragFile {
        removeExpired()
        let leaseID = UUID()
        if var entry = entries[item.id], isUnchanged(entry) {
            entry.activeLeases.insert(leaseID)
            entry.expiresAt = now().addingTimeInterval(retention)
            entries[item.id] = entry
            return ScreenshotDragFile(url: entry.url, itemID: item.id, leaseID: leaseID)
        }
        removeEntry(item.id)
        guard entries.count < fileLimit,
            item.pngData.count <= byteLimit - entries.values.reduce(0, { $0 + $1.byteCount })
        else {
            throw ScreenshotDragError.capacityExceeded
        }

        let directory = sessionDirectory.appendingPathComponent(item.id.uuidString, isDirectory: true)
        let url = directory.appendingPathComponent(item.suggestedFilename)
        do {
            try createPrivateDirectory(baseDirectory)
            try createPrivateDirectory(sessionDirectory)
            try lockSession()
            try createPrivateDirectory(directory)
            try item.pngData.write(to: url, options: .atomic)
            // Read-only, so receivers cannot edit the original that later drags reuse.
            try files.setAttributes([.posixPermissions: 0o400], ofItemAtPath: url.path)
        } catch {
            try? files.removeItem(at: directory)
            throw ScreenshotDragError.preparationFailed
        }
        entries[item.id] = Entry(
            url: url, byteCount: item.pngData.count,
            modifiedAt: (try? files.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
            expiresAt: now().addingTimeInterval(retention), activeLeases: [leaseID])
        return ScreenshotDragFile(url: url, itemID: item.id, leaseID: leaseID)
    }

    /// Pass the session's pasteboard so its copy of the PNG is released together with the export.
    public func finishDrag(_ file: ScreenshotDragFile, pasteboard: NSPasteboard? = nil) {
        if let pasteboard { dragPasteboard = (file.itemID, pasteboard, pasteboard.changeCount) }
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
        if entries.isEmpty {
            try? files.removeItem(at: sessionDirectory)
            if sessionLock >= 0 { close(sessionLock) }
            sessionLock = -1
        }
    }

    private func removeEntry(_ id: UUID) {
        guard let entry = entries[id] else { return }
        let directory = entry.url.deletingLastPathComponent()
        do {
            if files.fileExists(atPath: directory.path) { try files.removeItem(at: directory) }
            entries.removeValue(forKey: id)
            // Any app can read the drag pasteboard until the next drag replaces it.
            if let drag = dragPasteboard, drag.itemID == id {
                if drag.pasteboard.changeCount == drag.changeCount { drag.pasteboard.clearContents() }
                dragPasteboard = nil
            }
        } catch {
            // Retain the entry and its byte budget so the next cleanup can retry.
        }
    }

    /// A receiver can still replace the file within the private directory; such a
    /// file is rewritten from the original instead of being reused.
    private func isUnchanged(_ entry: Entry) -> Bool {
        guard let attributes = try? files.attributesOfItem(atPath: entry.url.path) else { return false }
        return (attributes[.size] as? NSNumber)?.intValue == entry.byteCount
            && attributes[.modificationDate] as? Date == entry.modifiedAt
    }

    private func createPrivateDirectory(_ url: URL) throws {
        if !files.fileExists(atPath: url.path) {
            try files.createDirectory(
                at: url, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
        }
        let attributes = try files.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
            (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid()
        else {
            throw ScreenshotDragError.preparationFailed
        }
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    /// Held for the session's lifetime. Unlike a PID, a lock cannot be taken over
    /// by an unrelated process after a crash or reboot.
    private func lockSession() throws {
        guard sessionLock < 0 else { return }
        let descriptor = open(
            sessionDirectory.appendingPathComponent(".lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw ScreenshotDragError.preparationFailed }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw ScreenshotDragError.preparationFailed
        }
        sessionLock = descriptor
    }

    private func isAbandoned(_ directory: URL, pid: Int32) -> Bool {
        let descriptor = open(directory.appendingPathComponent(".lock").path, O_RDONLY | O_NOFOLLOW)
        // Directories from before session locks fall back to the owner's PID.
        guard descriptor >= 0 else { return kill(pid, 0) == -1 && errno == ESRCH }
        defer { close(descriptor) }
        return flock(descriptor, LOCK_EX | LOCK_NB) == 0
    }

    private func removeStaleSessions() {
        guard let attributes = try? files.attributesOfItem(atPath: baseDirectory.path),
            attributes[.type] as? FileAttributeType == .typeDirectory,
            (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
            let children = try? files.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil)
        else { return }
        for directory in children {
            let parts = directory.lastPathComponent.split(separator: "-", maxSplits: 1)
            guard parts.count == 2, let pid = Int32(parts[0]), pid > 0,
                UUID(uuidString: String(parts[1])) != nil,
                let info = try? files.attributesOfItem(atPath: directory.path),
                info[.type] as? FileAttributeType == .typeDirectory
            else { continue }
            // Never clean another running instance's export directory.
            if directory != sessionDirectory, isAbandoned(directory, pid: pid) { try? files.removeItem(at: directory) }
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
