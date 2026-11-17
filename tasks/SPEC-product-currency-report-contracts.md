# Spec: Contratos de reportes para venta por producto

- Module id: `product-currency-report-contracts`.
- Estado: APROBADA en REP por el usuario tras presentar MC-004. Desbloquea preparar/revisar las tareas MC-045/M06, no implementar reportes automáticamente ni ejecutar SQL de escritura.
- Depende de: `SPEC-product-currency-sale.md` (contrato aprobado y sección 15/MC-003), `SPEC-store-product-currency-policy.md` y plan MC vigente.
- Entorno de referencia: newa. Main no se consultó ni modificó para este documento.
- Alcance: contratos/adaptadores de consumidores existentes, sin nuevos desgloses visuales generales. MC-045 detallará las tareas M06 después de REP; MC-046 cubre ticket/caja/resumen operativo coordinadamente.

## 1. Objetivo y límites

Una venta producto-v1 puede mezclar líneas CUP/USD y medios. Los lectores deben conservar la realidad comercial de cada línea, el dinero realmente cobrado, la deuda nativa y los equivalentes CUP históricos, sin sumarlos como si fueran ingresos independientes.

Esta spec no cambia precios, promociones, descuento unitario, redondeo, condiciones de cobro ni costos históricos. No habilita más monedas, conversiones de deuda, atribución retroactiva, nuevas pantallas, exportaciones nuevas ni contabilidad fiscal completa. Adaptar exportaciones existentes y sus unidades sí está incluido. No rehabilitar módulos hoy deshabilitados como parte incidental de la feature.

Las reglas de venta ya aprobadas no vuelven a votarse aquí. Las propuestas de lectura/presentación/corte de este documento requieren REP antes de convertirse en tareas de implementación.

## 2. Evidencia contrastada

### 2.1 Código local

| Consumidor | Evidencia/riesgo observado | Obligación del adaptador |
|---|---|---|
| `services/sales_service.dart`, `getProductSalesReport` | Usa proveedor5 / por_turno_v2; el dinero fiable está en totales SQL, no en unitario representativo por cantidad. Hay fallback de turnos ante cualquier excepción. | Conservar grano/presentaciones y distinguir rama histórica de análisis con precios actuales; no degradar v1 a RPC antigua ante permisos/error de red. |
| `models/sales.dart`, `screens/sales_screen.dart` | `VentasPorMoneda` separa nativo/base/consolidado; varios parseos tolerantes devuelven cero. Pantalla/exportaciones suman consolidado, no nativos. | Preservar contrato legacy. V1 debe declarar magnitud/moneda, validar números exactos y no presentar ausencias como cero. |
| `services/customer_service.dart` | Métricas suman `importe_total` y calculan ticket medio con ese escalar. | Adaptador de neto comparable por versión y conteo único de órdenes; no sumar alias previo al manual como ingreso neto. |
| `lib/sql/reporte_ordenes_json.sql` | Archivo local agrega importes e inventario, descuento global y pagos; filtra catálogo de medios activos. | No usarlo como copia exacta de newa: inspección remota detectó campos monetarios adicionales. Evitar fan-out y desaparición de cobros históricos al desactivar medio. |
| `services/cxc_service.dart` | Saldo `double`, fallback a cero y liquidación escalar/FIFO por operación. | Lectura de saldo por moneda y línea; error no equivale a deuda cero. Coordinar M05, no sumar directamente deuda v1 a saldo legacy. |
| `financial_dashboard_service.dart` | Llama RPC no encontradas en la inspección y tiene fallbacks mock/ceros. Tiene consumidor en `financial_dashboard_screen.dart`. | Confirmar alcance activo; no usar mocks/ceros como evidencia financiera v1 ni declarar esta ruta compatible sin prueba. |
| `financial_reports_service.dart` | Parte de rentabilidad deshabilitada; otras rutas contemplan mocks. Tiene consumidor en `financial_reports_screen.dart`. | Clasificar alcance real de cada método; no implementar RPC inexistentes solo por aparecer en un comentario. |
| `products_analytics_service.dart` | Análisis con costo promedio y precio de catálogo. | Separar análisis de catálogo/proyección de utilidad realizada histórica; no revaluar ventas viejas con precio/costo actual. |
| `sales_analyst_service.dart` / controller | Serializa ventas/costos/ganancias para el analista. | Enviar magnitud, moneda, corte y cobertura; no inventar ingresos ni exponer ganancias restringidas a través del contexto de IA. |
| TPV: impresoras Wi-Fi, Bluetooth, web y rutas activas restantes | Usan total escalar y descuento global legacy; algunos fallbacks agrupan desde items. | Ticket v1 deriva netos/selecciones persistidos, distingue pagado/pendiente y no aplica de nuevo descuento global. MC-046 verificará todas las rutas de impresión activas, incluida física. |
| TPV: cierre y resumen de turno | Mezcla de métricas comerciales y caja en consumidores existentes. | Caja procede de cobros/egresos/entradas, no del neto de productos no cobrados; mantener corte de turno explícito. |

