El rebalanceo actual (presentaciones_inventario/03_rebalanceo.sql) intenta reunir toda la cantidad en la presentación solicitada y después descontarla. Eso sirve para “abrir una caja y entregar unidades”, pero no para el despacho físico acordado: con Caja ×10, Bulto ×5 y Unidad ×1, una solicitud de 10 Unidades debe entregar 1 Caja cerrada; una de 15 debe entregar 1 Caja + 1 Bulto; y una de 16, al no existir cobertura exacta solo con empaques cerrados, debe consumir las 10 Unidades, entregar 1 Bulto cerrado y abrir otro Bulto para la unidad restante. El saldo final esperado es 2 Cajas + 3 Bultos + 4 Unidades.

La corrección inicial se limita a SQL/Supabase y a las operaciones activas de ventiq_admin_app abiertas desde inventory_screen.dart. ventiq_app y el TPV se migrarán después. Se trabajará directamente en main, sin worktree ni agentes durante la ejecución, preservando los cambios preexistentes en .claude/.

Semántica cerrada

1. La clave de stock es siempre (producto, variante, opción, ubicación, presentación); nunca se mezclan variantes ni ubicaciones.
2. id_presentacion siempre significa app_dat_producto_presentacion.id; si llega NULL, la RPC resuelve la base con fn_presentaciones_producto; nunca se usa el fallback 1.
3. Se compara por equivalente base exacto, pero el ledger y los detalles operativos guardan las presentaciones realmente entregadas.
4. Antes de consumir sueltas se busca una combinación exacta compuesta solo por empaques cerrados mayores, maximizando lexicográficamente los empaques de mayor factor. Ejemplos: 10 → 1 Caja; 15 → 1 Caja + 1 Bulto.
5. Si no existe esa cobertura cerrada exacta: consumir primero saldo propio de la presentación pedida; cubrir exactamente el remanente con empaques cerrados mayores cuando sea posible; luego consumir empaques cerrados sin excederlo, de mayor a menor; y abrir el empaque inmediato superior más pequeño que cubra el último residuo.
6. Pedir una presentación mayor sin saldo propio permite empaquetarla desde presentaciones inferiores, siempre con cantidades físicas enteras y equivalente exacto.
7. Factores adyacentes no divisibles se descomponen sin fracciones artificiales: Caja ×40 → 6 Blíster ×6 + 4 Unidades. Cada conversión debe cumplir equivalente_entradas = equivalente_salidas.
8. Presentaciones no fraccionables solo admiten cantidades enteras. Los factores NUMERIC se escalan a enteros para el solver exacto; una cadena que no pueda conservar el equivalente produce un error de configuración, nunca redondeo.
9. Si el equivalente total no alcanza, las nuevas operaciones admin fallan atómicamente; no respetan stock negativo.
10. Recepciones y conteos físicos completos registran exactamente lo declarado y no rebalancean.

Implementación recomendada

1. Persistir solicitud lógica y cumplimiento físico

Crear presentaciones_inventario/35_cumplimiento_fisico_v2.sql con tablas nuevas:

- app_dat_solicitud_inventario: UUID idempotente, flujo, tienda/usuario, hash canónico del payload, estado, operación creada, respuesta final y posible solicitud revertida.
- app_dat_solicitud_inventario_linea: producto/variante/opción/ubicación, presentación y cantidad solicitadas, factor congelado y equivalente; client_line_uuid único por solicitud.
- app_dat_cumplimiento_inventario_linea: presentación/cantidad físicas, factor y equivalente congelados, origen (propio, empaque_cerrado, apertura, empaquetado) y referencias al detalle de extracción/recepción.
- app_dat_conversion_presentacion_evento y ..._pata: conversiones N→N capaces de representar Caja ×40 → 6 Blíster + 4 Unidades; agregar referencia nullable al evento nuevo en el ledger y conservar id_conversion para el histórico.

