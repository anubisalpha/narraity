# Narraity — Google Play Store Publishing Checklist

*Created: 3 August 2026*

Modeled on `Development/Mosaity/PLAY_STORE_PUBLISHING.md`, adapted for Narraity's actual data
flows (no health data; optional Google Drive sync; optional GitHub sign-in for Feedback).

---

## 1. Google Play Developer Account

- [x] Account already exists: "Anubis Productions" (marc.anubis@gmail.com) — shared across the
      -aity/Android app family, see memory `play-console-account`. Account-level step, done.
- [x] Confirmed Narraity has its own app entry in Play Console

---

## 2. App Identity

| Item | Current | Status |
|---|---|---|
| `applicationId` | `uk.aity.narraity` | Already unique, matches the family's `aity.uk` domain — no rename needed (unlike Mosaity, which had to migrate off `com.example`) |
| `namespace` | `uk.aity.narraity` | Matches |
| `versionCode` / `versionName` | `9` / `1.4.1` | Current release version, fine to ship as first Play submission |
| `compileSdk` / `targetSdk` | `36` (confirmed by reading the installed Flutter SDK's `FlutterExtension.kt` default, 2026-08-03) | Meets Play's current `targetSdk >= 35` requirement, no bump needed |
| AGP | `8.9.1` (`android/settings.gradle.kts`) | Modern, should support compileSdk 35 fine (Mosaity needed 8.5.2 minimum) |

### Action items
- [ ] Confirm resolved compileSdk/targetSdk once the current release-build test finishes
- [x] App icon already exists (`mipmap-*/ic_launcher.png` — fountain-pen-and-book mark, matches family wordmark convention)

---

## 3. App Signing

- [x] Generated release keystore 2026-08-03 — `narraity-release.jks` (project root), alias
      `narraity`, 10000-day validity, confirmed with user before generating
- [x] **Back the `.jks` up off-machine** — not a separate action needed; the whole `claudecore`
      folder tree (including this project) is already covered by Google Drive backup.
- [x] `keystore.properties` created at project root, added to `.gitignore` (`*.jks`,
      `keystore.properties`)
- [x] Signing config wired into `android/app/build.gradle.kts` — reads from
      `keystore.properties`, falls back to debug signing if that file is missing (so a fresh
      checkout without the keystore still supports `flutter run --release`)
- [ ] Opt into Play App Signing during first upload

---

## 4. Build Release AAB

- [x] `flutter build apk --release` sanity check — succeeded 2026-08-03, unsigned-config APK,
      74.0MB (unminified; Flutter's template doesn't set `isMinifyEnabled` in the release block,
      unlike Mosaity's native project)
- [x] `flutter build appbundle --release` — succeeded 2026-08-03,
      `build/app/outputs/bundle/release/app-release.aab`, 58.2MB
- [x] Verified genuinely signed with the release key (not a debug fallback) — inspected
      `META-INF/NARRAITY.RSA` inside the .aab via `keytool -printcert -jarfile`, confirmed cert
      `CN=Anubis Productions, OU=Narraity`, matches the keystore generated above
- [ ] **Rebuild both the AAB and the beta APK via `android/build_release.ps1`** (added
      2026-08-09) — every Android build so far, including the one above and the beta APK at
      `aity.uk/beta/narraity.v1.4.1.b9.apk`, was built with a bare `flutter build appbundle`/
      `flutter build apk`, which does **not** pick up `oauth_config.json`. Confirmed live on both
      the emulator and the user's real device: Settings → Google Drive Sync shows "not configured
      for this build" — Drive sync has never actually been enabled in any Android build shipped so
      far, unlike Windows (whose own `release.ps1`/`build_installer.ps1` already passed
      `--dart-define-from-file=oauth_config.json` correctly). Use the new script for every future
      Android release build so this can't silently regress again.
- [ ] Test the release build on a real device/emulator (now also needs to confirm Drive sign-in
      actually completes end-to-end, not just that the app launches)

---

## 5. Store Listing Content

### Text — draft, needs review

- [x] App name (30 chars): `Narraity`
- [x] Short description draft (79 chars):
> Local-first novel writing. Own your manuscript — no subscription, no cloud lock-in.

- [x] Full description draft:
> **Write your novel. Own your data.**
>
> Narraity is a local-first novel writing app built for authors who want Dabble's workflow
> without the subscription or the cloud lock-in. Everything lives on your own device by default —
> your manuscript is yours, in open formats, forever.
>
> **Full manuscript toolkit**
> - Book/Chapter/Scene manuscript editor with markdown-style formatting
> - Characters, worldbuilding notes, and a visual Relationship Diagram
> - Plot Grid and Timeline for structuring your story
> - Spell check and thesaurus, built in, no internet required
> - Voice dictation
> - Version history, so you can always go back
>
> **Export anywhere**
> PDF, EPUB, DOCX, and plain text — plus KDP-ready export for paperback, hardcover, and eBook,
> built directly from Amazon's own formatting rules (trim size, bleed, margins, running headers,
> copyright page, all handled for you).
>
> **Your data, your choice**
> Projects are stored as plain files on your device. Want to sync across devices? Turn on optional
> Google Drive sync — to your own Drive, not ours. We have no backend, no server, no analytics,
> no ads.
>
> **Series support**
> Group multiple books into a Series with shared characters, world notes, and to-dos across the
> whole series.
>
> **Free and open**
> Narraity's source is public on GitHub. Report bugs, follow release notes, and see exactly what
> the app does with your data.

- [ ] User review pass before submitting — needs your read-through, not yet approved

### Category & Tags
- [x] Category: **Productivity** — confirmed with user 2026-08-03 (over Books & Reference, given
      the tooling-heavy feature set: plot grid, timeline, relationship diagrams, exports)
- [ ] Tags (up to 5) — candidates: Writing, Notebook, Books

### Graphics
- [x] App icon exists (512x512 export needed from the existing mark)
- [ ] Feature graphic (1024x500 PNG)
- [x] Phone screenshots — 3 captured 2026-08-03 on the `nd_pixel` emulator, in
      `store-assets/`: `phone_screenshot_library.png`, `phone_screenshot_manuscript_tree.png`
      (drawer open), `phone_screenshot_editor.png`. Taken *after* the responsive-layout fix below
      — see that section, these would have shown broken UI before it.
- [ ] Tablet screenshots (min 2) — same `mosaity_tablet`-style AVD approach can be reused

---

## 6. Content Rating (IARC)

Not yet completed in Play Console. Expected answers, given what the app actually does:

| Questionnaire item | Expected answer |
|---|---|
| Violence / sexual content / profanity / substances / gambling | None (the app itself has none — it's a writing tool; user-authored manuscript content is private/local, not moderated or distributed by the app) |
| User-generated content shared with others | No by default — manuscript content never leaves the device unless the user explicitly enables Google Drive sync (their own Drive) or exports a file themselves. Posting to GitHub Discussions (Feedback) is user-initiated, explicit sign-in required, and is *app feedback text the user types*, not manuscript content |
| Personal info collected | Minimal — Google account (Drive sync, optional) and GitHub identity (Feedback sign-in, optional), both via OAuth, both opt-in, both third-party auth flows rather than data Narraity itself stores/transmits beyond the token needed to talk to that service |
| Location | No |

**Expected rating:** Likely "Everyone" — no concerning content categories apply.

---

## 7. Privacy & Data Safety

### Privacy Policy (required)
- [ ] Narraity has no privacy policy yet. `Sites/aity.uk/privacy.html` currently only has a Mosaity
      section — needs a new Narraity section added, following the same structure
- [ ] Host at `https://aity.uk/privacy#narraity` (or similar) once written
- [ ] Enter URL in Play Console

**Draft HTML block below**, written to slot into `Sites/aity.uk/privacy.html` as a new
`.product-banner` + policy section (same pattern as Mosaity's), right after Mosaity's `<hr>` and
before the closing `<a class="back">`. **Not yet applied to the live file or published** — needs
your go-ahead first, since that's a public site edit.

```html
        <div class="product-banner">
            <span class="name">Narraity</span>
            <a class="visit" href="https://github.com/anubisalpha/narraity" target="_blank" rel="noopener">Visit on GitHub &rarr;</a>
        </div>

        <h2 style="margin-top:0.5rem; font-size:1.4rem;">Narraity Privacy Policy</h2>
        <p class="updated">Last updated: [DATE OF PUBLISH]</p>

        <div class="summary">
            <strong>In short:</strong> Your manuscript stays on your device. Narraity has no
            backend and no server of its own — the only data that ever leaves your device is what
            you explicitly choose to sync to your own Google Drive, or what you type into a
            Feedback post under your own GitHub account.
        </div>

        <h2>What we store on your device only</h2>
        <p>By default, everything Narraity creates stays on your device, as plain files:</p>
        <ul>
            <li>Your manuscripts, characters, worldbuilding notes, plot and timeline data</li>
            <li>App preferences (theme, sidebar layout, etc.)</li>
            <li>A local error log, never transmitted anywhere</li>
        </ul>

        <h2>Google Drive sync (optional)</h2>
        <p>If you turn on Drive sync for a project, your project files are synced to <strong>your own Google Drive</strong> — not to any server we run, because Narraity doesn't have one. We authenticate via Google's own sign-in; your Drive access token is stored encrypted on Windows and in app-private sandboxed storage on Android. Turn sync off at any time in Settings.</p>

        <h2>GitHub sign-in for Feedback (optional)</h2>
        <p>The in-app Feedback screen lets you sign in with GitHub to post feedback as a GitHub Discussion, under your own GitHub identity. This is entirely opt-in — nothing is posted or shared until you choose to sign in and submit feedback yourself. Release Notes and the News Feed also read public data from GitHub, but don't require sign-in or send any personal data.</p>

        <h2>What we never do</h2>
        <ul>
            <li>Run our own server or database that your manuscript ever touches</li>
            <li>Sell or share your data with advertisers or third parties</li>
            <li>Use any analytics SDK or tracker</li>
            <li>Show you adverts</li>
        </ul>

        <h2>Deleting your data</h2>
        <p>Delete a project from within the app, or uninstall the app, to remove everything stored locally. If you enabled Drive sync, delete the synced files from your own Google Drive directly — we have no server-side copy to delete.</p>

        <h2>Children</h2>
        <p>Narraity is not directed at children under 13. If you are under 13, please do not use the app without a parent or guardian's involvement.</p>

        <h2>Your rights (UK GDPR)</h2>
        <p>Because Narraity stores your data on your own device (and, if you opt in, your own Google Drive), you already hold and control it directly. If you have questions about how the app handles data, contact us below.</p>

        <h2>Changes to this policy</h2>
        <p>If we change this policy, the updated version will be published here.</p>

        <h2>Contact</h2>
        <p>Questions about this policy: <a href="mailto:contacts@aity.uk">contacts@aity.uk</a></p>

        <hr>
```

**Open questions before publishing:**
- [x] `contacts@aity.uk` mailbox confirmed set up
- [ ] Fill in the real publish date
- [ ] User read-through/edits
- [ ] Explicit go-ahead to edit the live `privacy.html` and SFTP-deploy it (per the deploy command
      in `Sites/aity.uk/README.md`)

### Data Safety Form — draft answers

| Category | Collected? | Shared with 3rd parties? | Optional/Required? | Notes |
|---|---|---|---|---|
| Files and docs (manuscript content) | Yes | No | Required (core feature) | Local device storage only, unless the user opts into Drive sync (goes to their own Drive) |
| Google account info | Yes, conditionally | No (Google is the sync destination, not a Narraity third party) | Optional | Only if Drive sync enabled |
| GitHub identity | Yes, conditionally | Yes — to GitHub, for the Discussion post itself | Optional | Only if the user signs in via Feedback |
| App activity / analytics | No | No | — | No analytics SDK present |
| Crash logs | No | No | — | Local `app.log` file only (`app_logger.dart`), never transmitted |

- [ ] "Encrypted in transit?" → Yes (HTTPS to Google/GitHub APIs)
- [ ] "Way to request data deletion?" → local data: the app itself, or delete the project/uninstall;
      no server-side data exists to delete since Narraity has no backend

---

## 8. App Content Declarations

- [ ] Target audience — likely general/no restriction (no mature content)
- [ ] Ads: None
- [ ] Government apps: No
- [ ] News: No (Release Notes/News Feed are about the app itself, not general news)
- [ ] Financial: No

---

## 9. Pre-Launch Testing

- [ ] Verify release build (minified) doesn't break Hunspell/Vosk FFI bindings or the SQLite
      thesaurus — these are exactly the kind of native/reflection-touching code R8 can break
      silently, and the general Mosaity checklist's ProGuard warning applies here too, likely more
      so given the FFI surface
- [ ] Cold start test, full navigation pass
- [ ] Test Google Drive sync end-to-end on the release build specifically
- [ ] Test GitHub Feedback sign-in on the release build specifically
- [ ] Test manuscript import (DOCX/Markdown/Dabble JSON) and all four export formats
- [ ] Test on a small screen and a large screen/tablet

---

## 10. Release Strategy

Same phased approach as Mosaity: Internal testing → Closed testing → Open testing → Production,
starting at partial rollout.

---

## Status

**Session 2026-08-03:** Signing is now real — keystore generated, `keystore.properties` wired
into `build.gradle.kts`, a signed release AAB built and verified (`app-release.aab`, 58.2MB).
compileSdk/targetSdk confirmed at 36 (meets Play's requirement, no bump needed). Category
(Productivity) and contact email (support@aity.uk) decided with the user. Store listing short/full
description drafted, not yet reviewed/approved. `.gitignore` updated to exclude the keystore and
its properties file.

**Session 2026-08-03, continued:** generating real phone screenshots surfaced a genuine responsive-
layout bug — the desktop three-pane layout (sidebar + editor + Reference Panel docked side by side)
was never verified on a phone-width screen and broke badly (wrapped text, AppBar actions overflowing
off-screen). Fixed properly with a real breakpoint (drawer + full-screen Reference Panel below
700px) rather than just patching the overflow — full writeup in `BUILD_LOG.md`. Same AppBar-overflow
bug also fixed in `library_screen.dart`. Swept the rest of the app for the same bug class — no other
genuine overflow found; `timeline_screen.dart`'s fixed-260px track sidebar is cramped but doesn't
overflow, noted as a follow-up.

**That first fix had its own bug**, caught live by the user: the scrollable-actions-row approach
(`Expanded` inside AppBar's `actions`) rendered the drawer button on top of the leading back arrow.
Root-caused and fixed by switching to the standard Material pattern (a few primary actions + one
overflow ⋮ menu) — full writeup in `BUILD_LOG.md`. Verified live: back arrow and drawer button now
render as two separate icons, drawer and overflow menu both open correctly. Screenshots recaptured
again after this second fix and are clean. Rebuilt the signed release AAB with all fixes —
`app-release.aab`, 58.2MB, re-verified genuinely signed via `keytool -printcert -jarfile` (took 5
retries due to persistent Windows Defender locks on Gradle's release-lint cache — worked around by
disabling `checkReleaseBuilds` for Android lint, `flutter analyze` remains the real gate).

**Settings screen also fixed**, per the user's own description of the right approach: below 700px,
Settings collapses from its always-two-pane `NavigationRail` layout to a menu-list page (tap a
category → full-width page with its own back button → back returns to the list). This was the root
cause of the Appearance theme-picker overflow. Verified live, clean. Full writeup in `BUILD_LOG.md`.

**Also this session:** built and uploaded a signed release APK (not the Play-Store-only AAB) for
direct-install testing, per the `-aity` family's beta-upload convention:
**https://aity.uk/beta/narraity.v1.4.1.b9.apk** — same release keystore as the AAB. Rebuilt the
signed AAB again afterward with the Settings fix included.

**Not yet done:**
- Back up `narraity-release.jks` off-machine (important — do this soon)
- Confirm/create the Narraity app entry in Play Console
- Set up `support@aity.uk` mailbox (Plesk) — doesn't exist yet, checked 2026-08-03
- Write and publish a Narraity privacy-policy section on `aity.uk/privacy.html` (needs explicit
  go-ahead before editing/publishing a live public page)
- Graphics: feature graphic, tablet screenshots (phone screenshots done, see above)
- Content rating questionnaire, data safety form, app content declarations — all Play Console UI,
  can't be automated from here
- Test the signed release build on a real device/emulator (not yet done — the AAB is built and
  verified signed, but no release-mode/minified smoke test has happened yet, and this app has an
  FFI surface — Hunspell/Vosk — that a minified build could break silently, same caveat as
  Mosaity's checklist)
- `timeline_screen.dart`'s track sidebar (fixed 260px width, `_TrackSidebar`/`_TrackSidebarRow`)
  doesn't overflow on phone width but is cramped — leaves very little room for the timeline canvas
  itself. Not fixed this session (no crash/overflow, just tight) — worth a proper look before
  submission, same "never verified on phone" root cause as the other fixes above
- No screen other than Library/ProjectShell/SeriesDetail/Settings has been live-tested at phone
  width — worth a deliberate pass over the rest of the app (Export, Plot Grid, Relationship
  Diagram, etc.) rather than assuming they're fine because their AppBar action counts are low
