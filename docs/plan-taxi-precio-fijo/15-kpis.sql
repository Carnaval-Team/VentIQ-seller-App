-- ============================================================================
-- 15-kpis.sql — Tablero mínimo del plan de taxi (esquema `muevete`)
--
--   Consultas listas para pegar en el SQL Editor del proyecto de PRUEBAS
--   (`qhprswhhfasrikhawjoz`) o en producción cuando se quiera mirar el tablero.
--   Todas son de SÓLO LECTURA: no crean, no borran y no tocan
--   `configuracion_tarifas`.
--
--   Verificadas contra la BD de pruebas el 2026-11-12: las 8 corren sin error.
--   Hoy esa BD está vacía (0 solicitudes, 0 viajes), así que devuelven 0 filas;
--   las columnas y los tipos son los que se ven en esa corrida. El anexo del
--   final no es un KPI: es la consulta de control del interruptor de corte.
--
--   Convenciones
--     · "viaje" = fila de `muevete.solicitudes_transporte` con estado
--       `completada` (la fuente del dinero congelado: precio_plataforma,
--       comision_pct, precio_chofer). `muevete.viajes` es la fila operativa del
--       chofer; para KPIs de negocio se usa la solicitud.
--     · Día = `date_trunc('day', ...)` en hora local del servidor (UTC en
--       Supabase). Si el negocio cierra a las 00:00 de La Habana, resta
--       `interval '5 hours'` antes del truncado.
--     · Estados posibles: pendiente | aceptada | completada | cancelada |
--       expirada (ver 038/039/040).
-- ============================================================================


-- ============================================================================
-- K01 · Viajes completados por día (últimos 30 días) y por zona
-- ----------------------------------------------------------------------------
-- Qué mide: volumen diario y reparto geográfico. Es el pulso del negocio.
--   · `viajes`        → viajes cerrados ese día
--   · `ticket_medio`  → precio medio al cliente ese día en esa zona
--   · `sin_zona`      → viajes cuyo `zona_id` es NULL o ya no existe en
--                       `zonas_tarifa` (cotizados con fallback municipal)
-- Valor malo:
--   · Caída > 25 % día contra la media de 7 días → revisar flag, versión mínima
--     o caída de la oferta de choferes (no la demanda).
--   · `sin_zona` alto (> 20 %) → el editor de polígonos dejó huecos: la
--     cotización está cayendo al fallback municipal.
-- ============================================================================
SELECT date_trunc('day', s.completada_at)::date        AS dia,
       coalesce(z.nombre, 'Fuera de zona')             AS zona,
       count(*)                                        AS viajes,
       round(avg(s.precio_plataforma), 2)              AS ticket_medio,
       count(*) FILTER (WHERE s.zona_id IS NULL OR z.id IS NULL) AS sin_zona
  FROM muevete.solicitudes_transporte s
  LEFT JOIN muevete.zonas_tarifa z ON z.id = s.zona_id
 WHERE s.estado = 'completada'
   AND s.completada_at >= now() - interval '30 days'
 GROUP BY 1, 2
 ORDER BY 1 DESC, 3 DESC;


-- ============================================================================
-- K02 · Tiempo de asignación (publicación → aceptada_at): p50 y p90
-- ----------------------------------------------------------------------------
-- Qué mide: cuánto espera el cliente desde que publica hasta que un chofer
--   toma el viaje. Sólo cuenta solicitudes que llegaron a tener chofer.
--   `p50` es la experiencia típica; `p90` la cola (el cliente que se va).
-- Valor malo:
--   · p50 > 3 min → hay choferes pero no están viendo la lista (realtime roto,
--     o `place` desactualizado: `fn_viajes_disponibles` ordena por distancia).
--   · p90 > 10 min → la cola es insostenible; el TTL de 15 min hace que muchos
--     de esos viajes mueran sin chofer.
--   · `sin_metricas` > 0 → hay filas `aceptada` sin `aceptada_at`, señal de
--     escritura fuera de `fn_tomar_viaje` (no debería pasar tras 039).
-- ============================================================================
SELECT count(*) FILTER (WHERE s.aceptada_at IS NOT NULL)                    AS con_tiempo,
       count(*) FILTER (WHERE s.aceptada_at IS NULL)                        AS sin_metricas,
       round(percentile_cont(0.5) WITHIN GROUP (
         ORDER BY extract(epoch FROM (s.aceptada_at - s.created_at)))::numeric, 1)
                                                                            AS p50_seg,
       round(percentile_cont(0.9) WITHIN GROUP (
         ORDER BY extract(epoch FROM (s.aceptada_at - s.created_at)))::numeric, 1)
                                                                            AS p90_seg,
       round(avg(extract(epoch FROM (s.aceptada_at - s.created_at)))::numeric, 1)
                                                                            AS media_seg
  FROM muevete.solicitudes_transporte s
 WHERE s.aceptada_at IS NOT NULL
   AND s.created_at >= now() - interval '30 days';


