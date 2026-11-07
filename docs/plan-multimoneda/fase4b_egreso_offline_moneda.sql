-- ============================================================================
-- FASE 4b (cierre) — DIVISA DEL EGRESO EN EL CAMINO OFFLINE
--
-- PROBLEMA: `fn_registrar_egreso_offline` no acepta divisa. El sincronizador
-- offline recibe el egreso con su `moneda` en la cola, pero al persistirlo el
-- importe acaba siempre en la moneda base: un egreso de 20 USD se guarda como
-- 20 CUP, y el arqueo descuenta 20 CUP de un cajón que en realidad no los tiene.
--
-- SOLUCIÓN: `fn_registrar_egreso_offline_v2(..., p_moneda)` **envuelve** a la
-- vigente en vez de reescribirla. La vigente son 3,5 KB de plpgsql con
-- idempotencia por `client_uuid` y validaciones de negocio ya probadas; la v2
-- solo valida la divisa y ajusta la fila que acaba de crear. Mismo patrón que
-- `registrar_egreso_parcial_v3` en el camino online.
--
-- Contrato de retorno: idéntico al de la vigente
-- (`{success, egreso_id, idempotent, message, ...}`), así que el cliente no
-- cambia nada más.
--
-- Idempotente. Verificado en `newa` el 2026-11-05:
--   · alta en EUR → fila `30 EUR`
--   · replay con el mismo `client_uuid` → `idempotent: true`, egreso_id 2
--   · moneda inexistente → error del catálogo
-- ============================================================================

create or replace function public.fn_registrar_egreso_offline_v2(
  p_client_uuid    uuid,
  p_id_turno       bigint,
  p_monto_entrega  numeric,
  p_nombre_recibe  character varying,
  p_nombre_autoriza character varying,
  p_motivo_entrega text,
  p_id_medio_pago  smallint default null,
  p_uuid_usuario   uuid default null,
  p_moneda         text default 'CUP'
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_res    jsonb;
  v_id     bigint;
  v_moneda text;
begin
  v_moneda := upper(trim(coalesce(nullif(p_moneda, ''), 'CUP')));

  if not exists (select 1 from public.monedas m where m.codigo = v_moneda and m.activo) then
    raise exception 'La moneda % no existe o no está activa en el catálogo', v_moneda;
  end if;

  -- Toda la lógica (idempotencia por client_uuid, validaciones, alta) la sigue
  -- haciendo la vigente: aquí no se duplica nada.
  v_res := public.fn_registrar_egreso_offline(
             p_client_uuid, p_id_turno, p_monto_entrega,
             p_nombre_recibe, p_nombre_autoriza, p_motivo_entrega,
             p_id_medio_pago, p_uuid_usuario);

  -- En un replay idempotente `egreso_id` es el de la fila ya existente y la
  -- divisa es la misma, así que este UPDATE es inocuo.
  if coalesce((v_res->>'success')::boolean, false) then
    v_id := nullif(v_res->>'egreso_id', '')::bigint;
    if v_id is not null then
      update public.app_dat_entregas_parciales_caja
      set moneda = v_moneda
      where id = v_id;
    end if;
  end if;

  return v_res;
end $$;

comment on function public.fn_registrar_egreso_offline_v2(
  uuid, bigint, numeric, character varying, character varying, text, smallint, uuid, text) is
  'Alta de egreso offline con divisa. Envuelve a fn_registrar_egreso_offline y fija `moneda` en la fila creada.';

grant execute on function public.fn_registrar_egreso_offline_v2(
  uuid, bigint, numeric, character varying, character varying, text, smallint, uuid, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Verificación
-- ---------------------------------------------------------------------------
select p.oid::regprocedure::text as firma
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('fn_registrar_egreso_offline', 'fn_registrar_egreso_offline_v2')
order by 1;