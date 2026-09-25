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
    case windowUnavailable
    case windowNotOnScreen

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: return L10n.text("Screen recording permission is missing.")
        case .invalidSelection: return L10n.text("The selected area is invalid.")
        case .displayUnavailable: return L10n.text("The selected display is unavailable.")
        case .captureFailed: return L10n.text("The screen could not be captured.")
        case .pngEncodingFailed: return L10n.text("The captured image could not be encoded as PNG.")
        case .windowUnavailable: return L10n.text("The window is no longer open.")
        case .windowNotOnScreen:
            return L10n.text("The window is minimized or on another Space, so it has no current content.")
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
            try Self.encodePNG(image, scale: scale)
        }.value
        return CapturedImage(pngData: data, pixelWidth: width, pixelHeight: height)
    }

    /// Normal app windows, front to back; on-screen windows come first.
    public func windows() async throws -> [AgentWindow] {
        guard hasPermission else { throw ScreenCaptureError.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        let order = ((info as? [[String: Any]]) ?? []).compactMap {
            ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return content.windows.compactMap { window -> (AgentWindow, Int)? in
            guard window.windowLayer == 0, window.frame.width >= 40, window.frame.height >= 40,
                let app = window.owningApplication, app.processID != ownPID
            else { return nil }
            let title = window.title ?? ""
            // Apps keep many hidden, untitled helper windows off screen.
            guard window.isOnScreen || !title.isEmpty else { return nil }
            let entry = AgentWindow(
                id: window.windowID, app: app.applicationName, bundleID: app.bundleIdentifier, title: title,
                width: Int(window.frame.width), height: Int(window.frame.height), isOnScreen: window.isOnScreen)
            return (entry, order.firstIndex(of: window.windowID) ?? Int.max)
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }

    /// Captures the window's own content, so covering windows do not appear.
    public func capture(windowID: UInt32) async throws -> CapturedImage {
        guard hasPermission else { throw ScreenCaptureError.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenCaptureError.windowUnavailable
        }
        guard window.isOnScreen else { throw ScreenCaptureError.windowNotOnScreen }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale: CGFloat
        if #available(macOS 14.2, *) {
            scale = CGFloat(filter.pointPixelScale)
        } else {
            scale = NSScreen.screens.first { $0.frame.intersects(window.frame) }?.backingScaleFactor ?? 2
        }
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((filter.contentRect.width * scale).rounded()))
        configuration.height = max(1, Int((filter.contentRect.height * scale).rounded()))
        configuration.showsCursor = false
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch { throw ScreenCaptureError.captureFailed }
        let data = try await Task.detached(priority: .userInitiated) {
            try Self.encodePNG(image, scale: scale)
        }.value
        return CapturedImage(pngData: data, pixelWidth: image.width, pixelHeight: image.height)
    }

    /// Records the display scale as DPI so receivers place Retina captures at their on-screen size.
    nonisolated static func encodePNG(_ image: CGImage, scale: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ScreenCaptureError.pngEncodingFailed
        }
        let properties = [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ScreenCaptureError.pngEncodingFailed }
        return data as Data
    }
}