Los paths de servicios/modelos/pantallas admin son relativos a `ventiq_admin_app/lib`. Esta tabla es inventario de impacto, no prueba de implementación ni de navegación completa. MC-045 debe continuar llamadas y exportaciones de cada ruta activa, incluidos widgets de inicio que usan tienda propia, no necesariamente la activa en preferencias.

### 2.2 Newa: catálogo y lectura de definiciones, sin ejecutar reportes de negocio

| RPC observada | Huella MD5 de definición |
|---|---|
| `reporte_ordenes_json(bigint,timestamptz,timestamptz,bigint)` | `1f89076eeab2c2c97a45d7e50cded8c4` |
| `fn_reporte_ventas_por_moneda(bigint,date,date,bigint)` | `91c3bae42dde03438fa2d547cfb1767a` |
| `fn_reporte_ventas_con_proveedor5(bigint,date,date,bigint,text)` | `e889b26a9e276440a74d4c7f22d81fd6` |
| `fn_reporte_ventas_con_proveedor_por_turno_v2(bigint,date,date,bigint)` | `9046834077312a68d8be32552d02e2ec` |
| `fn_listar_ordenes(bigint,bigint,uuid,smallint,date,date,bigint,boolean,boolean,integer,integer)` | `aff1002843b275c1d5d974cb9f923449` |
| `fn_resumen_turno_por_id(bigint)` | `3a409f7a7554f61e18c7e15eb1909b73` |

No se encontraron `fn_profit_and_loss` ni `fn_sales_metrics` en public durante esta inspección. Las seis definiciones anteriores no mencionan `version_monetaria`; esto es diagnóstico textual, no auditoría completa de capacidades/autorización. Las huellas identifican el baseline observado, no firmas de seguridad ni instrucciones para retroceder funciones si newa avanza.

La definición leída de `fn_reporte_ventas_por_moneda`:

- Agrega `app_dat_pago_venta`, cuenta operaciones distintas por moneda y suma nativo/equivalente CUP almacenado.
- Filtra por fecha de creación de operación y último estado 2; el comentario local que dice que no filtra por estado no coincide con newa.
- Usa `fn_moneda_consolidacion` para la presentación; no es una segunda venta ni reemplaza el equivalente histórico.
- Por tanto describe cobros atribuidos a una cohorte de ventas, no necesariamente cobros ocurridos dentro del intervalo de fecha de pago. No renombrar esa métrica sin adaptar contrato/filtros.

MC-001 además encontró 139 referencias textuales a extracciones, policies públicas permisivas y ocho tablas sin RLS. No asumir aislamiento por tener `SECURITY DEFINER` o RLS encendido; MC-005 debe revisar acceso directo y por RPC. No ejecutar ni copiar DDL de los archivos locales para igualar newa con ellos.

## 3. Diccionario financiero y grano

