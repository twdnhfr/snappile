import AppKit
import SnapPileCore
import SwiftUI

let pileAccent = Color(red: 0.14, green: 0.64, blue: 0.53)

enum StackLayout {
    static let contentWidth: CGFloat = 175
    static let width: CGFloat = contentWidth + 36
    static let maxCardHeight: CGFloat = 175
    static let layerOffset: CGFloat = 6
    static let cardSpacing: CGFloat = 8
    /// Header row plus the paddings around the card area.
    static let chromeHeight: CGFloat = 66
    static let maxExpandedHeight: CGFloat = 540
    static func depth(itemCount: Int) -> CGFloat { CGFloat(min(max(itemCount - 1, 0), 2)) * layerOffset }

    /// Cards are always square, so browsing between formats keeps the panel height stable.
    static func cardSize(maxHeight: CGFloat = maxCardHeight) -> CGSize {
        let side = max(1, min(contentWidth, maxHeight))
        return CGSize(width: side, height: side)
    }

    static func height(itemCount: Int, expanded: Bool) -> CGFloat {
        let cardHeight = cardSize().height
        guard expanded else { return chromeHeight + cardHeight + depth(itemCount: itemCount) }
        let cardsHeight = CGFloat(itemCount) * cardHeight
        let spacing = CGFloat(max(itemCount - 1, 0)) * cardSpacing
        return min(maxExpandedHeight, chromeHeight + max(cardsHeight + spacing + 2, 182))
    }
}

struct StackView: View {
    @ObservedObject var model: AppController
    @ObservedObject var store: ScreenshotStore
    @ObservedObject var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(model: AppController) {
        self.model = model
        store = model.store
        settings = model.settings
    }

    var body: some View {
        GeometryReader { proxy in
            stackContent(maxCardHeight: availableMaxCardHeight(proxy.size.height))
        }
    }

    private func availableMaxCardHeight(_ viewportHeight: CGFloat) -> CGFloat {
        let reserved =
            StackLayout.chromeHeight + (model.isExpanded ? 0 : StackLayout.depth(itemCount: store.items.count))
        return max(80, min(StackLayout.maxCardHeight, viewportHeight - reserved))
    }

    @ViewBuilder
    private func stackContent(maxCardHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text("SnapPile").font(.system(size: 11, weight: .semibold))
                Button(action: model.toggleExpanded) {
                    Text(
                        model.isExpanded || store.items.count < 2
                            ? "\(store.items.count)" : "\(model.stackPosition) / \(store.items.count)"
                    )
                    .font(.system(size: 9, weight: .semibold, design: .rounded)).monospacedDigit()
                    .padding(.horizontal, 4).padding(.vertical, 3)
                    .background(.primary.opacity(0.07), in: Capsule())
                }.buttonStyle(.plain).help(
                    "Bild \(model.stackPosition) von \(store.items.count) · Scrollen zum Blättern · Klicken für alle Bilder"
                )
                .accessibilityLabel(
                    model.isExpanded
                        ? "\(store.items.count) Bilder" : "Bild \(model.stackPosition) von \(store.items.count)")
                Spacer(minLength: 2)
                SmallIconButton("Neue Aufnahme", symbol: "plus", action: model.beginCapture)
                SmallIconButton("Stapel ausblenden", symbol: "minus", action: model.hideStack)
            }.frame(height: 24).padding(.horizontal, 2)
            if model.isExpanded {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.items) { item in
                            ScreenshotCard(model: model, item: item, maxCardHeight: maxCardHeight)
                        }
                    }.padding(.bottom, 2)
                }.scrollIndicators(.hidden)
            } else if let item = model.selectedStackItem {
                let cardSize = StackLayout.cardSize(maxHeight: maxCardHeight)
                ZStack(alignment: .top) {
                    ForEach(Array(store.items.prefix(3).enumerated().reversed()), id: \.element.id) { index, _ in
                        if index > 0 {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.background)
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.12)))
                                .frame(width: cardSize.width, height: cardSize.height)
                                .offset(y: CGFloat(index) * StackLayout.layerOffset)
                                .accessibilityHidden(true)
                        }
                    }
                    ScreenshotCard(model: model, item: item, maxCardHeight: maxCardHeight)
                        .id(item.id)
                        .transition(
                            .asymmetric(
                                insertion: .offset(x: settings.side == .right ? 24 : -24).combined(with: .opacity),
                                removal: .opacity))
                }.frame(
                    width: StackLayout.contentWidth,
                    height: cardSize.height + StackLayout.depth(itemCount: store.items.count), alignment: .top)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.09)))
        .overlay(alignment: .bottom) {
            if let message = model.message {
                Label(
                    message, systemImage: model.messageIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
                )
                .font(.system(size: 10, weight: .medium)).lineLimit(3)
                .foregroundStyle(model.messageIsError ? Color.orange : Color.primary)
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(12).allowsHitTesting(false)
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 3)
        .padding(10)
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: model.selectedStackItem?.id)
    }
}

