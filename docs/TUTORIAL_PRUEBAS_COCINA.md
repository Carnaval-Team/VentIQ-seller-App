# Tutorial de pruebas · Restaurante + Cocina

Guía paso a paso para probar **todo** lo implementado en las fases 0–5, en las dos apps.
Nada queda sin verificar: cada paso dice qué hacer, qué debe pasar y cómo comprobarlo.

> **Antes de empezar, léete esto:**
> - Todo el SQL (`funcionalidad_cocina/01`–`22`) ya está aplicado en producción.
> - **`cocina_activa` está en `false`.** Hasta que lo enciendas, el sistema se comporta como antes: el inventario se mueve al cobrar. Eso es a propósito (§2).
> - **No hay cocinas creadas todavía** en la tienda 11. Las creas en §2.
> - Las apps no se han compilado en esta sesión: solo `dart analyze`. El §0 cubre el arranque.

---

## Estado real verificado (tienda de pruebas)

| Qué | Valor |
|-----|-------|
| Tienda | **11** — "Tienda La estrella" |
| `modo_restaurante` | `true` ✅ |
| `cocina_activa` | **`false`** ← hay que encenderlo |
| TPV | **18** — "TPV La estrella" → almacén **12** |
| Almacenes | 12 "La Estrella warehouse", 15 "contenedor refrigerado" |
| Mesas | 1 "Mesa 1" (Terraza), 2 "mesa2" (planta) |
| Cocinas | **0** ← hay que crearlas |

### Productos que se usan en el tutorial

| id | Producto | Tipo | Receta |
|----|----------|------|--------|
| 216 | harina de trigo | materia prima | — |
| 217 | azúcar refino | materia prima | — |
| 218 | sal común | materia prima | — |
| **219** | **croqueta** | elaborado | harina ×40 + sal ×10 |
| **220** | **pan de la casa** | elaborado | harina ×80 + sal ×5 + azúcar ×3 |
| **221** | **pan con croqueta** | elaborado | **2× croqueta + 1× pan de la casa** ← el combo anidado |
| 238 | pan solo | materia prima | — |
| 239 | perro caliente | materia prima | — |
| 240 | pan con perro | elaborado | pan solo ×1 + perro ×2 |

El **221 "pan con croqueta"** es la estrella del tutorial: es un elaborado que contiene otro elaborado. Con eso se prueba la parada de BOM (§7).

---

## Índice

| § | Qué se prueba | App | Tiempo |
|---|---------------|-----|--------|
| 0 | Arranque de las apps | ambas | 10 min |
| 1 | Fase 0 — descuento de receta por almacén | admin | 10 min |
| 2 | Fase 1 — crear cocinas y ligarlas | admin | 15 min |
| 3 | Fase 3a — asignar jefe de cocina (por SQL) | SQL | 5 min |
| 4 | Fase 1b — catálogo dual en el vendedor | vendedor | 10 min |
| 5 | Fase 2 — pedir ≠ cobrar (el corazón) | vendedor | 25 min |
| 6 | Fase 3b — KDS | vendedor | 20 min |
| 7 | Fase 4 — tandas y parada de BOM | vendedor | 25 min |
| 8 | Fase 5 — offline e idempotencia | vendedor | 15 min |
| 9 | Fase 5b — cierre de turno con comandas | vendedor | 10 min |
| 10 | Permisos y aislamiento entre cocinas | ambas | 15 min |
| 11 | No-regresión (que nada viejo se rompió) | ambas | 20 min |
| 12 | Checklist final | — | — |

**Total ≈ 3 horas** si se hace todo seguido. Cada sección es independiente salvo que se diga lo contrario.

---

## Cómo verificar por SQL

Varios pasos piden comprobar el inventario. Abre el **SQL Editor de Supabase** y ten esta consulta a mano:

```sql
-- Stock de los productos del tutorial en un almacén.
-- Cambia 12 por el id del almacén de la cocina cuando toque.
SELECT p.id, p.denominacion,
       public.fn_stock_producto_almacen(p.id, 12) AS stock_alm_12
  FROM app_dat_producto p
 WHERE p.id IN (216, 217, 218, 219, 220, 221)
 ORDER BY p.id;
```

Y esta para ver las cocinas y sus almacenes:

```sql
SELECT c.id AS id_cocina, c.denominacion, c.id_almacen, c.activa,
       (SELECT string_agg(tc.id_tpv::text, ', ')
          FROM app_dat_tpv_cocina tc WHERE tc.id_cocina = c.id) AS tpvs_ligados
  FROM app_dat_cocina c
 WHERE c.id_tienda = 11 AND c.deleted_at IS NULL
 ORDER BY c.id;
```

> ⚠️ **Anota los ids que te devuelva.** El tutorial los llama `<ID_COCINA_CALIENTE>`, `<ALM_CALIENTE>`, etc. porque son distintos en cada corrida.

---

## § 0 · Arranque de las apps

Esto no se hizo en la sesión de desarrollo (se verificó solo con `dart analyze`), así que es el primer paso real.

### 0.1 Admin

```bash
cd C:/Users/cesar/Documents/VentIQ-seller-App/ventiq_admin_app
export PATH="/c/Users/cesar/Documents/develop/flutter/bin:$PATH"
flutter pub get
flutter run -d windows   # o chrome / el emulador que uses
```

### 0.2 Vendedor

```bash
cd C:/Users/cesar/Documents/VentIQ-seller-App/ventiq_app
export PATH="/c/Users/cesar/Documents/develop/flutter/bin:$PATH"
flutter pub get
flutter run -d windows
```

**Qué debe pasar:** las dos apps compilan y llegan al login.

**Si falla la compilación**, el sospechoso conocido es `utils/package_image_picker_web.dart` (error preexistente de `dart:js_util`, ajeno a cocina). Solo afecta a la build **web**; en Windows/Android no debería dar problema.

- [ ] 0.1 Admin arranca
- [ ] 0.2 Vendedor arranca
- [ ] 0.3 Login OK en las dos con tu usuario de la tienda 11

---

## § 1 · Fase 0 — Descuento de receta acotado al almacén

Esta fase arregló un bug real: al vender un elaborado, el sistema buscaba la materia prima en "la última fila global" de inventario en vez de en el almacén correcto.

### 1.1 Preparar: harina en dos almacenes

En el SQL Editor:

```sql
-- Ver dónde hay harina hoy
SELECT d.id_ubicacion, d.id_almacen, d.cantidad_final
  FROM public.fn_stock_producto_almacen_detalle(216, NULL) d
 ORDER BY d.id_almacen, d.id_ubicacion;
```

Necesitas harina (216) y sal (218) en el **almacén 12** (el del TPV). Si no hay, cárgalas por la app de admin: **Inventario → Recepción**, o pide ayuda al almacenero.

> Prefiere cargar stock por la app (Recepción) y no con `INSERT` a mano: así se prueba también que la recepción sigue funcionando.

### 1.2 Vender un elaborado desde el TPV

En la **app vendedor**, con `cocina_activa` todavía en `false`:

1. Abre turno si no hay uno abierto.
2. Ve al catálogo y busca **croqueta (219)**.
3. Véndela (venta normal de mostrador, sin mesa), cantidad 1.
4. Cobra.

### 1.3 Verificar

```sql
SELECT p.id, p.denominacion,
       public.fn_stock_producto_almacen(p.id, 12) AS stock
  FROM app_dat_producto p WHERE p.id IN (216, 218);
```

**Esperado:** la harina bajó **40** y la sal **10** — exactamente la receta de una croqueta, y en el **almacén 12**, no en otro.

- [ ] 1.1 Hay harina y sal en el almacén 12
- [ ] 1.2 Venta de croqueta completada
- [ ] 1.3 Harina −40 y sal −10 **en el almacén 12**
- [ ] 1.4 El stock de **otros** almacenes (15) no cambió

---

## § 2 · Fase 1 — Crear cocinas y ligarlas al TPV

Ahora empieza lo nuevo. **Este paso es obligatorio**: sin cocinas no hay nada que probar después.

### 2.1 Encender el módulo de cocina

App **admin** → menú lateral → **Configuración** → pestaña **Configuración Global**.

1. Busca el switch **"Cocina activa"**.
2. Enciéndelo.

**Qué debe pasar:** aparece un snackbar de ~5 s. Si `modo_restaurante` estuviera apagado, se enciende **automáticamente** (van acoplados: no tiene sentido cocina sin restaurante).

> En la tienda 11 `modo_restaurante` ya está en `true`, así que solo verás encenderse la cocina.

**Verificar:**

```sql
SELECT modo_restaurante, cocina_activa
  FROM app_dat_configuracion_tienda WHERE id_tienda = 11;
```
Ambos deben quedar en `true`.

### 2.2 Comprobar el acoplamiento inverso

Sigue en la misma pantalla:

1. Apaga **modo restaurante**.
2. **Esperado:** la cocina se apaga también.
3. Vuelve a encender los dos y déjalos en `true`.

- [ ] 2.1 `cocina_activa = true`
- [ ] 2.2 Apagar restaurante apaga cocina
- [ ] 2.3 Los dos quedan encendidos al final

### 2.3 Aparece la entrada "Cocinas" en el menú

App **admin** → menú lateral. Debe aparecer **"Cocinas"** (antes no estaba).

> Si no aparece, cierra y vuelve a abrir el drawer, o reinicia la app: el flag se lee de caché.

