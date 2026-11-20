# Referencia multimoneda: intención confirmada y plan preliminar

- Fecha de creación: 2026-11-13.
- Última actualización: 2026-11-19. El párrafo de «Estado» que sigue es histórico (llega hasta el script 47 y dice que el flag sigue apagado). Lo vigente está en «Estado al 2026-11-19 — cambios desde la redacción», justo debajo.
- Estado: contrato de venta, plan técnico y desglose MC aprobados; MC-001–MC-004 completados y REP aprobada. MC-005 cerrada el 2026-11-14 por orden del usuario. En newa el usuario aplicó los scripts 1–24. El harness de rol pasó en una sesión: vendedor de otra tienda, escalación y replay secuencial, con ROLLBACK. No se probó la carrera de dos sesiones ni el anónimo; newa no tiene superadmin inactivo. Los cortes R0h de Admin Lite quedan fuera. MC-006 a MC-011 quedaron aplicadas en newa. MC-012 a MC-015 y MC-018 a MC-021 están en el cliente. Los scripts 32 a 38 quedaron aplicados en newa. MC-029 a MC-033 leen la política sin encenderla: el flag sigue apagado y una caché incompleta bloquea la orden nueva. MC-034 a MC-038 están en el cliente: el cobro nuevo agrupa netos ya fijados, el envío guarda la clave y no cae al registro anterior, y el script 39 quedó aplicado en newa: la guarda existe, solo actúa al insertar y el flag sigue apagado. MC-039 a MC-046 quedaron en el cliente y el usuario aplicó los scripts 40 a 44 en newa. La lectura de catálogo devuelve las funciones, el RLS de las tablas nuevas y el flag apagado. el usuario aplicó los scripts 45 y 46: anon ya no ejecuta esas funciones y la comanda queda solo en cocina al pedido. MC-049 a MC-051 quedaron en la decisión local y en la lectura de newa: el flag sigue apagado, no hay venta v1 aceptada, no hay autorización para encender una tienda y no hay ticket físico. MC-016 de Admin Lite queda fuera. MC-017 y main siguen cerrados. El script 47 está para pegar y no está aplicado: no enciende ninguna tienda. El detalle del vendedor elige CUP o USD cuando la tienda lo tiene activo y rechaza la moneda sin precio configurado. S01 de configuración ya estaba aplicado.
- Apps implicadas en el alcance inmediato: `ventiq_app`, configuración de tienda en `ventiq_admin_app` y persistencia/RPC en Supabase.

## Estado al 2026-11-19 — cambios desde la redacción

Medido el 2026-11-19 con consultas de solo lectura a newa (`qhprswhhfasrikhawjoz`) y main (`vsieeihstajlrdvpuooh`), y con la suite local de las dos apps. Este bloque corrige lo que el resto del documento daba por cierto cuando se escribió (13–16/11). El contrato funcional de abajo no cambió; cambió el estado del trabajo y el destino.

### Qué es distinto respecto al texto original

| Tema | Lo que decía el plan | Estado al 19/11 |
|---|---|---|
| Promoción a main | «No queda autorizada»; exigía su propia comparación | La comparación está hecha y documentada: `docs/plan-multimoneda/desincronizacion_newa_main.md`, `comparacion_funciones_newa_main.md` (81 funciones con cuerpo distinto), `analisis_8_funciones_pendientes.md` y `tasks/plan_sync_newa_main.md`. Main no tiene nada de M01: 0 funciones `fn_m01_*`, sin `version_monetaria`, sin el flag, y `app_dat_configuracion_tienda` y `app_dat_precio_tpv` siguen con RLS apagado. La aprobación para aplicar en main sigue siendo del usuario |
| Scripts M01 | 1–47; el 47 «para pegar» | 1–56. Verificado en newa: existen `reporte_ordenes_json_v2` (54), `fn_reporte_ventas_por_moneda_v2` (55), `fn_turno_alinear_fecha_apertura` y `fn_alinear_apertura_turno_offline` (56) y `fn_m01_fijar_moneda_por_producto` con la exclusión flag/forzada (53). Hay 79 funciones `fn_m01_*` |
| Flag y ventas v1 | «El flag sigue apagado, no hay venta v1 aceptada» | `permitir_moneda_por_producto` está encendido en 1 de las 3 tiendas de newa (piloto) y hay 9 operaciones con `version_monetaria`. El resto de tiendas sigue apagado y main no tiene la columna |
| Zona horaria de newa | `TimeZone = UTC` (evidencia del 13/11) | `America/Havana`, igual que main. La evidencia de MC-001 queda como histórica. El cliente ya no depende de eso: manda la hora corregida con `ServerTimeService` |
| RLS de precios por TPV | `app_dat_precio_tpv` sin RLS en newa | Con RLS activo en newa (M01 29–31). En main sigue apagado |
| Turnos offline | No existía en el plan | R33: script 56 (aplicado en newa) y cliente D1–D7 (commit `337c2920`). Ver abajo |
| Defecto de `fn_listar_ordenes` | Script 52 aplicado | Llevaba `'tipo_paago'` en vez de `'tipo_pago'`: el TPV lee `payment['tipo_pago']` (`orders_screen.dart`) y en newa los pagos recargados perdían el tipo. Corregido en la fuente (`m01_r29_listar_ordenes_v1_propuesta.sql`) y con parche para newa: `sql_updates/fix_listar_ordenes_tipo_pago.sql`. **Pendiente de correr en newa** |

### Qué se decidió el 19/11 para el pase (81 funciones)

- 21 funciones donde newa está más nueva viajan a main (las M01 offline con idempotencia, `auth.uid()` y lock por clave, entre otras). Antes hay que correr el parche de `tipo_pago`.
- 42 no tienen cambio lógico y se ignoran (incluidas `get_detalle_producto` y `get_detalles_productos_batch`: la vista `app_v_precio_venta_base_vigente` ya filtra la variante base en las dos bases).
- 16 donde main está más nueva se traen a newa. Cuatro ya están (hash idéntico al de main): `fn_dashboard_carnaval_proveedor`, `fn_stock_producto_almacen_detalle`, `fn_stock_saldos_presentacion`, `fn_reporte_ventas_con_proveedor_por_turno`, con el índice parcial `idx_inv_prod_lote_producto`. Faltan en newa (cinco recomprobadas el 19/11) `fn_check_update`, `fn_listar_motivos_extraccion`, `fn_update_carnaval_product_prices`, `sync_price_to_carnaval`, las siete `get_productos_completos_by_tienda_*` y `buscar_producto_por_codigo_barras_v3` (main manda: `ORDER BY id DESC`, regla de `AGENTS.md`).
- Dos se combinaron a mano y ya están aplicadas **en newa** (verificado por `prosrc`); **ninguna en main**:
  - `fn_reporte_ventas_por_turno` (`sql_updates/fix_reporte_ventas_por_turno_sin_cierre.sql`): manda el criterio de main (rango de ids de operación) y se le añade el de newa para turnos sin `id_operacion_cierre`: fecha de cierre, o `now()` si sigue abierto, y nunca más allá de la siguiente apertura del mismo TPV y vendedor. Motivo: en main, 32 turnos cerrados sin `id_operacion_cierre` arrastraban 56 228 ventas en vez de 681.
  - `fn_registrar_cambio_estado_operacion_mejorado` (`sql_updates/fix_cambio_estado_operacion_mejorado_recepcion.sql`): conserva de main la lógica de completar recepción y de newa el flag `cambiar_fecha_creacion_operacion_al_cierre`. Cancelar o devolver una recepción ya no borra filas de inventario: si ningún producto se movió, devuelve la cantidad con un movimiento compensatorio (`origen_cambio` 4 devolución, 5 cancelación); si alguno ya se usó, no cancela nada y devuelve `error_code = 'RECEPCION_INVENTARIO_USADO'` con `productos_con_problema` (producto, recibido, saldo actual, motivo). Admin muestra el aviso (`inventory_operations_screen.dart`) y manda `p_uuid_usuario`. No revierte costos (precio promedio, `costo_real`).
- Las 7 firmas que solo existen en main: las tres sobrecargas viejas de contabilización de órdenes se retiran (newa ya las quitó con `newa_contabilizacion_firmas.sql`; en main hay que dejar solo `fn_actualizar_operacion_contabilizada(bigint, boolean, bigint)` y las de info e historial con `id_tienda`, y revocar `anon`); `fn_desvincular_usuario_trabajador` queda sustituida por `fn_m01_personal_desvincular_usuario_trabajador` (el cliente la llama primero y no borra los roles); `fn_fdi_crear_liquidacion` debe quedar con la firma de 11 parámetros porque Admin siempre manda `p_repartir_igual`; `fn_trg_bloquear_operaciones_usuario` y su trigger `trg_bloquear_operaciones_maria` son solo de main y se conservan; `match_ai_kb` es la misma función con el tipo `vector` calificado.

### R33 — ventas offline fuera de su turno

La causa de fondo es la pertenencia de una venta a un turno: main usa el rango de ids de operación, newa la ventana por fecha. El script 56 recupera la hora real de apertura al reutilizar o repetir un turno (`fn_turno_alinear_fecha_apertura`: solo hacia atrás, tope 72 h, sin pisar el turno anterior) y el cliente guarda la apertura más temprana (`aperturaMasTemprana`), conserva las órdenes sincronizadas del turno abierto hasta el cierre y no pisa `created_offline_at`. Diagnóstico en `docs/issues/ventas_offline_desaparecen_tras_sync.md`; orden de despliegue en `m01_orden_aplicacion.md`. Main no tiene `fn_turno_alinear_fecha_apertura` todavía.

### Validación del 19/11

- `ventiq_admin_app`: suite completa, 344 pasan y 1 falla (`widget_test.dart`, la plantilla de contador de Flutter, ajena a esta feature). El test nuevo `sync_newa_main_sql_contract_test.dart` añade 15 casos y pasan (contrato de los scripts de recepción, turno, funciones traídas de main y `tipo_pago`, más el aviso de Admin).
- `ventiq_app`: suite completa, 594 pasan y 2 fallaron: `widget_test.dart` (la misma plantilla, sin Supabase inicializado) y `session_refresh_service_test.dart` «un 429 no dispara login con contraseña y conserva un JWT vigente». **El segundo se resolvió el 20/11** (ver abajo); queda solo la plantilla.
- Causa del 429: no tenía relación con moneda. `pubspec.lock` no se versiona y el entorno había subido a `supabase_flutter` 2.16.0 / gotrue 2.26.0. Con esa versión un 429 en el refresh hace que el SDK cierre la sesión y emita `signedOut` con `signOutReason = sessionExpired`, aunque el JWT siga vigente. `SessionRefreshService` deducía el motivo por la expiración del token y lo tomaba por un cierre explícito, así que no restauraba la sesión. Arreglo: `_motivoSignOut` usa `event.signOutReason` (`userInitiated` → explícito, `sessionExpired`, `sessionMissing`) y deja la deducción solo como respaldo; `ventiq_app/pubspec.yaml` exige `supabase_flutter: ^2.16.0`, que trae gotrue 2.26. Los 11 casos del test y `app_compile_test.dart` pasan.
- Los tests de contrato SQL inspeccionan el archivo. Comprobaciones adicionales: el cuerpo de `fn_registrar_cambio_estado_operacion_mejorado` se probó en newa con una transacción que se revierte; el criterio de turnos se contrastó con SELECT de solo lectura sobre datos de main; las cuatro funciones traídas tienen el mismo hash que en main; el parche de `tipo_pago` se probó en newa con una transacción revertida (sin typo restante, `SECURITY DEFINER` y `search_path` intactos). Nada de esto sustituye una venta real, la sincronización contra main ni la impresión del ticket.

### Antes de llevar M01 a main

1. Correr `fix_listar_ordenes_tipo_pago.sql` en newa.
2. Regenerar los baselines `md5` de los preflight de los scripts 14, 17 y 56: los actuales son de newa y el hotfix de main cambia esos cuerpos.
3. Traer a newa las 12 funciones de main que faltan y aplicar en main, en este orden: contabilización, `fn_reporte_ventas_por_turno`, `fn_registrar_cambio_estado_operacion_mejorado` (probar primero con una recepción completada y sin uso), firma de 11 parámetros de `fn_fdi_crear_liquidacion` y después M01.
4. No copiar al revés lo que solo main tiene: WhatsApp, referidos, versiones de app, precios Carnaval, `egresos_por_turno`, el trigger de `maria` y los crons de main.
5. Verificar en main online, offline con caché fresca y offline con caché vacía antes de dar la feature por lista, como exige la regla de sincronización del repo.

## Intención confirmada — contrato funcional vigente

### Ajuste de alcance confirmado — Admin Lite del vendedor (2026-11-14)

El usuario indicó ignorar Admin Lite en `ventiq_app` porque se va a retirar. No continuar endureciendo sus handlers/fallbacks ni sus RPC exclusivas como parte de esta feature; sus cortes R0h y harness ya preparados quedan como antecedentes, no como requisito de terminación del TPV normal. Esta instrucción no autoriza borrar código, revertir cambios anteriores ni aplicar SQL. Reorientar MC-005 al registro/cobro/sync del vendedor normal y a las fuentes compartidas de roles, tienda/TPV e idempotencia que esos flujos realmente consumen. No excluir controles compartidos solo porque también los use Admin Lite. Antes de liberar M01, revisar el orden y las dependencias para no aplicar incidentalmente los cortes exclusivos de Admin Lite ni dejar entradas privilegiadas activas que eludan los controles compartidos; su retirada/cierre necesita revisión y autorización propias. Este ajuste prevalece sobre los siguientes pasos anteriores que proponían seguir con otras entradas Admin Lite.

Esta sección recoge las decisiones explícitas de la entrevista posterior al borrador de reportes. Sustituye el alcance inmediato y cualquier supuesto incompatible del borrador histórico incluido más abajo. Las secciones numeradas 1–13 son antecedentes de la propuesta inicial de reportes, no tareas aprobadas ni instrucciones vigentes de implementación.

### Flag y selección en el vendedor

1. Añadir un flag por tienda, apagado por defecto, que habilita la selección de moneda en el detalle del producto. El nombre técnico queda para la spec.
2. Con el flag apagado se conserva exactamente el comportamiento actual, incluida la distribución de pagos del checkout.
3. Con el flag encendido se añade la moneda junto al medio de pago que ya se maneja en el detalle. No se crea ni sustituye la gestión actual de medios de pago.
4. Cada línea tiene una moneda y un medio de pago para toda su cantidad; no se divide una misma línea entre combinaciones distintas.
5. Si la tienda fuerza una moneda, solo se permite esa. Sin moneda forzada, el vendedor elige entre las habilitadas y con precio disponible.
6. CUP usa el precio CUP propio y USD usa el precio USD propio. No se convierten entre sí para sustituir esos precios. Si falta el precio seleccionado, se bloquea esa selección; si es la moneda forzada, se bloquea la venta de esa línea hasta disponer de precio válido.
7. El alcance inmediato es CUP y USD. Para otras monedas se requerirían tasas configuradas desde superadmin; las reglas completas deben especificarse antes de habilitarlas.

### Checkout y producto repetido

8. Con el flag encendido, el checkout agrupa y respeta los importes seleccionados en los detalles por moneda y medio. No permite redistribuir libremente esas selecciones; para cambiarlas se vuelve al detalle.
9. Si se añade el mismo producto con distinta moneda o medio, se informa la diferencia y se solicita confirmación: mantener líneas separadas o unirlas.
10. Al unirlas, el vendedor selecciona explícitamente la combinación final para toda la cantidad, ve el importe usando el precio propio de esa moneda y confirma. No se elige automáticamente ni se convierte el precio anterior.

### Persistencia, equivalente contable y reportes

11. La trazabilidad nueva aplica a ventas nuevas. No reconstruir ni atribuir por suposición moneda/medio a detalles históricos.
12. Conservar por detalle la moneda, medio, precio e importe nativos utilizados y su información contable de conversión. Los nombres y tipos definitivos se definirán tras trazar los consumidores actuales.
13. Decisión final confirmada por el usuario: guardar también la tasa histórica aplicada y el equivalente CUP de cada detalle, separado del importe nativo. Por ejemplo, 5 USD conserva 5 USD; su equivalente CUP es otro dato.
14. El equivalente contable no cambia el precio propio ni el cobro nativo y no debe exigir que el precio USD propio coincida con el precio CUP propio del catálogo. La validación de pago debe respetar lo adeudado por moneda.
15. Los totales nativos se muestran por moneda; no sumar CUP y USD como una sola magnitud.
16. El detalle se tendrá en cuenta en las funciones de reporte. No añadir por ahora su nuevo desglose visual a los reportes. La ampliación general del admin descrita en el borrador queda diferida.
17. Conservar el registro de pagos de la orden; el detalle por producto aporta trazabilidad y no sustituye el registro de cobro efectivo.
18. Cambio de configuración con orden iniciada o pendiente offline: conserva la modalidad y las condiciones monetarias ya seleccionadas. Un cambio posterior de flag o moneda forzada se aplica a órdenes nuevas, no convierte ni redistribuye silenciosamente la existente al sincronizar. No reinterpretar los precios, monedas, medios y tasas persistidos con la configuración más reciente.
19. Si no hay una tasa USD→CUP válida disponible online ni en caché, bloquear la venta nueva de la línea en USD aunque tenga precio USD propio. No inventar tasas ni convertir el precio CUP para sustituirlo. CUP puede continuar si las demás reglas de tienda lo permiten; si la tienda fuerza USD no se habilita CUP como fallback. Los detalles pendientes con tasa histórica válida conservan ese snapshot al sincronizar.

### Promociones automáticas — reglas confirmadas

- Porcentajes sobre el precio propio de la moneda elegida, respetando las condiciones de medio y cantidad existentes.
- Descuentos y recargos fijos con importes independientes por moneda, sin conversiones entre ellos.
- Si falta importe fijo para una moneda, no aplicar esa promoción e informar al vendedor; no bloquear por ello una venta con precio y tasa válidos.
- Decisión posterior del usuario: los descuentos se manejan sobre el detalle del producto en la modalidad nueva. Sustituye la propuesta anterior de descuento manual global por moneda; no se aprobó reparto proporcional ni registro como gasto operativo.
- Cada descuento manual se vincula a una línea concreta y usa su moneda, conservando el medio de pago. No identificar solo por producto: puede repetirse con distintas combinaciones. Conservar bruto, descuento y neto para explicar el cobro real.
- Fijo manual confirmado por unidad de la línea: 3 unidades a 100 CUP con descuento de 10 CUP por unidad dejan 90 CUP unitarios, descuento total de 30 CUP y neto de 270 CUP. El descuento total deriva de la cantidad vendida; no aplicarlo una sola vez al subtotal ni confundir presentación vendida con unidades base de inventario.
- Redondeo confirmado para la modalidad nueva: conservar precisión durante cálculo unitario y multiplicación por cantidad; redondear neto final de línea CUP/USD a dos decimales al más cercano, con empate half-up, y sumar los netos fijados por moneda/medio. Ejemplo: 3 × 1,05 USD con 10% → 2,835 USD → 2,84 USD; no redondear cada unidad para cobrar 2,85.
- El flujo legacy, su redondeo y sus descuentos históricos no se reinterpretan. La precisión contable y de tasas se concretará aparte.

### Precios específicos por TPV — ampliación confirmada

- Los precios específicos también serán multimoneda, ampliando la configuración existente para CUP/USD con importes propios independientes.
- Cada moneda puede tener precio específico o heredar el general de esa misma moneda. Vacío significa herencia, no cero ni conversión.
- La resolución es por moneda: específico vigente TPV → general vigente aplicable al producto/variante → selección bloqueada si ninguno existe.
- Debe informarse al menos un precio específico positivo por registro; para heredar ambos se desactiva la configuración específica. Los registros CUP existentes no generan un precio USD por conversión.
- Una configuración vigente nueva con USD vacío no rescata un específico USD anterior: hereda el general USD. Mantener resolución determinista por vigencia y fecha del servidor.
- Integrar ambos precios y su procedencia en admin, vendedor y pipeline de sync existente; no crear un catálogo offline paralelo ni recalcular órdenes iniciadas o ventas históricas.
- En newa se comprobó que app_dat_precio_tpv tiene RLS desactivado, sin policies. Su ampliación debe proteger lectura por acceso a tienda y escritura administrativa, validando pertenencia de producto y TPV. Esta protección no se ejecutó todavía.
- Esta ampliación es requisito previo del contrato de venta; queda por planificar dentro del mapa aprobado, sin autorizar implementación ni alterar silenciosamente sus módulos.

### Evidencia remota comprobada en main durante la entrevista

Inspección realizada mediante MCP `supabase-main`, solo lectura. No se aplicaron cambios.

- `app_dat_extraccion_productos` tiene ID propio, operación, producto, variante, presentación, ubicación, lote, cantidad, precio unitario e importes. No tiene moneda, medio de pago, tasa ni equivalente CUP por detalle.
- `app_dat_pago_venta` guarda moneda, medio, monto, tasas y equivalente CUP, pero se vincula a la venta y no directamente al detalle de extracción.
- `app_dat_extraccion_productos` y `app_dat_pago_venta` tienen RLS activado. Esta comprobación no equivale a una auditoría completa de sus policies.
- Los índices inspeccionados no imponen unicidad por producto dentro de una operación. No se encontraron triggers no internos sobre la tabla de extracciones.
- `fn_agregar_producto_orden_pendiente_v2` fusiona automáticamente por operación, producto, variante y ubicación, sin comparar moneda ni medio. Debe revisarse para respetar la confirmación explícita y conservar líneas distintas.
- `fn_registrar_venta_v3_impl` inserta el detalle y suma cantidad por precio unitario a un total único. La función de agregar pendientes también suma importes sin distinguir monedas. No introducir importes nativos mixtos en esos campos sin resolver su compatibilidad.
- La tabla de extracciones también sirve para operaciones no comerciales: no exigir medio de pago en todas las extracciones ni alterar su semántica global.
- La tabla es candidata viable para ampliar el detalle, pero el diseño definitivo exige revisar RPC, cantidades/presentaciones, descuentos, inventario, reportes y sincronización offline. No se ha aprobado DDL específico.

### Siguiente etapa y límites

Preparar un mapa de capacidades revisado que empiece por configuración del flag, detalle de venta y persistencia/sync, antes del trabajo visual del admin. Someter ese mapa y las specs correspondientes a revisión antes de implementar.

La preparación offline debe reutilizar el pipeline existente, cachear el nuevo flag y conservar selección, precios y tasa históricos en pendientes/sincronización. El detalle del contrato y sus pruebas se fijará en la spec, sin activar comportamiento nuevo al recibir configuración ausente.

Fuera del alcance inmediato: reconstrucción histórica, división de una línea entre varias monedas/medios, cambios de precios de catálogo, habilitación de otras monedas sin reglas aprobadas y nuevos desgloses visuales generales de reportes.

## Mapa revisado de capacidades — aprobado

Estado: mapa de tres capacidades y contrato consolidado de venta aprobados explícitamente por el usuario. La aprobación incluye secciones 0.1–0.3 y secuencia de sección 14 de SPEC-product-currency-sale.md: contabilidad CUP separada de nativos, revisiones/constancias offline bajo la ventana existente con revisión de envíos tardíos, y cobertura de preorden/mesa/cocina/CxC con medio diferido en pendientes. Autoriza preparar el plan técnico detallado, no implementar ni ejecutar DDL. El usuario aprobó el plan técnico, el desglose MC-xxx y el inicio del primer lote MC-001–MC-003. Su estado y evidencia se registran más abajo; SQL de escritura, spec de reportes y activación conservan sus puertas específicas. La spec de reportes está aprobada en REP en tasks/SPEC-product-currency-report-contracts.md. Esto permite detallar/revisar tareas MC-045/M06; implementación, SQL de escritura y activación siguen sujetos a sus dependencias y puertas. El endurecimiento S01 de configuración se ejecutó por separado en newa.

