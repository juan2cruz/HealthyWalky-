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

# Supabase (cloud project — no local Docker required)
supabase link --project-ref qpobvyuqbqimbdfmakwd   # one-time, requires DB password
supabase db push                     # apply pending migrations to remote DB
supabase migration list              # check local vs remote migration sync
supabase migration new <name>        # scaffold a new migration file

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
    ├── teams/              # (Paso 4 — not yet implemented)
    ├── challenges/         # (Paso 5 — not yet implemented)
    └── steps/              # (Paso 6 — not yet implemented)
```

Each feature follows: `models/` → `providers/` → `screens/`.

**State management:** `flutter_riverpod` with plain `Provider`/`FutureProvider`/`StreamProvider`. The `riverpod_annotation` + `build_runner` packages are installed for future code-gen providers — run `build_runner` after adding `@riverpod` annotations.

**Routing:** Go Router with a top-level `redirect` guard in `app_router.dart`. The router does **not** use `refreshListenable` — auth-driven navigation is handled explicitly with `context.go()` in each screen. This avoids race conditions on Flutter Web where Supabase auth events fire before the browser URL is fully resolved.

**Environment:** Credentials loaded from `.env` via `flutter_dotenv`. The `.env` file is declared as a Flutter asset in `pubspec.yaml`. Only the Supabase publishable (anon) key is used client-side.

## Database (Supabase / Postgres)

Migrations live in `supabase/migrations/` and run in order. Key design decisions:

- **Multi-tenancy via RLS:** Every table has `company_id` and Row-Level Security enabled. All policies call the `my_company_id()` helper (defined in `0009_fix_rls_recursion.sql`) — a `SECURITY DEFINER` function that reads the caller's `company_id` from `profiles` without triggering recursive RLS on that same table. **Do not write RLS policies on `profiles` that query `profiles` directly — it causes infinite recursion.**
- **JWT claim injection:** A Postgres trigger (`set_claim_company_id`) on `profiles` writes `company_id` into `auth.users.raw_app_meta_data` after profile creation. The `my_company_id()` function is the canonical way to get it in RLS — the JWT claim is a secondary optimization.
- **RPCs (all defined in migrations, callable via `supabase.rpc()`):**
  - `register_company(name, slug, display_name)` — atomically creates a company + admin profile on first signup
  - `accept_invite(token, display_name)` — links a new user to an existing company via an invite token
  - `create_invite()` — admin generates a one-time invite token (stored in `company_invites`)
  - `upsert_steps(step_date, step_count)` — inserts or updates a user's manual daily step entry
  - `get_individual_leaderboard(challenge_id)` / `get_team_leaderboard(challenge_id)` — pre-computed ranking queries
- **Invite flow:** `company_invites` table (migration 0008) holds tokens. After `accept_invite` the token is marked used. The invite URL carries the token as a query param; the app reads it in `InviteScreen` and calls the RPC after sign-up.

## Key Conventions

- **Roles:** `admin` vs `member` stored in `profiles.role`. UI branches on this (`DashboardScreen`, `MainShell` nav items). RLS restricts write operations to admins.
- **Step data:** `daily_steps` is denormalized with `company_id` for RLS performance. The `source` column (`manual` / `google_fit` / `apple_health` / `samsung_health`) and `is_canonical` flag support future health-platform sync (Phase 2). Leaderboard queries always filter `WHERE is_canonical = true`.
- **No service-role key in client:** All Supabase calls go through the publishable key; authorization is enforced entirely by RLS + RPCs.
- **Lint rule:** The project uses `flutter_lints`. Avoid leading underscores on local variables (use `ctx`/`st` not `_ctx`/`_st` in go_router builders); avoid double underscores (`__`).
