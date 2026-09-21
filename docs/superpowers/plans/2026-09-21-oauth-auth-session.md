# OAuth sign-in in a system sheet (ASWebAuthenticationSession) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox syntax.

**Goal:** Google sign-in opens in Apple's secure web-authentication sheet inside TimeTug (passkeys and system autofill work; Safari cookies are shared) and the sheet closes itself when sign-in completes; the current default-browser flow stays as the fallback.

**Architecture:** Google requires a loopback redirect (`http://127.0.0.1:port`), which `ASWebAuthenticationSession` cannot intercept, so the existing loopback listener keeps receiving the real redirect. After it receives the code it answers with a `302` to a custom URL (`timetug-oauth://done`); the session catches that scheme and dismisses the sheet. A small presenter seam (`AuthorizationPresenting`) keeps `LoopbackSession` testable; the real presenter wraps `ASWebAuthenticationSession`. The library (`CalendarCore`, `GoogleCalendar`) is untouched: this is an optional Apple adapter in `CalendarApple`.

**Tech Stack:** Swift 5 mode in `CalendarApple` and the app, AuthenticationServices, AppKit, Swift Testing (package), XCTest (app).

## Global Constraints
- Library layering: OS-specific code lives only in `Packages/CalendarApple` (and the app composition root); `CalendarCore`/`GoogleCalendar` must not change.
- `prefersEphemeralWebBrowserSession = false` (share Safari's sessions, passkeys and autofill).
- The fallback (present fails to start, or no presenter supplied) is exactly today's behaviour: `openURL` (NSWorkspace) and the plain "You're signed in" 200 page. The `302` is sent only when a presenter actually started a session.
- User cancelling the sheet must end the flow promptly with `LoopbackError.cancelled` (not wait for the 300 s timeout), and the flow ending any other way must dismiss the sheet.
- Never print or log OAuth codes, tokens or client values. Never run `pkill -x TimeTug`.
- New behaviour gets a failing Swift Testing test first. Commit messages end with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`. Land through a PR into `master`; do not merge.

---

## Task 1: Presenter seam and 302 completion in the loopback session

**Files:**
- Modify: `Packages/CalendarApple/Sources/CalendarApple/LoopbackAuthorizationInteraction.swift`
- Test: `Packages/CalendarApple/Tests/CalendarAppleTests/LoopbackTests.swift` (extend; read the existing tests first and reuse their way of hitting the listener)

**Interfaces (produces):**

```swift
/// Shows the authorization page to the user in a window the host controls.
public protocol AuthorizationPresenting: Sendable {
    /// Presents `url`. Returns false when it could not start (the caller then falls back to the browser).
    /// `onEnded` is called at most once when the presentation ends without the host having seen the
    /// redirect: `nil` when the completion URL (scheme `completionScheme`) was reached, an error when the
    /// user cancelled or it failed.
    func present(_ url: URL, completionScheme: String, onEnded: @escaping @Sendable (Error?) -> Void) async -> Bool
    /// Dismisses the presentation if it is still showing.
    func dismiss() async
}
```

`LoopbackAuthorizationInteraction.init(openURL:promptCredentials:presenter:completionScheme:timeout:)` gains `presenter: (any AuthorizationPresenting)? = nil` and `completionScheme: String = "timetug-oauth"` (keep existing labels and defaults so current call sites and tests compile unchanged).

- [ ] **Step 1: Failing tests** (add to `LoopbackTests.swift`, adapting to the file's helpers):
  1. With a fake presenter whose `present` returns true and simulates the browser by making an HTTP GET to `<redirectURI>/?code=abc&state=xyz` (using `session.redirectURI`), `authorize` returns that redirect URL and the raw HTTP response the fake sees is a `302` whose `Location` is `timetug-oauth://done` (assert status and header; do not follow the redirect).
  2. With a fake presenter that calls `onEnded(CancellationError())` (user cancelled) and never hits the listener, `authorize` throws `LoopbackError.cancelled` well before the timeout (use a short timeout and assert it is not `.timedOut`).
  3. With a fake presenter returning false from `present`, `authorize` falls back to `openURL` (a recording closure), and the listener's response for the simulated GET is the existing 200 page, not a 302.
  4. `close()` calls the presenter's `dismiss()` exactly once (also when the flow already finished).
  5. `onEnded(nil)` (the sheet reached the completion URL) after the redirect was delivered does not change the result.
  Run `swift test --package-path Packages/CalendarApple --filter Loopback`: expect FAIL (does not compile / assertions).
- [ ] **Step 2: Implement.**
  - Add the protocol above (public, in the same file or a new `AuthorizationPresenting.swift` in the same folder).
  - `LoopbackSession` gets `presenter`, `completionScheme` and a lock-protected `completionRedirect: URL?` set to `URL(string: "\(completionScheme)://done")` only after `present` returned true.
  - `authorize(at:)`: if a presenter exists, call `present(url, completionScheme:, onEnded:)` where `onEnded` delivers `.failure(LoopbackError.cancelled)` for a non-nil error and does nothing for nil; if it returns true set `completionRedirect`; if false (or no presenter) call `openURL` exactly as today and throw `couldNotOpenBrowser` if that fails. Set `completionRedirect` BEFORE the sheet can hit the listener (i.e. before calling `present`, clear it again if `present` returns false); a request that arrives while it is set gets the 302.
  - `respond(on:redirect:)`: when a redirect URL was parsed and `completionRedirect` is set, send `HTTP/1.1 302 Found\r\nLocation: <completionRedirect>\r\nContent-Length: 0\r\nConnection: close\r\n\r\n`; otherwise the existing 200/404 behaviour.
  - `close()`: call `await presenter?.dismiss()` in addition to today's cleanup; keep it safe to call twice.
- [ ] **Step 3: Run** the filtered tests (PASS) and then `swift test --package-path Packages/CalendarApple` (all pass; report counts).
- [ ] **Step 4: Commit** (`feat(apple): loopback session can present sign-in through a host presenter`).

## Task 2: ASWebAuthenticationSession presenter and app wiring

**Files:**
- Create: `Packages/CalendarApple/Sources/CalendarApple/WebAuthenticationSessionPresenter.swift`
- Modify: `Packages/CalendarApple/Package.swift` (only if a framework dependency is needed; system frameworks need none), `Apps/macOS/Sources/AppConnectors.swift` and/or where `LoopbackAuthorizationInteraction` is constructed (find with `grep -rn "LoopbackAuthorizationInteraction(" Apps`)
- Test: compile-level in the package; app tests must still pass

**Interfaces (consumes):** `AuthorizationPresenting`, the new init parameters (Task 1).

- [ ] **Step 1: Implement** `public final class WebAuthenticationSessionPresenter: NSObject, AuthorizationPresenting, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable`:
  - `init(anchor: @escaping @Sendable @MainActor () -> NSWindow?)`.
  - `present(...)`: hop to the main actor; create `ASWebAuthenticationSession(url: url, callbackURLScheme: completionScheme) { callbackURL, error in ... }`; set `presentationContextProvider = self` and `prefersEphemeralWebBrowserSession = false`; keep a strong reference to the session; call `start()` and return its Bool. In the completion handler: `onEnded(nil)` when there is a callback URL, otherwise `onEnded(error ?? CancellationError())` (a user cancel is `ASWebAuthenticationSessionError.canceledLogin`); then drop the reference.
  - `presentationAnchor(for:)` returns `anchor()` if available, else `NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()`.
  - `dismiss()`: on the main actor, `session?.cancel()` and drop it (safe when nil; must not call `onEnded` a second time with an error that would mask success: once `onEnded` has fired the session is nil).
- [ ] **Step 2: Wire the app.** Where the app builds `LoopbackAuthorizationInteraction`, pass `presenter: WebAuthenticationSessionPresenter(anchor: { NSApp.keyWindow })` (use the Settings window if the app has an obvious reference to it). Keep `openURL` (NSWorkspace) as the fallback. Add `import AuthenticationServices`/`import AppKit` only where needed.
- [ ] **Step 3: Verify.** `swift build --package-path Packages/CalendarApple`, `swift test --package-path Packages/CalendarApple`, then `xcodegen generate --spec Apps/macOS/project.yml` (restore the two Info.plists with `git checkout -- Apps/macOS/Sources/Info.plist Apps/macOS/Widgets/Info.plist`) and `xcodebuild -project Apps/macOS/TimeTug.xcodeproj -scheme TimeTug -destination 'platform=macOS' test` (expect `** TEST SUCCEEDED **`, report the count; it was 195). Do NOT launch the app (the user's own instance may be running).
- [ ] **Step 4: Commit** (`feat(app): Google sign-in in a system web-authentication sheet that closes itself`).

## Task 3: Docs
- [ ] Update `AGENTS.md` (the `CalendarApple` layout line and a short gotcha: sign-in uses ASWebAuthenticationSession plus the loopback 302 to `timetug-oauth://done`; the browser flow is the fallback) and add a short "OAuth in a system sheet" note to ADR 0012 (why not an embedded web view: Google blocks embedded user agents; why the 302 trick). Keep prose free of credential-looking assignments. Commit (`docs: OAuth sheet flow`).
