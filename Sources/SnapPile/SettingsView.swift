import Carbon
import SnapPileCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppController
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ScreenshotStore
    @State private var shortcutCode: UInt32
    @State private var shortcutMods: UInt32
    @State private var shortcutSaved = false
    init(model: AppController) {
        self.model = model
        settings = model.settings
        store = model.store
        _shortcutCode = State(initialValue: model.settings.shortcutKeyCode)
        _shortcutMods = State(initialValue: model.settings.shortcutModifiers)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 15) {
                Image(systemName: "square.3.layers.3d").font(.system(size: 32, weight: .medium))
                    .foregroundStyle(pileAccent).frame(width: 66, height: 66)
                    .background(pileAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text("SnapPile").font(.system(size: 27, weight: .semibold, design: .rounded))
                    Text("Kurz festhalten. Einfach weitergeben.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Entwicklung")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(.primary.opacity(0.05), in: Capsule())
            }.padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 18)
            Button(action: model.beginCapture) {
                HStack {
                    Label("Bereich aufnehmen", systemImage: "viewfinder").fontWeight(.semibold)
                    Spacer()
                    Text(settings.shortcutLabel).font(.system(.body, design: .rounded)).opacity(0.85)
                }.padding(.horizontal, 8).frame(height: 32)
            }.buttonStyle(.borderedProminent).tint(pileAccent).disabled(model.isCapturing || !model.screenPermission)
                .padding(.horizontal, 26)
            Form {
                Section {
                    permissionRow(
                        "Bildschirmaufnahme", subtitle: "Für den von dir markierten Bereich",
                        granted: model.screenPermission, action: model.requestScreenPermission)
                    if settings.doubleOptionEnabled {
                        permissionRow(
                            "Eingabeüberwachung", subtitle: "Für linke + rechte Option-Taste",
                            granted: model.inputPermission, action: model.requestInputPermission)
                    }
                    if !model.screenPermission || (settings.doubleOptionEnabled && !model.inputPermission) {
                        Text("Bereits in macOS erlaubt? Status aktualisieren oder SnapPile neu starten.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text("Berechtigungen")
                        Spacer()
                        Button("Status aktualisieren", action: model.refreshPermissions)
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Berechtigungsstatus erneut prüfen")
                            .accessibilityLabel("Berechtigungsstatus aktualisieren")
                    }
                }
                Section {
                    Toggle("Linke + rechte Option-Taste", isOn: $settings.doubleOptionEnabled).tint(pileAccent)
                    if let issue = model.optionMonitoringIssue {
                        Text(issue).font(.caption).foregroundStyle(.orange)
                    }
                    HStack(spacing: 6) {
                        Text("Ersatz-Kürzel")
                        Spacer()
                        modifierToggle("⌃", mask: UInt32(controlKey))
                        modifierToggle("⌥", mask: UInt32(optionKey))
                        modifierToggle("⇧", mask: UInt32(shiftKey))
                        modifierToggle("⌘", mask: UInt32(cmdKey))
                        Picker("Taste", selection: $shortcutCode) {
                            ForEach(AppSettings.keys, id: \.code) { Text($0.label).tag($0.code) }
                        }
                        .labelsHidden().frame(width: 68)
                        Button(shortcutSaved ? "✓" : "Setzen") {
                            shortcutSaved = model.applyShortcut(keyCode: shortcutCode, modifiers: shortcutMods)
                        }.fixedSize().frame(minWidth: 56)
                    }
                    if let error = model.shortcutError { Text(error).font(.caption).foregroundStyle(.orange) }
                } header: {
                    Text("Aufnahme")
                }
                Section {
                    Picker("Automatisch löschen", selection: $settings.expiryMinutes) {
                        ForEach([5, 15, 30, 60, 120], id: \.self) { Text("Nach \($0) Minuten").tag($0) }
                    }
                    Picker("Maximal im Stapel", selection: $settings.maxItems) {
                        ForEach([5, 10, 20, 50], id: \.self) { Text("\($0) Screenshots").tag($0) }
                    }
                    Picker("Bildschirmrand", selection: $settings.side) {
                        ForEach(StackSide.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    if store.items.count > settings.maxItems {
                        Text("Pins belegen mehr als das Limit. Löse Pins, um Platz freizugeben.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                } header: {
                    Text("Dein Stapel")
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden)
            if let message = model.message {
                Label(message, systemImage: model.messageIsError ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 11)).foregroundStyle(model.messageIsError ? Color.orange : pileAccent)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 26).padding(.bottom, 10)
            }
            VStack(alignment: .leading, spacing: 5) {
                Label("Nur für den Moment.", systemImage: "clock").font(.system(size: 11, weight: .semibold))
                Text(
                    "Pins schützen vor Ablauf. Beim Ziehen entsteht eine temporäre PNG, die nach 30 Min. gelöscht wird. Beim Beenden wird alles verworfen."
                )
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 26)
            HStack {
                Text(
                    "\(store.items.count) Bilder · \(ByteCountFormatter.string(fromByteCount:Int64(store.totalBytes),countStyle:.memory)) PNG-Daten"
                )
                .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Einrichtung …", action: model.showOnboarding)
                Button("Stapel zeigen", action: model.showStack).disabled(store.items.isEmpty)
                Button("Beenden") { NSApp.terminate(nil) }
            }.controlSize(.small).padding(.horizontal, 26).padding(.vertical, 18)
        }.frame(width: 520, height: 710)
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear { model.refreshPermissions() }
            .onChange(of: shortcutCode) { _, _ in shortcutSaved = false }
            .onChange(of: shortcutMods) { _, _ in shortcutSaved = false }
    }
    private func modifierToggle(_ label: String, mask: UInt32) -> some View {
        Button {
            if shortcutMods & mask != 0 { shortcutMods &= ~mask } else { shortcutMods |= mask }
        } label: {
            Text(label).font(.system(size: 13, weight: .medium)).frame(width: 25, height: 24)
        }
        .buttonStyle(.plain)
        .background(
            shortcutMods & mask != 0 ? pileAccent.opacity(0.17) : Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5).strokeBorder(
                shortcutMods & mask != 0 ? pileAccent.opacity(0.5) : Color.primary.opacity(0.08))
        )
        .accessibilityLabel("Modifier \(label)")
        .accessibilityValue(shortcutMods & mask != 0 ? "Aktiv" : "Inaktiv")
    }
    private func permissionRow(
        _ title: String, subtitle: String, granted: Bool, action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                PermissionStatusBadge()
            } else {
                Button("Erlauben …", action: action).controlSize(.small)
            }
        }
    }
}

