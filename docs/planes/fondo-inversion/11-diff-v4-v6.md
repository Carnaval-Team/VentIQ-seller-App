# v4 → v6: auditoría de pérdida de información en `PLAN.md`

**Alcance.** v4 = `origin/main:docs/planes/fondo-inversion/PLAN.md` (`f081ba7d`, padre 2 del merge
`bab9725b`): **892 líneas / 53.167 B**. v6 = el archivo en `multimoneda` (`09266ec8`), 595 líneas.
(El encargo decía 753 líneas para v4; `origin/main` tiene 892 y el contenido cierra coherente, así que se
auditó esa). Volcados UTF-8 en `.dsh/tmp/v4.md` y `.dsh/tmp/v6.md`. Solo lectura: no se editó el plan.

**Veredicto.** No se perdió ninguna PD ni ninguna fase, y las correcciones de la v6 son correctas. Se
perdieron **4 elementos de gravedad alta** —el parámetro `p_origen` de la recepción con su nota de
compatibilidad, la fórmula del backfill de `costo_real`, dos invariantes de dinero y el E2E integral— y
~25 piezas menores, casi todas por compresión de build/checklist/E2E. Criterio de A: solo cuenta lo que
cambia lo que un ejecutor haría.

## A · Pérdidas reales

| # | Elemento | v4 | Falta en v6 | Grav. | Texto a recuperar |
|---|---|---|---|---|---|
| A1 | `p_origen` en la recepción | L512-514, L575 | No existe el parámetro, ni el eje `compra\|externa`, ni la regla de derivación | **alta** | "**`p_origen text DEFAULT 'externa'`** en la operación de recepción … Con DEFAULT no rompe a `ventiq_app`, ni a los RPC de transferencia entre layouts, ni a los egresos con rebalanceo. **No añadir un eje que contradiga `motivo`**: `origen` se **deriva** de `motivo`." |
| A2 | Fórmula del backfill de `costo_real` | L628-630 | v6 (0b-3) solo dice "backfill de las 30.038 filas NULL" | **alta** | "hacer **backfill** (`= precio_unitario − descuentos`) y dejar un **rollback** que restaure la expresión." |
| A3 | E2E integral + salida de la fase 8 | L768-783 | La fase 8 de v6 es un párrafo: única fase sin Exit criteria ni E2E | **alta** | Los 8 pasos ("Ingresar saldo al fondo en dos monedas … Abrir todo en móvil, tablet y PC") y "Todos los reportes cuadran con los datos de prueba de las fases 3-7". |
| A4 | Inmutabilidad de las tres cifras | L113-114 | v6 lista las cifras y calla qué es inmutable | **alta** | "El `total_financiado` es inmutable tras reservar; el `costo_aterrizado` crece con documentos de ajuste." |
| A5 | Definición de tasa y no-regresión de v1 | L102-105 | "`T(A→B)` con par explícito. `fn_fdi_transferir` no se toca; se crea `_v2`" | media | "`T(A→B)` = unidades de B por 1 de A … Cambiar la semántica de la v1 sin cambiar su firma rompería el cliente desplegado (`fondo_inversion_service.dart:389`) con un factor de 103 en dinero real." |
| A6 | Regla de redondeo | L310, L645 | "residuo" y "mayor base" no aparecen | media | "redondeo en servidor, **residuo a la línea de mayor base**." |
| A7 | Ajustes `por_financiar` | L133, L652-653 | Desapareció la fila de la tabla de dinero y no hay bullet de build | media | "cada uno crea su propia reserva y pago (nunca mutan `total_financiado`) y generan un **documento de ajuste de costo** que actualiza la valoración sin reescribir el histórico." |
| A8 | Protocolo E2E por fase | L254-255 | Solo queda "E2E del dueño" como paso de promoción | media | "cada fase entrega una lista numerada de pasos literales … qué hacer, qué debe verse, qué haría fallar. **Sin OK del dueño no se abre la fase siguiente.**" |
| A9 | E2E numéricos de la fase 5 | L593-616 | v6: "3 recepciones parciales suman"; sin cifras ni script de fallo | media | "100 → 60 (pendiente 40) → 25 (15) → 15 (0); una cuarta recepción se rechaza"; "`verify/05_forzar_fallo.sql`, que hace `RAISE` en la segunda línea; la operación **no** debe quedar creada." |
| A10 | Grano de `fn_fdi_conciliacion` | L314-315 | v6 omite el agrupamiento | media | "por (cuenta, medio, moneda) devuelve `saldo`, `Σ movimientos`, `último saldo_nuevo` y la diferencia." |
| A11 | Alcance de la validación R1 | L304-305 | v6 solo pide que `p_id_tienda` corresponda a la cuenta | media | "…y que medio/moneda sean coherentes con la tienda." |
| A12 | Alcance de la idempotencia | L345-348 | v6: "`uuid UNIQUE` en el movimiento", sin forma del índice ni RPCs | media | "índice único **parcial por `tipo`** … Aplicar a `fn_fdi_ingreso_manual`, `fn_fdi_ajuste`, `fn_fdi_gasto`." |
| A13 | Cordura de `fn_fdi_transferir_v2` | L349-352 | v6: ">20 % → rechazo", sin referencia ni columna inversa | media | "rechazar si la tasa se aparta >20 % de la **última conocida del mismo par**) e **inversa desnormalizada**." |
| A14 | Contrato de X9 | L355-356 | v6: "tasa de pagos resuelta en servidor" | media | "desde el histórico por fecha; **el cliente no la provee**." |
| A15 | `fn_fdi_compra_liberar` / `_anular` | L458-459 | v6 los nombra sin comportamiento | media | "liberar (cancelación, **motivo obligatorio + usuario**) y anular (contramovimiento de lo pagado no consumido + liberación)." |
| A16 | Fórmula y defaults de la fase 3 | L402-406 | v6: "`total_financiado` por trigger"; falta la fórmula y dos constraints | media | "`total_financiado` recalculado por trigger desde líneas + ajustes con `origen_pago = fondo`"; "`CHECK(costo_unitario >= 0)`"; "`origen_pago` NOT NULL con default `fondo` en ajustes de mercancía." |
| A17 | RLS/GRANT y contrato de las RPC | L407-411 | v6: "RLS en las 5 tablas; escritura solo por RPC" | media | "+ `GRANT SELECT` a `authenticated`"; "`fn_fdi_compra_editar` (**solo en `creada`**) … Todas con idempotencia y validación de tienda"; "Ruta `/compras`, entrada en `admin_drawer.dart`, permisos dueño/gerente." |
| A18 | Matriz de permisos por rol | L411, L808 | v6 solo dice "permisos por rol" | media | "el almacenero ve pendientes y recepciones; el dueño/gerente ve montos y exporta." |
| A19 | Ventana de edición del cargo de importadora | L505-507 | v6 enumera columnas y calla el resto | media | "**editables antes de confirmar, con historial de quién cambió qué**." |
| A20 | Filtro de líneas ofrecidas | L508-509 | v6: "Solo productos de la compra (PD6)" | media | "solo se ofrecen sus productos **con pendiente > 0**." |
| A21 | Selector de carga multi-factura | L528-530 | v6 describe el modelo, no la pantalla | media | "poder marcar **varias compras** … que cada bloque muestre su factura, proveedor y su % de importadora." |
| A22 | Desvío de importadora visible (PD8) | L86-88 | No está en PD8 ni en la fase 6 | media | "la fase 6 muestra el desvío (`Σ cargos` vs `Σ valores de factura vinculados`) sin corregirlo sola." |
| A23 | Exclusividad y naturaleza del aporte | L707-712 | v6: "Exclusividad 100 % en BD; `Σ aportes = total_financiado`" | media | "no puede existir pago ni reserva con `origen = fondo`"; "devolución = cancelación de pasivo; solo el interés es gasto si `naturaleza = pasivo`." |
| A24 | E2E con cifras de fases 1, 2 y 7 | L332-336, L375-379, L729-735 | v6 deja criterios genéricos | media | "inversión de 1.000 USD anulada → saldo vuelve al inicial"; "X aporta 800, Y aporta 700 → restante 500 y **no deja pagar**". |
| A25 | `DROP` de los overloads de 9 args | L515-516 | v6 solo verifica "1 sola firma" | baja | "`DROP` de los overloads de 9 args y verificar `pronargs` + ausencia de sobrecargas." |
| A26 | Función que propaga el lote | L524-526 | v6 conserva "el lote sobrevive" y "camino único con lote", no la función | baja | "usar `fn_contabilizar_recepcion_inventario` (el único que propaga `id_lote`)." |
| A27 | Efecto de `fn_fdi_compra_cerrar_corto` | L561-564 | v6 lo nombra sin efecto | baja | "Registra la diferencia, libera lo no usado y **no** reescribe el dinero ya pagado." |
| A28 | Fase 8: descuadre declarado y legado | L749-750 | v6: "retirar el alta … (legado del carril B)" | baja | "listado de compras con descuadre declarado"; "marcar el módulo como legado de solo lectura." |
| A29 | Fase 9: detalle, export y orden | L798-805 | v6: "detalle de faltantes por producto y línea; registro exportable" | baja | "última recepción, días sin movimiento"; "Excel/PDF … del histórico de recepciones"; "Ordenable por antigüedad y por monto." |
| A30 | Pantallas Stitch de fases 4-7 y 9 | L463, 530, 659, 713, 809 | v6 solo conserva las tres de la fase 3 | baja | `LIQUIDACIÓN — multimoneda (desktop/móvil)`, `RECEPCIÓN — carga multi-factura`, `RECEPCIÓN — importadora y adicionales`, `CONFIG — costos adicionales`, `COMPRA — aportes de inversores`, `PENDIENTES — panel/detalle`. |
| A31 | Regla de parada | L224-226 | v6 no la tiene | baja | "Si una suposición se cae, **para, actualiza este archivo y dilo**; no improvises en silencio." |
| A32 | Checks que salieron de `verify/00` | L274-282 | v6 tiene 8 (superset) pero pierde dos | baja | "(f) `imp_dat_factura` tiene columnas de moneda y de compra"; y `app_cont_tipo_costo` en la lista del baseline. |
| A33 | Fase 6: caso fondo y reparto configurable | L644-645, L675-676 | v6 solo conserva el caso wallet | baja | "si es fondo, `= 2.150`"; "cantidad/peso como excepción configurable". |
| A34 | PD2: quién declara el descuadre | L71-74 | v6: "hasta declarar motivo" | baja | "dueño/gerente declare el motivo (queda en historial)." |