| Magnitud | Fuente/grano autorizado | Nunca sustituir por |
|---|---|---|
| Venta bruta | Línea comercial: cantidad y precio nativo anteriores a ajustes, según snapshot | Precio actual del catálogo o cobro recibido |
| Automático/manual/recargo | Ajustes efectivos del detalle y sus insumos/snapshots; manual fijo por unidad | Descuento global legacy repartido por suposición o gasto operativo |
| Venta neta | Neto fijado de cada línea, después de ajustes; totales nativos por moneda | `importe_total` genérico, SUM de pagos o SUM de nativos mezclados |
| Neto contable CUP | Suma de equivalentes netos históricos fijados por línea | Convertir hoy el total USD, precio CUP actual del producto o valor visual consolidado |
| Cobrado | Pagos reales válidos, sus aplicaciones y ajustes de cobro; una vez por identidad | Medio seleccionado en producto, pending/sentinel, factura o liquidación además de su pago |
| Saldo nativo | Obligación vigente de línea menos aplicaciones válidas en su misma moneda, con ajustes documentados | Diferencia de equivalentes CUP o deuda en otra moneda |
| Coste realizado | Fuente histórica de costo vinculada al consumo/venta con unidad, moneda y factor demostrables | Precio de costo/promedio actual o cero porque el campo no llegó |
| Utilidad comercial | Neto menos coste realizado comparable, indicando moneda/base y cobertura | Neto menos descuento otra vez; cobrado menos coste de ventas distintas |
| Gastos operativos | Fuente de gastos real y su moneda/fecha, independiente del descuento comercial | Descuentos como gastos para restarlos dos veces |
| Operaciones/ticket medio | Identidades únicas de ventas elegibles; promedio de neto comparable por esas órdenes | Suma de conteos por divisa o número de filas de join |

Una extracción de inventario no comercial no se convierte en una venta por contener precio. Cuenta/mesa/comanda aún abierta y borrador no son una segunda venta; referenciar su finalización comercial única. No asumir que toda línea requiere una fila de inventario directa: servicios/elaborados pueden tener consumos de ingredientes. Separar integridad financiera de evidencia de stock; verificar ambos sin descartar dinero silenciosamente.

Cantidades por presentación no se suman como si fueran la misma unidad. Usar equivalentes base solo con factor histórico válido; no aplicarlo otra vez al precio/importe. Un unitario representativo de reporte no sirve para reconstruir totales si la fila agrupa varios precios, factores, monedas o tasas.

## 4. Sumas, redondeo y trazabilidad

1. Usar las cantidades financieras persistidas del contrato de venta, no reevaluar promociones/precios/tasas al consultar.
2. Agregar nativos únicamente dentro de la misma moneda y magnitud. Agrupar cobros por moneda/medio no obliga a un pago por producto.
3. Sumar equivalentes CUP ya fijados por línea/aplicación. Dos líneas 5 USD a tasas 400 y 420 forman 10 USD / 4.100 CUP, no 4.200 CUP. Una tasa promedio de reporte es informativa, no fuente para recalcular registros.
4. Descuento manual nominal = descuento unitario × cantidad vendida, antes de redondear la línea. Neto ya descontado no vuelve a descontarse al agregar/reportar.
5. Conservar bruto, previo al manual, neto, nominales y residuos del cálculo. El residual del neto ideal frente al neto fijado puede diferir del residual que reconcilia componentes mostrados redondeados por separado. No llamar descuento o gasto a ese residual ni modificar nativos para cuadrarlo.
6. Si un reporte expone bruto/descuentos/recargos/neto, su contrato debe declarar componentes y ajuste de redondeo que satisfacen la reconciliación en esa moneda/base. Derivarlos de los insumos del snapshot según núcleo aprobado, no inventar otra regla de redondeo en el lector.
7. Preagregar líneas, pagos, ajustes y stock por sus respectivas identidades antes de unir resultados. JOIN de dos pagos y dos movimientos no multiplica el importe de una línea. COUNT DISTINCT de órdenes no repara un SUM monetario ya duplicado.
8. Una liquidación CxC y los pagos que genera no son dos cobros. El vínculo de atribución no crea dinero adicional. Devolución comercial y devolución de dinero son eventos relacionados, no equivalentes automáticos.

## 5. Fechas, estado y deuda — propuesta REP

Distinguir expresamente estas bases temporales; no cambiar el significado de una RPC legacy por cambiarle una etiqueta:

| Base | Ventana y significado |
|---|---|
| Comercial | Ventas/ajustes comerciales por instante persistido aceptado; documentar estados que hacen elegible cada ruta. No filtrar venta a crédito solo por es_pagada=false. |
| Cobros del período | Pagos/devoluciones de cobro por fecha propia, no fecha de la venta. Puede incluir liquidación de una venta de otro período. |
| Cohorte de ventas | Ventas filtradas por su fecha y pagos atribuidos hasta corte declarado. No llamarlo flujo de caja del período. |
| Saldo al corte | Obligaciones y aplicaciones/ajustes hasta ese instante. No restar cobros futuros ni usar el saldo actual como si fuera histórico. |
| Turno | Alcance/identidad y ventana del turno según contrato existente; no mezclarlo con un simple rango de creación. |

