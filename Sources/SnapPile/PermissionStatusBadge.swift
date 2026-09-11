import SnapPileCore
import SwiftUI

struct PermissionStatusBadge: View {
    var body: some View {
        Label(L10n.text("Allowed"), systemImage: "checkmark.circle.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.green)
            .fixedSize()
            .accessibilityLabel(L10n.text("Allowed"))
    }
}
