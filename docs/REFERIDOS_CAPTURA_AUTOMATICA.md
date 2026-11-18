# Captura automática de invitaciones (referidos) sin tocar la app

Fecha: 2026-11-12 · Proyecto Supabase: `vsieeihstajlrdvpuooh`
Migración: [`supabase/migrations/20261112150000_referral_capture_auto_attribution.sql`](../supabase/migrations/20261112150000_referral_capture_auto_attribution.sql)
Rollback: [`supabase/rollback/20261112150000_referral_capture_rollback.sql`](../supabase/rollback/20261112150000_referral_capture_rollback.sql)

## 1. Problema

`ventiq_landing/r.html` copia el código de invitación al portapapeles con el
formato `CARNAVAL-REF:<CODIGO>` y la app lo lee al primer arranque. La copia
falla o se pierde en casos reales:

* navegador in-app de WhatsApp/Instagram que bloquea la escritura del portapapeles;
* iOS Safari, donde la copia exige gesto de usuario y a veces no se completa;
* el usuario copia otra cosa (un enlace, un código OTP) entre instalar y abrir la app.

Si eso pasa, el referido se pierde y nadie cobra la invitación.

## 2. Idea

No se puede leer un identificador del teléfono desde la web (no existe API y
sería invasivo). Lo que sí se puede es **reconocer la visita desde el servidor**
cuando la app crea la cuenta, porque ese alta también es una petición HTTP y
PostgREST expone la IP del cliente dentro de la transacción
(`current_setting('request.headers')`).

Flujo:

```
r.html  ──(código + token único + UA)──►  Supabase: referral_visits
   │                                        (hash de IP, TTL 120 min)
   │
   ├─ portapapeles: CARNAVAL-REF:<CODIGO>  ──►  app (camino normal, sigue igual)
   │
   └─ enlace Play con &referrer=ref=<CODIGO>&v=<TOKEN>   (preparado a futuro)

app crea Usuarios ──► trigger trg_usuarios_aplicar_visita
                         ├─ ¿el INSERT ya traía referal_from?  → no toca nada
                         ├─ ¿hay UNA visita con el mismo teléfono? → aplica (phone_trigger)
                         ├─ ¿hay UNA visita con la misma IP móvil en la ventana? → aplica (ip_trigger)
                         └─ si hay 0 o 2+ candidatas → no aplica (nunca adivina)
```

Después, si la app aplica el código real del portapapeles y difiere del
heurístico, **gana el de la app** (`fn_usuario_apply_referral` reemplaza y marca
`source = 'app'`). El portapapeles sigue siendo la fuente de verdad; la tabla es
solo el respaldo.

## 3. Qué cambia y qué no

| Pieza | Cambio |
| --- | --- |
| App Carnaval | **Ninguno.** No lee nada nuevo, no hay que publicar versión. |
| Landing `r.html` | Genera un token de visita (UUID v4, 24 h en `localStorage`), lo registra con una RPC y añade `&referrer=` al enlace de Play. Si la RPC no existe, falla en silencio. |
| `tracking.js` | Expone `VentiqTracking.getClient()` para reutilizar la config de Supabase. |
| Base de datos | 3 tablas nuevas, 6 funciones y 1 trigger. Nada existente se modifica salvo `fn_usuario_apply_referral` (solo una rama nueva). |

El **contrato del portapapeles no cambia**: sigue siendo exactamente
`CARNAVAL-REF:` + código.

## 4. Cómo aplicar (cuando se decida)

1. Ejecutar la migración en el SQL Editor de Supabase o con `supabase db push`.
2. Verificar:

```sql
-- debe existir y valer true
select exists (select 1 from public.referral_capture_config) as config_ok;

-- anon NO debe poder leer las tablas (3 filas con false)
select 'visits' t, has_table_privilege('anon','public.referral_visits','SELECT') anon_can_read
union all select 'attribs', has_table_privilege('anon','public.referral_user_attributions','SELECT')
union all select 'config',  has_table_privilege('anon','public.referral_capture_config','SELECT');
```

3. Prueba de humo (en una transacción, sin persistir):

```sql
begin;
select set_config('request.headers','{"x-forwarded-for":"203.0.113.77"}',true);
-- usa un código real de carnavalapp."Usuarios"
select public.fn_referral_visit_register(
  (select referal_code from carnavalapp."Usuarios"
    where nullif(btrim(coalesce(referal_code,'')),'') is not null limit 1),
  gen_random_uuid()::text, 'Android', 'UA-prueba');
insert into carnavalapp."Usuarios"(email, rol, uuid, created_at)
values ('prueba@example.com','cliente', gen_random_uuid(), now());
select referal_from from carnavalapp."Usuarios" where email='prueba@example.com';
rollback;
```

