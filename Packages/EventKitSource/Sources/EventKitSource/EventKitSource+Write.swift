import CalendarCore
import EventKit
import Foundation

// Several behaviours below rest on EventKit facts that the Task 1 spike has not confirmed yet (marked "Unverified"):
// how occurrences of a series share `eventIdentifier`, what `.futureEvents` does on a series' first occurrence,
// whether `refresh()` reports a deleted event, and whether `lastModifiedDate` changes on every save. The live tests
// in EventKitLiveWriteTests.swift check them: `TIMETUG_LIVE_EVENTKIT=1 swift test --package-path Packages/EventKitSource --filter eventKit`.
extension EventKitSource: WritableCalendarSource {
    public func create(_ draft: EventDraft, in calendarID: String, notify: NotifyPolicy) async throws -> CalendarEvent {
        // Everything that does not need the store comes first: a malformed recurrence rule crashes EventKit with an
        // NSException, so it must never reach the mapping.
        try draft.validate()
        try WriteValidation.requireWritable(draft.usedFields, capabilities)
        let alarms = try draft.reminders.map(EventKitWriteMapping.alarms)   // before the store is touched
        try requireAccess()
        try EventKitWriteMapping.checkNotify(notify, hasOtherAttendees: false)
        let calendar = try writableCalendar(calendarID)
        if let uid = draft.uid, !uid.isEmpty {
            let window = EventKitWriteMapping.duplicateSearchWindow(for: draft.timing)
            let candidates = store.events(matching: store.predicateForEvents(withStart: window.start, end: window.end, calendars: [calendar]))
            if let index = EventKitWriteMapping.matchingIndex(uid: uid, candidates: candidates.map { ($0.calendarItemExternalIdentifier, $0.status == .canceled) }) {
                throw WriteError.alreadyExists(map(candidates[index]))
            }
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = draft.title
        event.notes = draft.notes
        event.location = draft.location
        applyTiming(draft.timing, to: event)
        setAvailability(draft.availability, on: event, in: calendar)
        if let alarms { event.alarms = alarms }
        if let rule = draft.recurrence { event.addRecurrenceRule(EventKitWriteMapping.recurrenceRule(rule)) }
        try save(event, span: .thisEvent)
        return map(reload(event, isSeries: draft.recurrence != nil))
    }

    /// Callers read expanded occurrences, so a `timing` in `patch` is the occurrence's absolute date. A series-wide
    /// (`.allInSeries`) write starts from the first occurrence, so a time change is accepted only when `ref` is that
    /// first occurrence; otherwise it throws `WriteError.unsupported(fields: [.timing])` before any save.
    public func update(_ ref: EventRef, _ patch: EventPatch, scope: RecurrenceScope, notify: NotifyPolicy) async throws -> CalendarEvent {
        try WriteValidation.requireWritable(patch.touchedFields, capabilities)
        try Self.validate(patch)
        // A rule belongs to the whole series: on one occurrence the store would take it as a change to the series or drop
        // it, so it is refused up front (Google refuses it too).
        if scope == .thisInstance, ref.seriesID != nil, patch.recurrence != .keep { throw WriteError.unsupported(fields: [.recurrence]) }
        try requireAccess()
        let target = try locateTarget(ref, scope: scope)
        if patch.isEmpty { return patch.base ?? map(target.event) }
        try requireModifiable(target.event)
        if scope == .allInSeries, patch.timing != nil, ref.seriesID != nil {
            // Unverified: the event fetched by identifier is the series' first occurrence.
            guard let original = ref.originalStart, let slot = target.event.occurrenceDate,
                  abs(slot.timeIntervalSince(original)) < 1 else {
                throw WriteError.unsupported(fields: [.timing])
            }
        }
        try EventKitWriteMapping.checkNotify(notify, hasOtherAttendees: hasOtherAttendees(target.event))
        // An occurrence's modification date does not describe the whole series, so a series-wide write has no lock.
        let version = scope == .allInSeries && ref.seriesID != nil ? nil : ref.version
        return try await PatchMerge.apply(
            patch: patch, version: version,
            fetchCurrent: { self.map(try self.locateTarget(ref, scope: scope).event) },
            write: { expected -> PatchMerge.Attempt<CalendarEvent> in
                let current = try self.locateTarget(ref, scope: scope)
                // Unverified: `lastModifiedDate` changes on every save, and `refresh()` (in `locate`) makes it current.
                if let expected, expected != EventKitWriteMapping.version(current.event.lastModifiedDate) { return .stale }
                try self.apply(patch, to: current.event)
                do { try self.save(current.event, span: current.span) }
                catch {
                    // The in-memory event already carries the edit; discard it so a failed save leaves nothing
                    // pending on the (possibly shared) store object. `rollback()` unloads the dirty state, whereas
                    // `refresh()` keeps unsaved edits (it only unloads properties that have not been modified).
                    current.event.rollback()
                    throw error
                }
                return .done(self.map(self.reload(current.event, isSeries: ref.seriesID != nil)))
            })
    }

    public func delete(_ ref: EventRef, scope: RecurrenceScope, notify: NotifyPolicy) async throws {
        try requireAccess()
        let target = try locateTarget(ref, scope: scope)
        try requireModifiable(target.event)
        try EventKitWriteMapping.checkNotify(notify, hasOtherAttendees: hasOtherAttendees(target.event))
        do { try store.remove(target.event, span: target.span, commit: true) }
        catch { throw WriteError.invalid(error.localizedDescription) }
    }

    /// EventKit does not let apps change a response.
    public func respond(to ref: EventRef, _ response: ResponseStatus, scope: RecurrenceScope, notify: NotifyPolicy) async throws -> CalendarEvent {
        throw WriteError.unsupported(fields: [.attendees])
    }

    // MARK: Helpers

    /// The checks a patch needs before any store access. `patch.timing` is covered by `EventTiming.validate()`, but a
    /// recurrence rule and reminders are not (an invalid rule would crash EventKit).
    private static func validate(_ patch: EventPatch) throws {
        try patch.timing?.validate()
        if case .set(let rule) = patch.recurrence { try rule.validate() }
        if case .set(let reminders) = patch.reminders {
            if reminders.contains(where: { if case .relative(let offset, _) = $0.trigger { offset > 0 } else { false } }) {
                throw WriteError.invalid("reminder minutes must not be negative")
            }
            _ = try EventKitWriteMapping.alarms(reminders)   // refuses what EventKit cannot write before the store is touched
        }
    }

    private func writableCalendar(_ id: String) throws -> EKCalendar {
        guard let calendar = store.calendar(withIdentifier: id) else { throw WriteError.notFound }
        guard calendar.allowsContentModifications else { throw WriteError.forbidden("read-only calendar") }
        return calendar
    }

    /// The event as stored after a save, so the returned `version` is the stored modification date. A series edit can
    /// re-identify the occurrences after it, so a series event is returned as saved.
    private func reload(_ event: EKEvent, isSeries: Bool) -> EKEvent {
        guard !isSeries, let id = event.eventIdentifier, let stored = store.event(withIdentifier: id) else { return event }
        return stored
    }

    private func hasOtherAttendees(_ event: EKEvent) -> Bool {
        (event.attendees ?? []).contains { !$0.isCurrentUser }
    }

    private func save(_ event: EKEvent, span: EKSpan) throws {
        do { try store.save(event, span: span, commit: true) }
        catch { throw WriteError.invalid(error.localizedDescription) }
    }

    /// The closest value the calendar accepts (`Availability.closest`); a calendar that tracks none is left alone.
    private func setAvailability(_ availability: Availability, on event: EKEvent, in calendar: EKCalendar) {
        let supported = EventKitMapping.supportedAvailabilities(calendar.supportedEventAvailabilities)
        if let value = availability.closest(in: supported) { event.availability = EventKitMapping.eventAvailability(value) }
    }

    private func requireModifiable(_ event: EKEvent) throws {
        guard event.calendar?.allowsContentModifications == true else { throw WriteError.forbidden("read-only calendar") }
    }

    /// The occurrence a ref designates, in the ref's calendar. A recurring occurrence is found through a date-range
    /// predicate around its `originalStart` (wide, because the predicate matches an occurrence's actual dates and
    /// it may have been moved) and matched on `seriesID` (the shared `eventIdentifier`) and `occurrenceDate` (Unverified: occurrences share
    /// an identifier; `eventID` carries a per-occurrence suffix). A deleted event, one in another calendar, or one `refresh()` reports as gone (Unverified) is
    /// `.notFound`.
    private func locate(_ ref: EventRef) throws -> EKEvent {
        var found: EKEvent?
        if ref.seriesID != nil {
            guard let original = ref.originalStart else { throw WriteError.invalid("a recurring occurrence needs its original start") }
            guard let calendar = store.calendar(withIdentifier: ref.calendarID) else { throw WriteError.notFound }
            let window = EventKitWriteMapping.occurrenceSearchWindow(around: original)
            let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: [calendar])
            found = store.events(matching: predicate).first { event in
                EventKitWriteMapping.isOccurrence(ref, eventIdentifier: event.eventIdentifier, occurrenceDate: event.occurrenceDate)
            }
        } else {
            found = store.event(withIdentifier: ref.eventID)
        }
        guard let event = found, event.calendar?.calendarIdentifier == ref.calendarID, event.refresh() else { throw WriteError.notFound }
        return event
    }

