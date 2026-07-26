import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'drive_token_store.dart';

/// Google Drive sign-in, using `googleapis_auth`'s browser + local-loopback
/// OAuth flow rather than the `google_sign_in` package PLAN.md originally
/// named — `google_sign_in` only supports Android/iOS/macOS/Web, not
/// Windows. `clientViaUserConsent` opens the system browser to Google's
/// consent screen and catches the redirect on a `localhost` port it starts
/// itself, which works identically on Windows and Android — one code path
/// for both v1 platforms instead of two.
///
/// `drive.file` scope only (per PLAN.md): the app can only see files/folders
/// it creates itself, never the user's whole Drive.
class DriveAuthService {
  DriveAuthService({
    required this.clientId,
    DriveTokenStore? tokenStore,
  }) : _tokenStoreFuture = tokenStore != null
            ? Future.value(tokenStore)
            : DriveTokenStore.forPlatform();

  final ClientId clientId;
  final Future<DriveTokenStore> _tokenStoreFuture;

  static const _scopes = [drive.DriveApi.driveFileScope];

  AutoRefreshingAuthClient? _client;

  Future<bool> get isSignedIn async {
    if (_client != null) return true;
    final store = await _tokenStoreFuture;
    return await store.loadRefreshToken() != null;
  }

  /// Returns an authenticated client, silently reusing a saved refresh token
  /// if one exists and is still valid. Falls through to an interactive
  /// browser sign-in (via [onSignInUrl], which just needs to open the URL —
  /// normally [launchUrl]) if there's no saved token or it's been revoked.
  Future<AutoRefreshingAuthClient> ensureSignedIn({
    Future<void> Function(String url)? onSignInUrl,
  }) async {
    final existing = _client;
    if (existing != null) return existing;

    final store = await _tokenStoreFuture;
    final savedRefreshToken = await store.loadRefreshToken();
    final base = http.Client();

    if (savedRefreshToken != null) {
      try {
        final placeholder = AccessCredentials(
          // Already-expired access token — forces an immediate refresh
          // rather than trying (and failing) to use empty token data.
          AccessToken('Bearer', '', DateTime.utc(1970)),
          savedRefreshToken,
          _scopes,
        );
        final refreshed = await refreshCredentials(clientId, placeholder, base);
        _client = autoRefreshingClient(clientId, refreshed, base);
        return _client!;
      } catch (_) {
        // Saved token is invalid/revoked (user revoked access, token
        // expired server-side, ...) — clear it and fall through to a fresh
        // interactive sign-in rather than failing silently forever.
        await store.clear();
      }
    }

    final prompt = onSignInUrl ?? (url) => launchUrl(Uri.parse(url));
    final client = await clientViaUserConsent(clientId, _scopes, prompt, baseClient: base);
    final refreshToken = client.credentials.refreshToken;
    if (refreshToken != null) await store.saveRefreshToken(refreshToken);
    _client = client;
    return client;
  }

  Future<void> signOut() async {
    _client?.close();
    _client = null;
    final store = await _tokenStoreFuture;
    await store.clear();
  }
}
