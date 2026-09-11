import SwiftUI

struct PermissionStatusBadge: View {
    var body: some View {
        Label("Erlaubt", systemImage: "checkmark.circle.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.green)
            .fixedSize()
            .accessibilityLabel("Erlaubt")
    }
}
