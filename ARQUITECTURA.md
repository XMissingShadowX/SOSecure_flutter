# SOSecure — Arquitectura y flujos (app Flutter + web Next.js)

Documento de referencia de cómo encajan las dos mitades del sistema. La web
(Next.js) es a la vez la PWA y el **backend de la app Flutter**: no hay un
servidor aparte.

> Complementa, no reemplaza, al `CLAUDE.md` del repo web (que cubre a fondo el
> cifrado de contactos, el PIN, RLS y los planes). Aquí el foco está en **cómo
> se hablan los dos proyectos**.

---

## 1. Panorama

```
┌──────────────────┐        ┌───────────────────────────┐        ┌────────────┐
│  App Flutter     │        │  Web Next.js (Vercel)     │        │  Supabase  │
│  (Android/Pixel) │        │  www.sosecure.site        │        │            │
│                  │        │                           │        │            │
│  repositories ───┼───────▶│  /api/*  (App Router)     │───────▶│  Postgres  │
│                  │  HTTPS │                           │ service│  Auth      │
│  supabase_client ┼────────┼───────────────────────────┼───────▶│  Realtime  │
│                  │  SDK   │  PWA (misma UI en web)    │  anon  │  Storage   │
└──────────────────┘        └───────────────────────────┘        └────────────┘
                                        │
                                        ├──▶ Anthropic Claude (chat IA)
                                        ├──▶ Resend (correos)
                                        └──▶ Mercado Pago / PayPal (pagos)
```

La app usa **dos vías** hacia los datos, y saber cuál toca cada cosa es la clave
para depurar:

| Vía | Cuándo se usa | Auth |
|---|---|---|
| **Supabase SDK nativo** (`supabase_client.dart`) | Lecturas/escrituras normales sujetas a RLS: contactos, incidentes, alertas, planes | Sesión del SDK, `auth.uid()` en RLS |
| **HTTP a `/api/*` de la web** | Todo lo que necesita un secreto de servidor (service role, API key de Claude, tokens de MP/PayPal) o lógica compartida con la web | `Authorization: Bearer <access_token>` |

---

## 2. Reglas de oro del transporte HTTP

Dos detalles han causado bugs reales. Ambos rompen **solo los POST** y de forma
silenciosa (la respuesta es HTML, no JSON, y revienta en `jsonDecode`).

### 2.1 La barra final NO es opcional

`next.config.ts` de la web tiene `trailingSlash: true`. Una URL sin barra final
devuelve **308** hacia la versión con barra, y en ese salto el POST **pierde el
cuerpo**.

```dart
// MAL — devuelve HTML "Redirecting..."
Uri.parse('${Env.apiBaseUrl}/api/family/checkout')
// BIEN
Uri.parse('${Env.apiBaseUrl}/api/family/checkout/')
```

### 2.2 El dominio va CON `www`

El dominio canónico en Vercel es `www.sosecure.site`. `https://sosecure.site`
responde **307** hacia el `www`, con la misma pérdida de cuerpo.

```
sosecure.site/api/premium/checkout/       → 307 Redirecting...
www.sosecure.site/api/premium/checkout/   → 401 {"error":"No autenticado"}  ✅
```

Un 401 JSON es **buena señal**: significa que la ruta se alcanzó. Un
`FormatException: Unexpected character (at character 1)` con `Redirecting...`
significa que se violó 2.1 o 2.2.

`Env.apiBaseUrl` (`lib/core/env.dart`) es la fuente de verdad del dominio.

---

## 3. Autenticación entre app y API

La web autentica por **cookie**; la app Flutter no tiene cookies. El puente es
`getAuthedUser(req)` en `lib/supabase/server.ts` (repo web): acepta la cookie de
sesión **o** el header `Authorization: Bearer <access_token>`, así que una ruta
migrada sigue funcionando igual para la web.

```dart
// Patrón en la app (plan_api.dart / pin_api.dart)
Future<Map<String, String>> _authHeaders() async {
  final token = supabase.auth.currentSession?.accessToken;
  return {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
}
```

Variante: `getRequestScopedClient(req)` devuelve el **cliente** en vez del user,
para rutas que necesitan `auth.uid()` dentro de un RPC o de RLS. El admin client
(service role) **no sirve** ahí: `auth.uid()` resolvería a `null`.

