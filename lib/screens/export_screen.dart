import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../services/export/docx_exporter.dart';
import '../services/export/epub_exporter.dart';
import '../services/export/pdf_exporter.dart';
import '../services/export/txt_exporter.dart';
import '../services/filename_sanitizer.dart';
import '../services/manuscript_service.dart';
import '../state/drive_provider.dart' show projectDirectory;
import '../state/library_provider.dart';

enum ExportFormat { pdf, docx, epub, txt }

extension on ExportFormat {
  String get label => switch (this) {
        ExportFormat.pdf => 'PDF',
        ExportFormat.docx => 'Word document (.docx)',
        ExportFormat.epub => 'EPUB (e-reader/Kindle)',
        ExportFormat.txt => 'Plain text (.txt)',
      };

  String get subtitle => switch (this) {
        ExportFormat.pdf => 'Full fidelity — formatting, headings, page layout.',
        ExportFormat.docx => 'Full fidelity, editable in Word.',
        ExportFormat.epub => 'Reflowable e-book with a table of contents.',
        ExportFormat.txt => 'Formatting and images are dropped — bare text only.',
      };

  String get fileExtension => switch (this) {
        ExportFormat.pdf => 'pdf',
        ExportFormat.docx => 'docx',
        ExportFormat.epub => 'epub',
        ExportFormat.txt => 'txt',
      };
}

/// General export (PLAN.md Phase 6): PDF, DOCX, EPUB, and an explicit
/// stripped-down plain-text option. KDP-specific print/trim-size concerns
/// (Phase 6.3) aren't part of this screen — those need their own
/// margin/bleed/trim-size UI, not built yet.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key, required this.project});

  final Project project;

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  ExportFormat _format = ExportFormat.pdf;
  bool _busy = false;
  String? _error;

  Future<bool> _confirmTxtWarning() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export as plain text?'),
        content: const Text(
          'Plain text export drops all formatting (bold, italic, headings, quotes) and cannot '
          'include images. Use this only if you specifically need bare, unformatted text.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _export() async {
    if (_format == ExportFormat.txt && !await _confirmTxtWarning()) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Export "${widget.project.title}"',
        fileName:
            '${sanitizeFileName(widget.project.title)}.${_format.fileExtension}',
        type: FileType.custom,
        allowedExtensions: [_format.fileExtension],
        lockParentWindow: true,
      );
      if (path == null) return; // user cancelled

      final library = ref.read(libraryServiceProvider);
      final projectDir = await projectDirectory(library, widget.project);
      final manuscript = ManuscriptService(projectDir);
      final structure = await manuscript.loadStructure();

      switch (_format) {
        case ExportFormat.pdf:
          await PdfExporter(projectDir).exportToFile(widget.project, structure, path);
        case ExportFormat.docx:
          await DocxExporter(projectDir).exportToFile(widget.project, structure, path);
        case ExportFormat.epub:
          await EpubExporter(projectDir).exportToFile(widget.project, structure, path);
        case ExportFormat.txt:
          await TxtExporter(projectDir).exportToFile(widget.project, structure, path);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported to $path')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Export failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Export "${widget.project.title}"', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Card(
                child: RadioGroup<ExportFormat>(
                  groupValue: _format,
                  onChanged: _busy ? (_) {} : (value) => setState(() => _format = value!),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final format in ExportFormat.values)
                        RadioListTile<ExportFormat>(
                          value: format,
                          title: Text(format.label),
                          subtitle: Text(format.subtitle),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              FilledButton.icon(
                onPressed: _busy ? null : _export,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share),
                label: Text(_busy ? 'Exporting...' : 'Choose location & export'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