## B · Reescrituras equivalentes (las que alguien podría echar de menos)

| Elemento | v4 | v6 | Por qué es equivalente |
|---|---|---|---|
| Fases 1-2 sin checklist ni E2E propios | L317-379 | Una línea "Checklist / Exit criteria / E2E" | Se conservan R1/R2/R3/R6/R7, `_v2`, idempotencia, X9, X11 y conciliación 0,00; solo cambia la forma (las cifras, en A24). |
| E2E de la fase 4 (6 pasos) | L482-489 | Una frase con 2.000 / 1.000 / 20.000 / 1.000 / 980 | Las cifras caras sobreviven; los pasos 3-6 quedan cubiertos por los Exit criteria (disponible vs saldo, liberación, segunda compra). |
| Tabla "cinco eventos" | L123-138 | Tabla de 8 filas "eventos del carril A" | Misma semántica por compra; la fila "llega un costo después de pagar" es A7. |
| Firma de `fn_fdi_inversion_anular` | L307-308 | `fn_fdi_inversion_anular` sin firma | El comportamiento (contramovimiento, historial, estado `anulado`) se mantiene. |
| Cinco filas de la tabla de riesgos (rastra 4 facturas, % por recepción, recordatorio, multi-almacén, convivencia del legado) | L862-868 | No están como filas | El requisito vive en el cuerpo: multi-factura (L179-183), PD3, fase 9, `id_almacen/id_ubicacion` (L400), arquitectura del legado. No se pierde ningún riesgo. |
| Rutas de artefactos | L245, L651 | `ventiq_admin_app/lib/sql/`, `inventory_service.dart:1409-1414` | Mismo artefacto, ruta y líneas corregidas. |
| PD5: para qué existen `reservada`/`anulada` | L75-77 | Lista de 7 estados | El uso está en la tabla de eventos (`reservas activas`, `contramovimiento`). |
| PD7: "lo no recuperable sí capitaliza" | L78-81 | "Si el IVA fuese acreditable…" | La regla queda en Arquitectura: un componente capitaliza siempre, se financia solo si su origen es `fondo`. |
| "Restricciones del entorno" en prosa | L140-159 | Tabla `Entornos` newa vs Main | Misma información, ahora medida; lo obsoleto pasó a C. |
| "Modelo de importadora" en prosa | L161-181 | Tabla de 4 filas + ejemplo | Conserva conceptos y el ejemplo 2.000 / 15 % / −150 / 2.150. |

