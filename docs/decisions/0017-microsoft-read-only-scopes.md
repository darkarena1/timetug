# ADR 0017: Microsoft sign-in asks for read-only calendar permissions

**Status:** Accepted

## Context

The Microsoft connector (ADR 0012) first requested `Calendars.ReadWrite` and `Calendars.ReadWrite.Shared` so the
library's write API would work against Microsoft. The app does not write events: nothing in `Apps/macOS` calls the write
API, and the privacy policy describes TimeTug as reading calendars. Asking for edit rights the app never uses is more
access than the feature needs, and it is harder to justify on the consent screen and in the privacy policy. Google's
connector already asks only for read-only scopes.

## Decision

- **Request `Calendars.Read` and `Calendars.Read.Shared`** in place of the `ReadWrite` pair. `offline_access`,
  `User.Read` and `MailboxSettings.Read` are unchanged.
- **The write code stays in the library.** With read-only scopes its calls fail with a 403 from Graph, which is the
  honest result. The source's `capabilities` still say `canWrite`; a host that shows edit controls must not offer them
  for a Microsoft account until the scopes are widened.
- **Widening later** is a change to `MicrosoftConnectorKind.scopes` plus the Entra registration, and existing accounts
  must sign in again to grant it (a new consent, like any scope increase). That ships with the feature that needs it.
- **Existing sign-ins keep working.** A token issued under the old scopes still holds the edit grant until the user
  revokes it in their Microsoft account or signs in again; the app simply never uses it.

## Consequences

- The Entra app registration should list the same delegated permissions (`Calendars.Read`, `Calendars.Read.Shared`), and
  the `ReadWrite` pair should be removed (`docs/release.md` and the Phase 4 spec).
- The privacy policy states Microsoft's read-only permissions.
