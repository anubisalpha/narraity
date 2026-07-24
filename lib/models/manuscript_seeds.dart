import 'package:uuid/uuid.dart';

import 'manuscript.dart';

const _uuid = Uuid();

ManuscriptNode _node(String typeLabel, String title, [List<ManuscriptNode> children = const []]) =>
    ManuscriptNode(
      id: '${typeLabel.toLowerCase()}-${_uuid.v4()}',
      title: title,
      typeLabel: typeLabel,
      children: children,
    );

/// One-click starting shapes for a new project — picked once at creation
/// (see ManuscriptStructure's doc comment for why "locked at creation"
/// doesn't mean the tree is rigid afterward). These are exactly the five
/// examples requested, plus a blank/custom option.
enum ManuscriptSeed {
  actChapterScene,
  chaptersOnly,
  actScenes,
  chapterActScene,
  chapterScenes,
  blank,
}

extension ManuscriptSeedInfo on ManuscriptSeed {
  String get label => switch (this) {
        ManuscriptSeed.actChapterScene => 'Act → Chapter → Scene',
        ManuscriptSeed.chaptersOnly => 'Chapters only',
        ManuscriptSeed.actScenes => 'Act → Scenes',
        ManuscriptSeed.chapterActScene => 'Chapter → Act → Scene',
        ManuscriptSeed.chapterScenes => 'Chapter → Scenes',
        ManuscriptSeed.blank => 'Start blank / custom',
      };

  String get description => switch (this) {
        ManuscriptSeed.actChapterScene => 'The classic three-level structure.',
        ManuscriptSeed.chaptersOnly =>
          'Chapters hold your prose directly — no scene subdivision.',
        ManuscriptSeed.actScenes => 'Acts contain scenes directly, no chapters.',
        ManuscriptSeed.chapterActScene => 'Chapters group acts, which group scenes.',
        ManuscriptSeed.chapterScenes => 'Chapters contain scenes, no acts.',
        ManuscriptSeed.blank =>
          'Start with one untitled scene and build your own structure as you go — '
              'you can add and label sections however you like at any time.',
      };

  List<ManuscriptNode> buildStarter() => switch (this) {
        ManuscriptSeed.actChapterScene => [
            _node('Act', 'Act 1', [
              _node('Chapter', 'Chapter 1', [_node('Scene', 'Scene 1')]),
            ]),
          ],
        ManuscriptSeed.chaptersOnly => [_node('Chapter', 'Chapter 1')],
        ManuscriptSeed.actScenes => [
            _node('Act', 'Act 1', [_node('Scene', 'Scene 1')]),
          ],
        ManuscriptSeed.chapterActScene => [
            _node('Chapter', 'Chapter 1', [
              _node('Act', 'Act 1', [_node('Scene', 'Scene 1')]),
            ]),
          ],
        ManuscriptSeed.chapterScenes => [
            _node('Chapter', 'Chapter 1', [_node('Scene', 'Scene 1')]),
          ],
        ManuscriptSeed.blank => [_node('Scene', 'Scene 1')],
      };
}
