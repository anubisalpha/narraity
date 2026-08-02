import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:narraity/services/github_auth_service.dart';
import 'package:narraity/services/github_token_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_github_auth_test_');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<GitHubAuthService> serviceWith(
    Future<http.Response> Function(http.Request request) handler,
  ) async {
    return GitHubAuthService(
      clientId: 'test-client-id',
      client: MockClient((request) => handler(request)),
      tokenStore: await GitHubTokenStore.forPlatform(rootOverride: tempDir),
    );
  }

  group('requestDeviceCode', () {
    test('parses a successful response', () async {
      final service = await serviceWith((request) async => http.Response(
            '{"device_code":"dc","user_code":"ABCD-1234",'
            '"verification_uri":"https://github.com/login/device",'
            '"expires_in":900,"interval":0}',
            200,
          ));

      final result = await service.requestDeviceCode();

      expect(result.deviceCode, 'dc');
      expect(result.userCode, 'ABCD-1234');
      expect(result.verificationUri, 'https://github.com/login/device');
      expect(result.expiresIn, 900);
      expect(result.interval, 0);
    });

    test('throws on a non-200 response', () async {
      final service = await serviceWith((request) async => http.Response('error', 500));
      expect(() => service.requestDeviceCode(), throwsA(isA<GitHubAuthException>()));
    });

    test('throws when the response body contains an error', () async {
      final service = await serviceWith((request) async => http.Response(
            '{"error":"invalid_client","error_description":"bad client id"}',
            200,
          ));
      expect(() => service.requestDeviceCode(), throwsA(isA<GitHubAuthException>()));
    });
  });

  group('pollForToken', () {
    final request = DeviceCodeRequest(
      deviceCode: 'dc',
      userCode: 'ABCD-1234',
      verificationUri: 'https://github.com/login/device',
      expiresIn: 900,
      interval: 0,
    );

    test('succeeds immediately and saves the token', () async {
      final service = await serviceWith(
        (r) async => http.Response('{"access_token":"tok_123"}', 200),
      );

      final token = await service.pollForToken(request);
      expect(token, 'tok_123');
      expect(await service.currentToken(), 'tok_123');
    });

    test('keeps polling through authorization_pending until approved', () async {
      var callCount = 0;
      final service = await serviceWith((r) async {
        callCount++;
        if (callCount < 3) {
          return http.Response('{"error":"authorization_pending"}', 200);
        }
        return http.Response('{"access_token":"tok_after_wait"}', 200);
      });

      final token = await service.pollForToken(request);
      expect(token, 'tok_after_wait');
      expect(callCount, 3);
    });

    test('throws on expired_token', () async {
      final service = await serviceWith(
        (r) async => http.Response('{"error":"expired_token"}', 200),
      );
      expect(() => service.pollForToken(request), throwsA(isA<GitHubAuthException>()));
    });

    test('throws on access_denied', () async {
      final service = await serviceWith(
        (r) async => http.Response('{"error":"access_denied"}', 200),
      );
      expect(() => service.pollForToken(request), throwsA(isA<GitHubAuthException>()));
    });

    test('recovers from a transient unexpected error and still succeeds', () async {
      var callCount = 0;
      final service = await serviceWith((r) async {
        callCount++;
        if (callCount < 3) {
          return http.Response(
            '{"error":"incorrect_client_credentials","error_description":"bad creds"}',
            200,
          );
        }
        return http.Response('{"access_token":"tok_after_hiccup"}', 200);
      });

      final token = await service.pollForToken(request);
      expect(token, 'tok_after_hiccup');
      expect(callCount, 3);
    });

    test('gives up after enough consecutive unexpected errors', () async {
      var callCount = 0;
      final service = await serviceWith((r) async {
        callCount++;
        return http.Response(
          '{"error":"incorrect_client_credentials","error_description":"bad creds"}',
          200,
        );
      });

      await expectLater(
        service.pollForToken(request),
        throwsA(isA<GitHubAuthException>()),
      );
      expect(callCount, 5);
    });

    test('an unexpected error followed by authorization_pending resets the retry budget', () async {
      var callCount = 0;
      final service = await serviceWith((r) async {
        callCount++;
        // Four unexpected errors, then a normal pending response, then four
        // more unexpected errors, then success — never five unexpected
        // errors in a row, so this should still eventually succeed.
        if (callCount == 5) return http.Response('{"error":"authorization_pending"}', 200);
        if (callCount == 10) return http.Response('{"access_token":"tok_reset"}', 200);
        return http.Response(
          '{"error":"incorrect_client_credentials","error_description":"bad creds"}',
          200,
        );
      });

      final token = await service.pollForToken(request);
      expect(token, 'tok_reset');
      expect(callCount, 10);
    });

    test('stops polling and throws when cancelled', () async {
      var callCount = 0;
      final service = await serviceWith((r) async {
        callCount++;
        return http.Response('{"error":"authorization_pending"}', 200);
      });

      await expectLater(
        service.pollForToken(request, isCancelled: () => true),
        throwsA(isA<GitHubAuthException>()),
      );
      expect(callCount, 0);
    });
  });

  group('sign-in state', () {
    test('isSignedIn is false with no saved token', () async {
      final service = await serviceWith((r) async => http.Response('{}', 200));
      expect(await service.isSignedIn, isFalse);
    });

    test('signOut clears a saved token', () async {
      final service = await serviceWith(
        (r) async => http.Response('{"access_token":"tok_123"}', 200),
      );
      await service.pollForToken(DeviceCodeRequest(
        deviceCode: 'dc',
        userCode: 'ABCD-1234',
        verificationUri: 'https://github.com/login/device',
        expiresIn: 900,
        interval: 0,
      ));

      expect(await service.isSignedIn, isTrue);
      await service.signOut();
      expect(await service.isSignedIn, isFalse);
    });
  });
}
