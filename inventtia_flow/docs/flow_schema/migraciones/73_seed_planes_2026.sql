-- ════════════════════════════════════════════════════════════════════════════
-- MIGRACION 73: SEMILLA DE PLANES 2026 (starter / plus / professional / enterprise)
-- ════════════════════════════════════════════════════════════════════════════
--
-- QUE HACE
--   1. Crea (si no existen) los cuatro planes comerciales nuevos, con sus
--      límites en el jsonb `limites` y su modalidad:
--
--      | codigo       | nombre      | dias | precio | moneda | limites                                                        | etiqueta      | orden |
--      |--------------|-------------|------|--------|--------|----------------------------------------------------------------|---------------|-------|
--      | starter      | Inicio      | 30   | 20     | USD    | entidades 1, locales 2, servicios_por_local 5, usuarios 3      | NULL          | 10    |
--      | plus         | Plus        | 30   | 30     | USD    | entidades 1, locales 3, servicios_por_local 10, usuarios 8     | 'Más popular' | 20    |
--      | professional | Profesional | 30   | 50     | USD    | entidades 2, locales 5, servicios_por_local 10, usuarios 15    | NULL          | 30    |
--      | enterprise   | Empresarial | 30   | 0      | USD    | {} (sin límites)                                               | NULL          | 40    |
--
--      `enterprise` va con `modalidad = 'contacto'`: en la app y en el panel se
--      muestra como "Contactar con ventas" (WhatsApp de soporte) y NO genera
--      intent de pago. Los otros tres son de pago (`modalidad = 'pago'`).
--
--   2. Desactiva los planes de prueba de 1/2/3 CUP (`flow_mensual`,
--      `flow_trimestral`, `flow_anual`): dejan de aparecer en la vitrina y ya no
--      se pueden comprar. OJO: NO se borran y NO se tocan las suscripciones ya
--      acreditadas — esas conservan su `id_plan`, sus días y su libro de
--      movimientos; simplemente su plan ya no se ofrece. Si alguna entidad los
--      tiene, `entidad_limites` seguirá devolviendo sus límites ({} = sin
--      límites), como cualquier plan.
--
-- POR QUE `on conflict (codigo) do nothing`
--   `codigo` es UNIQUE global. Si el superadmin ya creó/editió un plan con ese
--   código, esta semilla NO lo pisa: la migración sólo siembra lo que falta.
--   Así se puede reejecutar sin miedo y el panel manda después.
--
-- POR QUE `'{}'` EN enterprise
--   `limites = {}` = SIN límites (el contrato de la 72: número > 0 = límite).
--   Es lo correcto para el plan a medida: el detalle lo cierra ventas.
--
-- DEPENDE DE: 72_planes_limites_privados.sql (columnas modalidad/etiqueta y el
--             contrato de `limites`). Si la 72 no está aplicada, este archivo
--             falla a propósito con un mensaje claro.
-- NO APLICAR AUTOMÁTICAMENTE: el usuario pega el SQL en el editor.
--
-- REVERSIBILIDAD: ver bloque comentado al final (borrar/desactivar los cuatro
-- planes; reactivar los de prueba sólo si se quiere volver atrás).
-- ════════════════════════════════════════════════════════════════════════════

-- ── 0. Comprobación previa: la 72 tiene que estar aplicada ──────────────────
do $pre$
begin
  if to_regclass('flow.suscripcion_plan') is null then
    raise exception 'Falta flow.suscripcion_plan (migraciones 43-46).';
  end if;

  if not exists (select 1 from information_schema.columns
                  where table_schema = 'flow' and table_name = 'suscripcion_plan'
                    and column_name = 'modalidad') then
    raise exception 'Falta flow.suscripcion_plan.modalidad: aplica primero 72_planes_limites_privados.sql.';
  end if;

  if not exists (select 1 from information_schema.columns
                  where table_schema = 'flow' and table_name = 'suscripcion_plan'
                    and column_name = 'etiqueta') then
    raise exception 'Falta flow.suscripcion_plan.etiqueta: aplica primero 72_planes_limites_privados.sql.';
  end if;

  if not exists (select 1 from information_schema.columns
                  where table_schema = 'flow' and table_name = 'suscripcion_plan'
                    and column_name = 'id_entidad') then
    raise exception 'Falta flow.suscripcion_plan.id_entidad: aplica primero 72_planes_limites_privados.sql.';
  end if;
end
$pre$;

-- ══ 1. LOS CUATRO PLANES 2026 ═══════════════════════════════════════════════
--
-- `activo = true`: son los planes que se ofrecen en "Mi suscripción".
-- `id_entidad` se queda NULL (planes públicos); los privados los crea el
-- superadmin desde el panel.
-- `servicios_catalogo` no se siembra: ausente = sin límite de catálogo. Se deja
-- así a propósito para no sorprender a los negocios que ya tienen su catálogo
-- montado; el superadmin puede añadirlo por plan cuando quiera.
insert into flow.suscripcion_plan
  (codigo, nombre, descripcion, duracion_dias, precio, moneda, limites,
   orden, activo, modalidad, id_entidad, etiqueta)
