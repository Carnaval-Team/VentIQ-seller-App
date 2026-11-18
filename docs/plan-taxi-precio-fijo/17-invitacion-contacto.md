# 17 · Invitación de contacto de emergencia (sin gateway de WhatsApp)

> **Hito**: seguridad H2 · **Migración**: `inventtia_muevete/docs/migrations/050_sms_outbox.sql` (RPC ya aplicadas en PRUEBAS)
> **Edge Function**: `supabase/functions/contacto-invitacion/index.ts`
> **App**: `inventtia_muevete` (`seguridad_service.dart`, `contactos_emergencia_screen.dart`)
> **Depende de**: `16-sms-y-verificacion-contactos.md`

---

## 1. Por qué existe

El gateway de WhatsApp del bot (OpenWA) se cae, y con él el OTP de verificación de
contactos. Este flujo **no depende de ese gateway ni de la app del contacto**:

1. El usuario dueño de la cuenta abre **Contactos de emergencia → Verificar**.
2. Elige **"Compartir enlace de invitación"** (opción recomendada, primera).
3. La app llama a la RPC `muevete.fn_contacto_invitacion(<contacto_id>)` y recibe
   un `token` de 32 bytes en hex (64 caracteres) que **sólo se guarda hasheado**
   en `contactos_emergencia.token_hash`; expira a los **7 días**.
4. La app copia al portapapeles (no hay `share_plus` en el pubspec) el texto:
   `Te agregué como contacto de emergencia en Muévete. Abre este enlace para confirmar: <url>`
   y lo muestra en un diálogo con botón **"Copiar enlace"** para pegarlo en
   WhatsApp, Telegram o SMS.
5. El contacto abre el enlace **en el navegador del móvil** (sin cuenta, sin
   instalar nada). La Edge Function confirma server-side con la RPC pública
   `muevete.fn_confirmar_contacto_invitacion(p_token)`.
6. El contacto queda `estado='aceptado'`, `verificado=true`; el token se limpia.
   La app recarga la lista y lo muestra como **Verificado**.

El botón "Enviar código por WhatsApp" sigue disponible como segunda opción, con
la nota *"Requiere que el WhatsApp del bot esté conectado"*.

---

## 2. Endpoint

```
GET https://<REF>.supabase.co/functions/v1/contacto-invitacion?token=<64 hex>
```

- En la app la URL base está en `lib/config/supabase_config.dart`:
  `SupabaseConfig.contactoInvitacionUrlBase` (hoy apunta a PRUEBAS
  `qhprswhhfasrikhawjoz`; en producción se cambia al ref `vsieeihstlrdvpuooh`).
- Responde **HTML** (nunca JSON), mobile-first, en español, marca Muévete
  (naranja `#FE6B00`), CSS inline y **sin JavaScript ni recursos externos**.
- La función llama server-side a
  `POST {SUPABASE_URL}/rest/v1/rpc/fn_confirmar_contacto_invitacion` con
  `apikey`/`Authorization: Bearer <SUPABASE_ANON_KEY>` y body
  `{"p_token":"<token>"}`. Como el esquema no es el de PostgREST por defecto,
  envía `Content-Profile: muevete` (y `Accept-Profile: muevete`).
- El token **no se renderiza ni se loguea**; todo texto de la base se escapa.

### Estados de la página

| Situación | HTTP | Qué ve el contacto |
|---|---|---|
| `success=true, ya_confirmado=false` | 200 | "✅ Contacto confirmado": `<nombre>, te agregaron como contacto de emergencia en Muévete.` + número enmascarado (`aceptado_por`) |
| `success=true, ya_confirmado=true` | 200 | "Este contacto ya estaba confirmado" |
| `success=false, motivo=token_expirado` | 200 | "Este enlace venció": los enlaces duran 7 días; pide uno nuevo |
| `success=false, motivo=token_invalido` | 200 | "Enlace no válido": no existe, ya se usó o está incompleto |
| Falta `token` | 400 | "Enlace incompleto" |
| Token con formato basura | 400 | "Enlace no válido" (no se refleja el valor recibido) |
| RPC caída / `pepper_no_configurado` | 503 | "No pudimos confirmar el enlace" + botón "Abrir Muévete" |
| Método ≠ GET | 405 | Página de error + `Allow: GET` |