Propuesta para lectura v1 nueva: intervalos de instantes [desde, hasta), zona declarada y hasta exclusivo. Adaptar explícitamente los filtros de fecha inclusiva existentes; no alterar sus resultados legacy incidentalmente. Una fecha local se traduce a límites UTC con zona conocida, no con la zona del teléfono. Si el dato viejo no permite el corte prometido, declararlo no comparable, no fabricar el instante.

Cambios posteriores de flag, moneda forzada, tasa, catálogo, promoción o estado activo del medio no cambian snapshots. Una baja de medio puede impedir nuevas selecciones, pero no borrar sus cobros históricos del reporte.

Anulaciones/devoluciones v1 se leen como ajustes autorizados con referencia a origen y fecha/estado del evento; no borrar o mutar la venta original para reescribir un período cerrado. La vista de estado actual y la vista de eventos/corte se identifican como tales. El detalle de estados/reconocimiento y de reversión de costos debe concretarse por ruta con M05/MC-045 antes de implementar, conservando las reglas aprobadas y sin crear una política fiscal nueva.

Pagos parciales mantienen moneda y medio real fijado según venta/CxC. Un equivalente CUP suficiente no liquida una obligación USD si falta su pago nativo. Una discrepancia de atribución/tasa/cobertura se informa; no se corrige asignando medio, convirtiendo deuda ni moviendo importes de otra moneda.

## 6. Compatibilidad, disponibilidad y presentación mínima

- Leer versión persistida por orden/detalle, no flag actual. Apagar el flag conserva interpretación v1 de ventas ya creadas. NULL legacy genuino conserva su contrato; versión desconocida no se interpreta como legacy.
- La rama legacy, sus campos/payloads y presentación actual permanecen. No backfill de moneda/medio/tasa por detalle desde pagos de orden o configuración actual. Un pago legacy puede tener moneda real conocida sin que eso autorice atribuirla a sus productos.
- Un alias legacy de CUP previo al manual no se convierte en neto v1. El adaptador legacy usa solo significado demostrado de su fuente y correcciones ya existentes, no resta dos veces el descuento global.
- Dataset mixto puede sumar equivalentes CUP solo cuando representan la misma magnitud/base/corte y están demostrados. No tratar información desconocida como 0. Publicar cobertura y motivos; si no permite un total global verdadero, usar estado incompleto/no disponible, no un subtotal parcial etiquetado como total.
- Propuesta REP: KPI contable de un dataset con v1 usa CUP histórico y etiqueta CUP explícita. La consolidación visual existente es otra magnitud/presentación, no cambia contabilidad, precio o saldo. Legacy-only conserva su presentación; no imponer un rediseño de sus tarjetas.
- No sumar importe_nativo con importe_base/consolidado ni convertir de nuevo importe_consolidado ya expresado en su moneda. No aplicar moneda forzada actual como etiqueta a un equivalente CUP.
- No se autoriza una política nueva de conversión visual a USD u otras monedas. Donde la presentación v1 requiera conversión no definida, MC-045 debe resolverla antes de dar el consumidor por compatible; el KPI CUP propuesto no depende de ella.
- Sin nuevas pestañas, gráficos o desgloses de producto/moneda. Reutilizar controles, estados de error y etiquetas existentes que eviten mentir sobre unidad/dato. PDF/Excel/widgets existentes y analista consumen el mismo adaptador, magnitud y cobertura, no reconstruyen totales por su cuenta.
- No sustituir ausencias por mocks/ceros ni hacer fallback a una RPC vieja tras un error de permisos. Un fallback de capacidades solo es admisible para datos legacy y contrato compatible verificado. Datos v1 requieren capacidad v1 y fallan de forma visible si no está disponible.
- Reportes administrativos globales se consultan online; cualquier caché existente debe conservar tienda, versión, corte y estado de antigüedad, sin añadir otro catálogo/pipeline por esta spec. Ticket/reimpresión/cierre offline usan el contrato de orden y pagos ya persistido por el sync existente. Caché vacía/corrupta o snapshot faltante no permite recalcular con catálogo/tasa actual ni presentar una cola local como reporte global completo.