S01: el usuario autorizó incluir endurecimiento de `app_dat_configuracion_tienda`. Se documentó el impacto en la primera spec y se prepararon `docs/plan-multimoneda/configuracion_tienda_rls_propuesta.sql` y `docs/plan-multimoneda/verificar_configuracion_tienda_rls.sql`. La propuesta cubre RLS, grants y guardas de `sync_bundle`, licencia firmada y consolidación; no basta proteger solo el acceso directo a tabla. Newa fue confirmado por el usuario como entorno de pruebas y su compatibilidad se contrastó mediante SELECT: tabla/roles compatibles, dos RPC idénticas y una versión revisada de consolidación con distinta huella. Newa es la referencia de desarrollo: la propuesta toma exclusivamente sus versiones actuales y preserva sus avances. Las diferencias respecto a main son esperables; la promoción a main requerirá comparación y migración específicas después de validar en newa. El usuario ejecuta desde SQL Editor; instrucciones en la primera spec, sin requerir psql. Estado actualizado: el usuario ejecutó ambos SQL en newa desde SQL Editor; el agente confirmó por MCP las seis comprobaciones de catálogo en true, las cuatro policies y los helpers esperados. Endurecimiento aplicado en newa; flag todavía inexistente. Pendiente: pruebas funcionales de vendedor/gerente y aislamiento entre tiendas antes de solicitar promoción a main. El agente no ejecutó escrituras remotas y no se modificó código Dart ni main.

| Module id | Responsabilidad y resultado verificable | Depende de | Spec prevista |
|---|---|---|---|
| `store-product-currency-policy` | Configurar el flag por tienda con permisos; descargarlo y cachearlo en el pipeline existente; exponer una política consistente con moneda forzada y monedas habilitadas, sin activar el modo por ausencia de configuración. | — | `tasks/SPEC-store-product-currency-policy.md` |
| `product-currency-sale` | Venta completa con moneda por detalle: precio propio, medio existente, duplicados confirmados, checkout restringido, snapshot nativo/contable, persistencia online/offline, pendientes y reintentos. | `store-product-currency-policy` | `tasks/SPEC-product-currency-sale.md` |
| `product-currency-report-contracts` | Adaptar funciones de reporte para consumir detalles nuevos sin sumar monedas nativas incompatibles, duplicar cobros ni atribuir datos falsos a históricos. Sin nuevas vistas de desglose en el admin. | `product-currency-sale` | `tasks/SPEC-product-currency-report-contracts.md` |

Orden de construcción: `store-product-currency-policy` → `product-currency-sale` → `product-currency-report-contracts`.

El segundo módulo incluye detalle, checkout, BD y sincronización porque forman una sola capacidad: conservar el acuerdo de venta por producto de extremo a extremo. Separarlos en módulos con contratos independientes produciría dependencias circulares. Su plan se dividirá en tareas pequeñas y cortes verticales, no en una implementación masiva.

### Fronteras y contratos a especificar

#### Proveedor: `store-product-currency-policy`

- Entrega al flujo de venta una política asociada a la tienda: modo por producto activo/inactivo, moneda forzada si existe y monedas habilitadas.
- Distingue configuración ausente de política conocida; ausencia del nuevo flag nunca activa la modalidad nueva.
- Integra la caché y preparación offline existentes. Debe probar online, offline con caché fresco y offline con caché vacío/stale.
- La spec resolverá cómo se fija la política de una orden y qué sucede si cambia durante su edición o antes de sincronizar. No reinterpretar una orden pendiente usando silenciosamente una política distinta.

#### Proveedor: `product-currency-sale`

- Consume la política y conserva el medio de pago actual del detalle, añadiendo moneda, precio/importe nativo y snapshot de tasa/equivalente CUP.
- Expone identidad estable del detalle y un discriminador verificable para distinguir ventas nuevas de modalidad por producto frente al flujo legacy. Nombres de campos y mecanismo exacto pendientes de spec.
- Deriva el cobro agrupando por moneda y medio en modo activo; modo inactivo conserva el editor y contratos existentes.
- Define persistencia y lectura compatibles en `app_dat_extraccion_productos` sin redefinir silenciosamente campos usados por inventario y reportes. La elección de columnas concretas requiere trazar primero sus consumidores.
- Valida lo adeudado en moneda nativa, sin comparar el precio propio USD con el precio CUP de catálogo para decidir si está pagado.
- Incluye órdenes normales, pendientes y flujos de mesa que llamen a las RPC afectadas; identificar rutas activas antes de cambiar sus contratos. No declarar soporte por modificar solo el checkout principal.
- Mantiene trazabilidad entre detalle y cobro agrupado sin requerir una fila de pago por cada producto. El mecanismo de relación y validación se diseñará en la spec.
- Reutiliza sync, catálogo y colas offline existentes; no descarta pendientes por errores de capacidad ni usa fallbacks que pierdan moneda/medio.
- Tickets y resúmenes existentes no pueden sumar monedas distintas ni presentar una venta mixta como monomoneda. Esto es compatibilidad necesaria del flujo de venta, no ampliación visual general de reportes.

#### Consumidor: `product-currency-report-contracts`

- Lee las nuevas magnitudes documentadas por el módulo de venta; mantiene separados facturado, cobrado y equivalente contable.
- Para nuevos detalles puede agrupar por producto, moneda y medio seleccionado. Para históricos sin atribución no inventa dicha relación.
- No confunde medio seleccionado/importe de línea con cobro efectivamente recibido, en particular en órdenes pendientes, CxC, cancelaciones y devoluciones. Las reglas exactas se fijarán en la spec.
- Conserva contratos compatibles con las pantallas actuales; definir campos nuevos/versiones sin introducir importes nativos mixtos en totales escalares legacy.
- No añade ahora UI de desglose monetario a dashboards, reportes o IA; esos trabajos del borrador original quedan fuera del incremento inmediato.

## Plan técnico detallado — aprobado

### Estado, alcance y puertas

El usuario aprobó el contrato de venta, la secuencia y este plan técnico. La aprobación actual autoriza desglosar y revisar tareas pequeñas; no inicia su implementación ni ejecución SQL. El desglose MC-xxx de este documento sigue en borrador hasta su aprobación. Los archivos y nombres nuevos mencionados debajo son propuestas, no artefactos existentes.

- Entorno: newa, conservando sus versiones actuales; usuario ejecuta SQL desde SQL Editor y agente verifica en lectura. Main requiere promoción separada.
- S01 de configuración ya aplicado: no reejecutarlo ni tratarlo como migración de moneda. No se ha creado el flag.
- Mantener capacidades aprobadas: configuración → venta → contratos de reportes. Las fases técnicas dividen esas capacidades, no crean un cuarto módulo funcional.
- Incluir TPV CUP/USD, política/cache, descuento unitario, duplicados, cobro, sync, preorden, mesa/cocina y CxC. Ninguna exclusión silenciosa ni nuevos desgloses visuales generales de reportes.
- La spec de product-currency-report-contracts falta: redactarla y aprobarla antes de elaborar sus tareas; los contratos de datos de venta ya son su entrada. Nada se activa mientras falte adaptar un consumidor crítico.

### Fases y entregables

| Fase | Dependencia | Entregable verificable | Puerta de salida |
|---|---|---|---|
| P0 Baseline y contratos | Plan y tareas aprobados | Inventario nuevo de schema/RPC/grants de newa, fixtures y capacidad backend; trazabilidad de consumidores. | SQL de preflight revisado y regresiones baseline conocidas. |
| P1 Seguridad y política | P0 | Flag false, revisiones inmutables y constancias emitidas, autorización/aislamiento de infraestructura compartida. | Policies/grants/RPC y pruebas por rol/tienda aprobadas en newa. |
| P2 Precios propios por TPV | P1 | CUP/USD opcionales independientes, resolver determinista, edición/importación y payload de catálogo. | Resolver y clientes toleran ambas monedas, solo CUP y solo USD sin conversiones. |
| P3 Núcleo monetario y modelos | P0, contratos P1/P2 definidos | DTO versionado, cálculo exacto, descuentos unitarios, snapshots y persistencia local. | Fixtures Dart/SQL equivalentes, JSON roundtrip y legacy sin cambios. |
| P4 Registro y cobro nuevos | P1–P3 | Campos financieros aditivos, orquestación transaccional y atribución de pagos a detalles; edición por versión. | Concurrencia, replay y errores parciales no duplican efectos. |
| P5 Política y flujo TPV | P1–P4 | Proveedor/cache y admin flag protegido; moneda en detalle, duplicados y checkout restringido. | Online y offline con caché fresca/vacía/stale, reinicio y dos tiendas. |
| P6 Rutas completas | P4/P5 | Preorden, mesa/cocina, CxC/parciales y ajustes referenciados a líneas. | Todas las rutas PCS-11 y efectos de stock/comanda/cobro verificados. |
| P7 Consumidores | Spec de reportes aprobada y P4–P6 | Adapters por versión para reportes, métricas, caja, resumen y ticket existentes. | Sin dobles descuentos/ingresos ni suma de nativos mixtos. |
| P8 Activación piloto | P0–P7 | Checklist y prueba integral en una tienda de newa, flag activado por administrador autorizado. | Evidencia funcional por rol, recuperación e impresión; main sigue sin cambios. |

P3 puede desarrollarse como pruebas/núcleo puro una vez aprobado el contrato de datos, pero los clientes no se despliegan/activan antes del backend compatible. P2 solo admite registros USD-only cuando todos sus lectores relevantes toleran CUP null. Preparación backend y cliente se separan de activación funcional.

### P0 — baseline, autorización y pruebas primero

1. Registrar firmas y cuerpos actuales de las RPC afectadas, dependencias, triggers, tipos/constraints, grants, propietarios/search_path y policies. No usar hashes de main para reemplazar avances de newa.
2. Confirmar disponibilidad de vistas vigentes y RPC base de precios. Si faltan, proponer sus migraciones en orden AGENTS.md; no asumir instalación remota.
3. Inventariar consumidores de precio_unitario/importe/importe_real/importe_total/precio_con_descuento_total y de la tabla compartida de idempotencia. Clasificar precio, bruto previo al manual, neto, cobrado, deuda y costo; no adaptar mediante sustitución global de nombres.
4. Fijar fixtures ficticios compartidos para CUP/USD, descuentos y presentación/cantidad. Crear pruebas que fallen frente al comportamiento actual antes de implementar cada corte.
5. La capacidad backend se verifica por contrato/versión y permisos reales. No probar disponibilidad enviando una venta que pueda crear efectos. Una RPC ausente no autoriza fallback que pierda campos.

### P1 — política autorizada y protección

- Extender app_dat_configuracion_tienda con permitir_moneda_por_producto boolean NOT NULL DEFAULT false. Conservar flags legacy independientes.
- Proponer almacenamiento de revisiones inmutables de política y constancias de entrega ligadas a tienda/usuario/dispositivo, revisión, emisión y ventana offline existente. Mantener actor solicitante y vendedor original diferenciados para sync administrativo autorizado; no confiar en p_uuid como autenticación.
- Emitir snapshot consistente de flag, forzado y monedas en una lectura/operación del servidor. Una lista de monedas cargada en otro momento no sustituye esa revisión. Solo CUP/USD en modo nuevo; forzado debe ser compatible.
- Emisión y modificación de política por roles autorizados; vendedor puede obtener su política/constancia, no redactar revisiones ni ampliar autorización. Alta de revisiones derivada del cambio protegido, no INSERT libre del cliente.
- Cada tabla nueva: CREATE TABLE seguido inmediatamente de ENABLE ROW LEVEL SECURITY y policies explícitas; consultas por tienda y constancia por sujeto/alcance. Escritura directa de revisiones/constancias no autorizada; funciones servidor con grants mínimos y guardas.
- Endurecer app_dat_operacion_offline_idempotencia solo después de revisar todos sus tipos de operación y consumidores. No bloquear turnos/egresos/admin offline al proteger ventas. SECURITY DEFINER requiere autorización, search_path fijo y permisos explícitos, además de RLS.
- Antes de habilitar flag, verificar capacidad de contratos, forzado/monedas y readiness de la tienda. El cliente muestra rechazo del servidor, no éxito optimista falso.

### P2 — precios específicos CUP/USD de extremo a extremo

Backend: ampliar app_dat_precio_tpv con USD nullable y CUP nullable; al menos uno positivo y cada informado válido/finito. Mantener vigencias, soft-delete y unicidad existentes, tras preflight de datos. Resolver primero la configuración vigente de mayor ID y después cada campo: específico de esa moneda → general vigente de esa moneda → no disponible. No buscar el último USD no nulo de otra configuración histórica.

- Mantener ámbito TPV/producto actual; no introducir overrides por variante como capacidad nueva. Respetar resolución de variante/presentación existente y documentar su interacción antes de cambiarla.
- Validar producto/TPV de la misma tienda y RLS para lectura autorizada incluido vendedor; escritura administrativa conforme al modelo existente. Guardar origen/id/vigencia en resolución.
- Admin: adaptar lib/models/tpv_price.dart, services/tpv_price_service.dart, screens/tpv_prices_screen.dart y widgets/tpv_managements/add_price_tpv_product.dart, price_alterations.dart y tpv_price.dart. Trazar y adaptar importación/exportación real; vacíos heredan, cero no hereda. Preview independiente de precios efectivos.
- Seller/Admin Lite: services/admin_inventory_service.dart, screens/admin/admin_tpv_prices_screen.dart y fn_admin_caja_precio_tpv_offline deben leer/escribir ambos valores, con misma seguridad y regla de herencia.
- Catálogo/offline: extender Product y payload de precios por pipeline existente, no otro catálogo. Invalidar detalles en memoria tras merge; nunca borrar pendientes. Conservar metadatos de vigencia/procedencia.
- Despliegue escalonado: backend tolerante y lectores primero; habilitar escritura USD-only después. El feature flag de venta no vuelve seguros a clientes viejos que siguen editando precios.

### P3 — DTO y núcleo decimal

- Mantener discriminador legacy/producto-v1 en orden, línea y payload. Identidad por id de línea estable, no solo id_producto. Sin versión histórica = legacy; versión nueva incompleta/desconocida = error explícito.
- Proponer núcleo puro de decimal/racional exacto con primitivas Dart BigInt y representación canónica, sin dependencia nueva por defecto. La revisión de pubspec del vendedor no encontró dependencia directa decimal/money/rational. Antes de implementar, evaluar límites y reutilización existente; cualquier dependencia requiere revisión aparte.
- Cálculo nuevo no deriva dinero de double.toString tras perder precisión. Leer/serializar decimales canónicos o unidades menores exactas; legacy puede mantener sus doubles pero no es autoridad de producto-v1.
- Orden de cálculo: precio propio y presentación → reglas automáticas por medio/cantidad → descuento manual unitario en la moneda de línea → multiplicación por cantidad → neto de línea a 2 decimales half-up → agrupación moneda/medio. Precio/tasa/cantidad y valores intermedios se preservan con precisión suficiente.
- Bruto de catálogo, subtotal previo al manual y neto son magnitudes diferentes. Conservar componentes y residual reproducible; no alterar el descuento unitario elegido para esconder centavos.
- Modelo y persistencia: models/product.dart, models/order.dart, servicios de preferencias/carrito/cola; cubrir copyWith/toJson/fromJson, reinicio y relación presentación/factor. No reconstruir moneda/medio de órdenes nuevas desde pagos globales.
- Validación servidor de rangos, valores finitos, permisos de descuento y coherencia. Distinguir precio faltante de neto cero por promoción autorizada; una gratuidad no crea un pago ficticio ni evita control de stock. No ampliar permisos de precio/descuento por añadir moneda.

### P4 — esquema financiero y orquestación

- Ampliar extracciones y operación con los campos propuestos en la spec; validaciones condicionales para producto-v1. Históricos/no comerciales siguen nullable y sin backfill monetario. FK/índices deben conservar integridad y acceso por tienda.
- Campos legacy se proyectan en CUP según sección 0.1: previo al manual y neto en su lugar explícito, sin introducir nativos mixtos en aliases. Los mutadores deben usar la rama nueva y no reconstruir nativos desde esos aliases.
- Proponer contrato nuevo de orquestación versionado para creación/finalización y otro de edición autorizada; nombres/firma definitivos en tareas. No cambiar firmas existentes de modo que rompan clientes ni invocar wrappers legacy como atajo que pierda moneda o reaplique descuentos.
- Reutilizar lógica de inventario/presentaciones corregida de newa, comprobando los puntos de entrada y rollback. No retroceder a implementaciones de main ni perder equivalencias de ingredientes.
- Transacción: autorización → exclusión por clave → comprobar idempotencia/huella → validar política/precio/tasa/descuento → operación/detalles/stock → pagos y atribuciones → registro de clave → respuesta con ids estables. Fallo revierte el intento.
- Bloqueo transaccional antes del SELECT/crear. Misma clave y mismo contenido autorizado devuelve mismo resultado; distinta huella/tipo/alcance produce conflicto. No regenerar UUID para convertir ese conflicto en otra venta.
- Proponer atribución financiera pago↔detalle/segmento de tasa con importes nativos y equivalentes, solo si la infraestructura existente no permite esa relación verificable. Si requiere tabla, misma regla RLS inmediata. No crear una fila de ingreso adicional por atribución.
- Verificar cobro nativo por moneda/medio, excluir pendientes como ingresos, y conservar equivalente como dato contable. Edición/cantidad/eliminación no deben sobrescribir cobros reales para cuadrar un total nuevo.

### P5 — configuración, detalle, checkout y sync

- Admin config: services/store_config_service.dart y widgets/monedas_tienda_card.dart, selector flag y errores/permisos; default false y no activación anticipada.
- Seller: StoreConfigService/SyncModule.storeConfig descargan flag y referencia/snapshot de política. Revisiones/constancias satélite requieren descarga/cache explícitos enganchados a AutoSyncService y device_offline_prep_service, aunque se expongan mediante el mismo proveedor; no basta con select('*') de configuración. Productos/precios conservan su pipeline independiente ya existente.
- Enumerar por fase datos descargados, exclusivamente online y requeridos en caché. Modo ON con metadata requerida ausente/inválida bloquea nuevas órdenes que la necesitan, sin degradación silenciosa; modo OFF conserva su ruta. No inventar TTL adicional.
- Detalle: moneda junto al medio existente, solo opciones habilitadas/con precio y tasa. Duplicados comparan identidad logística y snapshot monetario. Separar crea línea; unir exige combinación final elegida, preview y confirmación antes de stock/servidor.
- Checkout: rama legacy conserva editor y sus pagos editados, como AGENTS.md. Rama producto-v1 elimina redistribución libre y usa netos agrupados; cambiar selección vuelve al detalle. No rehacer importes USD dividiendo por tasa.
- OrderService y AutoSyncService: persistir UUID/snapshot antes del envío, mismos DTO y resultado; validar acceso actual al subir, permitir delegación administrativa autorizada sin suplantar al vendedor. En modo nuevo no usar cadena de fallbacks que elimine campos/pagos/fecha/versiones.
- Red perdida o app cerrada: no repetir cobro/stock; replay de venta aceptada recupera resultado aun si su autorización offline original ya venció. Primer envío fuera de autorización se retiene para revisión autorizada sin borrar/convertir.

### P6 — rutas y estados

- Preorden: preorder_screen_styled.dart y rutas alternativas activas, incluyendo envío directo offline. Sustituir CUP implícito y agrupación solo por medio únicamente en producto-v1; validar ingredientes/almacén con las reglas existentes.
- Mesa/cocina: models/mesa_cuenta.dart, MesaCuentaService y RPC abrir/agregar/pedir/actualizar/cancelar/obtener/finalizar. Guardar política al abrir y snapshot al añadir/pedir; validar antes de stock/comanda. Transferir ids y datos al Order sin reconstruir precios. Finalizar enlaza y cierra idempotentemente; stock_movido impide doble consumo.
- Crédito: ampliar contratos CxC y liquidación, atribución de deuda y pagos parciales por detalle/moneda. Filtrar FIFO o distribución por obligaciones compatibles, no SUM(monto) entre monedas.
- Medio pendiente no es cobro real: al primer pago de esa línea se fija el medio real; siguientes parciales lo respetan. Liquidación en moneda original, sin convertir deuda ni repartir una línea entre medios. Guardas/bloqueos contra dos liquidaciones simultáneas que excedan saldo.
- Ajustes/devoluciones: referencia a venta/línea/pago original, snapshot y permisos, inventario y conciliación transaccionales. No DELETE de históricos monetarios ni modificación de pagos liquidados para fingir otro cobro; cualquier acción destructiva real requiere autorización específica.
- Cancelar una cuenta ya pedida revierte solo los efectos reales correspondientes, no todo el stock por cantidad interpretada en otra presentación. Probar reinicio durante pedido/cobro/cierre.

### P7 — contratos de reportes y consumidores

Antes de sus tareas, completar SPEC-product-currency-report-contracts.md con las entradas de venta aprobadas y criterios propios. No implementarlo por inferencia a partir del borrador histórico de dashboards.

- Adaptar reporte_ordenes_json, métricas de CustomerService y consumidores encontrados en P0 por versión. Selección comercial, obligación, cobro y deuda no son la misma magnitud.
- Bruto/subtotal/neto y descuentos se leen una sola vez. Evitar join detalle×pago que multiplique ingresos. Consolidar solo equivalentes contables; no usar tasas actuales para ventas/costos/liquidaciones históricas.
- Caja/ticket/resumen operativo deben mostrar monedas correctas y grupo real de cobro. No añadir ahora nuevos desgloses visuales generales de reportes ni funcionalidades IA.
- Revisar también integración Carnaval/SQL de devolución local si está desplegada/activa; su archivo local no demuestra estado remoto. Ninguna ruta activa puede ejecutar recálculo escalar sobre producto-v1.

### Transición, activación y reversibilidad

1. Preparar backend aditivo y lectores con flag false. Migrar solo formatos locales sin alterar datos financieros históricos: órdenes previas se conservan legacy; nuevas reciben revisión vigente.
2. Antes de activar, sincronizar las colas antiguas cuando sea posible. Órdenes legacy antiguas sin evidencia de revisión no se descartan ni convierten: requieren conciliación/autorización de reanudación si el servidor no puede demostrar su origen. No abrir una excepción universal que permita crear ventas legacy nuevas con flag ON.
3. RPC legacy debe impedir altas nuevas que eludan la modalidad activa, conservando reanudación autorizada de órdenes realmente previas. Definir mecanismo de reanudación acotado a UUID/huella/tienda/sujeto y auditado; no una variable de sesión que el cliente pueda falsificar. Probar clientes viejos y reintentos durante el cambio.
4. Activar solo con backend, lectores, todos los flujos y consumidores críticos listos. El apagado posterior afecta órdenes nuevas, no cambia contratos iniciados ni hace perder lectura/replay de producto-v1.
5. Reversión operativa: deshabilitar altas nuevas del modo, conservar esquema/datos y procesar pendientes con su contrato. No DROP columnas/tablas, truncar, borrar colas ni revertir migraciones destructivamente como rollback automático. Revisar compatibilidad antes de volver a desplegar un cliente antiguo.
6. Promoción a main: nueva inspección/diff de schema y funciones, scripts específicos preservando su contexto, validación y ejecución autorizada separadas. Ningún éxito en newa equivale a autorización de main.

### Paquetes SQL propuestos y ejecución manual

Ubicación docs/plan-multimoneda; nombres orientativos para tareas futuras:

| Paquete | Contenido | Revisión/ejecución |
|---|---|---|
| M00 preflight | Catálogo, versiones, datos incompatibles y capacidades; solo lectura. | Revisar antes de preparar cada migración. |
| M01 seguridad/política | Revisiones/constancias, flag, aislamiento de idempotencia y guardas necesarias. | RLS/policies al crear cada tabla; probar roles/otros usos compartidos. |
| M02 precios TPV | Campo USD, CUP nullable, constraints, resolver, RLS y RPC offline de edición. | Preflight y clientes tolerantes antes de habilitar USD-only. |
| M03 datos de venta | Versiones, snapshots, moneda/importes y soporte en cuenta de mesa/atribución. | Aditivo, sin backfill de moneda/medio en históricos. |
| M04 orquestación | Creación/edición/finalización/cobro/replay con guardas. | Tests transaccionales y concurrentes antes de cliente nuevo. |
| M05 CxC/ajustes | Obligaciones y liquidaciones nativas, atribuciones y protección de saldo. | Verificar legado y no duplicar dinero ni stock. |
| M06 consumidores | Funciones de reporte y lecturas por versión. | Depende de su spec aprobada. |
| M07 verificación | Lecturas antes/después y harness de datos ficticios/roles. | Pruebas con escrituras claramente separadas y aprobadas; no etiquetarlas solo lectura. |

Cada paquete incluye prerequisitos, guardas de schema/definiciones, transacción cuando corresponda y verificación de lectura separada. Si una definición cambió, detener y revisar; no forzar una huella antigua. No reejecutar ciegamente scripts ya aplicados. El usuario ejecuta en newa; no se generan ni ejecutan estos SQL durante el plan. Una dependencia real de inventtia_flow debe guardar sus RPC SQL bajo docs/flow_schema, no aquí por comodidad.

