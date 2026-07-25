import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/review_session.dart';
import '../services/review_markdown_parser.dart';
import '../state/review_session_provider.dart';

const _categories = <String>[
  'pacing',
  'consistency',
  'dialogue',
  'continuity',
  'prose',
];

/// One review session: the anchored paragraphs down the page, a comment
/// icon per paragraph, and an Export action that writes the comments JSON
/// `ReviewExportService.importComments` (the author's side) expects.
/// Every comment edit autosaves immediately — a reviewer closing the app
/// mid-pass shouldn't lose work, same expectation as the author's own
/// autosaving scene editor.
class ReviewSessionDetailScreen extends ConsumerStatefulWidget {
  const ReviewSessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ReviewSessionDetailScreen> createState() =>
      _ReviewSessionDetailScreenState();
}

class _ReviewSessionDetailScreenState
    extends ConsumerState<ReviewSessionDetailScreen> {
  ReviewSession? _session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = ref.read(reviewSessionServiceProvider);
    final sessions = await service.listSessions();
    if (!mounted) return;
    setState(() {
      _session = sessions.firstWhere((s) => s.id == widget.sessionId);
    });
  }

  Future<void> _saveSession() async {
    final session = _session;
    if (session == null) return;
    final service = ref.read(reviewSessionServiceProvider);
    await service.save(session);
    ref.invalidate(reviewSessionListProvider);
  }

  Future<void> _commentOn(ReviewParagraph paragraph) async {
    final session = _session;
    if (session == null) return;
    final existing = session.comments[paragraph.anchorId];
    final controller = TextEditingController(text: existing?.text ?? '');
    var category = existing?.category;

    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Comment'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paragraph.text,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Comment'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: category,
                  decoration: const InputDecoration(
                    labelText: 'Category (optional)',
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    for (final c in _categories)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (value) => setDialogState(() => category = value),
                ),
              ],
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.of(context).pop(('', null)),
                child: const Text('Remove'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop((controller.text, category)),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;

    final (text, resultCategory) = result;
    setState(() {
      if (text.trim().isEmpty) {
        session.comments.remove(paragraph.anchorId);
      } else {
        session.comments[paragraph.anchorId] = ReviewComment(
          anchorId: paragraph.anchorId,
          text: text.trim(),
          category: resultCategory,
        );
      }
    });
    await _saveSession();
  }

  Future<void> _export() async {
    final session = _session;
    if (session == null || session.comments.isEmpty) return;
    final service = ref.read(reviewSessionServiceProvider);
    final json = service.exportCommentsJson(session);

    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Save review comments to send back',
      fileName: '${session.title}.comments.json',
      lockParentWindow: true,
    );
    if (savePath == null) return;
    await File(savePath).writeAsString(json);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved to $savePath'),
        action: SnackBarAction(
          label: 'Copy Path',
          onPressed: () => Clipboard.setData(ClipboardData(text: savePath)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(session.title),
        actions: [
          IconButton(
            tooltip: 'Export Comments to Send Back',
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: session.comments.isEmpty ? null : _export,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (session.metadata != null)
            _MetadataHeader(metadata: session.metadata!),
          Expanded(
            child: session.paragraphs.isEmpty
                ? const Center(
                    child: Text(
                      'This file has no anchored paragraphs to review.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: session.paragraphs.length,
                    itemBuilder: (context, index) {
                      final paragraph = session.paragraphs[index];
                      final isNewScene =
                          index == 0 ||
                          session.paragraphs[index - 1].sceneTitle !=
                              paragraph.sceneTitle;
                      final comment = session.comments[paragraph.anchorId];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isNewScene) ...[
                            if (index != 0) const SizedBox(height: 12),
                            Text(
                              paragraph.sceneTitle,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Divider(),
                          ],
                          Card(
                            color: comment != null
                                ? Theme.of(context).colorScheme.primaryContainer
                                      .withValues(alpha: 0.3)
                                : null,
                            child: ListTile(
                              title: Text(paragraph.text),
                              subtitle: comment == null
                                  ? null
                                  : Text(
                                      comment.category == null
                                          ? comment.text
                                          : '[${comment.category}] ${comment.text}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                              trailing: IconButton(
                                tooltip: comment == null
                                    ? 'Add comment'
                                    : 'Edit comment',
                                icon: Icon(
                                  comment == null
                                      ? Icons.comment_outlined
                                      : Icons.comment,
                                ),
                                onPressed: () => _commentOn(paragraph),
                              ),
                              onTap: () => _commentOn(paragraph),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Project title/subtitle/author/export-timestamp from the export's
/// metadata comment, shown up front so the reviewer knows whose work and
/// which project this is without needing to open the raw file.
class _MetadataHeader extends StatelessWidget {
  const _MetadataHeader({required this.metadata});

  final ReviewExportMetadata metadata;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              metadata.projectTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (metadata.subtitle != null)
              Text(
                metadata.subtitle!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 4),
            if (metadata.author != null) Text('By ${metadata.author}'),
            Text(
              'Exported ${DateFormat.yMMMd().add_jm().format(metadata.exportedAt)}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
