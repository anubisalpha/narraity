import 'package:flutter/material.dart';

import '../models/manuscript.dart';
import '../services/manuscript_service.dart';

/// A node's overview — every child underneath it with a rolled-up word
/// count, and a read-only combined view of all its prose (including the
/// node's own, if any) in document order. Answers "let me see everything in
/// this section at once" without the complexity of making a concatenated
/// multi-file view directly editable.
class SectionOverviewScreen extends StatelessWidget {
  const SectionOverviewScreen({super.key, required this.service, required this.node});

  final ManuscriptService service;
  final ManuscriptNode node;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${node.typeLabel}: ${node.title}'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Contents'),
            Tab(text: 'Combined Text'),
          ]),
        ),
        body: TabBarView(
          children: [
            _ContentsTab(service: service, node: node),
            _CombinedTextTab(service: service, node: node),
          ],
        ),
      ),
    );
  }
}

class _ContentsTab extends StatelessWidget {
  const _ContentsTab({required this.service, required this.node});

  final ManuscriptService service;
  final ManuscriptNode node;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: service.wordCountUnder(node),
      builder: (context, snapshot) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.summarize_outlined),
                title: Text('${snapshot.data ?? '…'} words total'),
                subtitle: Text(
                  '${ManuscriptStructure.contentCount(node)} '
                  '${ManuscriptStructure.contentCount(node) == 1 ? "item" : "items"} in this section',
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final child in node.children) _ChildSummary(service: service, node: child),
          ],
        );
      },
    );
  }
}

class _ChildSummary extends StatelessWidget {
  const _ChildSummary({required this.service, required this.node});

  final ManuscriptService service;
  final ManuscriptNode node;

  @override
  Widget build(BuildContext context) {
    final hasChildren = node.children.isNotEmpty;

    if (!hasChildren) {
      return FutureBuilder(
        future: service.readScene(node.id),
        builder: (context, sceneSnapshot) => ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(node.title),
          subtitle: Text('${node.typeLabel} · ${sceneSnapshot.data?.wordCount ?? 0} words'),
        ),
      );
    }

    return FutureBuilder<int>(
      future: service.wordCountUnder(node),
      builder: (context, snapshot) {
        return ExpansionTile(
          title: Text(node.title),
          subtitle: Text(
            '${node.typeLabel} · ${snapshot.data ?? '…'} words · '
            '${ManuscriptStructure.contentCount(node)} items',
          ),
          children: [
            for (final child in node.children)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: _ChildSummary(service: service, node: child),
              ),
          ],
        );
      },
    );
  }
}

class _CombinedTextTab extends StatelessWidget {
  const _CombinedTextTab({required this.service, required this.node});

  final ManuscriptService service;
  final ManuscriptNode node;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: service.combinedContentUnder(node),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            snapshot.data!.isEmpty ? 'Nothing written here yet.' : snapshot.data!,
          ),
        );
      },
    );
  }
}
