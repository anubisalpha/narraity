import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../state/news_provider.dart';

/// Simple chronological feed parsed from the repo's `NEWS.md` — v1 keeps it
/// deliberately plain, no read/unread tracking or badges (see PLAN.md's
/// "News Feed" section).
class NewsScreen extends ConsumerWidget {
  const NewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newsAsync = ref.watch(newsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('News')),
      body: newsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Could not load news: $err')),
        data: (result) {
          final (entries, fetchedAt, fromCache) = result;
          if (entries.isEmpty) {
            return const Center(child: Text('No news yet.'));
          }
          return Column(
            children: [
              if (fromCache && fetchedAt != null)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Showing cached news from ${DateFormat.yMMMd().add_jm().format(fetchedAt)} — '
                    'couldn\'t reach GitHub for a fresh check.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 32),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(entry.title, style: Theme.of(context).textTheme.titleLarge),
                            ),
                            Text(
                              DateFormat.yMMMd().format(entry.date),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(entry.body),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
