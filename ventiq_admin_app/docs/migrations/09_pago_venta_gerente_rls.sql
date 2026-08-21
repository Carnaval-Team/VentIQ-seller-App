-- Migración: permitir a gerentes/supervisores crear pagos de venta
-- Problema: app_dat_pago_venta tenía RLS restringida a vendedores, por lo que
-- registrar una venta desde inventory_extractionbysale_screen fallaba al insertar
-- el detalle de pago cuando el usuario era gerente/supervisor.
--
-- Se añaden políticas para INSERT/SELECT/UPDATE/DELETE que conceden acceso a
-- gerentes, supervisores y auditores de la tienda a la que pertenece la operación.

ALTER TABLE public.app_dat_pago_venta ENABLE ROW LEVEL SECURITY;

-- Helper local: devuelve el id_tienda de una operación de venta.
CREATE OR REPLACE FUNCTION public.fn_get_tienda_by_operacion_venta(p_id_operacion_venta bigint)
RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT o.id_tienda
  FROM public.app_dat_operacion_venta ov
  JOIN public.app_dat_operaciones o ON o.id = ov.id_operacion
  WHERE ov.id_operacion = p_id_operacion_venta
  LIMIT 1;
$$;

-- Política INSERT para gerente/supervisor/auditor de la tienda.
DROP POLICY IF EXISTS pago_venta_admin_insert ON public.app_dat_pago_venta;
CREATE POLICY pago_venta_admin_insert
  ON public.app_dat_pago_venta
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.fn_user_can_access_tienda(
      public.fn_get_tienda_by_operacion_venta(id_operacion_venta)
    )
  );

-- Política SELECT para gerente/supervisor/auditor de la tienda.
DROP POLICY IF EXISTS pago_venta_admin_select ON public.app_dat_pago_venta;
CREATE POLICY pago_venta_admin_select
  ON public.app_dat_pago_venta
  FOR SELECT
  TO authenticated
  USING (
    public.fn_user_can_access_tienda(
      public.fn_get_tienda_by_operacion_venta(id_operacion_venta)
    )
  );

-- Política UPDATE para gerente/supervisor/auditor de la tienda.
DROP POLICY IF EXISTS pago_venta_admin_update ON public.app_dat_pago_venta;
CREATE POLICY pago_venta_admin_update
  ON public.app_dat_pago_venta
  FOR UPDATE
  TO authenticated
  USING (
    public.fn_user_can_access_tienda(
      public.fn_get_tienda_by_operacion_venta(id_operacion_venta)
    )
  )
  WITH CHECK (
    public.fn_user_can_access_tienda(
      public.fn_get_tienda_by_operacion_venta(id_operacion_venta)
    )
  );

-- Política DELETE para gerente/supervisor/auditor de la tienda.
DROP POLICY IF EXISTS pago_venta_admin_delete ON public.app_dat_pago_venta;
CREATE POLICY pago_venta_admin_delete
  ON public.app_dat_pago_venta
  FOR DELETE
  TO authenticated
  USING (
    public.fn_user_can_access_tienda(
      public.fn_get_tienda_by_operacion_venta(id_operacion_venta)
    )
  );
