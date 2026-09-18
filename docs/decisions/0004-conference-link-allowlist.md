# ADR 0004: Conference Link Provider Allowlist

**Status:** Accepted

## Context

Events often include join links in location, URL, or notes fields. A "Join" button must open only real video-conference endpoints, not Google Docs, shared spreadsheets, or other URLs the organizer happened to attach. The detector must also unwrap redirect links (Outlook SafeLinks, Google Analytics redirects) to find the real target.

## Decision

Use a known-provider allowlist, not any URL:
- **Allowlisted providers:** Zoom (`zoom.us`, `zoom.com`, `zoommtg://`), Google Meet (`meet.google.com`), Microsoft Teams (`teams.microsoft.com`, `teams.live.com`), Webex (`webex.com`), GoToMeeting (`gotomeet.me`, `gotomeeting.com`), Whereby (`whereby.com`), Jitsi (`meet.jit.si`), Slack huddles (`app.slack.com/huddle`).
- **Fallback:** If no allowlisted link is found but the event's own `url` field is an http(s) link, offer it as Join. (The invite author put it on purpose; we respect that over our allowlist.)
- **Unwrapping:** Strip Outlook SafeLinks and Google redirects (up to 3 layers deep) to expose the real link.
- **Out of scope (v1):** Dial-in numbers are ignored; conference data from Google Calendar (structured `conferenceData` field) is parsed separately by `EventKitSource` and stored directly in `conferenceURL`.

Provider list lives in `ConferenceLinkDetector.providers` as data, not logic, so it is easy to extend and document.

Rejected alternative: "Any URL" would require a Join button that opens a Google Doc or shared screenshot, defeating the purpose and creating security confusion.

## Consequences

**Advantages:**
- Users can trust the Join button; it never opens a random URL.
- Simple to extend with new providers; no code changes needed.
- Unwrapping handles real-world email wrapping; links are robust to corporate security tools.

**Trade-off:** New providers require a code update. Mitigation: the list is stable (most orgs use the top 5); future sub-projects will add Google and Exchange sources with their own structured link fields, reducing reliance on text parsing.

The fallback `url` field respects the event author's intent while keeping the join action safe.
