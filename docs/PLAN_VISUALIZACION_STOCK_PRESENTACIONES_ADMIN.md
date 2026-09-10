# Plan: visualización de stock por presentación en `ventiq_admin_app`

## Estado de ejecución (auditoría 2026-09-09)

Verificado con `dart analyze lib` (0 errores/avisos), `flutter test` (32 tests OK),
PostgREST en producción y llamada real de la app:

- **Fases 0, 2, 3 y 4: implementadas y verificadas.** Modelo tipado
  (`lib/models/stock_mixto.dart`), Inventario → Stock y ficha de producto
  consumen stock mixto, sección «Presentaciones y factores de empaque» con la
  cadena canónica.
- **Fase 1: aplicada en producción pero con un bug corregido localmente.**
  La v3 y `fn_stock_mixto_producto_por_ubicacion` existen y rechazan `anon`
  (42501). La llamada real de la app a la v3 devolvía
  `42P01: relation "app_dat_vendedor" does not exist`: la v2 envuelta resuelve
  relaciones sin calificar y heredaba el `search_path = ''` de la v3.
  **Corregido en `presentaciones_inventario/31_inventario_resumen_stock_mixto_v3.sql`**
  (restaura `search_path` a `public, pg_catalog` antes de invocar la v2;
  `proconfig` lo restaura al salir). **Pendiente: aplicar el 31 actualizado en el
  dashboard de Supabase** y revalidar la llamada de la app.
- **Fase 5 (breakdown logístico por presentación): pendiente.** `StockBreakdown`
  sigue mostrando los 3 agregados como estado logístico separado, que es la fase
  mínima aceptada; el desglose dimensional no se creó.
- **Fase 6:** `dart analyze lib` y tests dirigidos sin errores; smoke visual y
  capturas pendientes.

`fn_stock_mixto_json(11001, NULL, 349)` verificado en producción:
`49 Cajas + 2.8 Bultos` / corto `49 CAJ + 2.8 BLT` / equivalente `1190`.

## Objetivo

Corregir las pantallas de inventario y detalle de producto para que el stock físico nunca
se represente como la suma aritmética de cantidades de presentaciones distintas.

Ejemplo obligatorio:

- Stock físico: **49 Cajas + 2.8 Bultos**.
- Equivalente comparable: **1.190 Unidades base**.
- Valor que no debe mostrarse como total: **51.8** (`49 + 2.8`).

El plan cubre:

1. listado y diálogo del tab **Inventario → Stock**;
2. vista detallada por fila de inventario;
3. sección **Ubicaciones y Stock** de la ficha del producto;
4. significado de **Presentaciones (N)** y **Equivalencia de cantidades**;
5. contratos SQL/RPC, modelos Dart, pruebas y despliegue compatible.

No cambia cómo se escribe el ledger ni las reglas de rebalanceo ya implementadas en
`PLAN_PRESENTACIONES_INVENTARIO.md`.

---

## Diagnóstico confirmado

### Caso real que explica el `51.8`

Verificado en Supabase el 2026-09-09:

| Dato | Valor |
|---|---|
| Producto | `11001` — `prod azucar multiipresentacion` |
| Tienda | `223` |
| Almacén | `331` |
| Ubicación | `349` — `refrigerada` |
| Presentaciones configuradas | 4: Caja, Bulto, Unidad y Gramo |
| Presentaciones con saldo | 2 |
| Caja | 49 × factor relativo 24 = 1.176 base |
| Bulto | 2.8 × factor relativo 5 = 14 base |
| Unidad | 0 × factor relativo 1 = 0 base |
| Total físico correcto | `49 Cajas + 2.8 Bultos` |
| Equivalente base correcto | `1.190` |
| Suma cruda incorrecta | `51.8` |

`fn_stock_mixto_json(11001, NULL, 349)` ya devuelve exactamente:

```text
texto:             49 Cajas + 2.8 Bultos
texto_corto:       49 CAJ + 2.8 BLT
equivalente_base:  1190
```

Esto prueba que el `51.8` observado no es un redondeo ni una conversión válida: es la suma
de dos magnitudes con unidades distintas.

### Dónde se pierde hoy la dimensión presentación

#### Inventario → Stock

Flujo real:

```text
InventoryScreen
  → InventoryStockScreen
  → InventorySummaryList / InventorySummaryCard
  → _showInventorySummaryDetails
```