-- ============================================================================
-- K03 · % de viajes tomados en menos de 60 segundos
-- ----------------------------------------------------------------------------
-- Qué mide: la salud del emparejamiento en una sola cifra. Es el KPI que mejor
--   correlaciona con retención del cliente.
--   `pct_60s` = tomados en < 60 s / total con tiempo de asignación.
-- Valor malo:
--   · < 40 % → el viaje "se enfría": revisar número de choferes en línea por
--     zona, y si el precio fijo está espantando la oferta.
--   · > 95 % sostenido con poca oferta → probablemente hay pocos viajes y el
--     número no es representativo; mirar `con_tiempo`.
-- ============================================================================
SELECT count(*)                                                             AS con_tiempo,
       count(*) FILTER (
         WHERE extract(epoch FROM (s.aceptada_at - s.created_at)) < 60)      AS en_menos_60s,
       round(100.0 * count(*) FILTER (
         WHERE extract(epoch FROM (s.aceptada_at - s.created_at)) < 60)
         / nullif(count(*), 0), 1)                                          AS pct_60s
  FROM muevete.solicitudes_transporte s
 WHERE s.aceptada_at IS NOT NULL
   AND s.created_at >= now() - interval '30 days';


-- ============================================================================
-- K04 · Cancelaciones por día y motivo
-- ----------------------------------------------------------------------------
-- Qué mide: cuánto se cae la demanda después de publicar, y por qué.
--   `motivo_cancelacion` lo escribe `fn_cancelar_solicitud` (texto libre) o el
--   barrido de TTL (`expirada_ttl`). Las expiradas tienen su propio KPI (K05).
-- Valor malo:
--   · Cancelación > 15 % de lo publicado → fricción: precio percibido alto,
--     espera larga, o el cliente cancela porque no ve choferes.
--   · Predominio de motivos manuales sobre `expirada_ttl` → el cliente se va
--     antes de que el viaje muera: señal de que la lista está vacía.
--   · Cancelaciones con reembolso (`metodo_pago='wallet'`) altas → revisar que
--     `fn_cancelar_solicitud` esté devolviendo el hold (ver test_039_040 T05).
-- ============================================================================
SELECT date_trunc('day', s.cancelada_at)::date                    AS dia,
       coalesce(s.motivo_cancelacion, '(sin motivo)')             AS motivo,
       s.metodo_pago,
       count(*)                                                   AS cancelaciones,
       round(sum(s.precio_plataforma), 2)                         AS valor_no_cobrado
  FROM muevete.solicitudes_transporte s
 WHERE s.estado = 'cancelada'
   AND s.cancelada_at >= now() - interval '30 days'
 GROUP BY 1, 2, 3
 ORDER BY 1 DESC, 4 DESC;


