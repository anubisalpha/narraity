import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dictation_model.dart';
import '../state/dictation_provider.dart';
import '../state/theme_provider.dart';
import '../widgets/editor_settings_form.dart';
import '../widgets/vault_settings_section.dart';

enum _SettingsCategory {
  appearance,
  editor,
  dictation,
  backup,
  spellCheck,
  drive,
  export,
}

extension on _SettingsCategory {
  String get label => switch (this) {
        _SettingsCategory.appearance => 'Appearance',
        _SettingsCategory.editor => 'Editor',
        _SettingsCategory.dictation => 'Dictation',
        _SettingsCategory.backup => 'Backup & Vault',
        _SettingsCategory.spellCheck => 'Spell Check & Language',
        _SettingsCategory.drive => 'Google Drive Sync',
        _SettingsCategory.export => 'Export',
      };

  IconData get icon => switch (this) {
        _SettingsCategory.appearance => Icons.palette_outlined,
        _SettingsCategory.editor => Icons.edit_note,
        _SettingsCategory.dictation => Icons.mic_outlined,
        _SettingsCategory.backup => Icons.shield_outlined,
        _SettingsCategory.spellCheck => Icons.spellcheck,
        _SettingsCategory.drive => Icons.cloud_sync_outlined,
        _SettingsCategory.export => Icons.ios_share,
      };

  /// Categories for phases not built yet — shown in the nav so the
  /// structure is ready, with a "coming soon" placeholder as their content.
  bool get isComingSoon => switch (this) {
        _SettingsCategory.spellCheck ||
        _SettingsCategory.drive ||
        _SettingsCategory.export =>
          true,
        _ => false,
      };

  /// Which phase will implement this — shown in the placeholder.
  String get comingInPhase => switch (this) {
        _SettingsCategory.spellCheck => 'Phase 4.5',
        _SettingsCategory.drive => 'Phase 5',
        _SettingsCategory.export => 'Phase 6',
        _ => '',
      };
}

/// App-wide settings, organized by category in a side nav — built to grow:
/// Appearance and Editor are live now, Dictation was added in Phase 1.3, and
/// Spell Check/Drive Sync/Export are placeholders for phases 4.5/5/6 so the
/// structure doesn't need reshaping as they land.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _SettingsCategory _selected = _SettingsCategory.appearance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            minExtendedWidth: 220,
            selectedIndex: _SettingsCategory.values.indexOf(_selected),
            onDestinationSelected: (index) =>
                setState(() => _selected = _SettingsCategory.values[index]),
            labelType: NavigationRailLabelType.none,
            destinations: [
              for (final category in _SettingsCategory.values)
                NavigationRailDestination(
                  icon: Icon(category.icon),
                  label: Text(category.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _buildContent(_selected),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(_SettingsCategory category) {
    if (category.isComingSoon) {
      return _ComingSoonSection(category: category);
    }
    return switch (category) {
      _SettingsCategory.appearance => const _AppearanceSection(),
      _SettingsCategory.editor => const _EditorSection(),
      _SettingsCategory.dictation => const _DictationSection(),
      _SettingsCategory.backup => const _BackupSection(),
      _ => const SizedBox.shrink(),
    };
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ComingSoonSection extends StatelessWidget {
  const _ComingSoonSection({required this.category});

  final _SettingsCategory category;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: category.label, subtitle: 'Not built yet'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Icon(category.icon, color: Theme.of(context).disabledColor, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    '${category.label} settings arrive in ${category.comingInPhase}, '
                    'per the project roadmap.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title: 'Appearance',
          subtitle: 'Theme for the whole app shell.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto),
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode),
                  label: Text('Dark'),
                ),
              ],
              selected: {themeMode},
              onSelectionChanged: (selection) =>
                  ref.read(themeModeProvider.notifier).setThemeMode(selection.first),
            ),
          ),
        ),
      ],
    );
  }
}

class _EditorSection extends StatelessWidget {
  const _EditorSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title: 'Editor',
          subtitle: 'Typography used while writing (separate from export fonts).',
        ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: EditorSettingsForm(),
          ),
        ),
      ],
    );
  }
}