## 7. Contrato de lectura propuesto, aditivo

Separar versión de reporte de versión monetaria de cada registro. La forma exacta y nombres de RPC se revisarán en MC-045; no cambiar a ciegas RETURNS de funciones que ya consumen clientes legacy ni crear un contrato paralelo de cálculo.

| Grupo lógico requerido | Contenido |
|---|---|
| Identidad/capacidad | version_reporte, versiones monetarias incluidas, id de tienda/TPV autorizado y grano de filas. |
| Semántica | magnitud (venta_neta/cobrado/saldo/etc.), moneda/unidad por importe y base temporal/corte/estados/filtros resueltos. |
| Completitud | estado completo/incompleto/no_disponible/no_autorizado; conteos de registros comparables/no atribuibles y motivos, sin exponer datos de otra tienda. |
| Orden y línea | id de operación, id_linea_cliente/extracción para v1, versión y referencias de snapshot; claves que permiten reconciliar sin exponer evidencia privada. |
| Montos | Valores exactos como cadenas decimales según MC-003; nativo con moneda, equivalentes con unidad CUP, componentes/residuales identificados cuando correspondan. |
| Cobros/deuda | Identidades de pagos/aplicaciones/ajustes; medio seleccionado separado del cobrado real y saldo nativo. No inferir pago de una bandera UI. |
| Coste/utilidad | Disponibilidad/cobertura/fuente histórica y unidad; null/no autorizado cuando corresponda, nunca 0 de relleno. |

Agregados de eventos con devoluciones pueden resultar negativos con su signo/origen declarado; esto no relaja la exigencia de cantidades/precios positivos del DTO de alta. El reporte no genera deuda negativa por exceso de aplicación ni reclasifica excedentes como ingresos sin un contrato autorizado.

En un conjunto vacío válido los totales de la magnitud autorizada pueden ser cero con estado completo. Eso es distinto de error, valor faltante o denegación de acceso. Un éxito con números malformados/no finitos/versión desconocida no se degrada a ceros. Decimales/cantidades no pasan por double para computar la autoridad monetaria; conversión final de presentación no vuelve a sumarse como libro contable.

Una omisión de campo requerido es error de contrato. Paginar/exportar usa mismo conjunto/corte coherente: las filas paginadas no se presentan como total global y cambios concurrentes no duplican/omiten cobros entre páginas. MC-045 debe fijar mecanismo de consistencia, paginación e índices por consulta, con límites de memoria/payload verificables; no fijar aquí un umbral inventado.

## 8. Seguridad y límites de acceso

Validar en servidor acceso a tienda/TPV/turno y permisos para costo/utilidad, independientemente de preferencias y banderas del cliente. Misma política para consulta, exportación, dashboard, widgets y contexto de IA. Ocultar una etiqueta no permite devolver costos restringidos en JSON ni derivarlos de agregados filtrados parcialmente.

Ningún reporte usa SECURITY DEFINER como sustituto de RLS. Revisar políticas permisivas existentes y helpers que excluyen vendedores antes de reutilizarlos: lectura de su operación/turno no equivale a acceso administrativo a toda la tienda. Las reglas concretas y sus pruebas por rol se fijan en MC-005; esta spec no concede privilegios nuevos.

Consultas sensibles por tienda se parametrizan; p_id_tienda es alcance solicitado, no prueba de autorización. Datos históricos sin nueva atribución no se hacen públicos por estar incompletos. No exportar tokens/constancias/evidencias privadas o PII innecesaria para reconciliación. Cualquier tabla nueva requiere RLS/policies inmediatamente en su creación, con SQL revisado y ejecutado por el usuario en newa.

## 9. Matriz de ejemplos verificables

Vectores ficticios para pruebas futuras M06, no ventas/remesas ejecutadas. Reutilizan los fixtures monetarios MC-003 donde aplica.

