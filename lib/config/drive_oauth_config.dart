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

  /// False until real values are supplied via `--dart-define-from-file` —
  /// lets the UI show "not configured" instead of failing confusingly deep
  /// inside an OAuth call.
  static bool get isConfigured => clientId.isNotEmpty;
}
