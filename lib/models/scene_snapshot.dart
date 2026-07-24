/// Auto snapshots capture on-save; checkpoints are manually named and never
/// pruned (PLAN.md "Version History").
enum SnapshotType { auto, checkpoint }

/// One entry in a scene's history. [patchText] is a `diff_match_patch`
/// patch (serialized to text) from the *previous kept snapshot's* content to
/// this snapshot's content — not a full copy, per PLAN.md. Reconstructing
/// any snapshot's actual text means replaying the chain from the start; see
/// SceneHistoryService.reconstructContent.
class SceneSnapshot {
  final DateTime timestamp;
  final SnapshotType type;
  final String? label;
  final String patchText;
  final int wordCount;

  const SceneSnapshot({
    required this.timestamp,
    required this.type,
    this.label,
    required this.patchText,
    required this.wordCount,
  });

  /// Filename-safe id — also used as the on-disk filename stem.
  String get id => timestamp.toIso8601String().replaceAll(':', '-');

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
        if (label != null) 'label': label,
        'patchText': patchText,
        'wordCount': wordCount,
      };

  factory SceneSnapshot.fromJson(Map<String, dynamic> json) => SceneSnapshot(
        timestamp: DateTime.parse(json['timestamp'] as String),
        type: SnapshotType.values.firstWhere((t) => t.name == json['type']),
        label: json['label'] as String?,
        patchText: json['patchText'] as String,
        wordCount: json['wordCount'] as int,
      );
}
