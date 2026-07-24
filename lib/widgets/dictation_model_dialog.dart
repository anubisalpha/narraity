import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dictation_model.dart';
import '../state/dictation_provider.dart';

/// First-use flow: pick a dictation language (only shown on Windows — the
/// model download step doesn't apply to Android's native recognizer), then
/// download with progress. Returns true once a model is ready to use.
Future<bool> ensureDictationModelReady(BuildContext context, WidgetRef ref) async {
  final alreadyDownloaded =
      await ref.read(dictationModelDownloadedProvider.future);
  if (alreadyDownloaded) return true;

  if (!context.mounted) return false;
  final proceeded = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _DictationModelDialog(),
  );
  return proceeded ?? false;
}

class _DictationModelDialog extends ConsumerStatefulWidget {
  const _DictationModelDialog();

  @override
  ConsumerState<_DictationModelDialog> createState() => _DictationModelDialogState();
}

class _DictationModelDialogState extends ConsumerState<_DictationModelDialog> {
  double? _progress;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _progress = 0;
      _error = null;
    });

    try {
      final model = await ref.read(resolvedDictationModelProvider.future);
      final service = ref.read(dictationModelServiceProvider);
      await for (final progress in service.download(model)) {
        if (!mounted) return;
        setState(() => _progress = progress);
      }
      ref.invalidate(dictationModelDownloadedProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Download failed: $error';
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(dictationLanguageProvider);
    final modelSize = ref.watch(dictationModelSizeProvider);
    final modelAsync = ref.watch(resolvedDictationModelProvider);
    final downloading = _progress != null;

    return AlertDialog(
      title: const Text('Set Up Voice Dictation'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dictation runs fully offline. The speech model downloads once '
              'and is reused for every project.',
            ),
            const SizedBox(height: 16),
            if (!downloading) ...[
              DropdownButtonFormField<DictationLanguage>(
                initialValue: language,
                decoration: const InputDecoration(labelText: 'Language'),
                items: [
                  for (final lang in DictationLanguage.values)
                    DropdownMenuItem(value: lang, child: Text(lang.displayName)),
                ],
                onChanged: (lang) {
                  if (lang != null) {
                    ref.read(dictationLanguageProvider.notifier).select(lang);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<DictationModelSize>(
                initialValue: modelSize,
                decoration: const InputDecoration(labelText: 'Model size'),
                isExpanded: true,
                items: [
                  for (final size in DictationModelSize.values)
                    DropdownMenuItem(
                      value: size,
                      child: Text(size.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (size) {
                  if (size != null) {
                    ref.read(dictationModelSizeProvider.notifier).select(size);
                  }
                },
              ),
            ],
            const SizedBox(height: 12),
            modelAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, stack) => Text('Could not check model catalog: $err'),
              data: (model) => Text(
                'Download size: ${model.sizeText}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              const SizedBox(height: 8),
              Text('${((_progress ?? 0) * 100).round()}%'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: downloading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: downloading ? null : _download,
          child: const Text('Download & Enable'),
        ),
      ],
    );
  }
}
