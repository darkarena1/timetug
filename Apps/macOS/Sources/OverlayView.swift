import AppKit
import SwiftUI
import TimeTugCore

/// The takeover on the primary display: hero, live countdown, meeting details and the actions.
struct OverlayView: View {
    let request: TakeoverRequest
    let calendarTitle: String?
    let onJoin: () -> Void
    let onSnooze: (TimeInterval) -> Void
    let onDismiss: () -> Void

    private enum Field { case join, dismiss }
    @FocusState private var focus: Field?

    private var event: CalendarEvent { request.event }

    var body: some View {
        ZStack {
            TakeoverBackdrop()
            VStack(spacing: 18) {
                Image("AboutHero")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 440)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    .accessibilityHidden(true)
                TakeoverCountdown(start: event.start, labelSize: 15, valueSize: 88, statusSize: 48)
                Text(event.title)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Text(TakeoverText.details(start: event.start, end: event.end, calendarTitle: calendarTitle,
                                          otherAttendees: event.otherAttendeeCount))
                    .font(.system(size: 16))
                    .foregroundStyle(TakeoverColors.muted)
                    .multilineTextAlignment(.center)
                actions
                    .padding(.top, 6)
                Text(TakeoverText.hints(hasJoin: request.joinURL != nil, snoozeOptions: request.snoozeOptions))
                    .font(.system(size: 12))
                    .foregroundStyle(TakeoverColors.hint)
                    .accessibilityLabel(TakeoverText.spokenHints(hasJoin: request.joinURL != nil,
                                                                 snoozeOptions: request.snoozeOptions))
            }
            .frame(maxWidth: 560)
            .padding(32)
            snoozeShortcuts
        }
        .preferredColorScheme(.dark)
        .onAppear { focus = request.joinURL != nil ? .join : .dismiss }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if let url = request.joinURL {
                Button(action: onJoin) {
                    Label("Join", systemImage: "video.fill")
                }
                .buttonStyle(TakeoverButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)   // Return
                .focused($focus, equals: .join)
                .help(JoinLabel.text(for: url))
                .accessibilityLabel("Join meeting")
                .accessibilityHint(JoinLabel.text(for: url))
            }
            if !request.snoozeOptions.isEmpty {
                Menu {
                    ForEach(request.snoozeOptions, id: \.self) { seconds in
                        Button(TakeoverText.snoozeTitle(seconds)) { onSnooze(seconds) }
                    }
                } label: {
                    SnoozeChip()
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Snooze this reminder")
                .accessibilityLabel("Snooze")
            }
            Button("Dismiss", action: onDismiss)
                .buttonStyle(TakeoverButtonStyle(kind: .quiet))
                .keyboardShortcut(.cancelAction)   // Esc
                .focused($focus, equals: .dismiss)
                .help("Dismiss this reminder")
                .accessibilityLabel("Dismiss")
        }
    }

    /// Zero-size buttons that only carry keyboard shortcuts: 1, 5, 0 snooze; Return dismisses when there is no link.
    private var snoozeShortcuts: some View {
        ZStack {
            ForEach(request.snoozeOptions, id: \.self) { seconds in
                if let key = TakeoverText.snoozeKey(for: seconds)?.first {
                    Button("Snooze \(TakeoverText.snoozeTitle(seconds))") { onSnooze(seconds) }
                        .keyboardShortcut(KeyEquivalent(key), modifiers: [])
                }
            }
            if request.joinURL == nil {
                Button("Dismiss", action: onDismiss).keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// The takeover on every other display: a mirror of the countdown and title, no controls.
struct SecondaryOverlayView: View {
    let title: String
    let start: Date

    var body: some View {
        ZStack {
            TakeoverBackdrop()
            VStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                TakeoverCountdown(start: start, labelSize: 18, valueSize: 56, statusSize: 56)
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("Dismiss on your main display")
                    .font(.system(size: 14))
                    .foregroundStyle(TakeoverColors.muted)
            }
            .frame(maxWidth: 800)
            .padding(32)
        }
        .preferredColorScheme(.dark)
    }
}

/// "Starts in" + big clock, "Starting now" or "Started N min ago", refreshed every second.
struct TakeoverCountdown: View {
    let start: Date
    let labelSize: CGFloat
    let valueSize: CGFloat
    let statusSize: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(TakeoverText.headline(startsIn: start.timeIntervalSince(context.date)),
                    startsIn: start.timeIntervalSince(context.date))
        }
    }

    private func content(_ headline: TakeoverText.Headline, startsIn: TimeInterval) -> some View {
        let pulsing = headline.kind == .countdown && headline.tone == .urgent && !reduceMotion
        return VStack(spacing: 2) {
            if let label = headline.label {
                Text(label)
                    .font(.system(size: labelSize))
                    .foregroundStyle(TakeoverColors.muted)
            }
            Text(headline.value)
                .font(.system(size: headline.kind == .countdown ? valueSize : statusSize, weight: .medium).monospacedDigit())
                .foregroundStyle(TakeoverColors.headline(headline.tone))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .scaleEffect(pulsing && pulse ? 1.03 : 1.0)
                .animation(pulsing ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : .default, value: pulse)
        }
        .onChange(of: pulsing, initial: true) { _, active in pulse = active }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TakeoverText.spokenHeadline(startsIn: startsIn))
    }
}

/// Label of the Snooze menu: a secondary capsule with hover feedback (the menu supplies the pressed state).
private struct SnoozeChip: View {
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text("Snooze")
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .frame(minHeight: 40)
        .background(Capsule().fill(Color.white.opacity(hovering ? 0.18 : 0.10)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5))
        .contentShape(Capsule())
        .onHover { hovering = $0 }
    }
}

/// Capsule buttons for the takeover with hover and pressed feedback. All are at least 34 pt tall.
struct TakeoverButtonStyle: ButtonStyle {
    enum Kind { case primary, quiet }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(kind: kind, configuration: configuration)
    }

    struct StyledLabel: View {
        let kind: Kind
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            let pressed = configuration.isPressed
            switch kind {
            case .primary:
                configuration.label
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TakeoverColors.onBlue)
                    .padding(.horizontal, 30)
                    .frame(minHeight: 46)
                    .background(Capsule().fill(TakeoverColors.blue.opacity(pressed ? 0.75 : (hovering ? 0.92 : 1))))
                    .scaleEffect(pressed ? 0.98 : 1)
                    .onHover { hovering = $0 }
            case .quiet:
                configuration.label
                    .font(.system(size: 15))
                    .foregroundStyle(hovering || pressed ? Color.white.opacity(0.9) : TakeoverColors.muted)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .contentShape(Rectangle())
                    .onHover { hovering = $0 }
            }
        }
    }
}