### Matriz de trazabilidad y verificación

| Contrato | Fases | Evidencia mínima |
|---|---|---|
| SPC-AC-01–SPC-AC-12 de política | P1/P5/P8 | Roles, tienda, flag false/on, forzado, ausente/vacío/stale y snapshot. |
| PCS-01 | P0/P3/P5/P8 | Golden/fixtures legacy de precio, JSON, editor y distribución de pagos. |
| PCS-02/03 | P1/P2/P3/P5 | Precios propios, herencia, precio/tasa ausente, política histórica y forzado. |
| PCS-04/05 | P3/P5/P6 | Cantidad/presentación/factor y duplicados separados/unidos con confirmación. |
| PCS-06/07 | P3/P4/P5 | Neto unitario/lineal exacto y snapshots roundtrip; obligaciones nativas. |
| PCS-08 | P4/P6/P8 | Dos sesiones con misma clave, claves diferentes, respuesta perdida y app cerrada; un solo efecto. |
| PCS-09/10 | P0/P1/P4/P6 | Históricos/no comerciales y prueba negativa de roles/tiendas/UUID ajeno, sin service_role como sustituto de RLS. |
| PCS-11 | P6/P8 | Cada entrada activa: preorden, cuenta/cocina, CxC/parcial, edición y devolución. |
| PCS-12 | P7/P8 | Pago real separado de línea, totales sin doble descuento/ingreso, caja y ticket correcto. |

Casos numéricos mínimos nuevos: 3 × 100 CUP − 10 CUP/unidad = 270 CUP; 3 × 1,05 USD con 10% = 2,84 USD; precio específico CUP sin USD hereda USD general; configuración nueva con USD vacío no rescata USD antiguo; dos líneas mismo producto/moneda con distinto medio; grupo con tasas históricas distintas; descuento/recargo por moneda; fracciones/presentaciones; cero neto autorizado frente a precio ausente; residual contable sin cambiar cobro; sin tasa USD bloqueado sin inventar CUP si forzado USD.

Nombres de pruebas nuevos propuestos para desglosar en tareas: product_currency_money_test, product_currency_price_resolver_test, product_currency_order_roundtrip_test, product_currency_checkout_test, product_currency_sync_test, product_currency_policy_cache_test, product_currency_mesa_test y product_currency_cxc_test. Pueden reutilizar archivos cercanos cuando sea apropiado; no se han creado ni ejecutado.

Regresiones existentes verificadas por nombre en esta revisión: checkout_payment_lines_test.dart, moneda_venta_test.dart, multimoneda_core_test.dart, descuento_multimoneda_test.dart, order_usd_payments_test.dart, payment_currency_amounts_test.dart, venta_ingredient_consumo_test.dart y home/app_compile_test.dart. Ejecutar además la verificación focalizada de precios/servicios de AGENTS.md. En Windows usar flutter.bat desde PowerShell si el wrapper Bash no produce salida. Tras cambios, analyze y build sin arrancar APIs ni flutter run; documentar warnings/fallos baseline, no silenciarlos.

Gate final: tests unitarios/integración relevantes, SQL real en PostgreSQL con fixtures ficticios y roles, concurrencia en dos sesiones, venta online/offline/replay, stock/comanda sin duplicación, liquidación parcial y ticket físico. Tests estáticos de SQL y compilación no sustituyen esos recorridos. Nada de lo anterior se ha ejecutado para este plan.

## Tareas ejecutables MC — desglose aprobado

### Estado y disciplina de ejecución

El usuario aprobó el desglose y autorizó iniciar el primer lote MC-001–MC-003. El resto permanece pendiente; puertas DB/REP/P7/ACT conservan sus autorizaciones específicas. El progreso real se registra en la evidencia del primer lote: no inferir que el contrato o el plan aprobados estén implementados. S01 aplicado antes de este plan no se repite ni se considera una tarea MC nueva.

- Una tarea se inicia individualmente y se cierra con entregable y evidencia, no por haber editado archivos. Escribir primero el test/fixture que revela el caso cuando haya infraestructura adecuada; implementar después y ejecutar su verificación.
- Una dependencia MC debe estar completada y su puerta DB requerida verificada. Dependencias múltiples se unen con +. Una tarea local puede prepararse contra contrato/fixtures, pero no desplegarse antes del backend que necesita.
- Agente: prepara archivos, código y pruebas locales cuando las tareas se aprueben; inspección remota de lectura. Usuario: revisa y ejecuta migraciones/harness con escrituras en SQL Editor de newa. Aprobar tareas no equivale a autorizar escrituras remotas del agente, activar tienda ni tocar main.
- Entregables SQL en docs/plan-multimoneda y RPC de inventtia_flow, solo si surge dependencia real, en docs/flow_schema. Crear tabla implica ENABLE RLS y policies explícitas en las líneas siguientes, en el mismo script.
- Un fallo de permisos no permite otra vía de escritura ni fallback a contrato legacy. Un bloqueo se registra con causa/evidencia y se comunica; no se elimina de la lista ni se marca completado.
- Pruebas de permisos no se demuestran con el propietario/service_role. Usar sujetos/roles de prueba autorizados y fixtures ficticios; separar harness de escritura de verificación de lectura. Ninguna limpieza destructiva de datos ajenos se autoriza con este desglose.

### P0 — evidencia, fixtures y contrato de reportes

| ID | Depende de | Entregable acotado | Verificación para cerrar |
|---|---|---|---|
| MC-001 | Aprobación de tareas | M00 de lectura: inventario de newa, capacidades, schema/RPC/grants y mapa de consumidores; identificar fuentes de precios/tasas mutables y flujos directos legacy. | Archivo de lectura revisado, resultados sin secretos y diferencias respecto a spec registradas. No usar catálogo de main como reemplazo. |
| MC-002 | MC-001 | Baseline local de pruebas relevantes de ambas apps y registro de fallos previos. | Comandos/resultados documentados; no suprimir tests, warnings ni checks para obtener verde. No arrancar APIs. |
| MC-003 | MC-001 | Contrato DTO/financiero y fixtures canónicos ficticios que compartan Dart/SQL, incluidas claves estables y escala decimal. | Cubre todos los campos de spec, inválidos y diferencias bruto/subtotal/neto. Identidad de snapshots verificable sin confiar en números arbitrarios del cliente ni en históricos reconstruidos. |
| MC-004 | MC-003 | Redactar SPEC-product-currency-report-contracts.md usando el contrato aprobado y consumidores de MC-001. | Criterios para bruto/neto/cobrado/deuda/costos, duplicación por joins e históricos. Presentar para aprobación REP; no implementar reportes todavía. |

Primer lote propuesto: MC-001 → MC-002 y MC-003. Solo inventario de lectura, baseline y fixtures/contrato; no modifica schema remoto. MC-004 puede seguir antes de los adapters de P7 y requiere revisión de su spec, no una suposición de aprobación.

### P1 — seguridad y política

| ID | Depende de | Entregable acotado | Verificación para cerrar |
|---|---|---|---|
| MC-005 | MC-001+MC-003 | Matriz de autorización y helpers por tienda para política/constancia/ventas, incluidas delegación admin y vías directas. | Casos positivos/negativos de vendedor, dueño/gerente, superadmin, anon y otra tienda; actor autenticado separado de vendedor original. |
| MC-006 | MC-005 | Parte M01 de revisiones inmutables y flag false con generación protegida de snapshot consistente. | DDL aditivo, RLS/policies inmediatas; cambio protegido genera revisión correcta y no concede edición histórica al cliente. Test SQL preparado, no aplicado aún. |
| MC-007 | MC-006 | Parte M01 de constancias emitidas al sujeto/dispositivo, vinculadas a revisión y ventana offline existente. | Rechaza constancia ajena/manipulada, entrega consistente y no amplía licencia. Evidencia de precio/tasa debe seguir siendo validable aunque cambien las fuentes; no inventar hora exacta de creación offline. |
| MC-008 | MC-005 | Parte M01 de RLS/grants/guardas de idempotencia compartida, preservando usos de turnos/egresos/admin. | Pruebas preparadas de aislamiento y de cada uso existente; no devolver venta ajena por conocer un UUID. |
| MC-009 | MC-006+MC-007+MC-008 | Ensamblar M01, verificaciones y control de capacidad para que flag no pueda activarse prematuramente. | Preflight aborta ante definición desconocida; autoriza false y deniega activación sin backend requerido. Paquete listo para puerta DB-M01. |

### P2 — precios específicos por moneda

| ID | Depende de | Entregable acotado | Verificación para cerrar |
|---|---|---|---|
| MC-010 | DB-M01 | M02a de expansión: añadir USD opcional conservando CUP obligatorio durante transición; proteger tabla/RPC y vínculo producto/TPV. | Datos CUP actuales válidos, nuevo USD positivo/finito cuando informado y roles/tiendas correctos. Sin USD-only aún. |
| MC-011 | MC-010 | Resolver común y metadatos de capacidad/procedencia en M02a. | Vigencia CURRENT_DATE/ID mayor, herencia por moneda, base/variante/presentación compatibles y sin rescatar USD de override antiguo. Preparar fixtures para puerta DB-M02a. |
| MC-012 | DB-M02a | Modelo/servicio admin de TPV con CUP/USD independientes y actualización parcial segura. | Parseo CUP-only/both/USD-only futuro; ausencia no se vuelve cero y patch CUP no elimina USD. No alterar históricos. |
| MC-013 | MC-012 | Editor admin y preview de herencia/origen por moneda, con errores/permisos explícitos. | Widget tests de precio general/específico y falta de precio; USD-only sigue no habilitado mientras schema exija CUP. |
| MC-014 | MC-012 | Importación/exportación TPV en sus rutas reales con campos nativos separados. | Plantilla, vacíos, inválidos, fechas y actualización parcial; no convertir ni borrar override de otra moneda inadvertidamente. |
| MC-015 | DB-M02a+MC-003 | Product y sync existente transportan ambos precios y procedencia; invalidación de detalles tras merge. | Online/offline, ambos/solo CUP/solo USD fixtures, reinicio y caché no duplicada. Pendientes intactos. |
| MC-016 | DB-M02a | Editor/cache Admin Lite y fn_admin_caja_precio_tpv_offline con el mismo contrato. | Permisos de escritura administrativos y replay de actualización; vendedor no obtiene privilegios por UI offline. SQL servidor se revisa/ejecuta en puerta DB-M02b. |
| MC-017 | MC-012+MC-013+MC-014+MC-015+MC-016 | M02b de CUP nullable y check de al menos un precio válido, más capacidad USD-only. | Demostrar lectores tolerantes antes de aplicar; preservar vigencias/soft-delete/unicidad y no fabricar USD histórico. Paquete listo para DB-M02b. |

M02a/M02b son cortes del paquete M02 del plan, no dos modelos distintos. Si la compatibilidad permite unificarlos en un despliegue controlado se revisa el manifiesto, no se omite la puerta de lectores ni se habilita USD-only por el simple flag de venta.

### P3 — núcleo exacto y persistencia

| ID | Depende de | Entregable acotado | Verificación para cerrar |
|---|---|---|---|
| MC-018 | MC-003 | Núcleo decimal/racional puro y serialización canónica, sin dependencia nueva por defecto. | Parseo exacto, operaciones, límites, no finitos/negativos inválidos y half-up; sin epsilon float como autoridad. |
| MC-019 | MC-018 | Calculador unitario/línea con automático, manual por unidad, cantidad, neto y residual. | 3×100−10/unidad=270 CUP; 3×1,05 USD con 10%=2,84; recargos, fracciones, gratuidad autorizada y rechazo de precio faltante. Legacy conserva redondeo. |
| MC-020 | MC-003+MC-019 | DTOs/models Order/OrderItem versionados con identidad, selección y snapshots; Product de MC-015 integrado. | copyWith/JSON roundtrip, dos líneas del mismo producto con diferente moneda/medio y datos incompletos rechazados. |
| MC-021 | MC-020 | Carrito/cola/preferencias conservan DTO y UUID antes del primer envío. | Reinicio, cierre abrupto y lectura de pendientes viejos; no transformar legacy ni recomponer detalle desde pagos globales. |

### P4 — contratos SQL y orquestación

| ID | Depende de | Entregable acotado | Verificación para cerrar |
|---|---|---|---|
| MC-022 | DB-M01+MC-003 | M03: campos/versiones y constraints condicionales en operación/extracciones, aliases contables y snapshots. | Históricos/no comerciales siguen válidos; v1 exige datos completos y moneda/medio compatibles; cero backfill financiero. |
| MC-023 | MC-022 | M03: atribución pago↔detalle/segmento de tasa y claves/índices para identidad de línea. | No duplica ingreso, conserva montos nativos y tasas distintas; RLS/policies y FKs correctas. Tabla nueva solo si realmente hace falta. Listo para DB-M03. |
| MC-024 | DB-M03+MC-019 | Calculador/validador SQL con los mismos fixtures de Dart y validación de política/precio/tasa/descuento. | Iguales resultados exactos, equivalentes CUP y residual; rechaza snapshot adulterado y acepta snapshot legítimo sin sustituirlo por el actual. |
| MC-025 | MC-024+MC-008 | Alta producto-v1 transaccional con UUID, exclusión previa, huella canónica e inventario/presentaciones corregidos. | Mismo UUID no repite venta/stock; otra huella/tipo/tienda genera conflicto. Fallo de cualquier parte revierte el intento. |
| MC-026 | MC-025+MC-023 | Registro/validación de pagos nativos y es_pagada con atribución contable. | Obligación por moneda/medio; CUP sobrante no cubre USD; pendiente no cuenta como ingreso; no duplicar descuentos. |
| MC-027 | MC-025+MC-026 | Mutadores de pendiente por id de línea: cantidad, selección y eliminación/ajuste permitido según estado. | Versión y snapshots respetados, sin fusión silenciosa ni sobrescritura de cobros liquidados. Vías directas no eluden validaciones. |
| MC-028 | MC-025+MC-026+MC-027 | M04 y harness de concurrencia/replay/rollback con scripts separados de lectura y escritura. | Tests preparados para dos sesiones y respuesta perdida; actor/delegación autorizados y tienda ajena rechazada. Listo para DB-M04. |

### P5 — proveedor, selección, checkout y sincronización

| ID | Depende de | Entregable acotado | Verificación para cerrar |
|---|---|---|---|
| MC-029 | DB-M01+MC-021 | StoreConfigService/proveedor devuelve política consistente y estado incompleto sin activar modo por error. | Caché válida/vacía/corrupta/ajena, forzado inválido, logout/cambio de tienda y respuestas concurrentes. |
| MC-030 | MC-029+MC-007 | Sync/cache explícito de revisiones/constancias satélite integrado en AutoSyncService y preparación offline. | No basta select('*'); reinicio conserva referencias, modo ON sin autorización requerida bloquea nuevas órdenes sin convertirlas en legacy. |
| MC-031 | MC-029+DB-M04 | Control admin del flag y capacidad/permiso de tienda. | Guardado parcial, rollback/recarga ante error y vendedor sin escritura. No mostrar éxito falso ni ampliar privilegios por controles existentes. |
| MC-032 | MC-015+MC-019+MC-020+MC-030 | Detalle con moneda junto al medio actual y descuento manual unitario en esa moneda. | Solo precio/moneda/tasa permitidos, promociones por moneda y permisos de descuento; flag OFF conserva flujo anterior. |
| MC-033 | MC-032+MC-027 | Confirmación de duplicados y combinación final explícita al unir. | Separar/unir/cancelar con preview; distinta presentación no se convierte implícitamente; RPC mantiene identidad elegida. |
| MC-034 | MC-033+MC-026 | Checkout v1 de netos agrupados sin redistribución; rama legacy intacta. | UI y validación nativa, redondeo 2,84, edición vuelve al detalle y precios no se recalculan por distribución legacy. |
| MC-035 | MC-021+MC-034+DB-M04 | OrderService online versionado, persistencia previa de clave y recuperación del resultado. | Sin fallback que pierda contrato, sin cobro/stock duplicado ante timeout y sin segunda llamada no atómica para pagos v1. |
| MC-036 | MC-021+MC-030+MC-034+DB-M04 | AutoSync v1 conserva DTO/pagos y retiene incidencias para revisión autorizada. | Replay, primer envío tardío, caché/tasa ausente y recuperación; legacy usa su desglose editado sin inferencia nueva. |
| MC-037 | MC-035+MC-036 | Corte legacy/v1 y reanudación autorizada de pendientes antiguos, con guardas backend M04b. | Cliente antiguo no crea legacy nuevo para evadir flag ON; pendientes previos sin evidencia se conservan para revisión, no se borran. Listo para DB-M04b. |

### P6 — rutas restantes y estados financieros

| ID | Depende de | Entregable acotado | Verificación para cerrar |
|---|---|---|---|
| MC-038 | DB-M04b+MC-035+MC-036 | Preorden online y envío directo offline usan el mismo contrato monetario y agrupación. | Desaparece CUP implícito solo en v1; ingredientes/almacén y legacy siguen sus reglas. Separar en subcortes si las rutas activas requieren cambios independientes. |
| MC-039 | MC-022+MC-020+MC-029 | Modelo/cuenta de mesa conserva modalidad, revisión y snapshot por item desde apertura/alta hasta lectura. | RLS de tablas tocadas revisada, sin unión por producto que ignore moneda; roundtrip cuenta→Order sin pérdida. SQL de soporte listo para DB-M03b. |
| MC-040 | DB-M03b+MC-039+MC-033 | Pedir/editar/cancelar item de mesa/cocina valida antes de efectos y respeta unidades/origen. | Una comanda/consumo por pedido; cancelación revierte solo lo real; replay y cambio de cantidad no duplican stock. SQL listo para DB-M04c. |
| MC-041 | MC-040+MC-026+MC-035 | Preparar contrato/SQL y cliente de finalización con venta/pago/cierre idempotentes y referencias originales. | Fixtures y pruebas locales preparadas para cuenta cerrada, stock_movido y respuesta perdida. M04c incluye pedido/cancelación/finalización completos; no declarar verificación remota antes de DB-M04c. |
| MC-052 | MC-041+DB-M04c | Verificación remota focalizada de mesa/cocina después de aplicar sus contratos. | Pedido, edición/cancelación, cobro y cierre desde app: un solo consumo/comanda/venta, replay y reinicio correctos. Separada de la preparación para evitar dependencia circular de M04c. |
| MC-042 | DB-M04+MC-023 | M05a de obligaciones CxC por detalle/moneda y lectores de saldo compatibles con legacy. | No SUM de nativos mixtos ni atribución inventada a históricos; seller/admin autorizados y saldo verificable. |
| MC-043 | MC-042+MC-026 | Liquidación CxC nativa con medio real fijado al primer parcial y atribución por línea. | Parciales posteriores mismo medio, moneda original, saldo bloqueado frente a concurrencia y ningún ingreso por sentinel pendiente. Listo para DB-M05a. |
| MC-044 | DB-M05a+MC-027+MC-052 | Ajustes/devoluciones autorizados ligados a línea/pago originales y reversión de efectos reales. | Sin reescribir cobro/historia ni doble stock; integration Carnaval activa identificada y no usa recálculo escalar sobre v1. Paquete M05b revisado y puerta DB-M05b. |

MC-039–MC-041 se implementan contra los contratos/fixtures antes de ejecutar sus paquetes; no desplegar cliente que use columnas/RPC aún ausentes. Se puede desarrollar el conjunto localmente, pero cada cierre remoto requiere la puerta que corresponda.

### P7 — contratos pendientes y consumidores operativos

| ID | Depende de | Entregable acotado | Verificación para cerrar |
|---|---|---|---|
| MC-045 | MC-004+REP | Desglosar y someter a revisión tareas definitivas de M06: reporte_ordenes_json, métricas/consumidores de MC-001 y contratos del módulo de reportes. | Cada consumidor con entrada/salida, criterio propio y prueba. Aprobación de tareas de venta no aprueba una spec de reportes que aún no existe. Gate P7 exige luego implementar y verificar ese desglose. |
| MC-046 | MC-034+MC-035+MC-036+MC-052+MC-043 | Ticket, caja y resumen operativo leen magnitudes/monedas correctas según versión. | No suma CUP+USD ni cobro duplicado, distingue deuda/cobrado; formato legacy intacto. No UI general nueva de reportes. |

No se elimina trabajo de reportes: MC-004 → REP → MC-045 → tareas M06 revisadas/ejecutadas → P7. Sus detalles quedan bloqueados por la spec, como exige el plan aprobado. Esta es una dependencia de aprobación real, no un stub de código ni una declaración de feature lista.

### M06 — desglose de consumidores (MC-045, preparado para revisión)

Derivado de SPEC-product-currency-report-contracts (aprobada en REP). Cada fila es un entregable acotado con su consumidor, contrato de entrada/salida y verificación propia; ninguna autoriza SQL de escritura ni activación. Las rutas son relativas a `ventiq_admin_app/lib` salvo indicación.

| ID | Depende de | Consumidor y entregable | Verificación para cerrar |
|---|---|---|---|
| R01 | REP (aprobada) | Envelope común de lectura (`version_reporte`, magnitud, moneda por importe, corte/estados resueltos, completitud+motivos; §7 de la spec). Adaptador Dart compartido que todos los demás consumen; no reconstruye totales por su cuenta. | Parseo estricto: campo requerido ausente = error de contrato visible, nunca 0. Decimales como cadenas exactas (MC-003). Fixture JSON con dataset mixto v1+legacy. |
| R02 | R01 + DB-M04 | `reporte_ordenes_json(bigint,timestamptz,timestamptz,bigint)` versionado por línea: `id_linea_cliente`, `moneda_venta`, neto nativo, equivalente CUP histórico y componentes de ajuste por línea; cobros por moneda/medio sin join detalle×pago que multiplique ingresos (§3, §4-7). | Fixture de orden mixta CUP/USD + legacy en el mismo dataset: bruto/neto leídos una vez, equivalentes sumados por línea fijada, cero fan-out de pagos. Test SQL de contrato + lectura en newa. |
| R03 | R01 | `sales_service.getProductSalesReport` (proveedor5 / por_turno_v2 / precios_actuales): declarar rama histórica vs análisis con precios actuales; v1 no se degrada a RPC antigua ante error de red/permisos (§6). | Dataset con líneas v1 muestra magnitud/moneda correcta; fallback a turnos solo admisible para datos legacy verificados; error de capacidad v1 = estado no disponible, no cero. |
| R04 | R01+R03 | `VentasPorMoneda` / `sales_screen` + exportaciones PDF/Excel: KPI contable en CUP histórico etiquetado; nativos nunca sumados entre monedas; ausencia ≠ cero; exportador consume el mismo adaptador (§6). | Orden mixta: tarjeta/exportación muestran Total CUP + Total USD + Equiv. CUP sin mezclar; dataset incompleto muestra estado, no subtotal disfrazado de total. Widget/golden tests. |
| R05 | R01 | `fn_reporte_ventas_por_moneda`: declarar su semántica real — cohorte de ventas (pagos atribuidos por fecha de operación, último estado 2), NO flujo de caja del período; documentar filtro de estado que difiere del comentario local (§2.2, §5). | Cobro registrado en otra fecha no entra en el período del cobro; etiqueta/contrato no lo renombra como caja. Test SQL de contrato. |
| R06 | R01 | `customer_service` métricas: neto comparable por versión, conteo único de operaciones y ticket medio sobre ese neto; el alias CUP previo al manual no se suma como ingreso (§3, §6). | Cliente con orden mixta: ticket medio = neto contable ÷ operaciones únicas, sin doble conteo por join ni por moneda. Tests de servicio con fixtures. |
| R07 | R01 + MC-042 (M05a) | `cxc_service`: saldo nativo por moneda/línea con aplicaciones válidas en la misma moneda; error de lectura ≠ deuda cero; no sumar deuda v1 al escalar legacy (§3, §5). | Obligación USD no queda liquidada por equivalente CUP suficiente; saldo por moneda reconciliable con sus aplicaciones. Coordinado con el contrato CxC, no por adelantado. |
| R08 | R01 | `financial_dashboard_service` / `financial_reports_service`: clasificar cada método entre activo/inactivo/mock; RPCs ausentes en newa (`fn_profit_and_loss`, `fn_sales_metrics`, `fn_*profitability*`, `fn_cash_flow*`, etc.) quedan como no_disponible — los mocks/ceros nunca se presentan como dato v1 ni como evidencia financiera (§2.1, §6). | Pantalla muestra "no disponible" donde no hay capacidad, no 0 ni mock; ninguna ruta activa recalcula v1 en escalar. Inventario de métodos clasificado y verificado contra newa. |
| R09 | R01 | `products_analytics_service`: separar análisis de catálogo/proyección (costo/precio actuales declarados) de utilidad realizada histórica; no revaluar ventas viejas con precio/costo vigente (§3). | Cada métrica etiqueta su fuente y corte; una venta histórica no cambia por editar el catálogo hoy. Tests con fixture de cambio de precio posterior a la venta. |
| R10 | R01 | `sales_analyst_service` + controller: el contexto que se serializa al analista declara magnitud, moneda, corte y cobertura; no expone costos/utilidad restringidos ni inventa ingresos (§8). | Payload del contexto validado contra fixtures: magnitudes declaradas, sin campos restringidos por rol, incompletitud explícita. |
| R11 | R01 + todos los anteriores | Puerta de consistencia transversal: misma magnitud/corte/cobertura en pantalla, exportación, widget y analista; paginación/exportación con el mismo conjunto sin duplicar ni omitir cobros (§7). | Recorrido admin con dataset mixto: números idénticos en cada superficie; error de contrato en cualquiera = fallo visible en todas. |