El resumen recibe:

- `cant_almacen_total`;
- `cant_unidades_base`;
- `presentaciones_count`.

No recibe la colección de saldos por presentación. Por eso sabe mostrar «4
presentaciones», pero no cuánto hay de cada una. El diálogo vuelve a usar el total físico
heterogéneo e incluso lo etiqueta como `unidades`.

La vista detallada posterior sí conserva una fila por ubicación, variante, opción y
presentación, pero los desgloses auxiliares se indexan solo por producto+ubicación. Dos
presentaciones en la misma ubicación pueden recibir el mismo total agregado.

#### Ficha del producto

`ProductService.getProductStockLocations` recibe filas que originalmente incluyen
`id_presentacion`, variante y opción. Después:

1. conserva temporalmente la combinación completa;
2. vuelve a agrupar solo por ubicación;
3. suma `cantidad_final` de las presentaciones;
4. descarta presentación, factor, variante y opción;
5. `ProductDetailScreen` suma nuevamente las ubicaciones.

Ese es el origen directo de `51.8` en **Ubicaciones y Stock**.

### Dos conceptos de catálogo que hoy parecen duplicados

#### Presentaciones (N)

Fuente: `app_dat_producto_presentacion`.

Es la configuración **operativa** usada por inventario y movimientos:

- vínculo producto-presentación;
- factor;
- presentación base;
- costo promedio de la base;
- cadena para abrir/empaquetar.

No es stock. El texto actual «Cantidad equivalente: N unds» es ambiguo y usa el factor
crudo sin explicar la base.

#### Equivalencia de cantidades

Fuente: `app_inf_presentacion_producto`.

Es una tabla **informativa antigua**, independiente del ledger y de los helpers actuales.
No mueve inventario ni alimenta `fn_stock_mixto_json`.

Medición en producción:

- 176 filas informativas en 174 productos;
- 172 no tienen una presentación operativa equivalente;
- de las 4 que sí casan, solo 1 coincide con `factor_rel`;
- 3 contradicen la configuración operativa (por ejemplo, `Unidad = 288`, mientras la
  presentación operativa Unidad tiene `factor_rel = 1`).

Por tanto, las dos secciones son tablas diferentes, pero semánticamente duplican la
idea de equivalencia y pueden contradecirse. Para la operación moderna, la fuente de
verdad debe ser `app_dat_producto_presentacion` mediante `fn_presentaciones_producto`.

---

## Decisiones de diseño

1. **El stock físico mixto es el valor principal.**
   Mostrar `49 Cajas + 2.8 Bultos`.
2. **El equivalente base es secundario y siempre va etiquetado.**
   Mostrar `Equivalente: 1.190 Unidades base`.
3. **Nunca se suma cantidad física entre presentaciones.**
   `49 + 2.8` no produce un total utilizable.
4. **`presentaciones_count` es un conteo, no un desglose.**
5. **Los umbrales globales usan equivalente base**, no la suma física.
6. **El detalle por ubicación conserva presentación.**
7. **La configuración de empaque no se presenta como inventario.**
8. **No se mantienen dos factores editables.** La sección informativa antigua se retira
   de la ficha o se convierte en notas sin valor numérico operativo.
9. **Compatibilidad:** no se modifica el contrato de una RPC que consume la app vieja.
   Si hace falta ampliar el resumen, se crea una función nueva con sufijo sucesivo.

---

## Contratos backend ya disponibles

### `fn_stock_saldos_presentacion`

Ya devuelve, por ubicación + variante + opción + presentación:

- `id_presentacion` operativo (`app_dat_producto_presentacion.id`);
- nombre;
- `factor_rel`;
- `es_base`;
- `nivel`;
- saldo físico;
- equivalente base.

Es suficiente para el detalle exacto y para construir respuestas batch.

### `fn_stock_mixto_json`

Ya devuelve:

- `desglose`;
- `texto`;
- `texto_corto`;
- `equivalente_base`;
- ámbito de almacén/ubicación.

Es suficiente para una ficha de producto o un diálogo individual.

### `fn_stock_mixto_almacen`

Alias para consultar el mixto de un producto en un almacén.

### `fn_presentaciones_producto`

Debe ser la única autoridad para:

- base efectiva;
- `factor_rel`;
- niveles de cadena;
- relaciones padre/hijo;
- nombre y SKU.

### RPC de resumen

