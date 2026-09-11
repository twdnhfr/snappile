import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Ein Thumbnail mit getrennten Klick- und Drag-Gesten. Der Drag exportiert stets
/// die originalen PNG-Bytes; das Thumbnail dient ausschließlich als Drag-Ansicht.
public struct DraggableThumbnail: NSViewRepresentable {
    public let item: ScreenshotItem
    public let onClick: () -> Void

    public init(item: ScreenshotItem, onClick: @escaping () -> Void) {
        self.item = item
        self.onClick = onClick
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> ThumbnailView {
        let view = ThumbnailView()
        view.coordinator = context.coordinator
        view.update(item: item, onClick: onClick)
        return view
    }

    public func updateNSView(_ nsView: ThumbnailView, context: Context) {
        nsView.coordinator = context.coordinator
        nsView.update(item: item, onClick: onClick)
    }

    public final class Coordinator: NSObject, NSDraggingSource {
        private var activeProvider: PNGFilePromiseProvider?

        fileprivate func beginDrag(item: ScreenshotItem, from view: ThumbnailView, event: NSEvent) {
            // Ein Writer stellt sowohl PNG als auch das Finder-File-Promise bereit;
            // dadurch erzeugt ein Drop genau einen Screenshot.
            let provider = PNGFilePromiseProvider(data: item.pngData,
                                                   filename: item.suggestedFilename)
            activeProvider = provider
            let draggingItem = NSDraggingItem(pasteboardWriter: provider)
            draggingItem.setDraggingFrame(view.bounds, contents: item.thumbnail)
            view.beginDraggingSession(with: [draggingItem], event: event, source: self)
        }

        public func draggingSession(_ session: NSDraggingSession,
                                    sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }

        public func draggingSession(_ session: NSDraggingSession,
                                    endedAt screenPoint: NSPoint,
                                    operation: NSDragOperation) {
            // AppKit hält den Pasteboard-Writer während eines akzeptierten Drops. Der
            // Provider hält wiederum seinen Delegate, sodass der asynchrone Schreibvorgang
            // nicht vom Coordinator abhängt.
            activeProvider = nil
        }
    }

    public final class ThumbnailView: NSView {
        fileprivate weak var coordinator: Coordinator?
        private var item: ScreenshotItem?
        private var clickAction: (() -> Void)?
        private var mouseDownPoint: NSPoint = .zero
        private var didStartDrag = false

        fileprivate func update(item: ScreenshotItem, onClick: @escaping () -> Void) {
            self.item = item
            clickAction = onClick
            setAccessibilityRole(.image)
            setAccessibilityLabel("Screenshot \(item.suggestedFilename)")
            needsDisplay = true
        }

        public override var isFlipped: Bool { true }

        public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        public override func draw(_ dirtyRect: NSRect) {
            guard let image = item?.thumbnail else { return }
            let scale = min(bounds.width / max(image.size.width, 1),
                            bounds.height / max(image.size.height, 1))
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let rect = NSRect(x: bounds.midX - size.width / 2,
                              y: bounds.midY - size.height / 2,
                              width: size.width, height: size.height)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: isFlipped, hints: nil)
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
            coordinator.beginDrag(item: item, from: self, event: event)
        }

        public override func mouseUp(with event: NSEvent) {
            if !didStartDrag { clickAction?() }
        }
    }
}

final class PNGFilePromiseProvider: NSFilePromiseProvider {
    private var promiseDelegate: PNGFilePromiseDelegate?

    // AppKit creates an empty instance while inspecting a pasteboard writer class.
    // Keep NSObject's initializer available in addition to our payload initializer.
    override init() {
        super.init()
    }

    init(data: Data, filename: String) {
        let payload = PNGFilePromiseDelegate(data: data, filename: filename)
        promiseDelegate = payload
        super.init()
        fileType = UTType.png.identifier
        delegate = payload
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        if !types.contains(.png) { types.append(.png) }
        return types
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType,
                                 pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        type == .png ? [] : super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .png ? promiseDelegate?.data : super.pasteboardPropertyList(forType: type)
    }
}

final class PNGFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    let data: Data
    let filename: String

    init(data: Data, filename: String) {
        self.data = data
        self.filename = filename
        super.init()
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             fileNameForType fileType: String) -> String { filename }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        let bytes = data
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try bytes.write(to: url, options: .atomic)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }
}