La última consulta debe devolver el código de invitación.

4. Desplegar la landing con los cambios de `r.html` y `tracking.js`. Mientras la
   migración no esté aplicada, la llamada a la RPC devuelve 404 y la página sigue
   funcionando igual (sin respaldo).

## 5. Configuración

Todo se ajusta en `public.referral_capture_config` (una fila):

| Columna | Por defecto | Para qué |
| --- | --- | --- |
| `ttl_minutes` | 120 | Vida de una visita pendiente (tiempo máximo entre abrir el enlace y registrarse). |
| `ip_window_minutes` | 45 | Ventana de coincidencia por IP. |
| `ip_match_enabled` | true | Apagar la heurística por IP si molesta. |
| `phone_match_enabled` | true | Apagar el emparejamiento por teléfono. |
| `max_registrations_per_token` | 5 | Refrescos permitidos del mismo token. |
| `retention_days` | 30 | Retención antes de purgar. |

La columna `salt` se genera aleatoriamente al aplicar la migración y **no debe
copiarse al repo ni rotarse sin volver a hashear**: es lo que hace irreversible
el hash de IP/teléfono.

Purga manual: `select public.fn_referral_visits_purge();`
Purga automática opcional (pg_cron está disponible):

```sql
select cron.schedule('referral-visits-purge', '17 4 * * *',
                     $$select public.fn_referral_visits_purge();$$);
```

## 6. Límites y riesgos (importante)

* **No existe un ID de teléfono en la web.** El token de visita identifica la
  *visita*, no el dispositivo ni a la persona.
* **CGNAT.** En redes móviles muchos usuarios comparten IP pública. Por eso la
  coincidencia exige **una sola visita pendiente** desde esa IP en la ventana y
  que la visita venga de un navegador móvil. Si hay dos invitados detrás de la
  misma IP, no se atribuye a ninguno: se prefiere no atribuir antes que atribuir
  mal (una atribución errónea paga comisión a quien no corresponde).
* **iOS** no tiene Install Referrer; ahí el respaldo real es el portapapeles,
  la heurística por IP o el teléfono (si algún día la landing lo pide).
* **El teléfono ya está soportado por la BD** (`fn_referral_visit_attach_phone`),
  pero la landing todavía no muestra ese campo. Añadirlo aumenta mucho la
  precisión; es una decisión de producto (fricción vs. efectividad).
* **El código debe existir.** La RPC rechaza códigos inexistentes, así que el
  trigger nunca asigna un invitador inválido.
* **Si el usuario ya tenía referidor, no se cambia** (regla existente). La única
  excepción es el reemplazo de una atribución heurística por el código real de
  la app.
* **Altas sin pasar por PostgREST** (por ejemplo un `INSERT` hecho desde el SQL
  Editor o una migración) no tienen IP: no se atribuyen y no rompen nada.

## 7. Privacidad

* Se guarda `sha256(sal || ip)` y, opcionalmente, `sha256(sal || últimos 8
  dígitos del teléfono)`. Nunca IP ni teléfono en claro.
* No se guardan cookies, IDFA/GAID ni datos personales del invitado.
* Retención 30 días por defecto.
* Si se quiere ser exhaustivo con Google Play, conviene declarar en *Seguridad
  de los datos* la atribución de invitaciones (no cambia lo que la app recolecta;
  sí lo que la web registra). Ver `ventiq_landing/privacy.html` y
  `ventiq_landing/data-safety.html`.

## 8. Camino determinista (si algún día se toca la app)

Un cambio de ~20 líneas en la app elimina la heurística: leer el **Play Install
Referrer** en el primer arranque (`referrer` ya viene en el enlace con
`ref=...&v=<token>`) y llamar a una RPC de reclamo por `visit_token`. El resto
del diseño (tabla, TTL, atribución, prioridad del portapapeles) ya está listo
para ese día; solo faltaría exponer una RPC `fn_referral_visit_claim(token,
install_id)` y el código en la app.

## 9. Hallazgo colateral

`ventiq_landing/assets/js/tracking.js` llama a la RPC
`public.fn_track_landing_event`, que **no existe** en la base (no hay ninguna
función de tracking/landing en `public` ni en `carnavalapp`). El tracking de la
landing lleva tiempo fallando en silencio: solo se ve un `console.error` en el
navegador. Si se quiere medir conversión de la landing hay que crear esa RPC (o
reapuntar `track()` a `carnavalapp.analytics_events`). No se toca en esta
migración para no mezclar alcances.