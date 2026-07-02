# Spec: Steps & Leaderboard (Paso 6)

## Objetivo

Permitir que los usuarios registren sus pasos diarios (automáticamente vía Google Fit / Apple Health o manualmente) y visualicen el leaderboard de equipos del desafío activo.

---

## 1. Cambios en el modelo de datos

### 1.1 Tabla `challenges` — campo nuevo

```sql
ALTER TABLE challenges ADD COLUMN count_weekends boolean NOT NULL DEFAULT true;
```

- `true` (default): los fines de semana cuentan para el leaderboard.
- `false`: solo se suman los pasos de días laborables (lunes–viernes).
- Se configura al crear el desafío. No se puede cambiar una vez activo.

### 1.2 Tabla `daily_steps` — sin cambios

Ya existe con los campos necesarios:

| Campo | Propósito |
|---|---|
| `user_id` | Usuario |
| `company_id` | RLS multi-tenant |
| `step_date` | Fecha (date) |
| `step_count` | Pasos del día |
| `source` | `'manual'` \| `'google_fit'` \| `'apple_health'` |
| `is_canonical` | `true` = este registro es el autorizado para leaderboard |
| `sync_status` | `'synced'` \| `'conflict'` |
| `external_record_id` | Clave de deduplicación de la plataforma fuente |

### 1.3 Tabla `step_sync_sources` — sin cambios

Ya existe para registrar qué plataforma tiene el usuario conectada.

---

## 2. RPCs (Supabase functions)

### `upsert_steps(p_step_date date, p_step_count int, p_source text)`

Inserta o actualiza un registro de pasos. Lógica:

1. Si no existe registro para `(user_id, step_date, source)` → insertar con `is_canonical = true`, `sync_status = 'synced'`.
2. Si ya existe registro del mismo `source` → actualizar `step_count`.
3. Si existe registro de **distinto** `source` con `is_canonical = true` → insertar el nuevo con `is_canonical = false`, `sync_status = 'conflict'`. El cliente detectará el conflicto y preguntará al usuario.

### `resolve_step_conflict(p_step_date date, p_winning_source text)`

El usuario elige qué fuente prevalece para un día con conflicto:

1. Marca `is_canonical = true` en el registro de `p_winning_source`.
2. Marca `is_canonical = false` en todos los otros registros del mismo `(user_id, step_date)`.
3. Actualiza `sync_status = 'synced'` en ambos.

### `get_team_leaderboard(p_challenge_id uuid)`

Devuelve el ranking de equipos para el desafío activo:

```sql
-- v_days_elapsed = días elegibles (respeta count_weekends) entre start_date
-- y LEAST(end_date, CURRENT_DATE), con mínimo 1 para evitar división por cero.
SELECT
  RANK() OVER (ORDER BY
    COALESCE(SUM(ds.step_count)::numeric / NULLIF(COUNT(DISTINCT tm.user_id) * v_days_elapsed, 0), 0) DESC
  )                                                                   AS ranking,
  t.id                                                                AS team_id,
  t.name                                                              AS team_name,
  COUNT(DISTINCT tm.user_id)                                          AS member_count,
  COALESCE(
    ROUND(SUM(ds.step_count)::numeric / NULLIF(COUNT(DISTINCT tm.user_id) * v_days_elapsed, 0)),
    0
  )                                                                   AS avg_steps
FROM teams t
JOIN challenge_enrollments ce
  ON ce.team_id = t.id AND ce.challenge_id = p_challenge_id AND ce.status = 'active'
LEFT JOIN team_members tm
  ON tm.team_id = t.id AND tm.challenge_id = p_challenge_id AND tm.status = 'active'
LEFT JOIN daily_steps ds
  ON ds.user_id = tm.user_id AND ds.is_canonical = true
 AND ds.step_date BETWEEN v_start AND v_end
 AND (v_count_weekends = true OR EXTRACT(DOW FROM ds.step_date) NOT IN (0, 6))
GROUP BY t.id, t.name
ORDER BY avg_steps DESC;
```

