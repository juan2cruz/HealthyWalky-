import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthywalky/core/supabase/client.dart';
import 'package:healthywalky/features/teams/models/models.dart';
import 'package:healthywalky/features/teams/providers/team_provider.dart';
import 'package:healthywalky/features/auth/models/profile.dart';
import 'package:healthywalky/features/auth/providers/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Mock classes
class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

// ignore: must_be_immutable
class MockPostgrestFilterBuilder<T> extends Mock implements PostgrestFilterBuilder<T> {
  Future<T>? mockFuture;

  @override
  Future<R> then<R>(FutureOr<R> Function(T) onValue, {Function? onError}) {
    return (mockFuture ?? Future<T>.value()).then(onValue, onError: onError);
  }
}

// ignore: must_be_immutable
class MockPostgrestTransformBuilder<T> extends Mock implements PostgrestTransformBuilder<T> {
  Future<T>? mockFuture;

  @override
  Future<R> then<R>(FutureOr<R> Function(T) onValue, {Function? onError}) {
    return (mockFuture ?? Future<T>.value()).then(onValue, onError: onError);
  }
}

class MockProfile extends Mock implements Profile {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('Team Providers', () {
    late MockSupabaseClient mockSupabase;
    late MockSupabaseQueryBuilder mockQueryBuilder;
    late MockPostgrestFilterBuilder<List<Map<String, dynamic>>> mockFilterBuilder;
    late MockPostgrestTransformBuilder<List<Map<String, dynamic>>> mockTransformBuilder;
    late MockPostgrestTransformBuilder<Map<String, dynamic>?> mockSingleTransformBuilder;
    ProviderContainer? container;

    final testProfile = Profile(
      id: 'user-123',
      companyId: 'company-456',
      displayName: 'Test User',
      role: 'member',
      createdAt: DateTime.parse('2026-06-30T12:00:00Z'),
    );

    setUp(() {
      mockSupabase = MockSupabaseClient();
      mockQueryBuilder = MockSupabaseQueryBuilder();
      mockFilterBuilder = MockPostgrestFilterBuilder<List<Map<String, dynamic>>>();
      mockTransformBuilder = MockPostgrestTransformBuilder<List<Map<String, dynamic>>>();
      mockSingleTransformBuilder = MockPostgrestTransformBuilder<Map<String, dynamic>?>();
      mockSupabaseClient = mockSupabase;
      container = null;
    });

    tearDown(() {
      mockSupabaseClient = null;
      container?.dispose();
    });

    void mockRpc(String fn, {Map<String, dynamic>? params, required dynamic response}) {
      final rpcFilterBuilder = MockPostgrestFilterBuilder<dynamic>();
      rpcFilterBuilder.mockFuture = Future.value(response);

      if (params != null) {
        when(() => mockSupabase.rpc(fn, params: params)).thenAnswer((_) => rpcFilterBuilder);
      } else {
        when(() => mockSupabase.rpc(fn, params: any(named: 'params'))).thenAnswer((_) => rpcFilterBuilder);
      }
    }

    group('teamsProvider', () {
      test('returns empty list when profile is null', () async {
        container = ProviderContainer(
          overrides: [
            currentProfileProvider.overrideWith((ref) => null),
          ],
        );
        final teams = await container!.read(teamsProvider.future);
        expect(teams, isEmpty);
      });

      test('fetches teams from current company', () async {
        container = ProviderContainer(
          overrides: [
            currentProfileProvider.overrideWith((ref) async => testProfile),
          ],
        );

        final mockData = [
          {
            'id': 'team-1',
            'company_id': 'company-456',
            'name': 'Team Alpha',
            'status': 'active',
            'created_at': '2026-06-30T12:00:00Z',
            'created_by': 'user-123',
            'disqualification_reason': null,
            'disqualified_at': null,
            'challenge_id': null,
          }
        ];

        when(() => mockSupabase.from('teams')).thenAnswer((_) => mockQueryBuilder);
        when(() => mockQueryBuilder.select()).thenAnswer((_) => mockFilterBuilder);
        when(() => mockFilterBuilder.eq('company_id', 'company-456')).thenAnswer((_) => mockFilterBuilder);
        when(() => mockFilterBuilder.order('created_at', ascending: false)).thenAnswer((_) => mockTransformBuilder);
        mockTransformBuilder.mockFuture = Future.value(mockData);

        final teams = await container!.read(teamsProvider.future);
        expect(teams, hasLength(1));
        expect(teams.first.id, 'team-1');
        expect(teams.first.name, 'Team Alpha');
        verify(() => mockSupabase.from('teams')).called(1);
        verify(() => mockFilterBuilder.eq('company_id', 'company-456')).called(1);
      });

      test('maps raw data to Team objects', () async {
        container = ProviderContainer(
          overrides: [
            currentProfileProvider.overrideWith((ref) async => testProfile),
          ],
        );

        final mockData = [
          {
            'id': 'team-1',
            'company_id': 'company-456',
            'name': 'Team Alpha',
            'status': 'active',
            'created_at': '2026-06-30T12:00:00Z',
            'created_by': 'user-123',
            'disqualification_reason': null,
            'disqualified_at': null,
            'challenge_id': null,
          },
          {
            'id': 'team-2',
            'company_id': 'company-456',
            'name': 'Team Beta',
            'status': 'draft',
            'created_at': '2026-06-30T13:00:00Z',
            'created_by': 'user-456',
            'disqualification_reason': null,
            'disqualified_at': null,
            'challenge_id': null,
          }
        ];

        when(() => mockSupabase.from('teams')).thenAnswer((_) => mockQueryBuilder);
        when(() => mockQueryBuilder.select()).thenAnswer((_) => mockFilterBuilder);
        when(() => mockFilterBuilder.eq('company_id', 'company-456')).thenAnswer((_) => mockFilterBuilder);
        when(() => mockFilterBuilder.order('created_at', ascending: false)).thenAnswer((_) => mockTransformBuilder);
        mockTransformBuilder.mockFuture = Future.value(mockData);

        final teams = await container!.read(teamsProvider.future);
        expect(teams, hasLength(2));
        expect(teams[0].id, 'team-1');
        expect(teams[0].name, 'Team Alpha');
        expect(teams[0].status, 'active');
        expect(teams[1].id, 'team-2');
        expect(teams[1].name, 'Team Beta');
        expect(teams[1].status, 'draft');
      });
    });

    group('teamByIdProvider', () {
      test('returns single team by id', () async {
        container = ProviderContainer(
          overrides: [
            currentProfileProvider.overrideWith((ref) async => testProfile),
          ],
        );

        final mockData = {
          'id': 'team-1',
          'company_id': 'company-456',
          'name': 'Team Alpha',
          'status': 'active',
          'created_at': '2026-06-30T12:00:00Z',
          'created_by': 'user-123',
          'disqualification_reason': null,
          'disqualified_at': null,
          'challenge_id': null,
        };

        final singleFilterBuilder = MockPostgrestFilterBuilder<List<Map<String, dynamic>>>();

        when(() => mockSupabase.from('teams')).thenAnswer((_) => mockQueryBuilder);
        when(() => mockQueryBuilder.select()).thenAnswer((_) => singleFilterBuilder);
        when(() => singleFilterBuilder.eq('id', 'team-1')).thenAnswer((_) => singleFilterBuilder);
        when(() => singleFilterBuilder.eq('company_id', 'company-456')).thenAnswer((_) => singleFilterBuilder);
        when(() => singleFilterBuilder.maybeSingle()).thenAnswer((_) => mockSingleTransformBuilder);
        mockSingleTransformBuilder.mockFuture = Future.value(mockData);

        final team = await container!.read(teamByIdProvider('team-1').future);
        expect(team, isNotNull);
        expect(team!.id, 'team-1');
        expect(team.name, 'Team Alpha');
      });

      test('returns null if team not found in company', () async {
        container = ProviderContainer(
          overrides: [
            currentProfileProvider.overrideWith((ref) async => testProfile),
          ],
        );

        final singleFilterBuilder = MockPostgrestFilterBuilder<List<Map<String, dynamic>>>();

        when(() => mockSupabase.from('teams')).thenAnswer((_) => mockQueryBuilder);
        when(() => mockQueryBuilder.select()).thenAnswer((_) => singleFilterBuilder);
        when(() => singleFilterBuilder.eq('id', 'non-existent')).thenAnswer((_) => singleFilterBuilder);
        when(() => singleFilterBuilder.eq('company_id', 'company-456')).thenAnswer((_) => singleFilterBuilder);
        when(() => singleFilterBuilder.maybeSingle()).thenAnswer((_) => mockSingleTransformBuilder);
        mockSingleTransformBuilder.mockFuture = Future.value(null);

        final team = await container!.read(teamByIdProvider('non-existent').future);
        expect(team, isNull);
      });
    });

    group('teamMembersProvider', () {
      test('fetches members for a team', () async {
        container = ProviderContainer();

        final mockData = [
          {
            'id': 'member-1',
            'team_id': 'team-1',
            'user_id': 'user-123',
            'company_id': 'company-456',
            'joined_at': '2026-06-30T12:00:00Z',
            'status': 'active',
            'challenge_id': null,
            'expelled_at': null,
            'expelled_reason': null,
          }
        ];

        when(() => mockSupabase.from('team_members')).thenAnswer((_) => mockQueryBuilder);
        when(() => mockQueryBuilder.select()).thenAnswer((_) => mockFilterBuilder);
        when(() => mockFilterBuilder.eq('team_id', 'team-1')).thenAnswer((_) => mockFilterBuilder);
        when(() => mockFilterBuilder.order('joined_at')).thenAnswer((_) => mockTransformBuilder);
        mockTransformBuilder.mockFuture = Future.value(mockData);

        final members = await container!.read(teamMembersProvider('team-1').future);
        expect(members, hasLength(1));
        expect(members.first.userId, 'user-123');
      });

      test('maps raw data to TeamMember objects', () async {
        container = ProviderContainer();

        final mockData = [
          {
            'id': 'member-1',
            'team_id': 'team-1',
            'user_id': 'user-123',
            'company_id': 'company-456',
            'joined_at': '2026-06-30T12:00:00Z',
            'status': 'active',
            'challenge_id': null,
            'expelled_at': null,
            'expelled_reason': null,
          },
          {
            'id': 'member-2',
            'team_id': 'team-1',
            'user_id': 'user-456',
            'company_id': 'company-456',
            'joined_at': '2026-06-30T13:00:00Z',
            'status': 'invited',
            'challenge_id': null,
            'expelled_at': null,
            'expelled_reason': null,
          }
        ];

        when(() => mockSupabase.from('team_members')).thenAnswer((_) => mockQueryBuilder);
        when(() => mockQueryBuilder.select()).thenAnswer((_) => mockFilterBuilder);
        when(() => mockFilterBuilder.eq('team_id', 'team-1')).thenAnswer((_) => mockFilterBuilder);
        when(() => mockFilterBuilder.order('joined_at')).thenAnswer((_) => mockTransformBuilder);
        mockTransformBuilder.mockFuture = Future.value(mockData);

        final members = await container!.read(teamMembersProvider('team-1').future);
        expect(members, hasLength(2));
        expect(members[0].userId, 'user-123');
        expect(members[0].status, 'active');
        expect(members[1].userId, 'user-456');
        expect(members[1].status, 'invited');
      });
    });

    group('createTeamProvider', () {
      test('calls create_team RPC with correct params', () async {
        container = ProviderContainer();

        final mockResponse = {
          'id': 'team-1',
          'company_id': 'company-456',
          'name': 'Team Alpha',
          'status': 'draft',
          'created_at': '2026-06-30T12:00:00Z',
          'created_by': 'user-123',
          'disqualification_reason': null,
          'disqualified_at': null,
          'challenge_id': null,
        };

        mockRpc('create_team', params: {'p_name': 'Team Alpha'}, response: mockResponse);

        final team = await container!.read(createTeamProvider('Team Alpha').future);
        expect(team, isNotNull);
        expect(team!.name, 'Team Alpha');
        verify(() => mockSupabase.rpc('create_team', params: {'p_name': 'Team Alpha'})).called(1);
      });

      test('returns Team object on success', () async {
        container = ProviderContainer();

        final mockResponse = {
          'id': 'team-1',
          'company_id': 'company-456',
          'name': 'Team Alpha',
          'status': 'draft',
          'created_at': '2026-06-30T12:00:00Z',
          'created_by': 'user-123',
          'disqualification_reason': null,
          'disqualified_at': null,
          'challenge_id': null,
        };

        mockRpc('create_team', response: mockResponse);

        final team = await container!.read(createTeamProvider('Team Alpha').future);
        expect(team, isA<Team>());
        expect(team!.id, 'team-1');
      });

      test('throws error if RPC fails', () async {
        container = ProviderContainer();

        when(() => mockSupabase.rpc('create_team', params: any(named: 'params')))
            .thenThrow(Exception('DB Error'));

        expect(
          () => container!.read(createTeamProvider('Team Alpha').future),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('inviteToTeamProvider', () {
      test('calls invite_to_team RPC with team and user ids', () async {
        container = ProviderContainer();

        mockRpc(
          'invite_to_team',
          params: {
            'p_team_id': 'team-1',
            'p_user_id': 'user-123',
          },
          response: null,
        );

        final result = await container!.read(inviteToTeamProvider(('team-1', 'user-123')).future);
        expect(result, isTrue);
        verify(() => mockSupabase.rpc('invite_to_team', params: {
          'p_team_id': 'team-1',
          'p_user_id': 'user-123',
        })).called(1);
      });

      test('returns true on success', () async {
        container = ProviderContainer();

        mockRpc('invite_to_team', response: null);

        final result = await container!.read(inviteToTeamProvider(('team-1', 'user-123')).future);
        expect(result, isTrue);
      });
    });

    group('requestJoinTeamProvider', () {
      test('calls request_join_team RPC with team id', () async {
        container = ProviderContainer();

        mockRpc('request_join_team', params: {'p_team_id': 'team-1'}, response: null);

        final result = await container!.read(requestJoinTeamProvider('team-1').future);
        expect(result, isTrue);
        verify(() => mockSupabase.rpc('request_join_team', params: {'p_team_id': 'team-1'})).called(1);
      });

      test('returns true on success', () async {
        container = ProviderContainer();

        mockRpc('request_join_team', response: null);

        final result = await container!.read(requestJoinTeamProvider('team-1').future);
        expect(result, isTrue);
      });
    });

    group('respondInvitationProvider', () {
      test('calls respond_invitation RPC with accept=true', () async {
        container = ProviderContainer();

        mockRpc(
          'respond_invitation',
          params: {
            'p_team_member_id': 'member-1',
            'p_accept': true,
          },
          response: null,
        );

        final result = await container!.read(respondInvitationProvider(('member-1', true)).future);
        expect(result, isTrue);
        verify(() => mockSupabase.rpc('respond_invitation', params: {
          'p_team_member_id': 'member-1',
          'p_accept': true,
        })).called(1);
      });

      test('calls respond_invitation RPC with accept=false', () async {
        container = ProviderContainer();

        mockRpc(
          'respond_invitation',
          params: {
            'p_team_member_id': 'member-1',
            'p_accept': false,
          },
          response: null,
        );

        final result = await container!.read(respondInvitationProvider(('member-1', false)).future);
        expect(result, isTrue);
        verify(() => mockSupabase.rpc('respond_invitation', params: {
          'p_team_member_id': 'member-1',
          'p_accept': false,
        })).called(1);
      });
    });

    group('respondJoinRequestProvider', () {
      test('calls respond_join_request RPC with accept=true', () async {
        container = ProviderContainer();

        mockRpc(
          'respond_join_request',
          params: {
            'p_team_member_id': 'member-1',
            'p_accept': true,
          },
          response: null,
        );

        final result = await container!.read(respondJoinRequestProvider(('member-1', true)).future);
        expect(result, isTrue);
        verify(() => mockSupabase.rpc('respond_join_request', params: {
          'p_team_member_id': 'member-1',
          'p_accept': true,
        })).called(1);
      });

      test('calls respond_join_request RPC with accept=false', () async {
        container = ProviderContainer();

        mockRpc(
          'respond_join_request',
          params: {
            'p_team_member_id': 'member-1',
            'p_accept': false,
          },
          response: null,
        );

        final result = await container!.read(respondJoinRequestProvider(('member-1', false)).future);
        expect(result, isTrue);
        verify(() => mockSupabase.rpc('respond_join_request', params: {
          'p_team_member_id': 'member-1',
          'p_accept': false,
        })).called(1);
      });
    });

    group('expelTeamMemberProvider', () {
      test('calls expel_team_member RPC with reason', () async {
        container = ProviderContainer();

        mockRpc(
          'expel_team_member',
          params: {
            'p_team_member_id': 'member-1',
            'p_reason': 'Inactive',
          },
          response: null,
        );

        final result = await container!.read(expelTeamMemberProvider(('member-1', 'Inactive')).future);
        expect(result, isTrue);
        verify(() => mockSupabase.rpc('expel_team_member', params: {
          'p_team_member_id': 'member-1',
          'p_reason': 'Inactive',
        })).called(1);
      });

      test('returns true on success', () async {
        container = ProviderContainer();

        mockRpc('expel_team_member', response: null);

        final result = await container!.read(expelTeamMemberProvider(('member-1', 'Inactive')).future);
        expect(result, isTrue);
      });
    });

    group('disqualifyTeamProvider', () {
      test('calls disqualify_team RPC with reason', () async {
        container = ProviderContainer();

        mockRpc(
          'disqualify_team',
          params: {
            'p_team_id': 'team-1',
            'p_reason': 'Cheating',
          },
          response: null,
        );

        final result = await container!.read(disqualifyTeamProvider(('team-1', 'Cheating')).future);
        expect(result, isTrue);
        verify(() => mockSupabase.rpc('disqualify_team', params: {
          'p_team_id': 'team-1',
          'p_reason': 'Cheating',
        })).called(1);
      });

      test('returns true on success', () async {
        container = ProviderContainer();

        mockRpc('disqualify_team', response: null);

        final result = await container!.read(disqualifyTeamProvider(('team-1', 'Cheating')).future);
        expect(result, isTrue);
      });
    });
  });
}