| Caso | Resultado exigido |
|---|---|
| R-01: 3×100 CUP, manual 10/unidad | Bruto 300, manual nominal 30, neto 270 CUP. No 290 ni 240; no gasto de 30 adicional. |
| R-02: 3×1,05 USD, automático 10%, tasa 400 | Neto 2,84 USD y 1.136 CUP. Mantener 0,945 unitario calculado y residual; no cobrar 2,85 ni convertir precio CUP para reemplazarlo. |
| R-03: juntar R-01/R-02 | Una orden, netos nativos separados 270 CUP y 2,84 USD; neto CUP 1.406. Si cobrada completa, sus pagos no elevan ingreso comercial a 2.812 CUP. |
| R-04: 5 USD a 400 y 5 USD a 420, mismo medio | 10 USD nativos, 4.100 CUP atribuidos. Puede ser pago agrupado; no recalcular a 4.200. |
| R-05: venta 1.000 CUP día A, cobros 300 A y 700 B | Comercial A=1.000/B=0; cobrado A=300/B=700; saldo al cierre A=700/B=0. Cohorte A hasta B puede mostrar cobrado 1.000, no flujo A=1.000. |
| R-06: obligación USD, solo equivalente pagado en CUP | No declarar deuda USD saldada por igualdad de CUP. Dato inconsistente no se arregla en el lector. |
| R-07: 2 líneas, varios pagos y movimientos por línea | Importes/conteos iguales con o sin joins de auditoría; una orden no se convierte en varias por moneda/inventario. |
| R-08: tres líneas distintas del vector tiny_usd_line | Total nativo 0,03 USD / 12 CUP; no redondear de nuevo el ideal agregado para mostrar 0,02 USD. |
| R-09: legacy con pagos USD y detalles sin moneda | Pagos mantienen su moneda documentada; detalle sigue sin atribución. No asumir que todas las líneas eran USD. |
| R-10: cambio posterior de tasa/flag/medio activo | Montos históricos nativos/CUP no cambian, cobro no desaparece y versión persistida sigue mandando. |
| R-11: coste histórico no demostrable | Venta neta válida no se pierde; utilidad/coste no disponibles o cobertura explícita, no coste 0 ni ganancia igual a toda la venta. |
| R-12: cancelación/devolución posterior con pago parcial | Origen y ajuste aparecen una vez según corte; no borrado retroactivo ni doble reembolso/stock. Evento comercial no implica devolución de dinero sin evidencia. |
| R-13: mock, RPC ausente, campo requerido inválido o permiso denegado | Estado de error/no disponible, no informe ficticio exitoso. Sin fallback de v1 a legacy. |
| R-14: exportación/analista/widget frente a tabla | Igual magnitud, unidad, filtros, corte, cobertura y permisos; ninguna suma de nativos distintos ni fuga de costos. |

Para utilidad, no comparar ingresos CUP con costo USD sin equivalente histórico autorizado. Análisis a precios actuales sigue identificado como simulación/catálogo y no reemplaza venta neta realizada. Las pruebas deben incluir presentaciones, servicios, mesa/cocina y CxC, no solo producto físico de mostrador.

## 10. Criterios de aceptación

| ID | Criterio | Prueba mínima / trazabilidad |
|---|---|---|
| PCR-AC-01 | Versión capturada y legacy preservados, incluso tras apagar flag. | R-09/10, payloads/regresiones legacy; PCS-01/03/09. |
| PCR-AC-02 | Neto, bruto, ajustes y residuales coherentes, sin doble descuento. | R-01/02, fixtures MC-003 y contrato de componentes; PCS-02/07/12. |
| PCR-AC-03 | Magnitudes nativas separadas y CUP histórico fijado, sin revaluar. | R-03/04/08/10; PCS-02/06/07/12. |
| PCR-AC-04 | Pagos/atribución y comercial no duplican ingresos. | R-03/07/12 y prueba de fan-out; PCS-08/12. |
| PCR-AC-05 | Fechas/cortes y crédito parcial no confunden ventas, flujo y deuda. | R-05/06, límites de intervalo/turno y liquidación posterior; PCS-06/11/12. |
| PCR-AC-06 | Conteos y cantidades respetan identidad y presentación. | R-03/07, venta mixta única y factor no duplicado; PCS-04/05/11. |
| PCR-AC-07 | Información legacy/incompleta no se inventa ni se trata como cero. | R-09/11/13, cobertura/errores de contrato; PCS-09/12. |
| PCR-AC-08 | Coste/utilidad no usan fuentes actuales como realizadas ni duplican descuentos/gastos. | R-01/11/12, monedas/factores/roles; PCS-09/11/12. |
| PCR-AC-09 | Todas las salidas existentes usan el mismo contrato/unidad. | R-14, UI/PDF/Excel/widget/analista y ticket por MC-046; PCS-11/12. |
| PCR-AC-10 | Aislamiento/permisos en servidor, sin fugas por agregados/exportación. | Vendedor/gerente/superadmin/anon/otra tienda y costo restringido; PCS-10, SPC-AC-04/05. |
| PCR-AC-11 | Cambios de configuración/catálogo no borran ni revalúan registros. | R-10/12, medio inactivo y replay; PCS-03/07/08/09. |
| PCR-AC-12 | Compatibilidad demostrada antes de activar, sin nuevos desgloses generales. | Inventario activo cerrado, M06 + MC-046 verificados, REP/P7/ACT separados; PCS-11/12, SPC-AC-11/12. |

