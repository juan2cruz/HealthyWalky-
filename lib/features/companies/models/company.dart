class Company {
  final String id;
  final String name;
  final String slug;
  final String? logoUrl;
  final String plan;
  final DateTime createdAt;

  const Company({
    required this.id,
    required this.name,
    required this.slug,
    this.logoUrl,
    required this.plan,
    required this.createdAt,
  });

  factory Company.fromMap(Map<String, dynamic> map) => Company(
        id: map['id'] as String,
        name: map['name'] as String,
        slug: map['slug'] as String,
        logoUrl: map['logo_url'] as String?,
        plan: map['plan'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