Headers: `Cache-Control: no-store`, `Referrer-Policy: no-referrer`,
`X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY` y CSP cerrada
(`default-src 'none'`, sin JS).

---

## 3. Desplegar (PRUEBAS)

```bash
# Desde la raíz del repo (donde vive supabase/functions/).
# --no-verify-jwt porque la abre un `anon` sin sesión desde el navegador: la
# función no confía en el llamante, sólo en la posesión del token (32 bytes,
# hash SHA-256 en BD, un solo uso, 7 días).
supabase functions deploy contacto-invitacion --no-verify-jwt \
  --project-ref qhprswhhfasrikhawjoz
```

**Variables de entorno**

| Nombre | Obligatoria | Uso |
|---|---|---|
| `SUPABASE_URL` | sí (automática) | Base de PostgREST. |
| `SUPABASE_ANON_KEY` | sí (automática) | Clave anónima; la RPC tiene `GRANT EXECUTE` a `anon`. |
| `MUEVETE_APP_URL` | no | Enlace del botón "Abrir Muévete" en la página de error. Si falta, el botón se pinta **sin enlace** (todavía no hay deep link ni ficha de tienda configurada). |

No hace falta ningún secreto propio ni `service_role`.

---

## 4. Probar a mano

Generar un enlace (SQL editor de PRUEBAS, **solo lectura/escritura del token del
contacto**, nunca producción): como `fn_contacto_invitacion` exige `auth.uid()`,
se simula el JWT del dueño dentro de la misma transacción:

```sql
begin;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', '<uuid_del_dueno>', 'role', 'authenticated')::text,
  true);
select muevete.fn_contacto_invitacion(<contacto_id>);
-- { success: true, token: "...", url: "/c/...", expira_at: "...", dias_vigencia: 7 }
rollback; -- el token se genera igual; si no quieres tocarlo, usa la app
```

Y abrir la página:

```bash
curl -i "https://qhprswhhfasrikhawjoz.supabase.co/functions/v1/contacto-invitacion?token=<token>"
```

Sin token debe devolver `400`; con `POST`, `405`; un token inventado, la página
"Enlace no válido". Ojo: **abrir el enlace confirma** el contacto (es un GET con
efecto, por diseño: el contacto sólo tiene que abrirlo).

---

## 5. Qué pasa si el token vence

- A los 7 días la RPC devuelve `motivo='token_expirado'` y la página muestra
  "Este enlace venció". No se puede reutilizar: el contacto debe pedir otro.
- El dueño vuelve a **Verificar → Compartir enlace de invitación** (o al botón
  secundario **"Compartir enlace"** de la tarjeta, visible mientras el contacto
  está `pendiente`). `fn_contacto_invitacion` **sobrescribe** `token_hash` y
  `token_expira_at`, así que el enlace viejo deja de servir y el nuevo dura
  otros 7 días.
- Si el contacto ya estaba `aceptado`/`verificado`, la RPC devuelve
  `ya_confirmado=true` sin token; la app sólo refresca la lista y avisa
  "Ese contacto ya estaba verificado".

---

## 6. Cabos sueltos

- `share_plus` no está en `pubspec.yaml`: se usa portapapeles + diálogo con
  "Copiar enlace". Si se agrega, sustituir `Clipboard.setData` por `Share.share`
  en `_compartirEnlace` (la lógica de la RPC no cambia).
- `MUEVETE_APP_URL` queda sin configurar: no hay deep link (`muevete://`) ni
  ficha de Play Store/App Store en el proyecto. El botón "Abrir Muévete" se
  muestra deshabilitado hasta definirlo.
- `contactoInvitacionUrlBase` está fija a PRUEBAS. Al desplegar en producción
  hay que cambiar el ref en `supabase_config.dart` (o derivarla de
  `SupabaseConfig.supabaseUrl` si se quiere que siga a `kReleaseMode`).
- El esquema `muevete` debe seguir expuesto en PostgREST; si no, la RPC
  responde `PGRST106` y la página cae en el estado 503.
- El pepper de tokens (`seguridad_token_pepper` en Vault) debe existir en el
  proyecto; si falta, `fn_confirmar_contacto_invitacion` falla y se ve la página
  de error temporal (503), no un falso "confirmado".