# TimeTug Artwork Usage Guide

This file describes where each TimeTug art asset is intended to be used in the macOS app, GitHub repository, website, documentation, and marketing material.

The visual system is built around three core ideas:

1. **Bernese Mountain Dog puppy** — the friendly “tug” that pulls attention back to the calendar.
2. **Blue rope** — the visual metaphor for TimeTug interrupting hyperfocus.
3. **Clock / meeting imagery** — makes the product purpose immediately understandable.

---

## Quick reference

| Asset | Primary use | Avoid using for |
|---|---|---|
| `Branding/timetug-app-icon-1024.png` | App Store, Dock, Finder, marketing | macOS menu bar |
| `macOS/TimeTugAssets.xcassets/AppIcon.appiconset/` | Xcode AppIcon asset catalog | README banners |
| `Branding/timetug-logo-lockup.png` | Website, docs, splash/about views | 16–24 px UI icons |
| `Branding/timetug-wordmark.png` | Headers, nav bars, docs | Dock/App Store icon |
| `Branding/timetug-banner.png` | Website hero, launch material | compact UI |
| `GitHub/timetug-readme-banner.png` | GitHub README | App Store icon |
| `GitHub/timetug-social-preview-1280x640.png` | GitHub social preview / link cards | in-app UI |
| `macOS/TimeTugAssets.xcassets/MenuBarTemplate.imageset/` | Normal macOS menu bar icon | full-color marketing |
| `macOS/TimeTugAssets.xcassets/MenuBarColor.imageset/` | Optional attention/active state | default template state |
| `macOS/MenuBarExports/` | Direct `NSImage` loading/testing | canonical Xcode asset source |
| `Source/` | Design reference and provenance | shipping directly in the app |

---

# 1. App Icon

## File

`Branding/timetug-app-icon-1024.png`

This is the master TimeTug application icon featuring the Bernese Mountain Dog puppy, blue rope, and clock motif.

### Use it for

- macOS App Store artwork
- Dock icon
- Finder application icon
- DMG/install artwork
- product launch graphics
- website product icon
- GitHub release imagery
- social/profile avatars when the full logo is too wide

### Xcode

The production Xcode-ready set is located at:

`macOS/TimeTugAssets.xcassets/AppIcon.appiconset/`

It contains:

- 16×16
- 16×16 @2x
- 32×32
- 32×32 @2x
- 128×128
- 128×128 @2x
- 256×256
- 256×256 @2x
- 512×512
- 512×512 @2x

The `Contents.json` file is already included.

### Guidance

Do not use the detailed App Icon as a menu bar icon. At menu-bar scale, fur, eyes, rope texture, and the clock lose definition.

Do not add extra text over the icon. The dog + rope + clock should remain the complete symbol.

---

# 2. Menu Bar Icon — Template / Monochrome

## Xcode asset

`macOS/TimeTugAssets.xcassets/MenuBarTemplate.imageset/`

This is the **recommended default menu bar icon**.

macOS menu bar icons should normally behave as template images so the operating system can automatically render them correctly against light, dark, translucent, and accessibility menu bar appearances.

### Swift / AppKit example

```swift
if let image = NSImage(named: "MenuBarTemplate") {
    image.isTemplate = true
    statusItem.button?.image = image
}
```

### Recommended use

Use the monochrome/template icon for:

- idle/default state
- normal calendar monitoring
- menu bar presence
- dark mode
- light mode
- high contrast UI

The operating system should control the final foreground color.

### Important

Do not manually use the white preview image as the actual menu bar image. Use the template asset and let AppKit tint it.

---

# 3. Menu Bar Icon — Color

## Xcode asset

`macOS/TimeTugAssets.xcassets/MenuBarColor.imageset/`

This is an optional full-color variant.

### Good uses

The color version can work well when:

- a meeting is approaching
- TimeTug requires acknowledgement
- an onboarding/tutorial screen is demonstrating the menu bar
- a marketing screenshot needs the mascot to be immediately recognizable

### Suggested behavior

A strong macOS interaction pattern would be:

- **Idle:** monochrome template
- **Meeting soon:** monochrome + subtle animation/badge, or temporary color
- **Meeting now:** color icon or attention state
- **Acknowledged:** return to monochrome

Avoid leaving a brightly colored status icon permanently active unless testing shows users prefer it.

---

# 4. Direct Menu Bar PNG Exports

Folder:

`macOS/MenuBarExports/`

These are provided at several pixel sizes for testing, custom rendering, prototypes, or direct `NSImage` loading.

They are useful when experimenting outside an Xcode asset catalog.

For the shipping app, prefer the named Xcode assets whenever practical.

---

# 5. TimeTug Logo Lockup

