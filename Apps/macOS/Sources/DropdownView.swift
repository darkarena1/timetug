import AppKit
import SwiftUI
import TimeTugCore

/// The left-click popup: problems, header, today's cards, lead-time footer. Sizes to its content.
struct DropdownView: View {
    @ObservedObject var model: AppModel
    let onOpenSettings: () -> Void
    let onJoin: (URL) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var listHeight: CGFloat = 0
    @State private var chromeHeight: CGFloat = 0

    private var palette: PopupPalette { PopupPalette(scheme) }

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
                    VStack(spacing: 6) {
                        ForEach(Array(zip(rows, model.agenda.items)), id: \.0.id) { row, item in
                            EventCard(row: row, event: item.event, now: now,
                                      calendarTitle: calendarTitle(for: item.event),
                                      palette: palette, onJoin: onJoin)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 2)
                    .measureHeight { listHeight = $0 }
                }
                .scrollIndicators(.automatic)
                .frame(height: min(listHeight, listMax))
            }

            Text(PopupText.tugFooter(leadTime: model.leadTime))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(height: 16)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        }
    }

    /// Footer text height (16) plus its vertical padding (8 + 10).
    private var footerHeight: CGFloat { 34 }

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
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 28, height: 28)
                    .background(Color.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
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
    let onJoin: (URL) -> Void

    private var isPast: Bool { row.kind == .past }
    private var isNext: Bool { row.kind == .next }
    private var textColor: Color { isPast ? palette.secondary : palette.primary }
    private var barColor: Color { Color(hex: row.colorHex) ?? palette.blue }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(row.timeText)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(palette.secondary)
                    .frame(width: 52, alignment: .trailing)
                    .padding(.top, 2)
                RoundedRectangle(cornerRadius: 1.5).fill(barColor).frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(textColor)
                            .lineLimit(1)
                        if row.kind == .current { Pill(text: "Now", fg: palette.pillText, bg: palette.pillBackground) }
                        if isNext {
                            Pill(text: PopupText.countdown(until: row.start, now: now),
                                 fg: palette.chipText, bg: palette.chipBackground)
                        }
                        Spacer(minLength: 0)
                    }
                    Text(row.metaText)
                        .font(.system(size: 12)).foregroundStyle(palette.secondary).lineLimit(1)
                    if row.kind == .current {
                        ProgressBar(fraction: PopupText.progress(start: row.start, end: row.end, now: now), palette: palette)
                            .padding(.top, 4)
                    }
                }
                if row.kind == .current, let url = row.joinURL {
                    JoinButton(title: "Join", url: url, eventTitle: row.title, fullWidth: false, palette: palette, onJoin: onJoin)
                }
            }
            if isNext, let url = row.joinURL {
                JoinButton(title: JoinLabel.text(for: url), url: url, eventTitle: row.title, fullWidth: true, palette: palette, onJoin: onJoin)
            }
        }
        .padding(10)
        .background(isNext ? palette.blue.opacity(0.07) : Color.clear)
        .background(palette.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isNext ? palette.blue : palette.cardBorder, lineWidth: isNext ? 1 : 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .padding(.horizontal, 7).padding(.vertical, 1.5)
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
            .frame(height: fullWidth ? 30 : 28)
            .background(palette.blue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Join \(eventTitle)")
    }
}
