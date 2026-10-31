-- ============================================================================
-- MIGRACION 65: permisos de `service_role` sobre el schema `flow`
--
-- QUE ARREGLA
--   La Edge Function `flow-tasas` corre con `service_role` y lee
--   `flow.tasa_cambio` con `client.schema('flow')`. En release, el schema `flow`
--   solo tenia USAGE para `anon` y `authenticated`:
--
--       flow_acl = {postgres=UC/postgres, anon=U/postgres, authenticated=U/postgres}
--
--   Con el permiso sobre la TABLA pero sin USAGE en el SCHEMA, PostgREST
--   responde «permission denied for schema flow» y la funcion devuelve
--   `{ok:false,"error":"No se pudo leer la cache: permission denied for schema flow"}`.
--
-- QUE HACE
--   1. `grant usage on schema flow to service_role`.
--   2. Refuerza el SELECT de `service_role` sobre las tablas que leen las
--      funciones de servidor (idempotente: solo concede lo que falta).
--
-- QUIEN LO NECESITA
--   * release (`vsieeihstajlrdvpuooh`): SI, es el que estaba incompleto.
--   * debug (`qhprswhhfasrikhawjoz`): ya tenia USAGE; la migracion es un no-op.
--
-- REVERSION
--   revoke usage on schema flow from service_role;
--
-- IDEMPOTENTE.
-- ============================================================================

grant usage on schema flow to service_role;

-- El service_role es el rol de servidor: puede saltarse la RLS, pero necesita
-- los privilegios de tabla. Se repiten los de las migraciones 60-64 por si
-- alguna se aplico por separado.
grant select on flow.tasa_cambio,
                flow.tasa_cambio_sondeo,
                flow.precio_config,
                flow.cobro_config,
                flow.reserva_pago
  to service_role;

grant insert, update, delete on flow.tasa_cambio,
                                flow.tasa_cambio_sondeo,
                                flow.precio_config,
                                flow.cobro_config,
                                flow.reserva_pago
  to service_role;

notify pgrst, 'reload schema';

-- ══ VERIFICACION ══════════════════════════════════════════════════════════
--
-- select has_schema_privilege('service_role', 'flow', 'USAGE');          -- true
-- select has_table_privilege('service_role', 'flow.tasa_cambio', 'SELECT'); -- true
-- select nspacl::text from pg_namespace where nspname = 'flow';
--   -- debe incluir service_role=U/postgres
--
-- Prueba real de la funcion (desde el cliente o el dashboard):
--   POST /functions/v1/flow-tasas   ->  {"ok":true, ...}
--   Antes devolvia 500 con "permission denied for schema flow".