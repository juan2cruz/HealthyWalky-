# Spec: Teams

## Contexto

Los equipos son la unidad competitiva central de HealthyWalky. Un equipo se crea dentro de una empresa, se inscribe en el único desafío activo, y compite por la mejor media de pasos por miembro. Esta spec cubre el ciclo de vida completo: creación, composición, inscripción en desafío, competición y archivo histórico.

---

## Regla fundamental de seguridad

Toda restricción de acceso y de timing (quién puede invitar, cuándo se puede uno unir) se **enfuerza a nivel de base de datos mediante RLS y RPCs `SECURITY DEFINER`**, siguiendo el patrón establecido en el proyecto. La UI oculta acciones no disponibles, pero la BD es la última línea de defensa. Ninguna restricción puede depender únicamente de validación en el cliente.

---

## Actores

| Actor | Capacidades sobre equipos |
|---|---|
| **Member** | Crear equipos, enviar invitaciones (solo el creador, pre-desafío), solicitar unirse a equipos, aceptar/rechazar invitaciones recibidas |
| **Admin** | Todo lo anterior + aprobar/rechazar equipos, modificar nombre y composición de cualquier equipo en cualquier momento, expulsar miembros, descalificar equipos |

---

## Estados del equipo

```
draft ──► approved ──► enrolled ──► active ──► completed
                                       │
                                       └──► disqualified
```

| Estado | Descripción |
|---|---|
| `draft` | Recién creado por un member. Pendiente de revisión del admin. |
| `approved` | Aprobado por el admin. Acepta invitaciones y solicitudes de miembros. |
| `enrolled` | Inscrito en el desafío activo. Sigue aceptando invitaciones/solicitudes hasta que el desafío arranque. |
| `active` | El desafío ha comenzado. Composición congelada. No se admiten cambios de miembros voluntarios. |
| `completed` | El desafío ha terminado. El equipo pasa al histórico. Los members quedan libres para el próximo desafío. |
| `disqualified` | Descalificado por el admin durante la competición. Visible en el leaderboard con motivo. |

---

## Estados de membresía (`team_members.status`)

| Estado | Descripción |
|---|---|
| `invited` | El creador ha enviado una invitación. Pendiente de respuesta del member destinatario. |
| `request_pending` | El member ha solicitado unirse. Pendiente de respuesta del creador del equipo. |
| `active` | Miembro activo del equipo. |
| `rejected` | Invitación o solicitud rechazada. |
| `expelled` | Expulsado por el admin durante la competición. |

---

## Comportamientos por actor

### Cualquier member

**Crear un equipo**
- Puede crear un equipo mientras no haya un desafío en estado `active`. Un desafío en curso cierra la ventana de creación de nuevos equipos.
- Al crear, el equipo queda en estado `draft`.
- El creador queda registrado en `teams.created_by`. Es el único con capacidad de gestión del equipo en fase pre-desafío (invitar, aceptar solicitudes de unión).
- Una vez arrancado el desafío, el creador no tiene privilegios adicionales respecto al resto de miembros.

**Invitar a un member (solo el creador, solo pre-desafío)**
- El creador puede invitar a cualquier member de la misma empresa que no tenga ya `status = 'active'` en otro equipo inscrito en el mismo desafío.
- Crea una fila en `team_members` con `status = 'invited'`.
- El RPC valida que el desafío no esté en `active` antes de insertar. Si lo está, devuelve error.

**Solicitar unirse a un equipo (cualquier member, solo pre-desafío)**
- Cualquier member puede ver los equipos en estado `approved` o `enrolled` y solicitar unirse.
- Crea una fila en `team_members` con `status = 'request_pending'`.
- El RPC valida que el desafío no esté en `active`. Si lo está, devuelve error.
- Un member no puede solicitar unirse si ya tiene `status = 'active'` en otro equipo para el mismo desafío.

**Aceptar o rechazar una invitación recibida**
- El member destinatario acepta (`status → active`) o rechaza (`status → rejected`).
- El RPC valida que el desafío no esté en `active`. Si lo está, devuelve error.

