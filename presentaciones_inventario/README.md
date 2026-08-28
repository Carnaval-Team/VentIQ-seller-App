# Presentaciones de inventario - SQL

SQL de la implementacion de `docs/PLAN_PRESENTACIONES_INVENTARIO.md`.
Se aplica MANUALMENTE en el SQL Editor del dashboard de Supabase
(proyecto `vsieeihstajlrdvpuooh`), en el orden numerico de los archivos.

Todos los archivos que modifican algo son idempotentes: se pueden correr mas de
una vez sin romper nada.

## Orden de aplicacion

| # | Archivo | Fase | Modifica | Que hace |
|---|---------|------|----------|----------|
| 01 | `01_schema_conversion.sql` | 0 | si (solo agrega) | Tabla `app_dat_conversion_presentacion` + columna `app_dat_inventario_productos.id_conversion`. No toca ningun saldo. |
| 02 | `02_helpers_lectura_mixta.sql` | 0 | si (solo agrega) | Helpers de LECTURA: cadena de presentaciones, saldos por presentacion, equivalente base, texto "4 Cajas + 4 Unidades", validador de `id_presentacion`. |
| 03 | `03_rebalanceo.sql` | 0 | si (solo agrega) | Abrir / empaquetar en cadena + descuento con rebalanceo + ingreso sin conversion. |
| 04 | `04_guardas_triggers.sql` | 0 | **si (reemplaza 2 funciones vivas)** | Guardas en `fn_sincronizar_stock_producto` y `fn_notificar_producto_disponible`. **Aplicar antes de usar el 03 en produccion.** |
| 05 | `05_tests_fase0.sql` | 0 | no (BEGIN/ROLLBACK) | Los 5 tests del plan + 4 extras. Crea productos de prueba y los deshace. |
| 06 | `06_recepcion_sin_conversion.sql` | 1 | **si (reemplaza `fn_registrar_recepcion_con_inventario`)** | Valida `id_presentacion`, deja de recalcular el saldo a base y delega en `fn_ingresar_presentacion`. Arregla el empate de varias lineas de la misma presentacion en una recepcion. |
| 07 | `07_egresos_con_rebalanceo.sql` | 1 | **si (reemplaza `fn_crear_extraccion_con_movimiento` y `fn_transferir_inventario_entre_layouts`)** | La extraccion descuenta con rebalanceo en vez de restar a ciegas (ya no deja saldos negativos); la transferencia deja de aplanar a base, asi que 2 cajas mueven 2 cajas. |
| 08 | `08_ajuste_por_presentacion.sql` | 1 | **si (reemplaza `fn_insertar_ajuste_inventario2`)** | Lee el saldo previo real en vez de creerle al cliente y anota el desfase. `fn_admin_caja_ajuste_inventario_offline` hereda el arreglo sin tocarla. |
| 09 | `09_tests_fase1.sql` | 1 | no (BEGIN/ROLLBACK) | Tres bloques independientes: A recepcion, B egresos, C ajuste. |
| 10 | `10_preview_rebalanceo.sql` | 4 (habilita) | si (solo agrega, SOLO LECTURA) | `fn_fmt_cantidad` + `fn_preview_rebalanceo`: simula la conversion sin escribir y devuelve el `mensaje_usuario` del dialogo de confirmacion del TPV. |
| 11 | `11_indices_presentacion.sql` | 2 (prerequisito) | si (6 indices nuevos, `CONCURRENTLY`) | Indices por `id_presentacion` en las 4 tablas de movimientos + 2 en conversiones. Sin ellos `fn_presentacion_tiene_movimientos` tarda ~120 ms (4 Seq Scan sobre 720.000 filas); con ellos 0,3 ms. **Ejecutar cada CREATE INDEX por separado**: `CONCURRENTLY` no corre dentro de transaccion. |
| 12 | `12_congelar_factor_presentacion.sql` | 2 (prerequisito) | si (agrega 1 trigger a `app_dat_producto_presentacion`) | Impide cambiar `cantidad` / `es_base` / `id_presentacion` / `id_producto` y borrar la fila cuando ya hay movimientos. **Depende del 10 y del 11.** |
| 13 | `13_tests_congelar_factor.sql` | 2 | no (BEGIN/ROLLBACK) | Tests del 12: 12 bloques (A lo que debe fallar, B lo que debe seguir, C el escape, D estado). |
| 14 | `14_presentaciones_editable.sql` | 2 (UI) | si (solo agrega, SOLO LECTURA) | `fn_presentaciones_producto_editable`: la cadena del producto con `factor_editable`, `puede_borrarse` y `motivo_bloqueo` ya resueltos. Una llamada por producto en vez de N. Valida acceso a la tienda. |
| 15 | `15_presentacion_item_json.sql` | 2/3 | si (solo agrega, SOLO LECTURA) | `fn_presentacion_item_json(id_presentacion, cantidad)`: nombre, factor, **`factor_rel`** y texto formateado de una linea. El `factor_rel` es imprescindible: el producto 4445 tiene factor 30 y `factor_rel` 1, y sumar con el factor crudo inflaba x30. |
| 16 | `16_operaciones_con_presentacion.sql` | 3 | **si (reemplaza `fn_listar_operaciones_inventario_new`)** | Las listas de operaciones muestran la presentacion por linea. Merge **aditivo** al `jsonb`: las claves viejas (`importe`, `cantidad`, `sku_producto`, `precio_unitario`) siguen ahi para la app en produccion. |
| 17 | `17_kardex_con_presentacion.sql` | 3 | si (agrega **`get_product_movements_v4`**, la v3 queda intacta) | Kardex con `id_presentacion`, `presentacion_nombre`, `presentacion_factor`, `cantidad_formateada` y `es_conversion`. **Funcion nueva** porque cambiar el `RETURNS TABLE` de la v3 da 42P13 y rompe la app vieja. Ademas la conversion pasa a ser un tipo de movimiento propio (antes se mostraba como «Reajuste de cancelacion»). |
| 18 | `18_lecturas_stock_presentacion.sql` | 3 | **si (reemplaza `fn_inventario_resumen_por_usuario_almacen2`)** + alias nuevo | Corrige **2 bugs** del resumen: el factor de la base no es 1 (producto 4380: 16 se reportaban como 480) y el JOIN por `id_producto` multiplicaba filas (producto 9635 con 3 filas `es_base`: 15 donde hay 5). Añade el alias `fn_stock_mixto_almacen`. |
| 19 | `19_valoracion_costo_presentacion.sql` | 3 | **si (reemplaza `fn_inventory_valuation_rows`)** | Corrige el bug mas caro: el JOIN de costo comparaba `pp.id_presentacion` (FK al nomenclador, 1..20) contra `pp.id` (id de fila, miles) → **0 de 6.647** coincidencias y todo caia a un fallback arbitrario. **5.861 filas (88 %) mal valoradas.** Aplica a las 3 funciones de la pantalla de valoracion. |
| 20 | `20_costo_promedio_en_base.sql` | 3 | **si (reemplaza `fn_actualizar_precio_promedio_recepcion_v2`)** | La RPC **fallaba en el 100 % de las llamadas** (`column reference "cantidad" is ambiguous`) y el `EXCEPTION WHEN OTHERS` lo tapaba. Ahora pondera en unidades base y escribe solo en la presentacion base. La guarda de no-op necesita `::real`: `precio_promedio` es float4 y comparar contra `numeric` nunca filtraba. |
| 21 | `21_ipv_con_presentacion.sql` | 3 | si (agrega **`obtener_ipv2`**, `obtener_ipv` intacta) | `obtener_ipv` ya agrupaba por presentacion, pero solo la usaba para pegar el nombre entre parentesis. La v2 expone `id_presentacion`, `presentacion_nombre`, `presentacion_factor`, `cantidad_final_formateada` y `equivalente_base`. Funcion nueva por el mismo motivo que el 17. |
| 22 | `22_venta_saldo_por_presentacion.sql` | 4 | **si (reemplaza `fn_registrar_venta` y `fn_registrar_venta_mesa`)** | Leian el saldo anterior con el patron prohibido («ultimo movimiento del producto», sin filtro de presentacion) y lo escribian en una fila marcada con OTRA presentacion. Vender 1 Bulto con 100 Bolsas habria escrito **99 Bultos = 990 Bolsas**. Incluye el `COALESCE` escalar para no dejar de descontar en la primera venta de una presentacion. |
| 23 | `23_compatibilidad_es_base.sql` | 4 (compatibilidad) | **si (reemplaza `fn_trg_congelar_factor_presentacion` + recrea el trigger)** | Saca `es_base` del guard del 12. Bloquearlo rompia los 3 metodos de `presentation_service.dart` y el **23001 que el usuario vio en produccion**: `es_base` es un puntero reversible, no un dato irreversible como el factor. Apagar la marca es no-op en 8.781 de 8.792 productos. |
| 24 | `24_bom_cantidad_en_base.sql` | 4 | si (agrega `fn_cantidad_en_base` + **reemplaza las 2 funciones de venta**) | Cierra el riesgo que ABRE la Fase 4: ahora que la cantidad viaja en la presentacion, el BOM y las porciones la interpretaban como unidades base. Vender 1 Caja de 24 croquetas descontaba la receta de **1**. Afectaba a 3 productos elaborados reales (219, 220, 9925). |
| 25 | `25_venta_con_rebalanceo.sql` | 4 | **si (reemplaza las 2 funciones de venta)** | La venta abre y arma empaques: vender 1 Bulto con solo Bolsas empaqueta solo. Lleva la guarda `v_n_pres > 1` **por compatibilidad**: el rebalanceo valida stock y la venta hoy no lo hace, asi que en los 8.699 productos de una sola presentacion se salta y nada cambia. |
| 26 | `26_inventario_detallado_fanout.sql` | 3 | si (la funcion **no la llama nadie**: 0 consumidores en SQL y en Dart) | Auditoria de `fn_inventario_detallado_optimizado`. Los 4 CTE de movimientos ya agrupaban bien por presentacion, pero: (a) `stock_reservado` NO lo hacia y el reservado se contaba **dos veces** (15.460,30 real -> 30.920,60 en 3 combinaciones); (b) el `LEFT JOIN` a `app_dat_precio_venta` casaba con **todas** las filas activas y multiplicaba el inventario — el producto 217 devolvia **18 filas donde hay 3**. El fan-out del precio no es un bug de presentaciones: **2.198 productos tienen mas de una fila de precio activa** y 1.040 con precios distintos. Las funciones vivas no lo sufren porque desempatan con `DISTINCT ON`/`LATERAL`. |
| 27 | `27_stock_almacen_en_base.sql` | 3 | si (los tests de signo no cambian; **6.659 de 6.661 combos devuelven lo mismo**) | `fn_stock_producto_almacen` devolvia `SUM(cantidad_final)` **sin factor**: con 533 Cajas de 24 decia 533, no 12.792. Sus consumidores lo comparan contra cantidades de receta en unidades base, asi que **subestimaba el stock por el factor** y podia rechazar una produccion que si alcanzaba. La usan **13 funciones** de cocina. **El detalle NO se toca**: `fn_descontar_ingredientes_elaborado` lo usa para ESCRIBIR el ledger, aplicarle el factor guardaria saldos falsos. |