values
  ('starter', 'Inicio',
   'Para empezar: 1 entidad, 2 locales, 5 servicios por local y hasta 3 usuarios.',
   30, 20, 'USD',
   '{"entidades":1,"locales":2,"servicios_por_local":5,"usuarios":3}'::jsonb,
   10, true, 'pago', null, null),

  ('plus', 'Plus',
   'Para negocios que crecen: 1 entidad, 3 locales, 10 servicios por local y hasta 8 usuarios.',
   30, 30, 'USD',
   '{"entidades":1,"locales":3,"servicios_por_local":10,"usuarios":8}'::jsonb,
   20, true, 'pago', null, 'Más popular'),

  ('professional', 'Profesional',
   'Para varias entidades: 2 entidades, 5 locales, 10 servicios por local y hasta 15 usuarios.',
   30, 50, 'USD',
   '{"entidades":2,"locales":5,"servicios_por_local":10,"usuarios":15}'::jsonb,
   30, true, 'pago', null, null),

  ('enterprise', 'Empresarial',
   'Plan a medida: contacta con ventas para definir entidades, locales y usuarios.',
   30, 0, 'USD',
   '{}'::jsonb,
   40, true, 'contacto', null, null)
on conflict (codigo) do nothing;

-- ══ 2. RETIRAR LOS PLANES DE PRUEBA DE 1/2/3 CUP ══════════════════════════
--
-- Se DESACTIVAN (no se borran):
--   · dejan de aparecer en `cliente_planes_suscripcion` (filtra por activo) y
--     `cliente_crear_intent_suscripcion` rechaza planes inactivos;
--   · las suscripciones ya acreditadas NO se tocan: conservan sus días, su
--     `id_plan` y su historial en `flow.suscripcion_movimiento`;
--   · `admin_planes_listar` los sigue mostrando (inactivos) para que el
--     superadmin pueda reactivarlos si hiciera falta.
update flow.suscripcion_plan
   set activo = false
 where codigo in ('flow_mensual','flow_trimestral','flow_anual')
   and activo;

notify pgrst, 'reload schema';

-- ════════════════════════════════════════════════════════════════════════════
-- 3. VERIFICACIÓN (comentada: ejecutar a mano DESPUÉS de aplicar)
-- ════════════════════════════════════════════════════════════════════════════
--
-- 3.1 Los cuatro planes nuevos están y con los límites correctos
--     (esperado: 4 filas; enterprise con modalidad 'contacto' y limites {}).
-- select codigo, nombre, duracion_dias, precio, moneda, limites, modalidad,
--        etiqueta, orden, activo
--   from flow.suscripcion_plan
--  where codigo in ('starter','plus','professional','enterprise')
--  order by orden;
--
-- 3.2 Los planes de prueba quedaron inactivos (esperado: 0 filas activas).
-- select codigo, activo from flow.suscripcion_plan
--  where codigo in ('flow_mensual','flow_trimestral','flow_anual') and activo;
--
-- 3.3 Sin sesión (anon) la vitrina devuelve SOLO los 4 planes públicos y activos
--     (y `enterprise` con contacto_whatsapp relleno).
-- select jsonb_pretty(flow.cliente_planes_suscripcion());
--
-- 3.4 Ninguna suscripción acreditada se perdió (mismo total que antes de la 73).
-- select count(*) from flow.suscripcion;
--
-- 3.5 Reejecutar la migración no duplica ni cambia nada: el conteo de los
--     cuatro códigos sigue siendo 4 y `updated_at` no cambia.
-- select count(*) from flow.suscripcion_plan
--  where codigo in ('starter','plus','professional','enterprise');   -- 4
--
-- ════════════════════════════════════════════════════════════════════════════
-- 4. REVERSIÓN (comentada: NO ejecutar salvo que haya que deshacer)
-- ════════════════════════════════════════════════════════════════════════════
--
-- -- 4.1 Los cuatro planes nuevos: si nadie los usa se pueden borrar; si ya hay
-- --     suscripciones/intents apuntándoles, la FK lo impide (on delete restrict)
-- --     y lo correcto es desactivarlos, no romper el historial.
-- delete from flow.suscripcion_plan
--  where codigo in ('starter','plus','professional','enterprise')
--    and id not in (
--      select id_plan from flow.suscripcion where id_plan is not null
--      union
--      select id_plan from flow.suscripcion_intent
--    );
--
-- -- 4.2 Si no se pudieron borrar, al menos sacarlos de la vitrina.
-- update flow.suscripcion_plan
--    set activo = false
--  where codigo in ('starter','plus','professional','enterprise');
--
-- -- 4.3 Reactivar los planes de prueba (sólo si se quiere volver al estado
-- --     anterior de la vitrina).
-- update flow.suscripcion_plan
--    set activo = true
--  where codigo in ('flow_mensual','flow_trimestral','flow_anual');
--
-- notify pgrst, 'reload schema';
-- ════════════════════════════════════════════════════════════════════════════