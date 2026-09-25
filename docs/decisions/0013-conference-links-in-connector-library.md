# ADR 0013: Conference links live in the connector library

**Status:** Accepted. Partly supersedes ADR 0004 (its "Out of scope" section and the EventKit sentence).

## Context

Conference links were found in four places with different answers: the Google connector (structured `conferenceData` and `hangoutLink` only, with its own host checks), the EventKit connector (never), and TimeTug Core (three separate uses of `ConferenceLinkDetector`). Other apps using the library got no links from EventKit, an ICS-imported Google event with a Teams link only in its description got none either, and every path reduced the answer to one URL, dropping the rest.

## Decision

- One detector, `ConferenceDetector`, in `CalendarCore`. It keeps ADR 0004's allowlist, redirect unwrapping and permalink exclusion, and is the only place that maps a host to a `ConferenceProvider` (`meet, teams, zoom, webex, goToMeeting, whereby, jitsi, slack, other`).
- `CalendarEvent.conferences` is an ordered list of `ConferenceInfo` (`url`, `provider`, `origin`, computed `identity`), most likely first: the provider's structured links, then every allowlisted link in location, url and notes, duplicates removed by `identity`. `conference` is the first entry. `origin` (`structured, location, url, notes, eventURL`) says where a link came from.
- The event's own web `url` becomes the last-ranked entry, origin `.eventURL`, only when nothing else was found.
- Every connector fills the list: Google from all video entry points, `hangoutLink` and the description; EventKit from location, url and notes. TimeTug only consumes it: no detection in Core.
- Duplicate detection merges two events that share any link (by `identity`), and keeps them apart when both have links and none is shared. `.eventURL` entries never identify a meeting. The merged event's list is the primary's links, then the others', deduplicated, with recognised providers first.
- No UI change: Join uses the first link.
- `providesConference` stays until Issue 2 replaces it with a provided-fields declaration.

## Consequences

- Portable: `ConferenceDetector` uses only Foundation (`NSRegularExpression` is in corelibs), so the Linux job covers it.
- Dial-in numbers are still ignored.
- Adding a provider means adding one row to `ConferenceDetector.providers`.
