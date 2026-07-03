# Spec: Autenticación y onboarding

## Contexto

Hasta la 1.0.x la app solo admite email/contraseña, y la incorporación a una empresa se hace pegando a mano un token UUID. Esta spec introduce el inicio de sesión con Google (OAuth), reordena el onboarding alrededor de la identidad (autenticarse primero, elegir destino después) y convierte la invitación en un enlace compartible. El email/contraseña se conserva como método alternativo.

---

## Regla fundamental de seguridad

La identidad la gestiona Supabase Auth (GoTrue); la pertenencia a empresa y el rol viven en `profiles` y se **enfuerzan a nivel de base de datos mediante RLS y RPCs `SECURITY DEFINER`** (`register_company`, `accept_invite`). Ningún método de autenticación otorga acceso a datos por sí mismo: un usuario autenticado sin fila en `profiles` no ve nada (todas las policies dependen de `my_company_id()`). El cliente nunca usa la service-role key.

---

## Métodos de autenticación

| Método | Estado | Notas |
|---|---|---|
| Email + contraseña | Vigente | `signUp` / `signInWithPassword`; recuperación de registros a medias vía `signUpOrSignIn` (`auth_helpers.dart`) |
| Google (OAuth 2.0 / PKCE) | **Nuevo en 1.1.0** | `signInWithOAuth(OAuthProvider.google)` con navegador externo y retorno por deep link |
| Microsoft (Entra ID) | Fuera de alcance | Mismo mecanismo que Google; prevista como siguiente proveedor |
| Apple | Fuera de alcance | Bloqueado: requiere cuenta Apple Developer de pago (capability + Service ID) |

**Decisión explícitamente validada:** email/contraseña se mantiene como alternativa permanente (red de seguridad para emuladores sin Google Play y para tests). El upgrade es aditivo → versión `1.1.0`.

**Decisión explícitamente validada:** esta iteración incluye únicamente Google. Microsoft y Apple quedan documentados en Fuera de alcance.

---

## Estados de identidad

```
anónimo ──(login/signup password | OAuth Google)──► autenticado sin perfil
autenticado sin perfil ──(register_company)──► admin de empresa
autenticado sin perfil ──(accept_invite)────► member de empresa
member/admin ──(kick_user)──► autenticado sin perfil   (la fila de profiles se borra)
```

| Estado | Descripción | Qué ve en la app |
|---|---|---|
| Anónimo | Sin sesión | `/login` |
| Autenticado sin perfil | Sesión válida pero sin fila en `profiles` (recién llegado por OAuth, registro a medias, o kickeado) | Pantalla de onboarding con dos salidas: **Crear empresa** / **Tengo una invitación**. Nunca el dashboard vacío |
| Member / Admin | Sesión + perfil con `company_id` | Dashboard y navegación completa |

El estado "autenticado sin perfil" es de primera clase: es el punto de paso obligado del flujo OAuth y también el destino de los usuarios kickeados (antes: dashboard vacío, gap conocido).

**Sincronización de providers tras crear el perfil:** `currentProfileProvider` cachea `null` si se evalúa entre la autenticación y la creación del perfil; tras `register_company`/`accept_invite` se llama a `supabase.auth.refreshSession()` para forzar la relectura (patrón ya establecido).

---

## Comportamientos por actor

### Cualquier persona (sin empresa)

**Iniciar sesión / registrarse con Google**
- Botón "Continuar con Google" en `/login` (y como primer paso de registro de empresa e invitación).
- `signInWithOAuth(OAuthProvider.google, redirectTo: 'healthywalky://login-callback')` abre el navegador externo; al autorizar, el sistema devuelve el control a la app por deep link y `onAuthStateChange` emite `signedIn`.
- Tras el retorno: si `currentUserHasProfile()` → `/dashboard`; si no → onboarding (autenticado sin perfil).
- No existe distinción registro/login con OAuth: la primera autorización crea el `auth.users`.

**Iniciar sesión con email/contraseña** — flujo actual sin cambios.

**Registrar una empresa**
- Con sesión ya iniciada (venimos de Google): el formulario muestra solo datos de empresa + "Tu nombre completo" **precargado desde `user_metadata['full_name']` y editable**; se omiten email y contraseña.
- Sin sesión: flujo actual completo (email + contraseña + `signUpOrSignIn`).
- En ambos casos el cierre es `register_company` (RPC atómico: empresa + perfil admin) + `refreshSession()`.

