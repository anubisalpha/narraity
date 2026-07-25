import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../models/review_session.dart';
import '../state/review_session_provider.dart';
import 'review_session_detail_screen.dart';

/// The reviewer's own section — reachable from the Library screen, entirely
/// independent of any Narraity project. A 3rd-party reviewer receives an
/// exported `.review.md` file, opens it here, comments against it, and
/// exports the comments JSON to send back to the author. Sessions persist
/// (`_ReviewSessions/` at the library root) so a review in progress survives
/// closing the app, mirroring Global Ideas' "works with no project open"
/// pattern.
class ReviewSessionsScreen extends ConsumerWidget {
  const ReviewSessionsScreen({super.key});

  Future<void> _newReview(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Open a manuscript export for review (.md)',
      type: FileType.custom,
      allowedExtensions: ['md'],
      lockParentWindow: true,
    );
    final path = result?.files.single.path;
    if (path == null) return;

    final markdown = await File(path).readAsString();
    final service = ref.read(reviewSessionServiceProvider);
    final session = await service.createFromMarkdown(
      p.basenameWithoutExtension(path),
      markdown,
    );
    ref.invalidate(reviewSessionListProvider);

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReviewSessionDetailScreen(sessionId: session.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(reviewSessionListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Review a Manuscript')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newReview(context, ref),
        icon: const Icon(Icons.folder_open),
        label: const Text('Open File to Review'),
      ),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) =>
            Center(child: Text('Failed to load reviews: $err')),
        data: (sessions) => sessions.isEmpty
            ? const _EmptyReviews()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                itemCount: sessions.length,
                itemBuilder: (context, index) =>
                    _ReviewSessionCard(session: sessions[index]),
              ),
      ),
    );
  }
}

class _EmptyReviews extends StatelessWidget {
  const _EmptyReviews();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.rate_review_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('No reviews yet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Open a file someone sent you to review to get started.'),
        ],
      ),
    );
  }
}

class _ReviewSessionCard extends ConsumerWidget {
  const _ReviewSessionCard({required this.session});

  final ReviewSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = session.metadata?.author;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(session.title),
        subtitle: Text(
          '${author == null ? '' : 'By $author · '}'
          '${session.paragraphs.length} paragraph(s) · ${session.commentCount} comment(s) · '
          'Modified ${DateFormat.yMMMd().format(session.modified)}',
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReviewSessionDetailScreen(sessionId: session.id),
          ),
        ),
        trailing: IconButton(
          tooltip: 'Delete review',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final service = ref.read(reviewSessionServiceProvider);
            await service.deleteSession(session);
            ref.invalidate(reviewSessionListProvider);
          },
        ),
      ),
    );
  }
}