    /// The event to change and the span to save it with. `.allInSeries` starts from the series' first occurrence and
    /// saves with `.futureEvents`, which edits every occurrence (Unverified).
    private func locateTarget(_ ref: EventRef, scope: RecurrenceScope) throws -> (event: EKEvent, span: EKSpan) {
        guard ref.seriesID != nil else { return (try locate(ref), .thisEvent) }
        if scope == .allInSeries {
            guard let seriesID = ref.seriesID, let first = store.event(withIdentifier: seriesID), first.calendar?.calendarIdentifier == ref.calendarID,
                  first.refresh() else { throw WriteError.notFound }
            return (first, .futureEvents)
        }
        return (try locate(ref), EventKitWriteMapping.span(for: scope))
    }

    private func applyTiming(_ timing: EventTiming, to event: EKEvent) {
        if timing.isAllDay, let floating = EventKitWriteMapping.floatingAllDay(timing, calendar: Calendar.current) {
            event.isAllDay = true
            event.startDate = floating.start
            event.endDate = floating.end
        } else {
            event.isAllDay = false
            event.startDate = timing.start
            event.endDate = timing.end
            event.timeZone = timing.timeZone
        }
    }

    private func apply(_ patch: EventPatch, to event: EKEvent) throws {
        if let title = patch.title { event.title = title }
        switch patch.notes { case .keep: break; case .set(let value): event.notes = value; case .clear: event.notes = nil }
        switch patch.location { case .keep: break; case .set(let value): event.location = value; case .clear: event.location = nil }
        if let timing = patch.timing { applyTiming(timing, to: event) }
        if let availability = patch.availability, let calendar = event.calendar { setAvailability(availability, on: event, in: calendar) }
        switch patch.reminders {
        case .keep: break
        case .set(let list): event.alarms = try EventKitWriteMapping.alarms(list)
        case .clear: event.alarms = nil
        }
        switch patch.recurrence {
        case .keep: break
        case .clear: event.recurrenceRules?.forEach(event.removeRecurrenceRule)
        case .set(let rule):
            event.recurrenceRules?.forEach(event.removeRecurrenceRule)
            event.addRecurrenceRule(EventKitWriteMapping.recurrenceRule(rule))
        }
    }
}