struct MenuPopoverView: View {
    @ObservedObject var model: AppController
    @ObservedObject var store: ScreenshotStore
    @ObservedObject var settings: AppSettings
    init(model: AppController) {
        self.model = model
        store = model.store
        settings = model.settings
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.3.layers.3d").foregroundStyle(pileAccent)
                Text("SnapPile").font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(store.items.count) / \(settings.maxItems)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Button(action: model.beginCapture) {
                HStack {
                    Label("Bereich aufnehmen", systemImage: "viewfinder")
                    Spacer()
                    Text(settings.shortcutLabel).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(pileAccent).disabled(model.isCapturing)
            if store.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "rectangle.stack").font(.system(size: 24)).foregroundStyle(.tertiary)
                    Text("Platz für deinen nächsten Gedanken.").font(.system(size: 11, weight: .medium))
                    Text("Bereich aufnehmen, dann direkt\nin deinen KI-Chat ziehen.").font(.system(size: 11))
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 10)
            } else {
                ForEach(store.items.prefix(3)) { item in
                    HStack(spacing: 10) {
                        DraggableThumbnail(
                            item: item, onClick: { model.preview(item.id) },
                            onDragError: { model.notify($0, error: true) }
                        ).frame(width: 60, height: 38)
                            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5)).clipShape(
                                RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(item.pixelWidth) × \(item.pixelHeight)").font(.system(size: 11, weight: .medium))
                            Text(lifetimeText(item, minutes: settings.expiryMinutes)).font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        SmallIconButton("Kopieren", symbol: "doc.on.doc") { model.copy(item.id) }
                        SmallIconButton("Löschen", symbol: "trash") { model.delete(item.id) }
                    }
                }
                Button("Stapel zeigen (\(store.items.count))", action: model.showStack).buttonStyle(.plain)
                    .foregroundStyle(pileAccent)
            }
            Text(model.message ?? "Temporärer Stapel · \(settings.expiryMinutes) Min. Aufbewahrung")
                .font(.system(size: 10)).foregroundStyle(model.messageIsError ? Color.orange : Color.secondary)
                .lineLimit(2).frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
            Divider()
            HStack {
                Button("Einstellungen …", action: model.showSettings)
                Spacer()
                Menu {
                    Button("Einrichtung …", action: model.showOnboarding)
                    Button("Ungepinntes löschen", action: model.clearUnpinned).disabled(
                        store.items.allSatisfy(\.isPinned))
                    Divider()
                    Button("SnapPile beenden") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                }.menuStyle(.borderlessButton).frame(width: 24)
            }.buttonStyle(.plain).font(.system(size: 11))
        }.padding(17).frame(width: 320).fixedSize(horizontal: false, vertical: true)
    }
}
