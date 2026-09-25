# timetug.obryan.cloud

TimeTug's public homepage and privacy policy (`docs/decisions/` covers app architecture; this is the
marketing/legal site, unrelated to the Xcode project). Plain static HTML, no build step.

- `public/index.html` — homepage.
- `public/privacy.html` — privacy policy, required for Google OAuth verification (Settings > Accounts >
  Google) and linked from the app's consent screen.
- `public/style.css` — shared styles. Colors are taken from the app's own palette
  (`Apps/macOS/Sources/BlurBackdrop.swift` `TakeoverColors`, `Apps/macOS/Sources/AboutView.swift`), not
  invented for the web; keep them in sync if the app's palette changes.
- `public/download.js` — resolves the versioned DMG attached to GitHub's latest stable release. If the
  lookup fails or the release has no signed DMG yet, the button opens the latest release page.
- `public/img/` — resized copies of `artwork/Branding/timetug-app-icon-1024.png`. Regenerate with
  `sips -Z <size> artwork/Branding/timetug-app-icon-1024.png --out site/public/img/<name>.png` if the source
  icon changes.

Hosted on Firebase Hosting, project `timetug` (the same Google Cloud project as the Google Calendar OAuth
client — see `docs/decisions/`), custom domain `timetug.obryan.cloud`.

## Deploying

Automatic: pushing to `master` with changes under `site/` deploys via
`.github/workflows/firebase-hosting-merge.yml` (see that file for how the Firebase service account secret
is supplied). A pull request that touches `site/` gets a preview URL via
`.github/workflows/firebase-hosting-pull-request.yml`.

Manual, from this directory, if you have the Firebase CLI and are signed in as an account with access to
the `timetug` project:

```bash
cd site
firebase deploy --only hosting
```
