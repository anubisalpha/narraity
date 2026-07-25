import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/tts_service.dart';

/// One instance app-wide (voice engines are expensive to spin up repeatedly,
/// and only one scene can be read aloud at a time anyway).
final ttsServiceProvider = Provider<TtsService>((ref) {
  final service = TtsService();
  ref.onDispose(service.dispose);
  return service;
});

final availableTtsVoicesProvider = FutureProvider<List<TtsVoice>>((ref) async {
  final service = ref.watch(ttsServiceProvider);
  return service.availableVoices();
});

/// Whether Read Aloud is currently speaking — mirrors `isDictatingProvider`.
final isReadingAloudProvider = StateProvider<bool>((ref) => false);