## Estado

- [x] 01–04 aplicados en Supabase y verificados en produccion
- [x] 05 ejecutado contra las funciones ya aplicadas: los 9 tests pasan
- [x] 06–08 escritos, validados, ensayados y **aplicados**
- [x] 09 ejecutado: los tres bloques verdes
- [x] **10 aplicado** (`fn_preview_rebalanceo` + `fn_fmt_cantidad`), verificado contra el producto 217
- [x] **11 aplicado** (los 6 indices, VALIDOS y verificados con EXPLAIN)
- [x] **12 aplicado** y ensayado: los 12 bloques del 13 pasan
- [x] 13 escrito y ejecutado
- [x] **14 aplicado** y verificado contra la funcion viva (4 pruebas, incluido el aislamiento entre tiendas)
- [x] **15 aplicado** (ampliado despues con `factor_rel`)
- [x] **16 aplicado** y probado con datos reales (recepcion 154048, ventas 154050 y 153946)
- [x] **17 aplicado** — no-regresion v3 vs v4 fila por fila: **26/26 identicas**, la v4 solo añade columnas
- [x] **18 aplicado** — verificado: producto 4380 → 16/16, producto 9635 → 5/5; sobre las 270 filas de la tienda 174 cambian exactamente 2 valores
- [x] **19 aplicado** — no-regresion en 7 tiendas: **1.056 filas antes = 1.056 despues**, cambian solo las 6 filas previstas
- [x] **20 aplicado** — huella md5 de los 8.331 costos **identica antes y despues** (no toca ningun precio existente, solo la formula futura). Ensayado el caso mixto: 10 Bolsas a 12 + 2 Bultos a 100 → 10,6667 en la fila base
- [x] **21 aplicado** — no-regresion sobre **1.189 filas** en 4 tiendas: 0 diferencias en cantidades, costos, ventas y valor
- [x] **22 aplicado** — no-regresion sobre 200 productos de una sola presentacion: 0 discrepancias
- [x] **23 aplicado** — los 7 casos ensayados con ROLLBACK: pasa `es_base`, sigue rechazando factor / borrado / `id_presentacion` / el UPDATE combinado
- [x] **24 aplicado** — `fn_cantidad_en_base` verificada en los 6 casos borde; **8.785 presentaciones base** devuelven la cantidad sin cambio (compatibilidad exacta con la app vieja)
- [x] **27 APLICADO** y verificado: escalar con `factor_rel` (2 marcas), **detalle sin factor (0)**, firma/ACL/sobrecargas intactas. **6.659 combos con factor 1 → 0 diferencias**; solo cambian los 2 con factor ≠ 1 (4545 → 12.792 y 4558 → 360, tienda 25 con cocina apagada y ninguno usado como ingrediente). Smoke en la tienda 223 (cocina activa): `fn_validar_ingredientes_elaborado` y `fn_disponibilidad_plato` siguen ejecutando. **Ojo al censo**: filtrar por «>1 presentación con saldo» da los combos equivocados — el bug se dispara con **cualquier** presentación no-base de factor ≠ 1, aunque sea la única con stock.
- [x] **26 APLICADO** y verificado: marcas `lateral_precio 1 / resuelve_base 2 / join_reservado 1 / fanout_viejo 0`, firma y `RETURNS TABLE` intactos. Producto 217: **18 filas -> 3**, reservado 383,30 correcto. Los 3 casos del censo cuadran (217/37 383,30; 3046/110 77; 9753/192 15.000). 0 combinaciones duplicadas en las tiendas 11, 45 y 47. **Ojo al `COALESCE(...,0)`**: el primer intento mapeaba el `id_presentacion` nulo a `0` y eso PERDIA el reservado en vez de duplicarlo (el `0` no casa con ninguna presentacion real) — el null es la presentacion **base**, se resuelve con `fn_presentaciones_producto`. Se deja a proposito el mismo patron en los otros 3 CTE: solo afecta a historico congelado (**0 nulos nuevos en los ultimos 4 meses**, 96 % de los 2.854 pendientes son de sep-oct 2025).
- [x] **25 APLICADO** y verificado: 1/3/3/1/1 de marcas en las dos funciones; los 6 casos del ensayo dan lo esperado; la cadena de 2 conversiones (Unidad→Blister→Caja) queda auditada con `id_conversion` 20 y 21. Lleva **dos** guardas de compatibilidad, no una: solo multipresentacion, y si no alcanza respeta `permite_vender_aun_sin_disponibilidad` (2 tiendas / 31 productos venden en negativo a proposito y siguen pudiendo).

