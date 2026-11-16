# 16 · SMS y verificación de contactos de emergencia

> **Hito**: seguridad H2 · **Migración**: `inventtia_muevete/docs/migrations/050_sms_outbox.sql`
> **Edge Function**: `supabase/functions/send-sms/` (worker del outbox, no desplegada aún)
> **Depende de**: `037_taxi_seguridad.sql` (`contactos_emergencia`, `fn_token_hash`).

---

## 1. Realidad de Cuba (decidir con esto, no con marketing)

| Hecho | Consecuencia |
|---|---|
| **Supabase no tiene servicio de SMS propio.** | Hace falta un proveedor externo + una Edge Function que lo llame. |
| **Twilio no entrega SMS a +53** (Cuba está en su lista de países no soportados para SMS). | Descartado para el arranque. El adapter de `send-sms` queda listo para otros países, no para Cuba. |
| **ClickSend sí soporta Cuba, pero es one-way** y requiere **Alpha Tag** (remitente alfanumérico) con registro/aprobación de ~30 días hábiles; tiene coste por segmento y por Alpha Tag. | Es el candidato cuando exista cuenta y Alpha Tag aprobado. Los SMS llegan; **no se pueden recibir respuestas**. |
| Los "trial gratis con Cuba" (paneles tipo "prueba 10 SMS") **no son fiables**: bloquean +53, entregan con días de retraso o desaparecen. | No diseñar el flujo crítico asumiendo SMS gratis. |
| Sin datos en el teléfono, el SMS y la llamada son el único canal. | El modo sin SMS (WhatsApp/Telegram) cubre el caso normal; el SMS cubre el "sin datos". |

**Regla**: el SMS es **opcional**. Ningún flujo de seguridad puede quedar bloqueado porque el proveedor no esté configurado (`configuracion_sms.proveedor = 'mock'` es el default).

---

## 2. Modo sin SMS (recomendado para arrancar) — gratis y funciona en Cuba

El usuario **comparte un enlace por WhatsApp/Telegram**; el contacto lo abre en una **página web pública** y confirma. No hace falta que instale la app ni que exista proveedor de SMS.

### Flujo

1. La app crea/edita el contacto en `muevete.contactos_emergencia` (estado `pendiente`).
2. La app llama:
   ```sql
   select muevete.fn_contacto_invitacion(<contacto_id>);
   -- { success, token, url: "/c/<token>", expira_at, dias_vigencia: 7 }
   ```
   El token son **32 bytes aleatorios en hex (64 caracteres)**. En BD sólo se guarda `sha256(token || pepper)` en `token_hash`; expira a los **7 días**.
3. La app arma el texto y abre WhatsApp:
   ```
   https://wa.me/5355550003?text=Hola%2C%20acepta%20ser%20mi%20contacto%20de%20emergencia%20en%20Mu%C3%A9vete%3A%20https%3A%2F%2Fmuevete.app%2Fc%2F%3Ctoken%3E
   ```
   (Si el operador configura `ALTER DATABASE postgres SET muevete.url_publica = 'https://muevete.app';`, la RPC ya devuelve la `url` absoluta.)
4. La **página pública `/c/<token>`** (HTML estático + `supabase-js` con la clave pública) llama **sin sesión**:
   ```js
   const { data } = await supabase.schema('muevete')
     .rpc('fn_confirmar_contacto_invitacion', { p_token: token });
   // { success: true, ya_confirmado: false, contacto_nombre: "...", aceptado_por: "••••0003" }
   ```
   - `success:false, motivo:'token_invalido' | 'token_expirado'` → mostrar "Enlace vencido, pide uno nuevo".
   - Al confirmar: `estado='aceptado'`, `verificado=true`, `aceptado_at=now()`, y se limpian `token_hash`/`token_expira_at` (no se puede reutilizar).
5. La app ve el contacto como aceptado (`estado='aceptado'`, `verificado=true`) y ya puede usarlo en `fn_gate_seguridad`.

