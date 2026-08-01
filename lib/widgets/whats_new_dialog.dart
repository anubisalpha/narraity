import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/release_notes_screen.dart';
import '../services/release_notes_service.dart';
import '../state/release_notes_provider.dart';

/// Invisible widget (renders nothing itself) that watches
/// [whatsNewProvider] and shows a one-time "What's New" dialog the first
/// launch after an update. Placed in `LibraryScreen`'s tree alongside
/// `UpdateAvailableBanner` — deliberately its own widget rather than logic
/// inside `LibraryScreen` directly, since `LibraryScreen` is a stateless
/// `ConsumerWidget` and showing a dialog exactly once needs a mounted
/// `State` to guard against re-showing on every rebuild.
class WhatsNewDialogTrigger extends ConsumerStatefulWidget {
  const WhatsNewDialogTrigger({super.key});

  @override
  ConsumerState<WhatsNewDialogTrigger> createState() => _WhatsNewDialogTriggerState();
}

class _WhatsNewDialogTriggerState extends ConsumerState<WhatsNewDialogTrigger> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<ReleaseNote?>>(whatsNewProvider, (previous, next) {
      final release = next.valueOrNull;
      if (_handled || release == null) return;
      _handled = true;
      // Mark seen immediately (not after the dialog closes) so a crash or
      // early dismissal doesn't leave it re-prompting forever.
      writeLastSeenVersion(release.version);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showDialog(release);
      });
    });
    return const SizedBox.shrink();
  }

  void _showDialog(ReleaseNote release) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('What\'s New in ${release.version}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: SelectableText(
              release.notes.isEmpty ? 'No release notes were provided for this version.' : release.notes,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReleaseNotesScreen(highlightVersion: release.version),
                ),
              );
            },
            child: const Text('View Full History'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