### La venta SI validaba stock (correccion del analisis)

Durante el trabajo se creyo que `fn_registrar_venta` no validaba stock, porque el
INSERT resta sin comprobar. **Es falso.** La validacion vive en un CHECK:

```
CHECK (fn_validar_cantidad_final_inventario(id_producto, cantidad_final))
  -> constraint chk_cantidad_final_conditional
```

y esa funcion lee `app_dat_configuracion_tienda.permite_vender_aun_sin_disponibilidad`.
Los 5 saldos negativos vivos no son falta de validacion: son las 2 tiendas que
tienen la bandera encendida. De ahi salio la guarda 2 del `25`.

**El SQL de la Fase 2.0 esta completo y aplicado.** Lo que sigue es UI.

### El bug que el 12 introdujo en la app (y como se arreglo)

Aplicar el trigger rompio el guardado de productos, y no en un caso raro:
**7.454 de 8.779 productos** con presentaciones. `add_product_screen.dart` hacia

```dart
.update({'es_base': false}).eq('id_producto', productId);  // TODAS las filas
.update({'es_base': true, 'cantidad': ...})...             // y reafirma la base
```

Apagar `es_base` en la presentacion base es exactamente lo que el trigger
prohibe, y lo hacia **siempre**, aunque el usuario no hubiera tocado nada.
Reproducido contra produccion con el producto 217:

