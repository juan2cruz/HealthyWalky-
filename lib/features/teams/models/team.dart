class Team {
  final String id;
  final String companyId;
  final String name;
  final String? description;
  final String createdBy;
  final String status;
  final String? challengeId;
  final String? disqualificationReason;
  final DateTime? disqualifiedAt;
  final DateTime createdAt;

  const Team({
    required this.id,
    required this.companyId,
    required this.name,
    this.description,
    required this.createdBy,
    required this.status,
    this.challengeId,
    this.disqualificationReason,
    this.disqualifiedAt,
    required this.createdAt,
  });

  // Status getters
  bool get isDraft => status == 'draft';
  bool get isApproved => status == 'approved';
  bool get isEnrolled => status == 'enrolled';
  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';
  bool get isDisqualified => status == 'disqualified';
  bool get isArchived => status == 'archived';

  // Check if user is the creator
  bool isUserCreator(String userId) => createdBy == userId;

  // Can add members (pre-active)
  bool get canAddMembers => !isActive && !isCompleted;

  factory Team.fromMap(Map<String, dynamic> map) => Team(
    id: map['id'] as String,
    companyId: map['company_id'] as String,
    name: map['name'] as String,
    description: map['description'] as String?,
    createdBy: map['created_by'] as String,
    status: map['status'] as String,
    challengeId: map['challenge_id'] as String?,
    disqualificationReason: map['disqualification_reason'] as String?,
    disqualifiedAt: map['disqualified_at'] != null 
      ? DateTime.parse(map['disqualified_at'] as String)
      : null,
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}
