class TeamLeaderboardEntry {
  final int ranking;
  final String teamId;
  final String teamName;
  final int memberCount;
  final int avgSteps;

  const TeamLeaderboardEntry({
    required this.ranking,
    required this.teamId,
    required this.teamName,
    required this.memberCount,
    required this.avgSteps,
  });

  // From get_team_leaderboard RPC result
  factory TeamLeaderboardEntry.fromMap(Map<String, dynamic> map) =>
      TeamLeaderboardEntry(
        ranking: (map['ranking'] as num).toInt(),
        teamId: map['team_id'] as String,
        teamName: map['team_name'] as String,
        memberCount: (map['member_count'] as num).toInt(),
        avgSteps: (map['avg_steps'] as num).toInt(),
      );

  // From leaderboard_snapshots table (Realtime stream)
  factory TeamLeaderboardEntry.fromSnapshot(Map<String, dynamic> map) =>
      TeamLeaderboardEntry(
        ranking: (map['rank'] as num).toInt(),
        teamId: map['entity_id'] as String,
        teamName: map['entity_name'] as String,
        memberCount: (map['member_count'] as num).toInt(),
        avgSteps: (map['avg_steps'] as num).toInt(),
      );
}
