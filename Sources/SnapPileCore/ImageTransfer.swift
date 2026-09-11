import AppKit
import UniformTypeIdentifiers

@MainActor
public enum ImageTransfer {
    @discardableResult
    public static func copy(_ item: ScreenshotItem) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // PNG bleibt die kanonische Darstellung und wird ohne erneutes Dekodieren
        // direkt aus dem Originalbild übernommen.
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(item.pngData, forType: .png)
        return pasteboard.writeObjects([pasteboardItem])
    }

    public static func save(_ item: ScreenshotItem,
                            completion: @escaping (Result<URL?, Error>) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = item.suggestedFilename
        panel.title = "Screenshot speichern"
        panel.prompt = "Speichern"

        // Bei einer Menüleisten-App gibt es möglicherweise kein Key Window. Die
        // Aktivierung vor begin() stellt sicher, dass der Panel-Dialog sichtbar wird.
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