Notas del desglose:

- R02/R05 son los únicos entregables con SQL propuesto; ambos aditivos y declarativos de semántica, sin reescribir RETURNS que consumen clientes legacy (§7). Sus scripts irían a `docs/plan-multimoneda/` como propuesta, con la puerta DB correspondiente, nunca ejecutados por el agente.
- R07 queda bloqueada hasta M05a: el saldo nativo por línea/moneda necesita la atribución que MC-042/MC-043 todavía no tienen desplegada.
- Widgets de inicio y pantallas que consultan tienda propia (no la activa en preferencias) entran en la clasificación de R08/R11, como pide §2.1.
- No se crean desgloses visuales nuevos ni pestañas: cada consumidor conserva su superficie y solo corrige magnitud, moneda, corte y cobertura (§6).

### P8 — validación y piloto

| ID | Depende de | Entregable acotado | Verificación para cerrar |
|---|---|---|---|
| MC-047 | P7+DB-M05b+MC-038+MC-052+MC-044+MC-046 | Ejecutar regresiones y análisis/build de ambas apps sin lanzar servidores. | Resultados focalizados y fallos baseline identificados; no dependencias o checks relajados para pasar. |
| MC-048 | MC-047 | M07 de verificación final de lectura y checklist/harness ficticio separado para recorridos con escritura. | Scripts revisados y pasos realizables en SQL Editor, incluido control de concurrencia en dos sesiones. Usuario autoriza y ejecuta escrituras; agente verifica lectura. |
| MC-049 | MC-048+DB-M07 | Recorridos online/offline por rol, caché fresca/vacía/stale, reinicio y respuesta perdida con stock/comanda/CxC en tiendas de fixtures autorizadas. | Modos ON/OFF temporales solo en fixtures aprobados, sin cobros externos reales; evidencia de importes/estados, aislamiento y no duplicación. No habilitar la tienda piloto antes de ACT ni confundir harness con prueba desde app. |
| MC-050 | MC-049 | Checklist de activación piloto de una tienda newa con administrador autorizado. | Autorización específica ACT, backend/lectores listos, pendientes tratados y ticket físico comprobado; main no se toca. |
| MC-051 | MC-050+ACT | Verificar apagado posterior para altas nuevas y conservación/replay de órdenes v1 iniciadas. | Reversión operativa sin borrar schema/datos/cola, sin conversiones ni rollback destructivo. |

La promoción a main no queda autorizada ni se ejecuta como continuación automática de MC-051: exige su propia comparación, revisión y aprobación.

### Puertas SQL y de aprobación — no son efectos implícitos de una tarea local

Cada puerta DB implica: paquete completo revisado + autorización de ejecución del usuario → usuario ejecuta en newa → agente verifica con consultas de lectura y registra evidencia. Si falla, no iniciar dependientes ni reejecutar ciegamente. Los fixtures con escritura requieren aprobación específica y no se mezclan con verificadores de lectura.

| Puerta | Prerrequisitos | Qué desbloquea |
|---|---|---|
| DB-M01 | MC-009 y revisión de impacto de todos los usos compartidos | Política/constancias/seguridad disponibles, flag false. |
| DB-M02a | MC-010+MC-011 | Columnas y resolver necesarios para nuevos lectores; CUP aún obligatorio. |
| DB-M02b | MC-017 y evidencia de lectores compatibles | USD-only y escritura offline TPV actualizada, sin afectar precios históricos. |
| DB-M03 | MC-022+MC-023 | Schema financiero/atribución base para validar y registrar v1. |
| DB-M04 | MC-028 | Registro/cobro/edición transaccionales verificados. |
| DB-M04b | MC-037 | Corte y reanudación legacy verificados, sin evasión del flag. |
| DB-M03b | MC-039, revisado antes de desplegar su cliente | Soporte monetario en cuentas de mesa. |
| DB-M04c | MC-040+MC-041 completados como preparación local contra fixtures | Pedido/cancelación/finalización mesa con contratos completos; ejecución antes de verificación remota MC-052. |
| DB-M05a | MC-042+MC-043 | Deuda/liquidación nativas disponibles y verificadas. |
| DB-M05b | MC-044 | Ajustes/devoluciones coherentes con snapshots y efectos originales. |
| DB-M07 | MC-048 y autorización de cualquier fixture con escritura | Verificación final/harness completados, no permiso para activar. |
| REP | MC-004 presentado y aprobación explícita del usuario | Diseñar/revisar tareas definitivas de M06 mediante MC-045. |
| P7 | MC-045 y tareas M06 aprobadas, ejecutadas y verificadas | Consumidores críticos listos; es una puerta de trabajo real, no solo aprobar documentación. |
| ACT | MC-050 y autorización específica del usuario | Activar solo la tienda piloto de newa. |

### Lotes iniciales y definición de terminado

1. Tras aprobar este desglose: MC-001; luego MC-002/MC-003. Ninguna migración remota.
2. Preparar MC-004 y MC-005–MC-009. Presentar spec REP y paquete M01 por separado; no esperar una autorización genérica de implementación para ejecutar SQL.
3. Seguir dependencias del cuadro, separando compatibilidad de lectores de USD-only y manteniendo flag false hasta ACT.

Para cerrar cada tarea registrar: archivos/firmas tocados, test antes/después o verificación adecuada, resultado, limitaciones y dependencias desbloqueadas. Para SQL, además entorno, quién lo ejecutó, revisión aplicada y consultas de comprobación. Una prueba no ejecutada se marca pendiente, no aprobada por inspección. No crear documentación duplicada si estas tablas y las specs ya conservan la evidencia necesaria.

## Evidencia del primer lote autorizado

| Tarea | Estado | Evidencia |
|---|---|---|
| MC-001 | Completada | M00 de lectura preparado y catálogo consultado por bloques en newa mediante MCP; hallazgos y consumidores debajo. |
| MC-002 | Completada | Vendedor: 74 tests pasan en 12 archivos; admin: 36 tests pasan en 5 archivos. Ambos exit 0, sin cambios de código productivo. |
| MC-003 | Completada | Contrato en sección 15 de SPEC-product-currency-sale, JSON compartido, oráculo SQL de 14 casos y 7 tests nuevos. Vendedor final 81 tests pasan; análisis del test nuevo sin incidencias. |

### MC-001 — inventario newa

Artefacto: docs/plan-multimoneda/preflight_product_currency_m00.sql. Solo catálogo/SELECT dentro de transacción READ ONLY; no llama RPC de negocio, consulta datos personales, crea fixtures ni modifica schema. Los bloques equivalentes de catálogo se ejecutaron por MCP; el usuario no ha ejecutado todavía el archivo completo desde SQL Editor. Cada SELECT lleva etiqueta M00 y puede inspeccionarse por separado. Las huellas MD5 son diagnóstico de definiciones, no firmas de autorización.

Fecha del servidor consultado: 2026-11-13, TimeZone UTC (histórico: desde el 18/11 newa usa America/Havana), PostgreSQL 17.6 (170006). En esa inspección no existen permitir_moneda_por_producto ni precio_venta_usd de TPV. Ambas vistas vigentes existen con security_invoker=true; la vista principal usa CURRENT_DATE, NULL/0 base e ID descendente. fn_guardar_precio_venta_base está presente. No se requiere reinstalar por suposición las migraciones de esas vistas.

Hallazgos para las fases posteriores, no corregidos en este lote:

- app_dat_configuracion_tienda conserva RLS y cuatro policies acotadas del S01; anon sin SELECT. Esto no acredita por sí solo pruebas funcionales de todos los roles.
- Sin RLS/policies en las ocho tablas inspeccionadas: precio_tpv, precio_general_tienda, operacion_offline_idempotencia, descuentos_vendedor, mesa_cuenta_abierta, mesa_cuenta_item, comanda y comanda_item (prefijo app_dat_). Revisar permisos/impacto al tocar cada ruta, no copiar este estado a tablas nuevas.
- Extracciones, operación_venta, pago_venta y precio_venta tienen policies públicas ALL con true. Otras policies administrativas no bastan para asumir aislamiento. MC-005 debe incluir este riesgo de vías directas y presentar la solución/impacto compartido antes de la autorización de sus scripts; no ampliar automáticamente el S01 ya ejecutado.
- Hay RPC SECURITY DEFINER con EXECUTE anónimo y sin search_path fijo, incluidas precio TPV offline y CxC. Es evidencia de catálogo que exige revisión de guardas, no prueba de explotación ni autorización para ejecutar operaciones reales.
- Idempotencia: PK global client_uuid, sin huella de payload; 24 funciones públicas contienen referencia textual a esa tabla, incluidas ventas, pagos, turnos, egresos, pedidos/comandas y Admin Lite. Endurecerla sin probar esos usos puede romper módulos ajenos al nuevo cobro.
- Extracciones: 139 funciones públicas contienen referencia textual. M00 las enumera; referencia textual no equivale a dependencia exhaustiva, ruta activa ni permiso seguro. El módulo de reportes debe clasificar consumidores, no sustituir importes a ciegas.
- Precio TPV sigue CUP obligatorio, check positivo y unique producto/TPV/fecha. No tiene USD ni trigger de versionado en el inventario. La versión actual de tasa global es única por par y no tiene trigger de historial observado; su id por sí solo no demuestra un valor pasado.
- El cliente de tasas personales versiona mediante desactivar e insertar, pero eso no vuelve inmutables todos los accesos SQL. La fecha global es timestamp sin zona: DTO nuevo necesita instante UTC explícito emitido por servidor y evidencia del valor publicado, no reconstrucción desde reloj local ni fila actual.
- El catálogo general tiene trigger de UPDATE→INSERT y redondeo CUP configurable. Cambios de tasa pueden recalcular CUP cuando precio_venta_regido_por_usd está activo. Es gestión de catálogo existente, distinta del redondeo del cobro nuevo; no modificarla silenciosamente ni afirmar que toda fuente es append-only.

Consumidores locales adicionales localizados: TpvPriceService y TpvService; AdminInventoryService; CxcService; PersonalRatesService/CurrencyService; lecturas directas en SalesService/CustomerService/InventoryService y pantallas de venta/movimientos. El árbol tenía cambios previos del usuario, incluidos servicios de venta/sync/precios y tests: este lote no los revierte. El mapa de M00 es baseline, no validación funcional de esas rutas.

Huellas de referencia de ocho RPC críticas observadas en esa inspección (MD5 de pg_get_functiondef; firmas/grants/search_path se consultan en M00). Si newa avanza, reinspeccionar y adaptar; no reemplazarla por esta versión antigua ni por main:

| RPC | Huella observada |
|---|---|
| fn_registrar_venta_v3 | 97c58841e8a4ce7912fb6b6477b13723 |
| fn_registrar_venta_v3_impl | 2fa23774819d7accd358dc31ea8d3c6f |
| fn_registrar_venta_mesa_v3 | bb620c6f983e4b34f656dcc6fe4c38cb |
| fn_registrar_venta_mesa_v3_impl | f8aa6a1bf87631f6592407e4495de72b |
| fn_registrar_venta_offline_v4 | ef1dc813ab9c825d32a19a22b7ff7736 |
| fn_registrar_pago_venta_v3 | ea2778fb3b7bc312db00489b391affab |
| fn_admin_caja_precio_tpv_offline | 5d75dd184a7e3701260894b3be33f9dd |
| fn_editar_orden_pendiente_v2 | d9e4821bdf72b863c5d359993d0d615b |

### MC-002 — baseline ejecutado

Comando base en cada app: flutter.bat test --no-pub --reporter expanded, desde PowerShell. Se resumió stdout sin modificar tests ni el código de salida. Vendedor: 74 tests pasan, exit 0, en checkout_payment_lines, moneda_venta, moneda_venta_redondeo, multimoneda_core, descuento_multimoneda, order_usd_payments, payment_currency_amounts, home/product_detail_price_cache, home/product_detail_phase5, service_ingredients_warehouse, venta_ingredient_consumo y home/app_compile (todos bajo test/ con sufijo _test.dart). Admin: 36 tests pasan, exit 0, en precio_venta_contract, precio_venta_sql_contract, sales_totals_summary, service_inventory y app_compile.

Las dos líneas de error Sin permiso del admin son respuestas 403 ficticias previstas por los tests de permisos, no un fallo de autenticación real; se verificó su origen en los fixtures. No se ejecutó analyze, build, pruebas completas fuera de la selección, venta real ni impresión física. No se instalaron dependencias, iniciaron APIs de aplicación ni modificó Supabase; los mocks HTTP internos pertenecen a los tests. Este baseline refleja el árbol previo con cambios del usuario, no una rama limpia ni evidencia de que producto-v1 esté implementado.

### MC-003 — contrato y fixtures verificados

Se fijó el transporte en sección 15 de SPEC-product-currency-sale: versión única, IDs/decimales exactos, snapshots verificables, atribución de cobro y estado pendiente separado de medio real. Artefactos compartidos: product_currency_v1_fixtures.json y product_currency_v1_fixture_checks.sql en docs/plan-multimoneda; test de integridad en ventiq_app/test/product_currency_v1_fixtures_test.dart.

El SELECT numeric del oráculo se ejecutó en PostgreSQL newa sin tablas/RPC de negocio ni escrituras: los 14 casos finales devuelven passed=true. Detectó primero un expected incorrecto del fixture fractional_quantity: 0,125×10 da importe 1,25 pero unitario 10, no 1,25. Se añadió regresión que falló (exit 1), se corrigieron JSON/SQL y volvió a verde. No se relajaron cálculos ni umbrales.

Verificación final: flutter.bat test --no-pub --reporter expanded test/product_currency_v1_fixtures_test.dart y los 12 archivos de baseline del vendedor juntos: 81 tests pasan, exit 0. Admin conserva baseline de 36 tests, exit 0, sin cambios posteriores de código admin. dart.bat analyze test/product_currency_v1_fixtures_test.dart: No issues found, exit 0; formato aplicado únicamente al test nuevo. No se ejecutó análisis global ni build.

Trazabilidad de diseño/fixtures: PCS-02/03/04/06/07/08/09/10/12 y SPC-AC-01/07/09; no marcar estos criterios funcionales completos solo por este lote. Los casos de precio/inválidos son expectativas para resolver/validadores posteriores, no pruebas de su implementación. No se añadieron modelos/RPC de venta productivos, tablas, flag ni activación. Al cerrar el primer lote quedaron MC-004 y MC-005 en adelante como siguientes tareas; el avance posterior de MC-004 se registra a continuación. Los hallazgos de policies/fuentes mutables deben incorporarse a las revisiones siguientes.

## Avance MC-004 — spec preparada y REP aprobada

MC-004 completada como preparación de tasks/SPEC-product-currency-report-contracts.md, no como implementación ni aprobación del módulo. El usuario indicó continuar después del primer lote. REP fue aprobada por el usuario después de presentar la spec: MC-045 ya puede detallar las tareas M06, sin autorización automática para ejecutarlas. MC-005 está en curso; su matriz preliminar y bloqueo de alcance se registran a continuación.

MC-045: desglose M06 preparado en la sección «M06 — desglose de consumidores» (11 entregables R01–R11 con contrato y verificación propios, derivados de la spec aprobada). Estado: propuesto para revisión del usuario; no es aprobación de implementación ni autoriza SQL de escritura. R02/R05 son los únicos con SQL y requieren su puerta DB.

R01: entregado `ventiq_admin_app/lib/models/report_envelope.dart` — envelope estricto (`version_reporte`, `versiones_monetarias`, magnitud/base/completitud acotadas, motivos obligatorios en incompleto, conteos opcionales) + `MontoReporte` con decimales como cadenas exactas y suma que rechaza mezcla de monedas. Verificación: `test/report_envelope_test.dart` 11/11 en verde, analyze sin incidencias. Ningún consumidor migrado todavía: R03+ lo integran.

R03: entregado en `sales_service.getProductSalesReport` — (a) el fallback por-turnos a la RPC vieja solo se dispara cuando la función no existe (PGRST202/404/"does not exist"/"Could not find"), nunca ante error de red o permisos; (b) un payload que no sea lista lanza `ReporteContratoException` en vez de devolver `[]`; (c) el catch externo propaga (rethrow) en vez de fabricar «0 productos» — los tres llamadores ya tienen try/catch; (d) `ProductSalesReport.usaPreciosActuales` declara si la fila es análisis con precios vigentes o histórico, dos magnitudes no reetiquetables. Verificación: `test/product_sales_report_contract_test.dart` (2 tests) + suite R01 en verde; analyze sin errores nuevos (solo `avoid_print` preexistente). Pendiente de la tarea: la lectura estricta por versión de cada fila queda para R02/R04 — el parseo de fila actual sigue tolerante a ceros (contrato legacy).

R04: entregado en `sales_screen.dart` — (a) `_productSalesError` distingue «reporte no disponible» de «cero ventas»: un fallo de `getProductSalesReport` limpia filas y KPIs y muestra estado de error con reintento, en vez de presentar la lista vacía o totales del período anterior como dato válido; (b) el resto del contrato ya estaba: tarjeta «Ventas» etiquetada en moneda base, bloque «Por moneda» con consolidado y moneda de consolidación declaradas, aviso de tasa faltante, y PDF/Excel declaran el método de cálculo («Precios cobrados» vs «Precios de lista actuales») y la divisa en cabecera. Verificación: analyze de `sales_screen.dart` sin errores (solo warnings/infos preexistentes).

R02: propuesta `docs/plan-multimoneda/m01_r31_reporte_ordenes_v1_propuesta.sql` (script 54, borrador — no ejecutada). Función NUEVA `reporte_ordenes_json_v2(bigint,timestamptz,timestamptz,bigint)`: items con `version_monetaria` + `linea_v1` (id_linea_cliente, componentes nativos/equivalentes como cadenas decimales, medio seleccionado separado del cobrado), pagos por identidad con `aplicaciones` a línea (sin fan-out, LEFT JOIN a medios — desactivar no borra cobros), `totales_por_moneda` por orden y envelope R01 con completitud `V1_SIN_METADATA_DE_LINEA`. Añade validación de tienda en servidor (`fn_config_tienda_puede_leer`) que la v1 no tenía, y revoca anon. Contrato en `m01_r13_r16_sql_contract_test` (11 tests verdes). Adaptador cliente en `SalesService.getReporteOrdenesJson`: la auditoría de Ventas prefiere `reporte_ordenes_json_v2` y cae a la v1 solo si la función no existe (PGRST202/404); permisos y red no abren la v1. La v2 rellena `created_at` desde `fecha_operacion` y las líneas producto-v1 muestran el neto nativo en vez de `importe` NULL como 0. Pendiente: aplicar el script en newa.

R05: propuesta `docs/plan-multimoneda/m01_r32_ventas_por_moneda_v2_propuesta.sql` (script 55, borrador — no ejecutada). Verifiqué la definición real en newa (huella 91c3bae4): filtra operaciones por `created_at` + último estado 2 y atribuye pagos por `id_operacion_venta` sin mirar `fecha_pago` → es **cohorte de ventas**, no flujo de caja. La v2 declara exactamente eso: `magnitud='cobrado'`, `base_temporal='cohorte_ventas'`, corte resuelto, decimales exactos, `PAGOS_SIN_EQUIVALENTE_CUP` como incompletitud, medios por LEFT JOIN, `importe_consolidado` etiquetado como presentación con tasa actual, y `fn_config_tienda_puede_leer`. Contrato en `m01_r13_r16_sql_contract_test` (12 tests verdes). Adaptador cliente en `SalesService.getVentasPorMoneda`: prefiere `fn_reporte_ventas_por_moneda_v2`, exige magnitud `cobrado` y base `cohorte_ventas`, y cae a la v1 solo si la función no existe. Si el envelope marca `PAGOS_SIN_EQUIVALENTE_CUP`, el pie deja de llamarse total del corte. La v1 sigue sin esa aclaración. Pendiente: aplicar el script en newa.

R06: entregado en `customer_service.dart` — las ventas producto-v1 insertan `importe_total` NULL (el alta v1 no lo escribe) y las métricas de clientes las contaban como ventas de 0, diluyendo ticket medio y total del cliente. Nuevo adaptador `_netoComparableCupPorOperacion`/`_netoComparableDeVenta`: legacy usa `importe_total`, v1 suma `importe_neto_cup_equivalente` de sus líneas — misma magnitud (neto contable CUP), sin mezclar nativos. Aplicado a `getCustomerById` (métricas), `getCustomerMetrics` y `getTopCustomers`; los mapas devueltos declaran `total_sales_moneda`/`average_order_value_moneda = 'CUP'`. Verificación: analyze sin errores (solo `avoid_print` preexistente).

R08: clasificación ejecutada — consulté newa y **ninguna** de las 14 RPCs financieras existe (`fn_profit_and_loss`, `fn_sales_metrics`, `fn_inventory_metrics`, `fn_product/category_profitability`, `fn_cash_flow_projections`, `fn_historical_trends`, `fn_profitability_report`, `fn_category_profitability_analysis`, `fn_low_profitability_products`, `fn_historical_cash_flow`, `fn_historical_comparison`, `fn_trend_analysis`, `fn_budget_variance_analysis`). Cambios:
- `financial_dashboard_service`: eliminados `_getMockProfitAndLoss`/`_getMockKeyMetrics` (fabricaban $150k/$18k). Las fuentes devuelven `{'disponible': false}` y `getKeyMetrics` propaga no-disponible si cualquier componente falta; `getProfitAndLoss` declara `disponible:false + motivo` en vez del P&L inventado.
- `financial_reports_service`: eliminados los 6 `_getMock*`. `generateCashFlowProjections` deja de fabricar meses proyectados sobre historial vacío (antes promediaba `[]` y "proyectaba" con confidence 0.5). Todas las rutas devuelven `disponible:false + motivo`.
- Pantallas: `financial_dashboard_screen` muestra tarjeta "Información financiera no disponible" (con motivo) en vez de KPIs/P&L/gráfico de ceros; `financial_reports_screen` tiene `_buildUnavailableTab` por pestaña (Rentabilidad/Proyecciones/Presupuestos). Los `[]` de listas se conservan: el consumidor ya muestra "sin datos", que es literalmente cierto.
- `app_cont_gastos` (gastos reales por tabla) sigue siendo fuente válida; solo se marca no-disponible si la consulta falla.
Verificación: analyze sin errores (warnings `unused` preexistentes).

R09: entregado en `products_analytics_service.dart` — (a) `getStockTrends` devolvía una serie **simulada** (±15% sobre stock actual): ahora `[]` — no existe historial diario; (b) `getTopPerformingProducts` fabricaba `movimientos`=stock y `valorMovido`=stock×10: ahora `null` + `magnitud:'stock_actual'`; la tarjeta del dashboard pasó de "X mov." a "N uds. en stock" y el título a "Top 5 por stock"; (c) fallos ya no devuelven filas falsas "Sin datos/Sin alertas" ni "Sistema en funcionamiento" enmascarando errores; (d) `valorInventario` por categoría declara `valor_moneda:'CUP'` + `valor_base:'precio_venta_vigente'` (valuación de catálogo, no venta realizada); (e) defaults de KPIs/ABC/BCG marcan `disponible:false`. Eliminados los métodos `_getDefault*` muertos. Analyze sin errores.

