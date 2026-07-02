# HealthyWalky

App corporativa de bienestar: las empresas organizan **desafíos de caminata** entre sus empleados, que forman **equipos**, registran sus **pasos diarios** (a mano o sincronizados desde Google Fit / Apple Health) y compiten en un **ranking en tiempo real**.

**Stack:** Flutter + Riverpod + Go Router → Supabase (Postgres + Auth + RLS + Realtime)

## Funcionalidades (MVP1 — `v0.1.0-mvp1`)

- **Onboarding multiempresa**: registro de empresa (el fundador queda como admin) o alta por **invitación** con token de un solo uso. Aislamiento multi-tenant por RLS.
- **Roles**: `admin` (gestiona usuarios, equipos y desafíos; puede expulsar miembros) y `member` (participa). Misma navegación de 5 pestañas para todos — Inicio, Pasos, Equipos, Desafíos, Ranking — con acciones según rol dentro de cada pantalla.
- **Equipos**: cualquier usuario crea un equipo; invitaciones y solicitudes de unión gestionadas por el creador; aprobación, descalificación y archivado por el admin. Ciclo de vida completo (borrador → aprobado → inscrito → en competición → completado).
- **Desafíos**: individuales o por equipos, con rango de fechas y opción de **contar o no los fines de semana**. Inscripción abierta solo en borrador; al activarse, el roster de cada equipo se congela (las invitaciones sin responder expiran). El admin puede activar, cancelar e inscribir equipos retroactivamente.
- **Pasos**: registro manual día a día y **sincronización automática con Google Fit (Android) y Apple Health (iOS)**, con resolución de conflictos cuando ambas fuentes difieren (el usuario elige la fuente canónica).
- **Ranking en tiempo real**: leaderboard de equipos ordenado por **media diaria de pasos por miembro** (total ÷ miembros ÷ días transcurridos elegibles), lo que equilibra equipos de distinto tamaño. Los snapshots se propagan al instante a todos los usuarios vía Supabase Realtime.

## Cómo levantar el proyecto

### Requisitos

- Flutter SDK (en Windows este proyecto asume `C:\flutter`; añade `C:\flutter\bin` al PATH)
- [Supabase CLI](https://supabase.com/docs/guides/cli) (solo para gestionar migraciones)
- Un fichero `.env` en la raíz con las credenciales del proyecto Supabase (solo la clave publicable/anon — nunca la service-role):

```
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_ANON_KEY=<publishable-key>
```

### Flutter

```bash
flutter pub get

# Desarrollo (web)
flutter run -d chrome --web-port 3000

# En un dispositivo concreto
flutter run -d <device-id>

# Builds
flutter build apk         # Android
flutter build web         # Web

# Tests y lint
flutter test
flutter analyze

# Code-gen de providers Riverpod (si añades anotaciones @riverpod)
dart run build_runner build --delete-conflicting-outputs
```

### Supabase (proyecto cloud, sin stack local)

```bash
supabase link --project-ref qpobvyuqbqimbdfmakwd   # una vez; pide la contraseña de la BD
supabase migration list              # estado local vs remoto
supabase db push                     # aplica migraciones pendientes al remoto
supabase migration new <nombre>      # nueva migración
```

Las migraciones (`supabase/migrations/`, 0001–0020) son la única fuente de verdad del esquema y de las funciones RPC. **Nunca edites una migración ya aplicada** — los fixes van siempre en un archivo nuevo. Los specs funcionales viven en `docs/specs/`.

## Limitaciones conocidas (Known Gaps)

- **Los desafíos vencidos no se cierran solos**: un desafío cuya `end_date` ya pasó sigue en estado `active` (no hay job programado; el `pg_cron` documentado en la migración 0013 no está habilitado). El ranking sigue siendo correcto porque el rango de fechas se acota con `LEAST(end_date, CURRENT_DATE)`, pero solo puede haber un desafío activo por empresa hasta completarlo o cancelarlo a mano.
- **Sin ranking individual**: la RPC `get_individual_leaderboard` existe en la base de datos pero la pestaña Ranking solo muestra leaderboards de equipos (para desafíos individuales se muestra un mensaje explicativo).
- **Samsung Health**: la columna `source` lo contempla, pero la sincronización solo está implementada para Google Fit y Apple Health.

## Estructura

```
lib/
├── core/          # cliente Supabase, tema, router (guard de auth)
└── features/      # auth, companies, shell, teams, challenges, steps
                   # cada feature: models/ → providers/ → screens/
supabase/migrations/   # esquema + RPCs (0001–0020)
docs/specs/            # specs SDD (teams, challenges, steps)
test/features/         # tests de providers
```

Para convenciones de desarrollo y decisiones de diseño detalladas, ver [CLAUDE.md](CLAUDE.md).
