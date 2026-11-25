# Baseline main pre Fase 1 (G4) — 2026-11-24

Solo lectura. Etiqueta: `pre-m01-fase1-20261124`.
Bloque 1 del pase: aditivo + `_m01` (sin REPLACE de reportes C9–C13/C11).

## Estado previo

| Check | Valor |
|---|---|
| helpers config_tienda | no |
| fn_caja_disponible_para_egreso | no |
| tablas costos | no |
| m01_solicitud | no |
| version_monetaria | no |
| funciones `*_m01` | 0 |

## md5(prosrc) funciones relevantes

| proname | args | md5_prosrc |
|---|---|---|
| fn_actualizar_precio_promedio_recepcion_v2 | p_id_operacion bigint, p_productos jsonb | 304be05435d0a313968ed9e334648b78 |
| fn_apertura_turno_offline | (uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text, timestamptz) | 8c7ddcbfb2dccd447754b2722d5d33af |
| fn_apertura_turno_offline_monedas | … | 5f7d66d28b5984a01fbe0ee8bbe31e8d |
| fn_apertura_turno_offline_usd | … | b7e2a553a3fad1e245a5c33d7f70ecac |
| fn_cambiar_estado_comanda_item_offline | … | ffbb357d8b223c2589fc37d441723b78 |
| fn_cerrar_turno_offline | … | 5ba47aac84e2f8fcac8bffdf67199558 |
| fn_cerrar_turno_offline_monedas | … | a91281921e8f4dd1f7d5bdf8503a5a9c |
| fn_cerrar_turno_offline_usd | … | 0af792230ef1fe89f9936bd284f1e574 |
| fn_desglose_monedas_turno | p_id_turno bigint, p_criterio_resumen boolean | cf1a65e43781e17fd384bf6866cad22c |
| fn_esperado_turno_por_moneda | p_id_turno bigint | 02ee5696eedf6aed4863f617d61d4934 |
| fn_fdi_crear_liquidacion | (10 params) | 33a1495becb59fe933b4a03e9c0f403c |
| fn_listar_entregas_por_fechas_usuario | (4 params timestamptz) | a71db9342efae2687c72c5bb6f84269d |
| fn_listar_ordenes | … | 7b4e85d9d49e234e9e65631856c1d6a6 |
| fn_listar_turnos_admin | … | 32ca6176584c361c08d14b9618af2600 |
| fn_productos_vendidos_por_turno | p_id_turno bigint | ba90b79397056333a7f9056b06d3c44c |
| fn_productos_vendidos_por_turno_v2 | p_id_turno bigint | 5f4d4dc3d738031c7bb70a1f99a59672 |
| fn_registrar_cambio_estado_offline | … | 565daac1a8fdbecbd2faffa8efcacfce |
| fn_registrar_egreso_fondo_caja | … | edf72d771d6eb7ed9680e85b1541016b |
| fn_registrar_egreso_offline | … | 548113889a72572ca1c3c851f21cf174 |
| fn_registrar_egreso_offline_v2 | … | 61c28e3a710d108f34cde390e8b3e275 |
| fn_registrar_pago_venta_offline | … | 85f5e34cf046eb9b042073c6a917e4e6 |
| fn_registrar_venta_offline_v4 | … | 1833dad11bafe28cddd6a67184385ced |
| fn_reporte_ventas_por_turno | … | 0323104c6d4ac18d0ffd071b0d449518 |
| fn_resumen_turno_kpi | … | 992e8b682228b53c4758807e4c932cbc |
| fn_resumen_turno_kpi_corregido | … | 8433258f8f9aa282eb3fe1cdd06fe8a8 |
| fn_resumen_turno_kpi_v2 | … | 59d279ae19442d395976943d672a6b69 |
| fn_resumen_turno_por_id | … | dcaabbff20d14b1fed5623a3ed76460b |
| fn_resumen_turno_por_id_v2 | … | 4c94d1435425d9ead12bb6b3bacfa170 |

No existían al baseline: `fn_config_tienda_puede_*`, `fn_caja_disponible_para_egreso`, `fn_operacion_en_turno`, `fn_operacion_completada`, `fn_turnos_por_moneda`, `fn_reporte_ventas_producto_por_moneda`, `fn_registrar_egreso_fondo_caja_v2`, ninguna `*_m01`.
