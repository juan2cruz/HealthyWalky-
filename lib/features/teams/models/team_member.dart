class TeamMember {
  final String id;
  final String teamId;
  final String userId;
  final String status;
  final String? challengeId;
  final DateTime? expelledAt;
  final String? expelledReason;
  final DateTime joinedAt;

  const TeamMember({
    required this.id,
    required this.teamId,
    required this.userId,
    required this.status,
    this.challengeId,
    this.expelledAt,
    this.expelledReason,
    required this.joinedAt,
  });

  // Status getters
  bool get isInvited => status == 'invited';
  bool get isRequestPending => status == 'request_pending';
  bool get isActive => status == 'active';
  bool get isRejected => status == 'rejected';
  bool get isExpelled => status == 'expelled';

  // Visibility
  bool get canRespond => isInvited || isRequestPending;

  factory TeamMember.fromMap(Map<String, dynamic> map) => TeamMember(
    id: map['id'] as String,
    teamId: map['team_id'] as String,
    userId: map['user_id'] as String,
    status: map['status'] as String,
    challengeId: map['challenge_id'] as String?,
    expelledAt: map['expelled_at'] != null
      ? DateTime.parse(map['expelled_at'] as String)
      : null,
    expelledReason: map['expelled_reason'] as String?,
    joinedAt: DateTime.parse(map['joined_at'] as String),
  );
}
