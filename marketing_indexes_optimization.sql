-- =====================================================
-- ÍNDICES DE OPTIMIZACIÓN PARA MÓDULO DE MARKETING
-- =====================================================
-- Este archivo contiene todos los índices recomendados para optimizar
-- el rendimiento de las consultas del módulo de marketing.
-- Ejecutar después de implementar las funciones principales.

-- =====================================================
-- ÍNDICES PARA TABLA app_mkt_promociones
-- =====================================================

-- Índice compuesto para consultas por tienda y estado
CREATE INDEX IF NOT EXISTS idx_promociones_tienda_estado 
ON app_mkt_promociones (id_tienda, estado);

-- Índice para consultas por fechas de vigencia
CREATE INDEX IF NOT EXISTS idx_promociones_fechas 
ON app_mkt_promociones (fecha_inicio, fecha_fin);

-- Índice para búsquedas por código de promoción (único y frecuente)
CREATE INDEX IF NOT EXISTS idx_promociones_codigo 
ON app_mkt_promociones (codigo_promocion);

-- Índice para consultas por tipo de promoción
CREATE INDEX IF NOT EXISTS idx_promociones_tipo 
ON app_mkt_promociones (id_tipo_promocion);

-- Índice compuesto para consultas de validación de promociones activas
CREATE INDEX IF NOT EXISTS idx_promociones_activas 
ON app_mkt_promociones (id_tienda, estado, fecha_inicio, fecha_fin) 
WHERE estado = true;

-- Índice para auditoría y timestamps
CREATE INDEX IF NOT EXISTS idx_promociones_created_at 
ON app_mkt_promociones (created_at DESC);

-- =====================================================
-- ÍNDICES PARA TABLA app_mkt_campanas
-- =====================================================

-- Índice compuesto para consultas por tienda y estado
CREATE INDEX IF NOT EXISTS idx_campanas_tienda_estado 
ON app_mkt_campanas (id_tienda, estado);

-- Índice para consultas por fechas de campaña
CREATE INDEX IF NOT EXISTS idx_campanas_fechas 
ON app_mkt_campanas (fecha_inicio, fecha_fin);

-- Índice para consultas por tipo de campaña
CREATE INDEX IF NOT EXISTS idx_campanas_tipo 
ON app_mkt_campanas (tipo_campana);

-- Índice GIN para búsquedas en métricas JSONB
CREATE INDEX IF NOT EXISTS idx_campanas_metricas_gin 
ON app_mkt_campanas USING GIN (metricas);

-- Índices específicos para campos JSONB más consultados
CREATE INDEX IF NOT EXISTS idx_campanas_impresiones 
ON app_mkt_campanas ((metricas->>'impresiones')::INTEGER);

CREATE INDEX IF NOT EXISTS idx_campanas_conversiones 
ON app_mkt_campanas ((metricas->>'conversiones')::INTEGER);

-- Índice para auditoría
CREATE INDEX IF NOT EXISTS idx_campanas_created_at 
ON app_mkt_campanas (created_at DESC);

-- =====================================================
-- ÍNDICES PARA TABLA app_mkt_comunicaciones
-- =====================================================

-- Índice compuesto para consultas por tienda y estado
CREATE INDEX IF NOT EXISTS idx_comunicaciones_tienda_estado 
ON app_mkt_comunicaciones (id_tienda, estado);

-- Índice para consultas por canal de comunicación
CREATE INDEX IF NOT EXISTS idx_comunicaciones_canal 
ON app_mkt_comunicaciones (canal);

-- Índice para consultas por fecha de envío
CREATE INDEX IF NOT EXISTS idx_comunicaciones_fecha_envio 
ON app_mkt_comunicaciones (fecha_envio DESC);

-- Índice para consultas por segmento objetivo
CREATE INDEX IF NOT EXISTS idx_comunicaciones_segmento 
ON app_mkt_comunicaciones (id_segmento_objetivo);

-- Índice para auditoría
CREATE INDEX IF NOT EXISTS idx_comunicaciones_created_at 
ON app_mkt_comunicaciones (created_at DESC);

-- =====================================================
-- ÍNDICES PARA TABLA app_mkt_segmentos
-- =====================================================

-- Índice compuesto para consultas por tienda y estado
CREATE INDEX IF NOT EXISTS idx_segmentos_tienda_estado 
ON app_mkt_segmentos (id_tienda, activo);

-- Índice GIN para búsquedas en criterios JSONB
CREATE INDEX IF NOT EXISTS idx_segmentos_criterios_gin 
ON app_mkt_segmentos USING GIN (criterios);