struct ScreenshotCard: View {
    @ObservedObject var model: AppController
    let item: ScreenshotItem
    var maxCardHeight: CGFloat = StackLayout.maxCardHeight
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let cardSize = StackLayout.cardSize(maxHeight: maxCardHeight)
        DraggableThumbnail(
            item: item, onClick: { model.preview(item.id) }, onDragError: { model.notify($0, error: true) },
            contentMode: .fill
        )
        .frame(width: cardSize.width, height: cardSize.height)
        .background(.primary.opacity(0.045))
        .help(
            "\(item.pixelWidth) × \(item.pixelHeight) · \(lifetimeText(item, minutes: model.settings.expiryMinutes)) · Klicken für Vorschau"
        )
        .overlay(alignment: .topTrailing) {
            overlayActions(compact: cardSize.width < 110).padding(3)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.08)))
                .opacity(hovering ? 1 : 0.85).padding(6)
        }
        .overlay(alignment: .bottomLeading) {
            if hovering {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(
                        "\(item.pixelWidth) × \(item.pixelHeight) · \(lifetimeText(item, minutes: model.settings.expiryMinutes, now: context.date))"
                    )
                    .font(.system(size: 9)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                }.padding(6).allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.10)))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .contextMenu {
            Button("Kopieren") { model.copy(item.id) }
            Button("Speichern …") { model.save(item.id) }
            Button(item.isPinned ? "Pin lösen" : "Anheften") { model.store.togglePin(id: item.id) }
            Divider()
            Button("Löschen", role: .destructive) { model.delete(item.id) }
        }
    }

    @ViewBuilder
    private func overlayActions(compact: Bool) -> some View {
        if compact {
            VStack(spacing: 1) {
                actionButtons
            }
        } else {
            HStack(spacing: 1) {
                actionButtons
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        OverlayIconButton("Kopieren", symbol: "doc.on.doc") { model.copy(item.id) }
        OverlayIconButton("Speichern", symbol: "square.and.arrow.down") { model.save(item.id) }
        OverlayIconButton(
            item.isPinned ? "Pin lösen" : "Anheften", symbol: item.isPinned ? "pin.fill" : "pin",
            selected: item.isPinned
        ) { model.store.togglePin(id: item.id) }
        OverlayIconButton("Löschen", symbol: "trash") { model.delete(item.id) }
    }
}

private struct OverlayIconButton: View {
    let title: String
    let symbol: String
    var selected = false
    let action: () -> Void
    init(_ title: String, symbol: String, selected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.selected = selected
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(selected ? pileAccent : Color.primary)
            .help(title).accessibilityLabel(title)
    }
}

struct SmallIconButton: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary
    let action: () -> Void
    init(_ title: String, symbol: String, tint: Color = .secondary, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).frame(width: 23, height: 23)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(tint).help(title).accessibilityLabel(title)
    }
}
func lifetimeText(_ item: ScreenshotItem, minutes: Int, now: Date = Date()) -> String {
    if item.isPinned { return "Angeheftet" }
    let remaining = max(0, Int(ceil((item.expirationDate(minutes: minutes)?.timeIntervalSince(now) ?? 0) / 60)))
    return remaining > 0 ? "noch \(remaining) Min." : "läuft ab"
}
