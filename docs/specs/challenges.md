# Spec: Challenges

## Contexto

Un desafío es la competición dentro de la empresa. Define el período de tiempo, el tipo de participación (individual o por equipos) y el marco en el que se registran y comparan los pasos. Esta spec cubre el ciclo de vida completo del desafío: creación, inscripción de participantes, activación y cierre.

---

## Regla fundamental de seguridad

Toda restricción de acceso y timing se **enfuerza a nivel de base de datos mediante RLS y RPCs `SECURITY DEFINER`**, siguiendo el patrón establecido en el proyecto. La UI oculta acciones no disponibles, pero la BD es la última línea de defensa.

---

## Actores

| Actor | Capacidades sobre desafíos |
|---|---|
| **Admin** | Crear, editar (mientras `draft`), activar (`draft → active`), ver todos |
| **Member** | Ver todos los desafíos, inscribirse en desafíos `draft` de tipo `individual` |
| **Creador de equipo** | Inscribir su equipo en desafíos `draft` de tipo `team` |

---

## Estados del desafío

```
draft ──► active ──► completed
```

| Estado | Descripción |
|---|---|
| `draft` | Creado por el admin. Acepta inscripciones. Visible para todos. |
| `active` | Activado manualmente por el admin. Competición en curso. Sin nuevas inscripciones. Solo puede haber uno `active` a la vez. |
| `completed` | Cerrado automáticamente al llegar `end_date`. Resultado final e histórico. |

---

## Campos del desafío

| Campo | Tipo | Descripción |
|---|---|---|
| `title` | text | Nombre del desafío |
| `description` | text | Descripción opcional |
| `start_date` | date | Fecha de inicio (informativa; la activación es manual) |
| `end_date` | date | Fecha de cierre; al llegar, el desafío pasa a `completed` automáticamente |
| `enrollment_type` | text | `'individual'` o `'team'` — exclusivamente uno de los dos |
| `status` | text | `'draft'` / `'active'` / `'completed'` |
| `created_by` | uuid | Admin que lo creó |

No hay campos adicionales en esta fase (sin meta de pasos, sin premio).

---

## Comportamientos por actor

### Admin

**Crear un desafío**
- Solo admins pueden crear desafíos.
- Al crear, el desafío queda en `draft`.
- Pueden existir varios desafíos en `draft` simultáneamente.
- El RPC valida `end_date > start_date`.

**Editar un desafío**
- Solo mientras está en `draft`. Un desafío `active` o `completed` no puede modificarse.

**Activar un desafío (`draft → active`)**
- El admin decide manualmente cuándo arrancar la competición.
- El RPC valida que no exista ya otro desafío en `active` para la misma empresa antes de transicionar.
- Una vez `active`, la inscripción queda cerrada.

**Cierre automático (`active → completed`)**
- El sistema cierra automáticamente el desafío al llegar `end_date`.
- Se implementa mediante un job de pg_cron que evalúa diariamente los desafíos `active` cuya `end_date <= CURRENT_DATE` y los transiciona a `completed`.
- El admin no necesita hacer nada para cerrar el desafío.

---

### Member (desafío `individual`)

**Inscribirse**
- Cualquier member puede inscribirse en un desafío `draft` de tipo `individual`.
- La inscripción crea una fila en `challenge_enrollments` con `user_id`.
- El RPC bloquea la inscripción si el desafío no está en `draft`.
- No se puede inscribir dos veces en el mismo desafío (índice único en BD).

---

### Creador de equipo (desafío `team`)

**Inscribir al equipo**
- Solo el creador del equipo puede inscribir ese equipo en un desafío `draft` de tipo `team`.
- La inscripción crea una fila en `challenge_enrollments` con `team_id` y actualiza `teams.challenge_id` y `team_members.challenge_id` para todos los miembros activos (comportamiento definido en el RPC `enroll_team` de la spec de teams).
- El RPC bloquea la inscripción si el desafío no está en `draft`.
- Un equipo no puede inscribirse dos veces en el mismo desafío.

---

## Restricciones de timing — enforzadas en BD

| Operación | Permitida cuando | Bloqueada cuando |
|---|---|---|
| Crear desafío | Siempre (admin) | — |
| Editar desafío | Desafío en `draft` | Desafío en `active` o `completed` |
| Activar desafío | Desafío en `draft` y no hay otro `active` | Ya existe un desafío `active` |
| Inscripción individual | Desafío en `draft` | Desafío en `active` o `completed` |
| Inscripción de equipo | Desafío en `draft` | Desafío en `active` o `completed` |
| Desinscripción | Nunca | Siempre — no existe esta operación |

---

## Visibilidad

- Todos los desafíos (cualquier estado) son visibles para todos los members de la empresa.
- RLS con `public.my_company_id()` asegura aislamiento entre empresas.

---

## Pantalla de detalle de desafío activo

Muestra únicamente información básica del desafío: título, descripción, fechas, tipo y estado. El leaderboard y el progreso de pasos pertenecen a la feature de steps/leaderboard y no se implementan aquí.

---

## Cambios de esquema necesarios

El esquema de `challenges` y `challenge_enrollments` ya existe (migración 0004) y cubre los campos requeridos. No se necesitan columnas nuevas en esta fase.

La migración 0009 ya reescribió las RLS policies de `challenges` y `challenge_enrollments` con `my_company_id()`.

### RPCs a crear (todos `SECURITY DEFINER`)

| RPC | Actor | Descripción |
|---|---|---|
| `create_challenge(p_title, p_description, p_start_date, p_end_date, p_enrollment_type)` | Admin | Inserta desafío en `draft` |
| `activate_challenge(p_challenge_id)` | Admin | `draft → active`; valida que no haya otro `active` |
| `enroll_individual(p_challenge_id)` | Member | Inscribe al usuario en un desafío `individual` en `draft` |
| `complete_overdue_challenges()` | pg_cron | `active → completed` para desafíos cuya `end_date <= CURRENT_DATE` |

*Nota: `enroll_team` ya está definido en la spec y migración de teams (`enroll_team(p_team_id)`). Al ejecutarse, ese RPC ya identifica el desafío disponible e inscribe al equipo. No se duplica aquí.*

---

## Fuera de alcance (esta fase)

- Edición de desafío desde la UI (el admin puede hacerlo directamente en Supabase Studio si es necesario).
- Meta de pasos o premio asociado al desafío.
- Cierre manual anticipado por el admin.
- Notificaciones de inicio/fin de desafío.
- Desafíos inter-empresa.
