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
                            ? "Alles bereit. Du kannst deine erste Aufnahme machen."
                            : "Für die erste Aufnahme braucht SnapPile eine kurze Freigabe."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 10) {
                        PermissionCard(
                            number: "1",
                            title: "Bildschirmaufnahme",
                            badge: "ERFORDERLICH",
                            symbol: "rectangle.dashed.badge.record",
                            tint: pileAccent,
                            granted: model.screenPermission,
                            description:
                                "Du bestimmst bei jeder Aufnahme den Ausschnitt. SnapPile legt ihn vorübergehend in deinem Stapel ab.",
                            buttonTitle: "Bildschirm freigeben …",
                            action: model.requestScreenPermission,
                            refresh: model.refreshPermissions,
                            details:
                                "Aktiviere SnapPile in den macOS-Datenschutzeinstellungen und kehre hierher zurück. Falls macOS einen Neustart verlangt, beende und öffne SnapPile erneut."
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
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(pileAccent)
                    .frame(width: 62, height: 62)
                    .background(pileAccent.opacity(0.11), in: RoundedRectangle(cornerRadius: 17))

                VStack(alignment: .leading, spacing: 4) {
                    Text("SNAPPILE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(pileAccent)
                    Text("Einmal freigeben.\nDann einfach festhalten.")
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .lineSpacing(1)
                }
            }

            Text(
                "Markiere einen Ausschnitt, behalte ihn kurz im Stapel und ziehe ihn direkt dorthin, wo du ihn brauchst."
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
                        Text("Beide Option-Tasten")
                            .font(.system(size: 13, weight: .semibold))
                        Text("OPTIONAL")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.primary.opacity(0.07), in: Capsule())
                    }
                    Text("Für das schnelle Kürzel mit linker und rechter ⌥-Taste.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Toggle("Linke + rechte Option-Taste aktivieren", isOn: $settings.doubleOptionEnabled)
                .toggleStyle(.switch)
                .tint(pileAccent)
                .font(.system(size: 11, weight: .medium))

            Text(
                "Die Eingabeüberwachung erkennt ausschließlich den linken und rechten Option-Modifikator. Es werden keine Texteingaben aufgezeichnet."
            )
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if model.inputPermission && settings.doubleOptionEnabled {
                    PermissionStatusBadge()
                } else if settings.doubleOptionEnabled {
                    Button("Eingabeüberwachung freigeben …", action: model.requestInputPermission)
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
            }

            if let issue = model.optionMonitoringIssue {
                Text(issue).font(.system(size: 10)).foregroundStyle(.orange)
            }
            Text("Ohne diese Freigabe funktioniert das Ersatz-Kürzel \(settings.shortcutLabel) weiterhin.")
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
                    "Aufnahmen werden automatisch verworfen. Beim Ziehen entsteht vorübergehend eine PNG-Datei. Kein Konto, keine Cloud."
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                Button("Später", action: model.dismissOnboarding)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button("Einstellungen …", action: model.showSettings)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(action: model.finishOnboardingAndCapture) {
                    Label("Erste Aufnahme starten", systemImage: "viewfinder")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(pileAccent)
                .disabled(!model.screenPermission)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint(
                    model.screenPermission ? "Startet die Bereichsauswahl" : "Erst Bildschirmaufnahme erlauben")
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
                Button("Status aktualisieren", action: refresh)
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .help("Berechtigungsstatus erneut prüfen")
                    .accessibilityLabel("Berechtigungsstatus aktualisieren")
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