### Ventajas / límites

- **Gratis, sin proveedor, sin Alpha Tag, funciona con WhatsApp cubano.**
- El enlace es de **un solo uso** (se limpia al confirmar) y caduca a los 7 días.
- No verifica que el teléfono sea real: verifica que **alguien con acceso a ese WhatsApp** aceptó. Es el mismo nivel de confianza que un SMS one-way (que tampoco prueba que el número exista).
- Requiere publicar la página `/c/<token>` (un HTML estático en cualquier hosting, o una Edge Function `contacto-invitacion` que sirva el HTML).

---

## 3. Modo SMS (cuando haya cuenta de proveedor)

La base ya está lista: outbox `muevete.sms_mensajes` + Edge Function `send-sms`.

### 3.1 Secretos (Supabase → Edge Functions → Secrets)

| Nombre | Obligatorio | Uso |
|---|---|---|
| `SMS_CRON_SECRET` | sí (para el cron) | Header `x-sms-secret`. Sin él sólo se puede invocar con `Authorization: Bearer <service_role>`. |
| `CLICKSEND_USERNAME` | con ClickSend | Basic Auth de la API. |
| `CLICKSEND_API_KEY` | con ClickSend | Basic Auth de la API. |
| `TWILIO_ACCOUNT_SID` / `TWILIO_AUTH_TOKEN` / `TWILIO_FROM` | sólo otros países | Twilio **no sirve para Cuba**. |

`SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` los inyecta Supabase automáticamente.

> **Requisito de plataforma**: el esquema `muevete` debe estar expuesto en
> PostgREST (ya lo está: la app lo usa con `supabase.schema('muevete')`). Si en
> algún proyecto no lo estuviera, la función devolvería `config_sms` /
> `cola_no_disponible` (500) porque no puede leer la config ni la RPC.

### 3.2 Desplegar

```bash
# --no-verify-jwt es necesario: el cron manda x-sms-secret, no un JWT.
# La función valida su propio secreto (o el Bearer de service_role) y si no,
# responde 401, así que desactivar verify_jwt no deja el endpoint abierto.
supabase functions deploy send-sms --no-verify-jwt --project-ref <PROYECTO_DE_PRUEBAS>
supabase secrets set SMS_CRON_SECRET=<aleatorio-largo> \
  CLICKSEND_USERNAME=<usuario> CLICKSEND_API_KEY=<key> \
  --project-ref <PROYECTO_DE_PRUEBAS>
```

> Alternativa sin `--no-verify-jwt`: que el cron envíe
> `Authorization: Bearer <service_role>` (el secreto guardado en Vault) en vez
> de `x-sms-secret`. Las dos vías están soportadas por la función.

Prueba manual (con el secreto):

```bash
curl -i -X POST "https://<ref>.supabase.co/functions/v1/send-sms" \
  -H "x-sms-secret: $SMS_CRON_SECRET" -H "Content-Type: application/json" -d '{}'
# { ok:true, procesados:N, enviados:N, errores:0, simulado:false, proveedor:"clicksend", detalle:[...] }
```

### 3.3 Programar el worker (cada minuto)

**Opción A — Supabase Dashboard → Integrations → Cron** (o `pg_cron` + `pg_net`): job cada `* * * * *` que haga `net.http_post` a la URL anterior con el header `x-sms-secret` leído de Vault (`select decrypted_secret from vault.decrypted_secrets where name='sms_cron_secret'`).

**Opción B — SQL** (requiere `pg_cron` y `pg_net`; el secreto se guarda en Vault, no en el SQL):

```sql
select cron.schedule('send-sms-worker', '* * * * *', $$
  select net.http_post(
    url := 'https://<ref>.supabase.co/functions/v1/send-sms',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sms-secret', (select decrypted_secret from vault.decrypted_secrets
                        where name = 'sms_cron_secret')),
    body := '{}'::jsonb);
$$);
```

