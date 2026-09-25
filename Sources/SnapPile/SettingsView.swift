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
                BrandIcon().frame(width: 66, height: 66)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("SnapPile")).font(.system(size: 27, weight: .semibold, design: .rounded))
                    Text(L10n.text("Capture now. Share in seconds.")).font(.system(size: 12)).foregroundStyle(
                        .secondary)
                }
                Spacer()
                Text(
                    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                        ?? L10n.text("Development")
                )
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4).background(.primary.opacity(0.05), in: Capsule())
            }.padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 18)
            Button(action: model.beginCapture) {
                HStack {
                    Label(L10n.text("Capture Area"), systemImage: "viewfinder").fontWeight(.semibold)
                    Spacer()
                    Text(settings.shortcutLabel).font(.system(.body, design: .rounded)).opacity(0.85)
                }.padding(.horizontal, 8).frame(height: 32)
            }.buttonStyle(.borderedProminent).tint(pileAccent).disabled(model.isCapturing || !model.screenPermission)
                .padding(.horizontal, 26)
            Form {
                Section {
                    permissionRow(
                        L10n.text("Screen Recording"), subtitle: L10n.text("For the area you select"),
                        granted: model.screenPermission, action: model.requestScreenPermission)
                    if settings.doubleOptionEnabled {
                        permissionRow(
                            L10n.text("Input Monitoring"), subtitle: L10n.text("For the left + right Option keys"),
                            granted: model.inputPermission, action: model.requestInputPermission)
                    }
                    if !model.screenPermission || (settings.doubleOptionEnabled && !model.inputPermission) {
                        Text(L10n.text("Already allowed in macOS? Refresh the status or restart SnapPile."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text(L10n.text("Permissions"))
                        Spacer()
                        Button(L10n.text("Refresh Status"), action: model.refreshPermissions)
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(L10n.text("Check permission status again"))
                            .accessibilityLabel(L10n.text("Refresh permission status"))
                    }
                }
                Section {
                    Toggle(L10n.text("Left + right Option keys"), isOn: $settings.doubleOptionEnabled).tint(pileAccent)
                    if let issue = model.optionMonitoringIssue {
                        Text(issue).font(.caption).foregroundStyle(.orange)
                    }
                    HStack(spacing: 6) {
                        Text(L10n.text("Fallback Shortcut"))
                        Spacer()
                        modifierToggle("⌃", mask: UInt32(controlKey))
                        modifierToggle("⌥", mask: UInt32(optionKey))
                        modifierToggle("⇧", mask: UInt32(shiftKey))
                        modifierToggle("⌘", mask: UInt32(cmdKey))
                        Picker(L10n.text("Key"), selection: $shortcutCode) {
                            ForEach(AppSettings.keys, id: \.code) { Text($0.label).tag($0.code) }
                        }
                        .labelsHidden().frame(width: 68)
                        Button(shortcutSaved ? "✓" : L10n.text("Set")) {
                            shortcutSaved = model.applyShortcut(keyCode: shortcutCode, modifiers: shortcutMods)
                        }.fixedSize().frame(minWidth: 56)
                    }
                    if let error = model.shortcutError { Text(error).font(.caption).foregroundStyle(.orange) }
                } header: {
                    Text(L10n.text("Capture"))
                }
                Section {
                    Picker(L10n.text("Delete Automatically"), selection: $settings.expiryMinutes) {
                        ForEach([5, 15, 30, 60, 120], id: \.self) { Text(L10n.format("After %ld minutes", $0)).tag($0) }
                    }
                    Picker(L10n.text("Maximum in Pile"), selection: $settings.maxItems) {
                        ForEach([5, 10, 20, 50], id: \.self) { Text(L10n.format("%ld Screenshots", $0)).tag($0) }
                    }
                    Picker(L10n.text("Screen Edge"), selection: $settings.side) {
                        ForEach(StackSide.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    if store.items.count > settings.maxItems {
                        Text(L10n.text("Pins can exceed the limit. Unpin items to free space."))
                            .font(.caption).foregroundStyle(.orange)
                    }
                } header: {
                    Text(L10n.text("Your Pile"))
                }
                Section {
                    Toggle(L10n.text("Allow Agent Requests"), isOn: $settings.agentAccessEnabled).tint(pileAccent)
                    Text(
                        L10n.text(
                            "Coding agents on this Mac can ask you for a screenshot and read the newest image in the pile. You select every new area yourself."
                        )
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    if let error = model.agentAccessError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    if settings.agentAccessEnabled {
                        HStack(alignment: .top) {
                            Text(model.agentSetupCommand).font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button(L10n.text("Copy"), action: model.copyAgentSetupCommand).controlSize(.small)
                        }
                    }
                } header: {
                    Text(L10n.text("Coding Agents"))
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden)
            if let message = model.message {
                Label(message, systemImage: model.messageIsError ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 11)).foregroundStyle(model.messageIsError ? Color.orange : pileAccent)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 26).padding(.bottom, 10)
            }
            VStack(alignment: .leading, spacing: 5) {
                Label(L10n.text("Just for the moment."), systemImage: "clock").font(
                    .system(size: 11, weight: .semibold))
                Text(
                    L10n.format(
                        "Pins prevent expiration. Dragging creates a temporary PNG that is deleted after %ld minutes. Everything is discarded when you quit.",
                        Int(TemporaryScreenshotFiles.defaultRetention / 60))
                )
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 26)
            HStack {
                Text(
                    L10n.format(
                        "Images: %ld · %@ PNG data", store.items.count,
                        ByteCountFormatter.string(fromByteCount: Int64(store.totalBytes), countStyle: .memory))
                )
                .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("Setup…"), action: model.showOnboarding)
                Button(L10n.text("Show Pile"), action: model.showStack).disabled(store.items.isEmpty)
                Button(L10n.text("Quit")) { NSApp.terminate(nil) }
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
        .accessibilityLabel(L10n.format("Modifier %@", label))
        .accessibilityValue(shortcutMods & mask != 0 ? L10n.text("Active") : L10n.text("Inactive"))
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
                Button(L10n.text("Allow…"), action: action).controlSize(.small)
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
                BrandMark().frame(width: 20, height: 20)
                Text(L10n.text("SnapPile")).font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Text(L10n.format("%ld / %ld", store.items.count, settings.maxItems)).font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Button(action: model.beginCapture) {
                HStack {
                    Label(L10n.text("Capture Area"), systemImage: "viewfinder")
                    Spacer()
                    Text(settings.shortcutLabel).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(pileAccent).disabled(model.isCapturing)
            if store.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "rectangle.stack").font(.system(size: 24)).foregroundStyle(.tertiary)
                    Text(L10n.text("Room for your next thought.")).font(.system(size: 11, weight: .medium))
                    Text(L10n.text("Capture an area, then drag it\ndirectly into your AI chat.")).font(
                        .system(size: 11)
                    )
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
                            Text(L10n.format("%ld × %ld", item.pixelWidth, item.pixelHeight)).font(
                                .system(size: 11, weight: .medium))
                            LifetimeLabel(item: item, minutes: settings.expiryMinutes, font: .system(size: 10))
                        }
                        Spacer()
                        SmallIconButton(L10n.text("Copy"), symbol: "doc.on.doc") { model.copy(item.id) }
                        SmallIconButton(L10n.text("Delete"), symbol: "trash") { model.delete(item.id) }
                    }
                }
                Button(L10n.format("Show Pile (%ld)", store.items.count), action: model.showStack).buttonStyle(.plain)
                    .foregroundStyle(pileAccent)
            }
            Text(model.message ?? L10n.format("Temporary pile · %ld min. retention", settings.expiryMinutes))
                .font(.system(size: 10)).foregroundStyle(model.messageIsError ? Color.orange : Color.secondary)
                .lineLimit(2).frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
            Divider()
            HStack {
                Button(L10n.text("Settings…"), action: model.showSettings)
                Spacer()
                Menu {
                    Button(L10n.text("Setup…"), action: model.showOnboarding)
                    Button(L10n.text("Delete Unpinned"), action: model.clearUnpinned).disabled(
                        store.items.allSatisfy(\.isPinned))
                    Divider()
                    Button(L10n.text("Quit SnapPile")) { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis")
                }.menuStyle(.borderlessButton).frame(width: 24)
            }.buttonStyle(.plain).font(.system(size: 11))
        }.padding(17).frame(width: 320).fixedSize(horizontal: false, vertical: true)
    }
}
