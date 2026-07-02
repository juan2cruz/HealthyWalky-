# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run the app (web target during development)
flutter run -d chrome --web-port 3000

# Run on a specific device
flutter run -d <device-id>

# Build
flutter build apk         # Android
flutter build web         # Web

# Tests
flutter test                        # all tests
flutter test test/path/to_test.dart # single file

# Code generation (Riverpod providers via annotations)
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch          # watch mode during development

# Supabase (cloud project)
supabase link --project-ref qpobvyuqbqimbdfmakwd   # one-time, requires DB password
supabase db push                     # apply pending migrations to remote DB (no Docker needed)
supabase migration list              # check local vs remote migration sync (no Docker needed)
supabase migration new <name>        # scaffold a new migration file
supabase db dump --data-only -s public -x public.profiles -f out.sql
                                     # inspect remote data; REQUIRES Docker Desktop running;
                                     # always exclude profiles (personal data)

# Lint
flutter analyze
```

**Windows PATH note:** Flutter is installed at `C:\flutter`. If `flutter` is not found in a new terminal, add `C:\flutter\bin` to your user PATH or prefix commands with `C:\flutter\bin\flutter.bat`.

## Architecture

**Stack:** Flutter + Riverpod + Go Router → Supabase (Postgres + Auth + RLS)

**`lib/` layout — feature-based, MVVM-ish:**

```
lib/
├── main.dart               # App entry: loads .env, inits Supabase, runs app
├── core/
│   ├── supabase/client.dart    # Singleton SupabaseClient accessor
│   ├── theme/app_theme.dart    # Material 3 theme
│   └── router/app_router.dart  # Go Router config (all routes + auth guard)
└── features/
    ├── auth/               # Login, register company, invite join
    ├── companies/          # Dashboard + user/invite management
    ├── shell/              # Bottom nav shell wrapping nested routes
    ├── teams/              # Team CRUD, join requests/invites, member management
    ├── challenges/         # Challenge CRUD, enrollment (individual/team), activate/cancel
    └── steps/              # Manual + Google Fit/Apple Health sync, leaderboard (realtime)
