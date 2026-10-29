# Parte Backend (WS2) — despliegue de `wapi-send-products`, `wapi-cron-dispatch` y la migración `solo_disponibles`

> **Contexto**: producción (`vsieeihstajlrdvpuooh`) no es escribible desde los MCP de esta sesión
> (rol `supabase_read_only_user` / `default_transaction_read_only=on`; el otro MCP apunta a un
> proyecto distinto). Por eso **todo lo de abajo lo ejecuta el usuario** en su máquina.
>
> Esta parte es autónoma: no depende de las otras secciones del `DEPLOY_WAPI_2026-10-28.md`.
> No ejecutar `supabase db push` (ver nota 5): el historial remoto de migraciones NO coincide
> con los ficheros locales y un push intentaría aplicar ~10 migraciones viejas.

---

## 0. Qué cambia (resumen para revisar)

| Artefacto | Cambio |
|---|---|
| `supabase/functions/wapi-send-products/index.ts` | Fix del bug "producto no encontrado" (precarga por ventana posicional + fallback puntual + `error_code` `PRODUCTO_NO_ENCONTRADO`) + soporte `solo_disponibles` + modo `dry_run`. |
| `supabase/functions/wapi-cron-dispatch/index.ts` | Lee `app_wapi_programacion.solo_disponibles` y lo reenvía a `wapi-send-products` (sólo cuando es `true`). **Tolerante**: si la columna aún no existe (migración sin aplicar) reintenta el select sin ella, asume `false`, avisa en logs y la difusión se envía igual (no se salta en silencio). |
| `supabase/migrations/20261028_wapi_programacion_solo_disponibles.sql` | `alter table public.app_wapi_programacion add column if not exists solo_disponibles boolean not null default false;` + `comment on column`. **Aditiva e idempotente**. |
| `supabase/config.toml` | Fija `verify_jwt = false` para `wapi-send-products` y `verify_jwt = true` para `wapi-cron-dispatch` (que un deploy genérico no los cambie). |

Orden recomendado: **1) migración → 2) desplegar funciones → 3) verificar**. Gracias al blindaje
de `wapi-cron-dispatch` **cualquier orden es seguro**: si las funciones van primero, el cron avisa
en logs de que falta la migración y envía sin filtro de stock en vez de romperse.

---

## 1. Prerrequisitos

- Node.js 18+ y `npx` (o `npm i -g supabase`).
- Login de la CLI una sola vez (abre el navegador; no hay que tener PAT):
  ```powershell
  cd <ruta-al-repo>\ventiq_admin_app
  npx supabase login
  ```
  Comprobar: `npx supabase projects list` debe listar `vsieeihstajlrdvpuooh`.
- Todos los comandos se lanzan **desde `ventiq_admin_app/`** (ahí está `supabase/config.toml` y
  `supabase/functions/`). El `project_id` del config ya apunta a producción.

> Si `npx` está bloqueado por el sandbox (EPERM en `npm-cache`), redirigir la caché al workspace:
> `$env:npm_config_cache = "$PWD\.npm-cache"` antes de los `npx`.

---

## 2. Aplicar la migración (SOLO el fichero nuevo)

### Opción A — SQL Editor del dashboard (la más simple, recomendada)

1. Dashboard del proyecto `vsieeihstajlrdvpuooh` → **SQL Editor** → *New query*.
2. Pegar el contenido **completo** de
   `ventiq_admin_app/supabase/migrations/20261028_wapi_programacion_solo_disponibles.sql`.
3. *Run*. Es idempotente (`ADD COLUMN IF NOT EXISTS`), se puede repetir sin daño.

### Opción B — CLI (≥ 2.79) con `db query`

```powershell
cd ventiq_admin_app
npx supabase db query --file .\supabase\migrations\20261028_wapi_programacion_solo_disponibles.sql --project-ref vsieeihstajlrdvpuooh
```

