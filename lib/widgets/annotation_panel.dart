import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/annotation.dart';
import '../models/project.dart';
import '../state/annotation_provider.dart';

/// Lists every comment/highlight/sticky-note/footnote on the currently open
/// scene, docked under the editor. Tapping a row calls [onJumpTo] so the
/// editor can select the anchored range and scroll it into view.
class AnnotationPanel extends ConsumerWidget {
  const AnnotationPanel({
    super.key,
    required this.project,
    required this.sceneId,
    required this.onJumpTo,
  });

  final Project project;
  final String sceneId;
  final void Function(Annotation annotation) onJumpTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annotationsAsync = ref.watch(sceneAnnotationsProvider((project, sceneId)));

    return annotationsAsync.when(
      loading: () => const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => SizedBox(
        height: 60,
        child: Center(child: Text('Failed to load annotations: $err')),
      ),
      data: (annotations) {
        if (annotations.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No comments, highlights, sticky notes, or footnotes on this scene yet.'),
          );
        }
        final sorted = [...annotations]
          ..sort((a, b) => a.anchor.start.compareTo(b.anchor.start));
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final annotation in sorted)
                _AnnotationTile(
                  project: project,
                  annotation: annotation,
                  onJumpTo: () => onJumpTo(annotation),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AnnotationTile extends ConsumerWidget {
  const _AnnotationTile({
    required this.project,
    required this.annotation,
    required this.onJumpTo,
  });

  final Project project;
  final Annotation annotation;
  final VoidCallback onJumpTo;

  static const _kindIcons = {
    AnnotationKind.comment: Icons.comment_outlined,
    AnnotationKind.highlight: Icons.format_color_fill,
    AnnotationKind.stickyNote: Icons.sticky_note_2_outlined,
    AnnotationKind.footnote: Icons.note_alt_outlined,
  };

  Future<void> _delete(WidgetRef ref) async {
    final service = await ref.read(annotationServiceProvider(project).future);
    await service.delete(annotation.id);
    invalidateSceneAnnotations(ref, project, annotation.sceneId);
  }

  Future<void> _toggleResolved(WidgetRef ref) async {
    final service = await ref.read(annotationServiceProvider(project).future);
    await service.update(annotation.copyWith(resolved: !annotation.resolved));
    invalidateSceneAnnotations(ref, project, annotation.sceneId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quoted = annotation.anchor.quotedText;
    final preview = quoted.isEmpty
        ? '(marker at cursor position)'
        : quoted.length > 60
            ? '${quoted.substring(0, 60)}…'
            : quoted;

    return ListTile(
      dense: true,
      leading: Icon(
        _kindIcons[annotation.kind],
        color: annotation.kind == AnnotationKind.highlight && annotation.color != null
            ? Color(annotation.color!)
            : null,
      ),
      title: Text('"$preview"', overflow: TextOverflow.ellipsis),
      subtitle: annotation.body.isEmpty ? null : Text(annotation.body),
      onTap: onJumpTo,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (annotation.kind == AnnotationKind.comment)
            IconButton(
              tooltip: annotation.resolved ? 'Mark unresolved' : 'Mark resolved',
              icon: Icon(
                annotation.resolved ? Icons.check_circle : Icons.check_circle_outline,
                size: 18,
              ),
              onPressed: () => _toggleResolved(ref),
            ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => _delete(ref),
          ),
        ],
      ),
    );
  }
}
