import SnapPileCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppController
    @ObservedObject var settings: AppSettings

    init(model: AppController) {
        self.model = model
        settings = model.settings
    }

    private var isReady: Bool {
        model.screenPermission
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(
                        isReady
                            ? L10n.text("All set. You can take your first capture.")
                            : L10n.text("SnapPile needs a quick permission before your first capture.")
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 10) {
                        PermissionCard(
                            number: "1",
                            title: L10n.text("Screen Recording"),
                            badge: L10n.text("REQUIRED"),
                            symbol: "rectangle.dashed.badge.record",
                            tint: pileAccent,
                            granted: model.screenPermission,
                            description:
                                L10n.text(
                                    "You choose the area for each capture. SnapPile keeps it temporarily in your pile."),
                            buttonTitle: L10n.text("Allow Screen Access…"),
                            action: model.requestScreenPermission,
                            refresh: model.refreshPermissions,
                            details:
                                L10n.text(
                                    "Enable SnapPile in macOS Privacy settings and return here. If macOS asks you to restart, quit and reopen SnapPile."
                                )
                        )

                        optionCard
                    }

                    if let message = model.message {
                        Label(
                            message,
                            systemImage: model.messageIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(model.messageIsError ? Color.orange : pileAccent)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.automatic)

            footer
        }
        .frame(width: 560).frame(minHeight: 600, idealHeight: 740, maxHeight: 740)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.refreshPermissions() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                BrandIcon()
                    .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("SNAPPILE"))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(pileAccent)
                    Text(L10n.text("Grant access once.\nCapture whenever you need."))
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .lineSpacing(1)
                }
            }

            Text(
                L10n.text("Select an area, keep it briefly in the pile, and drag it wherever you need it.")
            )
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 22)
    }

    private var optionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                cardNumber("2", tint: .secondary)
                Image(systemName: "option")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(L10n.text("Both Option keys"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(L10n.text("OPTIONAL"))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.primary.opacity(0.07), in: Capsule())
                    }
                    Text(L10n.text("For the quick shortcut using the left and right ⌥ keys."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Toggle(L10n.text("Enable left + right Option keys"), isOn: $settings.doubleOptionEnabled)
                .toggleStyle(.switch)
                .tint(pileAccent)
                .font(.system(size: 11, weight: .medium))

            Text(
                L10n.text(
                    "Input monitoring detects only the left and right Option modifiers. No text input is recorded.")
            )
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if model.inputPermission && settings.doubleOptionEnabled {
                    PermissionStatusBadge()
                } else if settings.doubleOptionEnabled {
                    Button(L10n.text("Allow Input Monitoring…"), action: model.requestInputPermission)
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
            }

            if let issue = model.optionMonitoringIssue {
                Text(issue).font(.system(size: 10)).foregroundStyle(.orange)
            }
            Text(
                L10n.format(
                    "The fallback shortcut %@ continues to work without this permission.", settings.shortcutLabel)
            )
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.09)))
        .accessibilityElement(children: .contain)
    }

    private var footer: some View {
        VStack(spacing: 13) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(pileAccent)
                    .padding(.top, 1)
                Text(
                    L10n.text(
                        "Captures are discarded automatically. Dragging creates a temporary PNG file. No account, no cloud."
                    )
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                Button(L10n.text("Later"), action: model.dismissOnboarding)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button(L10n.text("Settings…"), action: model.showSettings)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(action: model.finishOnboardingAndCapture) {
                    Label(L10n.text("Start First Capture"), systemImage: "viewfinder")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(pileAccent)
                .disabled(!model.screenPermission)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint(
                    model.screenPermission ? L10n.text("Starts area selection") : L10n.text("Allow Screen Access first")
                )
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 30)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func cardNumber(_ number: String, tint: Color) -> some View {
        Text(number)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: 23, height: 23)
            .background(tint.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct PermissionCard: View {
    let number: String
    let title: String
    let badge: String
    let symbol: String
    let tint: Color
    let granted: Bool
    let description: String
    let buttonTitle: String
    let action: () -> Void
    let refresh: () -> Void
    let details: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(number)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .frame(width: 23, height: 23)
                    .background(tint.opacity(0.12), in: Circle())
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        Text(badge)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(tint.opacity(0.11), in: Capsule())
                    }
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                if granted {
                    PermissionStatusBadge()
                } else {
                    Button(buttonTitle, action: action).controlSize(.small)
                }
                Spacer(minLength: 0)
                Button(L10n.text("Refresh Status"), action: refresh)
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .help(L10n.text("Check permission status again"))
                    .accessibilityLabel(L10n.text("Refresh permission status"))
            }

            Text(details)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.09)))
    }
}
