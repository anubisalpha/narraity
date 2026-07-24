/// Manuscript structure — a generic, arbitrary-depth tree, not a hardcoded
/// Act > Chapter > Scene hierarchy. Different writers organize differently
/// (chapters only, acts with scenes and no chapters, chapters containing
/// acts, ...), so every [ManuscriptNode] carries its own freeform
/// [ManuscriptNode.typeLabel] ("Act", "Chapter", "Book", "Part", whatever
/// the writer calls it) and can have children regardless of what's above or
/// below it in the tree. Every node holds its own prose *and* may have
/// children at the same time — a Chapter can be written in directly and
/// later broken into Scene children, no upfront container/leaf choice
/// required. A project's initial shape is picked once at creation (see
/// `manuscript_seeds.dart` for the starter presets) purely as a convenience
/// seed — nothing stops adding a node with a new label at any depth
/// afterward, so nothing is ever really "locked in."
///
/// Plus special front/back matter sections that sit outside the tree
/// entirely (PLAN.md "Manuscript Structure & Formatting") — prologues,
/// epilogues etc. aren't part of "which hierarchy do you use," they're
/// orthogonal.
///
/// Ordering lives in `manuscript/structure.json`; scene prose lives in one
/// Markdown file per node (`manuscript/scenes/<id>.md`) with light
/// front-matter. Stable ids (never renumbered) keep version history and
/// future comment anchors attached across reorders.
library;

enum SpecialSectionType { prologue, epilogue, dedication, authorsNote }

extension SpecialSectionTypeLabel on SpecialSectionType {
  String get label => switch (this) {
        SpecialSectionType.prologue => 'Prologue',
        SpecialSectionType.epilogue => 'Epilogue',
        SpecialSectionType.dedication => 'Dedication',
        SpecialSectionType.authorsNote => "Author's Note",
      };

  /// Front matter renders before the first node; back matter after the last.
  bool get isFrontMatter =>
      this == SpecialSectionType.prologue || this == SpecialSectionType.dedication;
}

class SpecialSection {
  final String id;
  final SpecialSectionType type;
  String title;

  SpecialSection({required this.id, required this.type, String? title})
      : title = title ?? type.label;

  Map<String, dynamic> toJson() => {'id': id, 'type': type.name, 'title': title};

  factory SpecialSection.fromJson(Map<String, dynamic> json) => SpecialSection(
        id: json['id'] as String,
        type: SpecialSectionType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => SpecialSectionType.authorsNote,
        ),
        title: json['title'] as String?,
      );
}

/// One node in the manuscript tree. Every node holds its own prose (backed
/// by a `SceneDoc` file, the thing SceneEditor/SceneHistoryService operate
/// on) *and* can have child nodes beneath it — the two aren't exclusive.
/// A "Chapter" can be written in directly and also broken into "Scene"
/// children later; nothing forces a choice between "holds text" and
/// "organizes subsections" up front.
class ManuscriptNode {
  final String id;
  String title;
  String typeLabel;
  final List<ManuscriptNode> children;

  ManuscriptNode({
    required this.id,
    required this.title,
    required this.typeLabel,
    List<ManuscriptNode>? children,
  }) : children = children ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'typeLabel': typeLabel,
        'children': children.map((c) => c.toJson()).toList(),
      };

  factory ManuscriptNode.fromJson(Map<String, dynamic> json) => ManuscriptNode(
        id: json['id'] as String,
        title: json['title'] as String,
        typeLabel: json['typeLabel'] as String,
        children: (json['children'] as List<dynamic>? ?? [])
            .map((c) => ManuscriptNode.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  /// This node's own content id plus every descendant's, in document order
  /// (a node's own prose reads before its subsections').
  List<String> get contentIds => [id, for (final child in children) ...child.contentIds];
}

class ManuscriptStructure {
  final List<SpecialSection> frontMatter;
  final List<ManuscriptNode> nodes;
  final List<SpecialSection> backMatter;

  ManuscriptStructure({
    List<SpecialSection>? frontMatter,
    List<ManuscriptNode>? nodes,
    List<SpecialSection>? backMatter,
  })  : frontMatter = frontMatter ?? [],
        nodes = nodes ?? [],
        backMatter = backMatter ?? [];

  Map<String, dynamic> toJson() => {
        'frontMatter': frontMatter.map((s) => s.toJson()).toList(),
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'backMatter': backMatter.map((s) => s.toJson()).toList(),
      };

  factory ManuscriptStructure.fromJson(Map<String, dynamic> json) =>
      ManuscriptStructure(
        frontMatter: (json['frontMatter'] as List<dynamic>? ?? [])
            .map((s) => SpecialSection.fromJson(s as Map<String, dynamic>))
            .toList(),
        nodes: (json['nodes'] as List<dynamic>? ?? [])
            .map((n) => ManuscriptNode.fromJson(n as Map<String, dynamic>))
            .toList(),
        backMatter: (json['backMatter'] as List<dynamic>? ?? [])
            .map((s) => SpecialSection.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  /// Every content id (nodes + special sections) in reading order.
  List<String> get allContentIds => [
        for (final s in frontMatter) s.id,
        for (final node in nodes) ...node.contentIds,
        for (final s in backMatter) s.id,
      ];

  /// Total content-node count under (and including) a node — used for
  /// "N items" style summaries in the tree and section overview.
  static int contentCount(ManuscriptNode node) => node.contentIds.length;
}

/// A leaf's editable content: markdown prose plus per-node metadata kept in
/// the file's front-matter block.
class SceneDoc {
  final String id;
  String title;
  String content;
  String? pov;

  SceneDoc({required this.id, required this.title, this.content = '', this.pov});

  int get wordCount {
    final words = content.trim().split(RegExp(r'\s+'));
    return (words.length == 1 && words.first.isEmpty) ? 0 : words.length;
  }
}