### Estado de las rutas

| Ruta | Acepta Bearer | Usada por la app |
|---|---|---|
| `/api/pin/`, `/api/pin/verify/` | ✅ | ✅ |
| `/api/chat/`, `/api/emergency-chat/` | ✅ | ✅ |
| `/api/premium/checkout/`, `/api/family/checkout/` | ✅ | ✅ |
| `/api/premium/cancel/`, `/api/family/cancel/` | ✅ | ✅ |
| `/api/delete-account/` | ✅ | ✅ |
| `/api/family/invite/`, `/api/family/accept/` | ❌ cookie | ❌ solo web |
| `/api/tracking-invite/` | ❌ cookie | ❌ solo web |
| `/api/pin/finalize-reset/` | ❌ cookie | ❌ solo web (Magic Link) |
| `/api/*/webhook/` | n/a — firma del proveedor | ❌ |

**Si la app necesita una ruta marcada como "cookie":** cambiar
`createServerClient()` + `auth.getUser()` por `getAuthedUser(req)`. Es el mismo
cambio de dos líneas que se hizo en los checkout, y no afecta a la web.

---

### Correos de auth y deep links

El **Site URL** de Supabase es `sosecure://login-callback` (deep link a la app,
registrado en `AndroidManifest.xml` y manejado solo por `supabase_flutter`).
Como es un esquema personalizado, **todo flujo debe pasar su `redirectTo`
explícito** — si no coincide con la allowlist, Supabase cae al Site URL y el
correo llega con un link que en escritorio no hace nada.

| Flujo | `redirectTo` que manda |
|---|---|
| Registro desde la app | `sosecure://login-callback` |
| Registro desde la web | `${clientAppUrl()}/auth/callback` |
| Olvidé mi PIN | `${APP_URL}/auth/callback` |
| Recuperar contraseña (web) | `${window.location.origin}/auth/reset-password` |

Todos esos destinos tienen que estar en **Authentication → URL Configuration →
Redirect URLs**. Lo más robusto son comodines: `https://www.sosecure.site/**` y
`http://localhost:3000/**`.

> **El código del correo es de un solo uso.** Cualquier `useEffect` que llame
> `exchangeCodeForSession` debe correr **exactamente una vez**: guard con
> `useRef`, leer el código de `window.location` (no de `useSearchParams`) y
> borrarlo de la URL al leerlo. Un `t` de `useTranslation` en las dependencias
> basta para que el efecto se repita y el segundo canje falle con "el enlace ha
> expirado", aunque el primero haya funcionado.

---

## 4. Flujo de pago (el más enredado)

Mercado Pago y PayPal son flujos de **navegador**; no hay compra in-app. Lo que
cambió es *qué* se abre en el navegador.

```
Ajustes → "Activar"
   │
   ├─▶ checkout_launcher.dart: hoja "¿Con qué quieres pagar?" → mercadopago | paypal
   │
   ├─▶ PlanApi.startCheckout(family:, provider:)
   │      POST /api/{family|premium}/checkout/  + Authorization: Bearer
   │      body: { action: 'create-session', provider }
   │
   ├─▶ La web crea/recupera la fila (family_groups | premium_subscriptions)
   │   con el admin client y devuelve { url, provider }:
   │      MP     → init_point del preapproval_plan + ?external_reference=<id fila>
   │      PayPal → link 'approve' de la suscripción, con custom_id=<id fila>
   │
   ├─▶ launchUrl(url) → el usuario paga en la pasarela
   │
   └─▶ Al volver: el navegador aterriza en la página web SIN sesión,
       así que la captura del navegador falla y **el webhook es quien activa**.
```

### El respaldo

`openCheckout` envuelve todo en try/catch: si la API falla por lo que sea, abre
la **página web del checkout** (`/plan-familiar`, `/plan-premium/pago`), que
pedirá iniciar sesión pero funciona. Nunca deja al usuario sin forma de pagar.
El `debugPrint('[checkout] fallo la API…')` es lo que distingue un fallo de la
API del camino feliz — sin él son indistinguibles desde la UI.

### Activación y webhooks

El precio **no vive en el código**. `FAMILY_PLAN.amountCents` / `PREMIUM_PLAN`
solo se registran en Supabase y se muestran en la UI; lo que se cobra lo define
el plan en cada pasarela.

