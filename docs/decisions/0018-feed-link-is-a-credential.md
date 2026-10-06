# ADR 0018: A calendar feed link is a credential, and only the link is supported

**Status:** Accepted

## Context

Meetup's API needs a paid Pro subscription, but its Add to calendar menu offers private subscription links for the events a member has RSVP'd to. Such a link answers without any sign-in (checked 2026-10-05: `200 text/calendar`, no cookies), so possession of the link is the access. Other services (a Google secret address, an Outlook published calendar) work the same way. We first designed importing a downloaded `.ics` file as well, then dropped it: a downloaded file is a one-time copy of what the link serves and would go stale.

## Decision

- **One connector kind, `icalsub`, takes only a subscription link.** No file import and no Meetup-specific kind; Meetup appears as an example in the help text.
- **The link is stored like a password**: in the Keychain through `CredentialStore`, entered in a masked field, kept out of `Connection.config`, display names, logs and error messages. The connection keeps only the host.
- **A link the provider no longer honors (401, 403, 404, 410) is `authExpired`**, so the app asks for a new link through the existing sign-in-again flow. A temporary 404 from a provider can cause one needless prompt; that is accepted.
- **Redirects are followed by the library, only to `https`**, so a feed cannot send the link on to a plain-HTTP address.

- **A retention window limits what is kept**: the library default keeps everything, TimeTug keeps 1 day back and 7 days ahead for one-off events, and change detection ignores the rest.

## Consequences

- The privacy policy states that the link is a private address, where it is kept, and that nothing is written back.
- Anyone who holds the link can read the feed; the user revokes it at the provider.
- Writes and RSVP changes are out of reach for a feed; the source is read-only.
