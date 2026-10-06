import CalendarCore

enum AccountNoticeText {
    /// The tooltip and accessibility text for an account's warning icon, or nil when there is nothing to warn about.
    static func make(_ notices: [SourceNotice]?) -> String? {
        let count = (notices ?? []).filter { $0.kind == .unreadableRecurrence }.reduce(0) { $0 + $1.count }
        switch count {
        case ...0: return nil
        case 1: return "Some repeating events from this link use a rule TimeTug can't read, so they may not appear."
        default: return "\(count) repeating events from this link use a rule TimeTug can't read, so they may not appear."
        }
    }
}