## File

`Branding/timetug-logo-lockup.png`

The logo lockup contains the TimeTug wordmark plus the supporting tagline.

### Best uses

- website landing page
- onboarding
- About TimeTug window
- press kit
- documentation cover
- launch graphics
- presentation slides
- product screenshots with sufficient whitespace

Use this version when the viewer has room to read both the name and tagline.

---

# 6. TimeTug Wordmark

## File

`Branding/timetug-wordmark.png`

This is the compact branding option.

### Best uses

- GitHub README header
- website navigation
- footer branding
- About window
- documentation
- horizontal UI surfaces
- presentation title areas

Use the wordmark when the mascot would be visually excessive or when horizontal space is more valuable than vertical space.

---

# 7. Marketing Banner

## File

`Branding/timetug-banner.png`

This contains the core product story:

- TimeTug identity
- Bernese Mountain Dog mascot
- blue rope / tug metaphor
- calendar and meeting context
- screen interruption concept
- hyperfocus positioning

### Best uses

- website hero section
- launch announcement
- Product Hunt / launch assets
- press material
- blog header
- demo presentation
- feature overview

The banner is storytelling artwork, not an application UI asset.

---

# 8. GitHub README Banner

## File

`GitHub/timetug-readme-banner.png`

Use near the top of the repository README.

Recommended Markdown:

```md
<p align="center">
  <img src="GitHub/timetug-readme-banner.png" alt="TimeTug — a tug when time needs your attention">
</p>
```

This image introduces the project without requiring the full marketing banner to dominate the README.

---

# 9. GitHub Social Preview

## File

`GitHub/timetug-social-preview-1280x640.png`

Designed for repository and link-preview surfaces.

### GitHub setup

In the repository:

**Settings → General → Social preview**

Upload this image.

It is also appropriate for:

- Slack/Discord link previews
- blog cards
- release announcements
- social sharing

---

# 10. Source / Reference Artwork

Folder:

`Source/`

These files preserve the approved brand direction and generated source boards.

They exist so future contributors can understand:

- mascot appearance
- rope metaphor
- logo placement
- color relationships
- tone of the product
- menu bar intent

Source boards should generally **not** be shipped inside the application bundle.

---

# 11. Brand Color Direction

The TimeTug artwork uses a friendly productivity palette:

- **Primary blue:** calendar / action / rope / product identity
- **Deep navy:** typography and monochrome icon foundation
- **Orange:** attention and urgency accents
- **Warm white / cream:** approachable background surfaces
- **Bernese black, white, and rust:** mascot identity

The orange accent should behave like an attention signal rather than the dominant interface color.

Blue is the primary product color.

---

# 12. Mascot Usage

The Bernese Mountain Dog puppy represents the core product metaphor:

> TimeTug does not merely notify you. It gently but persistently pulls you out of hyperfocus when something important needs your attention.

### Good mascot contexts

- onboarding
- empty states
- meeting interruption screens
- marketing
- About window
- setup completion
- friendly error/recovery states

### Avoid mascot overload

Routine settings panels, permission dialogs, and dense utility interfaces should remain clean and native to macOS.

The puppy is more effective when it appears at meaningful moments.

---

# 13. Recommended Product States

The art system naturally supports several states.

### Idle

- monochrome menu bar icon
- no interruption
- normal calendar monitoring

### Meeting approaching

- subtle menu bar attention treatment
- optional color icon
- small notification

### Meeting now

- TimeTug screen takeover
- meeting information
- prominent Join button
- Bernese / rope branding where appropriate

### User acknowledges

- restore prior workflow
- return menu bar icon to template state

This keeps the product cute without sacrificing the “you cannot accidentally miss this” behavior.

---

# 14. File Naming Guidance for Future Assets

Use lowercase kebab-case for standalone files:

```text
timetug-app-icon-1024.png
timetug-logo-lockup.png
timetug-wordmark.png
timetug-menubar-template.png
timetug-menubar-color.png
timetug-readme-banner.png
```

For Xcode asset catalogs, use readable PascalCase asset names:

```text
AppIcon
MenuBarTemplate
MenuBarColor
```

---

# 15. Repository Recommendation

A clean repository layout is:

```text
TimeTug/
├── TimeTug/
│   └── Assets.xcassets/
├── artwork/
│   ├── Branding/
│   ├── GitHub/
│   └── Source/
├── README.md
└── ARTWORK_USAGE.md
```

For this package, the existing `macOS/TimeTugAssets.xcassets` directory can be copied directly into the Xcode project or its individual asset sets can be merged into an existing `Assets.xcassets`.

---

## Tagline

**A tug when time needs your attention.**

## Core positioning

**Never hyperfocus through another meeting.**
