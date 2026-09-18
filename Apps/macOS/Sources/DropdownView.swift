import AppKit
import SwiftUI
import TimeTugCore

/// The left-click popup: problems, header, today's cards, lead-time footer. Sizes to its content.
struct DropdownView: View {
    @ObservedObject var model: AppModel
    let onOpenSettings: () -> Void
    let onJoin: (URL) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var listHeight: CGFloat = 0
    @State private var chromeHeight: CGFloat = 0

    private var palette: PopupPalette { PopupPalette(scheme) }

    private var cardStyle: PopupCardStyle {
        if reduceTransparency || contrast == .increased { return .solid }
        return PopupCardStyle.available.contains(model.popupCardStyle) ? model.popupCardStyle : PopupCardStyle.defaultStyle
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .frame(width: PopupStyle.width)
        .background {
            if PopupStyle.usesSolidBackground { palette.surface.ignoresSafeArea() }
        }
    }

    private func content(now: Date) -> some View {
        let rows = PopupRowModel.rows(agenda: model.agenda, calendars: model.calendars, now: now)
        let left = PopupRowModel.meetingsLeft(agenda: model.agenda)
        let totalTimed = model.agenda.items.filter { !$0.event.isAllDay }.count
        let listMax = max(120, PopupStyle.maxHeight - chromeHeight)

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if !problems.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(problems, id: \.sourceID) {
                            ProblemRow(message: $0.message, showsPrivacyLink: $0.status == .needsPermission)
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 12)
                }
                header(now: now, meetingsLeft: left, totalTimed: totalTimed)
            }
            .measureHeight { chrome in chromeHeight = chrome + footerHeight }

            if rows.isEmpty {
                EmptyState()
            } else {
                if left == 0 { NoMoreMeetings() }
                ScrollView {
                    CardGroup(style: cardStyle) {
                        VStack(spacing: 8) {
                            ForEach(Array(zip(rows, model.agenda.items)), id: \.0.id) { row, item in
                                EventCard(row: row, event: item.event, now: now,
                                          calendarTitle: calendarTitle(for: item.event),
                                          palette: palette, style: cardStyle,
                                          strongBorder: contrast == .increased, onJoin: onJoin)
                            }
                        }
                    }
                    .animation(reduceMotion ? nil : .snappy, value: rows)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .measureHeight { listHeight = $0 }
                }
                .scrollIndicators(.automatic)
                .frame(height: min(listHeight, listMax))
            }

            Text(PopupText.tugFooter(leadTime: model.leadTime))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(height: 16)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
        }
    }

    /// Footer text height (16) plus its vertical padding (8 + 12).
    private var footerHeight: CGFloat { 36 }

    private func header(now: Date, meetingsLeft: Int, totalTimed: Int) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(PopupText.weekday(now: now)).font(.system(size: 15, weight: .medium))
                Text(PopupText.summary(now: now, meetingsLeft: meetingsLeft, totalTimed: totalTimed))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            GearButton(action: onOpenSettings)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    private func calendarTitle(for event: CalendarEvent) -> String? {
        model.calendars.first { $0.key == event.calendarKey }?.title
    }

    private struct Problem { let sourceID: String; let status: SourceStatus; let message: String }

    private var problems: [Problem] {
        model.statuses.compactMap { sourceID, status in
            let name = model.sourceNames[sourceID] ?? sourceID
            switch status {
            case .ok: return nil
            case .needsPermission: return Problem(sourceID: sourceID, status: status, message: "\(name) access denied")
            case .authExpired: return Problem(sourceID: sourceID, status: status, message: "\(name) needs you to sign in again")
            case .failing(let reason): return Problem(sourceID: sourceID, status: status, message: "\(name) failed: \(reason)")
            }
        }
        .sorted { $0.sourceID < $1.sourceID }
    }
}

// MARK: - Height measuring

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private extension View {
    /// Reports the view's laid-out height.
    func measureHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
            .onPreferenceChange(HeightKey.self) { h in
                DispatchQueue.main.async { onChange(h) }
            }
    }
}

// MARK: - Pieces

private struct ProblemRow: View {
    let message: String
    let showsPrivacyLink: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
            Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if showsPrivacyLink {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("No meetings today").font(.system(size: 16, weight: .medium))
            Text("Enjoy the quiet.").font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .accessibilityElement(children: .combine)
    }
}

private struct NoMoreMeetings: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 16, height: 16).accessibilityHidden(true)
            Text("No more meetings today. Nice.").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }
}

private struct EventCard: View {
    let row: PopupRowModel
    let event: CalendarEvent
    let now: Date
    let calendarTitle: String?
    let palette: PopupPalette
    let style: PopupCardStyle
    let strongBorder: Bool
    let onJoin: (URL) -> Void