## C · Corregido a propósito (no es pérdida)

| Qué decía v4 | Qué dice v6 | Motivo |
|---|---|---|
| Deprecar/redirigir `fn_registrar_cambio_estado_operacion_mejorado` en "Completar" (L524-526) | "**No se depreca.** Es el camino de cancelación/devolución" | Es la función combinada main+newa del 19/11 (compensatorio `origen_cambio` 4/5, `RECEPCION_INVENTARIO_USADO`); deprecarla deja devoluciones y el fix pendiente de Main sin camino. Ver la tensión en §4. |
| Crear rama `dev` desde `origin/main` (L144, L268) | Base `multimoneda`; rama de trabajo `feat/compras` desde ella | No existe `dev`, y `multimoneda` ya trae el trabajo (`2bff5b18`): ramificar de `origin/main` lo habría perdido. |
| "6 modificados y 3 sin trackear", 11 ramas `worktree-agent-*` (L142-145) | No aparecen | Hoy `git status --porcelain` está vacío (verificado en esta auditoría). Instrucción obsoleta. |
| `costo_real` es `GENERATED ALWAYS` (L151-153, L628) | En `newa` es `NEVER` + trigger NULL-safe; `GENERATED` es Main con 30.038 NULL | El `DROP EXPRESSION` es de Main (0b), no de `newa`. La premisa de v4 estaba medida sobre el proyecto equivocado. |
| "`fn_fdi_gasto` **no existe** … crear" (L149, L358) | "Ya existe en `newa`: se **extiende**, no se crea" | Crear otra habría duplicado. |
| `costos_adicionales_producto.sql` "aplicar **adaptado**" (L631-633) | DDL **extraído de `newa`**, no del script | Adaptar un script viejo reintroduce la deriva; el esquema vivo manda. |
| `precio_promedio`: "verificar cuál está viva y arreglar **la viva**" (L654-656) | `_v2` pondera bien; `_v3` es código muerto y se borra | La verificación ya está hecha: no hay defecto, solo código muerto. |
| "Bloqueada por: nada", "la fase 0 puede arrancar ya" (L388, L444, L625, L696, L889) | Bloqueante runtime: el cliente llama a `fn_fdi_registrar_recepcion` y no existe en ninguna base | La v4 no vio `multimoneda`; arrancar "ya" fallaba en el primer E2E de recepción. |
| X5 "cubierto, salvo `ventiq_app`" (L855) | "**no aplica**" | Consecuencia de la corrección de `precio_promedio`. |
| Fase 9: "el monto pendiente cuadra con `total_financiado − pagado`" (L822-823) | "el monto pendiente cuadra" | La fórmula de v4 se contradecía con "el pendiente es de mercancía, no de dinero" (L566). Quitarla es corrección. |
| `lib/sql/compra/`, `inventory_service.dart:1394-1402` (L245, L651) | `ventiq_admin_app/lib/sql/`, `1409-1414` | Rutas y líneas reales. |

