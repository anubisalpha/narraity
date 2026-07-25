/// Auto snapshots capture on-save; checkpoints are manually named and never
/// pruned (PLAN.md "Version History").
enum SnapshotType { auto, checkpoint }

/// Result of checking a snapshot's tamper-evidence signature against its
/// place in the chain. See SceneHistoryService for how these are computed.
enum SnapshotVerification {
  /// Signature present and matches both this entry's own fields and the
  /// claimed link to the previous entry.
  valid,

  /// No signature field at all — written before tamper-evidence was added,
  /// or written while no vault password was unlocked. Trusted (there's
  /// nothing to check), but not proof of anything.
  legacyUnsigned,

  /// A signature is present, but no vault password is unlocked right now to
  /// derive the key and check it. Trusted for this read (real, previously
  /// signed history shouldn't get flagged as tampered just because nobody's
  /// entered the password this session) — re-verified properly next time
  /// the vault is unlocked.
  locked,

  /// A signature is present but doesn't match, or the claimed link to the
  /// previous entry is wrong — the file was edited, reordered, or spliced
  /// in after the fact by something other than this app.
  tampered,
}

/// One entry in a scene's history. [patchText] is a `diff_match_patch`
/// patch (serialized to text) from the *previous kept snapshot's* content to
/// this snapshot's content — not a full copy, per PLAN.md. Reconstructing
/// any snapshot's actual text means replaying the chain from the start; see
/// SceneHistoryService.reconstructContent.
///
/// [prevSignature]/[signature] form a tamper-evident chain: each entry signs
/// its own fields *plus* the previous entry's signature, keyed with a secret
/// derived from the vault password (see HistorySigningKeyManager) — never
/// stored in this folder. Editing, deleting, or reordering a file breaks the
/// link for everything after it, because reproducing a valid signature
/// without the key isn't possible.
class SceneSnapshot {
  final DateTime timestamp;
  final SnapshotType type;
  final String? label;
  final String patchText;
  final int wordCount;

  /// Signature of the previous kept snapshot in this scene's chain, or ''
  /// for the first entry (or the first entry after a run of legacy/unsigned
  /// ones). Present on every snapshot written by this app; defaults to ''
  /// when reading pre-existing files that predate signing.
  final String prevSignature;

  /// HMAC-SHA256 (hex) over this snapshot's own fields plus [prevSignature].
  /// Null on snapshots written before tamper-evidence existed.
  final String? signature;

  const SceneSnapshot({
    required this.timestamp,
    required this.type,
    this.label,
    required this.patchText,
    required this.wordCount,
    this.prevSignature = '',
    this.signature,
  });

  /// Filename-safe id — also used as the on-disk filename stem.
  String get id => timestamp.toIso8601String().replaceAll(':', '-');

  /// The exact text signed to produce [signature]. Order and separators are
  /// part of the contract — changing this invalidates every existing
  /// signature, so treat it as a stable format, not an implementation detail.
  String canonicalPayload() =>
      '${timestamp.toIso8601String()}|${type.name}|${label ?? ''}|$patchText|$wordCount|$prevSignature';

  SceneSnapshot copyWith({String? prevSignature, String? signature}) => SceneSnapshot(
        timestamp: timestamp,
        type: type,
        label: label,
        patchText: patchText,
        wordCount: wordCount,
        prevSignature: prevSignature ?? this.prevSignature,
        signature: signature ?? this.signature,
      );

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
        if (label != null) 'label': label,
        'patchText': patchText,
        'wordCount': wordCount,
        'prevSignature': prevSignature,
        if (signature != null) 'signature': signature,
      };

  factory SceneSnapshot.fromJson(Map<String, dynamic> json) => SceneSnapshot(
        timestamp: DateTime.parse(json['timestamp'] as String),
        type: SnapshotType.values.firstWhere((t) => t.name == json['type']),
        label: json['label'] as String?,
        patchText: json['patchText'] as String,
        wordCount: json['wordCount'] as int,
        prevSignature: json['prevSignature'] as String? ?? '',
        signature: json['signature'] as String?,
      );
}

/// A snapshot paired with its verification outcome, for UI that needs to
/// show a "these entries failed verification" banner rather than just
/// silently dropping them.
class VerifiedSnapshot {
  const VerifiedSnapshot(this.snapshot, this.status);

  final SceneSnapshot snapshot;
  final SnapshotVerification status;
}