**Aceptar o rechazar una solicitud de unión entrante**
- El creador del equipo acepta (`status → active`) o rechaza (`status → rejected`) las solicitudes entrantes.
- **Decisión explícitamente validada:** es el creador —y solo el creador— quien gestiona las solicitudes de unión, no el admin ni otros miembros del equipo. Esto es deliberado: mantiene una responsabilidad clara de moderación del equipo en fase de formación.
- El RPC verifica que `auth.uid() = teams.created_by` antes de ejecutar. Si no coincide, devuelve error de permisos.
- El RPC valida que el desafío no esté en `active`. Si lo está, devuelve error.

---

### Admin

**Aprobar o rechazar un equipo**
- Puede transicionar un equipo de `draft` a `approved`, o eliminarlo.

**Modificar un equipo (en cualquier momento)**
- Puede cambiar el nombre de cualquier equipo.
- Puede añadir o eliminar miembros, sujeto a la restricción sobre el creador descrita a continuación.

**Restricción sobre el creador en fase pre-desafío**
- El admin **no puede expulsar al creador** de un equipo mientras el equipo esté en estado `draft`, `approved` o `enrolled`.
- Esta restricción evita que el equipo quede sin responsable de gestión en la fase de formación.
- El RPC `expel_team_member` debe comprobar si el usuario objetivo es `teams.created_by` y si el equipo no está en `active`; en ese caso devuelve error.
- **Una vez el desafío pasa a `active`, esta restricción deja de aplicar.** El admin puede expulsar al creador con las mismas reglas que a cualquier otro miembro.

**Expulsar a un miembro durante la competición**
- Cambia `team_members.status` a `expelled` y registra `expelled_at` y `expelled_reason`.
- **El recálculo de pasos es únicamente hacia adelante:** los `leaderboard_snapshots` generados para días anteriores a `expelled_at` son inmutables y no se modifican. Desde el día de la expulsión en adelante, el leaderboard calcula la media solo sobre los miembros con `status = 'active'`.
- El member expulsado **no puede** unirse a otro equipo en el mismo desafío (la ventana de inscripción ya está cerrada desde que el desafío pasó a `active`).

**Descalificar un equipo**
- Cambia el estado del equipo a `disqualified`.
- Requiere un motivo (`disqualification_reason text NOT NULL`).
- El equipo permanece visible en el leaderboard marcado como `disqualified`, con el motivo visible para todos los members de la empresa.
- Los pasos de sus miembros no se borran, pero el equipo no computa en el ranking.

---

## Restricciones de timing — enforzadas en BD

Implementadas como guards en los RPCs (`SECURITY DEFINER`). La UI las respeta ocultando acciones, pero el RPC es la garantía.

| Operación | Permitida cuando | Bloqueada cuando |
|---|---|---|
| Crear equipo | Desafío no en `active` | Desafío en `active` o `completed` |
| Invitar member | Desafío no en `active` | Desafío en `active` |
| Solicitar unirse | Desafío no en `active` | Desafío en `active` |
| Aceptar/rechazar invitación | Desafío no en `active` | Desafío en `active` |
| Aceptar/rechazar solicitud de unión | Desafío no en `active` | Desafío en `active` |
| Admin expulsar al creador | Solo si equipo en `active` | Equipo en `draft`, `approved` o `enrolled` |
| Admin expulsar a cualquier otro member | Desafío en `active` | Desafío en `completed` |
| Admin: modificar nombre | Siempre | — |
| Admin: descalificar equipo | Desafío en `active` | Desafío en `completed` |

---

## Regla de membresía única por desafío

Un usuario no puede tener `status = 'active'` en más de un equipo inscrito en el mismo desafío. Se implementa con un índice único parcial:

```sql
CREATE UNIQUE INDEX team_members_one_active_per_challenge
  ON team_members (user_id, challenge_id)
  WHERE status = 'active';
```

*(Requiere añadir `challenge_id` a `team_members`.)*

---

## Cálculo de la media del equipo y snapshots históricos

- La métrica del ranking es `AVG(step_count)` calculada **solo sobre miembros con `status = 'active'`** en `team_members` en el momento del cálculo.
- La tabla `leaderboard_snapshots` persiste snapshots diarios del ranking. Cada fila es el estado del leaderboard en un instante concreto y es **inmutable una vez escrita**.
- Los snapshots son la fuente de verdad para consultas históricas: "¿cómo quedó el ranking el día X del desafío Y?"
- Tras la expulsión de un miembro, los snapshots anteriores a `expelled_at` no se tocan. Los snapshots generados desde ese día usan el conjunto reducido de miembros activos.

