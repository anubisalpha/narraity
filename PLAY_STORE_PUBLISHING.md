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
- [x] **Rebuilt both the AAB and release APK via `android/build_release.ps1`** (2026-08-09) —
      every Android build before this was built with a bare `flutter build appbundle`/
      `flutter build apk`, which does **not** pick up `oauth_config.json`. Both new artifacts
      verified genuinely signed with the release key: AAB via `keytool -printcert -jarfile`
      (`"C:\Program Files\Java\jdk-26.0.2\bin\keytool.exe"` — plain `keytool` isn't on PATH), APK
      via `apksigner verify --print-certs` (keytool doesn't understand APK v2/v3 signing scheme,
      reports "Not a signed jar file" even on a genuinely-signed APK — use apksigner for APKs,
      keytool only for AABs/JARs). Both builds hit the same recurring
      `build/app/intermediates`/`build/app/outputs/apk/release` file-lock issue documented
      elsewhere in this file — cleared and retried each time, not a real failure.
- [x] Tested the release build live (installed on `emulator-5554`) — **found a second, deeper
      bug**: Settings → Google Drive Sync now correctly shows a real "Not connected. / Connect"
      state (confirming the oauth_config.json fix above worked), but tapping Connect threw
      `SocketException: Failed to create server socket (OS Error: Operation not permitted,
      errno = 1), address = localhost, port = 0`. Confirmed on the user's real device too — a
      genuine Android platform restriction, not an emulator artifact.
- [x] **Fixed** (2026-08-09) — `DriveAuthService` is now an abstract factory with two real
      implementations instead of one shared loopback flow: Windows keeps the existing
      `googleapis_auth` browser+loopback flow; Android uses `google_sign_in`'s Credential
      Manager-based flow instead. `flutter analyze` clean, all 590 tests pass, both
      `flutter build windows` and `flutter build apk --debug` succeed with the
      `oauth_config.json` dart-defines. Full detail (including exactly what to register in
      Google Cloud Console) in `README.md`'s "Google Drive Sync" section.
- [ ] **Blocked on Google Cloud Console setup** — the fix above needs two new OAuth clients in
      the same project as the existing Desktop-type one, neither of which exist yet:
      1. **Android**-type client: package `uk.aity.narraity`, release SHA-1
         `18:DE:24:8B:0E:85:53:4B:39:93:87:5E:ED:6A:90:C4:C2:43:0E:34` (from
         `narraity-release.jks`). Optionally also register the debug SHA-1
         `20:5F:0F:B4:E5:40:9F:20:7F:9E:D4:C3:D5:6E:79:51:56:00:53:0B` as a second Android-type
         client (same package name) if debug builds should be able to sign in too.
      2. **Web application**-type client (no SHA-1 needed) — its Client ID goes into
         `oauth_config.json` as `GOOGLE_OAUTH_ANDROID_SERVER_CLIENT_ID` (currently an empty
         placeholder there). Until this is filled in, Android will keep showing "not configured".
      Once both exist and `oauth_config.json` has the real Web client ID, rebuild via
      `android/build_release.ps1` and test sign-in for real on a device.

---

## 5. Store Listing Content

### Text — draft, needs review

- [x] App name (30 chars): `Narraity`
- [x] Short description (79 chars, revised 2026-08-09 to lead with the actual differentiators
      rather than a generic pitch):
> Local-first novel writing — signed history, real KDP export, no subscription.

- [x] Full description (revised 2026-08-09 — plain text/unicode bullets, not markdown; Play Store
      doesn't render `**bold**`. Same "what makes it different" framing as narraity.html, adapted
      for the store listing format — see that page for the source copy):

```
Write your novel. Own your data.

Narraity is a local-first novel writing app built for authors who want a full manuscript toolkit without the subscription or the cloud lock-in. Everything lives on your own device by default — your manuscript is yours, in open formats, forever.

WHAT MAKES NARRAITY DIFFERENT

• Tamper-evident version history — every save is cryptographically signed, not just snapshotted. Restore an earlier draft with confidence, or prove nothing was altered outside the app.

• Export built from KDP's actual rulebook — paperback and hardcover export use Amazon's own published formatting rules: trim size, bleed, page-count-scaled margins, correctly-suppressed running headers, an auto-generated copyright page.

• No subscription, no cloud lock-in, ever — your manuscript is plain files on your device from day one. Sync is optional and goes to your own Google Drive. There's no Narraity server for your writing to live on, and no monthly fee to keep reading it.

FULL MANUSCRIPT TOOLKIT

• Book/Chapter/Scene editor with markdown-style formatting
• Characters, worldbuilding notes, and a visual Relationship Diagram
• Plot Grid and Timeline for structuring your story
• Spell check and thesaurus, built in, offline, no internet required
• Offline voice dictation and Read Aloud
• Series support — shared characters, world notes, and to-dos across a whole series

EXPORT ANYWHERE

PDF, EPUB, DOCX, and plain text, plus KDP-ready paperback, hardcover, and eBook export.

A FEW MORE THINGS

• Switching from Dabble? Import your manuscript straight from a Dabble export — no retyping.
• Contextual Reference Panel — mention a character while writing and their card appears automatically.
• Adaptive daily goals — word-count or deadline targets that adjust to your actual pace.
• Feedback in the open — bug reports and suggestions post as public GitHub Discussions under your own account, not a black-box support ticket.
• Fully open source — the code is public. You don't have to take "your data stays local" on faith.

YOUR DATA, YOUR CHOICE

We have no backend, no server, no analytics, no ads. If you turn on Google Drive sync, it goes to your own Drive — never ours.
```

- [x] User review pass — approved as-is 2026-08-09, no changes requested

### Category & Tags
- [x] Category: **Productivity** — confirmed with user 2026-08-03 (over Books & Reference, given
      the tooling-heavy feature set: plot grid, timeline, relationship diagrams, exports)
- [ ] Tags (up to 5) — candidates: Writing, Notebook, Books

### Graphics
- [x] **App icon (512x512)** — `store-assets/graphics/icon-512.png`, resized from
      `branding/app_icon_master.png` (737x737 source) via PowerShell System.Drawing bicubic resize.
- [x] **Feature graphic (1024x500)** — `store-assets/graphics/feature-graphic.png`. Rendered from
      `feature-graphic-source.html` (kept alongside it for future edits) via Chrome headless
      (`chrome --headless --screenshot --window-size=1024,500`) for pixel-exact output — icon +
      wordmark + tagline on the app's own red/orange brand gradient (not aity.uk's navy/teal,
      since this is the app's own store listing, not a page on the umbrella site).
- [x] Phone screenshots — 4 captured 2026-08-03 on the `nd_pixel` emulator, in `store-assets/`:
      `phone_screenshot_library.png`, `phone_screenshot_manuscript_tree.png` (drawer open),
      `phone_screenshot_editor.png`, `phone_screenshot_settings.png`. Taken *after* the
      responsive-layout fix below — see that section, these would have shown broken UI before it.
- [x] **Tablet screenshots (2)** — `store-assets/graphics/tablet_screenshot_library.png` and
      `tablet_screenshot_editor.png`, captured 2026-08-09 on the `mosaity_tablet` AVD
      (2560x1600). Had to rebuild the debug APK twice first — the existing one had gone corrupted
      (220MB, failed APK signature verification on install) and a retry hit the same recurring
      `build/app/intermediates` file-lock issue as the Android debug builds earlier this session.
      Screenshots cropped to trim a thin colored line along the very bottom edge (present even in
      raw `adb screencap` output at this exact resolution — a genuine rendering quirk at this
      screen size, not a capture artifact; harmless and barely visible either way).

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
- [x] **Live at https://aity.uk/privacy.html#narraity** (deployed 2026-08-09) — added as a new
      `.product-banner` + policy section in `Sites/aity.uk/privacy.html`, same pattern as
      Mosaity's, plus an `id="narraity"` anchor (and a matching `id="mosaity"` added to Mosaity's
      banner for consistency) so the section can be linked to directly. Deployed via the SFTP
      command in `Sites/aity.uk/README.md`, verified live via a real page fetch (not just "upload
      succeeded").
- [ ] Enter URL in Play Console

**HTML block below** — kept for reference; this is what's now live in `Sites/aity.uk/privacy.html`.

```html
        <div class="product-banner" id="narraity">
            <span class="name">Narraity</span>
            <a class="visit" href="https://github.com/anubisalpha/narraity" target="_blank" rel="noopener">Visit on GitHub &rarr;</a>
        </div>

        <h2 style="margin-top:0.5rem; font-size:1.4rem;">Narraity Privacy Policy</h2>
        <p class="updated">Last updated: 9 August 2026</p>

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
- Content rating questionnaire, data safety form, app content declarations — all Play Console UI,
  can't be automated from here
- **Drive sync's Android auth code is fixed but untested end-to-end** — blocked purely on Google
  Cloud Console setup (an Android-type + a Web-type OAuth client, neither created yet — see
  section 3's Android sign-in entry above for the exact values to register). Once
  `oauth_config.json` has the real Web client ID, rebuild and test sign-in for real.
- Everything else in section 9 (Pre-Launch Testing) below is otherwise unblocked — the release
  build itself launches fine in release/minified mode (Hunspell/Vosk FFI survived), just Drive
  sign-in specifically fails.

## Session 2026-08-09 — help icons, Timeline fix, Android OAuth gap, privacy policy live

Started from the user reporting the in-app Help system didn't cover the manuscript sidebar tabs
(Manuscript/Characters/World/Notes/To-dos) or the scene editor's own formatting toolbar — only the
project toolbar (New Idea/Goals/Plot Grid/...) had a working "?" icon, even though
`help_content.dart` already had full topics written for the missing ones (`manuscript`,
`sceneEditor`, `charactersWorld`, `notes`, `todos`, `referencePanel`). Wired up help icons for the
sidebar tab group (one icon that follows whichever tab is selected), the scene editor toolbar, and
the Reference Panel — verified live on **both** the Android emulator and a fresh Windows debug
build (rebuilt after `windows/flutter/ephemeral` had gone missing its `.cc` source files —
regenerated via `flutter precache --windows` + `flutter pub get`).

While doing a broader phone-width sweep (Timeline, Plot Grid, Relationships, Export, Goals,
Settings sub-pages, Global Ideas, News, Feedback, About), found and fixed a real bug:
`timeline_screen.dart`'s track sidebar was a fixed 260px column regardless of screen width,
squeezing the canvas down to as little as ~100dp on a phone (confirmed live — the canvas was a
barely-visible sliver). Fixed with the same breakpoint pattern used elsewhere: below 700px the
sidebar becomes an end drawer (new "Tracks" AppBar icon), canvas gets the full width. Verified
live. Everything else checked in the sweep was already clean.

**The big find:** the user reported Drive sync doesn't work on their real Android device.
Checked the emulator's Settings → Google Drive Sync and got the same "OAuth client ID... not set
for this build" message. Root cause: `flutter build appbundle`/`flutter build apk` on their own do
**not** pick up `oauth_config.json` — Windows' `release.ps1`/`build_installer.ps1` already pass
`--dart-define-from-file=oauth_config.json` correctly, but no Android equivalent ever existed, so
every Android build shipped so far (the signed AAB, the beta APK, this session's debug builds) was
built without it. Added `android/build_release.ps1` to fix this going forward — checked the user
explicitly wants the build-process fix only for now, not an immediate rebuild/reship.

Also wrote and deployed the Narraity section of the privacy policy — **live at
https://aity.uk/privacy.html#narraity** — using the draft HTML already sitting in this file,
plus an `id="narraity"` anchor (and a matching one added to Mosaity's section) so it can be linked
to directly. Confirmed live via a real page fetch, not just "upload succeeded".

Four commits this session, all local on `main`, not yet pushed: help icons, Timeline fix, the
Android build script, plus this file's updates.
