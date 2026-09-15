# Plan: cumplimiento fisico por presentaciones (despacho exacto)

Corrige el rebalanceo actual, que reune la cantidad en la presentacion pedida
en vez de despachar empaques fisicos. Alcance de esta ronda: SQL + las
operaciones de `ventiq_admin_app/lib/screens/inventory_screen.dart`. El TPV y
`ventiq_app` se migran despues, en un plan separado.

Trabajo en `main`, sin worktrees ni agentes paralelos. Todo el SQL se aplica y
se prueba con el MCP de Supabase (proyecto `vsieeihstajlrdvpuooh`), una funcion
por paso, con parada y ejecucion real antes de seguir a la siguiente.

Documento hermano (no lo reemplaza): `docs/PLAN_PRESENTACIONES_INVENTARIO.md`.
Borrador previo de esta idea: `presentaciones_inventario/PLAN_DESEMPAQUETADO_PRESENTACION.md`.

---

## 1. El defecto, medido en produccion

Precision importante sobre el ejemplo del usuario, comprobada con el MCP antes
de escribir este plan: en el caso Caja ×10 / Bulto ×5 / Unidad con stock
2 + 5 + 10, pedir 16 Unidades **ya termina hoy** en 2 Cajas + 3 Bultos +
4 Unidades. La aritmetica del algoritmo actual (`16 - 10 = 6` faltantes →
`ceil(6/5) = 2` Bultos abiertos → 10 Unidades, sobran 4) da el saldo correcto
en ese caso concreto. Lo que no hace bien es **el camino**: consume primero las
sueltas y abre dos Bultos, en vez de entregar 1 Bulto cerrado y abrir solo uno,
y nunca entrega un empaque cerrado cuando la cantidad lo cubre exacto (pedir 10
deberia dar 1 Caja).

El defecto duro y no opinable son las **cantidades fisicas fraccionarias**,
reproducido con el MCP sobre el producto **11001** (Caja ×24 > Bulto ×5 >
Unidad ×1 > Gramo ×0.0023, ubicacion 349, saldo 49 Cajas + 2.8 Bultos):

| Llamada | Devuelve hoy | Problema |
|---|---|---|
| `fn_preview_rebalanceo(11001, 349, Unidad, 16)` | abrir 1 Caja → **4.8 Bultos**, luego 4 Bultos → 20 Unidades | cantidad fisica fraccionaria de un empaque |
| saldo vivo de ese producto | **Bulto = 2.800000** | ya hay decimales de empaque en el ledger |
| `fn_preview_rebalanceo(11001, 349, Bulto, 2)` | `sobrante_tras_consumo: 0.8` | el 0.8 de Bulto no existe fisicamente |