---

## Visibilidad

- Equipos, miembros y estado son visibles únicamente para los members de la misma empresa (enforced por RLS con `public.my_company_id()`).
- Los equipos `disqualified` son visibles con su motivo. No se ocultan del leaderboard.
- No hay ranking inter-empresa en esta fase.

---

## Cambios de esquema necesarios

### `teams` — columnas a añadir
```sql
status                  text NOT NULL DEFAULT 'draft'
                          CHECK (status IN ('draft','approved','enrolled','active','completed','disqualified')),
disqualification_reason text,          -- NOT NULL cuando status = 'disqualified'
disqualified_at         timestamptz,
challenge_id            uuid REFERENCES challenges(id)  -- se rellena al inscribir el equipo
```

### `team_members` — columnas a añadir o modificar
```sql
status          text NOT NULL DEFAULT 'invited'
                  CHECK (status IN ('invited','request_pending','active','rejected','expelled')),
expelled_at     timestamptz,
expelled_reason text,
challenge_id    uuid REFERENCES challenges(id)  -- para el índice de unicidad por desafío
```

Índice único parcial:
```sql
CREATE UNIQUE INDEX team_members_one_active_per_challenge
  ON team_members (user_id, challenge_id)
  WHERE status = 'active';
```

### RPCs a crear (todos `SECURITY DEFINER`)

| RPC | Actor | Descripción |
|---|---|---|
| `create_team(p_name)` | Member | Crea equipo en `draft`, registra `created_by` |
| `approve_team(p_team_id)` | Admin | `draft → approved` |
| `enroll_team(p_team_id)` | Member/Admin | `approved → enrolled`, vincula `challenge_id` |
| `invite_to_team(p_team_id, p_user_id)` | Creador | Inserta `status='invited'`, valida timing |
| `request_join_team(p_team_id)` | Member | Inserta `status='request_pending'`, valida timing |
| `respond_invitation(p_team_member_id, p_accept bool)` | Member destinatario | Acepta/rechaza, valida timing |
| `respond_join_request(p_team_member_id, p_accept bool)` | Creador del equipo | Acepta/rechaza, verifica `created_by`, valida timing |
| `expel_team_member(p_team_member_id, p_reason text)` | Admin | `active → expelled`, bloquea si objetivo es creador y equipo no está en `active` |
| `disqualify_team(p_team_id, p_reason text)` | Admin | `enrolled/active → disqualified`, registra motivo |
| `leave_team(p_team_id)` | Member (no creador) | Salida voluntaria pre-desafío: borra su fila `team_members` (0022). Bloqueado con desafío `active` |
| `remove_team_member(p_team_member_id)` | Creador | Retira a un miembro (`active/invited/request_pending`) pre-desafío: borra la fila (0022). Bloqueado con desafío `active` |

### Reglas de reciclaje y anti-atasco (0021–0022)

- **Reinvitación:** una fila `rejected` o `expelled` no veta al usuario: `invite_to_team` y `request_join_team` reciclan esa fila (`→ invited` / `→ request_pending`, limpiando `expelled_*` y `challenge_id`) en vez de fallar por la UNIQUE `(team_id, user_id)`. Filas `invited`/`request_pending`/`active` siguen dando error explícito.
- **Una militancia a la vez:** `respond_invitation` y `respond_join_request` rechazan la aceptación si el usuario ya es `active` en otro equipo no `archived`/`completed` (antes el índice único solo protegía con `challenge_id` no nulo, y la doble militancia pre-inscripción bloqueaba `enroll_team` para siempre).
- **Fin de desafío:** al completarse un desafío (manual `complete_challenge` o cron `complete_overdue_challenges`, 0023) los equipos `enrolled/active/disqualified` vuelven a `approved` con `challenge_id = NULL`; `team_members.challenge_id` se conserva como histórico del desafío terminado.

---

## Fuera de alcance (esta fase)

- Límites de tamaño de equipo (mínimo/máximo de miembros).
- Notificaciones push o email para invitaciones y solicitudes.
- Transferencia del rol de creador a otro miembro.
- Rankings inter-empresa.

> Nota: la salida voluntaria (`leave_team`) y la retirada de miembros por el creador (`remove_team_member`) se añadieron en la migración 0022 y ya no están fuera de alcance.