R10: entregado en `sales_analyst_service.dart` — el contexto de IA ahora declara `magnitud_total_ventas:'venta_neta_base_cup'`, `base_temporal:'comercial'`, `modo_precios_productos` (derivado de `usaPreciosActuales` de R03: lista_actual vs precios_cobrados) y `cobertura` (conteos + incluye_ganancias). Cada vendedor lleva `desglose_monedas` (nativo/base por divisa) y `total_base_cup`. El prompt prohíbe sumar nativos entre divisas, exige aclarar cuando los precios son de lista vigente y prohíbe estimar cifras ausentes. `ocultar_ganancias` ya existía y sigue vetando costos/márgenes. Analyze sin errores (warning `invalid_null_aware_operator` preexistente en otro archivo).

R11 (consistencia transversal): revisada la cadena pantalla→exportación→widget→analista. Las cuatro superficies ya compartían los mismos servicios (sin endpoints paralelos): `sales_screen` y PDF/Excel consumen `getProductSalesReport`/`getVentasPorMoneda` con magnitud y divisa declaradas; el widget Mini Dashboard consumía los mismos RPCs pero tenía **una divergencia de magnitud**: si el reporte de ganancias fallaba, sustituía `gananciaBruta` por `totalSales` y mostraba `ventas − gastos` como "ganancia neta" — una cifra que la pantalla nunca mostraría. Corregido en `widget_data_repository`: el campo `ganancia_neta` queda `N/D` cuando el reporte no está disponible, igual que el widget muestra `N/D` por contrato con Kotlin. El analista (R10) recibe la misma `venta_neta_base_cup` con la cobertura declarada. Pendiente estructural conocido: `fn_reporte_ventas_por_moneda` mide cohorte de ventas mientras los KPIs de `fn_reporte_ventas_con_proveedor4` miden venta neta — distintas bases temporales ya etiquetadas cada una en su bloque (R05 documenta la semántica en servidor). Analyze: 0 issues en los archivos tocados.

Se contrastaron consumidores locales de ventas, pedidos, clientes, CxC, costos, dashboards, exportaciones, widgets, analista y ticket/cierre. Consultas exclusivamente de catálogo/definición en newa verificaron seis RPC de lectura y ausencia en public de fn_profit_and_loss/fn_sales_metrics. La definición de Por moneda agrega pagos por fecha de operación y último estado 2, aunque el comentario del servicio local afirma que no filtra estado. Hay fallbacks mock/ceros en servicios financieros: deben clasificarse y no presentarse como datos v1 reales. Los archivos SQL locales no se usaron para sustituir las versiones adelantadas de newa.

La spec propone separar venta neta, cobrado del período, cobrado por cohorte y saldo al corte; conservar CUP contable histórico y nativos sin mezclarlos; grano/identidades para evitar fan-out; costo desconocido distinto de cero; versiones y cobertura explícitas; mismos permisos/unidades en exportación/IA/widget. Presentación mínima propuesta: KPI contable con v1 etiquetado CUP, legacy-only conservado, sin nuevos desgloses visuales. Los cortes/intervalos nuevos requieren REP y adaptación sin alterar incidentalmente filtros legacy.

Verificación de esta tarea: revisión estática de fuentes/callers, lectura remota sin datos de negocio ni escrituras, 14 ejemplos y 12 criterios PCR-AC con traza PCS/SPC. No se ejecutaron nuevos tests Flutter/SQL funcionales de reportes: los ejemplos son expectativas para M06, no funciones ya implementadas. No se crearon migraciones, modificaron fuentes Dart, iniciaron APIs, activó flag ni tocó main. La aprobación de esta spec no autoriza SQL de escritura ni activación.

## Avance MC-005 — ampliación autorizada y preparación parcial M01-R0a

El usuario aprobó REP y después autorizó expresamente incluir protección de fuentes de roles y vínculos tienda/TPV/trabajador en M01. MC-005 está EN CURSO, no completada: ya no espera autorización de alcance, pero falta cerrar implementación y pruebas del conjunto de fuentes/entradas. Se consultaron metadatos, definiciones y conteos agregados de integridad, sin extraer identidades/perfiles ni ejecutar escrituras remotas. La autorización permite preparar/revisar SQL; no autoriza al agente a aplicarlo ni a activar tiendas.

### Hallazgo de raíz de confianza

- app_dat_gerente, app_dat_vendedor, app_dat_tpv y app_dat_trabajadores tienen RLS pero policies públicas ALL con true; app_dat_supervisor y auditor no tienen RLS. En las seis tablas el catálogo confirma grants anon INSERT/UPDATE/DELETE. En las cinco primeras salvo trabajadores no hay triggers no internos; trabajadores tiene uno pendiente de revisión. No se ejecutaron ataques ni pruebas con usuarios reales.
- app_dat_operaciones también permite ALL público; no basta proteger sus extracciones si se puede manipular el padre/tienda. Dueño y superadmin sí tienen policies específicas, pero requieren revisar sus helpers y flujos, no reemplazarlas por permisos amplios.
- El S01 permanece aplicado a configuración y no se reejecuta. Sin embargo, sus decisiones dependen de pertenencias de gerente/otras tablas: políticas correctas en configuración no hacen íntegra una fuente de roles modificable. No declarar M01 seguro ignorando este hallazgo.
- fn_user_can_access_tienda incluye dueño/gerente/supervisor/auditor, no vendedor ni superadmin. check_user_has_access_to_tienda incluye vendedor/almacén/cocina, pero no superadmin. Los helpers S01 sí contemplan superadmin activo nivel_acceso=1 y lectura de trabajadores autorizados. Ninguno es intercambiable como permiso genérico de venta/administración.
- SellerService exige fila de vendedor y trabajador para entrar a Caja; no ampliar a gerente/supervisor solo por tener acceso a tienda. El perfil local toma tienda del trabajador y almacén del TPV: validar en servidor que todas las relaciones coinciden.
- fn_admin_caja_precio_tpv_offline es DEFINER sin search_path fijo ni guardas de rol/tienda en su cuerpo observado; lookup UUID no comprueba tipo/propietario. AdminInventoryService intenta escritura directa tras cualquier error de esa RPC. No permitir fallback después de denegación.
- fn_registrar_venta_offline_v4 comprueba acceso a tienda, pero lookup UUID no compara tipo/actor/huella y replay puede volver a reescribir pagos. Proteger la tabla sola no protege una RPC DEFINER que la elude; tratar los 24 consumidores compartidos por tipo.

### Matriz preliminar de acciones, no concesión de permisos nueva

| Acción | Regla objetivo |
|---|---|
| Leer política/catálogo | Acceso de tienda según S01, sin convertirlo en permiso administrativo/financiero global. |
| Cambiar flag/política o precio TPV | Dueño/gerente de tienda o superadmin activo full, con capacidad backend requerida. Vendedor no, incluso si customiza precio de una venta. |
| Gestionar personal/vendedores/TPV y asignaciones | Decisión expresa del usuario: Solo administración (dueño/gerente/superadmin activo full). Supervisor conserva lectura, no gestión operativa; separar nómina legítima de Recursos Humanos de identidades/roles/vínculos. La regla de dueños sigue siendo más estricta: gerente no puede conceder propiedad. |
| Emitir constancia | Servidor para sujeto/dispositivo/tienda autorizados y finalidad concreta; lectura de configuración no concede capacidad de vender. |
| Crear venta propia en Caja | Vendedor autenticado, TPV/tienda/trabajador coherentes y autorización/licencia/constancia válidas. No confiar en p_uuid ni preferencias locales. |
| Sincronización delegada | Administrador autorizado de esa tienda, origen/sujeto/TPV demostrables, auditoría separando actor de vendedor original; no suplantación por parámetro. |
| Replay ya aceptado | Validar acceso actual al resultado y pertenencia/tipo/huella de clave, sin repetir efectos. No exigir crear otra venta para recuperar la respuesta. |
| Primer envío sin autorización suficiente | Retener para revisión autorizada; no borrar cola, convertir a legacy ni regenerar UUID. |
| Ajustar/cancelar/cobrar parcial | Validar objeto, estado, permisos específicos y alcance de línea/pago; acceso a tienda solo no basta. |
| Leer reportes/costo | Alcance y permiso de magnitud en servidor, según REP; no otorgar costo por ocultarlo solo en UI ni por bandera cliente. |
| Anon/otra tienda/rol solo lectura | Sin escrituras sensibles ni lectura de constancias/resultado ajeno. Multirrol se evalúa por pertenencias legítimas, no por etiqueta UI. |

### Contratos de helpers a cerrar en M01

Separar predicados de leer política, administrar tienda, operar como vendedor, delegar sincronización, leer resultado y consultar magnitudes. Actor siempre auth.uid(); sujeto/origen y TPV son parámetros a validar, nunca identidad autenticada por sí mismos. Resolver tienda desde relaciones protegidas; no usar id_tienda declarado como autoridad.

Funciones internas con privilegio restringido, objetos calificados/search_path fijo y sin EXECUTE público/anónimo; no romper wrappers legacy INVOKER al revocar impls a ciegas. RPC de entrada vuelve a validar; contexto/GUC enviado por cliente no acredita ejecución interna. RLS por sí sola no controla propietario/BYPASSRLS. Constancias y snapshots no los inserta/edita el cliente.

Casos de prueba pendientes: vendedor propio vs otro TPV/tienda; admin delegado con origen válido vs ajeno; perfil eliminado/incoherente; superadmin full vs inactivo/solo lectura; modificación directa de pertenencia para elevar privilegios; UUID de otro tipo/actor/tienda; misma clave con payload distinto; replay sin efectos; denegación de RPC seguida de fallback directo. Se diseñarán fixtures y harness por rol para ejecución autorizada del usuario: catálogo inspeccionado no equivale a pruebas RLS funcionales.

El alcance de raíces de confianza ya fue autorizado. Pendiente técnico: cerrar la clasificación de entradas/altas y preparar el conjunto de guardas/RLS/harness antes de dar M01 por aplicable. No crear un segundo registro de roles ni copiar membresías inseguras para eludir el problema. Producto-v1 no se activa mientras falten estos controles.

### Incremento preparado: preflight y propuesta parcial R0a

- `docs/plan-multimoneda/preflight_m01_fuentes_autorizacion.sql`: inventario en transacción READ ONLY / REPEATABLE READ, con grants (también TRUNCATE/TRIGGER/REFERENCES), policies, helpers, escritores textuales, triggers, FK y seis conteos de integridad. Se ejecutaron los bloques de lectura en newa sin errores; los seis conteos resultaron 0. Eso no prueba permisos por rol ni ausencia de otros problemas. No se extrajeron identidades/perfiles.
- El índice ampliado a schemas no internos encontró 97 funciones con escrituras textuales a las fuentes y padre de operaciones, en public y carnavalapp. Incluye comentarios/posibles falsos positivos y no descubre todo SQL dinámico/llamadas indirectas. Debe clasificarse por operación/columna; no convertir esos 97 resultados automáticamente en parches ni limitar la revisión a public.
- `docs/plan-multimoneda/m01_r0a_duenos_propuesta.sql`: borrador parcial, NO EJECUTAR aisladamente. Nuevo predicado acotado fn_m01_fuentes_puede_gestionar_duenos(bigint): dueño real de esa tienda o superadmin activo nivel 1, sin actor enviado por cliente. Cambia únicamente las cuatro policies conocidas de app_dat_dueno y sus grants; conserva lectura existente acotada, no modifica datos ni activa flag. Exige postgres, aprobación manual específica, baseline/hash exacto de policies, propietario/RLS esperados y aborta si ya existe el helper o cambia newa. Conserva DML de servicio existente, retira privilegios fuera del ámbito DML a authenticated y deja verificación transaccional.
- Se evitó cambiar globalmente fn_user_is_dueno: considera dueño a cualquier superadmin activo y tiene consumidores en personal, precios base y FDI (incluidas lecturas). El predicado nuevo evita esa ampliación para gestionar dueños sin alterar silenciosamente todos esos contratos. Los demás usos del helper legado siguen pendientes de clasificación; no declararlos endurecidos.
- `docs/plan-multimoneda/verificar_m01_r0a_duenos.sql`: solo catálogo, muestra atributos/grants/definición/policies para revisión; no certifica RLS funcional. La consulta de estado en newa confirmó helper_presente=false, grants antiguos y RLS activo: R0a NO está aplicado. MCP reportó supabase_read_only_user en esa inspección; no se usa como prueba de permisos de vendedor/gerente.
- `ventiq_admin_app/test/m01_duenos_sql_contract_test.dart`: checks estáticos del borrador y scripts de lectura, no simulación de autorización real. Primero falló por artefacto inexistente; después pasó el contrato inicial de cuatro tests junto al baseline (40 tests). Verificación final con el quinto check de lectura/no DDL: 41 tests pasan, exit 0 (cinco nuevos + 36 de baseline). Comando desde ventiq_admin_app: flutter.bat test --no-pub test/m01_duenos_sql_contract_test.dart test/precio_venta_contract_test.dart test/precio_venta_sql_contract_test.dart test/app_compile_test.dart test/sales_totals_summary_test.dart test/service_inventory_test.dart. dart.bat analyze test/m01_duenos_sql_contract_test.dart: No issues found, exit 0. Los mensajes 42501 corresponden a pruebas negativas fake ya presentes; no se cambió su manejo. No se ejecutó el DDL propuesto en PostgreSQL ni se verificó su comportamiento por roles reales. No hay psql/docker disponibles en PATH para compilación local; no se intenta compensarlo con escrituras remotas.

### Cortes restantes de raíces M01, dentro del alcance autorizado

| Corte | Trabajo pendiente antes de liberar el paquete |
|---|---|
| R0a | Revisar policies/grants de dueño y compilar/probar el borrador por roles en el entorno autorizado; no interpretar tests de texto como aceptación DB. |
| R0b | Gerente, supervisor, auditor, vendedor y trabajador: guardas de fuente y perfiles, roles legítimos, OLD/NEW tienda y enlaces coherentes. No promover por etiqueta/id_roll ni aceptar p_uuid como actor. |
| R0c | TPV, almacén/cocina y sus roles/vínculos: proteger los destinos usados para resolver alcance sin romper operaciones legítimas de cocina/inventario. No mover stock ni corregir históricos por esta migración. |
| R0d | Alta inicial/crear_estructura_tienda, asignación/edición/baja/restauración y entradas DEFINER/INVOKER: la creación de una tienda nueva no tiene todavía pertenencia previa. Necesita entrada protegida y ámbito derivado de lo realmente creado, sin bootstrap genérico sobre una tienda existente ni GUC del cliente como autoridad. |
| R0e | Integrar fuentes con guardas de operaciones e idempotencia compartida, pruebas concurrentes y permisos DML/DDL. Preservar usos legítimos admin/turno/egreso y callbacks de Carnaval; sin fallback tras denegación ni borrado de cola. |

Compatibilidad localizada: VendedorService reasignar/desasignar envía updated_at, columna que no apareció en el catálogo de app_dat_vendedor inspeccionado. Registrar y verificar esa diferencia antes de usar ese recorrido como prueba de hardening; no añadir columnas o ampliar permisos para esconder el error. También hay actualizaciones directas de salarios/UUID de trabajador y flags/TPV que deben conservar su autorización administrativa legítima.

Contratos de helpers: lectura de política mantiene S01; administrar política/precio usa autoridad dueño/gerente/full solo después de proteger sus fuentes; gestionar dueños usa predicado más estricto sin gerente implícito. Crear venta exige vendedor/TPV/trabajador coherentes; delegar primer envío exige administrador y procedencia/sujeto demostrables; replay aceptado exige acceso al resultado y clave/tipo/huella sin repetir efectos. No usar permiso de crear venta como condición para recrear una ya aceptada. Las guardas de mutación validan ambos ámbitos OLD/NEW; un perfil sin ámbito demostrable se retiene/revisa, no se le inventa tienda. Service_role/propietario no demuestran permisos de usuario final ni autentican un vendedor original por parámetro.

Estado: ampliación autorizada y primeros artefactos preparados; MC-005/M01 siguen EN CURSO. No aplicar R0a hasta revisar dependencias y pruebas del paquete; sin DDL remoto, cambios productivos Dart, APIs iniciadas, flag activado ni cambios en main.

### R0b — trazado adicional en curso

- El trigger existente de trabajadores es trg_sync_trabajador_user_mail, BEFORE INSERT/UPDATE OF uuid: deriva user_mail desde auth.users. No sincroniza UUID de las tablas de roles. Se leyó su definición, no filas de auth.users.
- fn_editar_trabajador_basico modifica solo trabajador.uuid (COALESCE) y no sus roles. WorkerService.updateWorkerUUID también actualiza directamente ese campo. Un simple guard de integridad puede bloquear esta ruta o dejar roles incoherentes: hace falta definir actualización coordinada/atómica, no copiar UUID históricos.
- fn_actualizar_datos_rol_trabajador es INVOKER y maneja vendedor/almacenero/cocina. fn_admin_caja_vendor_assign_tpv_offline es DEFINER sin guardas observadas, lookup global UUID y sin control de tienda/origen/tipo. fn_restaurar_trabajador también es DEFINER y sin guardas en el cuerpo leído. No basta endurecer RLS.
- PermissionsService permite rutas workers y HR a recursosHumanos y supervisor; no conceder gestión de identidades por poder ver una pantalla, pero tampoco bloquear salarios legítimos con un guard genérico gerente-only sobre toda la fila. fn_hr_update_worker_salary cambia únicamente campos salariales, es DEFINER y usa p_modificado_por para auditoría sin validar actor en el cuerpo observado. Separar capacidades de identidad y nómina, validar auth.uid y ámbito.
- La consulta de definiciones no encontró fn_desvincular_usuario_trabajador en public aunque WorkerService.removeWorkerUser la llama. Confirmar ausencia/firma antes de usar desvinculación como prueba de compatibilidad; no borrar cuentas Auth ni roles históricos como solución automática.
- Próximo incremento concreto: regresión HTTP ficticia para VendedorService.asignarVendedorATpv/desasignarVendedorDeTpv que detecte el envío de updated_at inexistente en newa y verifique que 403 no provoca otro intento. Corregir solo ese payload incompatible, sin cambiar permisos ni inventar columnas. Después continuar R0b SQL y coordinación de altas/UUID.

### R0b — atributos de catálogo newa (solo lectura) y cliente alineado

- Atributos confirmados en newa: `crear_estructura_tienda`, `fn_editar_trabajador_basico` y `fn_actualizar_datos_rol_trabajador` son INVOKER (prosecdef=false): con RLS endurecido el alta inicial y la edición de identidad quedan gobernados solo por policies; el creador de una tienda nueva todavía no tiene pertenencia, por lo que R0d necesita entrada DEFINER validada o conversión del flujo, no una policy genérica de bootstrap.
- DEFINER sin `search_path` fijo: `crear_tpv_completo`, `create_gerente_from_email`, `fn_admin_caja_tpv_create_offline`, `fn_admin_caja_tpv_update_offline`, `fn_admin_caja_vendor_assign_tpv_offline`, `fn_admin_caja_vendor_flags_offline`, `fn_asignar_vendedor`, `fn_desasignar_vendedor`, `fn_asignar_supervisor`, `fn_desasignar_supervisor`, `fn_hr_update_worker_salary`, `fn_restaurar_trabajador` y `fn_is_superadmin_full_access`. `fn_user_is_dueno` y `fn_asignar_jefe_cocina` fijan `search_path=public`; `fn_config_tienda_puede_escribir` ya usa `pg_catalog` (S01). `fn_desvincular_usuario_trabajador` confirmada ausente en public; la guarda R0b aún no existe (esperado).
- `docs/plan-multimoneda/m01_r0b_rpc_reasignacion_vendedor_propuesta.sql`: segundo borrador parcial, NO EJECUTAR. `fn_m01_personal_reasignar_vendedor(bigint,bigint)` DEFINER con `search_path=pg_catalog`: invoca la guarda (que hereda `auth.uid()` del contexto del llamador), hace el único `UPDATE id_tpv` permitido y devuelve boolean; EXECUTE solo para `authenticated` (PUBLIC/anon revocados; service_role sin grant). Preflight exige la guarda ya instalada: orden de aplicación guarda → RPC, ambas tras revisión del conjunto M01. La ruta offline `fn_admin_caja_vendor_assign_tpv_offline` debe reutilizar la misma guarda en su endurecimiento (R0e), no duplicar lógica.
- Cliente alineado a "Solo administración" en `permissions_service.dart`: `worker.create/edit/delete`, `tpv.create/edit/delete`, `tpv_price.*`, `vendor.assign_tpv/unassign_tpv/create/delete/edit_price_permission` y `settings.edit` quedan solo `gerente` (dueño tiene bypass; superadmin full lo valida el servidor). Supervisor y auditor conservan las pantallas/lectura; Recursos Humanos conserva `hr.*` y pierde `worker.*`. `settings.edit` y `tpv_price.*` ya eran denegados en servidor por S01: el cliente dejaba de prometer una escritura imposible. Permiso de UI no es autoridad; las policies/RLS siguen siendo la frontera real (M01).
- Nuevas pruebas estáticas: `m01_personal_admin_scope_test.dart` (3 tests: acciones solo-administración, lectura supervisor, nómina RH) y 4 tests R0b-RPC en `m01_personal_sql_contract_test.dart` (preflight+dependencia de guarda, firma sin actor/ámbito declarados, única escritura `id_tpv`, EXECUTE solo authenticated). Lote verificado: 21/21 tests verdes (guarda, RPC, alcance cliente, asignación, dueños) más `dart analyze` limpio y `git diff --check` limpio. Son contratos estáticos, no prueba funcional de RLS.
- Dependencia de despliegue registrada: cuando el paquete R0b se aplique, `VendedorService.asignarVendedorATpv/desasignarVendedorDeTpv` debe pasar de escritura directa a `fn_m01_personal_reasignar_vendedor` (la escritura directa quedará denegada por policies); hasta entonces el servicio actual sigue siendo la ruta vigente. No cambiar el servicio antes de aplicar el SQL: la RPC aún no existe.
- `docs/plan-multimoneda/verificar_m01_r0b_personal.sql`: verificador de solo catálogo para guarda+RPC (presencia, atributos DEFINER/`pg_catalog`, EXECUTE según diseño) e inventario de policies de vendedor/trabajadores/TPV. Estado previo confirmado en newa con lectura: `guarda_presente=false`, `rpc_presente=false`. No certifica RLS funcional.
- `docs/plan-multimoneda/m01_r0b_policies_personal_propuesta.sql`: tercer borrador parcial, NO EJECUTAR. Baseline newa confirmado: trabajadores ('all workers' ALL + 'worker police select' SELECT, ambas public/true), vendedor ('Open access to vendedor' + 'select all' SELECT + 'all vednedor' ALL, public/true). Sustituye esas 5 policies por 8 acotadas a authenticated: lectura propia (`uuid = auth.uid()`) + `fn_config_tienda_puede_leer` + RH vía nuevo helper `fn_m01_personal_es_recursos_humanos` (solo trabajadores); escrituras solo `fn_config_tienda_puede_escribir` del ámbito derivado (vendedor resuelve tienda por trabajador→TPV vía `fn_m01_personal_vendedor_id_tienda`/`fn_m01_personal_tienda_para_vinculos`, que devuelven NULL ante vínculos incoherentes). Revoca tabla a anon y UPDATE tabular a authenticated, dejando GRANT por columna: trabajadores solo (nombres, apellidos, maneja_apertura_control); vendedor solo (numero_confirmacion, permitir_customizar_precio_venta). Identidad (uuid/id_tienda/id_roll/deleted_at/user_mail), nómina y vínculos (id_tpv/id_trabajador) pasan a exigir RPC privilegiada.
- Dependencias duras declaradas en el propio SQL: `fn_editar_trabajador_basico` y `fn_actualizar_datos_rol_trabajador` (INVOKER) perderán acceso a columnas restringidas hasta convertirse/sustituirse por rutas DEFINER validadas; `WorkerService.updateWorkerUUID` quedará bloqueado (identidad por RPC pendiente); INSERT de trabajadores exige `fn_config_tienda_puede_escribir` y bloquea `crear_estructura_tienda` hasta R0d. Preflight aborta si falta S01/RH, si el baseline de policies cambió o si ya existen helpers; solo WARNING si falta la RPC de reasignación.
- Hallazgo nuevo registrado: `app_dat_recursos_humanos` tiene `rls=false` y sin policies; se usa como fuente de pertenencia RH en el predicado de lectura y necesita su propio endurecimiento antes de liberar M01.
- `docs/plan-multimoneda/m01_r0b_identidad_trabajador_propuesta.sql`: cuarto borrador parcial, NO EJECUTAR. `fn_m01_personal_vincular_usuario_trabajador(bigint,uuid)` DEFINER/`pg_catalog`: via única para cambiar a qué usuario Auth pertenece un trabajador (sustituye `WorkerService.updateWorkerUUID` y la parte de identidad de `fn_editar_trabajador_basico`). Lock FOR UPDATE, exige `fn_config_tienda_puede_escribir` sobre la tienda derivada del trabajador, valida uuid en `auth.users`, sin duplicado activo, y RECHAZA trabajador con fila en `app_dat_dueno` o uuid en `app_dat_superadmin` (propiedad/superadmin van por dominio R0a). Actualización atómica: `trabajadores.uuid` + las 7 tablas de rol con `id_trabajador` (vendedor, almacenero, supervisor, auditor, gerente, jefe_cocina, recursos_humanos) — uuid es identidad, todas las filas siguen a la misma persona. Desvincular (uuid NULL) queda fuera: `fn_desvincular_usuario_trabajador` no existe y su semántica requiere decisión aparte. EXECUTE solo authenticated. Columnas confirmadas en newa: todas las tablas de rol tienen `id_trabajador`; escritores de RH son las INVOKER `fn_*_trabajador_completo`.
- `docs/plan-multimoneda/m01_r0b_policies_recursos_humanos_propuesta.sql`: quinto borrador parcial, NO EJECUTAR. Activa RLS en `app_dat_recursos_humanos` (baseline verificado: `rls=false`, 0 policies): lectura propia/tienda/pertenencia RH (usa `fn_m01_personal_es_recursos_humanos` — dependencia de orden tras policies_personal), altas/bajas solo `fn_config_tienda_puede_escribir`. UPDATE no se concede: las filas son pura pertenencia y mutarlas en sitio cambiaría identidad (vía: baja+alta o RPC de identidad). Las INVOKER `fn_*_trabajador_completo` siguen operando para gerente/dueño bajo policy.
- Tests: 8 nuevos contratos (5 identidad, 3 RH); lote `m01_personal_sql_contract_test.dart` completo 19/19 verdes. Contrato estático, no prueba funcional.

