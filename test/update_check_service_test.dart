import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:narraity/services/update_check_service.dart';

void main() {
  UpdateCheckService serviceReturning(String body, {int statusCode = 200}) {
    return UpdateCheckService(
      client: MockClient((request) async => http.Response(body, statusCode)),
    );
  }

  const releaseJson = '''
{
  "tag_name": "v1.2.0",
  "html_url": "https://github.com/anubisalpha/narraity/releases/tag/v1.2.0",
  "body": "Adds thing."
}
''';

  test('reports an update when the latest tag is newer', () async {
    final service = serviceReturning(releaseJson);
    final update = await service.checkForUpdate('1.1.0');

    expect(update, isNotNull);
    expect(update!.version, '1.2.0');
    expect(update.htmlUrl, 'https://github.com/anubisalpha/narraity/releases/tag/v1.2.0');
    expect(update.notes, 'Adds thing.');
  });

  test('returns null when already on the latest version', () async {
    final service = serviceReturning(releaseJson);
    final update = await service.checkForUpdate('1.2.0');

    expect(update, isNull);
  });

  test('returns null when running a newer version than the latest release', () async {
    final service = serviceReturning(releaseJson);
    final update = await service.checkForUpdate('1.3.0');

    expect(update, isNull);
  });

  test('ignores the +build suffix when comparing', () async {
    final service = serviceReturning(releaseJson);
    final update = await service.checkForUpdate('1.2.0+7');

    expect(update, isNull);
  });

  test('throws UpdateCheckException on a non-200 response', () async {
    final service = serviceReturning('not found', statusCode: 404);

    expect(() => service.checkForUpdate('1.0.0'), throwsA(isA<UpdateCheckException>()));
  });

  test('throws UpdateCheckException on malformed JSON', () async {
    final service = serviceReturning('not json');

    expect(() => service.checkForUpdate('1.0.0'), throwsA(isA<UpdateCheckException>()));
  });

  test('throws UpdateCheckException when tag_name is missing', () async {
    final service = serviceReturning('{"html_url": "https://example.com"}');

    expect(() => service.checkForUpdate('1.0.0'), throwsA(isA<UpdateCheckException>()));
  });
}