`fn_inventario_resumen_por_usuario_almacen2` ya corrige el cálculo con `factor_rel`,
pero solo retorna escalares y `presentaciones_count`; no devuelve desglose JSON.

La app actual también contiene una llamada a
`fn_inventario_resumen_por_usuario_almacen` (sin `2`). En producción ambas funciones
existen y no son equivalentes: la primera no contiene `factor_rel`; la segunda sí. Antes
de implementar, cada llamador debe quedar inventariado y migrado al contrato nuevo sin
cambiar el contrato de la función antigua.

---

## Arquitectura propuesta

### A. Modelo Dart tipado

Reutilizar `StockMixto`, pero tipar el contenido de `desglose` en lugar de propagar
`List<Map<String, dynamic>>`:

```dart
class SaldoPresentacion {
  final int idPresentacion;
  final String nombre;
  final double cantidadFisica;
  final double factorRel;
  final double equivalenteBase;
  final bool esBase;
  final int? nivel;
}
```

Extender `StockMixto` con:

```dart
final List<SaldoPresentacion> desglose;
final String texto;
final String textoCorto;
final double equivalenteBase;
```

Estados de carga explícitos:

- cargando;
- cargado vacío;
- cargado con saldos;
- error.

Una falla de RPC no debe convertirse silenciosamente en «sin presentaciones» o «sin
stock».

### B. Resumen batch para Inventario → Stock

No llamar `fn_stock_mixto_json` una vez por tarjeta. Eso crearía N+1.

Crear una **RPC nueva** basada en la función corregida del resumen, por ejemplo:

```text
fn_inventario_resumen_por_usuario_almacen3
```

Debe conservar las columnas de la versión que adopte el cliente y añadir al final:

- `stock_desglose jsonb`;
- `stock_texto text`;
- `stock_texto_corto text`;
- `stock_equivalente_base numeric`;
- opcionalmente `nombre_presentacion_base text`.

Reglas:

1. construir el desglose desde los últimos saldos por clave completa;
2. agrupar cantidades únicamente dentro del mismo `id_presentacion`;
3. omitir saldos cero del texto;
4. ordenar por `nivel`;
5. calcular equivalente con `factor_rel`;
6. respetar filtros de tienda, almacén, variante y opción del resumen;
7. mantener paginación y `total_count`;
8. validar acceso a tienda igual que la versión corregida;
9. no modificar ni borrar las funciones anteriores.

Alternativa aceptable: RPC batch separada que reciba los IDs visibles. Se prefiere la
v3 del resumen porque evita una segunda ida y mantiene una foto coherente de la página.

### C. Detalle por ubicación

Para una sola ficha puede usarse `fn_stock_mixto_json(producto, NULL, ubicacion)`.
Para evitar N+1 al listar muchas ubicaciones, crear una RPC batch específica si el
producto puede estar en muchas zonas:

```text
fn_stock_mixto_producto_por_ubicacion(p_id_producto, p_id_almacen)
```

Una fila por ubicación con:

- almacén y ubicación;
- `desglose`;
- `texto` y `texto_corto`;
- equivalente base.

Si la UI permite seleccionar variante/opción, el contrato debe aceptar esos filtros o
retornar el desglose con esas dimensiones. El helper actual agrega variantes; no debe
presentarse como disponibilidad de una variante concreta.

### D. Pedidos y entregas

`StockBreakdown` hoy solo conserva tres números (`enAlmacen`, `enPedidos`,
`entregando`) y los RPC de breakdown no devuelven presentación. No sumar esos valores a
una fila de Caja o Unidad.

Fase mínima:

- mostrar el stock físico desde `StockMixto`;
- mostrar pedidos/entregas como estado logístico separado y claramente agregado;
- no calcular `enAlmacen = stock + enPedidos` si las dimensiones no están garantizadas.

Fase completa:

- crear versiones nuevas de los RPC de breakdown;
- agrupar por producto + ubicación + variante + opción + presentación;
- retornar cantidad física y equivalente base por estado.

---

## Cambios por superficie

### 1. `InventorySummaryCard`

Estado actual:

- muestra `cantidadTotalEnAlmacen` como cifra principal;
- usa ese escalar para color/estado;
- añade equivalente solo como complemento.

Cambio:

