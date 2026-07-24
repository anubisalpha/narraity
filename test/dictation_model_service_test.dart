import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narraity/models/dictation_model.dart';
import 'package:narraity/services/dictation_model_service.dart';
import 'package:narraity/services/library_service.dart';

void main() {
  late Directory tempDir;
  late DictationModelService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('narraity_dictation_test_');
    service = DictationModelService(LibraryService(rootOverride: tempDir));
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  const model = ResolvedDictationModel(
    language: DictationLanguage.enUs,
    size: DictationModelSize.small,
    modelName: 'vosk-model-small-en-us-0.15',
    downloadUrl: 'https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip',
    sizeText: '~40MB',
  );

  test('isDownloaded is false before any download', () async {
    expect(await service.isDownloaded(model), isFalse);
  });

  test('modelPath points inside .models/ at the library root', () async {
    final path = await service.modelPath(model);
    expect(path.replaceAll('\\', '/'), endsWith('.models/vosk-model-small-en-us-0.15'));
  });

  test('isDownloaded becomes true once the model folder exists', () async {
    final path = await service.modelPath(model);
    await Directory(path).create(recursive: true);
    expect(await service.isDownloaded(model), isTrue);
  });
}
