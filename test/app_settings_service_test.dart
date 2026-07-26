import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/services/app_settings_service.dart';
import 'package:narraity/services/library_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory libraryRoot;
  late AppSettingsService service;

  setUp(() {
    libraryRoot = Directory.systemTemp.createTempSync('narraity_app_settings_test_');
    service = AppSettingsService(libraryService: LibraryService(rootOverride: libraryRoot));
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    libraryRoot.deleteSync(recursive: true);
  });

  test('settingsRoot is a reserved _Settings folder at the library root', () async {
    final dir = await service.settingsRoot();
    expect(dir.path, endsWith('_Settings'));
  });

  test('exportToFile writes only known keys currently set in SharedPreferences', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', 'dark');
    await prefs.setDouble('editor.fontSize', 18.0);
    await prefs.setString('some.unrelated.key', 'should not be exported');

    await service.exportToFile();

    final file = File('${(await service.settingsRoot()).path}/settings.json');
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('"themeMode": "dark"'));
    expect(content, contains('"editor.fontSize": 18.0'));
    expect(content, isNot(contains('unrelated')));
  });

  test('importFromFile applies exported values back into SharedPreferences', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', 'dark');
    await prefs.setDouble('tts.rate', 0.75);
    await prefs.setBool('spellCheck.enabled', false);
    await prefs.setInt('vault.retentionCount', 15);
    await service.exportToFile();

    // Simulate a fresh device / cleared prefs, as if this were the first
    // launch after Drive pulled the settings file down.
    SharedPreferences.setMockInitialValues({});
    await service.importFromFile();

    final reloaded = await SharedPreferences.getInstance();
    expect(reloaded.getString('themeMode'), 'dark');
    expect(reloaded.getDouble('tts.rate'), 0.75);
    expect(reloaded.getBool('spellCheck.enabled'), false);
    expect(reloaded.getInt('vault.retentionCount'), 15);
  });

  test('importFromFile is a no-op when no settings file exists yet', () async {
    await service.importFromFile(); // should not throw
  });

  test('importFromFile ignores a corrupt settings file rather than throwing', () async {
    final dir = await service.settingsRoot();
    await dir.create(recursive: true);
    await File('${dir.path}/settings.json').writeAsString('not valid json{{{');

    await service.importFromFile(); // should not throw
  });

  test('reference panel state is never exported (deliberately workspace-local)', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('referencePanel.visible', false);
    await prefs.setDouble('referencePanel.width', 400);

    await service.exportToFile();

    final content =
        File('${(await service.settingsRoot()).path}/settings.json').readAsStringSync();
    expect(content, isNot(contains('referencePanel')));
  });
}