- Cambiar precio en MP: `PUT /preapproval_plan/{id}` con
  `auto_recurring.transaction_amount` (en **pesos**, no centavos).
- Cambiar precio en PayPal: `POST /v1/billing/plans/{id}/update-pricing-schemes`.
  La **moneda no se puede cambiar** en un plan existente → crear plan nuevo.

Webhooks (respaldo si el usuario cierra el navegador antes de volver):

| Proveedor | Endpoint | Eventos |
|---|---|---|
| Mercado Pago (ambos planes) | `/api/family/webhook` | `subscription_preapproval`, `payment` |
| PayPal familiar | `/api/family/webhook` | `BILLING.SUBSCRIPTION.ACTIVATED/CANCELLED` |
| PayPal premium | `/api/premium/webhook` | `BILLING.SUBSCRIPTION.ACTIVATED/CANCELLED` |

**Consecuencia práctica:** tras pagar desde la app, el plan puede tardar unos
segundos en verse activo y hay que salir y volver a entrar a Ajustes. Si eso
molesta, la solución es un endpoint de captura que la app llame con su token
pasándole el `preapproval_id` / `subscription_id`.

---

## 5. Estructura de la app Flutter

Riverpod para estado, go_router para navegación, easy_localization para i18n.

```
lib/
├── main.dart                  # bootstrap: Supabase, i18n, foreground service
├── app.dart                   # MaterialApp.router
├── core/
│   ├── env.dart               # ⚠️ apiBaseUrl, claves públicas de Supabase
│   ├── router.dart            # rutas + redirect por sesión/PIN/permisos
│   ├── theme.dart, brand.dart, glass.dart
│   └── indigenous_locale_fallback.dart   # nah/myn/tze caen a es
│
├── data/
│   ├── supabase_client.dart   # instancia global del SDK
│   ├── api/                   # ── HTTP hacia /api/* de la web ──
│   │   ├── pin_api.dart
│   │   └── plan_api.dart      # checkout, cancelar, borrar cuenta
│   └── repositories/          # ── Supabase directo (RLS) ──
│       ├── contacts_repository.dart      # vía RPCs cifradas
│       ├── incidents_repository.dart
│       ├── alerts_repository.dart
│       ├── live_location_repository.dart # Realtime
│       ├── live_stream_repository.dart
│       ├── recordings_repository.dart    # Storage
│       ├── plan_repository.dart          # lee estado de premium/familiar
│       ├── chat_repository.dart          # + HTTP a /api/chat/
│       ├── emergency_chat_repository.dart
│       ├── routes_repository.dart        # OSRM
│       └── geocoding_repository.dart     # Nominatim
│
├── domain/models/             # modelos puros (incident, sos_alert, …)
│
├── features/                  # una carpeta por pantalla
│   ├── onboarding/            # login, sign-up, permission gate
│   ├── pin/                   # pin_lock_screen
│   ├── shell/                 # app_shell_screen (tabs) + settings_screen
│   ├── home/ before/ during/ after/ medic/ map/ routes/
│   ├── during/sos_button.dart
│   ├── chat/                  # emergency chat + live stream viewer
│   └── premium/               # checkout_launcher, upgrade_cta
│
├── platform/                  # canales nativos
│   ├── volume_button_channel.dart   # SOS con botones de volumen
│   ├── sos_alarm.dart
│   └── sos_foreground_service.dart
│
└── state/                     # providers Riverpod (uno por dominio)
```

### Rutas de navegación (`core/router.dart`)

`/` (shell con tabs), `/login`, `/sign-up`, `/sign-up-success`,
`/permission-gate`, `/pin-lock`, `/settings`.

El `redirect` decide a dónde mandar según sesión, y se refresca con
`GoRouterRefreshStream(supabase.auth.onAuthStateChange)`. El router se construye
**una sola vez** (`appRouter` global): reconstruirlo pierde el estado de
navegación.

### i18n

`assets/translations/{es,en,nah,myn,tze}.json`, `fallbackLocale: es`. Las
lenguas indígenas heredan del español, así que **basta agregar una clave nueva a
`es.json` y `en.json`**; los otros tres caen a español solos. Los nombres de
marca (Mercado Pago, PayPal) no se traducen — van literales en el Dart.

---