La función toma **hasta 25 pendientes por invocación** y deja el resto para el siguiente minuto. No hace falta desplegar nada más: el backoff (5/10/15 min) y el corte por `max_intentos` los aplica `muevete.fn_sms_marcar`.

### 3.4 Cambiar de proveedor

```sql
-- Modo sin SMS (default, no envía nada):
update muevete.configuracion_sms
   set proveedor = 'mock', remitente = null where id = 1;

-- ClickSend (Cuba). remitente = Alpha Tag aprobado:
update muevete.configuracion_sms
   set proveedor = 'clicksend', remitente = 'MUEVETE' where id = 1;

-- Apagar el worker sin borrar la config:
update muevete.configuracion_sms set activo = false where id = 1;
```

Con `proveedor='mock'` el worker **no llama a nadie**: marca cada SMS como `enviado` con `proveedor_msg_id='mock-<id>'` y responde `simulado:true`. Sirve para probar el flujo completo en PRUEBAS.

---

## 4. Reutilización desde otras apps/procesos

Cualquier app del ecosistema encola con **una sola llamada**; el worker se encarga del resto:

```sql
select muevete.fn_sms_encolar(
  '+5355550001',              -- destinatario E.164 (obligatorio)
  'Tu pedido está listo.',    -- texto (1..480 caracteres)
  'aviso',                    -- otp | contacto_emergencia | panico | aviso | otro
  'ventiq_app',               -- app que encola (default 'muevete')
  'pedidos',                  -- ref_tabla opcional
  '123'                       -- ref_id opcional
);
-- { success: true, id: 42, estado: "pendiente" }
```

- **Rate limit**: máximo **5 SMS al mismo destinatario en 10 minutos**; el 6.º lanza `P0065 sms_rate_limit`.
- Estados: `pendiente → enviado | error` (con reintentos) y `entregado`/`cancelado` si un webhook futuro los marca.
- La tabla `muevete.sms_mensajes` es genérica (`app`, `tipo`, `ref_tabla`, `ref_id`): no hay que crear una tabla por caso de uso.
- El OTP de contactos de emergencia se encola solo: `fn_iniciar_validacion_contacto()` ya crea el código, guarda el hash y encola el SMS (`tipo='contacto_emergencia'`, `ref_tabla='contactos_emergencia'`, `ref_id=<contacto_id>`) devolviendo `sms_id` y `sms_estado`.

---

## 5. Costos y seguridad

- **Costos**: ClickSend cobra por SMS y por segmento (el texto de OTP son ~2 segmentos: acentos + longitud), más el alta del Alpha Tag (~30 días hábiles). Un SMS por validación de contacto y por pánico es barato; un bucle de reintentos no lo es → el rate limit y `max_intentos=3` existen por eso.
- **OTP fuera de logs**: `send-sms` sólo registra `id`, `tipo` y destinatario enmascarado (`+53••••001`). El código de 4 dígitos nunca se loguea ni se devuelve al cliente fuera de `muevete.entorno='dev'`.
- **El outbox guarda el texto en claro** (el proveedor necesita el OTP). Por eso `muevete.sms_mensajes` está con RLS: sólo `service_role` escribe/lee (el superadmin puede auditar por política). No exponer la tabla a las apps: usan `fn_sms_encolar`.
- **Tokens hasheados**: invitaciones y enlaces de viaje se guardan como `sha256(token || pepper)`; el pepper vive en Vault (`seguridad_token_pepper`). Sin pepper la RPC falla (`pepper_no_configurado`), no hay fallback en producción.
- **El modo `mock` no verifica teléfonos ajenos**: sólo simula el envío. En producción, un contacto con `verificado=true` por mock no prueba nada; para validar números reales hay que usar un proveedor real o el flujo de invitación (que confirma una persona, no un número).
- **Retención**: pendiente definir purga periódica del outbox (p. ej. borrar `enviado/error` con más de 30 días). Mientras tanto, el texto con OTP queda en la tabla: no volcarla a logs ni a soporte.