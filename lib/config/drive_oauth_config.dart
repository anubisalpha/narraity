/// Google Drive OAuth client credentials, supplied at build time via
/// `--dart-define-from-file=oauth_config.json` (gitignored — copy
/// `oauth_config.example.json` at the repo root and fill in real values).
///
/// This is the **one app-level OAuth client** (a "Desktop app" type client
/// registered in Google Cloud Console) shared by every install of Narraity —
/// not a per-user credential. Individual end users still sign in with their
/// own Google account and grant `drive.file` access (the app can only see
/// files it creates); this Client ID/secret just identifies the *app* to
/// Google, same relationship as an API key identifies a service. See
/// README.md's "Google Drive Sync" section for the full Google Cloud Console
/// setup steps.
class DriveOAuthConfig {
  static const clientId = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');
  static const clientSecret = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_SECRET');

  /// The **Web application**-type OAuth client ID, used as Android's
  /// `serverClientId` — the browser+loopback flow above doesn't work on
  /// Android (Android blocks the app from binding the local server socket;
  /// confirmed on real hardware, not an emulator artifact), so Android signs
  /// in via `google_sign_in`'s Credential Manager-based flow instead. That
  /// flow needs its own OAuth client ID separate from [clientId] above
  /// (which is Desktop-type, Windows-only) — a Web-type client, plus a
  /// matching Android-type client (package name + release/debug SHA-1)
  /// registered against the same Google Cloud project. See README.md's
  /// "Google Drive Sync" section for the exact setup steps.
  static const androidServerClientId =
      String.fromEnvironment('GOOGLE_OAUTH_ANDROID_SERVER_CLIENT_ID');

  /// False until real values are supplied via `--dart-define-from-file` —
  /// lets the UI show "not configured" instead of failing confusingly deep
  /// inside an OAuth call. Gates the Windows/desktop client id/secret only;
  /// see [isConfiguredForAndroid] for Android's separate requirement.
  static bool get isConfigured => clientId.isNotEmpty;

  static bool get isConfiguredForAndroid => androidServerClientId.isNotEmpty;
}
