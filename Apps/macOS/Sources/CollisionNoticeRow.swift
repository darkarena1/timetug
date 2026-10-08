import SwiftUI

/// A quiet banner: the message and a Dismiss button. Never modal.
struct CollisionNoticeRow: View {
    let notice: CollisionNotice
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(notice.message).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Dismiss", action: onDismiss).buttonStyle(.link).font(.footnote)
        }
    }
}
