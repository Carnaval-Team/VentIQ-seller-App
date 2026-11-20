# Hallazgos de las pruebas en newa que deben corregirse antes de pasar a main

Registro vivo, creado el 2026-11-20. Cada problema que aparezca probando en newa se anota aquí **en el momento**, con su arreglo y su efecto en main. Ninguna fase de `tasks/plan_promocion_main.md` se da por lista mientras haya filas con estado «pendiente».

Reglas:
- Todo script que se aplique en newa a causa de una prueba entra en `sql_updates/` y en esta tabla.
- La columna «Main» dice si el defecto existe allí hoy. Si existe, el arreglo viaja con la fase 1 del plan.
- Un defecto de cliente (app) se anota igual: la versión que se publique tiene que incluirlo.

| # | Fecha | Síntoma | Causa | Arreglo | Script / archivo | newa | Main |
|---|---|---|---|---|---|---|---|
| H1 | 2026-11-20 | Al abrir turno online: `violates foreign key constraint "app_dat_caja_turno_moneda_id_turno_fkey"` | `fn_apertura_turno_offline` devuelve en `id_turno` el id de la **operación** de apertura (lo que devuelve `registrar_apertura_turno_v3`), no el del turno. `_monedas` inserta con ese id en una tabla con FK al turno; `_usd` actualiza `app_dat_caja_turno` con el id equivocado; la alineación de fecha (R33) toca otro turno o ninguno | La rama de creación resuelve el turno por `id_operacion_apertura`, usa su id para alinear, guardar la idempotencia y responder, y añade `id_operacion`. El replay resuelve también claves antiguas (acotado a TPV y vendedor) | `sql_updates/fix_apertura_turno_offline_id_turno.sql` (prueba de contrato en `ventiq_admin_app/test/sync_newa_main_sql_contract_test.dart`) | Aplicado 2026-11-20. Probado con rollback: turno 18 / operación 123, filas CUP y USD en `app_dat_caja_turno_moneda`, USD en el turno, replay devuelve el mismo turno | **Existe** (cuerpo idéntico). No se nota porque ningún cliente publicado llama `_monedas`. En el sync offline un turno nuevo se guarda con el id de operación como si fuera el de turno: revisar si hay turnos ya afectados antes de la fase 1 |
| H2 | 2026-11-19 | `fn_listar_ordenes` emite la clave JSON `'tipo_paago'` | Errata en `m01_r29_listar_ordenes_v1_propuesta.sql` | Parche que reemplaza el literal en la definición viva; la propuesta ya está corregida | `sql_updates/fix_listar_ordenes_tipo_pago.sql` | **Pendiente de aplicar** (se verificó con rollback) | No existe: main ya emite `tipo_pago`. No pasar la función de newa sin el parche |
| H3 | 2026-11-20 | `session_refresh_service_test.dart` fallaba en el caso 429 | gotrue 2.26 emite `signedOut` con `signOutReason` ante un 429 en el refresh; el servicio lo trataba como cierre explícito | `_motivoSignOut` lee `SignOutReason`; `supabase_flutter ^2.16.0` | `ventiq_app/lib/services/session_refresh_service.dart`, `pubspec.yaml` | Corregido y probado | Cliente: incluir en la versión que se publique. Admin: mismo comportamiento posible, sin cambio (decisión pendiente) |
| H4 | 2026-11-20 | (revisión previa al pase) Clientes viejos hacen PATCH directo a `app_dat_trabajadores` | M01 R0b revoca `UPDATE` a `authenticated` en esa tabla | No es un defecto de newa: va a la fase de contrato | `tasks/plan_promocion_main.md` §2 y §4 | — | Bloquea R0b en la primera pasada |

## Ideas y dudas surgidas en pruebas (no son defectos confirmados)

| Fecha | Tema | Resultado |
|---|---|---|
| 2026-11-20 | La apertura de turno pide solo CUP y USD | El formulario ya genera un campo por moneda activa de la tienda (`TurnoService.divisasDeCaja`: `app_dat_tienda_moneda` → caché → respaldo CUP+USD). En newa las 6 tiendas tienen solo CUP y USD y el catálogo `monedas` solo CUP y USD, por eso no aparece otra. Pendiente decidir el respaldo y la persistencia de monedas extra (ver H5) |

## Riesgos abiertos para la apertura multimoneda

- **H5 (por confirmar).** `app_dat_caja_turno` solo tiene columnas para CUP y USD. Una tercera moneda se guarda únicamente en `app_dat_caja_turno_moneda` (lo hace `fn_apertura_turno_offline_monedas`). Si la RPC `_monedas` no existe, el cliente cae a `registrar_apertura_turno_usd` / `_v3` y **pierde** el desglose de las demás monedas sin aviso. Antes de pasar a main: decidir si ese respaldo debe avisar o bloquear cuando hay más de dos monedas.
- **H6 (por confirmar).** Si fallan la consulta de monedas de la tienda y la caché (offline con caché vacía), `divisasDeCaja` ofrece CUP + USD aunque la tienda acepte otras. Probar offline con caché fresca y con caché vacía antes de dar la apertura por lista.
