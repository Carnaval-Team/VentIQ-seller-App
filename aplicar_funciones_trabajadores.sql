-- =====================================================
-- SCRIPT PARA APLICAR TODAS LAS FUNCIONES DE TRABAJADORES
-- =====================================================

-- Este script debe ejecutarse en la base de datos de VentIQ
-- para crear todas las funciones necesarias para el manejo de trabajadores

-- =====================================================
-- PASO 1: EJECUTAR FUNCIONES PRINCIPALES
-- =====================================================

-- Ejecutar el contenido del archivo funciones_trabajadores.sql
\i funciones_trabajadores.sql

-- =====================================================
-- PASO 2: EJECUTAR FUNCIONES AUXILIARES
-- =====================================================

-- Ejecutar el contenido del archivo funciones_auxiliares_trabajadores.sql
\i funciones_auxiliares_trabajadores.sql

-- =====================================================
-- PASO 3: VERIFICAR QUE LAS FUNCIONES SE CREARON CORRECTAMENTE
-- =====================================================

-- Listar todas las funciones relacionadas con trabajadores
SELECT 
    proname as nombre_funcion,
    pg_get_function_arguments(oid) as argumentos,
    pg_get_function_result(oid) as tipo_retorno
FROM pg_proc 
WHERE proname LIKE '%trabajador%' 
   OR proname LIKE '%roles%'
   OR proname LIKE '%tpvs%'
   OR proname LIKE '%almacenes%'
   OR proname LIKE '%permisos%'
   OR proname LIKE '%estadisticas%'
ORDER BY proname;

-- =====================================================
-- PASO 4: PRUEBAS BÁSICAS (OPCIONAL)
-- =====================================================

-- Descomentar las siguientes líneas para hacer pruebas básicas
-- NOTA: Reemplazar los valores de ejemplo con datos reales de tu base de datos

/*
-- Prueba 1: Obtener roles de una tienda (reemplazar 1 con ID real)
SELECT fn_obtener_roles_tienda(1);

-- Prueba 2: Obtener TPVs de una tienda (reemplazar 1 con ID real)
SELECT fn_obtener_tpvs_tienda(1);

-- Prueba 3: Obtener almacenes de una tienda (reemplazar 1 con ID real)
SELECT fn_obtener_almacenes_tienda(1);

-- Prueba 4: Obtener estadísticas de trabajadores (reemplazar 1 con ID real)
SELECT fn_estadisticas_trabajadores_tienda(1);

-- Prueba 5: Verificar permisos de usuario (reemplazar UUID con uno real)
SELECT fn_verificar_permisos_usuario('00000000-0000-0000-0000-000000000000'::uuid, 1);
*/

-- =====================================================
-- INFORMACIÓN IMPORTANTE
-- =====================================================

/*
FUNCIONES CREADAS:

PRINCIPALES:
1. fn_listar_trabajadores_tienda(id_tienda, usuario_solicitante)
   - Lista todos los trabajadores de una tienda
   - Solo gerentes y supervisores pueden ejecutarla
   - Muestra datos específicos según el rol (TPV para vendedores, almacén para almaceneros)

2. fn_insertar_trabajador_completo(id_tienda, nombres, apellidos, tipo_rol, usuario_uuid, [tpv_id], [almacen_id], [numero_confirmacion])
   - Crea un trabajador completo con su rol específico
   - Maneja automáticamente la creación en las tablas correspondientes
   - Asigna TPV/almacén automáticamente si no se especifica

3. fn_eliminar_trabajador_completo(trabajador_id, id_tienda)
   - Elimina un trabajador y su registro en la tabla de rol específico
   - Verifica que no tenga operaciones registradas (operaciones, turnos, pagos, pre-asignaciones)
   - Solo permite eliminación si el trabajador no tiene actividad en el sistema
   - Maneja la eliminación en cascada correctamente

4. fn_editar_trabajador_completo(trabajador_id, id_tienda, [nuevos_datos])
   - Permite editar todos los datos del trabajador, incluyendo cambio de rol
   - Maneja la transición entre roles automáticamente
   - Actualiza solo los campos proporcionados

AUXILIARES:
5. fn_obtener_roles_tienda(id_tienda) - Lista roles disponibles
6. fn_obtener_tpvs_tienda(id_tienda) - Lista TPVs disponibles
7. fn_obtener_almacenes_tienda(id_tienda) - Lista almacenes disponibles
8. fn_obtener_detalle_trabajador(trabajador_id, id_tienda) - Detalle completo de un trabajador
9. fn_verificar_permisos_usuario(usuario_uuid, id_tienda) - Verifica permisos y roles
10. fn_estadisticas_trabajadores_tienda(id_tienda) - Estadísticas de trabajadores

CARACTERÍSTICAS:
- Todas las funciones retornan JSON con estructura estándar: {success, message, data}
- Manejo robusto de errores con códigos SQL
- Validación de permisos integrada
- Logging detallado para debugging
- Compatibilidad con la estructura existente de VentIQ
- Transacciones seguras con rollback automático en caso de error

SEGURIDAD:
- Solo gerentes y supervisores pueden listar/gestionar trabajadores
- Validación de pertenencia a tienda en todas las operaciones
- UUIDs verificados contra auth.users
- Prevención de inyección SQL mediante parámetros tipados

USO RECOMENDADO:
1. Usar fn_verificar_permisos_usuario() antes de operaciones sensibles
2. Usar funciones auxiliares para poblar dropdowns en UI
3. Manejar respuestas JSON en el frontend para mostrar errores/éxitos
4. Implementar logging en el frontend para operaciones críticas
*/
