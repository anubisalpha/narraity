/// Manuscript structure — acts > chapters > scenes, plus special front/back
/// matter sections that sit outside act/chapter numbering (PLAN.md
/// "Manuscript Structure & Formatting").
///
/// Ordering lives in `manuscript/structure.json`; scene prose lives in one
/// Markdown file per scene (`manuscript/scenes/scene-<id>.md`) with light
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

  /// Front matter renders before Act 1; back matter after the final act.
  bool get isFrontMatter =>
      this == SpecialSectionType.prologue || this == SpecialSectionType.dedication;
}

class SceneRef {
  final String id;
  String title;

  SceneRef({required this.id, required this.title});

  Map<String, dynamic> toJson() => {'id': id, 'title': title};

  factory SceneRef.fromJson(Map<String, dynamic> json) =>
      SceneRef(id: json['id'] as String, title: json['title'] as String);
}

class ChapterNode {
  final String id;
  String title;
  final List<SceneRef> scenes;

  ChapterNode({required this.id, required this.title, List<SceneRef>? scenes})
      : scenes = scenes ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'scenes': scenes.map((s) => s.toJson()).toList(),
      };

  factory ChapterNode.fromJson(Map<String, dynamic> json) => ChapterNode(
        id: json['id'] as String,
        title: json['title'] as String,
        scenes: (json['scenes'] as List<dynamic>? ?? [])
            .map((s) => SceneRef.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

class ActNode {
  final String id;
  String title;
  final List<ChapterNode> chapters;

  ActNode({required this.id, required this.title, List<ChapterNode>? chapters})
      : chapters = chapters ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'chapters': chapters.map((c) => c.toJson()).toList(),
      };

  factory ActNode.fromJson(Map<String, dynamic> json) => ActNode(
        id: json['id'] as String,
        title: json['title'] as String,
        chapters: (json['chapters'] as List<dynamic>? ?? [])
            .map((c) => ChapterNode.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
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

class ManuscriptStructure {
  final List<ActNode> acts;
  final List<SpecialSection> frontMatter;
  final List<SpecialSection> backMatter;

  ManuscriptStructure({
    List<ActNode>? acts,
    List<SpecialSection>? frontMatter,
    List<SpecialSection>? backMatter,
  })  : acts = acts ?? [],
        frontMatter = frontMatter ?? [],
        backMatter = backMatter ?? [];

  Map<String, dynamic> toJson() => {
        'acts': acts.map((a) => a.toJson()).toList(),
        'frontMatter': frontMatter.map((s) => s.toJson()).toList(),
        'backMatter': backMatter.map((s) => s.toJson()).toList(),
      };

  factory ManuscriptStructure.fromJson(Map<String, dynamic> json) =>
      ManuscriptStructure(
        acts: (json['acts'] as List<dynamic>? ?? [])
            .map((a) => ActNode.fromJson(a as Map<String, dynamic>))
            .toList(),
        frontMatter: (json['frontMatter'] as List<dynamic>? ?? [])
            .map((s) => SpecialSection.fromJson(s as Map<String, dynamic>))
            .toList(),
        backMatter: (json['backMatter'] as List<dynamic>? ?? [])
            .map((s) => SpecialSection.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  /// Every content id (scenes + special sections) in reading order.
  List<String> get allContentIds => [
        for (final s in frontMatter) s.id,
        for (final act in acts)
          for (final chapter in act.chapters)
            for (final scene in chapter.scenes) scene.id,
        for (final s in backMatter) s.id,
      ];
}

/// A scene's editable content: markdown prose plus per-scene metadata kept in
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