```
No se puede cambiar la marca de base (es_base: t -> f) de la presentacion
"Bolsa" (id 336) del producto 217: ya tiene movimientos...   [23001]
```

Arreglo: los UPDATE tienen que afectar **solo filas que cambian de valor de
verdad**. Postgres dispara el trigger por fila afectada, asi que con un `WHERE`
extra las filas sin cambio no se tocan y no hay rechazo.

```dart
// apagar es_base solo donde deja de serlo
.eq('es_base', true).neq('id_presentacion', nuevaBase)
// encenderlo solo si falta
.eq('id_presentacion', nuevaBase).eq('es_base', false)
// el factor, aparte y solo si cambia
.neq('cantidad', nuevaCantidad)
```

Verificado contra produccion: la secuencia nueva completa (base + adicionales)
guardando **sin cambios** pasa, `precio_promedio` sigue actualizandose, y un
cambio de factor **genuino** sigue rechazado con 23001.

La leccion general: **un trigger BEFORE UPDATE obliga a revisar todo write path
que reescriba columnas con su mismo valor.** Es un patron comun ("apago todo y
prendo lo que va") que funciona sin trigger y explota con uno.

### El timeout del 13, y por que aparecio el archivo 11

La primera corrida del 13 en el dashboard dio **timeout**. No era el trigger ni el
test: **ninguna** tabla de movimientos tenia indice por `id_presentacion`. Los dos
que existian sobre el ledger (`idx_inv_prod_combo`,
`idx_inventario_productos_optimized`) arrancan por `id_producto`, y Postgres no
puede saltar la primera columna de un btree.

Medido con EXPLAIN ANALYZE antes de arreglarlo: Seq Scan en las cuatro tablas,
~120 ms por llamada a `fn_presentacion_tiene_movimientos`. El bloque D2 la
llamaba una vez por fila: 8.891 × 120 ms ≈ **18 minutos**.

Dos arreglos, los dos aplicados:

1. **`11_indices_presentacion.sql`** — 6 indices parciales. La comprobacion
   completa pasa de ~120 ms a **0,293 ms**, con Index Only Scan y `Heap Fetches: 0`.
   Esto importa mas alla del test: la UI va a llamar a esa funcion cada vez que
   se abra la pantalla de edicion de un producto.
2. **D2 reescrito** sin llamar a la funcion: `UNION` de las 4 tablas + `LEFT JOIN`
   contra `app_dat_producto_presentacion`, una sola pasada. **320 ms**.

El timeout fue util: destapo una regresion de rendimiento que iba a pegar en
produccion por la UI, no solo en un test.

### Cifra corregida: 7.486 congeladas, no 7.434

El conteo por `UNION` dio **7.486 congeladas / 1.405 libres / 8.891 total**. La
version anterior (7.434 / 1.457) miraba **solo el ledger**; las 52 de diferencia
son presentaciones que aparecen en un detalle de recepcion, extraccion o control
pero todavia no en el ledger. El trigger las protege igual, y hace bien.

### Limite preexistente: 87 presentaciones imborrables por precio_costo

Una presentacion a la que alguien le puso precio ya no se puede borrar, aunque
nunca se haya movido: `trg_registrar_precio_costo` le inserta una fila en
`app_dat_precio_costo` y esa FK es NO ACTION. Reparto real:

- **7.486** con movimientos → las congela el trigger del 12
- **87** sin movimientos pero con `precio_costo` → imborrables por la FK
- **1.319** borrables de verdad

Es anterior a este trabajo y el 12 no lo introduce, pero la pantalla de edicion
de presentaciones (Fase 2) se va a topar con ese error.

### Sobre `esp_4cajas: "Sin stock"` en el `C0_setup` del 09

No es un fallo. Dentro de un mismo `SELECT`, Postgres no garantiza el orden de
evaluacion de las subconsultas, asi que `fn_stock_mixto_json` puede correr antes
que el `fn_ingresar_presentacion` de la misma fila. Que las 4 cajas si estaban se
ve en el bloque siguiente (`C1_estado` devuelve `4 Cajas + 5 Unidades`). Solo
afecta a esa linea del test.

### Trampa al verificar el 06 y el 07

`pg_get_functiondef(...) ILIKE '%ORDER BY created_at DESC%'` da **falso negativo**:
esos archivos documentan en comentarios el patron viejo que eliminan, y el ILIKE
encuentra el comentario. Hay que filtrar las lineas que empiezan con `--` antes de
buscar; las consultas de verificacion al final de cada archivo ya lo hacen.

## Resultado del ensayo (los 9 tests, contra datos reales)

Ejecutado con `BEGIN; ... ROLLBACK;` via MCP el 2026-08-26. Produccion quedo
intacta (verificado: tabla, columna y funciones no existen, 0 productos `ZZ TEST`,
0 filas con `origen_cambio = 20`).

| Test | Escenario | Esperado | Obtenido |
|------|-----------|----------|----------|
| T1 | entrar 4 cajas + 4 u (caja=12) | `4 Cajas + 4 Unidades`, equiv 52 | igual |
| T2 | vender 1 u con 4 cajas y 0 sueltas | `3 Cajas + 11 Unidades`, equiv 47 | igual, estrategia `abrir` |
| T3 | vender 1 caja con 0 cajas y 20 u | `8 Unidades`, equiv 8 | igual, estrategia `empaquetar` |
| T4 | vender 1 u con solo 1 pallet (120/12/1) | `9 Cajas + 11 Unidades`, equiv 119 | igual, **2 conversiones en cadena** (Bulto->Caja, Caja->Unidad) |
| T5 | pedir 200 u / 5 pallets sin stock | error, 0 saldos negativos | `INSUFFICIENT_STOCK_CONVERTIBLE`, 0 negativos |
| T6 | vender 2 cajas teniendo 9 | no abre nada | estrategia `ninguna`, 0 conversiones |
| T7 | trazabilidad de la conversion | 2 patas por conversion, neto 0 en equiv base | 4 conversiones, 2 patas cada una, neto 0.000000 en todas |
| T8 | producto de una sola presentacion | sin regresiones | `7 Unidades`, 0 conversiones, error correcto al pedir 100 |
| T9 | almacen 73 con 2 ubicaciones (3 u en la 75, 2 cajas en la 76), pedir 10 u | 3 de la 75 sin abrir + abrir 1 caja en la 76 | `1 Caja + 5 Unidades`, equiv 17, 2 movimientos |

El T4 es el que demuestra el requisito "no saltar niveles": para sacar 1 unidad
de un pallet se abre el pallet a cajas y luego UNA caja a unidades, dejando
9 cajas intactas. Se registran dos conversiones, no una.

## Validar antes de aplicar

```bash
# venv de un solo uso (el mismo que usa funcionalidad_cocina)
uv venv "$LOCALAPPDATA/Temp/vqsql" --python 3.11
uv pip install --python "$LOCALAPPDATA/Temp/vqsql/Scripts/python.exe" pglast

PY="$LOCALAPPDATA/Temp/vqsql/Scripts/python.exe"

# sintaxis SQL + cuerpo plpgsql de cada archivo
"$PY" presentaciones_inventario/_validar_sql.py
```

`_validar_sql.py` usa pglast (el parser real de Postgres). No comprueba que
tablas o columnas existan; eso sale al aplicar en el dashboard o al ensayar con
`BEGIN/ROLLBACK`.

## Decisiones tomadas contra el estado real de produccion

Todas verificadas por MCP antes de escribir el SQL.

**El factor es relativo a la base, no absoluto.** 131 filas `es_base` tienen
`cantidad <> 1` (ej. producto 7075 "Cerveza Coronita": Unidad con cantidad 24).
Por eso todo usa `factor_rel = pp.cantidad / cantidad_de_la_base`, no
`pp.cantidad` a secas. Multiplicar por `pp.cantidad` directamente es el bug que
tiene hoy `fn_inventario_resumen_*`.

**La base se resuelve con cascada defensiva.** 9 productos NO tienen ninguna fila
`es_base` y 1 tiene varias. El criterio es: primero `es_base` de menor id (igual
que `fn_producto_json_a_presentacion_base`), y si no hay, la presentacion de menor
factor.

**El contrato de `id_presentacion` ya se cumple en los datos.** Las 308.375 filas
de `app_dat_inventario_productos` apuntan a `app_dat_producto_presentacion.id`;
ninguna al catalogo `app_nom_presentacion`. `fn_validar_id_presentacion` lo
documenta y lo hace explicito, distinguiendo el error de mandar el id del catalogo.

**Se reutilizan codigos existentes, no se inventan.**
`app_nom_tipo_operacion.id = 20` ('Cambio de presentacion') ya existe con 0 usos y
su descripcion es literalmente para esto. `origen_cambio = 20` sigue la convencion
que ya usa el 24 (coincidir con el tipo de operacion). Los valores en uso hoy son
1..7 y un 24 suelto.

**Hace falta la columna `id_conversion`; `origen_cambio` no basta.** `obtener_ipv` y
`obtener_reporte_inventario_completo*` clasifican como AJUSTE toda fila con
`id_recepcion IS NULL AND id_extraccion IS NULL AND id_control IS NULL`. Sin marca
propia, abrir una caja entraria al IPV como "ajuste positivo de 12 unidades" +
"ajuste negativo de 1 caja".

**Hay tres triggers vivos sobre el ledger** (por eso existe el 04):
`trg_sincronizar_stock_inventario` publicaba `NEW.cantidad_final` crudo en
`carnavalapp."Productos"` — con 4 cajas de 24 publicaba "4" — y
`trg_notificar_producto_disponible` mandaria un push falso "ya esta disponible"
cada vez que se abra una caja (las unidades sueltas nacen en 0). El tercero,
`trg_notificar_producto_agotado`, es AFTER UPDATE y la Fase 0 solo hace INSERT,
asi que no se toca. Alcance del riesgo de marketplace: 1.235 productos
sincronizados con carnavalapp, de los cuales solo 2 tienen mas de una presentacion.

## Funciones nuevas (todas con GRANT a anon, authenticated, service_role)

Lectura (`02`):

- `fn_presentaciones_producto(p_id_producto)` - cadena ordenada mayor->menor con
  `factor_rel`, `factor_hijo` (abrir un escalon) y `factor_padre` (empaquetar).
- `fn_stock_saldos_presentacion(p_id_producto, p_id_almacen, p_id_ubicacion, p_incluir_cero)`
  - saldo vigente por presentacion + su equivalente base.
- `fn_equivalente_base(...)` - total en unidades base. Solo para dinero y rotacion,
  nunca como "cantidad de almacen".
- `fn_plural_presentacion(nombre, cantidad)` - pluralizacion cosmetica en espanol.
- `fn_formatear_stock_mixto(jsonb, abreviar, vacio)` - `"4 Cajas + 4 Unidades"`.
  PURA (no consulta la base) para que el helper Dart de la Fase 2 la replique
  identica y funcione offline.
- `fn_stock_mixto_json(...)` - el payload unico que consumen las apps.
- `fn_validar_id_presentacion(producto, presentacion)` - cierra la confusion de IDs.

Escritura (`03`):

- `fn_registrar_conversion_presentacion(...)` - una conversion: cabecera + 2 patas
  del ledger con `origen_cambio = 20`.
- `fn_rebalancear_presentaciones(...)` - abre o empaqueta en cadena hasta cubrir la
  cantidad pedida. No descuenta.
- `fn_descontar_con_rebalanceo(...)` - **la unica ruta de egreso valida**. Filtra
  SIEMPRE por ubicacion y presentacion.
- `fn_descontar_con_rebalanceo_almacen(...)` - la anterior recorriendo las
  ubicaciones de un almacen: primero las que tienen saldo propio, luego las que
  solo tienen convertible.
- `fn_ingresar_presentacion(...)` - entrada en la presentacion tal cual, sin
  convertir a base. Una llamada por linea.

Preview para el dialogo del TPV (`10`, SOLO LECTURA):

- `fn_fmt_cantidad(cantidad)` - `1` -> `"1"`, `12.000` -> `"12"`, `1.5` -> `"1.5"`.
  Sin el punto colgante que deja `to_char` con `FM`.
- `fn_preview_rebalanceo(producto, ubicacion, presentacion, cantidad, ...)` -
  simula `fn_rebalancear_presentaciones` **sin escribir nada** y devuelve
  `necesita_conversion`, `estrategia`, `conversiones`, `sobrante_tras_consumo`,
  `maximo_convertible` y un `mensaje_usuario` listo para mostrar:
  `"Faltan 1 Unidad. ¿Abrir 1 Caja? Quedarán 11 Unidades."`.
  Cuando el saldo propio alcanza, `necesita_conversion` es `false` y
  `mensaje_usuario` es `NULL`: **la UI no debe preguntar nada.**

  No reserva stock. Entre la preview y la venta otra caja puede mover el saldo,
  asi que la escritura real vuelve a calcular y puede fallar aunque la preview
  dijera que si. Es una cortesia para el cajero, no una garantia transaccional.

Congelado del factor (`12`):

- `fn_presentacion_tiene_movimientos(id)` - true si esa fila ya aparece en el
  ledger, en un detalle de recepcion/extraccion/control o en una conversion.
  **La UI la necesita** para poner el campo del factor en readOnly antes de que
  el usuario escriba, en vez de dejarlo escribir y despues mostrarle el error.
  Depende de los indices del `11`: sin ellos son 4 Seq Scan (~120 ms), con ellos
  0,3 ms.
- `fn_trg_congelar_factor_presentacion()` + trigger
  `trg_congelar_factor_presentacion` BEFORE UPDATE OF (cantidad,
  id_presentacion, es_base, id_producto) OR DELETE.

  Por que hace falta: el factor NO se copia al ledger, se interpreta al leer
  (`factor_rel = pp.cantidad / cantidad_de_la_base`). El ledger guarda "4" en la
  fila de Caja; que eso valga 48 unidades o 96 lo decide `pp.cantidad` HOY. Asi
  que cambiar el 12 por un 24 en una Caja con historia no corrige un dato:
  reescribe el pasado. El IPV y la valoracion de meses cerrados cambian solos y
  sin traza. NetSuite y SAP B1 lo prohiben por lo mismo.

  Medido en produccion: **7.486 de 8.891 filas ya tienen movimientos (84 %)**, y
  antes del `12` nada lo impedia — el unico trigger de la tabla mira
  `precio_promedio`.

  Rechaza con **SQLSTATE 23001** y un mensaje que explica el motivo. Ese es el
  codigo que tiene que mirar la app.

  `precio_promedio` no se bloquea nunca (cambia en cada recepcion), ni el INSERT,
  ni nada sobre las filas sin historia. Salida de emergencia para un error de
  carga real:

  ```sql
  BEGIN;
  SET LOCAL ventiq.permitir_cambio_factor = 'on';
  UPDATE app_dat_producto_presentacion SET cantidad = 24 WHERE id = 11053;
  COMMIT;
  ```

  `SET LOCAL` muere con la transaccion. Es deliberado que sea incomodo.

## Que NO hace la Fase 0

No cambia ninguna funcion de venta, recepcion, extraccion, transferencia, IPV ni
reporte. No migra saldos historicos. No toca las UM de recetas. Los saldos
existentes siguen exactamente donde estan (306.814 de 308.371 filas estan en
presentacion base, y ahi se quedan).

Esas sustituciones son las Fases 1 a 5.