**Aceptar una invitación**
- El token llega por deep link `healthywalky://invite?token=...` (enlace compartido) o pegado a mano en el diálogo de `/login` (vía manual conservada).
- Con sesión iniciada: solo se muestra el nombre precargado (editable) + botón de unirse. Sin sesión: primero autenticarse (Google o email/contraseña) en la propia pantalla.
- Cierre: `accept_invite(p_token, p_display_name)` (valida one-time use, crea perfil `member`, quema el token) + `refreshSession()`.

**Decisión explícitamente validada:** el `display_name` con OAuth se toma del proveedor y es **editable antes de confirmar** (un paso menos, sin nombres vacíos).

### Admin

**Generar y compartir una invitación**
- `create_invite()` (RPC admin-only, token one-time) como hasta ahora.
- Nuevo: botón "Compartir invitación" que abre el **share sheet nativo** (`share_plus`) con un mensaje que incluye el enlace `healthywalky://open/invite?token=<token>` **y el código en texto plano como fallback** (no todos los mensajeros hacen clicable un scheme custom).
- Se conserva el botón de copiar el código.

**Decisión explícitamente validada:** la ergonomía elegida es enlace + share sheet, sin QR en esta iteración.

---

## Deep links

Scheme custom registrado en ambas plataformas: `healthywalky://`

| URI | Uso |
|---|---|
| `healthywalky://login-callback` | Retorno del flujo OAuth (redirect de Supabase Auth; lo procesa supabase_flutter, el router lo reconduce a login/dashboard) |
| `healthywalky://open/invite?token=<uuid>` | Abre la app en `/invite` con el token precargado. El segmento `open` es el *host* del URI: go_router enruta por el `path` (`/invite`), no por el host |

- Android: `intent-filter` `VIEW` + `BROWSABLE` con `android:scheme="healthywalky"` en `MainActivity`.
- iOS: `CFBundleURLTypes` en `Info.plist`.
- Limitación documentada: enlaces `https://` clicables universalmente (Android App Links / iOS Universal Links) requieren un dominio propio con ficheros de verificación y, en iOS, la capability Associated Domains (cuenta de pago). Fuera de alcance en fase POC.

---

## Vinculación de identidades (identity linking)

Supabase enlaza automáticamente un login de Google con un usuario email/contraseña existente **si el email coincide y está verificado**: el `auth.users.id` (y por tanto el perfil y sus datos) se conserva, y el usuario queda con dos identities. Comportamiento aceptado tal cual; no se construye UI de gestión de identities en esta fase. Caso borde documentado: si el email del usuario password no está verificado, Google crea un usuario distinto sin perfil → aterriza en onboarding y puede pedir una invitación nueva (mismo tratamiento que un kickeado).

---

## Restricciones enforzadas en BD

Sin cambios: `register_company` y `accept_invite` ya validan todo lo relevante en el servidor (atomicidad, one-time token, rol). **No se prevén migraciones nuevas para esta spec** — si durante la implementación surgiera la necesidad, iría numerada `0024+` sin editar migraciones aplicadas.

---

## Configuración externa requerida (no versionada en el repo)

| Dónde | Qué |
|---|---|
| Google Cloud Console | OAuth Client (tipo *Web application*) con redirect URI del proyecto Supabase (`https://<ref>.supabase.co/auth/v1/callback`) — uno por proyecto o compartido |
| Supabase dashboard (dev **y** testers) | Authentication → Providers → Google: habilitar con client ID + secret; Authentication → URL Configuration → añadir `healthywalky://**` a *Redirect URLs* (cubre `login-callback` y el retorno a `/invite`, que lleva el token en la query) |

Ambos proyectos (dev `qpobvyuqbqimbdfmakwd`, testers `qqrxaehuqjtwgukokggf`) deben configurarse o el login con Google fallará solo en uno de los entornos.

---

## Fuera de alcance (esta fase)

- Proveedores Microsoft (Entra ID) y Apple (este último bloqueado por cuenta Apple Developer de pago).
- Código QR de invitación.
- Auto-join por dominio de email corporativo (Google Workspace / Entra ID).
- Enlaces de invitación `https://` (App Links / Universal Links).
- Pantalla de perfil para editar `display_name` a posteriori.
- UI de gestión de identities vinculadas.
- Recuperación de contraseña por email (el método password sigue sin reset flow).
