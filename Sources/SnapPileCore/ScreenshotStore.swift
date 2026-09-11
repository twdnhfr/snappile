import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

public struct ScreenshotItem: Identifiable {
    public let id: UUID
    public let pngData: Data
    public let thumbnail: NSImage
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let createdAt: Date
    public internal(set) var isPinned: Bool

    public init(id: UUID = UUID(), pngData: Data, thumbnail: NSImage, pixelWidth: Int,
                pixelHeight: Int, createdAt: Date, isPinned: Bool = false) {
        self.id = id
        self.pngData = pngData
        self.thumbnail = thumbnail
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.createdAt = createdAt
        self.isPinned = isPinned
    }

    public var suggestedFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "Screenshot_\(formatter.string(from: createdAt)).png"
    }

    public func expirationDate(minutes: Int) -> Date? {
        guard minutes > 0 else { return nil }
        return createdAt.addingTimeInterval(TimeInterval(minutes) * 60)
    }
}

public enum ScreenshotStoreError: LocalizedError, Equatable {
    case invalidPNG
    case invalidDimensions
    case imageTooLarge
    case capacityExceeded

    public var errorDescription: String? {
        switch self {
        case .invalidPNG: return "Die Datei ist kein gültiges PNG-Bild."
        case .invalidDimensions: return "Die angegebenen Bildabmessungen sind ungültig oder stimmen nicht mit dem PNG überein."
        case .imageTooLarge: return "Das PNG überschreitet das Speicherlimit."
        case .capacityExceeded: return "Das Bild kann wegen angehefteter Screenshots nicht aufgenommen werden."
        }
    }
}

@MainActor
public final class ScreenshotStore: ObservableObject {
    @Published public private(set) var items: [ScreenshotItem] = []

    public var maxItems: Int { didSet { enforceLimits() } }
    public var expiryMinutes: Int
    public let byteLimit: Int
    private let now: () -> Date

    public init(maxItems: Int = 20, expiryMinutes: Int = 30,
                byteLimit: Int = 256 * 1024 * 1024, now: @escaping () -> Date = Date.init) {
        self.maxItems = max(1, maxItems)
        self.expiryMinutes = expiryMinutes
        self.byteLimit = max(0, byteLimit)
        self.now = now
    }

    public var totalBytes: Int { items.reduce(0) { $0 + $1.pngData.count } }

    @discardableResult
    public func add(pngData: Data, pixelWidth: Int, pixelHeight: Int,
                    createdAt: Date? = nil) throws -> UUID {
        guard pngData.count <= byteLimit else { throw ScreenshotStoreError.imageTooLarge }
        guard pixelWidth > 0, pixelHeight > 0 else { throw ScreenshotStoreError.invalidDimensions }
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetType(source) == UTType.png.identifier as CFString,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width == pixelWidth, height == pixelHeight,
              let thumbnailCG = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 520,
                  kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else {
            throw ScreenshotStoreError.invalidPNG
        }
        guard pngData.count <= byteLimit else { throw ScreenshotStoreError.imageTooLarge }

        let id = UUID()
        let date = createdAt ?? now()
        let size = NSSize(width: thumbnailCG.width, height: thumbnailCG.height)
        let candidate = ScreenshotItem(id: id, pngData: pngData,
                                       thumbnail: NSImage(cgImage: thumbnailCG, size: size),
                                       pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                                       createdAt: date)

        // Calculate admission on a copy first. This keeps the operation atomic on failure.
        var accepted = items
        accepted.insert(candidate, at: 0)
        while accepted.count > max(1, maxItems) || accepted.reduce(0, { $0 + $1.pngData.count }) > byteLimit {
            guard let index = accepted.enumerated()
                .filter({ !$0.element.isPinned && $0.element.id != id })
                .min(by: { $0.element.createdAt < $1.element.createdAt })?.offset else {
                throw ScreenshotStoreError.capacityExceeded
            }
            accepted.remove(at: index)
        }
        guard accepted.contains(where: { $0.id == id }) else { throw ScreenshotStoreError.capacityExceeded }
        items = accepted.sorted { $0.createdAt > $1.createdAt }
        return id
    }

    public func enforceLimits() {
        while items.count > max(1, maxItems) || totalBytes > byteLimit {
            guard let oldest = items.filter({ !$0.isPinned }).min(by: { $0.createdAt < $1.createdAt }) else { break }
            items.removeAll { $0.id == oldest.id }
        }
    }

    public func remove(id: UUID) { items.removeAll { $0.id == id } }

    public func removeAll(includingPinned: Bool = false) {
        if includingPinned { items.removeAll() }
        else { items.removeAll { !$0.isPinned } }
    }

    public func togglePin(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        enforceLimits()
    }

    public func removeExpired() {
        let current = now()
        items.removeAll { item in
            guard !item.isPinned, let expiration = item.expirationDate(minutes: expiryMinutes) else { return false }
            return expiration <= current
        }
    }

    public func item(id: UUID) -> ScreenshotItem? { items.first { $0.id == id } }
}