## 4 · Donde la v6 queda peor que la v4

1. **FEFO sin dueño.** v4 avisaba que `fn_registrar_cambio_estado_operacion_mejorado` "hoy completa sin
   lote y rompe FEFO en toda recepción externa" (L525-526). v6 prohíbe deprecarla, pero a la vez afirma
   "R9 cubierto con el camino único con lote" (L560) y "el lote sobrevive" (L471) **sin decir por dónde
   entra el lote** si el botón sigue usando esa función. Es la única contradicción real: hay que nombrar
   la RPC que usa "Completar" o cómo se propaga `id_lote` en el camino que se conserva (A26).
2. **Fase 8 sin puerta.** Es la única fase sin Exit criteria; el E2E integral (A3) era la aceptación del
   proyecto completo y ahora no está en ninguna parte.

## 5 · Acciones de recuperación

1. **Fase 5 · Build**: reinsertar el bullet `p_origen text DEFAULT 'externa'` con la nota de
   compatibilidad (`ventiq_app`, transferencias, egresos) y "`origen` se deriva de `motivo`" (A1).
2. **Fase 0b · item 3**: "backfill `= precio_unitario − descuentos`" y "rollback que restaura la
   expresión" (A2).
3. **Fase 8**: devolver Exit criteria + el E2E final de 8 pasos; y en Reportes, la lista R2-R7 con la
   referencia `02-contabilidad.md §6.3` (A3).