- valor principal: `stockTexto`;
- compacto en espacios reducidos: `stockTextoCorto`;
- segunda línea: equivalente base;
- estado de stock: evaluar `stockEquivalenteBase`;
- chip `N presentaciones`: se puede conservar como metadato, no como sustituto del
  desglose;
- si solo hay una presentación, seguir mostrando nombre y cantidad, no `unidades` en
  duro.

### 2. `_showInventorySummaryDetails`

Eliminar el texto:

```text
N unidades
```

cuando `N` proviene de `cant_almacen_total`.

Mostrar:

```text
Existencia física
49 Cajas + 2.8 Bultos
Equivalente: 1.190 Unidades base
```

Añadir una lista opcional por presentación:

```text
Caja       49       = 1.176 base
Bulto      2.8      =    14 base
Unidad      0       =     0 base  // solo en modo auditoría
```

En UI normal se omiten las presentaciones en cero.

### 3. Vista detallada de inventario

La fila ya conserva presentación y debe seguir haciéndolo. Corregir las claves de
breakdown para no aplicar un total producto+ubicación a cada presentación.

Clave lógica mínima:

```text
producto|ubicación|variante|opción|presentación
```

No basta cambiar la clave Dart si el RPC sigue agregado; ambos contratos deben alinearse.

### 4. `ProductDetailScreen` — Ubicaciones y Stock

Dejar de usar la `cantidad` agregada por `ProductService.getProductStockLocations` como
inventario mostrado.

Resumen global:

```text
Existencia física
49 Cajas + 2.8 Bultos
Equivalente: 1.190 Unidades base
```

Por ubicación:

```text
Refrigerada
49 Cajas + 2.8 Bultos
Equivalente: 1.190 Unidades base
```

Cambios del servicio:

- no descartar `id_presentacion`;
- no sumar cantidades físicas por ubicación;
- devolver DTO tipado por ubicación con `StockMixto`;
- separar reservado/pedidos/entregas hasta que compartan dimensión;
- usar `StockMixtoFormatter.cantidad` para decimales (`2.8`, no `3` ni `2.80`).

### 5. Sección de Presentaciones

Renombrar a **Presentaciones y factores de empaque**.

Usar la cadena de `fn_presentaciones_producto`, no el map dinámico crudo, y mostrar:

```text
Caja
1 Caja = 24 Unidades base

Bulto
1 Bulto = 5 Unidades base

Unidad
Presentación base

Gramo
1 Gramo = 0.0023 Unidades base · Fraccionable
```

Para cadenas de más de dos niveles puede añadirse la relación inmediata:

```text
1 Caja = 4.8 Bultos = 24 Unidades base
```

No llamar a esto «stock» ni «cantidad disponible».

### 6. Equivalencia de cantidades

Decisión recomendada:

- retirar el editor numérico de `app_inf_presentacion_producto` de la ficha moderna;
- no borrar la tabla ni los datos en esta fase;
- si `observaciones` aporta valor, mostrarla como **Notas sobre presentaciones**;
- incluir una leyenda temporal si se conserva la sección:
  «Información histórica; no modifica inventario, factores, precios ni costos».

Antes de eliminar definitivamente la tabla, auditar sus llamadores fuera de esta ficha.
Las 172 filas sin presentación operativa pueden ser datos de un módulo antiguo y no deben
migrarse automáticamente a `app_dat_producto_presentacion`.

### 7. Selección de presentación base

Retirar heurísticas por texto (`base`, `unidad`, `individual`) y consultas con
`limit(1)` sin orden. Usar siempre:

1. `fn_presentaciones_producto`;
2. `PresentacionCadena.esBase`;
3. el orden defensivo que devuelve SQL.

---

## Archivos principales previstos

### Dart

- `ventiq_admin_app/lib/screens/inventory_stock_screen.dart`
  - diálogo del resumen;
  - vista detallada;
  - claves de breakdown.
- `ventiq_admin_app/lib/widgets/inventory_summary_card.dart`
  - texto mixto principal;
  - equivalente base y estado.
- `ventiq_admin_app/lib/models/inventory.dart`
  - modelo del resumen y DTO del desglose;
  - parser por nombre, no índices posicionales nuevos.
- `ventiq_admin_app/lib/services/inventory_service.dart`
  - consumir RPC nueva;
  - corregir breakdowns y errores.
- `ventiq_admin_app/lib/screens/product_detail_screen.dart`
  - existencia global y por ubicación;
  - consolidar secciones de catálogo.