Las tablas nacen con RLS habilitado, sin acceso directo de anon/authenticated. Los RPC públicos revocan PUBLIC/anon, conceden solo a authenticated/service_role, validan auth.uid(), tienda y ubicaciones, y fijan search_path = ''. No habilitar RLS masivamente en las 104 tablas antiguas señaladas por Supabase: sin políticas compatibles rompería la aplicación; abrir esa remediación como trabajo separado.

2. Núcleo v2 sin romper funciones vivas

En el mismo archivo crear:

- fn_presentaciones_producto_v2: factores exactos respecto de base y validación de catálogo; no usa factor_hijo redondeado como cantidad física.
- fn_planificar_cumplimiento_presentaciones_v2: planificador puro; devuelve líneas físicas, conversiones y saldos proyectados.
- fn_preview_cumplimiento_presentaciones_v2: preview pública basada en el mismo planificador, evitando la divergencia actual entre preview y escritura.
- fn_registrar_conversion_presentacion_v2: registra evento y patas N→N y verifica neutralidad exacta.
- fn_aplicar_cumplimiento_presentaciones_v2: aplica un plan, crea detalles físicos y ledger, y persiste la respuesta.
- fn_revertir_solicitud_inventario_v2: movimientos compensatorios enlazados; nunca borra ledger ni reconstruye historia.

No modificar inicialmente fn_rebalancear_presentaciones, fn_descontar_con_rebalanceo, fn_preview_rebalanceo ni las RPC originales: siguen atendiendo a ventiq_app/TPV y builds antiguos.

3. Concurrencia, atomicidad e idempotencia

- Adquirir pg_advisory_xact_lock por cada clave completa de stock, en orden canónico, antes de planificar; esto cubre también claves sin fila previa.
- Releer el último snapshot bajo lock, planificar todas las líneas y solo entonces escribir.
- Una RPC engloba solicitud, conversiones, detalles, ledger, estados y vínculos; cualquier error lanza excepción y revierte todo.
- Verificar al final: no negativos, equivalencia antes − salidas = después y neutralidad de conversiones.
- Repetir UUID + mismo hash devuelve la respuesta guardada; UUID + payload distinto devuelve IDEMPOTENCY_KEY_REUSED.
- Cancelaciones/reducciones generan movimientos compensatorios en orden inverso. No reempaquetar automáticamente un paquete abierto durante una reversión.

4. RPC v2/v3 para operaciones admin

Crear presentaciones_inventario/36_callers_admin_cumplimiento_v2.sql:

- fn_crear_extraccion_con_movimiento_v2: persiste solicitud lógica, crea una app_dat_extraccion_productos por línea física y completa el estado dentro de la misma RPC.
- fn_transferir_inventario_entre_layouts_v2: planifica/aplica origen primero y construye la recepción exclusivamente desde las líneas físicas. Solicitud 10 Unidades cumplida por 1 Caja produce extracción y recepción de 1 Caja.
- fn_registrar_venta_v3 para Venta por Acuerdo solamente: conserva la lógica financiera/receta de la función viva, pero el SKU de barra usa el ejecutor v2. Distribuye el importe lógico proporcionalmente por equivalente entre líneas físicas y asigna cualquier residuo monetario a la última línea.
- fn_insertar_ajuste_inventario_v3 con modos explícitos: delta (positivo ingresa exacto; negativo usa cumplimiento físico) y conteo_fisico (setea cada presentación sin conversiones). Recibe todas las líneas de una sesión en una llamada.
- fn_consignacion_reservar_v2, fn_consignacion_actualizar_reserva_v2 y fn_consignacion_cancelar_reserva_v2: reemplazan las escrituras/borrados directos desde Flutter; aumentos cumplen el delta y reducciones/cancelaciones compensan historial sin DELETE.
- Para elaborados admin, consolidar todos los ingredientes y resolver su presentación base; enviarlos juntos a extracción v2. Si falta uno, falla toda la extracción, sin procesar subconjuntos.

5. Migrar ventiq_admin_app