- **Métrica**: media de pasos **por día transcurrido por miembro** desde el inicio del desafío hasta hoy — no un promedio solo sobre los días con registro. Los días sin pasos cuentan como 0, para que un equipo no pueda inflar la media registrando solo algunos días.
- El divisor `member_count` ya equilibra la desigualdad de tamaño entre equipos.
- Solo equipos con `challenge_enrollments.status = 'active'` para ese desafío (`LEFT JOIN` en `team_members`, no `JOIN`, para que un equipo con 0 miembros activos siga apareciendo).
- Solo miembros con `team_members.status = 'active'` y `team_members.challenge_id = p_challenge_id` (evita doble conteo si un usuario se reinscribe en más de un desafío).
- Filtra `count_weekends` dinámicamente, tanto en la suma de pasos como en `v_days_elapsed`.

### `get_my_steps_in_challenge(p_challenge_id uuid)`

Devuelve los pasos canónicos del usuario actual para cada día del desafío:

```sql
SELECT step_date, step_count, source, sync_status
FROM daily_steps
WHERE user_id = auth.uid()
  AND is_canonical = true
  AND step_date BETWEEN (SELECT start_date FROM challenges WHERE id = p_challenge_id)
                    AND LEAST(CURRENT_DATE, (SELECT end_date FROM challenges WHERE id = p_challenge_id))
ORDER BY step_date DESC;
```

### `get_my_conflicts()`

Devuelve los días donde el usuario tiene `sync_status = 'conflict'`, para que la app pueda mostrar el diálogo de resolución:

```sql
SELECT DISTINCT step_date FROM daily_steps
WHERE user_id = auth.uid() AND sync_status = 'conflict'
ORDER BY step_date DESC;
```

---

## 3. Integración con plataformas de salud

### Paquete

`health: ^11.x` (pub.dev) — API unificada sobre Google Health Connect (Android) y Apple HealthKit (iOS).

### Permisos requeridos