- `ventiq_admin_app/lib/services/product_service.dart`
  - reemplazar agregado crudo por DTO de stock mixto;
  - auditar llamadores de equivalencia informativa.
- `ventiq_admin_app/lib/services/presentacion_cadena_service.dart`
  - tipar el desglose;
  - diferenciar vacío real de error.
- `ventiq_admin_app/lib/utils/stock_mixto_formatter.dart`
  - reutilizar sin duplicar reglas.
- `ventiq_admin_app/lib/widgets/product_quantity_dialog.dart`
  - retirar heurística de base por nombre si sigue activa.

### SQL

Crear archivos nuevos en `presentaciones_inventario/`, siguiendo el patrón imperativo
del proyecto y sin reemplazar RPC consumidas por binarios viejos:

- resumen v3 con `stock_desglose` y textos;
- opcional: stock mixto batch por ubicación;
- opcional: breakdown logístico v2 por presentación.

Actualizar después:

- `presentaciones_inventario/README.md`;
- `docs/PLAN_PRESENTACIONES_INVENTARIO.md`;
- `docs/TUTORIAL_PRUEBAS_PRESENTACIONES.md`.

No aplicar SQL remoto durante la implementación hasta revisar y aprobar la migración.

---

## Seguridad Supabase que debe cerrarse junto al cambio

La auditoría fue de solo lectura y encontró:

- `fn_stock_saldos_presentacion`, `fn_stock_mixto_json` y otras funciones tienen
  `search_path` mutable;
- las RPC de lectura son ejecutables por `anon`/`PUBLIC`;
- `fn_inventario_resumen_por_usuario_almacen2` es `SECURITY DEFINER`, no fija
  `search_path` y es ejecutable por `anon` y `authenticated`;
- las tablas base de producto e inventario tienen exposición amplia y varias no tienen
  RLS habilitado.

Esto no impide elaborar la UI, pero una RPC nueva no debe copiar esas debilidades.

Requisitos para la RPC nueva:

1. preferir `SECURITY INVOKER` si los permisos lo permiten;
2. si realmente necesita `SECURITY DEFINER`, fijar `search_path` seguro, calificar
   relaciones y validar `auth.uid()` + acceso a tienda/almacén;
3. revocar `EXECUTE` de `PUBLIC` y `anon` salvo necesidad demostrada;
4. conceder solo a `authenticated`;
5. ejecutar advisors después de crearla;
6. tratar el endurecimiento global de RLS/permisos como migración de seguridad separada,
   porque puede afectar aplicaciones viejas.

---

## Fases de implementación

### Fase 0 — Contrato y tests puros

- [ ] Crear `SaldoPresentacion` tipado.
- [ ] Endurecer `StockMixto.fromJson` para aceptar mapas dinámicos de PostgREST.
- [ ] Separar error, vacío y configuración ausente.
- [ ] Añadir pruebas del parser y formatter.
- [ ] Prohibir por test que `49 + 2.8` se muestre como total.

### Fase 1 — RPC batch del resumen

- [ ] Crear la versión nueva sin tocar la RPC anterior.
- [ ] Añadir desglose, texto y equivalente.
- [ ] Validar filtros, paginación, variante y opción.
- [ ] Probar contra el producto 11001.
- [ ] Comparar filas y escalares heredados con la función anterior adecuada.
- [ ] Revisar plan de ejecución y evitar llamadas laterales por cada fila si resultan
  costosas.
- [ ] Ejecutar advisors de seguridad y rendimiento.

### Fase 2 — Inventario → Stock

- [ ] Migrar `InventoryService` y `InventorySummaryByUser`.
- [ ] Mostrar mixto en tarjetas.
- [ ] Mostrar mixto en diálogo.
- [ ] Usar equivalente para umbrales.
- [ ] Mantener conteo de presentaciones como metadato.
- [ ] Corregir claves de la vista detallada.

### Fase 3 — Ficha del producto

- [ ] Sustituir `getProductStockLocations` agregado por stock mixto tipado.
- [ ] Mostrar total global correcto.
- [ ] Mostrar desglose por ubicación.
- [ ] Separar estados logísticos.
- [ ] Unificar formato decimal.

### Fase 4 — Catálogo de presentaciones