4. **Arquitectura · "Tres cifras"**: añadir la inmutabilidad de `total_financiado` (A4).
5. **Fase 1 · Escala** y **Fase 6 · Reparto**: "redondeo en servidor, residuo a la línea de mayor base"
   (A6).
6. **Fase 6**: nuevo bullet "Ajustes `por_financiar`: reserva y pago propios, no mutan `total_financiado`,
   documento de ajuste de costo" (A7).
7. **Protocolo de entrega**: reinsertar el párrafo de E2E por fase, con el "sin OK del dueño no se abre
   la siguiente" (A8).
8. **Fase 5**: reinsertar los E2E numerados (100/60/25/15, 3 líneas, cuarta recepción) y
   `verify/05_forzar_fallo.sql` como criterio de atomicidad (A9).
9. **Fases 1 y 2**: grano (cuenta, medio, moneda) de la conciliación; "medio/moneda coherentes con la
   tienda"; índice parcial por `tipo` y las 3 RPCs; cordura contra la última tasa del mismo par e inversa
   desnormalizada; X9 "desde el histórico por fecha; el cliente no la provee" (A10-A14).
10. **Fase 3**: fórmula del trigger, `CHECK(costo_unitario >= 0)`, default `fondo`, `GRANT SELECT`,
    `_editar` solo en `creada`, permisos dueño/gerente y ruta `/compras` (A16-A18).
11. **Fases 5, 6 y 7**: "editables antes de confirmar, con historial", "pendiente > 0", selector
    multi-compra, desvío `Σ cargos` vs `Σ facturas`, y exclusividad/devolución del aporte (A19-A23).
12. **Bajas (A25-A34)**: una línea cada una en su sección; si se prefiere no tocar el cuerpo, anexar
    "Apéndice: textos operativos de la v4" al final de `PLAN.md` con el bloque completo.