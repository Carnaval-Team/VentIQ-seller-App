-- ============================================================================
-- SCRIPT DE DATOS (NO es una migracion): cerrar los pagos vivos que quedaron
-- sobre reservas ya canceladas
--
--   UN SOLO USO. NO va en `_APLICAR_RELEASE_68.sql`: no cambia el esquema, es la
--   reparacion puntual del estado que dejo el P0 antes de que existiera el
--   trigger que lo cierra solo.
--
-- EVIDENCIA (base de release, 2026-10-29)
--   reserva_pago.id = 7   -> estado 'creado'
--   agenda.id      = 302  -> id_estado = 2 ('Cancelado'), pago_estado = 'pendiente'
--
--   Es el UNICO intento vivo sobre una reserva cancelada. El resto de intentos
--   con reserva cancelada ya estan cerrados:
--     id 1, 2 y 3 -> 'rechazado'  (no se tocan)
--     id 4 y 5    -> 'expirado'   (no se tocan)
--     id 6        -> 'verificado' (NO se toca: el dinero si se verifico; si hay
--                                  reembolso es una decision del negocio, no un
--                                  dato roto)
--
-- QUE HACE
--   1. DIAGNOSTICO (select): intentos vivos ('creado'/'reportado') cuya reserva
--      esta 'Cancelado'. Debe salir SOLO reserva_pago.id = 7.
--   2. Los pasa a 'anulado' — el mismo criterio que el trigger de la 68.
--   3. Alinea `agenda.pago_estado` de esas reservas: 'pendiente'/'reportado' ->
--      'expirado'. Es el mismo mapeo del trigger: 'anulado' no esta permitido
--      por `agenda_pago_estado_chk` y 'expirado' es el unico valor que significa
--      "cerrado sin verificar" (ver DECISIONES de la migracion 68).
--   4. COMPROBACION dentro de la misma transaccion: 0 intentos vivos sobre
--      canceladas, 0 chips vivos, y el estado final de la agenda 302.
--
-- POR QUE AHORA Y EN QUE ORDEN
--   Aplicar PRIMERO la migracion 68 (o `_APLICAR_RELEASE_68.sql`) para que el
--   trigger impida que esto vuelva a pasar; despues este script. El script en si
--   no depende de la 68, pero aplicado antes solo tapa el sintoma.
--
-- COMO EJECUTARLO
--   * psql (recomendado):
--       psql "$DATABASE_URL" -f fix_datos_pagos_reserva_canceladas.sql
--     Las lineas que empiezan por `\echo` son meta-comandos de psql.
--   * SQL Editor de Supabase: NO entiende `\echo`. Borrar esas lineas antes de
--     pegar, o pegar solo el bloque comprendido entre `begin;` y `commit;`.
--
-- SEGURIDAD
--   * Todo va dentro de UNA transaccion: si el paso 4 no da 0 y 0, `rollback;`
--     en vez de `commit;`.
--   * Si el paso 1 devuelve ids DISTINTOS de 7, PARAR y revisarlos antes de
--     seguir: puede haber otro caso de negocio que no sea este P0.
--   * No borra nada ni toca importes: solo `reserva_pago.estado` y
--     `agenda.pago_estado`. El rastro de lo que se intento cobrar
--     (`pago_id`, `pago_monto`, `pago_moneda`) queda intacto.
--
-- ROLLBACK (no deberia hacer falta)
--   Con los ids que imprime el paso 1 (aqui seria el 7 sobre la agenda 302):
--     update flow.reserva_pago set estado = 'creado' where id = 7;
--     update flow.agenda set pago_estado = 'pendiente' where id = 302;
--   Ojo: si el intento ya habia vencido, lo correcto seria 'expirado', no
--   'creado'.
-- ============================================================================

\echo '== 1/4 DIAGNOSTICO: intentos vivos sobre reservas canceladas (esperado: solo el 7) =='

select rp.id,
       rp.id_agenda,
       rp.estado                                              as estado_intento,
       a.id_estado,
       es.nombre                                              as estado_reserva,
       a.pago_estado,
       a.pago_id,
       rp.monto,
       rp.moneda,
       rp.reportado_at,
       rp.expira_at,
       case when rp.expira_at <= now() then 'vencido' else 'en plazo' end as plazo
  from flow.reserva_pago rp
  join flow.agenda a             on a.id  = rp.id_agenda
  join flow.nom_estado_agenda es on es.id = a.id_estado
 where es.nombre = 'Cancelado'
   and rp.estado in ('creado', 'reportado')
 order by rp.id;

\echo '== 2/4 (dentro de la transaccion) cerrar intentos + alinear chips =='

begin;

-- 2.a Intentos vivos de reservas canceladas -> 'anulado'.
update flow.reserva_pago rp
   set estado = 'anulado'
 where rp.estado in ('creado', 'reportado')
   and exists (
         select 1
           from flow.agenda a
           join flow.nom_estado_agenda es on es.id = a.id_estado
          where a.id = rp.id_agenda
            and es.nombre = 'Cancelado'
       )
returning rp.id, rp.id_agenda, rp.estado;

-- 2.b Chip de la reserva: solo donde ya no queda NINGUN intento vivo. Asi no se
--     pisa un pago nuevo legitimo que pudiera seguir en curso.
update flow.agenda a
   set pago_estado = 'expirado',
       updated_at  = current_timestamp
 where a.id_estado = (select id from flow.nom_estado_agenda where nombre = 'Cancelado' limit 1)
   and a.pago_estado in ('pendiente', 'reportado')
   and not exists (
         select 1
           from flow.reserva_pago rp
          where rp.id_agenda = a.id
            and rp.estado in ('creado', 'reportado')
       )
returning a.id, a.pago_estado;

\echo '== 3/4 COMPROBACION: ambos contadores deben dar 0 =='

select count(*) as intentos_vivos_sobre_canceladas
  from flow.reserva_pago rp
  join flow.agenda a             on a.id  = rp.id_agenda
  join flow.nom_estado_agenda es on es.id = a.id_estado
 where es.nombre = 'Cancelado'
   and rp.estado in ('creado', 'reportado');            -- esperado: 0

select count(*) as agendas_canceladas_con_chip_vivo
  from flow.agenda a
  join flow.nom_estado_agenda es on es.id = a.id_estado
 where es.nombre = 'Cancelado'
   and a.pago_estado in ('pendiente', 'reportado');     -- esperado: 0

select a.id,
       es.nombre     as estado_reserva,
       a.pago_estado,
       a.pago_id,
       a.pago_monto,
       rp.id         as intento_id,
       rp.estado     as estado_intento
  from flow.agenda a
  join flow.nom_estado_agenda es on es.id = a.id_estado
  left join flow.reserva_pago rp on rp.id = a.pago_id
 where a.id = 302;                                      -- Cancelado / expirado / anulado

\echo '== 4/4 si los dos contadores del paso 3 dieron 0, confirmar con: commit;  (si no, rollback;) =='

commit;

\echo '== Listo: los intentos vivos sobre reservas canceladas quedaron anulados y sus agendas sin chip de pago vivo =='