### R0c — infraestructura y membresías de roles (borradores preparados)

Baseline newa confirmado (solo lectura): `app_dat_tpv` RLS + 2 policies public/true ('Open access to tpv', 'all on tpv'); `app_dat_almacen` RLS + 'almacne' ALL public; `app_dat_almacenero` RLS + 'almacenero' ALL public; `app_dat_gerente` RLS + 'geneente' ALL public; `seg_roll` RLS + 'seg_toll' ALL public; `app_dat_cocina`, `app_dat_jefe_cocina`, `app_dat_supervisor` y `auditor` SIN RLS ni policies. `app_dat_superadmin` ya tiene policies específicas authenticated (revisar sus quals en R0a/ampliación, no en este corte).

- `docs/plan-multimoneda/m01_r0c_policies_tpv_almacen_cocina_propuesta.sql`: NO EJECUTAR. 12 policies authenticated (4×3) con lectura `fn_config_tienda_puede_leer` y escritura `fn_config_tienda_puede_escribir`; activa RLS en cocina; coherencia `id_almacen→almacen.id_tienda` en INSERT/UPDATE de tpv y cocina; helpers `fn_m01_personal_tienda_de_almacen`/`_de_cocina` (STABLE DEFINER pg_catalog, EXECUTE authenticated). Columnas operativas directas: tpv (denominacion/modo_servicentro/servicentro_columnas), almacen (denominacion/direccion/ubicacion/es_cocina), cocina (denominacion/descripcion/impresora/orden/activa); `id_tienda`/`id_almacen`/`deleted_at` solo por rutas privilegiadas.
- `docs/plan-multimoneda/m01_r0c_policies_roles_propuesta.sql`: NO EJECUTAR. 20 policies authenticated en almacenero, jefe_cocina (RLS activado), supervisor (RLS activado), auditor (RLS activado), gerente y seg_roll. Membresía = alta/baja por policy: UPDATE revocado salvo `es_jefe` (jefe_cocina) y `denominacion/descripcion` (seg_roll). Lectura: `uuid = auth.uid()` (detección de rol del cliente) + acceso de tienda derivado por almacén/cocina/tienda. INSERT con coherencia trabajador↔ámbito vía `fn_m01_personal_tienda_de_trabajador`. seg_roll: lectura de roles globales (id_tienda NULL) y propios; filas globales solo `fn_is_superadmin_full_access()` (incluye GRANT EXECUTE).
- Dependencias: R0c-roles requiere R0c-infra (helpers de ámbito). `fn_actualizar_datos_rol_trabajador` y `fn_agregar/eliminar_rol_trabajador` (INVOKER) siguen operando para gerente/dueño por policy, pero pierden las columnas de rol revocadas hasta su conversión DEFINER (R0d); `fn_asignar_*` DEFINER siguen funcionando.
- Tests: 8 contratos en `m01_r0c_sql_contract_test.dart`; lote completo 41/41 verdes. Contrato estático, no funcional.

### R0d — entradas protegidas y alta inicial (borrador preparado)

Baseline: todas las RPC de asignación devuelven `jsonb` salvo `create_gerente_from_email` (TABLE); `app_dat_tienda` tiene RLS + 1 policy 'tienda policy' (qual pendiente de revisión en R0e); `app_dat_operaciones` tiene 2 policies ('Open access to operaciones', 'operaciones permitidas') y `app_dat_operacion_offline_idempotencia` sigue sin RLS.

- `docs/plan-multimoneda/m01_r0d_entradas_protegidas_propuesta.sql`: NO EJECUTAR. Tres acciones sin tocar cuerpos legacy:
  1. `ALTER FUNCTION ... SET search_path = pg_catalog, public` en 14 DEFINER sin path fijo o con `public` débil (asignaciones, crear_tpv_completo, create_gerente_from_email, insertar/restaurar trabajador, hr_update_worker_salary, is_superadmin_full_access, user_is_dueno, check_is_hr_user, hr_assert_access) y en `crear_estructura_tienda`, que es INVOKER y nombra `app_dat_tienda` sin esquema. El wrapper deja `search_path=pg_catalog`; sin este ALTER el alta responde que la tabla no existe. Corregido en newa el 2026-11-17.
  2. `REVOKE EXECUTE` de PUBLIC/anon/authenticated en las 8 DEFINER sensibles (ejecutan como postgres sin guardas); `service_role` conserva EXECUTE para llamadas servidor legadas.
  3. Ocho wrappers `fn_m01_*` DEFINER/`pg_catalog` que validan `auth.uid()` + `fn_config_tienda_puede_escribir` del ámbito derivado + coherencia trabajador/TPV/cocina↔tienda, y delegan en la legacy. `fn_m01_crear_tpv` fija `usuario_registrador := auth.uid()`. `fn_m01_crear_estructura_tienda` elimina el parámetro `usuario_creador` y fija el creador a `auth.uid()`. No exige superadmin ni 'Gerente General': el alta es de un usuario que todavía no pertenece a ninguna tienda. EXECUTE solo authenticated. La guarda de rol previo quedó aplicada en newa y bloqueaba el registro; el 2026-11-17 se corrige el cuerpo para aceptar cualquier autenticado.
- Resuelve el problema R0d del alta inicial: `crear_estructura_tienda` (INVOKER) queda protegida por wrapper DEFINER; las INSERTs internas corren como postgres y las policies R0b/R0c no la rompen. La llamada directa legacy queda denegada.
- Dependencia de despliegue: el cliente debe migrar llamadas `fn_asignar_*/crear_*` a `fn_m01_*` al aplicar; documentado junto al switch de `VendedorService`.
- Tests: 5 contratos en `m01_r0d_sql_contract_test.dart`, verdes. Contrato estático, no funcional.

### R0e — tienda, operaciones e idempotencia (borrador preparado)

Baseline newa (lectura): `app_dat_tienda` 'tienda policy' ALL public/true; `app_dat_operaciones` 'Open access to operaciones' SELECT public/true + 'operaciones permitidas' ALL public/true; `app_dat_operacion_offline_idempotencia` sin RLS ni policies (columnas: client_uuid, id_operacion, tipo, uuid_usuario, created_at). `app_dat_superadmin` YA tiene policies acotadas (own/full): no se toca.

- `docs/plan-multimoneda/m01_r0e_operaciones_tienda_idempotencia_propuesta.sql`: NO EJECUTAR.
  1. Helper `fn_m01_operaciones_puede_operar(bigint)` STABLE DEFINER/`pg_catalog`: operar (escritura de operaciones) = admin O vendedor/almacenero/jefe_cocina de esa tienda. Distinto de `puede_leer`, que incluye supervisor/auditor (solo lectura).
  2. `app_dat_tienda`: lectura `puede_leer(id)`, UPDATE solo `puede_escribir(id)`; INSERT/DELETE sin policy → denegado para authenticated (el alta legítima es el wrapper R0d DEFINER). Columnas de tienda quedan concedidas bajo esa policy hasta mapear campos (pendiente explícito).
  3. `app_dat_operaciones`: SELECT `puede_leer`, INSERT `puede_operar` (auditor/supervisor no insertan), UPDATE/DELETE solo admin. Las ventas offline siguen por RPC DEFINER.
  4. `app_dat_operacion_offline_idempotencia`: RLS on; authenticated solo lee sus propias claves (`uuid_usuario = auth.uid()`), sin INSERT/UPDATE/DELETE de cliente (es interna de las RPC de sync); anon sin tabla. Enmienda 2026-11-16: `REVOKE ALL ON TABLE` no retira GRANTs por columna ni los de PUBLIC; el borrador ahora revoca `FROM PUBLIC, anon, authenticated` a nivel tabla, revoca `REVOKE ALL (columnas)` por columna vía `pg_attribute` y añade un bloque de verificación que aborta si queda privilegio efectivo de escritura (INSERT/UPDATE por columna, DELETE/TRUNCATE/TRIGGER tabular) o lectura de anon. Lectura newa 2026-11-16 confirma que hoy anon y authenticated conservan INSERT/UPDATE/TRUNCATE/TRIGGER tabulares y UPDATE por columna sobre esa tabla: el revoke sigue siendo necesario.
- Pendiente explícito de este corte: endurecimiento interno de `fn_admin_caja_*` y `fn_registrar_venta_offline_v4` (guardas + serialización de reintentos) y revisión de quals de `app_dat_superadmin` (ya acotadas, verificar suficiencia).
- Tests: 5 contratos en `m01_r0e_sql_contract_test.dart`, verdes (incluye el revoke tabular/columna de idempotencia y la verificación). Contrato estático, no funcional.
- `docs/plan-multimoneda/verificar_m01_r0e_operaciones.sql`: verificador de solo lectura post-aplicación.
- `docs/plan-multimoneda/m01_orden_aplicacion.md`: orden de aplicación de los 10 scripts (R0a→R0e), advertencia de ventana de bloqueo del alta inicial entre los cortes 4–9, tabla de migración de clientes a `fn_m01_*` y pendientes fuera del paquete (INVOKER de rol, `fn_admin_caja_*`/`fn_registrar_venta_offline_v4`, columnas de tienda, harness funcional por rol).
- `docs/plan-multimoneda/verificar_m01_r0c_r0d.sql`: verificador combinado R0c+R0d de solo lectura (RLS en tablas expuestas, residuales permisivas = 0 en todas las tablas M01, helpers y wrappers DEFINER con `search_path=pg_catalog`, EXECUTE de wrappers solo authenticated, legacy sensibles solo service_role, guarda interna sin EXECUTE para cliente).

Estado del paquete M01: **10 scripts de cambio + 4 verificadores + documento de orden**, todos borradores NO EJECUTAR con preflight/aprobación.

### R0f — INVOKER de rol convertidas a entradas DEFINER (borrador preparado)

Baseline newa: `fn_editar_trabajador_basico`, `fn_agregar_rol_trabajador`, `fn_actualizar_datos_rol_trabajador` y `fn_eliminar_rol_trabajador` son INVOKER y devuelven `jsonb`; `fn_agregar_rol_trabajador` recibe `p_id_tienda`/`p_usuario_uuid` declarados por el llamador.

- `docs/plan-multimoneda/m01_r0f_invoker_roles_propuesta.sql`: NO EJECUTAR. Cuatro wrappers `fn_m01_*` DEFINER/`pg_catalog` con firma compatible que validan `auth.uid()` + `puede_escribir` de la tienda **derivada del trabajador** (lock FOR UPDATE) + coherencia TPV/almacén/cocina↔tienda, y delegan en la INVOKER legacy (que corre como postgres dentro del DEFINER).
  - Edición básica rechaza `p_uuid` (identidad solo por `fn_m01_personal_vincular_usuario_trabajador`).
  - Agregar rol exige `p_id_tienda = trabajadores.id_tienda` y `p_usuario_uuid = trabajadores.uuid`; delega con los valores derivados, no los declarados.
  - El rol `dueno` queda excluido de agregar/actualizar/eliminar (más estricto, R0a).
  - `REVOKE EXECUTE` de las 4 legacy a PUBLIC/anon/authenticated; wrappers solo `authenticated`.
- Tests: 4 contratos en `m01_r0f_sql_contract_test.dart`, verdes. Contrato estático, no funcional.

Pendientes fuera del paquete: endurecimiento interno de `fn_admin_caja_*`/`fn_registrar_venta_offline_v4` (guardas + serialización de reintentos), mapeo de columnas de `app_dat_tienda`, semántica de `fn_desvincular_usuario_trabajador` y harness funcional por rol.
- Tests: 4 nuevos contratos R0b-policies en `m01_personal_sql_contract_test.dart`; lote verificado 25/25 verdes (guarda, RPC, policies, alcance cliente, asignación, dueños). Sigue siendo contrato estático, no prueba funcional.

### R0g y primer corte R0h — preparación local, no aplicados (2026-11-14)

- Se reconcilió el seguimiento con `m01_r0g_offline_definer_propuesta.sql`, que ya existía en disco pero no estaba registrado en el orden. R0g restringe EXECUTE anónimo y fija search_path; authenticated conserva ejecución y las guardas internas siguen siendo trabajo R0h. No equivale a autorización completa de la flota.
- Se inspeccionó por MCP de solo lectura en newa `fn_admin_caja_vendor_assign_tpv_offline(uuid,bigint,bigint)`: DEFINER postgres, MD5 de definición `b388fa6c890a5b229a51f2ce910f07ae`, MD5 de prosrc `505a3b0c355f07ca4e6fa14fa8d7dd93`. Consulta UUID sin tipo/actor/payload, devuelve replay sin autorización y hace UPDATE sin comprobar fila. La tabla de idempotencia tiene cinco columnas y PK global client_uuid. Una consulta adicional inspeccionó el primer INSERT textual de sus 24 funciones consumidoras: todos declaran columnas explícitas, compatibles con añadir columnas nullable. Esto no descarta SQL dinámico, escrituras externas ni otros INSERT dentro de un mismo cuerpo. No se consultaron filas de negocio ni se ejecutaron mutaciones.
- Nuevo borrador parcial `docs/plan-multimoneda/m01_r0h_vendor_assign_offline_propuesta.sql`: conserva firma/respuesta, actor desde auth.uid(), guarda R0b para el primer envío y advisory lock transaccional por UUID antes del lookup. Agrega únicamente `m01_solicitud jsonb` y `m01_id_tienda bigint` nullable a la tabla compartida existente; no crea tablas, hace backfill ni altera claves anteriores. Compara solicitud exacta generada por servidor (incluido destino NULL), tipo, actor y vendedor. Replay exige acceso administrativo actual a la tienda registrada y devuelve resultado original sin repetir UPDATE ni exigir volver a crear la asignación. Conflicto con otra entrada no cooperativa provoca rollback por PK, no ON CONFLICT silencioso.
- UUID legacy sin evidencia nueva se rechaza para revisión, conservando la cola; no reconstruir payload, regenerar clave ni reejecutar automáticamente. Otras RPC aún no adaptadas pueden seguir consumiendo incorrectamente claves globales: este corte NO cierra el riesgo transversal. La serialización de dos sesiones y los permisos funcionales todavía no están probados.
- Preflight exige aprobación manual específica/postgres, cuerpo baseline exacto (independiente de los atributos que cambia R0g), guarda R0b, wrapper R0f y RLS/ausencia de escrituras cliente sobre idempotencia. No sustituye revisar el paquete completo ni probar todas las fuentes. Solo authenticated recibe EXECUTE de esta entrada; sin ruta service_role implícita porque también se exige sujeto Auth real.
- `m01_orden_aplicacion.md` enumera ahora 13 scripts e incluye limitaciones y pruebas pendientes de R0h. Los estados antiguos de 10 scripts/R0a parcial de secciones anteriores son evidencia histórica, no el inventario actual.
- TDD local: `m01_r0h_sql_contract_test.dart` falló primero por archivo SQL inexistente (exit 1); después pasaron sus 4 contratos estáticos. Lote final: 96 tests pasan (60 M01/asignación + 36 baseline admin), incluyendo los diez archivos M01/asignación y precio_venta_contract, precio_venta_sql_contract, app_compile, sales_totals_summary y service_inventory. `dart.bat analyze test/m01_r0h_sql_contract_test.dart`: sin incidencias, exit 0. `git diff --check`: exit 0, con advertencias CRLF de archivos previos ajenos. Estos checks NO compilan ni ejecutan PL/pgSQL y NO prueban RLS ni concurrencia.
- Siguiente incremento: seguir clasificando/endureciendo las otras entradas `fn_admin_caja_*` y `fn_registrar_venta_offline_v4`, preparar harness PostgreSQL por rol/concurrencia y revisar dependencias de cliente. MC-005 sigue EN CURSO; MC-006–MC-009, ejecución M01 y activación no se consideran desbloqueadas. Sin cambios Dart productivos en este corte, APIs iniciadas ni cambios en main. Todos los SQL nuevos siguen como propuestas para revisión, no instrucciones de ejecución inmediata.

### Segundo corte R0h y cliente Admin Lite — preparación/verificación local (2026-11-14)

- Inspección de solo lectura en newa: `fn_admin_caja_vendor_flags_offline(uuid,bigint,boolean)` es DEFINER postgres, cuerpo MD5 `9034dcd2f4ad7c8c5d2cee664c3bc709`; consulta UUID global sin comprobar tipo/actor/solicitud y no comprueba fila modificada. Se verificaron nombres/tipos de las columnas de vendedor/trabajador, sin consultar datos personales ni ejecutar operaciones de negocio.
- `docs/plan-multimoneda/m01_r0h_vendor_flags_offline_propuesta.sql`: conserva firma/respuesta y NULL→false legacy, pero conserva el argumento original en la solicitud exacta para que NULL y false no intercambien un UUID. Actor auth.uid(), lock por UUID compartido con asignación, replay por tipo/actor/vendedor/solicitud/acceso administrativo actual a tienda registrada, sin repetir UPDATE. Primer envío bloquea vendedor y vínculos existentes; rechaza trabajador eliminado, UUID incoherente, vínculo inexistente y trabajador/TPV de tiendas distintas. Sin TPV puede administrar si el trabajador válido demuestra tienda; sin trabajador puede demostrarla un TPV válido; sin ninguno bloquea. No llama una guarda de reasignación ni modifica id_tpv.
- Depende de las columnas de evidencia del primer R0h y de M01 completo; no añade tablas/columnas, reconstruye históricos ni aplica cambios remotos. Preflight con aprobación separada, baseline de cuerpo, tipos de evidencia, RLS y ausencia de escritura cliente en idempotencia. El orden registra 14 scripts de cambio, todavía propuestas no liberadas.
- `docs/plan-multimoneda/m01_r0h_vendor_flags_harness.sql`: harness parcial con fixtures de prueba revisados y aprobación específica; SET LOCAL ROLE authenticated/anon, claims simulados, primer envío, replay después de otro cambio, payload distinto, colisión entre tipo flags/asignación, UUID legacy sin evidencia, NULL→false, actor sin acceso y denegación anónima. Inserta solo una clave sintética legacy y usa claves aleatorias para sus llamadas, todo dentro de BEGIN/ROLLBACK. Aborta con triggers de usuario activos en vendedor/idempotencia. NO EJECUTADO: sigue pendiente compilación SQL, roles adicionales/aislamiento completo, JWT real y concurrencia de dos sesiones. Instrucciones/restricciones en m01_orden_aplicacion; no usar datos reales/main ni asumir que ROLLBACK neutraliza cualquier integración externa.
- Hallazgo cliente confirmado en `ventiq_app/lib/services/admin_inventory_service.dart`: los dos handlers de vendedor hacían UPDATE directo después de cualquier error de RPC y podían marcar una denegación como sincronizada. Se eliminaron únicamente esos dos fallbacks; se valida success/idempotent/id_vendedor antes de marcar sync. Constructor forTesting con cliente/cola inyectables sigue el patrón existente de servicios; singleton productivo conservado. Error llega a syncPendingOps, que registra last_error sin borrar operación ni regenerar UUID; se inspeccionó markAdminOpError en SQLite/SharedPreferences. Los demás fallbacks Admin Lite no se tocaron y siguen pendientes.
- TDD: cuatro contratos de flags y un contrato del harness fallaron primero por artefactos inexistentes y después pasaron. `ventiq_app/test/admin_vendor_sync_test.dart` reprodujo 8 fallos reales antes de corregir handlers (HTTP 403/404 y respuestas inválidas contadas como éxito; 4 casos positivos ya pasaban). Tras la corrección, 16 tests HTTP/cola simulada pasan: ambas RPC con denegación, ausencia, success=false, vendedor ajeno, idempotent ausente, respuesta null, éxito y replay. Verifican una sola petición RPC, cero UPDATE alternativo, payload/UUID intactos y marcado sync/error esperado; no ejecutan SQLite real ni PostgreSQL.
- Verificación final: admin 101 tests pasan (65 M01/asignación + 36 baseline); vendedor 97 tests pasan (16 nuevos + 81 baseline/fixtures), ambos exit 0. Admin: los mismos 15 archivos del lote previo; vendedor: admin_vendor_sync, product_currency_v1_fixtures y los 12 baseline de MC-002. Dart analyze del test R0h: sin incidencias, exit 0. Análisis de admin_inventory_service + admin_vendor_sync: sin errores/warnings, 33 infos avoid_print en líneas preexistentes, exit 0; no se suprimieron ni limpiaron avisos ajenos. Formato de tests aplicado; git diff --check exit 0 con avisos CRLF previos.
- MC-005 sigue EN CURSO. El siguiente paso que proponía más entradas Admin Lite queda sustituido por el ajuste de alcance del 2026-11-14. Sin ejecución SQL remota, activación, cambios en main ni arranque de APIs. No se ejecutó build global ni prueba de dispositivo/impresora.

### R0i — venta offline del vendedor y evidencia compartida (2026-11-14)

El ajuste de alcance deja los cortes R0h como antecedentes. La evidencia `m01_solicitud` / `m01_id_tienda` pasa a `m01_r0i_idempotencia_evidencia_propuesta.sql`, para que la clave global no dependa de aplicar la asignación de Admin Lite. `m01_r0h_vendor_assign_offline_propuesta.sql` ya no hace `ADD COLUMN`; exige esas columnas. Flags y el harness no entran en el orden de liberación del TPV.

Inspección de solo lectura en newa: `fn_registrar_venta_offline_v4` es DEFINER postgres, `prosrc` MD5 `a92ee3ea41abebb360e54f7b8f34ba29`, definición MD5 `ef1dc813ab9c825d32a19a22b7ff7736`. Comprueba acceso amplio a la tienda, busca el UUID sin tipo/actor/huella y, si ya existe, vuelve a llamar `fn_registrar_pago_venta_v2`. El INSERT usa `ON CONFLICT DO NOTHING`. `p_uuid` viaja como vendedor sin compararse con `auth.uid()`.

`m01_r0i_venta_offline_v4_propuesta.sql` conserva la firma. El actor sale de `auth.uid()`. El primer envío exige una sola fila coherente de vendedor, trabajador no eliminado y TPV de la misma tienda; otro usuario solo delega si `fn_config_tienda_puede_escribir` acepta esa tienda. El replay exige tipo `venta_v4`, el mismo actor, la solicitud exacta y la tienda registrada, y devuelve el `id_operacion` original sin vender ni cobrar otra vez. Una clave anterior sin evidencia se rechaza. No usa `ON CONFLICT`. Revoca EXECUTE de cliente en `fn_registrar_venta_offline_v3` y en las dos sobrecargas de `fn_registrar_venta_offline`. No revoca `fn_registrar_venta_v3`, que sigue siendo la venta online. Preflight con `app.m01_r0i_venta_approved`, hash de cuerpo, columnas ya creadas y RLS de idempotencia sin escritura de `authenticated`. NO EJECUTAR.