Modificar los servicios/modelos para generar un UUID estable por intento y consumir las respuestas con varias líneas físicas:

- ventiq_admin_app/lib/services/inventory_service.dart: extracción, transferencia, ajuste y elaborados apuntan a las nuevas RPC.
- inventory_extraction_screen.dart: eliminar idPresentacion ?? 1, enviar NULL o vínculo válido y quitar el segundo completeOperation no atómico.
- inventory_transfer_screen.dart: mantener el payload lógico, añadir idempotencia y mostrar el desglose físico devuelto.
- inventory_adjustment_screen.dart: enviar toda la sesión en una única llamada v3; exceso usa delta, faltante ingresa exacto.
- inventory_extractionbysale_screen.dart: migrar solo Venta por Acuerdo a fn_registrar_venta_v3 y eliminar todos los ?? 1; no tocar el TPV.
- elaborated_products_extraction_screen.dart/servicio: una extracción atómica de todos los ingredientes.
- asignar_productos_consignacion_screen.dart y servicios de consignación: mantener borrador local y reemplazar INSERT/UPDATE/DELETE directos sobre inventario/extracción por RPC de reservar/actualizar/cancelar.

Actualizar docs/PLAN_PRESENTACIONES_INVENTARIO.md con la nueva semántica, el contrato solicitud/cumplimiento y el estado real de cada flujo.

Verificación

Crear presentaciones_inventario/37_tests_cumplimiento_fisico_v2.sql, siempre con BEGIN/ROLLBACK, que cubra:

1. Stock 2 Caja ×10 + 5 Bulto ×5 + 10 Unidad: pedidos 10 → 1 Caja; 15 → 1 Caja+1 Bulto; 16 → 1 Bulto+11 Unidades y saldo 2/3/4.
2. Solver no greedy: factores 10 y 6, pedido 12 → 2 empaques ×6.
3. Caja ×40 / Blíster ×6 / Unidad ×1 → 6 Blíster +4 Unidad, patas enteras y equivalencia 40.
4. Empaquetado desde inferiores; fracciones válidas e inválidas; producto de una presentación.
5. Aislamiento de variantes/opciones/ubicaciones y ausencia de saldos negativos.
6. Transferencia: destino idéntico al cumplimiento físico del origen.
7. Venta por acuerdo: detalle físico e importe total cuadran con solicitud lógica.
8. Ajuste positivo, negativo con múltiples líneas y conteo físico sin conversiones.
9. Consignación crear/aumentar/reducir/cancelar sin borrar ledger.
10. Idempotencia, payload distinto, fallo inducido intermedio y dos sesiones concurrentes sobre el mismo saldo.
11. NULL resuelve base; ID nominal/ajeno falla; funciones originales conservan firma, cuerpo y permisos.

Después del SQL local: aplicar 35/36 únicamente mediante Supabase MCP, ejecutar 37 por MCP dentro de rollback, comprobar ACL/RLS y correr advisors de seguridad/rendimiento. Luego migrar Dart y ejecutar dart format --output=none --set-exit-if-changed, flutter analyze, flutter test y smoke manual desde todas las opciones pertinentes de inventory_screen.dart.

Orden de despliegue

1. Recapturar con MCP firmas, ACL, propietarios, dependencias, índices y huellas md5 vivas.
2. Implementar/revisar 35–37 localmente en main, preservando .claude/settings.local.json y .claude/worktrees/.
3. Aplicar tablas, núcleo y RPC v2/v3 compatibles por Supabase MCP; ejecutar tests transaccionales y advisors.
4. Verificar que las funciones originales no cambiaron.
5. Migrar y validar ventiq_admin_app; desplegar el admin.
6. Observar errores de stock, claves idempotentes y divergencias de equivalencia. Rollback de app = build anterior, porque las RPC viejas siguen disponibles.
7. Solo después de estabilizar admin, diseñar una migración separada de ventiq_app/TPV al mismo núcleo.