**Android** (`AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.health.READ_STEPS"/>
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION"/>
```

**iOS** (`Info.plist`):
```xml
<key>NSHealthShareUsageDescription</key>
<string>HealthyWalky usa tus pasos para el leaderboard corporativo.</string>
```

### Flujo de autorización

1. La primera vez que el usuario entra a la pantalla de pasos en móvil, se le muestra un banner explicando la integración.
2. Si acepta → `HealthFactory.requestAuthorization([HealthDataType.STEPS])` → se guarda `step_sync_sources` con `source_type` y `sync_enabled = true`.
3. Si rechaza → se oculta el banner y se muestra solo entrada manual.
4. El usuario puede revocar el acceso desde Ajustes del dispositivo. La app detecta el fallo de lectura y vuelve a modo manual silenciosamente.

### Lectura de datos

```dart
// Pasos del día concreto
final steps = await health.getTotalStepsInInterval(startOfDay, endOfDay);
// source: 'google_fit' en Android, 'apple_health' en iOS
```

Se llama a `upsert_steps(date, steps, source)` por cada día leído.

### Sincronización

| Momento | Acción |
|---|---|
| Al abrir la app (móvil) | Leer los últimos 7 días de la plataforma y hacer upsert |
| A medianoche (background) | WorkManager (Android) / BGAppRefreshTask (iOS) — leer el día anterior |
| A petición del usuario | Botón "Sincronizar ahora" en la pantalla de pasos |

**Web**: no hay acceso a datos de salud. Si el usuario ya tiene `step_sync_sources` con datos previos del móvil, los ve en modo lectura. Si no, puede introducir pasos manualmente.

---

## 4. Resolución de conflictos

Un conflicto ocurre cuando existen registros de `manual` y `google_fit`/`apple_health` para el mismo `(user_id, step_date)`.

**Flujo:**

1. Al entrar a la pantalla de pasos, la app llama a `get_my_conflicts()`.
2. Si hay conflictos, muestra un diálogo **no bloqueante** (puede posponer):
   > *"El {fecha} tienes datos distintos: {N} pasos manuales vs {M} pasos de Google Fit. ¿Cuál es el correcto?"*
   - Botón A: "Usar Google Fit / Apple Health ({M} pasos)"
   - Botón B: "Usar mi entrada manual ({N} pasos)"
   - Botón C: "Decidir más tarde"
3. Al elegir A o B → `resolve_step_conflict(date, winning_source)`.
4. Mientras no se resuelve, el leaderboard usa el registro `is_canonical = true` existente (el primero que se insertó).

---

## 5. Pantallas

### `StepsScreen` (ruta `/steps`)

Visible para todos los roles. Secciones:

1. **Banner de integración** (solo móvil, solo si no ha dado permisos aún): "Conecta Google Fit / Apple Health para sincronización automática" + botón "Conectar".
2. **Alerta de conflictos** (si `get_my_conflicts()` devuelve resultados): chip naranja "Tienes X días con datos en conflicto — Resolver" → abre diálogo.
3. **Resumen del desafío activo**: total de pasos acumulados en el desafío + días restantes.
4. **Botón "Sincronizar ahora"** (solo móvil, solo si tiene permisos): icono de refresh con timestamp del último sync.
5. **Historial día a día**: lista de cards con `step_date` y `step_count`. Cada card tiene un icono de edición para entrada/corrección manual.
6. **FAB "Añadir pasos"**: abre `ManualStepEntrySheet` (bottom sheet).

Si no hay desafío activo: mensaje "No hay ningún desafío activo ahora mismo."

### `ManualStepEntrySheet` (bottom sheet)

- Date picker (por defecto hoy; permite días pasados dentro del desafío activo).
- Campo numérico de pasos.
- Botón "Guardar" → `upsert_steps(date, count, 'manual')` → si hay conflicto, muestra diálogo de resolución inmediatamente.

### `LeaderboardScreen` (ruta `/leaderboard`, accesible desde la pestaña de pasos o desde el detalle del desafío)

- AppBar con nombre del desafío activo + botón refresh.
- Lista rankeada: posición · nombre del equipo · media de pasos · nº de miembros.
- Pull-to-refresh llama de nuevo a `get_team_leaderboard`.
- Si no hay desafío activo: mensaje vacío.
- El equipo propio se resalta visualmente.

---

## 6. Navegación

- `/steps` → `StepsScreen` (reemplaza el `SizedBox.shrink()` actual del router)
- `/leaderboard` → `LeaderboardScreen` (nueva ruta dentro del ShellRoute)
- La barra de navegación inferior añade un ítem "Leaderboard" (visible para todos los roles).

---

## 7. Formulario de creación de desafío — campo nuevo

`CreateChallengeScreen` añade un toggle:

> **¿Cuentan los fines de semana?** (Switch, por defecto activado)

Se envía como `p_count_weekends` al RPC `create_challenge` (que ya existe — actualizar su firma).

---

## 8. Restricciones y reglas de negocio

| Regla | Detalle |
|---|---|
| Solo se cuentan días dentro del rango `start_date..end_date` del desafío | El RPC filtra por fechas |
| Solo pasos con `is_canonical = true` | El RPC filtra explícitamente |
| Un usuario puede editar pasos manuales de cualquier día pasado del desafío | No hay bloqueo temporal para manual |
| La sync automática no sobreescribe una entrada manual sin preguntar | Lógica en `upsert_steps` → `sync_status = 'conflict'` |
| El leaderboard solo muestra el desafío activo | El RPC exige que el desafío esté en `status = 'active'` |
| Un equipo sin pasos registrados aparece en el ranking con media = 0 | `COALESCE(..., 0)` en el RPC |

---

## 9. Fuera de alcance (Fase 1)

- Leaderboard individual (solo equipos en esta fase).
- Historial de desafíos completados (pantalla separada, fase futura).
- Sync en background con servidor (Edge Function pull model) — el sync es desde la app cliente.
- Notificaciones push de recordatorio de pasos.
- Integración con Samsung Health.
- Validación de pasos anómalos (anti-trampa).