-- ============================================================================
-- K05 · Solicitudes que se quedaron sin chofer (expiradas) por día
-- ----------------------------------------------------------------------------
-- Qué mide: demanda que la oferta no pudo cubrir. Es el KPI de expansión de
--   flota: cada fila es un cliente que se fue sin viaje.
--   Se cuentan las `expirada` (barridas por `fn_crear_solicitud` o por el
--   script de limpieza) MÁS las `pendiente` que ya pasaron su `expires_at` y
--   todavía nadie barrió (si esa columna crece, el barrido no está corriendo).
-- Valor malo:
--   · > 10 % de lo publicado → falta de choferes en esa zona/hora.
--   · `pendiente_vencida` > 0 de forma sostenida → no hay proceso de expiración
--     activo (riesgo de "viajes huérfanos", criterio de aceptación de H8).
-- ============================================================================
SELECT dia, zona, expiradas, pendiente_vencida
  FROM (
    SELECT date_trunc('day', coalesce(s.cancelada_at, s.expires_at))::date AS dia,
           coalesce(z.nombre, 'Fuera de zona')                            AS zona,
           count(*) FILTER (WHERE s.estado = 'expirada')                  AS expiradas,
           count(*) FILTER (WHERE s.estado = 'pendiente'
                              AND s.expires_at <= now())                  AS pendiente_vencida
      FROM muevete.solicitudes_transporte s
      LEFT JOIN muevete.zonas_tarifa z ON z.id = s.zona_id
     WHERE (s.estado = 'expirada'
            OR (s.estado = 'pendiente' AND s.expires_at <= now()))
       AND coalesce(s.cancelada_at, s.expires_at) >= now() - interval '30 days'
     GROUP BY 1, 2
  ) t
 ORDER BY 1 DESC, 2;


-- ============================================================================
-- K06 · Comisión cobrada por día
-- ----------------------------------------------------------------------------
-- Qué mide: el ingreso de la plataforma, y si el % configurado se está
--   aplicando de verdad.
--   · `comision_real`    = precio_plataforma − precio_chofer (lo que quedó
--                          congelado en el viaje; ya incluye el tope).
--   · `comision_teorica` = precio_plataforma × comision_pct / 100.
--   · `desvio_pct`       = diferencia entre ambas, en % de lo teórico.
-- Valor malo:
--   · `desvio_pct` distinto de 0 → el `tope_comision_viaje` está actuando
--     (esperado si es bajo) o alguien tocó `comision_pct` a mitad de día.
--   · `comision_real` = 0 con viajes completados → viajes cerrados por fuera
--     de `fn_completar_viaje` (dinero no cobrado).
--   · Caída brusca de `comision_pct` en el desglose diario → revisar el
--     superadmin de tarifas (cambio no autorizado).
-- ============================================================================
SELECT date_trunc('day', s.completada_at)::date                        AS dia,
       count(*)                                                        AS viajes,
       round(sum(s.precio_plataforma), 2)                              AS facturado_cliente,
       round(sum(s.precio_plataforma - s.precio_chofer), 2)            AS comision_real,
       round(sum(round(s.precio_plataforma * s.comision_pct / 100.0, 2)), 2)
                                                                        AS comision_teorica,
       round(100.0 * (sum(s.precio_plataforma - s.precio_chofer)
                      - sum(round(s.precio_plataforma * s.comision_pct / 100.0, 2)))
             / nullif(sum(round(s.precio_plataforma * s.comision_pct / 100.0, 2)), 0), 1)
                                                                        AS desvio_pct,
       round(avg(s.comision_pct), 2)                                   AS comision_pct_medio
  FROM muevete.solicitudes_transporte s
 WHERE s.estado = 'completada'
   AND s.completada_at >= now() - interval '30 days'
 GROUP BY 1
 ORDER BY 1 DESC;