## 6. Estructura de la web Next.js

```
app/
├── page.tsx                   # splash + auth + confirma resets de PIN
├── auth/                      # login, sign-up, callback, reset, forgot
├── admin/                     # panel de administración
├── emergency/[alertId]/       # página pública de alerta SOS
├── tracking/[sessionId]/      # sesión de rastreo compartido
├── plan-familiar/             # pago + aceptar invitación
├── plan-premium/pago/
├── privacidad/, terminos/
└── api/
    ├── chat/, emergency-chat/         # Claude
    ├── pin/, pin/verify/, pin/finalize-reset/
    ├── premium/{checkout,cancel,webhook}/
    ├── family/{checkout,cancel,webhook,invite,accept}/
    ├── tracking-invite/, tracking-location/
    ├── emergency/[alertId]/video/
    └── delete-account/

components/  tabs/ + app-shell + sos-button + mapas (Leaflet)
lib/         store.ts (Zustand), i18n.ts, plan-config.ts, supabase/{client,server}.ts
```

---

## 7. Datos y seguridad (resumen operativo)

Detalle completo en `CLAUDE.md` del repo web. Lo mínimo que hay que saber al
tocar la app:

- **Teléfonos de contactos cifrados** (pgcrypto + Vault). Se accede **solo** por
  RPCs `SECURITY DEFINER`: `get_my_contacts()`, `add_emergency_contact(...)`,
  `update_emergency_contact(...)`. Nunca `from('emergency_contacts').select()`
  para leer el teléfono.
- **PIN**: hasheo y verificación **solo en servidor** (bcrypt, 12 rounds). La app
  llama `/api/pin/verify/`; nunca compara local. `pin_hash` tiene el SELECT
  revocado a nivel de columna: leerlo requiere admin client.
- **Escrituras a tablas con RLS** desde API routes → admin client (service role),
  o RLS las bloquea en silencio.
- `profiles` **no se crea sola** al registrarse (el trigger llena
  `user_profiles`). Escribir en `profiles` con `.upsert(onConflict:'id')`, nunca
  `.update()` — no falla, simplemente no afecta filas.

---

## 8. Depuración en dispositivo

`adb` no suele estar en el PATH en Windows:

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb devices
& $adb -s <serial> logcat -c                      # limpiar
& $adb -s <serial> logcat -s flutter:* -v time    # seguir logs de Dart
```

Compilar e instalar (desde la raíz del proyecto Flutter):

```powershell
flutter build apk --debug
flutter install -d <serial> --debug
```

Comprobar una ruta de la API sin la app (PowerShell abre un prompt de
credenciales ante un 401; usar `curl.exe`):

```powershell
curl.exe -s -X POST -H "Content-Type: application/json" -d "{}" `
  https://www.sosecure.site/api/premium/checkout/
# esperado: {"error":"No autenticado"}
```

### Síntomas frecuentes

| Síntoma | Causa probable |
|---|---|
| `FormatException` + `Redirecting...` | Falta barra final, o dominio sin `www` |
| `401 No autenticado` desde la app | La ruta aún no usa `getAuthedUser` |
| `permission denied for column` | Se leyó `pin_hash`/`pin_reset_pending` sin admin client |
| Escritura que "funciona" pero no cambia nada | RLS bloqueando, o `.update()` sobre fila inexistente |
| Plan pagado que no aparece activo | Normal: lo activa el webhook, no la página de retorno |

---

## 9. Pendientes conocidos

- **Captura inmediata del pago**: hoy depende del webhook. Un endpoint que la app
  llame con Bearer pasándole el `preapproval_id` quitaría la espera.
- **Captura del pago desde la app**: el flujo "olvidé mi PIN" iniciado en la app
  manda al usuario a la **web** (`/api/pin` usa `APP_URL` fijo), no de vuelta a
  la app. Funciona, pero es un desvío. Se arreglaría dejando que la app indique
  el destino (`sosecure://login-callback`), validado server-side contra una
  lista blanca para no abrir un redirect abusable.
- **Rate limiting del PIN**: es un `Map` en memoria, no persiste entre instancias
  serverless. Reemplazar por Redis/Upstash en producción real.
- **Rutas cookie-only**: invitaciones de familia y de tracking no son usables
  desde la app hasta migrarlas a `getAuthedUser`.