> Si tu versión de la CLI no reconoce `db query` (es reciente), no pasa nada: usa la **Opción A**
> (SQL Editor) o la **Opción C** (`psql`). El SQL es el mismo fichero.

### Opción C — `psql` con la cadena de conexión

Dashboard → *Project Settings* → *Database* → *Connection string* (usar la de **session pooler** o
*Direct connection*):

```powershell
psql "postgresql://postgres.<ref>:<PASSWORD>@<host>:5432/postgres" `
  -f .\supabase\migrations\20261028_wapi_programacion_solo_disponibles.sql
```

### Verificación de la migración

```sql
select column_name, data_type, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'public'
   and table_name   = 'app_wapi_programacion'
   and column_name  = 'solo_disponibles';
```

Esperado: **1 fila** → `solo_disponibles | boolean | NO | false`.

```sql
-- Estado actual de las programaciones (todas deben salir en false salvo que se active a mano)
select id, id_tienda, activa, solo_disponibles from public.app_wapi_programacion order by id;
```

Para **activarlo** en una programación concreta (ejemplo, la 13 de la tienda 177):

```sql
update public.app_wapi_programacion set solo_disponibles = true where id = 13;
```

---

## 3. Desplegar las 2 edge functions

### Opción A — CLI (recomendada; es la única que resuelve bien los `import ../_shared/*.ts`)

```powershell
cd ventiq_admin_app
npx supabase functions deploy wapi-send-products --project-ref vsieeihstajlrdvpuooh
npx supabase functions deploy wapi-cron-dispatch --project-ref vsieeihstajlrdvpuooh
```

- El `verify_jwt` lo toma de `supabase/config.toml` (ya está fijado); si la versión de CLI lo
  ignorase, pasarlo explícito:
  `--no-verify-jwt` para `wapi-send-products` (¡NO para cron-dispatch!).
- **Nunca** `npx supabase functions deploy` sin nombre: reescribe el `verify_jwt` de TODAS las
  funciones (rompería `wapi-webhook`, que también va con `verify_jwt = false`).
- No hace falta `--import-map` (no hay import map; las deps son `https://esm.sh/...` inline).

### Opción B — Management API con PAT (si la CLI no es viable)

Crear un PAT en https://supabase.com/dashboard/account/tokens y:
`$env:SUPABASE_ACCESS_TOKEN = "sbp_..."`.

La API de despliegue por ficheros que usa la CLI internamente (`POST /v1/projects/{ref}/functions/deploy?slug=...`,
`multipart/form-data` con una parte `metadata` JSON + una parte `file` por fichero) requiere el
bundle ya resuelto (eszip); **no es práctico a mano** para funciones con `_shared/`.

Ruta sí practicable con PAT: **`PUT /v1/projects/{ref}/functions/{slug}`** con el cuerpo de UNA
sola función (campo `body` = código fuente completo). Para eso hay que *inline-ar* `_shared`:

```powershell
# 1) bundle a un único fichero ESM (deja las URLs https://esm.sh como externas)
npx --yes esbuild .\supabase\functions\wapi-send-products\index.ts `
  --bundle --format=esm --platform=neutral --target=es2022 `
  --external:https://* --outfile=.\supabase\functions\wapi-send-products\bundle.ts
```

```powershell
# 2) subir el bundle (verify_jwt explícito)
$env:SUPABASE_ACCESS_TOKEN = "sbp_..."
$cuerpo = Get-Content .\supabase\functions\wapi-send-products\bundle.ts -Raw
$json = @{ name = "wapi-send-products"; slug = "wapi-send-products"; verify_jwt = $false; body = $cuerpo } | ConvertTo-Json -Depth 5
Invoke-RestMethod -Method Put `
  -Uri "https://api.supabase.com/v1/projects/vsieeihstajlrdvpuooh/functions/wapi-send-products" `
  -Headers @{ Authorization = "Bearer $env:SUPABASE_ACCESS_TOKEN"; "Content-Type" = "application/json" } `
  -Body $json
```

Repetir con `wapi-cron-dispatch` y `verify_jwt = $true`.
> ⚠️ La ruta B (bundle + `PUT`) no se ha probado contra producción en esta sesión: si la API la
> rechaza, usar la opción A (CLI) que es la que usa el propio dashboard.

---

## 4. Comprobaciones posteriores

### 4.1 Versión desplegada (debe subir)

Dashboard → *Edge Functions*, o:

```powershell
npx supabase functions list --project-ref vsieeihstajlrdvpuooh
```

Esperado (versiones antes del cambio: `wapi-send-products` **v31**, `wapi-cron-dispatch` **v24**):

- `wapi-send-products` → **v32 o mayor**, `verify_jwt = false`.
- `wapi-cron-dispatch` → **v25 o mayor**, `verify_jwt = true`.

Por Management API con PAT:
`GET https://api.supabase.com/v1/projects/vsieeihstajlrdvpuooh/functions` (mirar `version` y `verify_jwt`).

### 4.2 DRY-RUN por HTTP (no envía nada, no escribe nada)

`wapi-send-products` tiene `verify_jwt=false` en el gateway, **pero la función exige credenciales
propias**: acepta `service_role` o el JWT de un usuario gerente/supervisor de la tienda. **La
publishable/anon key devuelve 401** (`No autenticado`) a propósito: `dry_run` resuelve nombre,
precio y stock del catálogo y no se abre a llamadas anónimas.

> ⚠️ **NUNCA pegues la `service_role` key en el repo, en un commit, en un issue, en un chat ni en
> una captura de pantalla.** Es la llave maestra del proyecto (bypasea RLS). Si la pegas en una
> terminal para una prueba, que sea en tu máquina y bórrala del historial (`Remove-Item (Get-
> PSReadlineOption).HistorySavePath`) o, mejor, cárgala desde una variable de usuario. Si sospechas
> que se ha filtrado, rótala en *Project Settings → API keys → Rotate* y actualiza los secretos.
>
> Alternativas sin copiar la clave:
> - **Dashboard → Edge Functions → `wapi-send-products` → panel de *Test/Invoke*** (si tu versión
>   del Dashboard lo tiene): la petición sale autenticada por el propio Dashboard; pega el body
>   JSON de abajo tal cual.
> - **Con la sesión del propio usuario** (JWT de un gerente/supervisor de la tienda): sirve el
>   mismo body. Sirve, por ejemplo, un botón de diagnóstico en la app (si `flutter-ui` lo añade);
>   el contrato de la respuesta es el mismo.
>
> Con **service_role key** (Dashboard → *Project Settings* → *API keys* → `service_role`) y el
> mismo conjunto del incidente: **53 productos × 5 destinos = 265 mensajes**.

```powershell
$SERVICE = "<SERVICE_ROLE_KEY>"
$body = @'
{
  "id_sesion": 22,
  "dry_run": true,
  "product_ids": [5260,5263,5265,5266,5269,5282,5292,5315,6777,7232,7318,7319,7320,7323,7324,7325,7327,7328,7337,7338,7339,7344,7345,8919,8928,9082,9087,9088,9089,9092,9243,9249,9252,9322,9323,9324,9325,9512,9746,10410,10416,10417,10418,10504,10505,10507,10508,10509,11042,11058,11059,11061,11062],
  "destinations": [
    {"tipo":"grupo","chat_id":"120363172271515786@g.us"},
    {"tipo":"grupo","chat_id":"120363195152592934@g.us"},
    {"tipo":"grupo","chat_id":"120363266453891641@g.us"},
    {"tipo":"grupo","chat_id":"120363406746096914@g.us"},
    {"tipo":"grupo","chat_id":"120363409451879219@g.us"}
  ]
}
'@
$r = Invoke-RestMethod -Method Post `
  -Uri "https://vsieeihstajlrdvpuooh.supabase.co/functions/v1/wapi-send-products" `
  -Headers @{ Authorization = "Bearer $SERVICE"; "Content-Type" = "application/json" } `
  -Body $body
$r.data | ConvertTo-Json -Depth 4
```

**Criterio de éxito** (cuerpo `{success:true, data:{...}}`):

| Campo | Esperado | Significado |
|---|---|---|
| `dry_run` | `true` | Está en modo prueba |
| `productos` | `53` | Productos del plan |
| `productos_resueltos` | `53` | **Todos** con datos de producto |
| `productos_sin_info` | `[]` | **0** "producto no encontrado" ← esto es el bug |
| `productos_sin_imagen` | `[]` (o sólo productos realmente sin imagen) | |
| `destinos` | `5` | |
| `mensajes` | `265` | 53 × 5 pares preparables |
| `plan.length` | `265` | Un elemento por mensaje, con `caption_resumen` |

Además, en los logs de la función debe verse:
`DRY-RUN: 53/53 producto(s) resueltos, 265/265 mensaje(s) preparables, 0 sin info, 0 sin imagen`.

### 4.3 `solo_disponibles` de punta a punta (sin enviar nada)

1. Activar el flag en una programación de prueba:
   `update public.app_wapi_programacion set solo_disponibles = true where id = <id>;`
   (si la columna no existe todavía, aplica primero la migración: sección 2)
2. Forzar el cron manualmente (una sola vez):
   ```sql
   select public.fn_wapi_dispatch_diario();
   -- o directo por HTTP con service_role:
   -- POST /functions/v1/wapi-cron-dispatch  body {"id_programacion": <id>}
   ```
3. Mirar la respuesta y los logs:
   - Respuesta de `wapi-cron-dispatch`: `"solo_disponibles": true`. Si en su lugar aparece
     `"aviso": "la columna ... no existe..."`, falta aplicar la migración (la difusión se envió
     igual, sin filtro de stock).
   - Logs de `wapi-send-products`: debe aparecer
   `solo_disponibles: N/M producto(s) sin stock quedan fuera del envío`
   (y `stock DESCONOCIDO … NO se filtran`, si aplica).
   En `app_wapi_envio_log` no aparecen filas para los productos agotados en una tanda nueva (el
   producto agotado no se anuncia).
4. **Dejarlo como estaba** (`set solo_disponibles = false`) si no se quiere activar aún.

### 4.4 Regresión mínima (una tanda manual pequeña, en horario tranquilo)

Enviar 2–3 productos a 1 grupo de prueba desde la app y comprobar que el historial queda
`enviado` (o reanudable) y que el caption sigue igual que antes.

---

## 5. Notas / avisos

1. **No usar `supabase db push`**: el historial remoto (`supabase_migrations.schema_migrations`)
   no coincide con los ficheros locales de `supabase/migrations/`; un push intentaría aplicar
   ~10 migraciones antiguas. La migración nueva se aplica a mano (sección 2).
2. El fix del bucle **no cambia** el orden del plan, los delays, la idempotencia
   (`wa-log-<logId>-<hash>`) ni el chunking por presupuesto: sólo precarga los datos de producto
   que necesita. La única consulta añadida es la ventana que falte (máx. `ceil(N/25)` por worker;
   con 53 productos = 3, las mismas que antes en el caso normal) y un último intento puntual
   **sólo** si un producto no llegó a la caché.
3. `dry_run` no escribe en `app_wapi_envio_log`, no manda resumen y no encadena chunks: se puede
   repetir sin miedo. Tampoco en **reanudación** (con `resume_log_ids`): si `solo_disponibles` deja
   agotados fuera, el dry-run sólo los reporta en `filtrados_agotados`, no marca sus filas.
4. **Orden de despliegue**: da igual. `wapi-cron-dispatch` es tolerante a que la columna
   `solo_disponibles` aún no exista (reintenta el select sin ella, asume `false`, avisa en logs y
   la difusión se envía sin filtro de stock en vez de saltarse en silencio). Aun así, aplicar la
   migración **antes** evita el aviso y activa el filtro desde el primer envío.