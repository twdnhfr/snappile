import AppKit
import SwiftUI

enum BrandAssets {
    private static var resourceBundle: Bundle? {
        if let url = Bundle.main.url(forResource: "SnapPile_SnapPile", withExtension: "bundle"),
            let bundle = Bundle(url: url)
        {
            return bundle
        }
        // A packaged app must never resolve resources from the developer's
        // build directory. SwiftPM's module bundle remains useful for swift run.
        if Bundle.main.bundleURL.pathExtension == "app" { return nil }
        return Bundle.module
    }

    private static func image(named name: String, accessibilityDescription: String) -> NSImage? {
        guard let url = resourceBundle?.url(forResource: name, withExtension: nil),
            let image = NSImage(contentsOf: url)
        else { return nil }
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    static func icon() -> NSImage? {
        image(named: "BrandIcon.png", accessibilityDescription: "SnapPile")
    }

    static func mark() -> NSImage? {
        image(named: "BrandMark.svg", accessibilityDescription: "SnapPile")
    }

    static func menuBarMark() -> NSImage? {
        guard let image = image(named: "MenuBarMark.svg", accessibilityDescription: "SnapPile") else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}

struct BrandIcon: View {
    var body: some View {
        Group {
            if let image = BrandAssets.icon() {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "rectangle.stack").resizable().scaledToFit()
            }
        }
        .accessibilityLabel("SnapPile")
    }
}

struct BrandMark: View {
    var body: some View {
        Group {
            if let image = BrandAssets.mark() {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "rectangle.stack").resizable().scaledToFit()
            }
        }
        .accessibilityLabel("SnapPile")
    }
}
