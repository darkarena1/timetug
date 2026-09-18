import SwiftUI
import TimeTugCore

struct OverlayView: View {
    let request: TakeoverRequest
    let onJoin: () -> Void
    let onSnooze: (TimeInterval) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 24) {
                Text(request.event.title)
                    .font(.system(size: 56, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text(request.event.start, style: .time)
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdown(now: context.date)
                }
                if request.joinURL != nil {
                    Button(action: onJoin) {
                        Text("Join").font(.system(size: 28, weight: .semibold)).padding(.horizontal, 48).padding(.vertical, 10)
                    }
                    .keyboardShortcut(.defaultAction)   // Return
                    .controlSize(.extraLarge)
                    .buttonStyle(.borderedProminent)
                }
                HStack(spacing: 12) {
                    ForEach(request.snoozeOptions, id: \.self) { seconds in
                        Button("Snooze \(Int(seconds / 60))m") { onSnooze(seconds) }
                    }
                    Button("Dismiss", action: onDismiss)
                        .keyboardShortcut(.cancelAction)   // Esc
                }
                .controlSize(.large)
            }
            .foregroundStyle(.white)
            .padding(60)
        }
        .preferredColorScheme(.dark)
    }

    private func countdown(now: Date) -> some View {
        let remaining = request.event.start.timeIntervalSince(now)
        let text = remaining > 0
            ? "Starts in \(TimeFormatting.clock(remaining))"
            : (remaining > -60 ? "Starting now" : "Started \(TimeFormatting.compact(-remaining)) ago")
        return Text(text)
            .font(.system(size: 40, weight: .medium).monospacedDigit())
            .foregroundStyle(remaining > 0 ? .white : .orange)
    }
}

struct DimCoverView: View {
    let title: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            Text(title).font(.system(size: 40, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
        }
    }
}