Cliente, en las dos llamadas a `_registerSaleInSupabase` (lote y reintento): una denegación 42501 ya no se trata como función ausente aunque el mensaje diga "schema cache"; no se llama `fn_registrar_venta`; una respuesta sin `id_operacion` no marca la orden sincronizada; un replay cuyo desglose no coincide conserva la cola y no llama una RPC de pagos. El primer envío sí puede reparar el desglose cuando la respuesta no es idempotente, porque v3 todavía puede existir en entornos donde v4 no esté. `fn_registrar_pago_venta_offline` sigue sin este corte.

Verificación local: el contrato de sync falló primero en denegación, ausencia total e id inválido. Después, `flutter.bat test --no-pub test/offline_sale_sync_contract_test.dart` pasó 8/8: la denegación queda en una sola llamada, la ausencia total no llama `fn_registrar_venta`, el id ausente no marca sincronizada y el replay con desglose distinto conserva la cola sin RPC de pagos. Admin: `m01_r0i_sql_contract_test.dart` y `m01_r0h_sql_contract_test.dart`, 14/14. Esos contratos inspeccionan texto y no ejecutan PL/pgSQL. El helper de RPC ausente es compartido por turnos y egresos: una denegación ya no abre su cadena anterior; una función realmente ausente (PGRST202) sigue pudiendo usar el respaldo de esos módulos. Sin aplicación remota, sin activar el flag y sin cambios en main.

### R0i — cobro offline del vendedor (2026-11-14)

`fn_registrar_pago_venta_offline` en newa es DEFINER postgres, sin `search_path`, `prosrc` MD5 `85f5e34cf046eb9b042073c6a917e4e6`. Busca el UUID sin tipo, actor ni solicitud, devuelve éxito si la clave existe y registra con `fn_registrar_pago_venta` usando `p_uuid_usuario` como si autenticara. El INSERT usa `ON CONFLICT DO NOTHING`.

`m01_r0i_pago_offline_propuesta.sql` conserva la firma. Exige `auth.uid()`, operación/TPV/tienda coherentes y que quien cobra sea el vendedor de esa venta o un administrador que declara al vendedor original. El replay de tipo `pago` devuelve el resultado sin volver a cobrar. No crea columnas: usa la evidencia del script 13. NO EJECUTAR. Queda como script 15.

Cliente: el sync offline y el cobro online de `OrderService` ya no llaman `fn_registrar_pago_venta` cuando faltan las RPC con clave. Una denegación del cobro online tampoco abre esa cadena. `settings_screen` conserva dos copias antiguas que todavía caen a esa función y tragan el error; no son el sync vigente y no se tocaron en este corte. `fn_registrar_pago_venta` sigue concedida porque otras rutas la invocan. El contrato `cobro sin RPC idempotente no usa fn_registrar_pago_venta` pasa: intenta v3, conserva la cola y no llama la función sin clave. El contrato SQL del cobro también pasa; no ejecuta PL/pgSQL.

### R0i — cambio de estado offline (2026-11-14)

`fn_registrar_cambio_estado_offline` en newa es DEFINER postgres, sin `search_path`, `prosrc` MD5 `565daac1a8fdbecbd2faffa8efcacfce`. Acepta la clave sin tipo, actor ni solicitud, y registra con `ON CONFLICT DO NOTHING`. El sync llamaba a `fn_registrar_cambio_estado_operacion` ante cualquier error de esa RPC.

`m01_r0i_estado_offline_propuesta.sql` conserva la firma. El actor es `auth.uid()`; el cambio lo hace el vendedor de la venta o un administrador que declara a ese vendedor. El replay de tipo `estado:<n>` no repite el cambio. No revoca la función online. Es el script 16 y no se ejecuta.

El sync vigente lanza error y conserva `client_uuid_estado_<n>`. Los dos cobros de `settings_screen` ya no llaman `fn_registrar_pago_venta` y propagan el fallo.

Las copias muertas de `settings_screen` que llamaban `fn_registrar_venta`, `fn_registrar_pago_venta` y `fn_registrar_cambio_estado_operacion` se eliminaron. Las órdenes de esos diálogos salen por `AutoSyncService.syncSinglePendingOrder`. La cola `order_status_change` sale por `syncPendingOrderStatusChanges`, que usa `fn_registrar_cambio_estado_offline` y conserva `client_uuid_estado_<n>` en la operación si el RPC no está. El cambio de estado con la orden ya online en `OrderService.updateOrderStatusInSupabase` sale por `fn_registrar_cambio_estado_offline`. El borrador de venta también revoca `fn_registrar_venta_offline_v2`. Ajustes ya no abre ni cierra el turno por las funciones sin clave: ese paso lo deja en `uploadTurno`. Si `fn_cerrar_turno_offline` rechaza o deniega, el sync no llama `fn_cerrar_turno_tpv`. El respaldo sin clave queda solo cuando esa RPC no existe. El egreso online sale por `fn_registrar_egreso_offline_v2` con `client_uuid`; si la red falla, la cola conserva esa misma clave. La alta sin clave solo corre si esas RPC no existen. Una denegación que menciona «schema cache» ya no abre la variante anterior en turnos ni en el pedido de mesa. El cambio de estado de un plato en el KDS sale por `fn_cambiar_estado_comanda_item_offline` con `client_uuid`; si se corta la red, la cola de cocina conserva esa clave. La función sin clave solo corre si esa RPC no existe. El pedido de mesa sigue en `fn_pedir_item_cuenta_v2`: la RPC con clave delega en la versión anterior y perdería la cantidad en unidad base. Si v2 no existe, el respaldo es esa RPC con clave y no `fn_pedir_item_cuenta`. El cierre online sale por `fn_cerrar_turno_offline_monedas` con `client_uuid`; si se corta la red, la cola de cierre conserva esa clave. `fn_cerrar_turno_tpv_monedas` y `fn_cerrar_turno_tpv` solo corren si la RPC con clave no existe. Si esa RPC dice que cerró y la fila sigue abierta, el sync no hace `UPDATE` directo de `app_dat_caja_turno`: deja el turno en cola. La apertura online sale por `fn_apertura_turno_offline_monedas` con `client_uuid`; si se corta la red, la cola conserva esa clave. `registrar_apertura_turno_monedas` solo corre si la RPC con clave no existe. El estado de una orden ya online sale por `fn_registrar_cambio_estado_offline` y reutiliza la clave de esa operación y estado; la función sin clave solo corre si esa RPC no existe. El ticket completo del KDS aplica cada plato con `fn_cambiar_estado_comanda_item_offline` y salta el que ya no puede cambiar. `fn_cambiar_estado_comanda` solo corre si el ticket llega sin platos. Admin Lite sigue sin clave. El borrador `m01_r0i_caja_cocina_propuesta.sql` es el script 17: exige huella en apertura, cierre, egreso, pedido y estado de plato, incluye el mapa de monedas en esa huella, y el pedido delega en `fn_pedir_item_cuenta_v2`. No está aplicado. Hasta entonces el pedido online sigue llamando v2 primero. El ticket del KDS ya no llama `fn_cambiar_estado_comanda`. El cierre offline manda `fecha_cierre` en la RPC con clave y no la escribe con UPDATE. Un turno duplicado se cierra con `fn_m01_cerrar_turno_residual`, que no existe hasta el script 17: mientras tanto queda abierto. La venta online ya no cae a `fn_registrar_venta` si falta `_v3`. Cambiar, quitar o agregar un producto de una orden pendiente ya no cae a la función sin conversión a base. Pedir o cancelar un plato tampoco: si falta `_v2`, no se llama la función anterior. El descuento y el traslado de un pago prueban `fn_m01_aplicar_descuento_manual` y `fn_m01_mover_pago_venta` antes de escribir la tabla; esas funciones son el script 18 y no están aplicadas. El estado de un plato ya no usa la función sin clave si falta la que tiene clave. El verificador de lectura es `verificar_m01_r0i.sql`. El script 19 cubre el cierre solicitado, la limpieza del marcador, la cuenta por cobrar, la foto y el cliente de la venta. El script 20 recibe una orden anterior al turno, anota los trabajadores y registra el cambio de precio. La cola offline de trabajadores y la campana usan esas funciones. El script 21 escribe la configuración de tienda y solo deja pasar a quien puede escribir la tienda. El 22 limita el UPDATE de `app_dat_tienda` al perfil. El 23 cubre quitar la foto, el SMS y las notificaciones propias. Marcar como leída ya usa `fn_marcar_notificacion_leida`. El 24 desvincula el trabajador sin borrar la cuenta ni los roles. No está aplicado: si la función no existe, el cliente conserva la escritura actual y una denegación no la abre.

### Cierre MC-005 — orden del usuario (2026-11-14)

MC-005 queda cerrada por orden expresa del usuario. El cierre no abre MC-006, no crea `permitir_moneda_por_producto`, no activa tiendas y no toca main.

En newa el usuario ejecutó los scripts 1–24 desde el SQL Editor. Después corrió `docs/plan-multimoneda/m01_r0i_rol_harness.sql` y no saltó ningún error. El aviso previsto es que pasaron el vendedor de otra tienda, la escalación y el replay secuencial, y que la transacción se revierte. Una falla habría terminado en `P0001`.

Queda sin demostrar, y el cierre no lo convierte en probado: la carrera de dos pestañas del SQL Editor, el rechazo de `anon` y un superadmin inactivo. En newa no hay superadmin inactivo, así que ese caso se sacó del harness. `fn_admin_caja_*` sigue fuera de este corte. Las escrituras directas que quedan en el cliente solo corren cuando la función nueva no existe; una denegación no las abre.

### MC-006 — revisión de política preparada, no aplicada (2026-11-14)

`docs/plan-multimoneda/m01_r06_politica_revision_propuesta.sql` es el script 25. Añade `permitir_moneda_por_producto` en false, con un CHECK que impide encenderlo, y la tabla `app_dat_politica_moneda_revision`. Un cambio de flag, forzado o monedas de la tienda inserta una revisión nueva con el snapshot leído en esa transacción. Si el snapshot no cambió, devuelve la revisión existente y no la actualiza. El cliente autenticado solo puede leer la de su tienda. INSERT directo, UPDATE y DELETE de la revisión se rechazan. `fn_m01_publicar_revision_politica` la emite con `auth.uid()` y `fn_config_tienda_puede_escribir`; no acepta un snapshot del cliente. La configuración que ya escribe el TPV no incluye este flag. No crea la entrega al dispositivo: eso es MC-007. El usuario lo aplicó en newa. El contrato estático es `ventiq_admin_app/test/m01_r06_sql_contract_test.dart`.

### MC-007 — entrega de política preparada, no aplicada (2026-11-14)

`docs/plan-multimoneda/m01_r07_constancia_politica_propuesta.sql` es el script 26. `fn_m01_emitir_constancia_politica` entrega al `auth.uid()` y al dispositivo la última revisión publicada. La huella sale de esa fila, no de un JSON del cliente. Copia los días y el permiso offline ya configurados, y la fecha de la suscripción activa, sin modificarlos. Si no hay revisión, no inventa una. `fn_m01_validar_constancia_politica` rechaza una entrega de otro usuario, de otra tienda, de otro dispositivo o con otra huella. `usable_offline` mira la licencia viva, no la copia guardada, así que una entrega vieja no alarga la ventana. No guarda hora de creación offline ni precios. El cliente autenticado solo lee las suyas. No está aplicada. El contrato estático es `ventiq_admin_app/test/m01_r07_sql_contract_test.dart`.

### Preorden como origen del alta v1 — corte preparado (2026-11-16)

Hallazgo de campo: una venta online desde la pantalla de preorden con política activa se retenía en silencio antes de llamar a la RPC. Causa: `EnvioV1.decidir` solo admitía origen `mostrador` y `fn_m01_registrar_venta_v1` (script 35, ya aplicado) rechaza cualquier `origen != 'mostrador'`. Ambos cortes eran deliberados: la preorden todavía no era consumidor v1.

Decisión del usuario: implementar preorden v1. La preorden del TPV es un borrador local del mismo mostrador y comparte su contrato; la mesa sigue fuera (exige cuenta válida).

- Cliente (`venta_v1_envio.dart`): `decidir` admite `mostrador` y `preorden`; `mesa` y orígenes desconocidos siguen retenidos. Cubre online (`_rutaProductoV1`) y replay offline (`_registerSaleInSupabase` del sync), que usan la misma decisión. El payload ya viajaba con `origen.tipo` y la huella `m01_solicitud` conserva el origen declarado; no hay columna nueva.
- Servidor: `docs/plan-multimoneda/m01_r26_preorden_v1_propuesta.sql`, script 49, NO EJECUTAR. `CREATE OR REPLACE` del cuerpo aplicado por (35) con el chequeo `NOT IN ('mostrador','preorden')`. Preflight exige `app.m01_r26_preorden_approved`, usuario postgres y el `prosrc` intacto (guarda textual, no hash remoto). Sin cambio de firma, grants ni columnas.
- Bug relacionado corregido el mismo día en `order_service.dart`: una orden versionada sin `clientUuid` persistía una preorden ilegible para su propio contrato y vaciaba el carrito al abrir la pantalla (`CONTRACT_VERSION_UNSUPPORTED`). Ahora la orden versionada recibe `clientUuid` y `loadPersistentPreorder` descarta preórdenes con contrato incompatible.
- Tests: `venta_v1_envio_test.dart` actualizado (preorden → productoV1, mesa/desconocido → retener); `preorder_v1_persistence_test.dart` nuevo (2 casos); contrato estático del script 49 en `m01_r13_r16_sql_contract_test.dart`. Los estáticos no ejecutan PL/pgSQL.
- Defecto encontrado en la primera prueba real (2026-11-16): `app_dat_operaciones.uuid` tiene FK a `users` y el cuerpo del script 35 insertaba `v_uuid` (la clave de idempotencia), violando la FK en el alta real (`23503`). El script 49 corregido inserta `v_actor` y su preflight acepta tanto el cuerpo del 35 como una corrida previa del propio 49, así es re-ejecutable. **El mismo defecto existe en `m01_r20_mesa_cierre_v1_propuesta.sql` (script 42, aplicado)**: su INSERT de `app_dat_operaciones` también usa `v_uuid`; necesita una enmienda propia antes de probar el cierre de mesa v1 — no probado aún.
- Segundo defecto encontrado en la prueba real: `fn_m01_registrar_pagos_v1` (script 36) localizaba la venta por `operaciones.uuid = client_uuid_venta`, dependencia del mismo defecto de FK. Con el alta corregida (actor en `uuid`), el cobro caía con 42501 tras registrar la venta. El script 50 (`m01_r27_pagos_v1_operacion_lookup_propuesta.sql`) resuelve la venta por `app_dat_operacion_offline_idempotencia` (`tipo='venta_v1'`), que es el vínculo correcto. Verificado en newa: la venta sí quedó registrada (op 108, idempotencia `venta_v1`); el reintento del cobro quedó retenido con su UUID.
- Tercer defecto encontrado: cancelar/devolver la venta v1 fallaba con 23502 — `fn_registrar_cambio_estado_operacion` copia `extraccion.id_presentacion` (NULL = base en v1) al ledger `app_dat_inventario_productos` cuya columna es NOT NULL y guarda la fila `es_base` (p. ej. 19). El script 51 (`m01_r28_estado_devolucion_presentacion_propuesta.sql`) resuelve NULL → fila `es_base` del producto en el match de saldo y en el INSERT; también resuelve la base del ingrediente cuando un elaborado no tiene inventario previo.
- Cuarto defecto (reimpresión): `fn_listar_ordenes` no emitía el contrato v1 — la orden recargada perdía `seleccion`/`versionMonetaria` y el ticket caía al camino legacy con `precio_unitario` NULL→0 en líneas USD (total y desglose sí eran correctos). Script 52 (`m01_r29_listar_ordenes_v1_propuesta.sql`) añade a `detalles.items` las columnas v1 de la extracción y a `detalles` la versión + `client_uuid` de la huella; `_transformSupabaseToOrders` reconstruye `ProductCurrencySeleccion` por línea y marca la orden v1 solo si todas reconstruyen (sin tocar precios vigentes). Estado verificado en newa el 2026-11-16: script 50, 51 y 52 aplicados. `fn_registrar_cambio_estado_operacion` resuelve `id_presentacion` NULL con la fila `es_base`. `fn_listar_ordenes` emite `id_linea_cliente`, neto nativo, `version_monetaria` y `client_uuid`. `listar_ordenes` es otra función (no delega) y sigue sin esas columnas; la usan el admin, el sync y ajustes.
- Pendiente de prueba en la app, no de SQL: reintentar la venta retenida (cobro reanuda, idempotencia devuelve la op 108), la cancelación de la op 108 y la reimpresión del ticket por `fn_listar_ordenes` (líneas deben mostrar neto nativo por moneda). Después, prueba completa online + respuesta perdida. El flag de tienda sigue siendo decisión del usuario; nada de esto lo enciende.

## Inventario de apoyo al plan

### Puntos de integración localizados

| Área | Archivos existentes inspeccionados o localizados | Observación |
|---|---|---|
| Configuración admin | `ventiq_admin_app/lib/services/store_config_service.dart`, `lib/widgets/monedas_tienda_card.dart` | Reutilizar el flujo de configuración por tienda; verificar permisos en spec. |
| Configuración TPV | `ventiq_app/lib/services/store_config_service.dart`, `auto_sync_service.dart`, `device_offline_prep_service.dart` | Configuración remota por `select('*')`, caché `store_config` y sync existente; un flag nuevo también necesita acceso local consistente. |
| Modelo de línea | `ventiq_app/lib/models/order.dart` | `OrderItem` ya conserva `paymentMethod`; precio final y subtotal dependen también de promociones/medio. No basta añadir una etiqueta de moneda. |
| Selección y edición | `ventiq_app/lib/screens/preorder_screen_styled.dart`, `preorder_screen.dart`, `orders_screen.dart`, `payment_method_picker_screen.dart` | Rutas localizadas por uso de `PaymentMethod`; trazar navegación real y fusión de líneas antes de especificar cambios exactos. |
| Checkout | `ventiq_app/lib/screens/checkout_screen.dart`, `widgets/checkout_payment_lines_editor.dart` | Editor «Distribuir pagos» y validación actual contra total CUP; se necesita rama explícita que preserve el flujo legacy. |
| Persistencia online | `ventiq_app/lib/services/order_service.dart` | Llamadas a venta v3/mesa v3 y pago v3; revisar todos los payloads y fallbacks. |
| Persistencia offline | `ventiq_app/lib/services/auto_sync_service.dart`, `models/order.dart` | Serialización, rehidratación y reintentos deben conservar snapshot de línea y modalidad. |
| Backend main | RPC de venta, agregar/editar pendientes y pagos inspeccionadas durante la entrevista | Fusión automática y total escalar requieren cambios coordinados antes de admitir importes nativos mixtos. |

Las rutas localizadas no equivalen a haber trazado todas sus ramas. La fase Specify completará el recorrido y documentará qué campos y funciones se modifican.

### Riesgos que debe resolver la primera spec afectada

- Snapshot de política para órdenes en curso y pendientes offline al cambiar el flag o moneda forzada.
- Momento/fuente de tasa histórica, comportamiento sin tasa y validación servidor de tasas enviadas offline.
- Promociones, descuentos, presentaciones y aditamentos sin convertir precios propios CUP/USD ni recalcular históricos.
- Precios cero frente a precio ausente: no tratarlos como equivalentes sin comprobar reglas del producto.
- Identidad/idempotencia de detalle y confirmación de unión conservadas en cliente y RPC.
- Compatibilidad de pagos parciales, devoluciones y CxC; preguntar al usuario si las reglas existentes no determinan un resultado inequívoco.

### Puertas de revisión siguientes

1. Aprobar este mapa de tres capacidades y su alcance inmediato.
2. Redactar y revisar la spec de `store-product-currency-policy`, con comandos, criterios, contratos y pruebas concretas.
3. Preparar/aprobar su plan y tareas antes de implementar; aprobar la coordinación de despliegue para no habilitar el flag en tiendas sin soporte de venta completo.
4. Repetir el ciclo por módulo, manteniendo el flag apagado hasta que el recorrido activo completo sea compatible y verificable.

## Borrador histórico de reportes — no ejecutar sin replanificar

El contenido siguiente conserva el análisis anterior para referencia. Su mapa, decisiones pendientes, fases y próximo paso ya no representan el alcance inmediato; deben reemplazarse por el plan revisado después de aprobar las specs. No interpretar sus supuestos sobre consolidación o su prohibición de cambiar checkout como reglas que anulen la intención confirmada anterior.

- App principal del borrador original: `ventiq_admin_app`.
- Antecedente: `../plan.md`, especialmente secciones 17 y 18. Es evidencia histórica, no prueba del estado desplegado.
- Método propuesto: spec-driven development por módulo, con especificaciones vivas, tareas verificables y aprobación entre etapas.
- Este archivo no sustituye `tasks/plan.md`, `tasks/todo.md` ni `CAPABILITY-MAP.md`, pertenecientes a Fondo de Caja y preparación offline.

## 1. Objetivo y alcance

Permitir al administrador interpretar correctamente los valores de ventas, cobros y rentabilidad en todas las superficies del admin: pantalla de Ventas, turnos, dashboards, productos, clientes, widgets nativos, finanzas, analista IA y exportaciones.

El resultado no consiste en cambiar etiquetas CUP por USD. Debe preservar la moneda original de los pagos, separar facturación de cobros, consolidar solo valores compatibles y mantener los históricos intactos.

### Dentro del alcance

- Cobros nativos por N monedas, sin listas fijas CUP/USD.
- Equivalente contable CUP y consolidación de presentación según configuración de tienda.
- Totales, detalles, gráficos, rankings, comparativos, PDF y Excel que muestran valores de ventas.
- Consistencia de filtros, permisos, fuentes y criterios temporales.
- Compatibilidad con clientes y RPC existentes mediante cambios aditivos.
- Verificación de diferencias entre entornos antes de diseñar migraciones concretas.

### Límites

- No rediseñar el checkout ni crear un catálogo offline paralelo.
- No cambiar precios del catálogo, costos, ventas o liquidaciones históricas.
- No ampliar automáticamente monedas de compras, contratos de consignación, depósitos, proveedores, Carnaval, suscripciones o paquetería: revisar sus puntos de integración solo cuando presenten ventas TPV o compartan la consolidación afectada.
- No transformar cobros en ingresos contables por conveniencia de UI.
- No arrancar APIs ni aplicar SQL remoto como parte de la documentación.

## 2. Supuestos y decisiones pendientes de aprobación

Estos supuestos orientan el borrador; no se consideran decisiones nuevas aprobadas:

1. CUP continúa como base contable.
2. Se conserva la regla existente: moneda forzada de la tienda para consolidación de presentación; CUP si no se fuerza ninguna.
3. Los importes nativos se muestran siempre con código de moneda explícito.
4. Los pagos mantienen la tasa histórica persistida; una conversión a tasa actual se presenta como equivalente de presentación, no como cobro histórico exacto.
5. El soporte ya presente se reutiliza y se prueba antes de reemplazarlo.

| ID | Decisión por validar | Recomendación |
|---|---|---|
| D01 | Consolidación obligatoria por tienda o selector del observador | Mantener configuración de tienda; no introducir selector en esta iniciativa sin aprobación. |
| D02 | Conversión de moneda base a moneda de presentación | Conservar política existente, pero exponer fecha/tasa y carácter estimado; no usarla como sustituto del valor contable histórico. |
| D03 | Cobros en reportes filtrados por producto/proveedor | No atribuir pagos completos a cada fila. Mostrar facturado o definir una asignación explícita, separada del cobro nativo. |
| D04 | Criterio temporal de cada reporte | Hacer explícito creación, completado, fecha de pago o turno. Comparar fuentes solo bajo el mismo criterio. |
| D05 | Errores o backend sin capacidad multimoneda | Mostrar capacidad no disponible; nunca simular ausencia de cobros ni inventar ceros. |
| D06 | Finanzas | Distinguir devengo/facturado y flujo de caja/cobrado según contrato de cada reporte. |

## 3. Mapa de capacidades propuesto — pendiente de aprobación

