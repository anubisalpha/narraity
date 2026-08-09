import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config/drive_oauth_config.dart';
import 'drive_token_store.dart';

const _scopes = [drive.DriveApi.driveFileScope];

/// Google Drive sign-in. Two genuinely different implementations per
/// platform — not a shared code path, despite `DriveAuthService`'s own
/// earlier doc comment having claimed otherwise (wrong; see below):
///
/// - **Windows**: `googleapis_auth`'s browser + local-loopback OAuth flow.
///   `clientViaUserConsent` opens the system browser to Google's consent
///   screen and catches the redirect on a `localhost` port it starts itself.
/// - **Android**: the loopback flow above does **not** work — confirmed live
///   on a real device, not just the emulator: `SocketException: Failed to
///   create server socket (OS Error: Operation not permitted, errno = 1)`.
///   Google's loopback-IP redirect flow is documented as being for installed
///   *desktop* apps specifically; Android blocks the app from binding that
///   server socket at all. Android instead uses `google_sign_in`'s
///   Credential Manager-based flow, which needs its own Google Cloud Console
///   setup — see [DriveOAuthConfig.androidServerClientId]'s doc comment.
///
/// `drive.file` scope only (per PLAN.md): the app can only see files/folders
/// it creates itself, never the user's whole Drive.
abstract class DriveAuthService {
  Future<bool> get isSignedIn;

  /// Returns an authenticated [http.Client], silently reusing a saved
  /// session if there is one. Falls through to an interactive sign-in if
  /// there's no saved session or it's been revoked. [onSignInUrl] is only
  /// used by the Windows implementation (needs to open a browser URL);
  /// Android's Credential Manager UI has no equivalent.
  Future<http.Client> ensureSignedIn({Future<void> Function(String url)? onSignInUrl});

  Future<void> signOut();

  factory DriveAuthService({required ClientId clientId, DriveTokenStore? tokenStore}) {
    if (Platform.isAndroid) return _AndroidDriveAuthService();
    return _DesktopDriveAuthService(clientId: clientId, tokenStore: tokenStore);
  }
}

class _DesktopDriveAuthService implements DriveAuthService {
  _DesktopDriveAuthService({
    required this.clientId,
    DriveTokenStore? tokenStore,
  }) : _tokenStoreFuture = tokenStore != null
            ? Future.value(tokenStore)
            : DriveTokenStore.forPlatform();

  final ClientId clientId;
  final Future<DriveTokenStore> _tokenStoreFuture;

  AutoRefreshingAuthClient? _client;

  @override
  Future<bool> get isSignedIn async {
    if (_client != null) return true;
    final store = await _tokenStoreFuture;
    return await store.loadRefreshToken() != null;
  }

  @override
  Future<http.Client> ensureSignedIn({
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

  @override
  Future<void> signOut() async {
    _client?.close();
    _client = null;
    final store = await _tokenStoreFuture;
    await store.clear();
  }
}

/// Wraps a [GoogleSignInAccount] as an authenticated [http.Client] — fetches
/// fresh authorization headers per request (the SDK auto-refreshes the
/// underlying access token as needed) rather than caching one statically.
class _GoogleSignInAuthClient extends http.BaseClient {
  _GoogleSignInAuthClient(this._account);

  final GoogleSignInAccount _account;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final headers = await _account.authorizationClient.authorizationHeaders(
      _scopes,
      promptIfNecessary: true,
    );
    if (headers != null) request.headers.addAll(headers);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

class _AndroidDriveAuthService implements DriveAuthService {
  Future<void>? _initFuture;
  GoogleSignInAccount? _account;

  Future<void> _ensureInitialized() {
    return _initFuture ??= GoogleSignIn.instance.initialize(
      serverClientId: DriveOAuthConfig.androidServerClientId,
    );
  }

  @override
  Future<bool> get isSignedIn async {
    if (_account != null) return true;
    await _ensureInitialized();
    _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    return _account != null;
  }

  @override
  Future<http.Client> ensureSignedIn({
    Future<void> Function(String url)? onSignInUrl,
  }) async {
    await _ensureInitialized();
    _account ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
    _account ??= await GoogleSignIn.instance.authenticate();
    final account = _account!;
    // Requests the Drive scope explicitly — authenticate() alone only
    // establishes identity, not authorization for any particular scope.
    await account.authorizationClient.authorizeScopes(_scopes);
    return _GoogleSignInAuthClient(account);
  }

  @override
  Future<void> signOut() async {
    _account = null;
    await GoogleSignIn.instance.signOut();
  }
}
