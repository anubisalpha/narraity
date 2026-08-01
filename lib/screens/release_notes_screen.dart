import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/release_notes_service.dart';
import '../state/release_notes_provider.dart';

/// Full release history, newest first — reachable from Settings → About, or
/// from the update banner/"Check for Updates" result (passing
/// [highlightVersion] so the just-announced release is scrolled to and
/// visually marked rather than making the user hunt for it in the list).
/// Distinct from the one-time `WhatsNewDialogTrigger` popup: this is the
/// browse-anytime version, and shows every past release, not just the one
/// just installed.
class ReleaseNotesScreen extends ConsumerStatefulWidget {
  const ReleaseNotesScreen({super.key, this.highlightVersion});

  final String? highlightVersion;

  @override
  ConsumerState<ReleaseNotesScreen> createState() => _ReleaseNotesScreenState();
}

class _ReleaseNotesScreenState extends ConsumerState<ReleaseNotesScreen> {
  final _scrollController = ScrollController();
  bool _scrolledToHighlight = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(releaseNotesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Release Notes')),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Could not load release notes: $err')),
        data: (result) {
          final (releases, fetchedAt, fromCache) = result;
          if (releases.isEmpty) {
            return const Center(child: Text('No release notes available.'));
          }

          final highlightIndex = widget.highlightVersion == null
              ? -1
              : releases.indexWhere((r) => r.version == widget.highlightVersion);

          if (highlightIndex > 0 && !_scrolledToHighlight) {
            _scrolledToHighlight = true;
            // Rough offset estimate (list items vary in height with notes
            // length) — close enough to bring the entry into view, not
            // pixel-perfect; a real key-based ensureVisible would need
            // per-item GlobalKeys, overkill for a "jump near it" affordance.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  highlightIndex * 220.0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                );
              }
            });
          }

          return Column(
            children: [
              if (fromCache && fetchedAt != null)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Showing cached data from ${DateFormat.yMMMd().add_jm().format(fetchedAt)} — '
                    'couldn\'t reach GitHub for a fresh check.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: releases.length,
                  separatorBuilder: (_, __) => const Divider(height: 32),
                  itemBuilder: (context, index) => _ReleaseTile(
                    release: releases[index],
                    highlighted: index == highlightIndex,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReleaseTile extends StatelessWidget {
  const _ReleaseTile({required this.release, this.highlighted = false});
  final ReleaseNote release;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(release.version, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(width: 12),
            if (release.publishedAt != null)
              Text(
                DateFormat.yMMMd().format(release.publishedAt!),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (highlighted) ...[
              const SizedBox(width: 12),
              Chip(
                label: const Text('New'),
                visualDensity: VisualDensity.compact,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              ),
            ],
            const Spacer(),
            if (release.htmlUrl.isNotEmpty)
              TextButton(
                onPressed: () => launchUrl(Uri.parse(release.htmlUrl)),
                child: const Text('View on GitHub'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(
          release.notes.isEmpty ? 'No release notes were provided for this version.' : release.notes,
        ),
      ],
    );

    if (!highlighted) return content;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: content,
    );
  }
}