`fn_presentaciones_producto` calcula `factor_hijo = 24/5 = 4.8`. Ese numero es
la raiz del defecto: se usa como **cantidad fisica** de empaques hijos. Abrir
una Caja de 24 con Bultos de 5 no produce 4.8 Bultos, produce 4 Bultos + 4
Unidades — exactamente la regla que pidio el usuario ("si hay que romper un
bulto de 6 y sobran dos, pasar esas dos a unidades para eliminar los decimales").

Los dos defectos comparten causa (el solver razona por division, no por
composicion fisica) y se arreglan con el mismo planificador.

Censo del catalogo (8.886 productos con presentaciones):

- 96 productos con mas de una presentacion; 118 pares padre/hijo adyacentes.
- **5 pares no divisibles** en 4 productos: 248 (Caja 24 > Paquete 10),
  1072 (Caja 40 > Blister 6), 11001 (Caja 24 > Bulto 5), 11007 (Caja 24 > Blister 6).
- 4 combinaciones producto+ubicacion con saldo en mas de una presentacion:
  3046, 9753 (ambas basura de catalogo: dos "Unidad ×1"), **11001** y **11007**.
- 36 productos con factores duplicados (28 con saldo) y 1 con dos bases: los
  rechaza `fn_presentaciones_producto_v2`, ya aplicada.

Exposicion real hoy: baja (11001 y 11007 son los productos de prueba de la
tienda 349). Se arregla ahora que esta medido, antes de que el catalogo crezca.

---

## 2. Semantica cerrada

Numeradas para poder citarlas en los pasos.

1. La clave de stock es siempre `(producto, variante, opcion, ubicacion, presentacion)`.
   Nunca se mezclan variantes ni ubicaciones.
2. `id_presentacion` siempre es `app_dat_producto_presentacion.id`. Si llega
   NULL, la RPC resuelve la base. Nunca el fallback `1`.
3. Se compara por **equivalente base exacto**; el ledger guarda las
   presentaciones **realmente entregadas**.
4. **Cobertura cerrada exacta primero.** Si la cantidad pedida se cubre exacto
   con empaques cerrados mayores, se despachan esos y no se abre nada.
   Con Caja ×10 / Bulto ×5 / Unidad: pedir 10 → **1 Caja**; pedir 15 →
   **1 Caja + 1 Bulto**. Se maximizan lexicograficamente los empaques de mayor
   factor.
5. **Si no hay cobertura cerrada exacta**, en este orden:
   a. consumir el saldo propio de la presentacion pedida;
   b. cubrir el remanente con empaques cerrados si da exacto;
   c. consumir empaques cerrados de mayor a menor **sin excederse**;
   d. abrir el empaque inmediato superior **mas pequeño que cubra** el residuo.
   Caso del usuario, 16 Unidades: 10 sueltas + 1 Bulto cerrado + abrir 1 Bulto
   → saldo final **2 Cajas + 3 Bultos + 4 Unidades**. El saldo coincide con el
   que ya da el algoritmo viejo; lo que cambia es el detalle entregado (un
   Bulto sale cerrado y solo se rompe uno), que es lo que el ledger y el kardex
   deben reflejar.
6. Pedir una presentacion mayor sin saldo propio permite **empaquetar** desde
   inferiores, siempre con cantidades fisicas enteras y equivalente exacto.
7. **Factores no divisibles se descomponen sin fracciones.** Abrir 1 Caja ×40
   con Blister ×6 da **6 Blister + 4 Unidades**, no 6.67 Blister. Es la regla
   que el usuario pidio explicitamente ("si hay que romper un bulto de 6 y
   sobran dos, pasar esas dos a unidades para eliminar los decimales").
   Toda conversion cumple `equivalente_entradas = equivalente_salidas`.
8. Presentaciones no fraccionables solo admiten cantidades enteras. Los
   factores NUMERIC se escalan a enteros para el solver; una cadena que no
   pueda conservar el equivalente da **error de configuracion, nunca redondeo**.
9. Si el equivalente total no alcanza, la operacion admin falla **atomicamente**.
   No se respeta stock negativo en las rutas nuevas.
10. Recepciones y conteos fisicos completos registran **exactamente lo
    declarado** y no rebalancean nunca.
11. Las funciones vivas (`fn_rebalancear_presentaciones`,
    `fn_descontar_con_rebalanceo`, `fn_preview_rebalanceo`, y las RPC de venta)
    **no se modifican**: siguen sirviendo al TPV y a los builds viejos. Todo lo
    nuevo es `_v2`/`_v3`, segun el patron ya adoptado en el plan hermano.

### Casos limite ya resueltos en la semantica

- Pedido exacto de un empaque mayor teniendo sueltas: gana la regla 4, se
  entrega el empaque cerrado (el ejemplo del usuario: pido 10, doy 1 Caja y
  quedan 1 Caja + 5 Bultos + 10 Unidades).
- Residuo tras abrir: se convierte al siguiente nivel hacia abajo hasta que la
  cantidad sea entera (regla 7).
- Cadena de 4 niveles con factor decimal (`Gramo ×0.0023` del 11001): el solver
  escala a enteros; si no puede, error de catalogo (regla 8).
- Catalogo invalido (36 productos con factores duplicados): error explicito,
  no adivinar. Se listan para saneamiento de datos, no de codigo.

---

## 3. Estado del terreno (verificado por MCP)

Vivo y **no se toca**: `fn_presentaciones_producto`, `fn_rebalancear_presentaciones`,
`fn_descontar_con_rebalanceo` (+ `_almacen`), `fn_preview_rebalanceo`,
`fn_ingresar_presentacion`, `fn_registrar_venta`, `fn_crear_extraccion_con_movimiento`,
`fn_transferir_inventario_entre_layouts`, `fn_insertar_ajuste_inventario2`.

Ya aplicado del corte v2: **`fn_presentaciones_producto_v2`** (archivo local
`presentaciones_inventario/35_cumplimiento_fisico_v2.sql`), `SECURITY INVOKER`,
`search_path=''`, GRANT solo a `service_role`. Tests locales en el `37`.

No existe todavia: ninguna tabla `*_solicitud_inventario`, `*_cumplimiento_*`
ni `*_conversion_presentacion_evento`. Solo `app_dat_conversion_presentacion`
(1 origen → 1 destino), que no puede representar Caja → 6 Blister + 4 Unidades.

Tablas de detalle relevantes: `app_dat_extraccion_productos` y
`app_dat_recepcion_productos` llevan `id_presentacion` + `cantidad`, asi que una
solicitud logica cumplida con varias presentaciones se representa como **varias
filas de detalle**, sin DDL en esas tablas.

Rutas admin abiertas desde `inventory_screen.dart` (las 9 opciones del FAB):

| Opcion | Pantalla | RPC que llama hoy |
|---|---|---|
| Recepcion | `inventory_reception_screen.dart` | `fn_registrar_recepcion_con_inventario` (regla 10: no cambia) |
| Transferencia | `inventory_transfer_screen.dart` | `fn_transferir_inventario_entre_layouts` |
| Ajuste exceso / faltante | `inventory_adjustment_screen.dart` | `fn_insertar_ajuste_inventario2` |
| Extraccion | `inventory_extraction_screen.dart` | `fn_crear_extraccion_con_movimiento` |
| Extraccion elaborados | `elaborated_products_extraction_screen.dart` | idem, por ingrediente |
| Venta por acuerdo | `inventory_extractionbysale_screen.dart` | `fn_registrar_venta` |
| Consignacion | `asignar_productos_consignacion_screen.dart` | `fn_crear_extraccion_con_movimiento` + escrituras directas |
| IPV / filtro | solo lectura | — |

---

## 4. Pasos

Cada paso: SQL local → aplicar por MCP → ejecutar la prueba por MCP →
**parada y OK del usuario** → Dart del mismo paso → `dart analyze` → parada.
Ningun paso deja produccion en un estado intermedio: hasta el paso 8 las
pantallas siguen llamando a las RPC viejas.

### Paso 0 · Catalogo exacto (ya casi hecho)

- Entregable: `presentaciones_inventario/35_cumplimiento_fisico_v2.sql` (existe).
- Falta: ejecutar el `37` por MCP dentro de `BEGIN/ROLLBACK` y anotar el
  resultado. Ojo: el `37` T4/T5 espera encontrar catalogos invalidos y los hay
  (36 duplicados, 1 multi-base), asi que debe pasar.
- Verificacion: `fn_presentaciones_producto_v2(11001)` devuelve 4 filas con
  `factor_entero` entero y razones exactas; `(1072)` devuelve 40/6/1.

### Paso 1 · Solver puro (el corazon)

- Archivo: `presentaciones_inventario/38_planificador_cumplimiento_v2.sql`.
- `fn_planificar_cumplimiento_presentaciones_v2(p_id_producto, p_id_ubicacion,
  p_id_presentacion, p_cantidad, p_id_variante, p_id_opcion_variante)` → `jsonb`,
  **STABLE, no escribe**.
- Implementa reglas 4-8 sobre enteros escalados. Devuelve:
  `lineas_fisicas[]` (`id_presentacion`, `cantidad`, `origen` ∈
  `propio|empaque_cerrado|apertura|empaquetado`), `conversiones[]` (N→N con
  patas), `saldos_proyectados[]`, `equivalente_solicitado`, `equivalente_cumplido`,
  `estrategia`, `mensaje_usuario`, y en fallo `error_code`
  (`INSUFFICIENT_STOCK` | `CATALOGO_PRESENTACIONES_INVALIDO`).
- Prueba (MCP, solo lectura): el caso del usuario montado con el 11001 y con un
  escenario sintetico Caja ×10/Bulto ×5/Unidad → 10 = 1 Caja; 15 = 1 Caja + 1
  Bulto; 16 = 1 Bulto + 10 Unidades + apertura, saldo 2/3/4; 12 con factores
  10 y 6 → 2×6 (no greedy); Caja ×40 → 6 Blister + 4 Unidades.
- Sin Dart en este paso.

### Paso 2 · Preview publica

- Archivo: `39_preview_cumplimiento_v2.sql`.
- `fn_preview_cumplimiento_v2(...)`: envuelve el paso 1 y agrega
  `check_user_has_access_to_tienda`, GRANT a `authenticated`, `search_path=''`.
  Misma respuesta, mas `maximo_servible`.
- Es lo que consume la UI para mostrar el desglose antes de confirmar. Nace de
  la misma funcion que escribe, para no repetir la divergencia
  preview/escritura que ya existe entre el `03` y el `10`.
- Dart: `ventiq_admin_app/lib/services/cumplimiento_fisico_service.dart` (nuevo)
  + modelos `PlanCumplimiento` / `LineaFisica`. Sin conectar a ninguna pantalla
  todavia.

### Paso 3 · Registro de conversiones N→N

- Archivo: `40_conversion_evento_v2.sql`.
- Tablas nuevas `app_dat_conversion_presentacion_evento` y `..._pata`
  (RLS habilitado, sin acceso a `anon`/`authenticated`), columna nullable
  `id_conversion_evento` en el ledger. `app_dat_conversion_presentacion` y
  `id_conversion` se conservan para el historico y para el kardex actual.
- `fn_registrar_conversion_v2(...)`: escribe evento + patas y **verifica
  neutralidad exacta** en equivalente base; si no cuadra, excepcion.
- Prueba: 1 Caja ×40 → 6 Blister + 4 Unidades deja patas enteras y neto 0.
- Guarda obligatoria: revisar que los 3 triggers vivos de
  `app_dat_inventario_productos` sigan ignorando las patas (el `04` lo hace por
  `id_conversion`; hay que extender la condicion al evento nuevo o rellenar
  ambos campos).

### Paso 4 · Ejecutor

- Archivo: `41_aplicar_cumplimiento_v2.sql`.
- `fn_aplicar_cumplimiento_v2(...)`: `pg_advisory_xact_lock` por clave completa
  en orden canonico, relee saldos bajo lock, **replanifica**, escribe
  conversiones + ledger + detalles, y verifica al cierre: sin negativos,
  `antes - salidas = despues`, conversiones neutras. Idempotencia por UUID +
  hash del payload (`IDEMPOTENCY_KEY_REUSED` si el payload difiere).
- Prueba: ensayo `BEGIN … ROLLBACK` sobre el 11001 real; despues del ROLLBACK
  se reverifica que produccion quedo intacta.

### Paso 5 · Extraccion admin v2

- Archivo: `42_extraccion_cumplimiento_v2.sql` →
  `fn_crear_extraccion_con_movimiento_v2`: una fila de
  `app_dat_extraccion_productos` por **linea fisica**, estado completado dentro
  de la misma RPC (hoy la pantalla hace un segundo `completeOperation` no atomico).
- Dart: `inventory_service.insertCompleteExtraction` apunta a la v2 y devuelve el
  desglose fisico; `inventory_extraction_screen.dart` lo muestra antes de confirmar
  (reutiliza el `CantidadMixtaInput` que ya existe) y despues en el resumen.
- Entrega verificable: extraer 16 Unidades del 11001 deja 2 filas de detalle
  (1 Bulto + 10 Unidades) y el saldo mixto correcto.

### Paso 6 · Transferencia admin v2

- Archivo: `43_transferencia_cumplimiento_v2.sql` →
  `fn_transferir_inventario_entre_layouts_v2`: planifica/aplica el origen y
  construye la recepcion **solo desde las lineas fisicas**. Pedir 10 Unidades
  cumplidas con 1 Caja produce extraccion **y** recepcion de 1 Caja.
- Dart: `inventory_service.transferBetweenLayouts` + `inventory_transfer_screen.dart`
  (payload logico igual, UUID de idempotencia, desglose fisico en el resumen).

### Paso 7 · Ajuste admin v3

- Archivo: `44_ajuste_cumplimiento_v3.sql` → `fn_insertar_ajuste_inventario_v3`
  con modos explicitos: `delta` (positivo ingresa exacto, negativo pasa por
  cumplimiento fisico) y `conteo_fisico` (setea cada presentacion, sin
  conversiones, regla 10). Recibe **todas las lineas de la sesion en una
  llamada**, no una por presentacion.
- Dart: `inventory_adjustment_screen.dart` manda la sesion completa; se conserva
  el `null` en `id_presentacion` (nunca `?? 0`, bug ya corregido en Fase 5).

### Paso 8 · Venta por acuerdo, elaborados y consignacion

- `45_venta_acuerdo_v3.sql` → `fn_registrar_venta_v3` **solo** para venta por
  acuerdo: conserva la logica financiera y de receta de la funcion viva, pero
  el descuento de inventario usa el ejecutor v2. El importe logico se reparte
  proporcionalmente por equivalente entre lineas fisicas y el residuo de
  centavos va a la ultima linea. El TPV **no se toca**.
- Elaborados: consolidar todos los ingredientes, resolver su base y mandarlos
  juntos a la extraccion v2. Si falta uno, falla la extraccion completa.
- Consignacion: `fn_consignacion_reservar_v2` / `_actualizar_reserva_v2` /
  `_cancelar_reserva_v2` reemplazan los INSERT/UPDATE/DELETE directos desde
  Flutter; reducciones y cancelaciones compensan, nunca borran ledger.

### Paso 9 · Cierre

- `46_tests_cumplimiento_v2.sql`: suite transaccional completa (los 11 grupos
  del borrador: exactitud, no-greedy, no divisibles, empaquetado, aislamiento de
  variantes/ubicaciones, transferencia espejo, venta por acuerdo, ajuste,
  consignacion, idempotencia/concurrencia, contrato de IDs).
- Advisors de seguridad y rendimiento por MCP; verificar por md5 que las
  funciones viejas no cambiaron.
- Actualizar `docs/PLAN_PRESENTACIONES_INVENTARIO.md` y el README de
  `presentaciones_inventario/` con la semantica nueva.
- `dart format --output=none --set-exit-if-changed` y `dart analyze` en
  `ventiq_admin_app`. `flutter pub get` solo si el usuario lo pide.

---

## 5. Entregables

SQL en `presentaciones_inventario/`: `35` (hecho), `37` (hecho, falta correr),
`38`–`46`. Todos idempotentes (`CREATE OR REPLACE`, `IF NOT EXISTS`), con
cabecera de proposito, `REVOKE`/`GRANT` explicito y verificaciones al final.

Dart en `ventiq_admin_app/lib/`:
`services/cumplimiento_fisico_service.dart` (nuevo),
`services/inventory_service.dart`, `services/consignacion_service.dart`,
`screens/inventory_extraction_screen.dart`, `inventory_transfer_screen.dart`,
`inventory_adjustment_screen.dart`, `inventory_extractionbysale_screen.dart`,
`elaborated_products_extraction_screen.dart`,
`asignar_productos_consignacion_screen.dart`.

Docs: este archivo, mas la actualizacion del plan hermano al cerrar.

---

## 6. Riesgos

- **`factor_hijo` fraccionario ya escribio saldos**: el 11001 tiene
  `Bulto = 2.8` en el ledger. El plan no migra historico (igual que el plan
  hermano); el solver nuevo trabaja con lo que encuentre y no genera mas
  decimales de empaque. Si el usuario quiere sanear esas 2 filas, es un ajuste
  de conteo aparte.
- **36 catalogos con factores duplicados**: `fn_presentaciones_producto_v2` los
  rechaza, asi que en cuanto una pantalla pase por el camino v2 esos productos
  fallaran con error explicito donde antes "funcionaban" por azar del orden.
  Hay que decidir si se sanean antes del paso 5 o se acepta el error visible.
- **Dos rutas de descuento conviviendo** (vieja para TPV, nueva para admin)
  hasta el plan de `ventiq_app`. Es deliberado y reversible: rollback = build
  anterior del admin.
- **Kardex**: las conversiones N→N no encajan en la fila unica origen→destino
  que muestra hoy. Hasta el paso 9 se veran como varias patas; si molesta, se
  agrupa por `id_conversion_evento`.
- No se habilita RLS masivo en las 104 tablas antiguas que marcan los advisors:
  sin politicas compatibles rompe la app. Queda como trabajo separado.

---

## 7. Preguntas abiertas

1. Los 36 productos con factores duplicados (28 con saldo): ¿los saneo antes
   del paso 5, o dejo que fallen con error explicito cuando se usen?
2. El 11001 tiene `Gramo ×0.0023` en la cadena. ¿Es catalogo real o basura de
   prueba? Si es real, define si el ultimo nivel admite decimales (regla 8).
3. Consignacion (paso 8) es el bloque mas grande y hoy escribe inventario
   directo desde Flutter. ¿Entra en esta ronda o lo dejo para una siguiente?
