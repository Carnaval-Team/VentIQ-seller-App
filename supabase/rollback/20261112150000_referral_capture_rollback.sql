-- ============================================================================
-- Rollback de 20261112150000 · Captura automática de referidos
-- ============================================================================
-- Deja la base EXACTAMENTE como estaba antes de aplicar la migración:
--   * elimina tabla/configuración/triggers/funciones nuevas,
--   * restaura `carnavalapp.fn_usuario_apply_referral` a su definición original.
--
-- Uso: Supabase SQL Editor (o psql). Seguro de ejecutar una sola vez.
-- OJO: borra el historial de visitas capturadas (no se pierde nada más).
-- ============================================================================

-- 1. Trigger y función del trigger -------------------------------------------------
drop trigger if exists trg_usuarios_aplicar_visita on carnavalapp."Usuarios";
drop function if exists carnavalapp.fn_usuarios_aplicar_visita_pendiente();

-- 2. Restaurar la función original (sin la rama de reemplazo heurístico) -----------
create or replace function carnavalapp.fn_usuario_apply_referral(
  p_referal_from text,
  p_uuid         uuid default null::uuid
)
returns jsonb
language plpgsql
security definer
set search_path = carnavalapp, public, pg_temp
as $function$
declare
  v_uuid      uuid := coalesce(p_uuid, carnavalapp.fn_require_auth_uid());
  v_from      text := upper(btrim(coalesce(p_referal_from, '')));
  v_user_id   bigint;
  v_existing  text;
  v_mi_codigo text;
  v_tocadas   integer := 0;
begin
  -- Aborta si el uuid no es el de la sesion.
  perform carnavalapp.fn_assert_usuario_uuid(v_uuid);

  if v_from = '' then
    return jsonb_build_object(
      'aplicado', false, 'motivo', 'codigo_vacio', 'ordenes_estampadas', 0);
  end if;

  select u.id,
         nullif(btrim(coalesce(u.referal_from, '')), ''),
         nullif(btrim(coalesce(u.referal_code, '')), '')
    into v_user_id, v_existing, v_mi_codigo
    from carnavalapp."Usuarios" u
   where u.uuid = v_uuid;

  if v_user_id is null then
    return jsonb_build_object(
      'aplicado', false, 'motivo', 'usuario_no_encontrado', 'ordenes_estampadas', 0);
  end if;

  if v_mi_codigo is not null and upper(v_mi_codigo) = v_from then
    return jsonb_build_object(
      'aplicado', false, 'motivo', 'codigo_propio', 'ordenes_estampadas', 0);
  end if;

  if not exists (
    select 1 from carnavalapp."Usuarios" r
     where upper(btrim(coalesce(r.referal_code, ''))) = v_from
  ) then
    return jsonb_build_object(
      'aplicado', false, 'motivo', 'codigo_inexistente', 'ordenes_estampadas', 0);
  end if;

  -- Ya tenia referidor: el codigo NO se cambia (regla de siempre), pero se
  -- aprovecha para estampar con el codigo que YA tiene las ordenes abiertas que
  -- se hubieran quedado sin el. Asi un reintento del usuario recupera la orden.
  if v_existing is not null then
    v_tocadas := carnavalapp.fn_estampar_referal_en_ordenes_abiertas(
                   v_user_id, v_existing, 48);
    return jsonb_build_object(
      'aplicado', false, 'motivo', 'ya_tenia_referidor',
      'referal_from', v_existing, 'ordenes_estampadas', v_tocadas);
  end if;

  -- Se estampa ANTES del UPDATE a proposito: el trigger del punto 2 se dispara
  -- con ese UPDATE y haria el trabajo, dejando a la RPC reportando 0 ordenes.
  -- Haciendolo antes, el contador que ve la app es el real. El trigger corre
  -- despues y no encuentra nada que hacer (el helper ya no ve filas vacias).
  v_tocadas := carnavalapp.fn_estampar_referal_en_ordenes_abiertas(
                 v_user_id, v_from, 48);

  update carnavalapp."Usuarios" u
     set referal_from = v_from
   where u.id = v_user_id;

  return jsonb_build_object(
    'aplicado', true, 'motivo', 'ok',
    'referal_from', v_from, 'ordenes_estampadas', v_tocadas);
end;
$function$;

-- 3. Funciones nuevas ---------------------------------------------------------------
drop function if exists public.fn_referral_visit_register(text, text, text, text);
drop function if exists public.fn_referral_visit_attach_phone(text, text);
drop function if exists public.fn_referral_visits_purge(integer);
drop function if exists public.fn_referral_phone_hash(text);
drop function if exists public.fn_referral_phone_norm(text);
drop function if exists public.fn_referral_ip_hash();
drop function if exists public.fn_referral_request_ip();

-- 4. Tablas y secuencia -------------------------------------------------------------
drop table if exists public.referral_user_attributions;
drop table if exists public.referral_visits;
drop table if exists public.referral_capture_config;

-- 5. Cron (si se programó la purga) -------------------------------------------------
-- select cron.unschedule('referral-visits-purge');