### 2.4 Crear la primera cocina

**Cocinas** → botón **+**:

- Denominación: `Cocina caliente`
- Descripción: `Platos al pedido`
- Impresora: `COCINA-01` ← rellénala, se usa en §6.6
- Orden: `1`
- Activa: sí

Guarda.

**Qué debe pasar:** la cocina aparece en la lista. Y **se creó un almacén nuevo** con `es_cocina = true`: la cocina *es* un almacén.

**Verificar:**

```sql
SELECT c.id AS id_cocina, c.denominacion, c.id_almacen, c.impresora,
       a.denominacion AS almacen, a.es_cocina
  FROM app_dat_cocina c
  JOIN app_dat_almacen a ON a.id = c.id_almacen
 WHERE c.id_tienda = 11 AND c.deleted_at IS NULL;
```

📝 **Anota:** `<ID_COCINA_CALIENTE>` y `<ALM_CALIENTE>`.

### 2.5 Crear una segunda cocina

Repite con:

- Denominación: `Pizzería`
- Impresora: (déjala vacía) ← así se prueba el caso "cocina sin impresora"
- Orden: `2`

📝 **Anota:** `<ID_PIZZERIA>` y `<ALM_PIZZERIA>`.

> Dos cocinas son imprescindibles: casi todas las pruebas de aislamiento (§10) necesitan una cocina "ajena".

### 2.6 Ligar el TPV a la Cocina caliente

En la lista de cocinas, abre **Cocina caliente** → **TPVs** (o el icono de enlace):

1. Marca **TPV 18 "TPV La estrella"**.
2. Guarda.

**Deja la Pizzería SIN ligar.** Es intencional: en §5.6 se prueba que un plato de Pizzería es rechazado.

**Verificar:**

```sql
SELECT tc.id_tpv, c.denominacion AS cocina
  FROM app_dat_tpv_cocina tc
  JOIN app_dat_cocina c ON c.id = tc.id_cocina
 WHERE c.id_tienda = 11;
```
Debe salir **una sola fila**: TPV 18 → Cocina caliente.

- [ ] 2.4 Cocina caliente creada, con almacén propio y `es_cocina = true`
- [ ] 2.5 Pizzería creada
- [ ] 2.6 TPV 18 ligado **solo** a Cocina caliente

### 2.7 Asignar platos a las cocinas

**Cocinas** → **Cocina caliente** → pestaña **Platos**:

| Plato | Cocina | Modo |
|-------|--------|------|
| croqueta (219) | Cocina caliente | **al_pedido** |
| pan con croqueta (221) | Cocina caliente | **al_pedido** |
| pan de la casa (220) | **Pizzería** | al_pedido |

> El 220 va a **Pizzería** a propósito: es el plato "de la cocina ajena" para las pruebas de rechazo.

**Verificar:**

```sql
SELECT p.id, p.denominacion, p.modo_elaboracion,
       c.denominacion AS cocina
  FROM app_dat_producto p
  LEFT JOIN app_dat_cocina c ON c.id = p.id_cocina
 WHERE p.id IN (219, 220, 221);
```

### 2.8 Cargar materia prima en la cocina caliente

La cocina es un almacén, pero está **vacío**. Sin MP no se puede cocinar nada.

App **admin** → **Inventario → Recepción** (o la pantalla de recepción que uses):

- Almacén destino: **el de la Cocina caliente** (`<ALM_CALIENTE>`)
- harina de trigo (216): **2000**
- sal común (218): **500**
- azúcar refino (217): **300**

**Verificar:**

```sql
-- Sustituye <ALM_CALIENTE>
SELECT p.id, p.denominacion,
       public.fn_stock_producto_almacen(p.id, <ALM_CALIENTE>) AS stock_cocina
  FROM app_dat_producto p WHERE p.id IN (216, 217, 218);
```

- [ ] 2.7 Los 3 platos asignados a su cocina y modo
- [ ] 2.8 MP cargada en el almacén de la Cocina caliente

> 💡 **Punto de control.** Si llegaste aquí, la configuración está lista. Anota en un papel: `<ID_COCINA_CALIENTE>`, `<ALM_CALIENTE>`, `<ID_PIZZERIA>`, `<ALM_PIZZERIA>`.

---

## § 3 · Fase 3a — Asignar jefe de cocina (por SQL)

> ⚠️ **Pendiente conocido:** la UI de admin para asignar jefe de cocina **no está hecha**. El backend sí. Hasta que exista la pantalla, se asigna por SQL. Es el único paso del tutorial que obliga a salir de las apps.

### 3.1 Averiguar el uuid del trabajador

```sql
SELECT t.id AS id_trabajador, t.nombres, t.apellidos, t.uuid, t.user_mail
  FROM app_dat_trabajadores t
 WHERE t.id_tienda = 11 AND t.deleted_at IS NULL
 ORDER BY t.nombres;
```

📝 Anota el `uuid` y el `id_trabajador` de quien vaya a hacer de jefe de cocina.

> Puedes usar tu propio usuario. Si eres gerente o supervisor de la tienda, **ya ves todas las cocinas** sin necesidad de asignarte (así lo resuelve `fn_cocinas_del_usuario`). Pero conviene asignar a alguien que **no** sea gerente para probar el aislamiento de §10 de verdad.

### 3.2 Asignar como JEFE

```sql
-- Sustituye <UUID_JEFE>, <ID_TRABAJADOR> y <ID_COCINA_CALIENTE>
SELECT public.fn_asignar_jefe_cocina(
    '<UUID_JEFE>'::uuid,
    <ID_COCINA_CALIENTE>,
    <ID_TRABAJADOR>,
    true          -- true = jefe (puede producir tandas)
);
```

**Esperado:** `{"status":"success", "ya_existia":false, "message":"Asignado como jefe de Cocina caliente"}`

### 3.3 Probar que es idempotente

Ejecuta **la misma consulta otra vez**.

**Esperado:** `"ya_existia": true`. No falla, actualiza. Así una reasignación no revienta.

### 3.4 Asignar un COCINERO (para probar permisos)

Con **otro** trabajador:

```sql
SELECT public.fn_asignar_jefe_cocina(
    '<UUID_COCINERO>'::uuid,
    <ID_COCINA_CALIENTE>,
    <ID_TRABAJADOR_2>,
    false         -- false = cocinero: KDS sí, producir tandas no
);
```

### 3.5 Ver el personal de la cocina

```sql
SELECT public.fn_listar_personal_cocina(<ID_COCINA_CALIENTE>);
```

**Esperado:** los dos, con `rol` "Jefe de cocina" y "Cocinero". El jefe primero.

- [ ] 3.2 Jefe asignado
- [ ] 3.3 Reasignar devuelve `ya_existia: true`
- [ ] 3.4 Cocinero asignado con `es_jefe = false`
- [ ] 3.5 `fn_listar_personal_cocina` devuelve 2

---

## § 4 · Fase 1b — Catálogo dual en el vendedor

Aquí se comprueba que el vendedor **ve** los platos de cocina mezclados con los productos de barra.

App **vendedor**, login con el usuario del TPV 18.

### 4.1 El catálogo muestra platos de cocina

Ve al catálogo de productos (venta normal).

**Qué debe pasar:** además de los productos del almacén 12 (harina, sal, pan solo...), aparecen **croqueta** y **pan con croqueta**, que son platos de la Cocina caliente.

### 4.2 Los chips de cocina

Cada plato de cocina lleva un **chip** debajo del nombre. Colores:

| Color | Significado |
|-------|-------------|
| 🟠 ámbar | `por_tanda` — porciones ya hechas, se sirven al momento |
| 🔵 índigo | `al_pedido` — hay que cocinarlo, tarda |
| 🔴 rojo | agotado — no se puede pedir |

Ahora mismo croqueta y pan con croqueta deben salir **índigo** (`al_pedido`) con el nombre "Cocina caliente".

### 4.3 Un producto de barra NO lleva chip

Busca **pan solo (238)** o **harina (216)**: no deben tener chip de cocina. Son productos normales del almacén del TPV.

### 4.4 "pan de la casa" NO debe aparecer

El 220 lo asignaste a **Pizzería**, que no está ligada al TPV 18.

**Esperado:** **no aparece** en el catálogo. Es el criterio de aceptación *"bistec va a Cocina caliente; no aparece en Pizzería"*, al revés.

> Si aparece: revisa §2.6 (la Pizzería no debe estar ligada) y §2.7 (el 220 debe tener `id_cocina` = Pizzería).

### 4.5 Disponibilidad calculada

Toca **croqueta** para ver el detalle.

**Esperado:** la disponibilidad no es el stock de croquetas (que es 0), sino **cuántas se pueden hacer con la MP de la cocina**. Con 2000 de harina (×40) y 500 de sal (×10) → el límite lo pone la sal: **50**.

- [ ] 4.1 Croqueta y pan con croqueta visibles
- [ ] 4.2 Chips índigo con "Cocina caliente"
- [ ] 4.3 Productos de barra sin chip
- [ ] 4.4 "pan de la casa" (Pizzería) **no aparece**
- [ ] 4.5 Disponibilidad ≈ 50 croquetas

---

## § 5 · Fase 2 — Pedir ≠ cobrar (el corazón del sistema)

La idea: **pedir mueve el inventario y manda a cocina; cobrar solo cobra.** Antes todo pasaba al cobrar.