-- Índice para consultas por tipo de segmento
CREATE INDEX IF NOT EXISTS idx_segmentos_tipo 
ON app_mkt_segmentos (tipo_segmento);

-- Índice para auditoría
CREATE INDEX IF NOT EXISTS idx_segmentos_created_at 
ON app_mkt_segmentos (created_at DESC);

-- =====================================================
-- ÍNDICES PARA TABLA app_mkt_eventos_fidelizacion
-- =====================================================

-- Índice compuesto para consultas por tienda y tipo
CREATE INDEX IF NOT EXISTS idx_eventos_fidelizacion_tienda_tipo 
ON app_mkt_eventos_fidelizacion (id_tienda, tipo_evento);

-- Índice para consultas por cliente
CREATE INDEX IF NOT EXISTS idx_eventos_fidelizacion_cliente 
ON app_mkt_eventos_fidelizacion (id_cliente);

-- Índice para consultas por fecha de evento
CREATE INDEX IF NOT EXISTS idx_eventos_fidelizacion_fecha 
ON app_mkt_eventos_fidelizacion (fecha_evento DESC);

-- Índice para consultas por puntos otorgados
CREATE INDEX IF NOT EXISTS idx_eventos_fidelizacion_puntos 
ON app_mkt_eventos_fidelizacion (puntos_otorgados);

-- Índice compuesto para análisis de fidelización
CREATE INDEX IF NOT EXISTS idx_eventos_fidelizacion_analisis 
ON app_mkt_eventos_fidelizacion (id_tienda, tipo_evento, fecha_evento DESC);

-- =====================================================
-- ÍNDICES PARA TABLAS DE SOPORTE
-- =====================================================

-- Índices para app_dat_gerente (multi-tienda)
CREATE INDEX IF NOT EXISTS idx_gerente_uuid 
ON app_dat_gerente (uuid);

CREATE INDEX IF NOT EXISTS idx_gerente_tienda 
ON app_dat_gerente (id_tienda);

-- Índices para app_dat_tienda
CREATE INDEX IF NOT EXISTS idx_tienda_activa 
ON app_dat_tienda (activa) WHERE activa = true;

-- Índices para app_mkt_tipos_promocion
CREATE INDEX IF NOT EXISTS idx_tipos_promocion_denominacion 
ON app_mkt_tipos_promocion (denominacion);

-- Índices para app_mkt_criterios_segmentacion
CREATE INDEX IF NOT EXISTS idx_criterios_segmentacion_tipo 
ON app_mkt_criterios_segmentacion (tipo_dato);

-- =====================================================
-- ÍNDICES PARA OPTIMIZACIÓN DE FUNCIONES ESPECÍFICAS
-- =====================================================

-- Índice para función fn_listar_promociones
CREATE INDEX IF NOT EXISTS idx_promociones_listado_optimizado 
ON app_mkt_promociones (id_tienda, estado, fecha_inicio, fecha_fin, created_at DESC);

-- Índice para función fn_estadisticas_promociones
CREATE INDEX IF NOT EXISTS idx_promociones_estadisticas 
ON app_mkt_promociones (id_tienda, estado, fecha_inicio, fecha_fin, valor_descuento);

-- Índice para función fn_listar_campanas
CREATE INDEX IF NOT EXISTS idx_campanas_listado_optimizado 
ON app_mkt_campanas (id_tienda, estado, fecha_inicio, fecha_fin, created_at DESC);

-- Índice para función fn_listar_comunicaciones
CREATE INDEX IF NOT EXISTS idx_comunicaciones_listado_optimizado 
ON app_mkt_comunicaciones (id_tienda, estado, fecha_envio DESC, canal);

-- Índice para función fn_listar_segmentos
CREATE INDEX IF NOT EXISTS idx_segmentos_listado_optimizado 
ON app_mkt_segmentos (id_tienda, activo, created_at DESC);

-- Índice para función fn_listar_eventos_fidelizacion
CREATE INDEX IF NOT EXISTS idx_eventos_listado_optimizado 
ON app_mkt_eventos_fidelizacion (id_tienda, tipo_evento, fecha_evento DESC);

-- =====================================================
-- ÍNDICES PARA ANÁLISIS Y REPORTES
-- =====================================================

-- Índice para análisis temporal de promociones
CREATE INDEX IF NOT EXISTS idx_promociones_analisis_temporal 
ON app_mkt_promociones (id_tienda, EXTRACT(YEAR FROM fecha_inicio), EXTRACT(MONTH FROM fecha_inicio));

