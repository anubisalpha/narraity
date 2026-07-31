import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../services/filename_sanitizer.dart';
import '../services/review_export_service.dart';
import '../state/manuscript_provider.dart';
import '../state/review_export_provider.dart';

/// AI/external review round-trip (Phase 4), kept as its own screen rather
/// than buried in the scene editor toolbar — sending work out to a reviewer
/// is a distinct workflow from day-to-day writing, and picking more than one
/// scene needs real space for a checklist. Reuses `ReviewExportService`
/// exactly as the (removed) per-scene toolbar actions did.
class ReviewExportScreen extends ConsumerStatefulWidget {
  const ReviewExportScreen({super.key, required this.project});

  final Project project;

  @override
  ConsumerState<ReviewExportScreen> createState() => _ReviewExportScreenState();
}

class _ReviewExportScreenState extends ConsumerState<ReviewExportScreen> {
  final Set<String> _selected = {};

  Future<void> _export(List<(String id, String title)> columns) async {
    if (_selected.isEmpty) return;
    final scenes = [
      for (final column in columns)
        if (_selected.contains(column.$1)) column,
    ];

    final service = await ref.read(
      reviewExportServiceProvider(widget.project).future,
    );
    final markdown = await service.buildExportMarkdown(
      scenes,
      projectTitle: widget.project.title,
      subtitle: widget.project.subtitle,
      author: widget.project.author,
    );

    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Export for review',
      fileName: '${sanitizeFileName(widget.project.title)}.review.md',
      lockParentWindow: true,
    );
    if (savePath == null) return;
    await File(savePath).writeAsString(markdown);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported ${scenes.length} scene(s) for review')),
    );
  }

  Future<void> _import() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Import review comments (JSON)',
      type: FileType.custom,
      allowedExtensions: ['json'],
      lockParentWindow: true,
    );
    final path = result?.files.single.path;
    if (path == null) return;

    final service = await ref.read(
      reviewExportServiceProvider(widget.project).future,
    );
    final ReviewImportResult imported;
    try {
      imported = await service.importComments(await File(path).readAsString());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read that file: $error')),
        );
      }
      return;
    }

    if (!mounted) return;
    final message = imported.unknown == 0
        ? 'Imported ${imported.imported} comment(s)'
        : 'Imported ${imported.imported} comment(s), ${imported.unknown} anchor(s) not recognized';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final columnsAsync = ref.watch(sceneColumnsProvider(widget.project));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Export / Import for Review'),
        actions: [
          IconButton(
            tooltip: 'Import Review Comments',
            icon: const Icon(Icons.download_outlined),
            onPressed: _import,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: columnsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) =>
            Center(child: Text('Failed to load manuscript: $err')),
        data: (columns) {
          if (columns.isEmpty) {
            return const Center(child: Text('No scenes to export yet.'));
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(
                        () => _selected.addAll(columns.map((c) => c.$1)),
                      ),
                      child: const Text('Select All'),
                    ),
                    TextButton(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => setState(_selected.clear),
                      child: const Text('Clear'),
                    ),
                    const Spacer(),
                    Text('${_selected.length} of ${columns.length} selected'),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: [
                    for (final (id, title) in columns)
                      CheckboxListTile(
                        value: _selected.contains(id),
                        title: Text(title),
                        onChanged: (checked) => setState(() {
                          if (checked ?? false) {
                            _selected.add(id);
                          } else {
                            _selected.remove(id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(
                    _selected.isEmpty
                        ? 'Select scenes to export'
                        : 'Export ${_selected.length} scene(s) for review',
                  ),
                  onPressed: _selected.isEmpty ? null : () => _export(columns),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