La aprobación de este mapa precede a escribir las especificaciones detalladas por módulo. Los IDs son estables y se usarán para nombrar specs, tareas y pruebas.

| Module id | Responsabilidad | Depende de |
|---|---|---|
| `money-reporting-core` | Semántica de importes, contrato monetario, filtros, disponibilidad, formato y contexto de tienda. | — |
| `sales-multicurrency` | Ventas: tiempo real, TPV, proveedores, órdenes, históricos y reporte por moneda. | `money-reporting-core` |
| `cash-reconciliation` | Turnos y arqueos independientes por moneda. | `money-reporting-core` |
| `sales-insights` | Dashboards, productos, clientes, widgets nativos y contexto monetario del analista IA. | `money-reporting-core`, `sales-multicurrency` |
| `financial-reporting` | Resultados, rentabilidad, flujo de caja y comparativos con base monetaria consistente. | `money-reporting-core` |

Orden recomendado: `money-reporting-core` → `sales-multicurrency` → `cash-reconciliation` → `sales-insights` → `financial-reporting`.

Las exportaciones y pruebas pertenecen al módulo que produce el reporte; no se dejan para una fase final independiente.

## 4. Flujo spec-driven y mantenimiento

### Etapas y puertas de revisión

1. Aprobar mapa de capacidades y resolver decisiones bloqueantes.
2. Escribir y aprobar la spec de `money-reporting-core`.
3. Detallar y aprobar su plan y tareas.
4. Implementar un corte verificable, empezando por una superficie real de Ventas.
5. Repetir Specify → Plan → Tasks → Implement para los módulos restantes, en orden de dependencia.

Ubicación propuesta de las specs: `tasks/SPEC-<module-id>.md`. No crearlas hasta validar el mapa. Este archivo será el índice de la iniciativa y el registro general de avance. Si se decide adoptar otra ubicación, registrar aquí la decisión sin duplicar contenido.

### Contenido mínimo de cada spec

- Objetivo, usuarios, alcance y exclusiones.
- Escenarios funcionales y criterios identificados, por ejemplo `SM-AC-01`.
- Contratos de datos: unidad monetaria, origen, filtros, fechas, estado y disponibilidad.
- Reglas de conversión, redondeo y tratamiento de datos legacy.
- Archivos responsables, convenciones reales y comandos ejecutables.
- Pruebas unitarias, widgets, SQL e integración/manuales necesarias.
- Límites: qué se hace siempre, qué requiere aprobación y qué está prohibido.
- Preguntas abiertas, dependencias y evidencia de aprobación.

### Regla para mantener la documentación viva

- Antes de cambiar una regla de negocio o contrato aprobado, actualizar la spec y solicitar revisión.
- En cada entrega, actualizar tareas y evidencia: comando, resultado, entorno y limitaciones.
- Separar estados: propuesto, aprobado, implementado, verificado localmente y desplegado/verificado remotamente.
- Nunca marcar una migración desplegada por existir su archivo.
- No marcar una tarea completada solo por pasar análisis estático.
- Registrar decisiones sustituidas con motivo; no añadir notas contradictorias sin resolver el texto normativo.
- Cada tarea referencia criterios de su spec y las pruebas que los verifican.
- Mantener una sola lista de avance por módulo; no duplicar checklists entre varios archivos.

## 5. Estado local observado

Inspección de código realizada durante la preparación del plan; no se consultó Supabase ni se ejecutaron pruebas.

| Pieza | Evidencia local | Acción |
|---|---|---|
| Modelo por moneda | `ventiq_admin_app/lib/models/sales.dart`: `VentasPorMoneda`, importe nativo/base/consolidado. | Reutilizar y probar contratos legacy y nuevos. |
| Consolidación por tienda | `lib/services/moneda_consolidacion_service.dart`: configuración resuelta por RPC y caché. | Revisar contexto de tienda, fallos y separación formato/conversión. |
| Ventas | `lib/screens/sales_screen.dart`: pestaña por moneda y múltiples usos de consolidación. | Auditar rutas completas, filtros y exports; no asumir que toda la pantalla está cubierta. |
| Históricos de productos | `lib/services/sales_service.dart`: consulta de pagos de eventos selecciona monto y método, sin moneda/tasa/equivalente. | Completar contrato y consumidores. |
| Turnos | `caja_turno_service.dart`, `caja_turno.dart`, `widgets/tpv_managements/caja_turnos.dart`, `caja_turno_pdf_service.dart`. | Verificar listado, detalle, fallback, arqueo y PDF. |
| Clientes | `customer_service.dart`: totales y ticket calculados con `importe_total`. | Declarar unidad, estados y semántica; no sustituir por suma nativa de pagos. |
| Widgets | `widgets_home/data/widget_data_repository.dart`: agregaciones y snapshots propios. | Incorporar moneda y revisar lectores nativos. |
| IA | `sales_analyst_service.dart`: contexto con moneda CUP fija. | Contrato por métrica y trazabilidad de fuentes. |
| Finanzas | `financial_dashboard_service.dart`: RPC y fallbacks, incluido retorno de datos simulados ante error de P&G. | No mostrar resultados simulados como información financiera real. |

### Advertencias del antecedente

Las secciones 17 y 18 de `plan.md` contienen avances parciales, correcciones y afirmaciones incompatibles sobre facturado/cobrado y filtros. Deben usarse como pistas de investigación, no como contrato aprobado.

Los documentos de reconocimiento del 2026-11-04 no representan por sí solos el código actual ni el estado remoto.

## 6. Contrato funcional común

### Tipos de magnitudes

- Facturado: importes de líneas de operación, descuentos y totales históricos según contrato de la venta.
- Cobrado nativo: líneas de pago agrupadas por su moneda original.
- Equivalente base: valor CUP persistido o validado bajo reglas explícitas para registros legacy.
- Consolidado de presentación: equivalente en la moneda configurada, indicando política de conversión.
- Costos y ganancias: magnitudes históricas compatibles entre sí; no derivadas de cobros por sustitución automática.

Los nombres técnicos definitivos se fijarán en la spec. Se debe transportar moneda, importe, fuente, disponibilidad y metadatos de conversión necesarios, sin imponer una abstracción más grande de lo que exijan los consumidores.

### Invariantes

1. No sumar importes nativos de monedas distintas.
2. No convertir nuevamente un importe que ya está en la moneda de destino.
3. No aplicar tasas actuales a los valores históricos persistidos.
4. No reemplazar el total facturado por el cobrado para hacer coincidir tarjetas.
5. No duplicar pagos al unir líneas de productos con líneas de pago.
6. No contar una venta mixta dos veces en el total de operaciones únicas. Los conteos por moneda pueden solaparse y deben indicarlo.
7. No convertir una tasa ausente, error o dato faltante en cero válido.
8. Monedas desactivadas siguen visibles en el histórico.
9. Total y filas comparten filtros, estados y criterio temporal.
10. Costos o ganancias sin permiso no se exponen en UI, exports ni contexto de IA.
11. Redondear para presentación bajo una política declarada; probar sumas y tolerancias con precisión de BD, evitando acumulación prematura de redondeos.

### Filtros

Definir un universo de operaciones por tienda y filtros de cada reporte. Si se muestra un bloque de cobros con distinto alcance, indicarlo explícitamente; preferiblemente ofrecer el mismo alcance.

Producto/proveedor requieren especial cuidado: un pago de una orden con varios productos no identifica por sí solo cuánto corresponde a cada producto. Una asignación proporcional, si se aprueba, debe definir base, descuentos, residuo de redondeo, parciales y devoluciones, y rotularse como asignación.

## 7. Plan técnico y tareas propuestas

Todas las tareas están pendientes. Son un desglose de referencia, no tareas aprobadas para implementar. Antes de ejecutar una tarea grande, dividirla en cambios de aproximadamente 1–5 archivos.

### Fase A — Diagnóstico verificable

- [ ] A1. Inventariar contratos consumidos por Ventas y caja.
  - Dependencias: ninguna.
  - Archivos: `sales_service.dart`, `models/sales.dart`, `caja_turno_service.dart`, `models/caja_turno.dart` y SQL referenciado.
  - Aceptación: matriz por RPC/campo con fuente, unidad monetaria, filtros, fecha, estados y fallbacks.
  - Verificación: trazado desde UI hasta consulta; ejemplos de payload documentados sin datos sensibles.
- [ ] A2. Verificar capacidades desplegadas por entorno con consultas de solo lectura.
  - Dependencias: A1 y acceso autorizado.
  - Revisar: `fn_reporte_ventas_por_moneda`, `fn_moneda_consolidacion`, versiones de reporte por turno, resumen de turno, listado de turnos, `listar_ordenes`, `reporte_ordenes_json`.
  - Aceptación: firmas y campos confirmados por entorno; diferencias y migraciones pendientes registradas.
  - Verificación: inspección de definiciones, permisos y muestras agregadas; ninguna escritura remota.
- [ ] A3. Verificar integridad de equivalentes, tasas y cardinalidad.
  - Dependencias: A2.
  - Aceptación: conteo de pagos incompletos o inconsistentes y casos de operaciones mixtas sin duplicación; no se repara automáticamente.
  - Verificación: consultas agregadas con fuente y alcance explícitos.

Checkpoint A: aprobar mapa y decisiones D01–D06; resolver bloqueos antes de diseñar migraciones.

### Fase B — Núcleo y primer corte vertical

- [ ] B1. Aprobar spec de `money-reporting-core`.
  - Dependencias: checkpoint A.
  - Aceptación: contratos, invariantes, política de error/redondeo y escenarios verificables aprobados.
  - Verificación: revisión humana de spec y ejemplos numéricos.
- [ ] B2. Completar modelos monetarios y pruebas de parseo.
  - Dependencias: B1.
  - Archivos probables: modelos de ventas, contrato de pagos y sus pruebas.
  - Aceptación: distingue ausente/cero; soporta numeric serializado como entero, decimal o texto; no fuerza monedas desconocidas a CUP.
  - Verificación: tests unitarios de contratos legacy/nuevos y datos incompletos.
- [ ] B3. Separar formato nativo y conversión, con contexto por tienda.
  - Dependencias: B2.
  - Archivos probables: `moneda_consolidacion_service.dart`, componentes compartidos y tests.
  - Aceptación: códigos explícitos, sin doble conversión ni resultados de una tienda mostrados en otra; fallo visible y reintentable.
  - Verificación: tests de carga concurrente, invalidación, configuración cambiada y moneda sin tasa.
- [ ] B4. Completar un corte de Tiempo Real con total facturado y cobros separados.
  - Dependencias: B3 y spec aprobada de `sales-multicurrency` para este corte.
  - Archivos probables: `sales_screen.dart`, `sales_service.dart`, bloque monetario y tests.
  - Aceptación: tarjeta facturada coincide con filas; bloque de cobros declara/respetan filtros y criterio temporal.
  - Verificación: widget tests y comparación manual con operación mixta.

Checkpoint B: ninguna regresión CUP y un flujo mixto completo verificable antes de extender el patrón.

### Fase C — Completar Ventas

- [ ] C1. TPVs, vendedores y detalle de órdenes.
  - Dependencias: B y contratos remotos confirmados.
  - Aceptación: efectivo/digital y pagos por moneda; pendientes/CxC separados; total de operaciones únicas correcto.
  - Verificación: tests de agregación y detalle con varios pagos por operación.
- [ ] C2. Proveedores y productos.
  - Dependencias: B y D03 resuelta.
  - Aceptación: conserva facturado/costo/ganancia históricos; ninguna atribución implícita o duplicación de pagos.
  - Verificación: orden con dos proveedores y cobro mixto, descuentos y parciales.
- [ ] C3. Históricos y desglose.
  - Dependencias: B.
  - Aceptación: cada pago expone moneda, nativo y equivalente; histórico del producto incluye los campos que hoy omite la consulta.
  - Verificación: contrato RPC/PostgREST y widget de detalle; monedas desactivadas visibles.
- [ ] C4. Exportaciones de Ventas por corte.
  - Dependencias: C1–C3 según reporte.
  - Aceptación: PDF/Excel reutilizan resultado y filtros; columnas nativas y consolidadas separadas; faltantes explícitos.
  - Verificación: pruebas del dataset exportado y revisión manual de PDF/Excel.

Checkpoint C: todas las pestañas de Ventas y sus exports concuerdan bajo el mismo alcance.

### Fase D — Caja por moneda

- [ ] D1. Aprobar spec de `cash-reconciliation` y verificar listado/detalle.
  - Dependencias: B y A.
  - Aceptación: fuente definida para apertura, efectivo esperado, contado, diferencia y egresos por moneda.
  - Verificación: comparación con resumen real del turno; ausencia de capacidad no se interpreta como cero.
- [ ] D2. Completar conciliación y presentación.
  - Dependencias: D1.
  - Archivos probables: `caja_turno.dart`, `caja_turno_service.dart`, `caja_turnos.dart` y tests.
  - Aceptación: cada moneda concilia independientemente; medios digitales no se mezclan con efectivo físico; diferencias tienen unidad explícita.
  - Verificación: apertura CUP/USD, egreso USD, varios cobros y diferencia en una sola moneda.
- [ ] D3. PDF de turno.
  - Dependencias: D2.
  - Archivos probables: `caja_turno_pdf_service.dart` y tests.
  - Aceptación: PDF reproduce desglose y estado de disponibilidad del detalle.
  - Verificación: comparación del dataset y revisión visual del documento.

Checkpoint D: no se usa una diferencia consolidada para ocultar faltante de una moneda con sobrante de otra.

### Fase E — Dashboards y demás consumidores

Primero aprobar la spec de `sales-insights`; implementar y verificar cada tarea por separado.

- [ ] E1. Dashboard móvil y web.
  - Dependencias: B y spec aprobada.
  - Archivos: `dashboard_service.dart`, `dashboard_screen.dart`, `dashboard_web_screen.dart` y tests.
  - Aceptación: ventas/ticket/tendencias indican moneda y fuente; comparativos no mezclan políticas de conversión.
  - Verificación: períodos con tasas distintas, estados y filtros equivalentes.
- [ ] E2. Dashboard de inventario, detalle de producto y gráficos.
  - Dependencias: B y C2.
  - Archivos candidatos: `inventory_dashboard.dart`, `products_analytics_service.dart`, `product_sales_dialog.dart`, `products_charts_widget.dart`; localizar consumidores adicionales antes del cambio.
  - Aceptación: ingresos y rentabilidad históricos diferenciados de precio vigente y moneda de cobro.
  - Verificación: producto con cambio de precio y costo entre ventas; no recalcular históricos con vistas de precio vigente.
- [ ] E3. Clientes.
  - Dependencias: B.
  - Archivos: `customer_service.dart`, modelos/pantallas consumidoras y tests.
  - Aceptación: total comprado y ticket mantienen semántica de compras; cobros por moneda aparecen separados si se incluyen.
  - Verificación: varias órdenes, pago parcial, cancelación y cliente sin compras.
- [ ] E4. Widgets nativos.
  - Dependencias: E1 y C1.
  - Archivos: `widgets_home/data/widget_data_repository.dart`, claves/snapshots, lectores nativos localizados y tests.
  - Aceptación: cada snapshot lleva contexto monetario de su tienda; no depende de una moneda global mutable; no rompe lectores existentes.
  - Verificación: dos widgets de tiendas con monedas distintas y refrescos concurrentes; prueba en dispositivo.
- [ ] E5. Analista IA.
  - Dependencias: C y E1.
  - Archivos: `sales_analyst_service.dart`, modelos/controlador y tests.
  - Aceptación: contexto por magnitud, filtros y fuente; sin CUP global incorrecto; ganancias restringidas también en payloads.
  - Verificación: inspección de JSON y tests deterministas de contexto, sin depender de la respuesta generada del modelo para probar aritmética.

Checkpoint E: cada consumidor identificado está migrado o tiene exclusión justificada y aprobada; ningún importe de ventas queda monetariamente ambiguo.

### Fase F — Finanzas

- [ ] F1. Aprobar spec de `financial-reporting` y auditar RPC.
  - Dependencias: B, A y D06 resuelta.
  - Archivos: `financial_dashboard_service.dart`, `financial_reports_service.dart`, `financial_service.dart` y SQL correspondiente.
  - Aceptación: cada reporte declara devengo/caja, unidades y fuentes de ingreso/costo/gasto; no sustituye ingresos por pagos indiscriminadamente.
  - Verificación: contraste con definiciones desplegadas y un caso con CxC.
- [ ] F2. Resultados y métricas de rentabilidad.
  - Dependencias: F1.
  - Aceptación: ingreso/costo/gasto comparables; importes históricos conservados; error no muestra datos simulados como reales.
  - Verificación: fixtures de rentabilidad, error RPC y tasa ausente; separar tareas si excede cinco archivos.
- [ ] F3. Flujo de caja, tendencias y comparativos.
  - Dependencias: F1.
  - Aceptación: cobros/egresos por moneda y equivalente bajo política declarada; distinción entre cambio operativo y efecto de conversión.
  - Verificación: pagos parciales en fechas distintas y tasas históricas diferentes.
- [ ] F4. Presentación y exports financieros.
  - Dependencias: F2/F3.
  - Aceptación: pantallas y documentos coinciden y muestran moneda/política temporal.
  - Verificación: tests de datasets y revisión manual de documentos.

Checkpoint F: resultados y flujo de caja no se hacen coincidir artificialmente; diferencias explicables por sus contratos.

## 8. Matriz mínima de pruebas

| Caso | Resultado requerido |
|---|---|
| Solo CUP | Mismos valores históricos; identificación clara de moneda. |
| Solo USD | Nativo exacto; no reconversión innecesaria. |
| CUP + USD en una orden | Dos desgloses, una operación única, sin suma nativa cruzada. |
| Tercera moneda | Sin ramas binarias ni degradación a CUP. |
| Misma moneda, tasas históricas distintas | Equivalentes históricos respetados; conversión actual identificada. |
| Moneda desactivada | Visible en reportes históricos. |
| Tienda forzada/no forzada | Regla aprobada aplicada, sin alterar valores fuente. |
| Tasa ausente o inválida | Dato no disponible, no cero inventado. |
| RPC ausente, permiso denegado o red caída | Estados diferenciados; sin fallback engañoso. |
| Pago parcial y CxC | Facturado y cobrado separados. |
| Cancelación/devolución | Inclusión, signo y fecha según contrato aprobado. |
| Dos productos/proveedores y varios pagos | Sin multiplicación de importes por joins. |
| Filtros de almacén, TPV, vendedor y fechas | Totales y detalle comparten universo. |
| Cambio de tienda/cargas concurrentes | No se muestra moneda o datos de la tienda anterior. |
| Conteo por moneda | Se explica solapamiento; total único no suma conteos de ventas mixtas. |
| Permiso sin ganancias | Costos/ganancias ausentes en UI, export e IA. |
| PDF/Excel | Mismos datos, filtros, monedas y totales que la pantalla. |
| Redondeo | Política documentada; residuo controlado sin perder ni duplicar dinero. |

## 9. Verificación y comandos

Desde `ventiq_admin_app`, en PowerShell sobre Windows:

```powershell
flutter.bat test --no-pub test/precio_venta_contract_test.dart test/precio_venta_sql_contract_test.dart test/app_compile_test.dart test/sales_totals_summary_test.dart
flutter.bat analyze
```

El primer comando corresponde a verificaciones focalizadas documentadas en `AGENTS.md`; cubre regresiones relacionadas, no todo el alcance multimoneda. Añadir comandos exactos de los nuevos tests a la spec de cada módulo cuando existan, sin afirmar que hoy existen ni que ya pasan.

Antes de cada entrega:

1. Ejecutar tests nuevos y regresiones afectadas.
2. Analizar archivos tocados y evaluar el análisis global sin ocultar fallos previos.
3. Validar SQL en PostgreSQL de prueba; inspeccionar texto SQL no prueba su ejecución.
4. Verificar con rol autorizado y con rol sin acceso a otra tienda.
5. Comparar pantalla, detalle y exportación con los mismos filtros.
6. Registrar evidencia y límites: pruebas locales no sustituyen datos remotos ni uso real.

No se ejecutó ninguno de estos comandos al redactar este documento. No se inicia ninguna API para verificarlos.

## 10. Migraciones, seguridad y despliegue

- Inspeccionar esquema, firmas y políticas reales antes de preparar cambios.
- Preferir extensiones aditivas; no romper clientes ya desplegados.
- SQL en archivos versionados; mantener los artefactos de esta iniciativa localizables desde este índice.
- Si se crea una tabla, RLS y policies explícitas inmediatamente después del CREATE TABLE, con acceso por tienda y rol según las reglas del proyecto.
- RPC SECURITY DEFINER debe comprobar acceso y no sustituye RLS en tablas nuevas.
- No aplicar backfills, correcciones históricas ni operaciones destructivas sin una propuesta específica y aprobación.
- Desplegar SQL compatible antes del cliente; verificar capacidad por entorno.
- No usar un fallback legacy cuya unidad monetaria sea desconocida como total válido.
- Reversión preferida: volver al cliente previo y conservar cambios aditivos compatibles; no borrar datos ni columnas.
- No añadir dependencias salvo necesidad demostrada y aprobación correspondiente.

## 11. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Confundir facturado y cobrado | Contratos separados y pruebas con CxC. |
| Usar tasa actual como histórica | Metadatos, etiquetas y conservación de equivalentes persistidos. |
| Duplicar pagos por unión con productos | Preagregación y pruebas de cardinalidad. |
| Bloque monetario fuera del filtro visible | Universo compartido o aviso explícito de alcance distinto. |
| RPC diferentes entre entornos | Diagnóstico por entorno antes de migraciones. |
| Datos faltantes interpretados como cero | Disponibilidad explícita y pruebas de fallos. |
| Contexto global mutable de moneda | Contexto por reporte/tienda, probado con concurrencia y widgets. |
| Exports con aritmética independiente | Reutilizar dataset y probar igualdad. |
| Plan desactualizado | Actualización de spec y evidencia en cada entrega; una sola lista por módulo. |

## 12. Definición de terminado

- Cada superficie identificada tiene cobertura o exclusión aprobada.
- Monedas originales conservadas y ninguna suma nativa cruzada.
- Facturado, cobrado y consolidado claramente diferenciados.
- Totales y detalles cuadran bajo el mismo alcance y precisión acordados.
- Conversiones estimadas identificadas; históricos intactos.
- Exportaciones coherentes y permisos aplicados a todos los canales.
- Tests relevantes pasan; SQL ejecutado en entorno de prueba y verificación remota registrada por separado.
- Specs reflejan reglas vigentes; tareas cerradas con evidencia, no solo con una marca.

## 13. Registro de decisiones y avance

| Fecha | Evento | Estado |
|---|---|---|
| 2026-11-13 | Plan de referencia y mapa propuesto redactados a partir de inspección local. | Borrador, pendiente de revisión. |
| — | Preorden v1: totales por moneda en `preorder_screen*.dart` (header, ítem, footer, arqueo CUP-equivalente y desglose offline por método+moneda, con `TicketV1.totalesNativos`/`equivalenteCupItem`). Cache offline: el sync guarda `precios_vigentes` (filas de `app_v_precio_venta_vigente` por categoría) dentro de `detalles_completos` y el detalle offline aplica el mismo merge que `_unirPreciosVigentes` → precio CUP/USD disponible sin red. | Implementado en cliente; pendiente verificación en dispositivo (online, offline cache fresco y stale). |
| — | MC-056. Retirado el toggle legacy "Selector de moneda en ventas" (`mostrar_selector_moneda`): redundante con "monedas aceptadas". Quedan monedas aceptadas + forzar + moneda por producto, con exclusión mutua forzada↔per-product: servidor (script 53: `fn_m01_fijar_moneda_por_producto` apaga la forzada al activar; `fn_validar_moneda_forzada` rechaza la combinación), admin (`MonedasTiendaCard` no pinta el bloque forzado con per-product ON) y TPV (`_haySelectorMoneda` ya no consulta el flag legacy). La columna `mostrar_selector_moneda` se conserva para builds viejos. Detalle de orden v1: líneas usan neto nativo (`precio_unitario_neto_nativo`/selección) en vez del `precio_unitario` NULL legacy → totales por moneda, "≈ equiv." con la tasa del snapshot y Resumen por moneda. Al sincronizar se escribe el desglose registrado en la copia local de la cola (antes mostraba el snapshot stale). | Script 53 en borrador; resto implementado. |

Próximo paso: revisar el mapa de capacidades y D01–D06. Después redactar y aprobar la spec de `money-reporting-core`; no comenzar implementación antes de esa aprobación.