-- Índice para análisis de efectividad de campañas
CREATE INDEX IF NOT EXISTS idx_campanas_efectividad 
ON app_mkt_campanas (id_tienda, tipo_campana, ((metricas->>'conversiones')::INTEGER));

-- Índice para análisis de comunicaciones por canal
CREATE INDEX IF NOT EXISTS idx_comunicaciones_analisis_canal 
ON app_mkt_comunicaciones (id_tienda, canal, fecha_envio);

-- Índice para análisis de fidelización por cliente
CREATE INDEX IF NOT EXISTS idx_fidelizacion_por_cliente 
ON app_mkt_eventos_fidelizacion (id_cliente, fecha_evento DESC, puntos_otorgados);

-- =====================================================
-- ÍNDICES PARCIALES PARA CASOS ESPECÍFICOS
-- =====================================================

-- Solo promociones activas y vigentes
CREATE INDEX IF NOT EXISTS idx_promociones_activas_vigentes 
ON app_mkt_promociones (id_tienda, codigo_promocion) 
WHERE estado = true AND fecha_inicio <= NOW() AND (fecha_fin IS NULL OR fecha_fin >= NOW());

-- Solo campañas en ejecución
CREATE INDEX IF NOT EXISTS idx_campanas_en_ejecucion 
ON app_mkt_campanas (id_tienda, tipo_campana) 
WHERE estado = 'activa' AND fecha_inicio <= NOW() AND fecha_fin >= NOW();

-- Solo comunicaciones enviadas
CREATE INDEX IF NOT EXISTS idx_comunicaciones_enviadas 
ON app_mkt_comunicaciones (id_tienda, canal, fecha_envio DESC) 
WHERE estado = 'enviada';

-- Solo segmentos activos
CREATE INDEX IF NOT EXISTS idx_segmentos_activos 
ON app_mkt_segmentos (id_tienda, tipo_segmento) 
WHERE activo = true;

-- =====================================================
-- ESTADÍSTICAS Y MANTENIMIENTO
-- =====================================================

-- Actualizar estadísticas después de crear índices
ANALYZE app_mkt_promociones;
ANALYZE app_mkt_campanas;
ANALYZE app_mkt_comunicaciones;
ANALYZE app_mkt_segmentos;
ANALYZE app_mkt_eventos_fidelizacion;

-- =====================================================
-- NOTAS DE IMPLEMENTACIÓN DE ÍNDICES
-- =====================================================
/*
CONSIDERACIONES IMPORTANTES:

1. ORDEN DE EJECUCIÓN:
   - Ejecutar este archivo DESPUÉS de crear las tablas y funciones
   - Ejecutar durante horarios de baja actividad para evitar bloqueos

2. MONITOREO DE RENDIMIENTO:
   - Usar EXPLAIN ANALYZE para verificar que los índices se usan correctamente
   - Monitorear el tamaño de los índices vs beneficio en rendimiento
   - Considerar DROP de índices no utilizados

3. ÍNDICES JSONB:
   - Los índices GIN son costosos de mantener pero muy eficientes para búsquedas
   - Considerar índices específicos para campos JSONB frecuentemente consultados
   - Evaluar el uso de índices expresionales para campos calculados

4. MANTENIMIENTO:
   - Programar REINDEX periódico para índices muy actualizados
   - Monitorear fragmentación de índices
   - Actualizar estadísticas regularmente con ANALYZE

5. ÍNDICES PARCIALES:
   - Muy eficientes para consultas con condiciones WHERE frecuentes
   - Reducen el tamaño del índice y mejoran el rendimiento
   - Útiles para datos con distribución desigual

6. IMPACTO EN ESCRITURA:
   - Cada índice adicional ralentiza INSERT/UPDATE/DELETE
   - Balancear entre rendimiento de lectura y escritura
   - Considerar índices concurrentes para tablas con alta actividad

COMANDOS ÚTILES PARA MONITOREO:

-- Ver uso de índices
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch 
FROM pg_stat_user_indexes 
WHERE schemaname = 'public' AND tablename LIKE 'app_mkt_%';

-- Ver tamaño de índices
SELECT schemaname, tablename, indexname, pg_size_pretty(pg_relation_size(indexrelid)) as size
FROM pg_stat_user_indexes 
WHERE schemaname = 'public' AND tablename LIKE 'app_mkt_%'
ORDER BY pg_relation_size(indexrelid) DESC;

-- Identificar índices no utilizados
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes 
WHERE schemaname = 'public' AND tablename LIKE 'app_mkt_%' AND idx_scan = 0;
*/
