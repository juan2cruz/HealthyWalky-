class Challenge {
  final String id;
  final String companyId;
  final String title;
  final String? description;
  final DateTime startDate;
  final DateTime endDate;
  final String enrollmentType;
  final String status;
  final String? createdBy;
  final DateTime createdAt;

  const Challenge({
    required this.id,
    required this.companyId,
    required this.title,
    this.description,
    required this.startDate,
    required this.endDate,
    required this.enrollmentType,
    required this.status,
    this.createdBy,
    required this.createdAt,
  });

  bool get isDraft => status == 'draft';
  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
  bool get isIndividual => enrollmentType == 'individual';
  bool get isTeam => enrollmentType == 'team';

  factory Challenge.fromMap(Map<String, dynamic> map) => Challenge(
        id: map['id'] as String,
        companyId: map['company_id'] as String,
        title: map['title'] as String,
        description: map['description'] as String?,
        startDate: DateTime.parse(map['start_date'] as String),
        endDate: DateTime.parse(map['end_date'] as String),
        enrollmentType: map['enrollment_type'] as String,
        status: map['status'] as String,
        createdBy: map['created_by'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