```

Each feature follows: `models/` → `providers/` → `screens/`.

**Other directories:** `docs/specs/` holds the SDD specs (`teams.md`, `challenges.md`, `steps.md`) — keep them in sync with migrations when formulas or flows change. `test/features/` has provider tests (currently teams only). `referencias/` holds QA screenshots and notes from manual testing sessions (not code).

**State management:** `flutter_riverpod` with plain `Provider`/`FutureProvider`/`StreamProvider`. The `riverpod_annotation` + `build_runner` packages are installed for future code-gen providers — run `build_runner` after adding `@riverpod` annotations.

**Routing:** Go Router with a top-level `redirect` guard in `app_router.dart`. The router does **not** use `refreshListenable` — auth-driven navigation is handled explicitly with `context.go()` in each screen. This avoids race conditions on Flutter Web where Supabase auth events fire before the browser URL is fully resolved.

**Environment:** Credentials loaded from `.env` via `flutter_dotenv`. The `.env` file is declared as a Flutter asset in `pubspec.yaml`. Only the Supabase publishable (anon) key is used client-side.

## Database (Supabase / Postgres)

Migrations live in `supabase/migrations/` (currently 0001–0020) and run in order. **Never edit a migration that may already be applied** — the remote tracks checksums in `supabase_migrations.schema_migrations`, so fixes always go in a new file (0016–0020 are all `CREATE OR REPLACE` fixes layered over earlier definitions; the last one wins). Key design decisions:

- **Multi-tenancy via RLS:** Every table has `company_id` and Row-Level Security enabled. All policies call the `my_company_id()` helper (defined in `0009_fix_rls_recursion.sql`) — a `SECURITY DEFINER` function that reads the caller's `company_id` from `profiles` without triggering recursive RLS on that same table. **Do not write RLS policies on `profiles` that query `profiles` directly — it causes infinite recursion.**
- **JWT claim injection:** A Postgres trigger (`set_claim_company_id`) on `profiles` writes `company_id` into `auth.users.raw_app_meta_data` after profile creation. The `my_company_id()` function is the canonical way to get it in RLS — the JWT claim is a secondary optimization.
- **All writes go through RPCs** (`SECURITY DEFINER` functions defined in migrations, callable via `supabase.rpc()`), grouped by area:
  - *Onboarding:* `register_company(name, slug, display_name)` (atomic company + admin profile), `accept_invite(token, display_name)`, `create_invite()` (one-time token in `company_invites`; the invite URL carries it as a query param read by `InviteScreen`; after `accept_invite` the token is marked used)
  - *Teams:* `create_team` (auto-enrolls the creator as an active member — fixed in 0017), `enroll_team`, `invite_to_team`, `request_join_team`, `respond_invitation`, `respond_join_request`, `expel_team_member`
  - *Challenges:* `create_challenge` (includes `count_weekends` flag), `activate_challenge`, `enroll_individual`, `admin_enroll_team` (retroactive enrollment into an active challenge)
  - *Admin destructive (0014):* `abort_team` (archive + free members), `kick_user` (deletes profile; FK cascades remove steps/memberships/enrollments), `cancel_challenge` (resets enrolled teams to `approved`)
  - *Steps:* `upsert_steps(step_date, step_count, source)`, `resolve_step_conflict(step_date, winning_source)`, `get_my_steps_in_challenge(challenge_id)`
  - *Leaderboard:* `get_team_leaderboard(challenge_id)` and `refresh_leaderboard(challenge_id)` — the latter regenerates `leaderboard_snapshots` rows; called on leaderboard screen open and manual refresh (a `pg_cron` job is documented in `0013` but not enabled). Clients subscribe to `leaderboard_snapshots` via Supabase Realtime, so once a snapshot is written all viewers update instantly — rankings are not recalculated on every `upsert_steps`, only on refresh. `get_individual_leaderboard` exists in the DB but is unused by the app.
- **Leaderboard metric (0018):** `avg_steps = SUM(canonical steps) / (member_count × elapsed qualifying days)` — a daily average per member since the challenge start, so team size and challenge duration don't skew rankings. "Qualifying days" respects `count_weekends`; days with no logged steps count as zero (anti-gaming). Both `get_team_leaderboard` and `refresh_leaderboard` duplicate this formula — change both together.
- **Team lifecycle:** `teams.status`: draft → approved → enrolled → active → completed, plus disqualified/archived. `team_members.status`: invited / request_pending → active / rejected / expelled. `team_members.challenge_id` scopes each membership to one challenge (prevents double-counting steps across challenges — 0017). **Roster freeze (0020):** `activate_challenge` and `admin_enroll_team` expire (reject) unanswered invites/join requests, because `respond_invitation`/`respond_join_request` are blocked while a challenge is active — pending rows would otherwise be permanently unanswerable and invisible to the leaderboard.

## Key Conventions

- **Roles:** `admin` vs `member` stored in `profiles.role`. The bottom nav (`MainShell`) shows the same 5 tabs for everyone (Inicio, Pasos, Equipos, Desafíos, Ranking) — role branching happens *inside* screens (e.g. `DashboardScreen` shows admin quick-actions, `/users` management is linked only for admins). RLS + RPC role checks restrict write operations to admins.
- **Step data:** `daily_steps` is denormalized with `company_id` for RLS performance. The `source` column (`manual` / `google_fit` / `apple_health` / `samsung_health`) and `is_canonical` flag support health-platform sync, which is fully implemented in `StepsScreen` (via the `health` package on Android/iOS — auto-sync on load, manual "Sincronizar ahora", pull-to-refresh). When manual and synced entries disagree for the same day, the UI shows a conflict banner letting the user pick the canonical source. Leaderboard queries always filter `WHERE is_canonical = true`.
- **No service-role key in client:** All Supabase calls go through the publishable key; authorization is enforced entirely by RLS + RPCs.
- **Lint rule:** The project uses `flutter_lints`. Avoid leading underscores on local variables (use `ctx`/`st` not `_ctx`/`_st` in go_router builders); avoid double underscores (`__`).

## Known Gaps

- Challenges past their `end_date` stay `status = 'active'` — nothing runs a scheduled completion (the `pg_cron` refresh job in `0013` is documented but not enabled on the remote). The leaderboard clamps its date range with `LEAST(end_date, CURRENT_DATE)`, so results stay correct, but only one challenge can be active per company until it is manually completed/cancelled.
- No individual-ranking screen: `get_individual_leaderboard` exists in the DB but the Ranking tab only renders team leaderboards (shows an explanatory message for individual challenges).