-- ============================================================================
-- K07 · Deuda pendiente de choferes (`wallet_drivers.balance < 0`) y su total
-- ----------------------------------------------------------------------------
-- Qué mide: cuánto dinero le deben a la plataforma los choferes que trabajan a
--   efectivo (la comisión se descuenta y el saldo queda negativo hasta que una
--   recarga APROBADA lo cubra: `fn_recargar_wallet` sólo deja la transacción
--   `pendiente`). Es riesgo de crédito puro.
-- Valor malo:
--   · `deuda_total` creciendo más rápido que `facturado` → los choferes no
--     están recargando; el tope `limite_deuda_efectivo` los va a bloquear.
--   · Choferes en el tope (`en_tope`) > 10 % → muchos dejarán de ver viajes
--     (`P0023`): subir el tope o empujar recargas. `en_tope` es una
--     aproximación (deuda ≥ `limite_deuda_efectivo`); el bloqueo real de
--     `fn_tomar_viaje` ocurre cuando la comisión del viaje no cabe en
--     saldo + límite, así que el primer bloqueo llega un poco antes.
--   · Un solo chofer con deuda desproporcionada → cobranza individual.
-- ============================================================================
SELECT count(*) FILTER (WHERE w.balance < 0)                          AS choferes_con_deuda,
       round(abs(sum(w.balance) FILTER (WHERE w.balance < 0)), 2)      AS deuda_total,
       round(abs(min(w.balance)), 2)                                   AS deuda_maxima,
       round(abs(avg(w.balance) FILTER (WHERE w.balance < 0)), 2)      AS deuda_media,
       count(*) FILTER (
         WHERE w.balance < 0
           AND abs(w.balance) >= coalesce(
                 (SELECT c.limite_deuda_efectivo
                    FROM muevete.configuracion_tarifas c WHERE c.id = 1), 0))
                                                                       AS en_tope,
       count(*)                                                        AS choferes_con_wallet
  FROM muevete.wallet_drivers w;

-- Detalle por chofer, para cobranza (mismo criterio, ordenado por deuda):
SELECT w.driver_id, d.name, d.telefono, w.balance
  FROM muevete.wallet_drivers w
  LEFT JOIN muevete.drivers d ON d.id = w.driver_id
 WHERE w.balance < 0
 ORDER BY w.balance
 LIMIT 50;


-- ============================================================================
-- K08 · Viajes por tipo de vehículo y ticket promedio
-- ----------------------------------------------------------------------------
-- Qué mide: mezcla de flota y precio medio por tipo. Sirve para decidir si el
--   fijo de 1 500 se sostiene y qué tipo conviene incentivar.
-- Valor malo:
--   · `moto`/`tuktuk` con `ticket_medio` igual al del auto → el multiplicador
--     por tipo no se está aplicando (`multiplicador_tarifa`, 033).
--   · `pct_viajes` de un tipo < 2 % con `pasajeros_max` alto → ese tipo no
--     tiene oferta: revisar el catálogo (`v_catalogo_vehiculos`) y el gate KYC.
--   · `ticket_medio` con desviación estándar enorme (> 2× la media) → mezcla de
--     zonas muy distintas o viajes con espera cobrada; mirar `km_medio`.
-- ============================================================================
SELECT coalesce(vt.nombre, s.tipo_vehiculo, '(sin tipo)')              AS tipo_vehiculo,
       count(*)                                                       AS viajes,
       round(100.0 * count(*) / nullif(sum(count(*)) OVER (), 0), 1)   AS pct_viajes,
       round(avg(s.precio_plataforma), 2)                             AS ticket_medio,
       round(avg(s.precio_chofer), 2)                                 AS neto_chofer_medio,
       round(avg(s.distancia_km)::numeric, 2)                         AS km_medio,
       round(stddev_samp(s.precio_plataforma)::numeric, 2)            AS desv_ticket
  FROM muevete.solicitudes_transporte s
  LEFT JOIN muevete.v_catalogo_vehiculos vt ON vt.id = s.id_tipo_vehiculo
 WHERE s.estado = 'completada'
   AND s.completada_at >= now() - interval '30 days'
 GROUP BY 1
 ORDER BY 2 DESC;


-- ============================================================================
-- ANEXO · Consulta de control del interruptor de corte
-- ----------------------------------------------------------------------------
-- No es un KPI: es lo primero que se mira cuando "no se puede pedir viaje".
--   activo = false → toda `fn_crear_solicitud` responde
--                    P0003 servicio_en_mantenimiento (modo legacy).
-- ============================================================================
SELECT c.id,
       c.taxi_precio_fijo_activo  AS flag_activo,
       c.comision_pct,
       c.recarga_pct,
       c.limite_deuda_efectivo,
       c.permite_deuda,
       c.precio_vigente_desde,
       c.updated_at
  FROM muevete.configuracion_tarifas c
 WHERE c.id = 1;