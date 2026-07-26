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

## Building the signed MSIX installer

```powershell
powershell -File windows\build_msix.ps1
```

Bypasses the `msix` pub package's own bundled MakeAppx.exe/signtool.exe — on some machines
(including this project's dev environment) those fail with a WinSxS "side-by-side configuration is
incorrect" error, a version mismatch against a newer Windows SDK. The script uses the installed
Windows SDK's own matched copies of those tools instead. Needs `windows/narraity_signing.pfx`
present (a self-signed certificate, gitignored — generate your own with `New-SelfSignedCertificate`,
subject `CN=Anubis Productions` to match the existing `identity_name`/`publisher` in `pubspec.yaml`,
or update those to match a certificate of your own).

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