- [ ] Renombrar y rehacer la sección de Presentaciones con la cadena canónica.
- [ ] Retirar el factor informativo duplicado de la experiencia principal.
- [ ] Auditar llamadores de `app_inf_presentacion_producto`.
- [ ] Conservar notas históricas solo si tienen un uso real.
- [ ] Retirar heurísticas locales de presentación base.

### Fase 5 — Breakdown logístico por presentación

- [ ] Decidir si pedidos/entregas necesitan desglose físico o solo equivalente.
- [ ] Crear funciones nuevas si se requiere el desglose.
- [ ] Migrar `StockBreakdown` a un contrato dimensional explícito.
- [ ] Verificar históricos con `id_presentacion` nulo.

### Fase 6 — Documentación y smoke visual

- [ ] Actualizar el plan general y tutorial.
- [ ] Ejecutar `dart analyze lib`.
- [ ] Ejecutar tests dirigidos.
- [ ] Compilar y abrir la app.
- [ ] Capturar evidencia visual de tarjeta, diálogo y ficha.

---

## Pruebas mínimas

### Dart unitario

1. `StockMixto.fromJson` con Caja, Bulto y cero en Unidad.
2. Cantidades enteras y fraccionadas.
3. Base con factor crudo distinto de 1 y `factor_rel = 1`.
4. Múltiples filas marcadas `es_base` resueltas por SQL.
5. Mapa JSON de tipo dinámico.
6. RPC vacía versus error de red.
7. Texto corto y largo.
8. Estado de stock basado en equivalente.

### SQL

1. Producto 11001, ubicación 349:
   - texto `49 Cajas + 2.8 Bultos`;
   - equivalente `1190`;
   - nunca `51.8` como total.
2. Producto de una sola presentación: mismo comportamiento visual anterior, pero con su
   nombre real.
3. Producto con presentación base cuyo factor crudo no sea 1.
4. Producto con varias ubicaciones.
5. Producto con variante y opción.
6. Presentaciones con saldo cero omitidas del texto.
7. Paginación: mismas filas y `total_count` que la función base.
8. Acceso cruzado a otra tienda rechazado.
9. Rol `anon` sin permiso para la RPC nueva.

### Widget/smoke

1. Tarjeta del producto 11001.
2. Diálogo al tocar la tarjeta.
3. Botón `Ver detalles` y vista por presentación.
4. Ficha del producto, total global y ubicación refrigerada.
5. Sección de factores de empaque.
6. Producto sin stock.
7. Producto con una sola presentación.
8. Error de red: mostrar error/reintento, no cero falso.

---

## Criterios de aceptación

- [ ] En ninguna de las tres superficies aparece `51.8` como total físico del producto
  11001.
- [ ] Se muestra `49 Cajas + 2.8 Bultos`.
- [ ] Se muestra aparte `Equivalente: 1.190 Unidades base`.
- [ ] El usuario puede ver cuánto hay de cada presentación al tocar el producto en Stock.
- [ ] El detalle de producto conserva el desglose por ubicación.
- [ ] Una cantidad heterogénea no se etiqueta como `unidades`.
- [ ] Los colores/umbrales no usan la suma física cruda.
- [ ] La sección Presentaciones explica factores, no existencias.
- [ ] La sección informativa duplicada deja de competir con la configuración operativa.
- [ ] La app vieja continúa llamando sus RPC sin cambios de firma.
- [ ] La RPC nueva valida acceso y no es ejecutable por `anon`.
- [ ] `dart analyze lib` y las pruebas dirigidas terminan sin errores nuevos.

---

## Fuera de alcance de este plan

- Migrar o borrar automáticamente las 176 equivalencias informativas antiguas.
- Cambiar cómo se registran recepciones, ventas, transferencias o conversiones.
- Reabrir decisiones de rebalanceo del plan original.
- Corregir todos los permisos/RLS históricos del proyecto en la misma migración.
- Resolver el conteo mixto de apertura de turno.

---

## Orden recomendado

1. Modelo/test puro.
2. RPC de resumen nueva y segura.
3. Tarjeta y diálogo de Inventario → Stock.
4. Ficha del producto por ubicación.
5. Consolidación de Presentaciones/Equivalencias.
6. Breakdown logístico por presentación.
7. Build y smoke visual.

La prioridad inmediata son los pasos 1–4: corrigen el dato engañoso que el usuario ya
puede ver. La limpieza de la equivalencia informativa debe hacerse después de auditar sus
consumidores, sin convertir datos históricos en factores operativos automáticamente.