class _BackupSection extends StatelessWidget {
  const _BackupSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _SectionHeader(
          title: 'Backup & Vault',
          subtitle: 'Encrypted backups and tamper-evident version history.',
        ),
        VaultSettingsSection(),
      ],
    );
  }
}

class _DictationSection extends ConsumerStatefulWidget {
  const _DictationSection();

  @override
  ConsumerState<_DictationSection> createState() => _DictationSectionState();
}

class _DictationSectionState extends ConsumerState<_DictationSection> {
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
      ref.invalidate(downloadedDictationModelsProvider);
    } catch (error) {
      if (mounted) setState(() => _error = 'Download failed: $error');
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _redownload() async {
    final service = ref.read(dictationModelServiceProvider);
    final model = await ref.read(resolvedDictationModelProvider.future);
    await service.deleteModelByName(model.modelName);
    ref.invalidate(dictationModelDownloadedProvider);
    ref.invalidate(downloadedDictationModelsProvider);
    await _download();
  }

  Future<void> _deleteModel(DownloadedDictationModel model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete model?'),
        content: Text(
          '"${model.modelName}" (${model.sizeText}) will be removed. '
          'Dictation using this model will need to re-download it before working again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final service = ref.read(dictationModelServiceProvider);
    await service.deleteModelByName(model.modelName);
    ref.invalidate(dictationModelDownloadedProvider);
    ref.invalidate(downloadedDictationModelsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(dictationLanguageProvider);
    final size = ref.watch(dictationModelSizeProvider);
    final resolvedAsync = ref.watch(resolvedDictationModelProvider);
    final downloadedAsync = ref.watch(dictationModelDownloadedProvider);
    final allModelsAsync = ref.watch(downloadedDictationModelsProvider);
    final downloading = _progress != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title: 'Dictation',
          subtitle: 'Fully offline voice-to-text. Switch language/accuracy or '
              'free up space at any time.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<DictationLanguage>(
                        initialValue: language,
                        decoration: const InputDecoration(labelText: 'Language'),
                        items: [
                          for (final lang in DictationLanguage.values)
                            DropdownMenuItem(value: lang, child: Text(lang.displayName)),
                        ],
                        onChanged: downloading
                            ? null
                            : (lang) {
                                if (lang != null) {
                                  ref
                                      .read(dictationLanguageProvider.notifier)
                                      .select(lang);
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<DictationModelSize>(
                        initialValue: size,
                        decoration: const InputDecoration(labelText: 'Accuracy'),
                        items: const [
                          DropdownMenuItem(
                            value: DictationModelSize.small,
                            child: Text('Small'),
                          ),
                          DropdownMenuItem(
                            value: DictationModelSize.large,
                            child: Text('Large'),
                          ),
                        ],
                        onChanged: downloading
                            ? null
                            : (s) {
                                if (s != null) {
                                  ref.read(dictationModelSizeProvider.notifier).select(s);
                                }
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                resolvedAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (err, stack) => Text('Could not check model catalog: $err'),
                  data: (model) => downloadedAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (err, stack) => const SizedBox.shrink(),
                    data: (isReady) => Row(
                      children: [
                        Icon(
                          isReady ? Icons.check_circle : Icons.download_outlined,
                          size: 18,
                          color: isReady ? Colors.green : null,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isReady
                                ? '${model.modelName} ready (${model.sizeText})'
                                : 'Not downloaded — ${model.sizeText}',
                          ),
                        ),
                        if (!downloading)
                          TextButton(
                            onPressed: isReady ? _redownload : _download,
                            child: Text(isReady ? 'Re-download fresh copy' : 'Download'),
                          ),
                      ],
                    ),
                  ),
                ),
                if (downloading) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _progress == 0 ? null : _progress),
                  Text('${((_progress ?? 0) * 100).round()}%'),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Downloaded models', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          child: allModelsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, stack) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Could not list downloaded models: $err'),
            ),
            data: (models) => models.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No models downloaded yet.'),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final model in models)
                        ListTile(
                          leading: const Icon(Icons.folder_zip_outlined),
                          title: Text(model.modelName),
                          subtitle: Text(model.sizeText),
                          trailing: IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteModel(model),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
