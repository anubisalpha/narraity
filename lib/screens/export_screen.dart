import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../services/export/docx_exporter.dart';
import '../services/export/epub_exporter.dart';
import '../services/export/kdp_hardcover_exporter.dart';
import '../services/export/kdp_paperback_exporter.dart';
import '../services/export/pdf_exporter.dart';
import '../services/export/txt_exporter.dart';
import '../services/filename_sanitizer.dart';
import '../services/manuscript_service.dart';
import '../state/drive_provider.dart' show projectDirectory;
import '../state/library_provider.dart';

enum ExportFormat { pdf, docx, epub, txt, kdpPaperback, kdpHardcover }

extension on ExportFormat {
  String get label => switch (this) {
        ExportFormat.pdf => 'PDF',
        ExportFormat.docx => 'Word document (.docx)',
        ExportFormat.epub => 'EPUB (e-reader/Kindle)',
        ExportFormat.txt => 'Plain text (.txt)',
        ExportFormat.kdpPaperback => 'KDP Paperback (print-ready PDF)',
        ExportFormat.kdpHardcover => 'KDP Hardcover (print-ready PDF)',
      };

  String get subtitle => switch (this) {
        ExportFormat.pdf => 'Full fidelity — formatting, headings, page layout.',
        ExportFormat.docx => 'Full fidelity, editable in Word.',
        ExportFormat.epub =>
          'Reflowable e-book with a table of contents — already KDP-compliant '
              '(2-level ToC cap, footnotes, size limits).',
        ExportFormat.txt => 'Formatting and images are dropped — bare text only.',
        ExportFormat.kdpPaperback =>
          'Trim size, bleed, and KDP\'s page-count-scaled margins/numbering — interior file '
              'only, no cover.',
        ExportFormat.kdpHardcover =>
          'Same as Paperback, with hardcover\'s own trim sizes and page-count range — interior '
              'file only, no cover.',
      };

  bool get isKdpPrint => this == ExportFormat.kdpPaperback || this == ExportFormat.kdpHardcover;

  String get fileExtension => switch (this) {
        ExportFormat.pdf ||
        ExportFormat.kdpPaperback ||
        ExportFormat.kdpHardcover =>
          'pdf',
        ExportFormat.docx => 'docx',
        ExportFormat.epub => 'epub',
        ExportFormat.txt => 'txt',
      };
}

String _trimSizeLabel(KdpPrintTrimSize trim) {
  String fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  return '${fmt(trim.widthIn)}" × ${fmt(trim.heightIn)}"';
}

String _inkPaperLabel(KdpInkPaperType type) => switch (type) {
      KdpInkPaperType.blackWhite => 'Black & white ink, white paper',
      KdpInkPaperType.blackCream => 'Black & white ink, cream paper',
      KdpInkPaperType.groundwood => 'Black & white ink, groundwood paper',
      KdpInkPaperType.standardColor => 'Standard color ink, white paper',
      KdpInkPaperType.premiumColor => 'Premium color ink, white paper',
    };

/// General export (PLAN.md Phase 6) plus KDP-ready print export (Phase 6.3):
/// PDF, DOCX, EPUB (already KDP-eBook-compliant, no separate option needed),
/// an explicit stripped-down plain-text option, and KDP Paperback/Hardcover
/// (their own trim size + bleed picker, shown only when one of those two is
/// selected). Cover generation is out of scope for all of these — every
/// format here produces the interior/manuscript file only.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key, required this.project});

  final Project project;

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  ExportFormat _format = ExportFormat.pdf;
  KdpTrimSize _paperbackTrimSize = KdpTrimSize.in6x9;
  KdpInkPaperType _inkPaperType = KdpInkPaperType.blackWhite;
  KdpHardcoverTrimSize _hardcoverTrimSize = KdpHardcoverTrimSize.in6x9;
  bool _bleed = false;
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
        case ExportFormat.kdpPaperback:
          await KdpPaperbackExporter(projectDir).exportToFile(
            widget.project,
            structure,
            path,
            trimSize: _paperbackTrimSize,
            bleed: _bleed,
            inkPaperType: _inkPaperType,
          );
        case ExportFormat.kdpHardcover:
          await KdpHardcoverExporter(projectDir).exportToFile(
            widget.project,
            structure,
            path,
            trimSize: _hardcoverTrimSize,
            bleed: _bleed,
          );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported to $path')));
      }
    } catch (error) {
      // KdpPrintExportException's message is already a complete, user-facing
      // sentence (e.g. "This manuscript would be 40 pages, outside KDP's
      // paperback range of 75–550 pages.") — shown as-is, not wrapped in a
      // generic "Export failed" prefix that would just repeat itself.
      if (mounted) {
        setState(() => _error = error is KdpPrintExportException
            ? error.message
            : 'Export failed: $error');
      }
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
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Export "${widget.project.title}"',
                    style: Theme.of(context).textTheme.titleLarge),
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
                if (_format.isKdpPrint) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Trim size', style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 8),
                          if (_format == ExportFormat.kdpPaperback)
                            DropdownButtonFormField<KdpTrimSize>(
                              initialValue: _paperbackTrimSize,
                              isExpanded: true,
                              items: [
                                for (final trim in KdpTrimSize.values)
                                  DropdownMenuItem(
                                    value: trim,
                                    child: Text(
                                      trim == KdpTrimSize.in6x9
                                          ? '${_trimSizeLabel(trim)} (most common for novels)'
                                          : _trimSizeLabel(trim),
                                    ),
                                  ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (value) =>
                                      setState(() => _paperbackTrimSize = value!),
                            )
                          else
                            DropdownButtonFormField<KdpHardcoverTrimSize>(
                              initialValue: _hardcoverTrimSize,
                              isExpanded: true,
                              items: [
                                for (final trim in KdpHardcoverTrimSize.values)
                                  DropdownMenuItem(
                                    value: trim,
                                    child: Text(_trimSizeLabel(trim)),
                                  ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (value) =>
                                      setState(() => _hardcoverTrimSize = value!),
                            ),
                          if (_format == ExportFormat.kdpPaperback) ...[
                            const SizedBox(height: 16),
                            Text('Ink & paper', style: Theme.of(context).textTheme.labelLarge),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<KdpInkPaperType>(
                              initialValue: _inkPaperType,
                              isExpanded: true,
                              items: [
                                for (final type in KdpInkPaperType.values)
                                  DropdownMenuItem(
                                    value: type,
                                    child: Text(_inkPaperLabel(type)),
                                  ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() => _inkPaperType = value!),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              // KDP's allowed page-count range depends on this choice as well as
                              // trim size — surfaced here so a rejection at export time (if the
                              // manuscript falls outside that range) isn't a surprise.
                              'KDP\'s allowed page-count range depends on this choice.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            value: _bleed,
                            onChanged: _busy
                                ? null
                                : (value) => setState(() => _bleed = value ?? false),
                            title: const Text('Bleed'),
                            subtitle: const Text(
                              'Only if images or content run to the page edge — most text-only '
                              'novels don\'t need this.',
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Interior file only — cover generation isn\'t part of this. KDP\'s '
                            'own Cover Creator handles that separately.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
      ),
    );
  }
}
