/// The author's own log of a manuscript copy sent out for beta/ARC review —
/// who has it, when it went out, when it's due back, and how it went.
/// Deliberately separate from [ReviewSession] (the *reviewer's* own
/// paragraph-comment tool for an exported file) — this tracks the send
/// itself, and may optionally link to a [ReviewSession.id] once that
/// reviewer's comments come back. Mirrors `planning/reviewers.json`.
class ReviewerSend {
  ReviewerSend({
    required this.id,
    required this.contactId,
    this.format = '',
    required this.dateSent,
    this.targetDeadline,
    this.dateReturned,
    this.declined = false,
    this.rating,
    this.feedbackNotes = '',
    this.linkedReviewSessionId,
  });

  final String id;
  String contactId;
  String format;
  DateTime dateSent;
  DateTime? targetDeadline;
  DateTime? dateReturned;
  bool declined;
  int? rating;
  String feedbackNotes;
  String? linkedReviewSessionId;

  /// Computed, not stored — mirrors [PlanningMilestone.statusAsOf].
  ReviewerSendStatus statusAsOf(DateTime now) {
    if (declined) return ReviewerSendStatus.declined;
    if (dateReturned != null) return ReviewerSendStatus.returned;
    final deadline = targetDeadline;
    if (deadline != null && deadline.isBefore(now)) {
      return ReviewerSendStatus.overdue;
    }
    return ReviewerSendStatus.inProgress;
  }

  int? get turnaroundDays => dateReturned?.difference(dateSent).inDays;

  ReviewerSend copyWith({
    String? contactId,
    String? format,
    DateTime? dateSent,
    DateTime? targetDeadline,
    bool clearTargetDeadline = false,
    DateTime? dateReturned,
    bool clearDateReturned = false,
    bool? declined,
    int? rating,
    bool clearRating = false,
    String? feedbackNotes,
    String? linkedReviewSessionId,
  }) => ReviewerSend(
    id: id,
    contactId: contactId ?? this.contactId,
    format: format ?? this.format,
    dateSent: dateSent ?? this.dateSent,
    targetDeadline: clearTargetDeadline
        ? null
        : (targetDeadline ?? this.targetDeadline),
    dateReturned: clearDateReturned ? null : (dateReturned ?? this.dateReturned),
    declined: declined ?? this.declined,
    rating: clearRating ? null : (rating ?? this.rating),
    feedbackNotes: feedbackNotes ?? this.feedbackNotes,
    linkedReviewSessionId: linkedReviewSessionId ?? this.linkedReviewSessionId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'contactId': contactId,
    'format': format,
    'dateSent': dateSent.toIso8601String(),
    if (targetDeadline != null) 'targetDeadline': targetDeadline!.toIso8601String(),
    if (dateReturned != null) 'dateReturned': dateReturned!.toIso8601String(),
    'declined': declined,
    if (rating != null) 'rating': rating,
    'feedbackNotes': feedbackNotes,
    if (linkedReviewSessionId != null)
      'linkedReviewSessionId': linkedReviewSessionId,
  };

  factory ReviewerSend.fromJson(Map<String, dynamic> json) => ReviewerSend(
    id: json['id'] as String,
    contactId: json['contactId'] as String,
    format: json['format'] as String? ?? '',
    dateSent: DateTime.parse(json['dateSent'] as String),
    targetDeadline: json['targetDeadline'] == null
        ? null
        : DateTime.parse(json['targetDeadline'] as String),
    dateReturned: json['dateReturned'] == null
        ? null
        : DateTime.parse(json['dateReturned'] as String),
    declined: json['declined'] as bool? ?? false,
    rating: json['rating'] as int?,
    feedbackNotes: json['feedbackNotes'] as String? ?? '',
    linkedReviewSessionId: json['linkedReviewSessionId'] as String?,
  );
}

enum ReviewerSendStatus { inProgress, returned, overdue, declined }
