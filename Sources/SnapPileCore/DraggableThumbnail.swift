import AppKit
import SwiftUI

public enum ThumbnailContentMode { case fit, fill }

/// Ein Thumbnail mit getrennten Klick- und Drag-Gesten. Der Drag exportiert stets
/// die originalen PNG-Bytes; das Thumbnail dient ausschließlich als Drag-Ansicht.
public struct DraggableThumbnail: NSViewRepresentable {
    public let item: ScreenshotItem
    public let onClick: () -> Void
    public let onDragError: (String) -> Void
    public let contentMode: ThumbnailContentMode

    public init(
        item: ScreenshotItem, onClick: @escaping () -> Void, onDragError: @escaping (String) -> Void = { _ in },
        contentMode: ThumbnailContentMode = .fit
    ) {
        self.item = item
        self.onClick = onClick
        self.onDragError = onDragError
        self.contentMode = contentMode
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> ThumbnailView {
        let view = ThumbnailView()
        view.coordinator = context.coordinator
        view.update(item: item, onClick: onClick, onDragError: onDragError, contentMode: contentMode)
        return view
    }

    public func updateNSView(_ nsView: ThumbnailView, context: Context) {
        nsView.coordinator = context.coordinator
        nsView.update(item: item, onClick: onClick, onDragError: onDragError, contentMode: contentMode)
    }

    @MainActor
    public final class Coordinator: NSObject, NSDraggingSource {
        private var activeFile: ScreenshotDragFile?
        private var activeItem: NSPasteboardItem?

        fileprivate func beginDrag(
            item: ScreenshotItem, from view: ThumbnailView, event: NSEvent,
            onError: (String) -> Void
        ) {
            do {
                let file = try TemporaryScreenshotFiles.shared.beginDrag(for: item)
                activeFile = file
                let writer = ScreenshotDragPasteboard.item(pngData: item.pngData, fileURL: file.url)
                activeItem = writer
                let draggingItem = NSDraggingItem(pasteboardWriter: writer)
                draggingItem.setDraggingFrame(view.bounds, contents: item.thumbnail)
                view.beginDraggingSession(with: [draggingItem], event: event, source: self)
            } catch {
                onError(error.localizedDescription)
                NSSound.beep()
            }
        }

        public func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation { .copy }

        public func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            if let activeFile { TemporaryScreenshotFiles.shared.finishDrag(activeFile) }
            activeFile = nil
            activeItem = nil
        }
    }

    public final class ThumbnailView: NSView {
        fileprivate weak var coordinator: Coordinator?
        private var item: ScreenshotItem?
        private var clickAction: (() -> Void)?
        private var dragError: (String) -> Void = { _ in }
        private var contentMode: ThumbnailContentMode = .fit
        private var mouseDownPoint: NSPoint = .zero
        private var didStartDrag = false

        fileprivate func update(
            item: ScreenshotItem, onClick: @escaping () -> Void, onDragError: @escaping (String) -> Void,
            contentMode: ThumbnailContentMode
        ) {
            self.item = item
            clickAction = onClick
            dragError = onDragError
            self.contentMode = contentMode
            setAccessibilityRole(.image)
            setAccessibilityLabel("Screenshot \(item.suggestedFilename)")
            needsDisplay = true
        }

        public override var isFlipped: Bool { true }

        public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        public override func draw(_ dirtyRect: NSRect) {
            guard let image = item?.thumbnail else { return }
            let rect = Self.drawRect(imageSize: image.size, in: bounds, contentMode: contentMode)
            NSGraphicsContext.saveGraphicsState()
            bounds.clip()
            image.draw(
                in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                respectFlipped: isFlipped, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        }

        static func drawRect(imageSize: NSSize, in bounds: NSRect, contentMode: ThumbnailContentMode) -> NSRect {
            let imageWidth = max(imageSize.width, 1)
            let imageHeight = max(imageSize.height, 1)
            let scale: CGFloat
            switch contentMode {
            case .fit: scale = min(bounds.width / imageWidth, bounds.height / imageHeight)
            case .fill: scale = max(bounds.width / imageWidth, bounds.height / imageHeight)
            }
            let size = NSSize(width: imageWidth * scale, height: imageHeight * scale)
            return NSRect(
                x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                width: size.width, height: size.height)
        }

        public override func mouseDown(with event: NSEvent) {
            mouseDownPoint = convert(event.locationInWindow, from: nil)
            didStartDrag = false
        }

        public override func mouseDragged(with event: NSEvent) {
            guard !didStartDrag, let item, let coordinator else { return }
            let point = convert(event.locationInWindow, from: nil)
            let dx = point.x - mouseDownPoint.x
            let dy = point.y - mouseDownPoint.y
            guard hypot(dx, dy) > 4 else { return }
            didStartDrag = true
            coordinator.beginDrag(item: item, from: self, event: event, onError: dragError)
        }

        public override func mouseUp(with event: NSEvent) {
            if !didStartDrag { clickAction?() }
        }
    }
}
