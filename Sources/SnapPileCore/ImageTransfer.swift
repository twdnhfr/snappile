import AppKit
import UniformTypeIdentifiers

@MainActor
public enum ImageTransfer {
    @discardableResult
    public static func copy(_ item: ScreenshotItem) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // PNG remains the canonical representation and is copied directly from
        // the original image without decoding it again.
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(item.pngData, forType: .png)
        return pasteboard.writeObjects([pasteboardItem])
    }

    public static func save(
        _ item: ScreenshotItem,
        completion: @escaping (Result<URL?, Error>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = item.suggestedFilename
        panel.title = L10n.text("Save Screenshot")
        panel.prompt = L10n.text("Save")

        // A menu bar app may not have a key window. Activating it before begin()
        // ensures that the panel dialog is visible.
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(.success(nil))
                return
            }
            do {
                try item.pngData.write(to: url, options: .atomic)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
