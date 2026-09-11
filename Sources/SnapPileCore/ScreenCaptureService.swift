import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

public struct CaptureSelection: Sendable, Equatable {
    public let displayID: CGDirectDisplayID
    public let screenFrame: CGRect
    /// Global AppKit coordinates, whose origin is at the bottom left.
    public let rect: CGRect

    public init(displayID: CGDirectDisplayID, screenFrame: CGRect, rect: CGRect) {
        self.displayID = displayID
        self.screenFrame = screenFrame
        self.rect = rect
    }
}

public struct CapturedImage: Sendable {
    public let pngData: Data
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(pngData: Data, pixelWidth: Int, pixelHeight: Int) {
        self.pngData = pngData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public enum CaptureGeometry {
    public static func topLeftRect(for selection: CaptureSelection) -> CGRect {
        CGRect(
            x: selection.rect.minX - selection.screenFrame.minX,
            y: selection.screenFrame.maxY - selection.rect.maxY,
            width: selection.rect.width, height: selection.rect.height)
    }

    public static func outputPixelSize(for selection: CaptureSelection, scale: CGFloat) -> (width: Int, height: Int) {
        (
            max(1, Int((selection.rect.width * scale).rounded())),
            max(1, Int((selection.rect.height * scale).rounded()))
        )
    }
}

public enum ScreenCaptureError: LocalizedError, Equatable {
    case permissionDenied
    case invalidSelection
    case displayUnavailable
    case captureFailed
    case pngEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Die Bildschirmaufnahme-Berechtigung fehlt."
        case .invalidSelection: return "Der ausgewählte Bereich ist ungültig."
        case .displayUnavailable: return "Der ausgewählte Bildschirm ist nicht verfügbar."
        case .captureFailed: return "Der Bildschirm konnte nicht aufgenommen werden."
        case .pngEncodingFailed: return "Das aufgenommene Bild konnte nicht als PNG gespeichert werden."
        }
    }
}

@MainActor
public final class ScreenCaptureService {
    public init() {}

    public var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    public func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    public func capture(selection: CaptureSelection) async throws -> CapturedImage {
        guard hasPermission else { throw ScreenCaptureError.permissionDenied }
        guard selection.rect.width >= 2, selection.rect.height >= 2,
            selection.screenFrame.contains(selection.rect),
            let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                    == selection.displayID
            }), screen.frame == selection.screenFrame
        else { throw ScreenCaptureError.displayUnavailable }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw ScreenCaptureError.displayUnavailable
        }
        let excluded = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])

        // ScreenCaptureKit uses display-local top-left coordinates for sourceRect.
        let sourceRect = CaptureGeometry.topLeftRect(for: selection)
        guard CGRect(origin: .zero, size: selection.screenFrame.size).contains(sourceRect) else {
            throw ScreenCaptureError.invalidSelection
        }

        let scale: CGFloat
        if #available(macOS 14.2, *) {
            scale = CGFloat(filter.pointPixelScale)
        } else {
            scale = screen.backingScaleFactor
        }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        let output = CaptureGeometry.outputPixelSize(for: selection, scale: scale)
        configuration.width = output.width
        configuration.height = output.height
        configuration.showsCursor = false

        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch { throw ScreenCaptureError.captureFailed }
        let width = image.width
        let height = image.height
        let data = try await Task.detached(priority: .userInitiated) {
            try Self.encodePNG(image)
        }.value
        return CapturedImage(pngData: data, pixelWidth: width, pixelHeight: height)
    }

    private nonisolated static func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ScreenCaptureError.pngEncodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ScreenCaptureError.pngEncodingFailed }
        return data as Data
    }
}
