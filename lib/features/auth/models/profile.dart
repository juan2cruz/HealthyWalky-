class Profile {
  final String id;
  final String companyId;
  final String displayName;
  final String? avatarUrl;
  final String role;
  final DateTime createdAt;

  const Profile({
    required this.id,
    required this.companyId,
    required this.displayName,
    this.avatarUrl,
    required this.role,
    required this.createdAt,
  });

  bool get isAdmin => role == 'admin';

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        companyId: map['company_id'] as String,
        displayName: map['display_name'] as String,
        avatarUrl: map['avatar_url'] as String?,
        role: map['role'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