    private var isPast: Bool { row.kind == .past }
    private var isNext: Bool { row.kind == .next }
    /// Fixed brand text colors only on the opaque style; glass and material use semantic colors.
    private var titleColor: Color {
        style == .solid ? (isPast ? palette.secondary : palette.primary) : (isPast ? .secondary : .primary)
    }
    private var secondaryColor: Color { style == .solid ? palette.secondary : .secondary }
    private var barColor: Color { Color(hex: row.colorHex) ?? palette.blue }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(row.timeText)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(secondaryColor)
                    .frame(width: 52, alignment: .trailing)
                    .padding(.top, 1)
                Capsule().fill(barColor).frame(width: 4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                        if row.kind == .current { Pill(text: "Now", fg: palette.pillText, bg: palette.pillBackground) }
                        if isNext {
                            Pill(text: PopupText.countdown(until: row.start, now: now),
                                 fg: palette.chipText, bg: palette.chipBackground)
                        }
                        Spacer(minLength: 0)
                    }
                    Text(row.metaText)
                        .font(.system(size: 12)).foregroundStyle(secondaryColor).lineLimit(1)
                    if row.kind == .current {
                        ProgressBar(fraction: PopupText.progress(start: row.start, end: row.end, now: now), palette: palette)
                            .padding(.top, 4)
                    }
                }
                if row.kind == .current || isNext, let url = row.joinURL {
                    // Same compact button for the meeting in progress and the next one; the provider
                    // name ("Join Zoom") is in the tooltip and the VoiceOver label.
                    JoinButton(title: "Join", url: url, eventTitle: row.title, fullWidth: false, palette: palette, onJoin: onJoin)
                        .help(JoinLabel.text(for: url))
                        .accessibilityHint(JoinLabel.text(for: url))
                }
            }
        }
        .padding(12)
        .modifier(CardSurface(style: style, isNext: isNext, palette: palette, strongBorder: strongBorder))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [row.title]
        if row.kind == .allDay {
            parts.append("all day")
        } else {
            let r = PopupText.range(row.start, row.end).replacingOccurrences(of: " – ", with: " to ")
            parts.append(r)
        }
        if isNext { parts.append("in " + PopupText.spokenDuration(row.start.timeIntervalSince(now))) }
        if row.kind == .current { parts.append("in progress") }
        if isPast { parts.append("finished") }
        if let calendarTitle { parts.append("\(calendarTitle) calendar") }
        return parts.joined(separator: ", ")
    }
}

private struct Pill: View {
    let text: String, fg: Color, bg: Color
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(bg, in: Capsule())
            .fixedSize()
    }
}

private struct ProgressBar: View {
    let fraction: Double
    let palette: PopupPalette
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.progressTrack)
                Capsule().fill(palette.blue).frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

private struct JoinButton: View {
    let title: String
    let url: URL
    let eventTitle: String
    let fullWidth: Bool
    let palette: PopupPalette
    let onJoin: (URL) -> Void

    var body: some View {
        Button { onJoin(url) } label: {
            HStack(spacing: 5) {
                Image(systemName: "video.fill").font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(palette.joinText)
            .padding(.horizontal, 12)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: fullWidth ? 32 : 28)
            .background(palette.blue, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Join \(eventTitle)")
    }
}

// MARK: - Card surface

/// The card's chrome for each style. `glass` is native Liquid Glass; `frosted` is a thin material with a
/// hairline; `solid` is the opaque brand fill.
private struct CardSurface: ViewModifier {
    let style: PopupCardStyle
    let isNext: Bool
    let palette: PopupPalette
    let strongBorder: Bool
    @Environment(\.colorScheme) private var scheme

    private static let radius: CGFloat = 20
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Self.radius, style: .continuous) }

    @ViewBuilder func body(content: Content) -> some View {
        switch style {
        case .glass:
            if #available(macOS 26.0, *) {
                content.glassEffect(isNext ? .regular.tint(palette.blue.opacity(0.35)) : .regular, in: shape)
            } else {
                frosted(content)
            }
        case .frosted:
            frosted(content)
        case .solid:
            content
                .background(isNext ? palette.blue.opacity(0.07) : Color.clear, in: shape)
                .background(palette.cardFill, in: shape)
                .overlay(shape.strokeBorder(isNext ? palette.blue : palette.cardBorder,
                                            lineWidth: isNext ? 1 : (strongBorder ? 1.5 : 0.5)))
        }
    }

    private func frosted(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(isNext ? shape.fill(palette.blue.opacity(0.16)) : nil)
            .overlay(shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.06), lineWidth: 0.5))
            .overlay(isNext ? shape.strokeBorder(palette.blue, lineWidth: 1) : nil)
    }
}

/// Lets neighbouring glass cards blend (macOS 26+); a plain pass-through otherwise.
private struct CardGroup<Content: View>: View {
    let style: PopupCardStyle
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *), style == .glass {
            GlassEffectContainer(spacing: 8) { content }
        } else {
            content
        }
    }
}

// MARK: - Buttons

/// Hover and pressed feedback for the solid Join capsule.
private struct PressableStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.1 : (hovering ? 0.08 : 0))
            .onHover { hovering = $0 }
    }
}

/// Header gear: a glass button on macOS 26+ (it sits on the popover, not inside a card), a tinted fill before.
private struct GearButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        if #available(macOS 26.0, *) {
            Button(action: action) {
                Image(systemName: "gearshape").font(.system(size: 13)).frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Settings")
        } else {
            Button(action: action) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(hovering ? 0.26 : 0.16), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityLabel("Settings")
        }
    }
}
