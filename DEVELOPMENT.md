# Developing Narraity

This is for building from source or contributing. If you just want to use the app, see the
[Download](README.md#download) section of the README instead.

## Getting started

```bash
flutter pub get
flutter run -d windows      # or -d <android-device-id>
```

Windows builds need the vendored DLLs in `windows/vosk/` and `windows/hunspell/` (already checked
in) — no extra install step required.

## Google Drive Sync setup

Drive sync needs one OAuth client registered to the app (not per-user — see the README's Google
Drive Sync feature section). To set it up:

1. [Google Cloud Console](https://console.cloud.google.com/) → create/select a project → **APIs &
   Services → Library** → enable the **Google Drive API**.
2. **APIs & Services → OAuth consent screen** → User type **External** → add the `drive.file` scope
   → add your own Google account(s) as test users (fine for personal use; full verification is only
   needed to publish the app publicly).
3. **APIs & Services → Credentials → Create Credentials → OAuth client ID** → type **Desktop app**.
   Copy the **Client ID** and **Client Secret**.
4. Copy `oauth_config.example.json` to `oauth_config.json` (gitignored) and fill in both values.
5. Build/run with `--dart-define-from-file=oauth_config.json`, e.g.:

   ```bash
   flutter run -d windows --dart-define-from-file=oauth_config.json
   flutter build windows --dart-define-from-file=oauth_config.json
   ```

Without this, Settings → Google Drive Sync shows a "not configured" message instead of failing
confusingly deep inside an OAuth call.

## Building the Windows installer

```powershell
powershell -File windows\build_installer.ps1
```

Runs `flutter build windows --release`, then compiles `windows\narraity_installer.iss` with Inno
Setup's `ISCC.exe` to produce `narraity-setup.exe`. Needs Inno Setup installed
(`choco install innosetup` or download from [jrsoftware.org](https://jrsoftware.org/isinfo.php)).
No certificate, no signing — the installer is deliberately unsigned (see PLAN.md's "Windows
packaging" decision for why: a self-signed certificate turned out to be genuinely error-prone for
users to trust manually, and a CA-issued one costs real money for a free hobby project). Users see
a one-time "Windows protected your PC" SmartScreen prompt on first run, unavoidable for any
unsigned Windows binary.

**Also needs `nuget.exe` on `PATH`** — one plugin's (`flutter_tts`) Windows CMake build invokes it,
but only in **release** mode, not debug — so `flutter run -d windows` never surfaces this even
though `flutter build windows --release` (and therefore this script) needs it. Not installed by
default and needs no admin rights to fix: download from
[dist.nuget.org](https://dist.nuget.org/win-x86-commandline/latest/nuget.exe) into any folder on
`PATH` (`windows/tools/` is gitignored and works fine for this).

**Gotchas hit building the earlier signed-MSIX pipeline that likely still apply** (see BUILD_LOG.md
for the full original writeups):
- A stale `build/` directory from an earlier debug build can leave CMake's cached
  `CMAKE_INSTALL_PREFIX` pointing at the system default (`C:\Program Files\narraity`, which needs
  admin rights) instead of the project's own `windows/CMakeLists.txt` override. Delete `build/`
  entirely (or at minimum `build/windows/x64/CMakeCache.txt`) before a release build if you hit
  `file cannot create directory: C:/Program Files/...`.
- `flutter build windows --release` expects `build/native_assets/windows/` to exist (even though
  this project uses no Dart native-assets packages) — a `flutter build windows` that fails partway
  through can leave it never created, and the subsequent CMake install step fails with `file
  INSTALL cannot find ".../native_assets/windows": No error.` Create the empty directory by hand
  (`mkdir build\native_assets\windows`) and re-run if this happens.
- If `flutter test`/`flutter analyze` (the release script's own sanity gate) fails with a
  file-in-use error on `build\unit_test_assets` or a leftover `build\windows\x64\runner\Release\`
  directory from a prior partial build, something (antivirus real-time scanning, or a lingering
  handle from an earlier interrupted build) has a transient lock. Deleting the stale directory and
  re-running works around it.

## Releasing a new version

```powershell
powershell -File windows\release.ps1 -Version 1.2.0
```

Bumps `pubspec.yaml`'s version, runs `flutter analyze` + `flutter test` as a sanity gate, builds
the installer via `build_installer.ps1`, commits the bump, tags `v1.2.0`, pushes both, and
publishes a GitHub release with `narraity-setup.exe` attached via `gh release create`. Needs a
clean working tree and an authenticated `gh` CLI. Pass `-NotesFile path\to\notes.md` to supply
release notes yourself; otherwise `gh` auto-generates them from merged PRs/commits since the last
tag.

### Update checking

Narraity ships as a plain installer with no silent auto-update mechanism. The only update path is
the **in-app checker** (`lib/services/update_check_service.dart`) — a manual "Check for Updates"
button in Settings → About, plus a silent session-cached startup check that shows a dismissible
banner on the Library screen. It reads GitHub's `releases/latest` API and compares its `tag_name`
against the running app's version, then links to the release page for the user to download and run
themselves. A release that skips `gh release create` is invisible to it.

## Running tests

```bash
flutter test
flutter analyze
```

CI (`.github/workflows/ci.yml`) runs both on every push/PR, on `windows-latest` specifically —
the test suite loads real vendored native libraries (`libhunspell.dll`, `libvosk.dll`) via
`dart:ffi`, which are Windows binaries.

## Why not a Vosk Flutter plugin?

The only published `vosk_flutter_service` release has a build-breaking bug on Windows (its own
install script extracts the native DLL one folder deeper than its build script expects, and its
`CMakeLists.txt` also runs a stale command left over from a package rename). Rather than depend on
an unmaintained single-contributor package with that baked in, the real `libvosk.dll` — Apache
2.0, from the same upstream release — is vendored directly at `windows/vosk/`, with a ~150-line
hand-written FFI binding (`lib/services/vosk_ffi.dart`) covering the handful of functions actually
needed. Full writeup in that file's doc comment.

## Further reading

See [`BUILD_LOG.md`](BUILD_LOG.md) for a phase-by-phase record of what's been built, and
[`PLAN.md`](PLAN.md) for the full project plan (all phases, including ones not built yet).
