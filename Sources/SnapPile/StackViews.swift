import AppKit
import SnapPileCore
import SwiftUI

let pileAccent = Color(red: 0.14, green: 0.64, blue: 0.53)

struct StackView: View {
    @ObservedObject var model: AppController
    @ObservedObject var store: ScreenshotStore
    @ObservedObject var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(model: AppController) { self.model = model; store = model.store; settings = model.settings }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "square.3.layers.3d").foregroundStyle(pileAccent)
                Text("SnapPile").font(.system(size: 12, weight: .semibold))
                Text("\(store.items.count)").font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 3).background(.primary.opacity(0.08), in: Capsule())
                Spacer(minLength: 4)
                SmallIconButton("Neue Aufnahme", symbol: "plus", action: model.beginCapture)
                SmallIconButton(model.isExpanded ? "Stapel einklappen" : "Alle Bilder anzeigen", symbol: model.isExpanded ? "chevron.down" : "square.grid.2x2", action: model.toggleExpanded)
                SmallIconButton("Stapel ausblenden", symbol: "minus", action: model.hideStack)
            }.padding(.horizontal, 5)
            if model.isExpanded {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.items) { item in ScreenshotCard(model: model, item: item, alwaysShowActions: true) }
                    }.padding(.horizontal, 2).padding(.top, 2).padding(.bottom, 5)
                }.scrollIndicators(.hidden)
            } else if let item = store.items.first {
                ZStack(alignment: .top) {
                    ForEach(Array(store.items.prefix(3).enumerated().reversed()), id: \.element.id) { index, back in
                        if index > 0 {
                            RoundedRectangle(cornerRadius: 13)
                                .fill(.background)
                                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.10)))
                                .frame(height: 215)
                                .padding(.horizontal, CGFloat(index * 7))
                                .offset(y: CGFloat(index * 7))
                                .accessibilityHidden(true)
                        }
                    }
                    ScreenshotCard(model: model, item: item)
                        .id(item.id)
                        .transition(.asymmetric(insertion: .offset(x: settings.side == .right ? 34 : -34).combined(with: .opacity), removal: .opacity))
                }.padding(.bottom, min(CGFloat(store.items.count - 1), 2) * 7)
            }
            HStack(spacing: 4) {
                if let message = model.message {
                    Image(systemName: model.messageIsError ? "exclamationmark.circle" : "checkmark.circle")
                    Text(message).lineLimit(2)
                } else {
                    Image(systemName: "cursorarrow.and.square.on.square.dashed")
                    Text("Bild direkt in deinen Chat ziehen")
                    Spacer(minLength: 0)
                    if !model.isExpanded, store.items.count > 3 {
                        Button("+\(store.items.count - 3)", action: model.toggleExpanded).buttonStyle(.plain).fontWeight(.semibold).foregroundStyle(pileAccent)
                    }
                }
            }.font(.system(size: 10)).foregroundStyle(model.messageIsError ? Color.orange : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading).padding(.horizontal, 5)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(.primary.opacity(0.09)))
        .shadow(color: .black.opacity(0.17), radius: 12, x: 0, y: 5)
        .padding(14)
        .animation(reduceMotion ? nil : .spring(response:0.3, dampingFraction:0.85), value: store.items.map(\.id))
    }
}

struct ScreenshotCard: View {
    @ObservedObject var model: AppController
    let item: ScreenshotItem
    var alwaysShowActions = false
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Rectangle().fill(.primary.opacity(0.045))
                DraggableThumbnail(item: item, onClick: { model.preview(item.id) })
                    .padding(4)
                    .help("Klicken für Vorschau · Ziehen zum Einfügen")
                if item.isPinned {
                    Image(systemName:"pin.fill").font(.system(size:10,weight:.semibold)).foregroundStyle(pileAccent)
                        .padding(6).background(.regularMaterial, in: Circle()).padding(7).allowsHitTesting(false)
                }
            }.frame(height: 150).clipped()
            VStack(spacing: 5) {
                HStack {
                    Text("\(item.pixelWidth) × \(item.pixelHeight)").monospacedDigit()
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(lifetimeText(item, minutes: model.settings.expiryMinutes, now: context.date))
                    }
                }.font(.system(size:9)).foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    CardAction("Kopieren", symbol:"doc.on.doc", primary:true) { model.copy(item.id) }
                    CardAction("Speichern", symbol:"square.and.arrow.down") { model.save(item.id) }
                    Spacer(minLength: 0)
                    SmallIconButton(item.isPinned ? "Pin lösen" : "Anheften", symbol:item.isPinned ? "pin.slash" : "pin", tint: item.isPinned ? pileAccent : .secondary) { model.store.togglePin(id:item.id) }
                    SmallIconButton("Löschen", symbol:"trash", tint:.secondary) { model.delete(item.id) }
                }.opacity(hovering || alwaysShowActions ? 1 : 0.25)
            }.padding(.horizontal,8).padding(.vertical,7)
        }
        .background(.background, in: RoundedRectangle(cornerRadius:12))
        .clipShape(RoundedRectangle(cornerRadius:12))
        .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(.primary.opacity(0.09)))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration:0.12), value:hovering)
        .contextMenu {
            Button("Kopieren") { model.copy(item.id) }
            Button("Speichern …") { model.save(item.id) }
            Button(item.isPinned ? "Pin lösen" : "Anheften") { model.store.togglePin(id:item.id) }
            Divider()
            Button("Löschen", role:.destructive) { model.delete(item.id) }
        }
    }
}

struct SmallIconButton: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary
    let action: () -> Void
    init(_ title:String, symbol:String, tint:Color = .secondary, action:@escaping ()->Void) {
        self.title=title; self.symbol=symbol; self.tint=tint; self.action=action
    }
    var body: some View {
        Button(action:action) { Image(systemName:symbol).font(.system(size:11,weight:.medium)).frame(width:23,height:23).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(tint).help(title).accessibilityLabel(title)
    }
}
struct CardAction: View {
    let title:String
    let symbol:String
    var primary=false
    let action:()->Void
    init(_ title:String,symbol:String,primary:Bool=false,action:@escaping ()->Void) { self.title=title;self.symbol=symbol;self.primary=primary;self.action=action }
    var body:some View {
        Button(action:action) { Label(title,systemImage:symbol).font(.system(size:10,weight:.medium)).padding(.horizontal,5).frame(height:24) }
            .buttonStyle(.plain).foregroundStyle(primary ? pileAccent : Color.primary)
            .background(primary ? pileAccent.opacity(0.1) : Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:5))
            .help(title)
    }
}

func lifetimeText(_ item:ScreenshotItem,minutes:Int,now:Date=Date()) -> String {
    if item.isPinned { return "Angeheftet" }
    let remaining = max(0,Int(ceil((item.expirationDate(minutes:minutes)?.timeIntervalSince(now) ?? 0)/60)))
    return remaining > 0 ? "noch \(remaining) Min." : "läuft ab"
}
