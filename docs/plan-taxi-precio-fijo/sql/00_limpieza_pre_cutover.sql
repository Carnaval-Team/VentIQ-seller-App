-- ============================================================================
-- 00_limpieza_pre_cutover.sql
-- Limpieza de viajes abiertos ANTES del cutover (H8).
--
-- PARA QUÉ
--   Las apps viejas dejan solicitudes `pendiente` que nadie va a tomar y viajes
--   a medio camino. Si se enciende el precio fijo con basura abierta:
--     · un cliente no puede publicar (regla "una solicitud abierta por cliente");
--     · quedan retenciones de wallet sin devolver (dinero del cliente atrapado);
--     · el chofer puede aparecer "con viaje activo" y no ver la lista.
--
-- CÓMO SE USA
--   1. Ejecutar la sección REPORTE (solo lectura) y revisar los números.
--   2. Ejecutar la sección LIMPIEZA en una transacción, revisar y COMMIT.
--
-- NOTA: este archivo NO es una migración. NO se aplica con las 030–048; se
-- ejecuta a mano en la ventana del cutover, antes de encender el flag.
-- ============================================================================


-- ============================================================================
-- 1. REPORTE (solo lectura) — qué hay abierto
-- ============================================================================
select 'solicitudes pendientes' as que, count(*) as cuantas
  from muevete.solicitudes_transporte
 where estado = 'pendiente'
union all
select 'pendientes vencidas (más de 1 h)', count(*)
  from muevete.solicitudes_transporte
 where estado = 'pendiente' and created_at < now() - interval '1 hour'
union all
select 'aceptadas sin viaje cerrado', count(*)
  from muevete.solicitudes_transporte
 where estado = 'aceptada'
union all
select 'viajes abiertos', count(*)
  from muevete.viajes
 where coalesce(completado, false) = false
union all
select 'retenciones de wallet sin cerrar', count(*)
  from muevete.transacciones_wallet t
 where t.tipo = 'cobro_viaje'
   and t.estado = 'completada'
   and t.viaje_id is not null
   and not exists (
     select 1 from muevete.transacciones_wallet r
      where r.viaje_id = t.viaje_id and r.tipo = 'reembolso'
   )
   and not exists (
     select 1 from muevete.solicitudes_transporte s
      where s.id = (select v.solicitud_id from muevete.viajes v where v.id = t.viaje_id)
        and s.estado = 'completada'
   );

-- Detalle de las pendientes vencidas (revisar antes de tocar nada)
select id, user_id, created_at, precio_oferta, zona_id, estado
  from muevete.solicitudes_transporte
 where estado = 'pendiente' and created_at < now() - interval '1 hour'
 order by created_at
 limit 50;


-- ============================================================================
-- 2. LIMPIEZA (ejecutar en transacción)
-- ============================================================================
begin;

-- 2.1 Expirar solicitudes `pendiente` sin chofer con más de 1 hora.
--     El trigger de seguridad revoca los enlaces compartidos al cambiar estado.
update muevete.solicitudes_transporte
   set estado             = 'expirada',
       cancelada_at       = now(),
       motivo_cancelacion = coalesce(motivo_cancelacion, 'limpieza_pre_cutover')
 where estado = 'pendiente'
   and driver_id is null
   and created_at < now() - interval '1 hour';

-- 2.2 Cerrar viajes abiertos cuyas solicitudes ya no están activas
--     (evita que un chofer aparezca "con viaje activo" al arrancar).
update muevete.viajes v
   set completado = true,
       estado     = false
 where coalesce(v.completado, false) = false
   and exists (
     select 1 from muevete.solicitudes_transporte s
      where s.id = v.solicitud_id
        and s.estado in ('cancelada','expirada','completada')
   );

-- 2.3 Devolver retenciones de wallet de viajes que NO se completaron.
--     (Convenio de 038: retención = `cobro_viaje` negativo; reembolso = positivo.)
insert into muevete.transacciones_wallet
  (user_id, viaje_id, tipo, monto, balance_despues, descripcion, estado)
select t.user_id, t.viaje_id, 'reembolso', abs(t.monto),
       coalesce(su.balance, 0) + abs(t.monto),
       'Reembolso por limpieza pre-cutover (viaje #' || t.viaje_id || ')',
       'completada'
  from muevete.transacciones_wallet t
  join muevete.viajes v on v.id = t.viaje_id
  join muevete.solicitudes_transporte s on s.id = v.solicitud_id
  left join muevete.suscription_user su on su.user_id = t.user_id
 where t.tipo = 'cobro_viaje'
   and t.estado = 'completada'
   and t.viaje_id is not null
   and s.estado <> 'completada'
   and not exists (
     select 1 from muevete.transacciones_wallet r
      where r.viaje_id = t.viaje_id and r.tipo = 'reembolso'
   );

-- 2.4 Acreditar el reembolso en el saldo del cliente (misma fila, una vez)
update muevete.suscription_user su
   set balance = coalesce(su.balance, 0) + r.monto
  from (
    select w.user_id, sum(w.monto) as monto
      from muevete.transacciones_wallet w
     where w.tipo = 'reembolso'
       and w.descripcion like 'Reembolso por limpieza pre-cutover%'
       and not exists (
         select 1 from muevete.transacciones_wallet w2
          where w2.viaje_id = w.viaje_id and w2.tipo = 'reembolso'
            and w2.id < w.id
       )
     group by w.user_id
  ) r
 where su.user_id = r.user_id;

-- 2.5 comprobar y luego:  COMMIT;   /   ROLLBACK;
select 'solicitudes pendientes' as que, count(*) as cuantas
  from muevete.solicitudes_transporte where estado = 'pendiente'
union all
select 'viajes abiertos', count(*)
  from muevete.viajes where coalesce(completado, false) = false;

-- COMMIT;