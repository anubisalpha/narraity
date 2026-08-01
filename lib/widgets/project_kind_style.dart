import 'package:flutter/material.dart';

import '../models/project.dart';

/// Label, icon, and frame accent for each [ProjectKind] — the one place this
/// mapping lives, since both the New Project dialog's picker and the
/// library grid's card frame need the exact same association. Purely
/// cosmetic (see `ProjectKind`'s own doc comment): no manuscript/editor/
/// export behavior depends on any of this.
class ProjectKindStyle {
  const ProjectKindStyle({
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String label;
  final IconData icon;

  /// A representative color used for the card's frame accent — resolved
  /// against the current theme where it's actually painted (see
  /// [borderColor]), not fixed here, so it stays reasonable across light and
  /// dark mode instead of one hardcoded hex value.
  final Color Function(ColorScheme scheme) accent;

  static const _styles = {
    ProjectKind.novel: ProjectKindStyle(
      label: 'Novel',
      icon: Icons.menu_book,
      accent: _novelAccent,
    ),
    ProjectKind.comic: ProjectKindStyle(
      label: 'Comic',
      icon: Icons.auto_stories,
      accent: _comicAccent,
    ),
    ProjectKind.script: ProjectKindStyle(
      label: 'Script',
      icon: Icons.description_outlined,
      accent: _scriptAccent,
    ),
  };

  static Color _novelAccent(ColorScheme scheme) => scheme.primary;
  static Color _comicAccent(ColorScheme scheme) => scheme.tertiary;
  static Color _scriptAccent(ColorScheme scheme) => scheme.secondary;

  static ProjectKindStyle of(ProjectKind kind) => _styles[kind]!;
}

/// A per-[ProjectKind] frame around a library card's content — a book-
/// spine-style thick left edge for Novel, a bold all-around panel border
/// for Comic, and a thin, understated rule for Script (evoking a plain
/// title/script page) — same underlying card layout for all three (per the
/// "distinct border/frame + icon" scope decision, not a bespoke layout per
/// kind), just a different [Border] and accent color.
class ProjectKindFrame extends StatelessWidget {
  const ProjectKindFrame({super.key, required this.kind, required this.child});

  final ProjectKind kind;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = ProjectKindStyle.of(kind).accent(scheme);

    final border = switch (kind) {
      ProjectKind.novel => Border(left: BorderSide(color: color, width: 6)),
      ProjectKind.comic => Border.all(color: color, width: 2.5),
      ProjectKind.script => Border(top: BorderSide(color: color, width: 2)),
    };

    return Container(
      decoration: BoxDecoration(
        border: border,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
