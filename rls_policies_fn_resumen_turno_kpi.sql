-- =====================================================
-- RLS POLICIES FOR fn_resumen_turno_kpi FUNCTION
-- =====================================================
-- Políticas de acceso abierto para todas las tablas
-- involucradas en la función fn_resumen_turno_kpi
-- SIN RESTRICCIONES - Acceso completo para todos los usuarios

-- =====================================================
-- 1. TABLAS PRINCIPALES
-- =====================================================

-- Política para app_dat_caja_turno
ALTER TABLE app_dat_caja_turno ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Open access to caja_turno" ON app_dat_caja_turno
FOR SELECT USING (true);

-- Política para app_dat_tpv
ALTER TABLE app_dat_tpv ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Open access to tpv" ON app_dat_tpv
FOR SELECT USING (true);

-- Política para app_dat_vendedor
ALTER TABLE app_dat_vendedor ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Open access to vendedor" ON app_dat_vendedor
FOR SELECT USING (true);

-- =====================================================
-- 2. TABLAS DE OPERACIONES
-- =====================================================

-- Política para app_dat_operaciones
ALTER TABLE app_dat_operaciones ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Open access to operaciones" ON app_dat_operaciones
FOR SELECT USING (true);

-- Política para app_dat_operacion_venta
ALTER TABLE app_dat_operacion_venta ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Open access to operacion_venta" ON app_dat_operacion_venta
FOR SELECT USING (true);

-- Política para app_dat_control_productos
ALTER TABLE app_dat_control_productos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Open access to control_productos" ON app_dat_control_productos
FOR SELECT USING (true);

-- Política para app_nom_tipo_operacion
ALTER TABLE app_nom_tipo_operacion ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Open access to tipo_operacion" ON app_nom_tipo_operacion
FOR SELECT USING (true);

-- =====================================================
-- 3. TABLAS DE PAGOS
-- =====================================================

-- Política para app_dat_pago_venta
ALTER TABLE app_dat_pago_venta ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Open access to pago_venta" ON app_dat_pago_venta
FOR SELECT USING (true);

-- Política para app_nom_medio_pago
ALTER TABLE app_nom_medio_pago ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Open access to medio_pago" ON app_nom_medio_pago
FOR SELECT USING (true);

-- =====================================================
-- 4. VERIFICACIÓN DE POLÍTICAS EXISTENTES
-- =====================================================

-- Verificar si ya existen políticas similares antes de crear duplicados
-- Ejecutar estas consultas para revisar políticas existentes:

/*
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE tablename IN (
  'app_dat_caja_turno',
  'app_dat_tpv', 
  'app_dat_vendedor',
  'app_dat_operaciones',
  'app_dat_operacion_venta',
  'app_dat_control_productos',
  'app_nom_tipo_operacion',
  'app_dat_pago_venta',
  'app_nom_medio_pago'
)
ORDER BY tablename, policyname;
*/

-- =====================================================
-- 5. NOTAS IMPORTANTES
-- =====================================================

/*
NOTAS:
1. ACCESO ABIERTO: Todas las políticas usan "USING (true)" para permitir 
   acceso completo sin restricciones.

2. SIN AUTENTICACIÓN REQUERIDA: No se requiere auth.uid() ni roles específicos.

3. SIN FILTROS POR TIENDA: Los usuarios pueden acceder a datos de todas las tiendas.

4. TABLAS AFECTADAS: Todas las 9 tablas involucradas en fn_resumen_turno_kpi 
   tienen acceso completamente abierto.

5. SEGURIDAD: Esta configuración elimina todas las restricciones de seguridad.
   Usar solo en entornos de desarrollo o cuando se requiera acceso total.

6. Si alguna tabla ya tiene RLS habilitado, las políticas existentes podrían
   entrar en conflicto. Revisar con la consulta de verificación incluida.
*/