Los tests actuales de sales_totals_summary verifican layout/ocultación, no exactitud monetaria, permisos de backend ni ausencia de fan-out. Pruebas de texto SQL tampoco sustituyen ejecución en PostgreSQL ni impresión física. Al implementar: tests de adaptador/DTO/cálculo exacto, fixtures de integración SQL por rol/estado, pruebas de exportación y validación de consultas/cortes sobre datos ficticios autorizados.

## 11. Puertas y siguiente trabajo

1. Usuario revisa y aprueba esta spec (REP). El borrador no altera las decisiones de venta ya aprobadas ni aplica migraciones.
2. MC-045 prepara tareas M06 por consumidor activo con entradas/salidas, campos, estados, filtros/cortes, permisos, índices, fixtures y recuperación. Identificar llamadas indirectas/código deshabilitado y asignar cada consumo real, sin dar por compatibles las 139 referencias textuales.
3. Implementar/validar contratos aditivos y consumidores coordinados con P4/P6/MC-046, sin reinterpretar legacy ni reemplazar avances de newa por archivos antiguos.
4. Usuario ejecuta scripts revisados en newa, agente verifica en lectura; completar P7 y pruebas integrales antes de ACT. No activar por haber aprobado el documento o compilado Flutter.
5. Main requiere comparación y autorización propias. No se migra ni se recompone histórico como rollback; si un lector falla, bloquear su activación/operación de forma visible y preservar datos/cola.

Estado actual: sin código productivo, SQL de migración, datos de negocio o pruebas funcionales de reportes modificados. REP aprobada. MC-005 prepara la matriz de seguridad; MC-045 ya puede detallar las tareas M06, cuya implementación sigue pendiente de ese desglose, sus dependencias y puertas SQL.

## 12. MC-045 — tareas M06 sometidas a revisión

Estas tareas no están implementadas. Aprobar este desglose no enciende el flag ni autoriza SQL de reportes.

| ID | Consumidor | Entrada | Salida | No hacer |
|---|---|---|---|---|
| M06-01 | `getProductSalesReport` | Venta con versión, presentación y moneda de línea | Neto nativo y equivalente CUP por separado | Caer a la RPC vieja si falta permiso o red |
| M06-02 | `VentasPorMoneda` y pantalla de ventas | Filas v1 y filas sin versión | Legacy igual; v1 declara magnitud y moneda | Mostrar un ausente como cero |
| M06-03 | Métricas de cliente | Órdenes únicas y neto por versión | Ticket medio sobre el neto comparable | Sumar el alias previo al manual como ingreso |
| M06-04 | `reporte_ordenes_json` | Pagos y líneas ya guardados | Cobrado, deuda y comercial sin fan-out | Borrar un cobro histórico al desactivar el medio |
| M06-05 | CxC | Obligación por línea y moneda | Saldo nativo por moneda | Sumar CUP con USD ni devolver cero ante un error |
| M06-06 | Tableros y analista | Magnitud, moneda, corte y cobertura | Lo que el rol puede ver | Usar un mock o el precio actual como venta realizada |
| M06-07 | Exportaciones ya existentes | El mismo contrato de M06-01 a M06-06 | La misma unidad en UI, PDF y Excel | Abrir un desglose visual nuevo |