### 5.1 Foto del stock ANTES

```sql
-- Sustituye <ALM_CALIENTE>
SELECT 'harina' AS q, public.fn_stock_producto_almacen(216, <ALM_CALIENTE>) AS cocina
UNION ALL SELECT 'sal', public.fn_stock_producto_almacen(218, <ALM_CALIENTE>)
UNION ALL SELECT 'harina_barra', public.fn_stock_producto_almacen(216, 12);
```

📝 Anota los tres números.

### 5.2 Abrir mesa y pedir un plato de cocina

App **vendedor**:

1. **Mesas** → **Mesa 1** → abrir cuenta.
2. **Agregar productos** → **croqueta**, cantidad **2**.
3. Si la pantalla permite nota, escribe `sin sal, bien tostada`.
4. Confirma.

**Qué debe pasar:** el snackbar dice **"🍳 Enviado a Cocina caliente"** — no "Total en orden: N productos".

> Si dice "Total en orden", `cocina_activa` no está encendido (§2.1) o la app tiene la config en caché: reinicia la app.

### 5.3 Verificar que el inventario YA se movió

```sql
SELECT 'harina' AS q, public.fn_stock_producto_almacen(216, <ALM_CALIENTE>) AS cocina
UNION ALL SELECT 'sal', public.fn_stock_producto_almacen(218, <ALM_CALIENTE>);
```

**Esperado:** harina **−80** y sal **−20** respecto a §5.1 (2 croquetas × 40 y × 10).

**Esto es lo nuevo.** Antes de la Fase 2, pedir no tocaba nada.

### 5.4 Verificar que se creó la comanda

```sql
SELECT co.id, co.numero, co.estado, ck.denominacion AS cocina,
       m.numero AS mesa, ci.denominacion AS plato, ci.cantidad, ci.notas
  FROM app_dat_comanda co
  JOIN app_dat_cocina ck ON ck.id = co.id_cocina
  JOIN app_dat_comanda_item ci ON ci.id_comanda = co.id
  LEFT JOIN app_dat_mesas m ON m.id = co.id_mesa
 WHERE co.id_cuenta IS NOT NULL
 ORDER BY co.id DESC LIMIT 5;
```

**Esperado:** una comanda con `numero = 1` (correlativo por tienda/día), estado 1 (pendiente), tu nota en `notas`.

📝 Anota `<ID_COMANDA>`.

### 5.5 El estado se ve en la línea de la cuenta

Vuelve a la pantalla de la **cuenta de Mesa 1**.

**Qué debe pasar:**
- Un **banner** arriba: "1 en cocina · La cocina está preparando el pedido" (índigo).
- En la línea de la croqueta, un **chip** "En cocina · Cocina caliente · #1".
- La nota "sin sal, bien tostada" visible en naranja.

### 5.6 Un plato de cocina NO ligada se rechaza

Sigue en la cuenta. **Agregar productos** → busca **pan de la casa (220)**.

**Esperado:** no aparece en el catálogo (§4.4). Si lo fuerzas por búsqueda directa y lo intentas agregar, la RPC responde `COCINA_NO_LIGADA` y **no se agrega la línea**.

**Verificar que no se agregó:**
```sql
SELECT count(*) FROM app_dat_mesa_cuenta_item WHERE id_producto = 220;
```

### 5.7 Pedir un producto de BARRA en la misma cuenta

**Agregar productos** → **pan solo (238)** o **harina**, cantidad 1.

**Qué debe pasar:**
- El snackbar **no** menciona cocina.
- La línea **no** lleva chip de estado.
- El stock baja del **almacén 12** (la barra), no del de la cocina.

```sql
SELECT public.fn_stock_producto_almacen(238, 12) AS pan_barra;
```

**Esto prueba la convivencia:** en la misma cuenta hay una línea de cocina y una de barra, cada una descontando de su almacén.

### 5.8 ⭐ Cobrar NO vuelve a descontar

Este es **el** paso crítico de la Fase 2.

1. Foto del stock:

```sql
SELECT 'harina' AS q, public.fn_stock_producto_almacen(216, <ALM_CALIENTE>) AS cocina
UNION ALL SELECT 'sal', public.fn_stock_producto_almacen(218, <ALM_CALIENTE>);
```
📝 Anota.

2. En la cuenta → **Cerrar Nota** → completa el cobro (checkout normal).

3. **Aparecerá un diálogo** "Hay platos en cocina" (porque la comanda sigue pendiente): elige **Cobrar igual**.

4. Vuelve a mirar el stock con la misma consulta.

**Esperado: los mismos números.** Harina y sal **no bajaron** al cobrar, porque ya bajaron al pedir.

> ❌ **Si bajaron otra vez**, hay doble descuento. Ese era el bug #3 de la tabla del plan; el `17` lo arregla. Verifica:
> ```sql
> SELECT (prosrc LIKE '%v_lineas_ya_movidas%') AS tiene_17
>   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
>  WHERE n.nspname='public' AND p.proname='fn_registrar_venta_mesa';
> ```
> Debe dar `true`.

### 5.9 Confirmar en la respuesta de la venta

```sql
SELECT i.id, i.id_producto, i.origen_stock, i.stock_movido, i.estado_servicio
  FROM app_dat_mesa_cuenta_item i
  JOIN app_dat_mesa_cuenta_abierta c ON c.id = i.id_cuenta
 WHERE c.id_mesa = 1
 ORDER BY i.id DESC LIMIT 5;
```

**Esperado:** la croqueta con `origen_stock = 'al_pedido'` y `stock_movido = true`. El pan solo con `origen_stock = 'tpv'`.

`stock_movido = true` es la marca que le dice al cobro "esta línea ya se descontó, no la toques".

### 5.10 Cancelar un item NO servido devuelve el stock

1. Abre una cuenta nueva en **Mesa 2**.
2. Pide **croqueta ×1**. (harina −40)
3. Sin marcar nada en cocina, **elimina/cancela** esa línea desde la cuenta.

**Esperado:** harina **+40** (vuelve), y la comanda pasa a estado 5 (cancelada).

```sql
SELECT public.fn_stock_producto_almacen(216, <ALM_CALIENTE>) AS harina;
```

### 5.11 Cancelar un item YA servido es merma (no devuelve)

1. En la misma cuenta, pide **croqueta ×1** otra vez.
2. Ve al **KDS** (§6) y marca esa comanda como **entregada**.
3. Vuelve a la cuenta e intenta cancelar esa línea.

**Esperado:** pide **motivo** (`MOTIVO_REQUERIDO`). Con motivo, la línea se retira **pero el stock NO vuelve**: la materia prima ya se cocinó.

> Devolver stock de algo ya cocinado es el error clásico que descuadra el inventario de un restaurante. Por eso se distingue.

- [ ] 5.2 Snackbar "🍳 Enviado a Cocina caliente"
- [ ] 5.3 Harina −80, sal −20 **al pedir**
- [ ] 5.4 Comanda creada con número y nota
- [ ] 5.5 Banner + chip + nota visibles en la cuenta
- [ ] 5.6 Plato de Pizzería rechazado, sin crear línea
- [ ] 5.7 Producto de barra descuenta del almacén 12
- [ ] 5.8 ⭐ **Cobrar no vuelve a descontar**
- [ ] 5.9 `stock_movido = true` en la línea de cocina
- [ ] 5.10 Cancelar no servido devuelve stock
- [ ] 5.11 Cancelar servido exige motivo y NO devuelve

---

## § 6 · Fase 3b — KDS (pantalla de cocina)

Login en la app **vendedor** con el usuario **jefe de cocina** de §3.2.

### 6.1 La entrada "Cocina" en el menú

Menú lateral → debe aparecer **"Cocina"** con subtítulo "Comandas pendientes de preparar".

> La entrada aparece solo si el usuario **tiene cocinas asignadas**, no por el modo restaurante. Un vendedor sin cocina no la ve; un cocinero sí, aunque no maneje mesas.

### 6.2 Preparar: varias comandas

Con el usuario **vendedor**, crea 2–3 comandas:
- Mesa 1: croqueta ×2
- Mesa 2: croqueta ×1 + pan con croqueta ×1

Vuelve al usuario **jefe de cocina** → **Cocina**.

### 6.3 Lectura de la pantalla

**Qué debe pasar:**
- Tarjetas en cuadrícula (4 columnas en tablet, 1 en móvil).
- Cada tarjeta: **#número** grande, mesa y zona, minutos de espera.
- Orden **FIFO**: la más antigua primero.
- Cabecera gris azulado (pendiente).
- Cada plato con su cantidad en un cuadrado y botón **"Empezar"**.
- La nota del comensal en **naranja**, debajo del plato.

### 6.4 Avanzar un plato con un toque

Toca la fila de un plato (no el botón de la comanda).

**Esperado:** pasa a **"Preparando"** (índigo) y el botón cambia a **"Listo"**. Sin diálogo de confirmación: en cocina no hay tiempo.

Tócalo otra vez → **"Listo"** (verde) → otra vez → **"Entregado"**.

> El verde es el único color llamativo a propósito: es el único estado que exige acción del mesero (ir al pase a recoger).

### 6.5 Deshacer un marcado

Un plato en **Listo**: mantén pulsado... no, eso cancela. Para deshacer, el backend permite retroceder **un paso** (3→2). Si la UI no expone el botón de retroceso, verifícalo por SQL:

```sql
-- Sustituye <ID_COMANDA_ITEM>
SELECT public.fn_cambiar_estado_comanda_item(<ID_COMANDA_ITEM>, 2::smallint);
```
**Esperado:** `success`, vuelve a "en preparacion".

Y que un retroceso de **dos** pasos se rechaza:
```sql
SELECT public.fn_cambiar_estado_comanda_item(<ID_COMANDA_ITEM>, 1::smallint);
```
Estando en 3 → `TRANSICION_INVALIDA`.

### 6.6 "Marchando todo" (ticket completo)

En una comanda con **2 platos en estados distintos** (uno pendiente, uno preparando), pulsa el botón grande del pie: **"Marchando todo"**.

**Esperado:** los dos pasan a listo y la **cabecera** de la comanda queda en verde.

> Esto era un bug (#5 del plan): la matriz de transiciones solo permitía avanzar de uno en uno, así que los platos en "pendiente" se saltaban y la comanda nunca llegaba a listo. Quedaba atascada en el KDS para siempre. Si ves que la cabecera no se pone verde, avísame.

### 6.7 La cabecera es el mínimo de los items

Con una comanda de 2 platos: marca **uno** como listo y deja el otro en pendiente.

**Esperado:** la comanda sigue diciendo **"Pendiente"**, no "Listo". Es la verdad operativa: no puedes servir la mesa entera todavía.

### 6.8 Entregar y desaparecer de la vista

Marca una comanda como **Entregar**.

**Esperado:** desaparece de la lista (la vista muestra solo lo vivo: pendiente/preparando/listo).

Pulsa el icono de **historial** (arriba a la derecha): ahí está.

### 6.9 El mesero ve el cambio

Sin cerrar el KDS, con el usuario **vendedor** abre la cuenta de esa mesa.

**Esperado:** el chip de la línea cambió a **"Listo"** (verde) o **"Entregado"** (gris), y el banner de arriba dice "1 listo · Hay platos esperando en el pase".

> Detalle técnico: el chip lee `comanda_estado` (el dato vivo) con fallback a `estado_servicio` (la foto del momento de pedir). Si leyera solo el segundo, se quedaría atrás.

### 6.10 Refresco automático

Deja el KDS abierto. Con el vendedor, pide un plato nuevo.

**Esperado:** en **≤ 15 segundos** aparece la comanda nueva sin tocar nada. El subtítulo del AppBar muestra la hora de la última carga.

### 6.11 El ticket de cocina (backend)

> ⚠️ **La UI de impresión está pendiente.** El backend está listo y se puede verificar:

```sql
-- Sustituye <ID_COMANDA>
SELECT (public.fn_ticket_comanda(<ID_COMANDA>))->>'impresora' AS impresora,
       (public.fn_ticket_comanda(<ID_COMANDA>))->>'texto'    AS ticket;
```

**Esperado**, algo así:

```
               COMANDA #1
COCINA CALIENTE
----------------------------------------
Mesa: Mesa 1  (Terraza)
Atiende: <tu nombre>
Hora: 14:03
----------------------------------------
2 x croqueta
   >> SIN SAL, BIEN TOSTADA
----------------------------------------
```

Y `impresora` = `COCINA-01` (lo que pusiste en §2.4). Para la Pizzería saldría `null` → la app debería mostrar el ticket en pantalla.

> El ticket **no lleva precios**: al cocinero no le importan y ocupan espacio que necesitan las notas.

- [ ] 6.1 Entrada "Cocina" visible
- [ ] 6.3 Tarjetas FIFO con espera y notas
- [ ] 6.4 Un toque avanza el plato
- [ ] 6.5 Retroceso de 1 paso OK, de 2 rechazado
- [ ] 6.6 "Marchando todo" pone la cabecera en verde
- [ ] 6.7 Cabecera = mínimo de los items
- [ ] 6.8 Entregado sale de la vista viva y está en el historial
- [ ] 6.9 El mesero ve el cambio de estado
- [ ] 6.10 Refresco ≤ 15 s
- [ ] 6.11 `fn_ticket_comanda` devuelve texto + impresora

---

## § 7 · Fase 4 — Tandas y parada de BOM

Un arroz moro no se cocina por raciones: se hace una olla y se sirve hasta que se acaba. Eso es una **tanda**.

Login como **jefe de cocina**.

### 7.1 Poner un plato en modo `por_tanda`

App **admin** → **Cocinas** → **Cocina caliente** → **Platos**:

- Cambia **croqueta (219)** de `al_pedido` a **`por_tanda`**.

**Verificar:**
```sql
SELECT id, denominacion, modo_elaboracion, id_cocina
  FROM app_dat_producto WHERE id = 219;
```

### 7.2 La pantalla de Producción

App **vendedor** (jefe de cocina) → menú → **Producción**.

**Qué debe pasar:** dos pestañas, **Platos** y **Lotes**. En Platos aparece **croqueta**.

En la tarjeta:
- Número grande a la derecha: **porciones hechas** (0 ahora).
- Estado: **"Agotado"** en rojo (0 porciones, aunque haya materia prima de sobra).
- **"Se pueden hacer N más"**.
- **"Limita: sal comun"** o "harina de trigo" — el ingrediente que topa la producción.
- Botón **Producir**.

> Que diga *qué* ingrediente limita no es decoración: es lo que el jefe tiene que pedirle al almacén.

### 7.3 Producir una tanda

1. Foto del stock:

```sql
SELECT 'harina' AS q, public.fn_stock_producto_almacen(216, <ALM_CALIENTE>) AS v
UNION ALL SELECT 'sal', public.fn_stock_producto_almacen(218, <ALM_CALIENTE>)
UNION ALL SELECT 'croquetas', public.fn_stock_producto_almacen(219, <ALM_CALIENTE>);
```
📝 Anota.

2. Pulsa **Producir** → el diálogo propone un número (el máximo, topado a 10).
3. Pon **10** porciones y nota `olla del mediodia`.
4. Confirma.

**Esperado:** snackbar "10 porciones de croqueta listas en Cocina caliente".

5. Verifica con la misma consulta:

| Producto | Cambio esperado |
|----------|-----------------|
| harina | **−400** (10 × 40) |
| sal | **−100** (10 × 10) |
| croquetas | **+10** |

### 7.4 Ahora el plato está disponible

Vuelve a la pestaña **Platos**.

**Esperado:** croqueta con **10 hechas**, estado **"Disponible"** en verde.

Y en el catálogo del **vendedor**, el chip de croqueta cambió de índigo a **ámbar** (`por_tanda`).

### 7.5 No alcanza la materia prima

Pulsa **Producir** y pide un número absurdo: **500**.

**Esperado:** el diálogo lo rechaza antes de enviar ("Solo alcanza para N"). Si lo forzaras, el backend responde `INSUFFICIENT_STOCK` y **aparece un diálogo con el detalle**: cada ingrediente con *hay / hacen falta / falta*.

> Un "error de stock" genérico no sirve de nada. El jefe necesita saber qué pedir.

### 7.6 Vender de la tanda

Con el **vendedor**: abre Mesa 1 y pide **croqueta ×2**.

**Qué debe pasar:**
- **No se crea comanda** — ya está cocinada, se sirve directo.
- La línea sale como **entregada** (`estado_servicio = 4`).
- Bajan **2 porciones** del SKU terminado, **NO** baja harina ni sal.

```sql
SELECT 'croquetas' AS q, public.fn_stock_producto_almacen(219, <ALM_CALIENTE>) AS v
UNION ALL SELECT 'harina', public.fn_stock_producto_almacen(216, <ALM_CALIENTE>);
```
**Esperado:** croquetas 10 → **8**; harina **igual**.

Y que no hubo comanda:
```sql
SELECT count(*) AS comandas_nuevas FROM app_dat_comanda
 WHERE created_at > now() - interval '5 minutes';
```

### 7.7 Agotado aunque quede materia prima

Sirve croquetas hasta llegar a **0** (pide 8 más, o pon `porciones = 1` y produce/vende hasta agotar).

**Esperado:** con 0 porciones el plato queda **"Agotado"** en rojo, **aunque queden 1600 de harina**. Es la regla de la Fase 4: la disponibilidad de un `por_tanda` es el stock terminado, no lo que se podría cocinar.

### 7.8 ⭐ La parada de BOM (el combo anidado)

Aquí se prueba lo más delicado de la Fase 4.

**Contexto:** `pan con croqueta (221)` = 2 × croqueta (219) + 1 × pan de la casa (220). Y la croqueta ahora es `por_tanda`.

Cuando alguien pide un "pan con croqueta", el sistema **no debe** volver a explotar la receta de la croqueta (harina + sal): debe **consumir 2 croquetas ya hechas**.

1. Asigna **pan con croqueta (221)** a Cocina caliente en modo `al_pedido` (si no lo hiciste en §2.7).
2. Produce una tanda de **10 croquetas** (§7.3).
3. Comprueba lo que el sistema *cree* que va a consumir:

```sql
SELECT t.id_ingrediente, p.denominacion, t.cantidad_total_necesaria, t.es_por_tanda
  FROM public.fn_ingredientes_con_parada_tanda(221, 1) t
  JOIN app_dat_producto p ON p.id = t.id_ingrediente
 ORDER BY p.denominacion;
```

**Esperado (correcto):**

| ingrediente | cantidad | es_por_tanda |
|-------------|----------|--------------|
| azúcar refino | 3 | false |
| **croqueta** | **2** | **true** ← paró aquí |
| harina de trigo | 80 | false |
| sal comun | 5 | false |

Los 80 de harina y 5 de sal son del **pan de la casa**, no de la croqueta.

**Comparación con la función vieja** (que sigue existiendo para Fase 0):

```sql
SELECT p.denominacion, r.cantidad_total_necesaria
  FROM public.fn_obtener_ingredientes_recursivos(221, 1) r
  JOIN app_dat_producto p ON p.id = r.id_ingrediente
 ORDER BY p.denominacion;
```

**Esperado:** harina **160**, sal **25** — porque explota la croqueta hasta las hojas. Sin la parada, pedir un combo descontaría harina cruda **que ya se consumió al producir la tanda**: doble descuento silencioso.

4. Ahora pide **pan con croqueta ×1** desde una mesa y verifica:

```sql
SELECT 'croquetas' AS q, public.fn_stock_producto_almacen(219, <ALM_CALIENTE>) AS v
UNION ALL SELECT 'harina', public.fn_stock_producto_almacen(216, <ALM_CALIENTE>);
```
**Esperado:** croquetas **−2**, harina **−80** (solo la del pan).

- [ ] 7.1 Croqueta en `por_tanda`
- [ ] 7.2 Pantalla Producción con "Limita: X"
- [ ] 7.3 Producir 10: harina −400, sal −100, croquetas +10
- [ ] 7.4 Estado "Disponible" y chip ámbar
- [ ] 7.5 Diálogo de faltantes con detalle por ingrediente
- [ ] 7.6 Vender de tanda: −porciones, sin comanda, sin tocar MP
- [ ] 7.7 Agotado con 0 porciones aunque quede MP
- [ ] 7.8 ⭐ **Parada de BOM: croqueta=2 [TANDA], no harina=160**

### 7.9 Cerrar una tanda con merma

Al final del servicio sobran porciones y se botan.

1. **Producción** → pestaña **Lotes**. Ahí está la tanda **Abierta**, con producidas, quedan, costo/porción y quién la hizo.
2. Pulsa **Cerrar lote**.
3. El diálogo propone descartar **lo que queda** (al final del servicio, lo que sobró es lo que se bota).
4. Deja el número y **no pongas motivo** → pulsa Cerrar.

**Esperado:** rechaza con "Indica el motivo del descarte".

5. Escribe motivo `sobro del servicio` → Cerrar.

**Esperado:** snackbar con el mensaje **y el costo real por porción**.

**Verificar:**
```sql
SELECT id, porciones_producidas, porciones_descartadas, motivo_descarte,
       estado, costo_mp, closed_at
  FROM app_dat_produccion_tanda ORDER BY id DESC LIMIT 3;
```
`estado = 3` (cerrada), `porciones_descartadas` con el número, `motivo_descarte` con tu texto.

> **Por qué producidas y descartadas van separadas:** si produces 12 y botas 2, no es lo mismo que haber producido 10 — la materia prima de las 12 se gastó igual. Así `costo_por_servida` sale correcto (2498.4 con merma vs 2082 sin ella) y es el número que dice si el tamaño del lote fue el adecuado.

### 7.10 Anular una tanda (me equivoqué de plato)

1. Produce una tanda de **5** croquetas.
2. **Sin vender ninguna**, pulsa **Anular** → confirma.

**Esperado:** "Tanda anulada: se retiraron 5 porciones y se devolvió la materia prima".

**Verificar reversión exacta:** harina y sal vuelven a los valores previos, y las porciones también.

### 7.11 ⭐ Anular una tanda YA servida se rechaza

1. Produce **4** croquetas.
2. **Vende 1** desde una mesa.
3. Intenta **Anular**.

**Esperado:** se rechaza con "Ya salieron 1 porciones desde que se creó esta tanda" y la app **ofrece cerrar con merma** en el mismo diálogo.

4. Acepta → se cierra con merma.

> Este fue el bug #6 del plan: comparaba el stock **total** del plato contra las porciones del lote. Con 10 sobrantes de otro lote + 4 nuevas − 1 vendida = 13 ≥ 4, el chequeo pasaba y anulaba una tanda ya servida: retiraba 4 cuando quedaban 3, y devolvía la MP entera. Descuadre en los dos sentidos.
>
> Y el bug #7: el primer arreglo usaba `created_at`, pero `now()` es **constante dentro de una transacción**, así que una venta en la misma transacción tenía el mismo timestamp y se perdía. Se resolvió con `id_inventario_entrada` como ancla.

- [ ] 7.9 Cerrar sin motivo se rechaza; con motivo registra merma y costo real
- [ ] 7.10 Anular sin ventas revierte exacto (MP y porciones)
- [ ] 7.11 ⭐ Anular con 1 vendida se rechaza y ofrece cerrar con merma

---

## § 8 · Fase 5 — Offline e idempotencia

La tablet de un restaurante pierde el wifi a media comanda. Al volver la red, la cola reenvía. **Sin idempotencia el plato se pediría dos veces**: doble descuento de materia prima y dos comandas para la cocina.

### 8.1 La prueba clave, por SQL

Esta es la más importante de la fase y se puede verificar directamente. Copia el bloque completo en el SQL Editor (sustituye `<ID_COCINA_CALIENTE>` y `<ALM_CALIENTE>`):

```sql
BEGIN;
-- Simula ser el vendedor (por MCP/SQL Editor auth.uid() viene NULL)
SELECT set_config('request.jwt.claims',
  json_build_object('sub','<UUID_DEL_VENDEDOR>','role','authenticated')::text, true);

CREATE TEMP TABLE r(n int, paso text, resultado jsonb) ON COMMIT DROP;

DO $$
DECLARE
  CU  uuid := gen_random_uuid();   -- el client_uuid del dispositivo
  v_cta bigint; v_r1 jsonb; v_r2 jsonb;
  v_h0 numeric; v_h1 numeric; v_h2 numeric;
  v_lineas1 int; v_lineas2 int; v_com1 int; v_com2 int;
BEGIN
  v_cta := public.fn_abrir_cuenta_mesa(p_id_mesa:=1, p_id_tpv:=18, p_forzar_nueva:=true);
  v_h0  := public.fn_stock_producto_almacen(216, <ALM_CALIENTE>);

  -- 1er envío: llega, pero la tablet cree que falló
  v_r1 := public.fn_pedir_item_cuenta_offline(
    p_client_uuid := CU, p_id_cuenta := v_cta, p_id_producto := 219,
    p_cantidad := 2, p_precio_unitario := 100, p_notas := 'sin sal');
  v_h1 := public.fn_stock_producto_almacen(216, <ALM_CALIENTE>);
  SELECT count(*) INTO v_lineas1 FROM app_dat_mesa_cuenta_item WHERE id_cuenta = v_cta;
  SELECT count(*) INTO v_com1    FROM app_dat_comanda          WHERE id_cuenta = v_cta;

  INSERT INTO r VALUES (1, '1er envio', jsonb_build_object(
    'idempotent', v_r1->'idempotent', 'id_item', v_r1->'id_item',
    'harina', v_h0 || ' -> ' || v_h1, 'lineas', v_lineas1, 'comandas', v_com1));

  -- 2do envío: MISMO client_uuid (la cola reintenta al volver la red)
  v_r2 := public.fn_pedir_item_cuenta_offline(
    p_client_uuid := CU, p_id_cuenta := v_cta, p_id_producto := 219,
    p_cantidad := 2, p_precio_unitario := 100, p_notas := 'sin sal');
  v_h2 := public.fn_stock_producto_almacen(216, <ALM_CALIENTE>);
  SELECT count(*) INTO v_lineas2 FROM app_dat_mesa_cuenta_item WHERE id_cuenta = v_cta;
  SELECT count(*) INTO v_com2    FROM app_dat_comanda          WHERE id_cuenta = v_cta;

  INSERT INTO r VALUES (2, 'CLAVE 2do envio mismo uuid', jsonb_build_object(
    'idempotent', v_r2->'idempotent',
    'MISMO_ID_ITEM',         (v_r1->'id_item') = (v_r2->'id_item'),
    'NO_VOLVIO_A_DESCONTAR', v_h1 = v_h2,
    'SIN_LINEA_NUEVA',       v_lineas1 = v_lineas2,
    'SIN_COMANDA_NUEVA',     v_com1 = v_com2));

  -- 3er envío con OTRO uuid: sí debe crear otro pedido
  v_r2 := public.fn_pedir_item_cuenta_offline(
    p_client_uuid := gen_random_uuid(), p_id_cuenta := v_cta, p_id_producto := 219,
    p_cantidad := 1, p_precio_unitario := 100);
  INSERT INTO r VALUES (3, '3er envio otro uuid', jsonb_build_object(
    'idempotent', v_r2->'idempotent',
    'bajo_mas', v_h2 - public.fn_stock_producto_almacen(216, <ALM_CALIENTE>)));

  -- Sin client_uuid: rechazo
  v_r2 := public.fn_pedir_item_cuenta_offline(
    p_client_uuid := NULL, p_id_cuenta := v_cta, p_id_producto := 219,
    p_cantidad := 1, p_precio_unitario := 100);
  INSERT INTO r VALUES (4, 'sin client_uuid', jsonb_build_object('error', v_r2->>'error_code'));
END $$;

SELECT n, paso, resultado FROM r ORDER BY n;
ROLLBACK;   -- ← no deja rastro
```

**Esperado:**

| paso | resultado |
|------|-----------|
| 1er envío | `idempotent: false`, harina baja 80, 1 línea, 1 comanda |
| **2do envío** | `idempotent: true`, **MISMO_ID_ITEM: true**, **NO_VOLVIO_A_DESCONTAR: true**, **SIN_LINEA_NUEVA: true**, **SIN_COMANDA_NUEVA: true** |
| 3er envío | `idempotent: false`, `bajo_mas: 40` |
| sin uuid | `CLIENT_UUID_REQUERIDO` |

> El `ROLLBACK` del final deshace todo: puedes correrlo las veces que quieras sin ensuciar datos.

### 8.2 Lo mismo para el KDS

El cocinero marca "listo" sin red. Al reintentar no debe fallar:

```sql
BEGIN;
SELECT set_config('request.jwt.claims',
  json_build_object('sub','<UUID_JEFE>','role','authenticated')::text, true);

-- Sustituye <ID_COMANDA_ITEM> por uno real en estado 1 o 2
SELECT public.fn_cambiar_estado_comanda_item_offline(
  'aaaaaaaa-1111-2222-3333-444444444444'::uuid, <ID_COMANDA_ITEM>, 3::smallint) AS primero;

SELECT public.fn_cambiar_estado_comanda_item_offline(
  'aaaaaaaa-1111-2222-3333-444444444444'::uuid, <ID_COMANDA_ITEM>, 3::smallint) AS reintento;
ROLLBACK;
```

**Esperado:** el primero `idempotent: false`, el reintento `idempotent: true` con "Este cambio ya se habia aplicado".

### 8.3 Prueba real en el dispositivo

1. Abre una cuenta en Mesa 1.
2. **Pon el dispositivo en modo avión** (o apaga el wifi).
3. Pide **croqueta ×2**.

**Qué debe pasar:** la app avisa que no hay conexión. Según cómo esté enganchada la pantalla, el pedido queda en la cola local (`cocina_offline_queue.dart`, persistida en SharedPreferences).

4. **Cierra la app por completo** (no solo minimizar).
5. Vuelve a abrirla, **todavía sin red**.

**Esperado:** la cola **sigue ahí**. Esto es lo que diferencia esta cola de `NetworkRequestQueue`: aquella guarda closures en memoria y se perdería.

6. **Enciende la red.**

**Esperado:** al sincronizar, el pedido llega, se descuenta **una sola vez** y aparece la comanda en el KDS.

7. Verifica que no se duplicó:

```sql
SELECT i.id, i.id_producto, i.cantidad, i.stock_movido
  FROM app_dat_mesa_cuenta_item i
  JOIN app_dat_mesa_cuenta_abierta c ON c.id = i.id_cuenta
 WHERE c.id_mesa = 1 AND c.estado = 1
 ORDER BY i.id;
```
**Una sola línea** de croqueta, no dos.

> ⚠️ Si la pantalla todavía no llama a `CocinaOfflineQueue`, este paso puede comportarse como el camino online normal (error de red visible al usuario). El servicio y las RPC están probados; el enganche fino con cada pantalla es lo que puede faltar. Anótalo y me lo dices.

### 8.4 Registro de idempotencia

```sql
SELECT tipo, count(*) AS operaciones
  FROM app_dat_operacion_offline_idempotencia
 GROUP BY tipo ORDER BY 2 DESC;
```

**Esperado:** además de los tipos que ya existían (`cierre_turno`, `apertura_turno`, `pago`, `venta`, `admin_recepcion`), aparecen **`pedir_item`** y **`estado_comanda_item`** cuando los uses de verdad (sin `ROLLBACK`).

- [ ] 8.1 ⭐ Mismo `client_uuid` → mismo `id_item`, sin doble descuento, sin línea ni comanda nuevas
- [ ] 8.2 Cambio de estado offline idempotente
- [ ] 8.3 La cola sobrevive a cerrar la app; al volver la red no duplica
- [ ] 8.4 Tipos nuevos registrados

---

## § 9 · Fase 5b — Cierre de turno con comandas abiertas

Cerrar un turno con platos en cocina significa comida cocinada que nadie cobró, o comensales que siguen esperando.

### 9.1 Preparar el escenario

1. Con el **vendedor**, abre Mesa 1 y pide **croqueta ×1** (`al_pedido`, para que genere comanda).
2. **No la marques** en el KDS. Déjala pendiente.
3. **No cierres la cuenta.**

### 9.2 Intentar cerrar el turno

Ve a **Cierre de turno** y rellena el efectivo. Pulsa el botón de cerrar.

**Qué debe pasar:** antes de procesar nada aparece un **diálogo**:

- Título: **"Hay comandas sin servir"** con icono de cocina.
- El mensaje del servidor: *"1 comanda(s) sin servir en mesas sin cobrar"*.
- En **rojo**: "Ojo: hay mesas sin cobrar. Al cerrar el turno esa venta queda sin registrar."
- El detalle: `#1 · Mesa 1 · Pendiente · N min`.
- Dos botones: **Revisar cocina** / **Cerrar igual** (rojo).

### 9.3 "Revisar cocina" cancela el cierre

Pulsa **Revisar cocina**.

**Esperado:** el cierre **no se ejecuta**, vuelves a la pantalla. El turno sigue abierto.

### 9.4 Verificar por SQL lo que ve la app

```sql
SELECT public.fn_comandas_abiertas_turno(18);
```

**Esperado:** `total: 1`, `con_cuenta_abierta: 1`, **`bloquear: true`**, y el array `comandas` con mesa, zona, estado y `espera_minutos`.

### 9.5 Con la cuenta cobrada, ya no bloquea

1. Cobra la cuenta de Mesa 1 (con "Cobrar igual" en el diálogo de la nota).
2. La comanda sigue **sin servir** en el KDS.
3. Vuelve a consultar:

```sql
SELECT public.fn_comandas_abiertas_turno(18);
```

**Esperado:** `total: 1` (la comanda sigue viva) pero **`bloquear: false`**, con el mensaje *"1 comanda(s) sin servir, pero las cuentas ya se cerraron"*.

> **Por qué avisa y no bloquea:** una comanda sin servir cuya cuenta ya se cobró es un descuadre que hay que revisar, pero no impide cuadrar la caja. Y bloquear a secas dejaría al vendedor atrapado si la cocina se fue a su casa sin marcar los tickets. La RPC da el dato; la app elige la política.

### 9.6 Sin comandas pendientes, no molesta

1. En el **KDS**, marca todas las comandas como **entregadas**.
2. Intenta cerrar el turno.

**Esperado:** **no aparece ningún diálogo** de cocina. El cierre sigue su curso normal.

```sql
SELECT public.fn_comandas_abiertas_turno(18);
```
`total: 0`, `bloquear: false`, "No hay comandas pendientes en las cocinas de este TPV".

### 9.7 Solo alarma por las cocinas del TPV

Si tuvieras un segundo TPV ligado solo a Pizzería, una comanda de Pizzería **no** debería alarmar al cerrar el TPV 18.

Se puede verificar sin crear otro TPV: la consulta filtra por `app_dat_tpv_cocina`.

```sql
-- Comandas vivas de TODAS las cocinas de la tienda
SELECT co.id, co.numero, ck.denominacion AS cocina, co.estado
  FROM app_dat_comanda co JOIN app_dat_cocina ck ON ck.id = co.id_cocina
 WHERE ck.id_tienda = 11 AND co.estado IN (1,2,3);

-- Las que ve el cierre del TPV 18 (solo Cocina caliente)
SELECT (public.fn_comandas_abiertas_turno(18))->'total' AS ve_el_tpv_18;
```

### 9.8 Si la RPC falla, el cierre NO se bloquea

Este es un detalle de diseño importante: si no hay red o la cocina no está configurada, la consulta falla — y **el cierre debe seguir**. Cuadrar la caja no puede depender de que responda esa RPC.

No hay forma cómoda de forzarlo desde la app; queda documentado en el código (`_confirmarComandasPendientes` devuelve `true` en el `catch`).

- [ ] 9.2 Diálogo con detalle y aviso rojo
- [ ] 9.3 "Revisar cocina" cancela el cierre
- [ ] 9.4 `bloquear: true` con mesa sin cobrar
- [ ] 9.5 `bloquear: false` con la cuenta ya cobrada
- [ ] 9.6 Sin comandas pendientes no aparece el diálogo
- [ ] 9.7 Solo alarma por las cocinas ligadas al TPV

---

## § 10 · Permisos y aislamiento entre cocinas

Un jefe de la Cocina caliente **no** debe poder tocar la Pizzería, ni siquiera pasando el id a mano.

### 10.1 Preparar: personal en cada cocina

De §3 ya tienes un **jefe** y un **cocinero** en Cocina caliente. Añade un jefe en Pizzería:

```sql
SELECT public.fn_asignar_jefe_cocina('<UUID_JEFE_PIZZERIA>'::uuid, <ID_PIZZERIA>, <ID_TRAB_3>, true);
```

### 10.2 El KDS solo muestra "lo mío"

Login como **jefe de Cocina caliente** → **Cocina**.

**Esperado:** solo comandas de Cocina caliente. Si hay comandas de Pizzería, **no aparecen**.

> El KDS no pregunta "¿qué cocina quieres ver?", pregunta "¿qué es lo mío?". El alcance lo resuelve el backend con `fn_cocinas_del_usuario`, así que no se puede saltar desde el cliente.

### 10.3 Forzar el id de la cocina ajena

Como jefe de Cocina caliente, intenta listar la Pizzería:

```sql
BEGIN;
SELECT set_config('request.jwt.claims',
  json_build_object('sub','<UUID_JEFE_CALIENTE>','role','authenticated')::text, true);
SELECT public.fn_listar_comandas_cocina(<ID_PIZZERIA>);
ROLLBACK;
```

**Esperado:** **error de acceso denegado**. No una lista vacía: un rechazo.

### 10.4 Producir en la cocina ajena

```sql
BEGIN;
SELECT set_config('request.jwt.claims',
  json_build_object('sub','<UUID_JEFE_CALIENTE>','role','authenticated')::text, true);
SELECT public.fn_producir_tanda(<ID_PIZZERIA>, 220, 5);
ROLLBACK;
```

**Esperado:** rechazado por el guard.

### 10.5 Un cocinero NO puede producir

Login en la app como el **cocinero** (`es_jefe = false`) → **Producción**.

**Qué debe pasar:**
- Aparece un **aviso ámbar**: "Solo consulta: producir y cerrar lotes lo hace el jefe de cocina."
- Los botones **Producir** / **Cerrar lote** / **Anular** **no aparecen**.
- Pero **sí ve** el catálogo con las porciones hechas y el máximo producible.

> Sin ese aviso, el cocinero no vería los botones y pensaría que la app está rota.

Y por SQL:

```sql
BEGIN;
SELECT set_config('request.jwt.claims',
  json_build_object('sub','<UUID_COCINERO>','role','authenticated')::text, true);
SELECT public.fn_producir_tanda(<ID_COCINA_CALIENTE>, 219, 5);
ROLLBACK;
```
**Esperado:** `Acceso denegado: esta operacion requiere ser jefe de cocina`.

### 10.6 Un cocinero SÍ puede usar el KDS

Como cocinero → **Cocina**.

**Esperado:** ve y marca comandas de su cocina con normalidad. El KDS es su trabajo.

### 10.7 Un plato de otra cocina no se produce

Como **jefe de Cocina caliente**, intenta producir el pan de la casa (que es de Pizzería) **en tu propia cocina**:

```sql
BEGIN;
SELECT set_config('request.jwt.claims',
  json_build_object('sub','<UUID_JEFE_CALIENTE>','role','authenticated')::text, true);
SELECT public.fn_producir_tanda(<ID_COCINA_CALIENTE>, 220, 5);
ROLLBACK;
```

**Esperado:** `PLATO_OTRA_COCINA`.

### 10.8 Un plato `al_pedido` no se produce por tandas

```sql
-- Con un plato que esté en modo al_pedido
SELECT public.fn_producir_tanda(<ID_COCINA_CALIENTE>, 221, 5);
```

**Esperado:** `NO_ES_POR_TANDA`, con un mensaje que dice qué hacer: *"Cámbialo a 'por tanda' en la gestión de platos si se produce en lote."*

### 10.9 El gerente lo ve todo

Login como **gerente o supervisor** de la tienda 11 → **Cocina** y **Producción**.

**Esperado:** ve **las dos cocinas**. Si tienes más de una asignada, aparece un **selector de cocina** arriba (chips), con una **estrella** en las que eres jefe.

```sql
BEGIN;
SELECT set_config('request.jwt.claims',
  json_build_object('sub','<UUID_GERENTE>','role','authenticated')::text, true);
SELECT * FROM public.fn_cocinas_del_usuario();
ROLLBACK;
```
**Esperado:** las 2 cocinas, con `es_jefe = true` en ambas.

### 10.10 Un usuario sin cocinas

Login con un **vendedor normal** (sin asignación de cocina).

**Esperado:** las entradas **Cocina** y **Producción** **no aparecen** en el menú. Si llegara a la pantalla por ruta directa, vería "No tienes cocinas asignadas".

```sql
BEGIN;
SELECT set_config('request.jwt.claims',
  json_build_object('sub','11111111-2222-3333-4444-555555555555','role','authenticated')::text, true);
SELECT count(*) AS cocinas FROM public.fn_cocinas_del_usuario();
ROLLBACK;
```
**Esperado:** `0`.

- [ ] 10.2 KDS solo muestra la cocina propia
- [ ] 10.3 Forzar id de cocina ajena → rechazado
- [ ] 10.4 Producir en cocina ajena → rechazado
- [ ] 10.5 Cocinero: aviso ámbar, sin botones, RPC rechazada
- [ ] 10.6 Cocinero sí usa el KDS
- [ ] 10.7 `PLATO_OTRA_COCINA`
- [ ] 10.8 `NO_ES_POR_TANDA`
- [ ] 10.9 Gerente ve las dos cocinas con selector
- [ ] 10.10 Usuario sin cocinas no ve las entradas

---

## § 11 · No-regresión (que nada viejo se rompió)

Esta sección es tan importante como las anteriores. Se tocaron funciones que usan **todas** las tiendas, no solo las de restaurante: `fn_registrar_venta`, `fn_registrar_venta_mesa`, `check_user_has_access_to_tienda` y el catálogo del TPV.

### 11.1 ⭐ Venta normal de mostrador, con la cocina APAGADA

Este es el escenario del 99 % de las tiendas del sistema.

1. App **admin** → **Configuración Global** → **apaga `cocina_activa`**.
2. App **vendedor** → reinicia (el flag se cachea).
3. Vende un producto **normal** (pan solo, harina) de mostrador y cobra.

**Esperado:** funciona exactamente como antes. El stock baja del almacén del TPV al cobrar.

4. Vende un **elaborado** (croqueta) de mostrador y cobra.

**Esperado:** se descuenta la receta (harina −40, sal −10) al cobrar, del almacén correcto.

> Con `cocina_activa = false`, `OrderService.addItemToCurrentOrder` usa la rama vieja (`agregarItem`). El interruptor es un switch en el admin, no una línea de código: si algo va mal en producción, se apaga y todo vuelve al comportamiento anterior.

### 11.2 Los cinco roles anteriores siguen funcionando

Se añadió un 6.º UNION a `check_user_has_access_to_tienda`. Si eso se hubiera roto, **nadie** podría entrar a nada.

```sql
-- Cada rol debe seguir teniendo acceso a su tienda.
-- Sustituye los uuid por usuarios reales de cada tipo.
BEGIN;
CREATE TEMP TABLE res(rol text, acceso boolean) ON COMMIT DROP;

DO $$
DECLARE
  v_casos text[][] := ARRAY[
    ARRAY['vendedor',   '<UUID_VENDEDOR>',   '11'],
    ARRAY['almacenero', '<UUID_ALMACENERO>', '11'],
    ARRAY['supervisor', '<UUID_SUPERVISOR>', '11'],
    ARRAY['gerente',    '<UUID_GERENTE>',    '11'],
    ARRAY['jefe_cocina','<UUID_JEFE>',       '11']
  ];
  c text[];
BEGIN
  FOREACH c SLICE 1 IN ARRAY v_casos LOOP
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', c[2], 'role','authenticated')::text, true);
    BEGIN
      PERFORM public.check_user_has_access_to_tienda(c[3]::bigint);
      INSERT INTO res VALUES (c[1], true);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO res VALUES (c[1], false);
    END;
  END LOOP;
END $$;

SELECT * FROM res;
ROLLBACK;
```

**Esperado:** los 5 con `acceso = true`.

### 11.3 Un usuario ajeno sigue siendo rechazado

```sql
BEGIN;
SELECT set_config('request.jwt.claims',
  json_build_object('sub','11111111-2222-3333-4444-555555555555','role','authenticated')::text, true);
SELECT public.check_user_has_access_to_tienda(11);
ROLLBACK;
```

**Esperado:** **error de acceso denegado**. Si esto devuelve OK, el guard está roto y cualquiera lee cualquier tienda.

> ⚠️ **No uses un uuid real de la tienda como caso negativo.** En el desarrollo me equivoqué con esto: el uuid que usaba era gerente de 4 tiendas, así que su acceso era legítimo y parecía una regresión. Usa un uuid inventado.

### 11.4 El catálogo del TPV sin cocinas

En una tienda **sin cocinas** (la tienda 1, por ejemplo), el catálogo del TPV debe verse igual que siempre.

**Esperado:** los productos del almacén del TPV, sin chips, sin platos extra.

> El catálogo dual **no reemplazó** `get_productos_by_categoria_tpv_search_meta`. Se añadió `fn_productos_cocina_tpv` y la app concatena, degradando a lista vacía si falla. Una tienda sin cocinas ni se enteró del cambio.

### 11.5 Cuentas de mesa abiertas antes del cambio

Si tenías cuentas de mesa abiertas desde antes de aplicar el `13`, sus líneas tienen `stock_movido` en `NULL`.

```sql
SELECT i.id, i.id_producto, i.stock_movido, i.origen_stock
  FROM app_dat_mesa_cuenta_item i
 WHERE i.stock_movido IS NULL OR i.stock_movido = false
 ORDER BY i.id DESC LIMIT 10;
```

**Esperado:** al cobrar esas cuentas, el descuento ocurre **al cobrar** como siempre. `NULL`/`false` significa "línea legado, descuenta como antes".

Es la razón de existir de esa columna: no rompe lo que estaba a medias.

### 11.6 Recepción, conteo y transferencias

App **admin** → Inventario:

- [ ] Recepción de mercancía a un almacén normal
- [ ] Conteo / ajuste de inventario
- [ ] Transferencia entre almacenes

**Esperado:** todo funciona. Se creó una tabla nueva de cocinas y almacenes con `es_cocina = true`, pero no se cambió la mecánica de inventario.

### 11.7 Apertura y cierre de turno normales

En una tienda **sin cocinas**:

- [ ] Abrir turno
- [ ] Vender
- [ ] Cerrar turno

**Esperado:** sin diálogos nuevos. `fn_comandas_abiertas_turno` devuelve `total: 0` y la app no muestra nada.

### 11.8 Devolución / edición de orden pendiente

Esto tocaba la Fase 0 (`05`, `06`) y tenía el bug #2 (`fn_devolver_ingredientes_elaborado` fallaba en el 100 % de los casos por `id_presentacion`).

1. Crea una orden con un elaborado.
2. **Edítala**: quita o reduce la cantidad del elaborado.

**Esperado:** la materia prima **vuelve** al almacén correcto. Sin error `23502`.

```sql
-- Los movimientos de devolución por edición llevan origen_cambio = 3
SELECT ip.id, ip.id_producto, ip.cantidad_inicial, ip.cantidad_final, ip.created_at
  FROM app_dat_inventario_productos ip
 WHERE ip.origen_cambio = 3
 ORDER BY ip.id DESC LIMIT 10;
```

### 11.9 El analyzer no introdujo errores

```bash
cd C:/Users/cesar/Documents/VentIQ-seller-App/ventiq_app
export PATH="/c/Users/cesar/Documents/develop/flutter/bin:$PATH"
dart analyze lib/ 2>&1 | grep -cE "^\s*error"
```

**Esperado: `1`** — y es `dart:js_util` en `utils/package_image_picker_web.dart`, **preexistente y ajeno a cocina** (solo afecta a la build web).

Lo mismo en el admin:
```bash
cd ../ventiq_admin_app && dart analyze lib/ 2>&1 | grep -cE "^\s*error"
```

### 11.10 El SQL sigue siendo válido

```bash
cd C:/Users/cesar/Documents/VentIQ-seller-App
"$LOCALAPPDATA/Temp/vqsql/Scripts/python.exe" funcionalidad_cocina/_validar_sql.py
```

**Esperado:** `22/22 archivos validos`.

- [ ] 11.1 ⭐ Venta normal con cocina apagada = comportamiento de siempre
- [ ] 11.2 Los 5 roles anteriores conservan acceso
- [ ] 11.3 Usuario ajeno rechazado
- [ ] 11.4 Catálogo normal en tienda sin cocinas
- [ ] 11.5 Cuentas legado descuentan al cobrar
- [ ] 11.6 Recepción / conteo / transferencias OK
- [ ] 11.7 Turno normal sin diálogos nuevos
- [ ] 11.8 Devolución por edición sin error 23502
- [ ] 11.9 `dart analyze` = 1 error preexistente
- [ ] 11.10 `22/22 archivos validos`

---

## § 12 · Checklist final

### Por fase

| Fase | Qué se probó | § |
|------|--------------|---|
| 0 | Descuento de receta en el almacén correcto | 1 |
| 1 | Cocinas, TPV↔cocina, catálogo dual, chips | 2, 4 |
| 2 | Pedir mueve stock y crea comanda; cobrar no re-descuenta | 5 |
| 3 | Jefe/cocinero, KDS, transiciones, ticket | 3, 6 |
| 4 | Tandas, merma, anular, parada de BOM | 7 |
| 5 | Idempotencia offline, cola persistente, cierre de turno | 8, 9 |
| — | Permisos y aislamiento | 10 |
| — | No-regresión | 11 |

### Las 8 pruebas que no se pueden saltar

Si tienes poco tiempo, haz al menos estas:

1. **§5.8** — Cobrar no vuelve a descontar. *(Si falla: doble descuento en cada venta de mesa.)*
2. **§7.8** — Parada de BOM: `croqueta=2 [TANDA]`, no `harina=160`. *(Si falla: doble descuento en combos.)*
3. **§8.1** — Mismo `client_uuid` → mismo `id_item`, stock intacto. *(Si falla: cada reintento duplica el pedido.)*
4. **§10.3** — Jefe de cocina A no puede listar la cocina B. *(Si falla: el guard es decorativo.)*
5. **§6.6** — "Marchando todo" pone la cabecera en verde. *(Si falla: comandas atascadas para siempre.)*
6. **§7.11** — Anular una tanda ya servida se rechaza. *(Si falla: descuadre de inventario.)*
7. **§11.1** — Venta normal con cocina apagada. *(Si falla: se rompió el 99 % de las tiendas.)*
8. **§11.3** — Usuario ajeno rechazado. *(Si falla: fuga de datos entre tiendas.)*

### Pendientes conocidos (no son bugs)

| # | Qué falta | Alternativa hoy |
|---|-----------|-----------------|
| 1 | UI de admin para asignar jefe de cocina | SQL: `fn_asignar_jefe_cocina` (§3) |
| 2 | UI de impresión del ticket | Backend listo: `fn_ticket_comanda` (§6.11) |
| 3 | Recepción/conteo/transfer acotadas al almacén de la cocina | El jefe ve las pantallas de la tienda |
| 4 | Cocina por defecto por categoría (opcional) | Se asigna plato por plato |
| 5 | Enganche fino de la cola offline con cada pantalla | El servicio y las RPC están probados (§8.3) |

### Cómo reportar un fallo

Si algo no cuadra, dame estos cuatro datos y lo localizo rápido:

1. **Qué sección** (ej. §7.8).
2. **Qué esperabas y qué pasó.**
3. **Los ids** que anotaste: cocina, almacén, comanda, tanda.
4. **La consulta de stock** antes y después:

```sql
SELECT p.id, p.denominacion,
       public.fn_stock_producto_almacen(p.id, <ALM_CALIENTE>) AS cocina,
       public.fn_stock_producto_almacen(p.id, 12)             AS barra
  FROM app_dat_producto p
 WHERE p.id IN (216, 217, 218, 219, 220, 221)
 ORDER BY p.id;
```

Y si es un error de una RPC, el JSON completo que devolvió (trae `error_code` y `message`).

### Limpiar después de las pruebas

Las cocinas de prueba se pueden borrar (borrado suave, no se pierde histórico):

```sql
-- Ver qué hay antes de borrar
SELECT c.id, c.denominacion,
       (SELECT count(*) FROM app_dat_comanda co WHERE co.id_cocina = c.id) AS comandas,
       (SELECT count(*) FROM app_dat_produccion_tanda t WHERE t.id_cocina = c.id) AS tandas
  FROM app_dat_cocina c WHERE c.id_tienda = 11 AND c.deleted_at IS NULL;
```

Para dejar el sistema como estaba:

1. **Apaga `cocina_activa`** en Configuración Global. Con eso el comportamiento vuelve al de siempre sin tocar datos.
2. Devuelve `modo_elaboracion` de la croqueta a `al_pedido` si lo cambiaste.
3. Las cocinas puedes dejarlas: si `cocina_activa` está apagado, no afectan a nada.

> ⚠️ **No borres a mano las filas de `app_dat_inventario_productos`** generadas por las pruebas. El histórico de inventario se corrige por la vía normal (ajuste con trazabilidad), no con `DELETE`.

---

## Resumen de archivos

**SQL** (`funcionalidad_cocina/`, 22 archivos, todos aplicados):

| Archivo | Qué trae |
|---------|----------|
| `01`, `03`, `05`, `06` | Fase 0 · BOM por almacén, devoluciones |
| `07`–`11` | Fase 1 · cocinas, RPC, catálogo dual, venta enrutada |
| `13`, `14`, `17`, `18` | Fase 2 · comandas, pedir, cobro sin re-descontar |
| `15`, `16` | Fixes de bugs latentes de Fase 0 |
| `19`, `20` | Fase 3 · rol jefe de cocina, KDS |
| `21` | Fase 4 · tandas y parada de BOM |
| `22` | Fase 5 · offline, cierre de turno, ticket |
| `02`, `04`, `12` | Solo lectura (exports para inspección) |

**Dart nuevo** (`ventiq_app/lib/`):

`models/comanda.dart` · `models/tanda.dart` · `models/pedido_resultado.dart` · `services/comanda_service.dart` · `services/cocina_offline_queue.dart` · `screens/kds_screen.dart` · `screens/produccion_screen.dart` · `widgets/comanda_card.dart` · `widgets/tanda_widgets.dart` · `widgets/estado_servicio_chip.dart` · `widgets/cocina_chip.dart`

**Dart nuevo** (`ventiq_admin_app/lib/`):

`models/cocina.dart` · `services/cocina_service.dart` · `screens/cocinas_management_screen.dart` · `widgets/cocinas/` (4 archivos)

**Referencia:** `docs/PLAN_RESTAURANTE_COCINA.md` — checklist por fase, decisiones de diseño y la tabla de los 9 bugs encontrados.
