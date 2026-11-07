?# Plan: Cobro y contabilización multimoneda (CUP, USD y monedas nuevas)

**Estado:** propuesta para aprobación. **No implementado todavía.**
**Fecha:** 2026-11-04
**Apps implicadas:** `ventiq_app` (TPV vendedor) · `ventiq_admin_app` (Gestión) · `ventiq_superadmin` (Super Admin) · Supabase (esquema compartido)

### Documentos de soporte (recon de solo lectura, con evidencia `archivo:línea`)

| Documento | Qué contiene |
|---|---|
| [`docs/plan-multimoneda/recon-esquema.md`](docs/plan-multimoneda/recon-esquema.md) | DDL real de las tablas de moneda/tasas/pagos, RPCs de venta y caja, RLS, contradicciones del esquema |
| [`docs/plan-multimoneda/recon-ventiq_app.md`](docs/plan-multimoneda/recon-ventiq_app.md) | Flujo del cobro en el TPV, ~75 hardcodes CUP/USD, payloads exactos, caja/arqueo, offline |
| [`docs/plan-multimoneda/recon-admin-superadmin.md`](docs/plan-multimoneda/recon-admin-superadmin.md) | Contabilización del admin (todo RPC, CUP implícito), patrones CRUD del superadmin, seguridad |

---

## 0. Resumen ejecutivo

Hoy **ya se puede cobrar en USD**, y de hecho se hace: existen 7 pagos USD reales. Pero el sistema está construido como **"CUP + una excepción llamada USD"**, no como multimoneda:

- La moneda de un pago **sí** se guarda, en la línea de pago (`app_dat_pago_venta.moneda`), con `tasa_usd` y `monto_cup_equivalente`. La columna genérica existe; **la lógica que la usa no**.
- La base de datos **rechaza** cualquier moneda que no sea CUP o USD: `CHECK (moneda IN ('CUP','USD'))`.
- El núcleo de cálculo colapsa toda moneda distinta de USD a CUP: `price_utils.dart:136` → `raw == 'USD' ? 'USD' : 'CUP'`.
- El catálogo de monedas y las denominaciones **ya enumeran N monedas** (`app_dat_denominaciones_moneda.codigo_moneda`), pero **nadie las administra**: no hay pantalla en el superadmin ni DDL en el repo.
- El admin **ignora por completo** la moneda del pago: todos sus totales salen de RPC en CUP implícito y no lee `moneda`/`tasa_usd`/`monto_cup_equivalente`.

**Además hay un defecto contable activo hoy, independiente de este plan:** `fn_resumen_diario_cierre_v2` suma `pv.monto` **sin convertir ni filtrar por moneda** (`presentaciones_inventario/30_cierre_vendedor_v2.sql:255-278`). Un pago de 2 USD con tasa 550 entra a los totales CUP como `2`, no como `1100`. Cualquier cierre de turno con pagos USD está mal calculado.

**Objetivo de este plan:** convertir el modelo "CUP + excepción USD" en **multimoneda real con N monedas administrables desde el superadmin**, capaz de responder con exactitud *"¿cuánto se cobró en USD, cuánto en EUR, cuánto en CUP, y cuál es el total consolidado?"*, y reflejarlo en el admin.

**Idea central del diseño (mínima y retrocompatible):** la moneda nativa y el equivalente en moneda base **ya existen como columnas**; el único error es que el equivalente se calcula con una regla que solo entiende USD y que la moneda está restringida por un `CHECK`. Se generaliza **la tasa** (de `tasa_usd` a `tasa_cambio` para cualquier par) y se **elimina la restricción**, en vez de rediseñar el modelo desde cero.

---

## 1. Estado actual verificado

### 1.1 Dónde vive hoy la moneda

| Dato | Dónde | Evidencia |
|---|---|---|
| Moneda del pago | `app_dat_pago_venta.moneda` `TEXT NOT NULL DEFAULT 'CUP'` — **en la línea de pago**, no en la venta | `ventiq_app/sql/venta_usd.sql:2` |
| Tasa aplicada | `app_dat_pago_venta.tasa_usd` (solo USD; `NULL` en CUP) | `venta_usd.sql:3`, `:95` |
| Equivalente en CUP | `app_dat_pago_venta.monto_cup_equivalente` | `venta_usd.sql:4`, `:80` |
| Restricción de moneda | `CHECK (moneda IN ('CUP','USD'))` | `venta_usd.sql:16-19` |
| Moneda de la venta | **No existe**: es derivada de sus líneas de pago (una venta puede ser mixta) | `VentiQ.sql:401-425` |
| Moneda del medio de pago | **No existe**: no es atributo del método | `VentiQ.sql:1089-1097` |

**Consecuencia buena:** el diseño "moneda por línea de pago" ya es el correcto y soporta ventas mixtas. **No hay que cambiar el modelo de propiedad de la moneda.**

### 1.2 Los cuatro catálogos de moneda (incompatibles entre sí)

| Catálogo | Identidad | Alcance | Quién lo usa |
|---|---|---|---|
| `public.monedas` | `codigo` (texto, ISO) | Global | Admin (solo lectura/display); `tasas_conversion` le hace FK |
| `public.tipos_moneda` | `id` (`1`=CUP, `2`=USD) | Global | **UI de tasas por tienda del admin**; `tasa_cambio_extraoficial` le hace FK |
| `public.tasa_cambio_extraoficial` | par de **ids** int + `id_tienda` | **Por tienda** | `CurrencyService` del TPV (la tasa que realmente se usa al cobrar) |
| `public.dep_nom_moneda` / `prv_nom_moneda` | `codigo` texto | Global | Módulos de depósitos y pago a proveedores (CRUD propio) |
| *(el pago)* | texto `'CUP'`/`'USD'` | — | **Sin FK a ninguno** |

**Hay tres espacios de identidad distintos y ningún mapeo entre ellos.** *(Verificado en Fase 0: `monedas.codigo` es realmente `character(3)`, así que **sí** admite `'USD'` — el volcado `VentiQ.sql` del repo perdía el `(3)`. No hace falta `ALTER COLUMN`.)*

### 1.3 Cómo se calcula hoy (y por qué es binario)

```
Cobro (checkout_screen.dart)
  ├─ toggle binario ['CUP','USD'] ................. checkout_screen.dart:898
  ├─ monto USD = cupAmount / _usdRate ............. checkout_screen.dart:480
  └─ pago = {moneda, tasa_usd, monto} ............. checkout_screen.dart:474

Persistencia (fn_registrar_pago_venta)
  ├─ moneda := CASE WHEN 'USD' THEN 'USD' ELSE 'CUP'   ← coacciona TODO lo demás
  ├─ monto_cup := CASE WHEN 'USD' THEN monto*tasa ELSE monto  ← asume que no-USD ya es CUP
  └─ CHECK (moneda IN ('CUP','USD'))                    ← rechaza cualquier otra

Lectura y arqueo
  ├─ PriceUtils.paymentCurrency: 'USD' ? 'USD' : 'CUP'   price_utils.dart:136
  ├─ conteo de billetes: if USD → convierte; else → suma como CUP
  └─ cierre: if USD → cubo USD; else → cubo CUP
```

**Resultado:** si el superadmin creara `EUR`, el desplegable de monedas lo mostraría, pero el importe se **sumaría y se guardaría como CUP**. La moneda no se pierde "por un detalle de UI": se pierde en la aritmética y en el `CHECK`.

### 1.4 Lo que el admin muestra hoy

- Todos los agregados de ventas vienen de RPC SQL (`fn_reporte_ventas_ganancias`, `fn_reporte_ventas_por_turno`, `fn_listar_turnos_admin`, `fn_reporte_ventas_con_proveedor5`...), **ninguno devuelve moneda**.
- No hay `moneda` en ningún modelo ni pantalla de venta del admin; los importes se muestran con `$` sin código.
- `CajaTurno` (`ventiq_admin_app/lib/models/caja_turno.dart:205-435`) **no tiene** los campos `_usd` que sí existen en la BD.
- El admin nunca lee `app_dat_pago_venta.moneda` (selecciona solo `monto` y el método: `sales_service.dart:593-598`).
- El superadmin **no tiene** pantalla ni servicio de monedas (búsqueda negativa verificada).

### 1.5 Verificación en vivo (Fase 0 — **EJECUTADA** 2026-11-04)

Diagnóstico corrido contra la base real (usuario `supabase_read_only_user`, PostgreSQL 17.4). Resultado completo en [`docs/plan-multimoneda/diagnostico-resultado.md`](docs/plan-multimoneda/diagnostico-resultado.md). Lo que cambia respecto de lo deducido del repo:

| Hallazgo | Antes (repo) | Ahora (base real) |
|---|---|---|
| `monedas.codigo` | `bpchar(1)`, no cabe `'USD'` → `ALTER COLUMN` necesario | **`character(3)`** → el `ALTER` **se elimina** |
| `CHECK (moneda IN ('CUP','USD'))` | deducido | **CONFIRMADO**, existe en producción |
| RLS de catálogos de moneda | "no hay políticas en el repo" | **RLS activo con políticas permisivas**: `authenticated ALL USING(true) WITH CHECK(true)` en las 5 tablas → **cualquier trabajador de tienda puede crear monedas y cambiar la tasa global** |
| `tipos_moneda` | id + denominación (2 filas) | Confirmado: `id bigint`, 2 filas (`1`=CUP, `2`=USD), **sin `codigo`** |
| `tasa_cambio_extraoficial` | por tienda, ids | Confirmado: 73 filas, todas USD(2)→CUP(1) |
| `tasas_conversion` | global | 1 fila: USD→CUP = 900 |
| Denominaciones | `codigo_moneda` string | `varchar(10)`; CUP 14 y USD 6 |
| Caja USD | columnas `*_usd` | Existen, pero **0 de 3.385 turnos** usan inicial USD y solo **1** tiene cierre USD → migrar es casi greenfield |
| Helpers de RLS | en el repo | **Existen en producción** y son `SECURITY DEFINER`: `fn_is_superadmin_full_access()`, `fn_user_can_access_tienda()`, `fn_get_tienda_by_operacion_venta()` |

**Hallazgo nuevo y grave — `monto_cup_equivalente` no es fiable (ver §1.6).**

### 1.6 Defecto de datos en `monto_cup_equivalente` (**bloquea la Fase 3 si no se repara**)

De 129.331 pagos CUP:

- **666 filas con `monto_cup_equivalente` NULL.**
- **97 filas donde el equivalente es el total de la operación** mientras `monto` es solo una parte (granularidad equivocada).
- **664 operaciones** con al menos una fila NULL; en **548 de ellas los totales descuadran hoy**.
- `monto` acumulado en esas 664 operaciones: **133.304.184**; equivalente registrado: **3.781.280** → del orden de **129 millones de CUP sin equivalente**.

Consecuencia: **cualquier reporte que sume `monto_cup_equivalente` subestima.**

**Cómo se repara (importante, no como decía la versión anterior de este plan):** la reparación correcta es **recalcular fila por fila** `monto_cup_equivalente = round(monto * COALESCE(tasa_cambio,1), 2)`. Eso arregla a la vez los 666 NULL **y** las 97 filas que hoy llevan el total de la operación. Lo que **no** hay que hacer es un backfill *parcial* (rellenar solo los NULL copiando `monto`): en las 116 operaciones donde el total inflado ya vive en una fila hermana, eso dejaría la suma al doble. El recalculo completo es determinista y no depende de lo que hubiera antes.

**Causa raíz: NO identificada, y con una corrección importante.** El plan afirmaba que `fn_registrar_pago_venta_offline` no escribía `monto_cup_equivalente`. **Es falso**: en la BD desplegada esa función **delega** en `fn_registrar_pago_venta`, que sí lo escribe. La comprobación original buscó la cadena en el cuerpo del *wrapper* (donde no aparece) y dio un **falso negativo**; se verificó leyendo la definición real con `pg_get_functiondef`.

La auditoría de la Fase 3 propuso dos candidatos. **Uno está confirmado y cuantificado** con consulta a producción (2026-11-04):

| Origen | Filas NULL | Evidencia |
|---|---:|---|
| `INSERT` de «Ajuste Inventtia Caja» (`order_service`, mover montos) | **51** | 93 filas creadas con `referencia_pago = 'Ajuste Inventtia Caja…'`; **51 de ellas sin equivalente**. Antes el `INSERT` omitía `moneda` (tomaba el DEFAULT `'CUP'`) y `monto_cup_equivalente` (quedaba NULL). |
| Desconocido | **550** | `referencia_pago IS NULL`: no vienen de ese camino. Sigue sin identificarse. |

Ese `INSERT` **ya está corregido** (paso 4c): ahora declara `moneda` y calcula el equivalente. También se corrigió el `UPDATE` que bajaba `monto` sin tocar el equivalente — el otro síntoma observado (una fila con el total de la operación).

Queda pendiente identificar el camino que genera los **550 restantes** antes de la reparación (§4.4.1). Los arreglos 4a/4c/4d detienen la generación de nuevos casos, que es el requisito previo.

**✅ REPARADO Y BLINDADO en producción el 2026-11-05.** Estado medido antes: 675 filas
CUP con equivalente NULL (131.461.881 CUP invisibles) y 372 descuadradas. Después:
**0 NULL, 0 sin `tasa_cambio`, 0 descuadradas** sobre 129.695 pagos, con respaldo en
`app_dat_pago_venta_bkp_equiv` (revertible). Se hizo en dos capas:

1. **Prevención — trigger `trg_pago_venta_equivalente`** (BEFORE INSERT OR UPDATE):
   calcula `monto_cup_equivalente = monto × tasa` siempre. La razón de fondo: hay
   **12 funciones** que insertan en `app_dat_pago_venta` (las 3 de pago, las 4 de
   venta, 2 de orden pendiente, CxC y devoluciones); auditar 12 caminos a mano se
   vuelve a romper con el 13.º. Probado: rellena NULL, **corrige valores mal puestos**,
   rellena `tasa_cambio`/`tasa_usd` legacy y **no inventa** si una divisa no tiene tasa.
2. **Reparación — recálculo determinista** por fila (`monto × tasa`, sin redondear para
   no romper `es_pagada`), no un backfill de NULL: en las filas que llevaban el total de
   la operación, rellenar solo los NULL habría duplicado la suma.

Fichero: [`r11_reparacion_equivalente.sql`](docs/plan-multimoneda/r11_reparacion_equivalente.sql).
**A partir de aquí `monto_cup_equivalente` es fiable y la Fase 5 puede sumarlo.**

---

## 2. Objetivo y alcance

### 2.1 En alcance

1. **Cobrar en N monedas** en el TPV: cada línea de pago elige su moneda entre las habilitadas para la tienda (CUP, USD y las que cree el superadmin).
2. **Catálogo global de monedas administrable desde el superadmin** (crear, editar, activar/desactivar), con sus denominaciones.
3. **Habilitación de monedas por tienda** y **tasas por tienda** para cualquier par.
4. **Contabilización exacta**: por cada moneda → cuántas operaciones, cuánto se cobró en esa moneda (nativo) y su equivalente en moneda base; y totales consolidados.
5. **Reflejo en el admin**: desglose por moneda en ventas, turnos/cierres y reportes, con exportación.
6. **Caja/arqueo multimoneda** en apertura y cierre de turno.
7. **Corregir el defecto contable actual** de `fn_resumen_diario_cierre_v2` (USD sumado como CUP).
8. **Offline**: el cobro y el cierre offline llevan la moneda de cada línea; sincronización y migración de pendientes existentes.
9. **Contabilidad financiera multimoneda** completa: `fn_profit_and_loss`, márgenes, punto de equilibrio, flujo de caja, presupuestos y comparativos históricos (~14 RPC hoy en CUP implícito). **Confirmado: va incluido, no se difiere.**
10. **Convergencia de catálogos de moneda**: `dep_nom_moneda` y `prv_nom_moneda` pasan a referenciar el catálogo canónico `monedas`, dejando de ser islas.
11. **Endurecimiento de seguridad** del catálogo global (RLS real y rotación de la clave `service_role` expuesta en el cliente).

### 2.2 Fuera de alcance (explícito, para no confundir)

> **Decisión confirmada: no se difiere nada de lo que corresponde a este producto.** Todo lo relativo a moneda en TPV, caja, contabilidad financiera y catálogos está en alcance y se ejecuta fase a fase (§8). Lo que queda fuera es por **frontera de producto**, no por aplazamiento.

- **Carnaval / comercio electrónico** (`totalUsd`, `totalEuro` de pedidos Carnaval), **suscripciones** (`app_suscripciones_plan.moneda`), **referidos**, **paquetería**, **Muévete**: tienen su propia noción de moneda y **son productos distintos**; no se tocan. Donde sea trivial, consumirán el catálogo unificado en la Fase 7.
- **Conversión automática de precios de catálogo**: los precios siguen en `precio_venta_cup` con la excepción USD ya existente (`precio_venta_usd`). Esto es una **regla de negocio** (precio fijado en CUP), no una limitación técnica. Si más adelante quieres precio por moneda arbitraría, es otro plan.
- **Vuelto (cambio) automático en moneda cruzada**: se mantiene el criterio actual — el cajero ajusta montos manualmente (`tasks/plan_venta_usd.md:98`). Es una **regla operativa**, no deuda técnica.

---

## 3. Decisiones

### 3.1 Decisiones de arquitectura (recomendadas, con alternativa descartada)

| # | Decisión | Justificación |
|---|---|---|
| **D1** | **La moneda base contable sigue siendo CUP.** Se añade el concepto de *equivalente en moneda base*, que es exactamente `monto_cup_equivalente` ya existente. | Todos los precios están en `precio_venta_cup` y el 100% de los reportes existentes son CUP. Cambiar la base obligaría a reconvertir toda la contabilidad histórica. **Descartado:** base = USD (rompe 121.877 filas y todos los reportes). |
| **D2** | **Se generaliza la tasa**, no el modelo: `tasa_usd` pasa a tener un hermano genérico `tasa_cambio` (moneda nativa → CUP). `tasa_usd` se mantiene como columna legacy para no romper apps desplegadas. | Cambio puramente aditivo. La lógica `monto_cup_equivalente = monto * tasa` ya es correcta para *cualquier* moneda; solo hay que alimentarla con la tasa correcta. |
| **D3** | **La identidad canónica de moneda es el código ISO (`'CUP'`, `'USD'`, `'EUR'`…)**, porque es lo que el pago ya guarda y a lo que `tasas_conversion` ya hace FK. | Evita migrar el histórico de pagos. `tipos_moneda` (ids enteros) se conserva y se le añade `codigo` para tender un puente: `tasa_cambio_extraoficial` sigue usando ids y **no** se migra. |
| **D4** | **El superadmin administra el catálogo global y las tasas globales; el admin administra las tasas por tienda y qué monedas acepta cada tienda.** | Respeta la separación de responsabilidades que ya existe (`PersonalRatesTabView` en el admin ya gestiona tasas por tienda) y evita duplicar UI. |
| **D5** | **El `CHECK (moneda IN ('CUP','USD'))` se elimina** y la validación se hace contra el catálogo en la RPC (moneda activa + habilitada para la tienda + tasa > 0 si no es base). | Un `CHECK` con lista fija es exactamente lo que impide monedas nuevas. |
| **D6** | **La caja deja de usar columnas `*_usd` fijas** y pasa a una tabla hija por moneda. | `efectivo_inicial_usd`, `efectivo_real_usd`, `diferencia_usd` no escalan a N monedas. Las columnas legacy se conservan y se siguen escribiendo para la app vieja. |
| **D7** | **Compatibilidad total hacia atrás**: columnas nuevas con `DEFAULT`, parámetros de RPC nuevos con `DEFAULT NULL`, RPC nuevas como *sobrecargas* (`_v3`, `_v4`) sin tocar las actuales. | Permite desplegar la migración antes de actualizar las apps y convivir con versiones antiguas instaladas. |

### 3.2 Decisiones de negocio — **CONFIRMADAS (2026-11-04)**

| # | Decisión | Elección confirmada | Consecuencia |
|---|---|---|---|
| **B1** | Moneda base contable | **CUP**, más desglose por moneda nativa y totales en USD bajo demanda | Se conservan precios, histórico y reportes. §3.1-D1 aplica tal cual. |
| **B2** | Quién habilita monedas por tienda | **El admin, por tienda**; el superadmin solo administra el catálogo global | `app_dat_tienda_moneda` (§4.5) + pantalla en Ajustes del admin. |
| **B3** | "Cuántas se pagaron en USD" | **Operaciones e importe** (nativo + equivalente) | `fn_reporte_ventas_por_moneda` (§5.4) devuelve ambas. |
| **B4** | Cobrar en moneda sin tasa | **Bloqueado** con aviso al cajero | Validación en RPC + UI (§5.1). |
| **B5** | Alcance | **Todo el producto, fase a fase, sin diferir nada** | Contabilidad financiera (Fase 6) y convergencia de catálogos (Fase 7) **entran en el plan**. §2.2 reducido a fronteras de producto. |

**Fase 0** queda pendiente de acceso a la base: el MCP de Supabase devuelve `fetch failed`. Se entrega el SQL de diagnóstico listo para ejecutar (`docs/plan-multimoneda/diagnostico_fase0.sql`); en cuanto haya resultados se ajustan las migraciones de la Fase 1.

---

## 4. Modelo de datos objetivo

Los cambios son **aditivos**. Nada se elimina en esta fase.

### 4.1 `public.monedas` — catálogo global canónico

```sql
-- VERIFICADO en Fase 0: `codigo` YA es `character(3)` (bpchar(3)) y admite 'USD'.
-- El volcado VentiQ.sql del repo perdía el `(3)`. NO hace falta ALTER COLUMN.
-- Nota: al ser bpchar rellena con espacios; los códigos ISO-4217 son siempre 3 letras, encaja.

ALTER TABLE public.monedas
  ADD COLUMN IF NOT EXISTS decimales  smallint NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS orden      smallint NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS es_base    boolean  NOT NULL DEFAULT false,  -- CUP = true
  ADD COLUMN IF NOT EXISTS es_sistema boolean  NOT NULL DEFAULT false;  -- protege CUP/USD de borrado

-- Solo una moneda base
CREATE UNIQUE INDEX IF NOT EXISTS ux_monedas_una_base
  ON public.monedas ((es_base)) WHERE es_base;
```

### 4.2 `public.tipos_moneda` — puente con las tasas por tienda

```sql
-- `tasa_cambio_extraoficial` referencia tipos_moneda(id) y NO se migra.
-- Se añade el código para poder mapear id <-> código sin tocar el histórico.
ALTER TABLE public.tipos_moneda
  ADD COLUMN IF NOT EXISTS codigo character varying(3);

UPDATE public.tipos_moneda SET codigo = 'CUP' WHERE id = 1 AND codigo IS NULL;
UPDATE public.tipos_moneda SET codigo = 'USD' WHERE id = 2 AND codigo IS NULL;

ALTER TABLE public.tipos_moneda
  ADD CONSTRAINT tipos_moneda_codigo_fkey FOREIGN KEY (codigo) REFERENCES public.monedas(codigo);
CREATE UNIQUE INDEX IF NOT EXISTS ux_tipos_moneda_codigo ON public.tipos_moneda (codigo);
```

> **Regla de oro:** crear una moneda = insertar en `monedas` **y** en `tipos_moneda` en la misma transacción (RPC `fn_crear_moneda`, §5). Si una existe y la otra no, la moneda no sirve para cobrar.

### 4.3 Tasas por tienda para cualquier par — `public.fn_tasa_cambio(...)`

Se **reutiliza** `tasa_cambio_extraoficial` (que ya es por tienda y ya soporta pares por id). Lo único que falta es poder resolver el par por **código**, para lo que ya tenemos el puente de §4.2.

```sql
CREATE OR REPLACE FUNCTION public.fn_tasa_cambio(
  p_moneda_origen  text,
  p_moneda_destino text DEFAULT 'CUP',
  p_id_tienda      bigint DEFAULT NULL,
  p_fecha          timestamptz DEFAULT now()
) RETURNS numeric
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_id_origen  int;
  v_id_destino int;
  v_tasa       numeric;
BEGIN
  IF upper(p_moneda_origen) = upper(p_moneda_destino) THEN
    RETURN 1;
  END IF;

  SELECT id INTO v_id_origen  FROM public.tipos_moneda WHERE codigo = upper(p_moneda_origen);
  SELECT id INTO v_id_destino FROM public.tipos_moneda WHERE codigo = upper(p_moneda_destino);
  IF v_id_origen IS NULL OR v_id_destino IS NULL THEN
    RETURN NULL;
  END IF;

  -- 1) Tasa por tienda, la más reciente vigente a la fecha
  IF p_id_tienda IS NOT NULL THEN
    SELECT valor_cambio INTO v_tasa
    FROM public.tasa_cambio_extraoficial
    WHERE id_tienda = p_id_tienda
      AND id_moneda_origen = v_id_origen
      AND id_moneda_destino = v_id_destino
      AND activo
      AND created_at <= p_fecha
    ORDER BY created_at DESC
    LIMIT 1;
    IF v_tasa IS NOT NULL AND v_tasa > 0 THEN
      RETURN v_tasa;
    END IF;
  END IF;

  -- 2) Tasa global
  SELECT tasa INTO v_tasa
  FROM public.tasas_conversion
  WHERE moneda_origen = upper(p_moneda_origen)
    AND moneda_destino = upper(p_moneda_destino)
    AND fecha_actualizacion <= p_fecha
  ORDER BY fecha_actualizacion DESC
  LIMIT 1;

  RETURN NULLIF(v_tasa, 0);
END;
$$;
```

### 4.4 `public.app_dat_pago_venta` — pago multimoneda

```sql
-- 1) Fuera la lista fija de monedas
ALTER TABLE public.app_dat_pago_venta
  DROP CONSTRAINT IF EXISTS app_dat_pago_venta_moneda_check;

-- 2) Tasa genérica (moneda nativa -> CUP). Aditiva: `tasa_usd` se conserva.
ALTER TABLE public.app_dat_pago_venta
  ADD COLUMN IF NOT EXISTS tasa_cambio numeric;

UPDATE public.app_dat_pago_venta
SET tasa_cambio = COALESCE(tasa_usd, 1)
WHERE tasa_cambio IS NULL;

-- 3) Tipo de `moneda`: TEXT -> varchar(3), necesario para poder referenciar
--    monedas(codigo), que es bpchar(3). Coste trivial (129.331 filas).
ALTER TABLE public.app_dat_pago_venta
  ALTER COLUMN moneda TYPE character varying(3);

-- 4) Integridad referencial: la moneda debe existir en el catálogo.
ALTER TABLE public.app_dat_pago_venta
  ADD CONSTRAINT app_dat_pago_venta_moneda_fkey
  FOREIGN KEY (moneda) REFERENCES public.monedas(codigo);

-- 5) RECÁLCULO del equivalente. Va en script aparte y con validación previa (ver §4.4.1).
--    NO se ejecuta a ciegas: primero se mide, luego se aplica.
```

### 4.4.1 Reparación de `monto_cup_equivalente` (obligatoria antes de la Fase 5)

Orden estricto, en `newa` primero:

```sql
-- PASO A — medir (solo lectura): ¿cuánto descuadra y en qué operaciones?
WITH por_op AS (
  SELECT pv.id_operacion_venta,
         ov.importe_total,
         sum(pv.monto)                                        AS sum_monto,
         sum(round(pv.monto * COALESCE(pv.tasa_cambio,1), 2))  AS sum_recalculado,
         sum(COALESCE(pv.monto_cup_equivalente, 0))            AS sum_actual
  FROM public.app_dat_pago_venta pv
  JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = pv.id_operacion_venta
  GROUP BY 1, 2
)
SELECT
  count(*)                                                   AS operaciones,
  count(*) FILTER (WHERE sum_recalculado = importe_total)     AS recalculo_cuadra,
  count(*) FILTER (WHERE sum_actual       = importe_total)     AS actual_cuadra,
  count(*) FILTER (WHERE sum_recalculado <> importe_total)     AS requieren_revision
FROM por_op;

-- PASO B — snapshot de seguridad de las filas que se van a tocar
CREATE TABLE IF NOT EXISTS public.app_dat_pago_venta_bkp_equiv AS
SELECT id, moneda, monto, tasa_usd, monto_cup_equivalente, now() AS respaldado_en
FROM public.app_dat_pago_venta
WHERE monto_cup_equivalente IS DISTINCT FROM round(monto * COALESCE(tasa_cambio,1), 2);

-- PASO C — recalcular fila por fila (determinista, no depende del valor previo)
UPDATE public.app_dat_pago_venta
SET monto_cup_equivalente = round(monto * COALESCE(tasa_cambio, 1), 2)
WHERE monto_cup_equivalente IS DISTINCT FROM round(monto * COALESCE(tasa_cambio, 1), 2);

-- PASO D — verificar: el total debe cuadrar ahora en el mismo número de operaciones
--          que el PASO A calculó para sum_recalculado. Si no, revertir desde la copia B.
```

**Lo que este recálculo NO arregla** (y hay que decir explícitamente): las operaciones cuyo `sum(monto)` no cuadra con `importe_total` (~1.362 mediciones en producción, ver Fase 0). Eso es un **desajuste de negocio previo** (descuentos, pagos parciales, ediciones de orden), no un problema de moneda. Se entrega como **lista de revisión** para el admin, no se corrige a ciegas.

**Y se debe cerrar el agujero de código:** `fn_registrar_pago_venta_offline` **no escribe** `monto_cup_equivalente`. Debe escribirlo, o el problema vuelve a generarse.

**Invariantes que el modelo garantiza a partir de aquí:**

| Invariante | Significado |
|---|---|
| `moneda` + `monto` | **Fuente de verdad** de lo que el cliente entregó. Sumar por `moneda` da el total exacto por divisa, **sin conversión**. |
| `tasa_cambio` | Tasa aplicada en el instante del cobro (nativa → CUP). Congelada: si mañana cambia la tasa, el histórico no se mueve. |
| `monto_cup_equivalente` | `monto * tasa_cambio` (o `monto` si la moneda es CUP). Es el importe consolidable en moneda base. **Ya existe y ya es genérico**; solo se alimentaba mal. |
| `tasa_usd` (legacy) | Se sigue escribiendo cuando `moneda='USD'` para no romper consumidores antiguos. |

### 4.5 `public.app_dat_tienda_moneda` — qué monedas acepta cada tienda

Sustituye funcionalmente al flag booleano `mostrar_selector_moneda`, que no distingue monedas.

```sql
CREATE TABLE IF NOT EXISTS public.app_dat_tienda_moneda (
  id_tienda bigint  NOT NULL REFERENCES public.app_dat_tienda(id) ON DELETE CASCADE,
  moneda    character varying(3) NOT NULL REFERENCES public.monedas(codigo),
  activo    boolean NOT NULL DEFAULT true,
  orden     smallint NOT NULL DEFAULT 100,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id_tienda, moneda)
);

-- Semilla: toda tienda existente acepta CUP y USD (comportamiento actual)
INSERT INTO public.app_dat_tienda_moneda (id_tienda, moneda, activo, orden)
SELECT t.id, m.codigo, true,
       CASE m.codigo WHEN 'CUP' THEN 10 WHEN 'USD' THEN 20 ELSE 100 END
FROM public.app_dat_tienda t
CROSS JOIN public.monedas m
WHERE m.codigo IN ('CUP','USD')
ON CONFLICT DO NOTHING;
```

### 4.6 `public.app_dat_caja_turno_moneda` — arqueo multimoneda

```sql
CREATE TABLE IF NOT EXISTS public.app_dat_caja_turno_moneda (
  id_turno        bigint NOT NULL REFERENCES public.app_dat_caja_turno(id) ON DELETE CASCADE,
  moneda          character varying(3) NOT NULL REFERENCES public.monedas(codigo),
  efectivo_inicial numeric DEFAULT 0,
  efectivo_esperado numeric DEFAULT 0,
  efectivo_real   numeric,
  diferencia      numeric GENERATED ALWAYS AS (efectivo_real - efectivo_esperado) STORED,
  PRIMARY KEY (id_turno, moneda)
);

-- Backfill desde las columnas USD legacy
INSERT INTO public.app_dat_caja_turno_moneda (id_turno, moneda, efectivo_inicial, efectivo_real)
SELECT id, 'USD', COALESCE(efectivo_inicial_usd, 0), efectivo_real_usd
FROM public.app_dat_caja_turno
WHERE COALESCE(efectivo_inicial_usd, 0) <> 0 OR efectivo_real_usd IS NOT NULL
ON CONFLICT DO NOTHING;
```

### 4.7 RLS de los catálogos (hueco real: **demasiado abierto**, no ausente)

**Verificado en Fase 0.** RLS **está habilitado** en las 5 tablas, pero con políticas **permisivas** que permiten a *cualquier* usuario autenticado escribir el catálogo global y la tasa global:

| tabla | política actual |
|---|---|
| `monedas` | `monedas_authenticated_all` — `ALL` a `authenticated` `USING(true) WITH CHECK(true)` |
| `tipos_moneda` | `tipos_moneda_authenticated_all` — ídem |
| `tasas_conversion` | `tasas_conversion_authenticated_all` — ídem |
| `tasa_cambio_extraoficial` | `tasa_cambio_extraoficial_authenticated_all` — ídem |
| `app_dat_denominaciones_moneda` | `app_dat_denominaciones_moneda_authenticated_all` — ídem |

**Consecuencia:** hoy un trabajador de tienda puede crear monedas y cambiar la tasa de **todas** las tiendas. No hay que "añadir RLS", hay que **sustituir** las políticas.

```sql
-- Lectura abierta a autenticados + escritura solo superadmin.
-- Se ELIMINAN las políticas permisivas existentes (nombres verificados en producción).
DROP POLICY IF EXISTS monedas_authenticated_all               ON public.monedas;
DROP POLICY IF EXISTS tipos_moneda_authenticated_all          ON public.tipos_moneda;
DROP POLICY IF EXISTS tasas_conversion_authenticated_all      ON public.tasas_conversion;
DROP POLICY IF EXISTS app_dat_denominaciones_moneda_authenticated_all
  ON public.app_dat_denominaciones_moneda;

CREATE POLICY monedas_lectura ON public.monedas
  FOR SELECT TO authenticated USING (true);
CREATE POLICY monedas_escritura_superadmin ON public.monedas
  FOR ALL TO authenticated
  USING (public.fn_is_superadmin_full_access())
  WITH CHECK (public.fn_is_superadmin_full_access());

-- Repetir el mismo par (lectura / escritura_superadmin) en:
--   public.tipos_moneda, public.tasas_conversion, public.app_dat_denominaciones_moneda
```

Para `tasa_cambio_extraoficial` **no** se aplica el patrón superadmin: la tasa es **por tienda**, así que la escritura se restringe a la tienda del usuario con `public.fn_user_can_access_tienda(id_tienda)` — eso cierra además el `UPDATE` global indebido que hoy hace el admin (§9).

> **Advertencia de alcance:** mientras las apps sigan distribuyendo la clave `service_role` en el cliente (Fase 8), estas políticas **no protegen en release**. Son necesarias pero no suficientes.

### 4.8 Tasa automática («el toque») — reutiliza la infraestructura de `flow`

**Verificado en newa (2026-11-04).** El esquema `flow` (de `inventtia_flow`) ya vive en **este mismo proyecto** y aporta todo lo necesario:

| Pieza | Qué hace |
|---|---|
| `flow.tasa_cambio` | caché diaria: `fecha`, `hora`, `fuente`, `tasas` (jsonb), `conversiones` (jsonb) |
| `flow.tasa_factor(origen, destino)` | factor entre dos monedas, cruzando por CUP |
| `flow.tasas_actuales()` | estado de la caché (`vigente` = ¿es de hoy?) |
| `flow.tasas_refrescar(forzar)` | pide la tasa al proveedor vía `pg_net` (asíncrono) |
| `flow.tasas_ingest(request_id)` | recoge la respuesta y cachea (idempotente) |

**La Edge Function `flow-tasas` NO está desplegada** (comprobado con `list_edge_functions`); el archivo existe en `inventtia_flow/docs/flow_schema/edge_functions/flow-tasas/index.ts` pero nunca se desplegó. **No hace falta**: el camino `pg_net` funciona y se verificó de punta a punta (HTTP 200 del proveedor → ingesta → caché fresca).

#### Wrappers en `public` (aislamiento)

`public` **no** llama a `flow` directamente. Se exponen wrappers `SECURITY DEFINER` que degradan a `NULL` si `flow` no existe, para que el TPV nunca se rompa por una tasa automática no disponible:

| Función | Devuelve |
|---|---|
| `fn_tasa_automatica(origen, destino)` | `numeric` o `NULL` |
| `fn_tasa_automatica_estado()` | `{disponible, ok, fecha, hora, fuente, actualizado, vigente, tasas_cup:{USD,EUR,MLC}, monedas_cubiertas}` |
| `fn_tasas_refrescar(forzar)` | dispara y vuelve: `{estado:'solicitado', request_id}` o el estado si ya era vigente |
| `fn_tasas_ingerir()` | recoge respuestas pendientes: estado + `{ingeridos, pendientes_procesados}` |

#### Precedencia de `fn_tasa_cambio` (actualizada)

1. Tasa **de la tienda** (`tasa_cambio_extraoficial`, manual)
2. Tasa **global** (`tasas_conversion`, manual)
3. Tasa **automática** («el toque») ← **nuevo**
4. `NULL` → cobrar en esa moneda se bloquea

**La manual siempre gana.** Para que una moneda use la automática basta con **no** configurarle tasa manual. Instalar esto no cambia el comportamiento de ninguna tienda existente.

#### Restricción del proveedor (importante)

La matriz automática cubre **solo USD, EUR y MLC** (más CUP como pivote). Verificado: `CAD` y `GBP` devuelven `NULL`. Por tanto:

> **Cualquier moneda nueva creada desde el superadmin necesitará tasa manual.** La pantalla lo dice y el botón «Traer automática» avisa cuando el par no está cubierto.

#### Refresco: por qué el sondeo vive en el cliente

El rol `authenticated` tiene **`statement_timeout = 8s`** (verificado en `pg_roles`). Un sondeo bloqueante en Postgres queda al borde del límite y, si el proveedor tarda, aborta con *«canceling statement due to statement timeout»* en vez de devolver un estado limpio. Medido: el proveedor tarda ~6 s.

Diseño final: `fn_tasas_refrescar` **dispara y vuelve** (< 1 s); la app espera 3 s y llama a `fn_tasas_ingerir` (idempotente) hasta 4 veces. Cada RPC queda muy por debajo del límite.

#### Refresco programado — ✅ aplicado en `newa`, SQL listo para producción

Sin un job programado, la caché solo se refresca cuando alguien pulsa «Actualizar». Ya está resuelto:

| Job | Cadencia | Comando |
|---|---|---|
| `flow-tasas-refresco` | horaria, al minuto 15 | `select flow.tasas_refrescar(false);` |
| `flow-tasas-ingesta` | cada 10 min | ingiere las respuestas pendientes de `flow.tasa_cambio_sondeo` |

Ambos llaman a `flow.*` **directamente** (no a los wrappers de `public`), porque un job de `pg_cron` no tiene sesión de usuario y los wrappers exigen superadmin.

**Verificado en `newa`:** `flow-tasas-ingesta` disparó a las 15:10:00 UTC y terminó `succeeded` en 8 ms («0 rows», sin pendientes). El comando del refresco se probó bajo el mismo rol: `{estado:'solicitado', request_id:12}`.

**En producción el estado — REVERIFICADO 2026-11-04 (segunda medición) es:**

| Fichero | Estado en producción |
|---|---|
| `fase1_catalogo_monedas.sql` | ✅ aplicado (`monedas` con `decimales`/`orden`/`es_base`/`es_sistema`, `tipos_moneda.codigo` = `character(3)`, 5 funciones) |
| [`fase1b_tasa_automatica.sql`](docs/plan-multimoneda/fase1b_tasa_automatica.sql) | ✅ **aplicado** — `fn_tasa_automatica`, `fn_tasa_automatica_estado`, `fn_tasas_refrescar`, `fn_tasas_ingerir` existen; `fn_tasa_cambio` tiene el escalón automático (probado: `EUR→CUP` = 930 y `MLC→CUP` = 698,81 sin tasa manual) |
| [`fase1d_cron_tasas.sql`](docs/plan-multimoneda/fase1d_cron_tasas.sql) | ✅ **aplicado** — `flow-tasas-refresco` (`15 * * * *`) y `flow-tasas-ingesta` (`*/10 * * * *`) activos y ejecutándose |

> La tabla anterior decía «pendiente» para `fase1b` y `fase1d`. **Esos datos eran
> de la primera medición y ya no valen**: el 2026-11-04 se comprobó contra
> producción que ambas están aplicadas y los dos jobs corren.

> **🔴 Defecto nuevo detectado al verificar el Checkpoint 3 (2026-11-04): la tasa
> automática no se refresca. El proveedor responde `HTTP 403` en todos los
> intentos.** Evidencia: `flow.tasa_cambio_sondeo` tiene `error = 'HTTP 403'` en
> todas las filas recientes (11:15, 12:15, 12:20, 13:15, 14:15), y la última fila
> de caché en `flow.tasa_cambio` se guardó el **2026-10-29** con datos del
> 2026-10-28. `fn_tasa_automatica_estado()` devuelve `vigente: false`,
> `actualizado: 2026-10-28T05:01:05-04:00`.
>
> **Los cron dicen `succeeded` porque la ingesta termina, no porque haya datos.**
> Consecuencia: cualquier divisa **sin tasa manual** (hoy `EUR` y `MLC`) se cobra
> con una tasa de hace 7 días, y si la caché se vaciara quedaría en `NULL` y
> bloquearía el cobro (B4). No afecta a CUP ni a USD (tienen tasa manual y la
> manual gana), por eso el Checkpoint 3 no se ve afectado — pero **hay que
> arreglarlo antes de habilitar EUR en una tienda**.

**El orden importa y no es opcional.** `fase1d` usa `public.fn_tasa_automatica` en su bloque de verificación; si se ejecuta antes de `fase1b` falla con `ERROR 42883: function public.fn_tasa_automatica(unknown, unknown) does not exist`. Es un error real, detectado al intentar aplicarlo. Al fallar, el script se revirtió y **no dejó jobs creados** (0 jobs `flow-tasas*` en producción). *(Nota: ese episodio fue antes de la aplicación efectiva; hoy ambos están.)*

Dos avisos que recoge ese archivo:

- **En producción, USD→CUP seguirá usando la tasa manual (900)**, porque `tasas_conversion` tiene ese par configurado y la manual siempre gana. La automática entra en los pares **sin** tasa manual (hoy EUR→CUP y MLC→CUP).
- Producción tiene 9 jobs de `pg_cron`, entre ellos `update_daily_prices_00_00` → `public.fn_update_daily_prices_carnaval()`, que es de **Carnaval**, no del TPV: **no hay dependencia de orden** con el refresco de tasas.

---

## 5. Contratos de RPC

Todas las RPC nuevas son **aditivas**: las vigentes se quedan intactas para las apps desplegadas.

### 5.1 Registrar pagos — `fn_registrar_pago_venta_v3`

```sql
CREATE OR REPLACE FUNCTION public.fn_registrar_pago_venta_v3(
  p_id_operacion_venta bigint,
  p_pagos jsonb
) RETURNS boolean ...
```

`p_pagos` (una entrada por línea de pago):

```json
[
  {
    "id_medio_pago": 1,
    "monto": 2.00,                 // importe EN LA MONEDA INDICADA (nativo)
    "moneda": "USD",               // CUALQUIER código del catálogo, no solo CUP/USD
    "tasa_cambio": 550,            // nativa -> CUP. Obligatoria si moneda != CUP
    "referencia_pago": null,
    "tipo_pago": 1
  }
]
```

Lógica (sustituye la coacción binaria):

```sql
v_moneda := upper(trim(v_pago->>'moneda'));

-- La tienda se obtiene igual que ya hace la RPC vigente (venta_usd.sql:41-45)
SELECT o.id_tienda INTO v_id_tienda
FROM public.app_dat_operacion_venta ov
JOIN public.app_dat_operaciones o ON o.id = ov.id_operacion
WHERE ov.id_operacion = p_id_operacion_venta;

-- validación (D5): existe, activa y habilitada para la tienda
IF NOT EXISTS (SELECT 1 FROM public.monedas WHERE codigo = v_moneda AND activo) THEN
  RAISE EXCEPTION 'Moneda "%" no existe o no está activa', v_moneda;
END IF;
IF NOT EXISTS (
  SELECT 1 FROM public.app_dat_tienda_moneda
  WHERE id_tienda = v_id_tienda AND moneda = v_moneda AND activo
) THEN
  RAISE EXCEPTION 'La tienda no acepta pagos en "%"', v_moneda;
END IF;

v_tasa := CASE WHEN v_moneda = 'CUP' THEN 1
               ELSE NULLIF(v_pago->>'tasa_cambio','')::numeric END;
IF v_tasa IS NULL OR v_tasa <= 0 THEN
  RAISE EXCEPTION 'Tasa de cambio inválida para "%"', v_moneda;
END IF;

v_monto_cup := round(v_monto * v_tasa, 2);

INSERT INTO public.app_dat_pago_venta (
  ..., moneda, tasa_cambio, monto_cup_equivalente, tasa_usd
) VALUES (
  ..., v_moneda, v_tasa, v_monto_cup,
  CASE WHEN v_moneda = 'USD' THEN v_tasa ELSE NULL END   -- legacy
);
```

`fn_registrar_pago_venta_v4` = igual, pero **idempotente** (reemplaza pagos con `id_liquidacion IS NULL`), mismo patrón que `_v2` → `fn_registrar_pago_venta_v2`.

### 5.2 Turnos

| RPC | Cambio |
|---|---|
| `registrar_apertura_turno_monedas(..., p_efectivo_inicial_por_moneda jsonb)` | `{"CUP": 1500, "USD": 20}` → escribe filas en `app_dat_caja_turno_moneda`. Sigue escribiendo `efectivo_inicial` (CUP) y `efectivo_inicial_usd` (legacy). |
| `fn_cerrar_turno_tpv_monedas(..., p_efectivo_real_por_moneda jsonb)` | Calcula `efectivo_esperado` por moneda = inicial + `SUM(pv.monto)` de los pagos **en efectivo de esa moneda** en el turno. Escribe diferencia por moneda. |
| `fn_apertura_turno_offline_monedas` / `fn_cerrar_turno_offline_monedas` | Equivalentes offline. |

### 5.3 Resumen de cierre — `fn_resumen_diario_cierre_v4`

**Y corrección obligatoria de v2** (bug activo, §0):

```sql
-- presentaciones_inventario/30_cierre_vendedor_v2.sql:255-258 — ANTES (incorrecto)
SUM(CASE WHEN mp.es_efectivo THEN pv.monto ELSE 0 END)
-- DESPUÉS
SUM(CASE WHEN mp.es_efectivo THEN pv.monto_cup_equivalente ELSE 0 END)
```

`fn_resumen_diario_cierre_v4` devuelve, además de las columnas de v3:

| Columna | Tipo | Significado |
|---|---|---|
| `desglose_monedas` | `jsonb` | `[{"moneda":"CUP","operaciones":120,"importe_nativo":45000,"importe_base":45000,"efectivo":30000,"digital":15000}, {"moneda":"USD","operaciones":7,"importe_nativo":14,"importe_base":7700,...}]` |
| `total_base` | `numeric` | Suma de `monto_cup_equivalente` (consolidado correcto) |
| `ventas_usd_nativo` | `numeric` | `SUM(monto) FILTER (WHERE moneda='USD')` — exacto, sin conversión |

### 5.4 Reporte "cuánto se cobró por moneda" — `fn_reporte_ventas_por_moneda`

Núcleo de la petición del usuario. Firma:

```sql
fn_reporte_ventas_por_moneda(
  p_id_tienda bigint,
  p_desde     date,
  p_hasta     date,
  p_id_tpv    bigint DEFAULT NULL
) RETURNS TABLE(
  moneda             text,
  operaciones        bigint,   -- nº de ventas distintas con pago en esa moneda
  importe_nativo     numeric,  -- suma de `monto` en esa moneda (EXACTO)
  importe_base       numeric,  -- suma de `monto_cup_equivalente` (consolidable)
  efectivo_nativo    numeric,
  digital_nativo     numeric,
  tasa_promedio      numeric   -- promedio ponderado de las tasas aplicadas
)
```

Consulta subyacente (la respuesta directa a "cuántas se pagaron en USD"):

```sql
SELECT
  pv.moneda,
  COUNT(DISTINCT pv.id_operacion_venta)                                   AS operaciones,
  SUM(pv.monto)                                                           AS importe_nativo,
  SUM(pv.monto_cup_equivalente)                                           AS importe_base,
  SUM(pv.monto) FILTER (WHERE mp.es_efectivo)                             AS efectivo_nativo,
  SUM(pv.monto) FILTER (WHERE NOT mp.es_efectivo)                         AS digital_nativo,
  ROUND(SUM(pv.monto_cup_equivalente) / NULLIF(SUM(pv.monto), 0), 4)      AS tasa_promedio
FROM public.app_dat_pago_venta pv
JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = pv.id_operacion_venta
JOIN public.app_dat_operaciones    o  ON o.id = ov.id_operacion
JOIN public.app_nom_medio_pago     mp ON mp.id = pv.id_medio_pago
WHERE o.id_tienda = p_id_tienda
  AND o.created_at::date BETWEEN p_desde AND p_hasta
  AND (p_id_tpv IS NULL OR ov.id_tpv = p_id_tpv)
GROUP BY pv.moneda
ORDER BY importe_base DESC;
```

### 5.5 Superadmin — catálogo de monedas

| RPC | Qué hace |
|---|---|
| `fn_crear_moneda(p_codigo, p_nombre, p_simbolo, p_pais, p_decimales, p_orden)` | Inserta en `monedas` **y** en `tipos_moneda` de forma atómica. Valida ISO-4217 (3 letras mayúsculas). |
| `fn_actualizar_moneda(p_codigo, p_nombre, p_simbolo, p_activo, p_decimales, p_orden)` | No permite desactivar la moneda base ni una moneda con pagos activos. |
| `fn_guardar_denominaciones(p_codigo, p_denominaciones jsonb)` | CRUD de `app_dat_denominaciones_moneda` (`[{denominacion, active}]`). |
| `fn_guardar_tasa_global(p_moneda_origen, p_moneda_destino, p_tasa)` | Insert versionado en `tasas_conversion`. |

---

## 6. Cambios por app

### 6.1 `ventiq_superadmin` — nueva pantalla "Monedas"

No existe hoy **nada** de monedas. Se construye desde cero con el patrón ya probado del proyecto:

| Pieza | Archivo | Detalle |
|---|---|---|
| Pantalla CRUD | `lib/screens/monedas_screen.dart` (nuevo) | Patrón de `screens/configuracion_screen.dart:82-387` (planes): `List<Map>`, `AlertDialog`, Supabase directo o servicio. `DataTable` en desktop / `ExpansionTile` en móvil vía `PlatformUtils.shouldUseDesktopLayout`. |
| Servicio | `lib/services/monedas_service.dart` (nuevo) | `listar()`, `crear()`, `actualizar()`, `guardarDenominaciones()`, `guardarTasaGlobal()`. |
| Ruta | `lib/main.dart` | `RouteGuard(route: '/monedas', child: MonedasScreen())` junto a `/configuracion`. |
| Permiso | `lib/config/app_routes.dart` | `AppRoute(route:'/monedas', label:'Monedas', group:'Sistema')` **y añadir a `AppRoutes.protected`** (si no, el guard legacy deja pasar sin permiso explícito). |
| Menú | `lib/widgets/app_drawer.dart` | Ítem en la sección "Sistema". |
| Gating UI | — | Botones de escritura con `AuthService.canWrite()` (patrón de `home_banners_screen.dart:126`). |

**Contenido de la pantalla:**
- Tabla de monedas: código, nombre, símbolo, país, decimales, orden, activa, es_base.
- Alta/edición en diálogo. `CUP` marcada como base y protegida (`es_sistema`).
- Sub-vista de **denominaciones** por moneda (billetes/monedas) → `app_dat_denominaciones_moneda`.
- Sub-vista de **tasa global** (`tasas_conversion`) por par.
- **Retirar** la lista hardcodeada `['USD','CUP','EUR','MLC']` de `flow_planes_screen.dart:465` y alimentarla del catálogo (es del módulo de suscripciones, pero pasa a consumir el catálogo).

### 6.2 `ventiq_admin_app`

**a) Tasas por tienda (ya existe, se generaliza).**
- `PersonalRatesService` (`lib/services/personal_rates_service.dart`) ya hace CRUD de tasas por par hacia CUP con `tipos_moneda`. Se mantiene; el selector de moneda origen ya es dinámico.
- Añadir **habilitación de monedas por tienda**: pantalla en Ajustes que gestiona `app_dat_tienda_moneda` (lista de monedas con switch activo/orden).
- Sustituir el texto del flag booleano "El cajero puede seleccionar la moneda (CUP/USD)" (`widgets/global_config_tab_view.dart:732`) por "Monedas aceptadas por la tienda".
- **Quitar** el `UPDATE` global de `tasas_conversion` desde la app de tienda (`lib/services/currency_service.dart:317-323`): una tienda no debe poder cambiar la tasa global.

**b) Contabilización — nuevas vistas con desglose por moneda.**

| Pantalla | Cambio |
|---|---|
| Ventas (`screens/sales_screen.dart`) | Nueva pestaña/tarjeta "Por moneda" consumiendo `fn_reporte_ventas_por_moneda`: tabla moneda · operaciones · importe nativo · equivalente CUP · efectivo/digital. |
| Cierre de turno (`widgets/tpv_managements/caja_turnos.dart`) | Mostrar el desglose por moneda del turno. |
| Modelo `CajaTurno` (`lib/models/caja_turno.dart:205-435`) | Añadir `desgloseMonedas` (lista) + getters; hoy ignora los `*_usd` que existen en BD. |
| Servicio caja (`lib/services/caja_turno_service.dart:149-161`) | Seleccionar las columnas de moneda y el desglose. |
| Reportes PDF/Excel (`screens/sales_screen.dart:4508-10823`, `services/caja_turno_pdf_service.dart`) | Añadir columna/bloque "Equivalente por moneda" y fila de totales por divisa. |
| `fn_listar_turnos_admin` / `fn_reporte_ventas_por_turno` | Extender el `RETURNS TABLE` con `desglose_monedas jsonb` (aditivo al final) + guard de compatibilidad si el RPC aún no está. |

**c) Derivar el total de ventas del dinero realmente cobrado.** Hoy `fn_reporte_ventas_con_proveedor3` calcula ingresos como `SUM(precio_venta_cup × cantidad)` (`SQL_OPTIMIZATION/fn_reporte_ventas_con_proveedor3.sql:276`), es decir, del **catálogo**, no de los pagos. Con multimoneda eso deja de cuadrar. Se añade el total por pagos (`SUM(monto_cup_equivalente)`) como columna nueva y se documenta la diferencia (descuentos/redondeos/vueltos).

### 6.3 `ventiq_app` (TPV) — el grueso

| # | Archivo | Cambio |
|---|---|---|
| 1 | `lib/models/currency.dart` **(nuevo)** | Modelo `Currency {codigo, nombre, simbolo, decimales}` y `Money {amount, codigo}`. Hoy la moneda viaja como `String` en mapas. |
| 2 | `lib/services/currency_service.dart` | Eliminar `_cupId=1`/`_usdId=2` (`:7-8`). Añadir `getRate(from, to)` y `getRatesForStore()`. `getUsdRate()` se conserva como alias de `getRate('USD','CUP')` para no tocar 30 llamadas. Cachear catálogo + tasas por tienda. |
| 3 | `lib/utils/price_utils.dart` | **Punto central.** `paymentCurrency` (`:136`) deja de colapsar a CUP; `paymentCupEquivalent` usa `tasa_cambio` genérica; `paymentTotalUsd` → `paymentTotalIn(codigo)`; `formatTicketMoney` por moneda. |
| 4 | `lib/screens/checkout_screen.dart` | `_buildCurrencyToggle` (`:888-935`) pasa de `['CUP','USD']` a las monedas de `app_dat_tienda_moneda`. `_paymentCurrencyByMethodId` pasa a `Map<int, String>` con cualquier código. `_currencyPaymentLines` (`:459-483`) y el bloque offline (`:2011-2028`) usan la tasa del par. Mostrar el total en la moneda base **y** el desglose por moneda elegida. |
| 5 | `lib/services/order_service.dart` | `_registerPaymentsInSupabase` (`:1592-1789`): normalización genérica (`:1616-1624`), envía `tasa_cambio`, intenta `fn_registrar_pago_venta_v4` → `_v2` → `fn_registrar_pago_venta`. Idempotencia (`_pagosCoincidenConEsperado`, `:1809`) agrupa por `(id_medio_pago, moneda)` con cualquier código — **debe ir en el mismo deploy que la migración**. |
| 6 | `lib/services/auto_sync_service.dart` | `_pagosParaSincronizar` (`:3695-3777`): normalización genérica, `monto_cup_equivalente = monto * tasa_cambio`, validación "toda moneda ≠ CUP requiere tasa" (`:3981-3990`). Reparación de pagos (`:4313-4437`) con la RPC nueva. |
| 7 | `lib/screens/cierre_screen.dart` | `_calculateClosureTotalsFromOrders` (`:341-425`) pasa de 2 cubos (CUP/USD) a `Map<codigo, total>`. Campos de efectivo real **por moneda** (dinámicos). Envía `p_efectivo_real_por_moneda`. Resumen con desglose. |
| 8 | `lib/screens/apertura_screen.dart` | Campos de efectivo inicial **por moneda** (dinámicos) en vez de sólo `_montoInicialUsdController`. Envía `p_efectivo_inicial_por_moneda`. |
| 9 | `lib/widgets/cash_count_dialog.dart` | `:148-170` pasa de `if USD ... else CUP` a acumuladores por moneda. **Devolver un mapa `{codigo: total}`**, no un único total CUP (`:172-174`). |
| 10 | `lib/widgets/bill_count_dialog.dart` | Igual: conversión genérica (`:200-204`), etiquetas por moneda (`:639,661`). |
| 11 | `lib/screens/orders_screen.dart`, `venta_total_screen.dart`, `order_product_summary.dart`, `usd_rate_chip.dart` | Sustituir condicionales binarias por formateo por código. Renombrar `usd_rate_chip` → chip de tasas. |
| 12 | `lib/services/turno_service.dart` | `:593-605` y `:760-775`: seleccionar RPC por presencia de `por_moneda`, no por `usd == null`. |
| 13 | `lib/services/user_preferences_service.dart` | Cache de catálogo (`monedas`+`tasas`+`denominaciones`) ya existe para denominaciones (`:4687-4757`); extender a tasas por moneda. |

### 6.4 Offline y migración de pendientes

- Los pagos pendientes viven en **SharedPreferences** (`pending_orders`), no en SQLite (`recon-ventiq_app.md §3.2`).
- Las órdenes pendientes antiguas ya llevan `moneda: 'CUP'|'USD'` y `tasa_usd`; son **compatibles** con el modelo nuevo. Se añade un normalizador al leer: `tasa_cambio ?? tasa_usd`, `moneda ?? 'CUP'`.
- **Riesgo de duplicado:** si la normalización cambia y `_pagosCoincidenConEsperado` agrupa distinto, un reintento puede reinsertar pagos. Mitigación: la nueva agrupación **incluye el código tal cual** (sin colapsar), y la RPC idempotente `_v4` borra y reescribe. Debe ir en el mismo release.

---

## 7. Resultado visible: qué responderá el sistema

Ejemplo de cierre de turno y de reporte tras el plan:

| Moneda | Operaciones | Importe nativo | Equivalente CUP | Efectivo | Digital |
|---|---:|---:|---:|---:|---:|
| CUP | 120 | 45.000,00 CUP | 45.000,00 | 30.000,00 | 15.000,00 |
| USD | 7 | 14,00 USD | 7.700,00 | 10,00 | 4,00 |
| EUR | 2 | 5,00 EUR | 2.400,00 | 5,00 | 0,00 |
| **Total** | **129** | — | **55.100,00 CUP** | | |

- **"Cuántas se pagaron en USD"** → columna USD: **7 operaciones, 14,00 USD** (importe nativo exacto, sin conversión).
- **"Total en USD"** → `55.100 / tasa_vigente` (o el importe nativo USD cuando la moneda base sea USD).
- **Consolidado correcto** → `SUM(monto_cup_equivalente)`, que **hoy está mal** por el bug de §0.

---

## 8. Fases de implementación

Cada fase es desplegable y reversible por separado. Las fases 1 y 2 no tocan las apps; se pueden desplegar antes de actualizar los clientes.

### Fase 0 — Verificación en vivo — ✅ **COMPLETADA** (2026-11-04)

Ejecutada contra la base real (MCP de Supabase, solo lectura). Resultado en [`docs/plan-multimoneda/diagnostico-resultado.md`](docs/plan-multimoneda/diagnostico-resultado.md) y resumen en §1.5/§1.6. El bloque SQL de abajo queda como referencia reproducible (el script está en [`docs/plan-multimoneda/diagnostico_fase0.sql`](docs/plan-multimoneda/diagnostico_fase0.sql)):

```sql
-- 1. Tipo real de monedas.codigo (el volcado dice character = bpchar(1))
SELECT column_name, data_type, character_maximum_length
FROM information_schema.columns
WHERE table_schema='public' AND table_name='monedas';

-- 2. Contenido del catálogo
SELECT * FROM public.monedas ORDER BY codigo;
SELECT id, * FROM public.tipos_moneda ORDER BY id;

-- 3. ¿Existe el CHECK y cuántas monedas distintas hay?
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.app_dat_pago_venta'::regclass;

SELECT moneda, count(*), sum(monto), min(tasa_usd), max(tasa_usd)
FROM public.app_dat_pago_venta GROUP BY moneda;

-- 4. DDL real de las tablas sin definición en el repo
\d public.tasa_cambio_extraoficial
\d public.tipos_moneda
\d public.app_dat_denominaciones_moneda

-- 5. RLS
SELECT tablename, policyname, cmd FROM pg_policies
WHERE schemaname='public'
  AND tablename IN ('monedas','tipos_moneda','tasas_conversion',
                    'tasa_cambio_extraoficial','app_dat_denominaciones_moneda');

-- 6. Volumen y entornos (¿está venta_usd.sql aplicado?)
SELECT count(*) FILTER (WHERE moneda='USD') AS usd,
       count(*) FILTER (WHERE moneda='CUP') AS cup
FROM public.app_dat_pago_venta;
```

**Entregable:** `docs/plan-multimoneda/diagnostico-resultado.md` con los resultados y cualquier corrección a este plan.

### Fase 1 — Catálogo y superadmin — ✅ **COMPLETADA Y VERIFICADA EN `newa`**

**Hecho y verificado en `newa` el 2026-11-04** con [`docs/plan-multimoneda/fase1_catalogo_monedas.sql`](docs/plan-multimoneda/fase1_catalogo_monedas.sql):

1. ✅ Migración §4.1, §4.2, §4.7 (metadatos de `monedas`, puente `tipos_moneda.codigo`, RLS de 3 catálogos).
2. ✅ `fn_tasa_cambio` (§4.3) + `fn_crear_moneda` / `fn_actualizar_moneda` / `fn_guardar_denominaciones` / `fn_guardar_tasa_global` (§5.5).

Evidencia de la verificación: ✅ columnas creadas · ✅ puente `1→CUP`, `2→USD` · ✅ 1 sola moneda base · ✅ `fn_tasa_cambio('CUP','CUP')=1` · ✅ tasa por tienda resuelta (850) · ✅ `EUR` sin tasa → `NULL` (bloquea el cobro, decisión B4) · ✅ 6 políticas (2 por catálogo, sin permisivas) · ✅ **idempotencia**: migración completa re-ejecutada sin error · ✅ **alta real**: `EUR` creada con 7 denominaciones, escritura atómica en `monedas` **y** `tipos_moneda` (id 3), dato de prueba eliminado después · ✅ **guardia fail-closed**: sin sesión de superadmin lanza `P0001: Solo un superadministrador puede crear monedas` · ✅ **regresión**: los 23 pagos de newa intactos, 0 en otras monedas.

**Bug encontrado por probar en `newa` (ya corregido en el `.sql` del repo):** los parámetros `p_decimales`/`p_orden` estaban declarados `smallint`, y un literal entero **no resuelve** contra `smallint` (la conversión `int4→int2` es de asignación, no implícita) → la llamada fallaba con `42883: function does not exist`. Ahora son `integer`, con `DROP FUNCTION IF EXISTS` de la firma vieja (cambiar el tipo de un parámetro **crea una sobrecarga**, no reemplaza). Esto habría roto la pantalla del superadmin en producción.

**Código de la fase (completado):**

3. ✅ Pantalla [`monedas_screen.dart`](ventiq_superadmin/lib/screens/monedas_screen.dart) + servicio [`monedas_service.dart`](ventiq_superadmin/lib/services/monedas_service.dart): catálogo, alta/edición, activar/desactivar, denominaciones por divisa y tasas globales. Registrada en `main.dart` (`/monedas`), en `AppRoutes.protected` y en el `AppDrawer`.
4. ✅ Lista hardcodeada `['USD','CUP','EUR','MLC']` retirada de [`flow_planes_screen.dart`](ventiq_superadmin/lib/screens/flow_planes_screen.dart): ahora carga de `monedas` con fallback CUP/USD.

5. ✅ **Tasa automática integrada** (§4.8): wrappers `fn_tasa_automatica`, `fn_tasa_automatica_estado`, `fn_tasas_refrescar`, `fn_tasas_ingerir`; `fn_tasa_cambio` gana el escalón automático; tarjeta «Tasa automática» en la pestaña de tasas (estado, fecha, valores USD/EUR/MLC, botón *Actualizar*) y botón «Traer automática» en el diálogo para prefijar el *custom*.
6. ✅ **Refresco no bloqueante verificado**: disparo < 1 s (`estado:'solicitado'`, `request_id:11`) → ingesta con `ingeridos:1` → caché fresca (USD 900 / EUR 990 / MLC 740,30). Guardia fail-closed comprobada en ambos RPC (`P0001: Solo un superadministrador...`).

**Verificación de código:** `dart analyze lib` (proyecto completo) → **No errors**.

**⚠️ Paso obligatorio tras desplegar la app — conceder la ruta `/monedas`.** `AuthService.canAccessRoute` exige que el rol del superadmin tenga la ruta en su lista `permisos`; con rol asignado **no** aplica el fallback de nivel 1. Verificado en newa: el rol `full` tenía 43 rutas y **no** incluía `/monedas`, así que la pantalla habría dado "Acceso denegado" con todo el SQL correcto. Se concede desde **Roles y Permisos** (recomendado) o por SQL (ver §7 del `.sql`). En newa ya está aplicado (43 → 44 rutas).

**Checkpoint 1:** ✅ cumplido. Se crea `EUR` y aparece en `monedas` **y** en `tipos_moneda` con `codigo='EUR'` (escritura atómica). La app actual **no cambia de comportamiento**: 23 pagos intactos, 0 en otras monedas.

**Limitación honesta:** la pantalla no se ha ejecutado en runtime (no hay click-through). La verificación es análisis estático limpio + las 5 RPC ejercitadas contra newa. Falta abrirla en la app y crear una moneda desde la UI.

> **⚠️ Divergencia entre ramas detectada:** `newa` tiene **237 tablas** (main 239) y **`tasas_conversion` está vacía** (main tiene `USD→CUP = 900`). Por eso la tasa global da `NULL` en newa y la de tienda sí resuelve. No afecta a la Fase 1, pero hay que tenerlo en cuenta al validar reportes en newa: sin tasa global, cualquier prueba que dependa de ella necesita una tasa por tienda.

### Fase 2 — Habilitación por tienda y tasas — 🟡 **SQL aplicado y verificado en `newa`** (falta click-through)

1. ✅ `app_dat_tienda_moneda` (§4.5) + semilla CUP/USD (10 filas · 5 tiendas).
2. ✅ RPC `fn_guardar_monedas_tienda`, que valida `fn_user_can_access_tienda` en servidor.
3. ✅ RLS endurecida en 3 tablas (§4.7), sustituyendo las políticas permisivas.
4. ✅ App admin: `MonedasTiendaCard` en Ajustes → Configuración, `TiendaMonedasService`, y **retirado el `UPDATE` global de `tasas_conversion`** de `currency_service.dart`.

**Verificación de RLS real.** Ojo: el cliente MCP conecta como `postgres`, que tiene `BYPASSRLS` — sin cambiar de rol, cualquier prueba de RLS da falso positivo. Se probó con `set local role authenticated` y el `sub` real de cada usuario:

| Caso | Esperado | Obtenido |
|---|---|---|
| gerente escribe `tasas_conversion` (global) | denegado | ✅ `new row violates row-level security policy` |
| gerente t3 escribe tasa de la tienda 4 | denegado | ✅ denegado |
| gerente t3 escribe tasa de **su** tienda 3 | permitido | ✅ permitido |
| gerente crea moneda en el catálogo | denegado | ✅ denegado |
| superadmin escribe `tasas_conversion` | permitido | ✅ permitido |

Ese tercer caso es el que importa para no romper el admin: **la pestaña «Tasas pers.» sigue funcionando**.

`dart analyze lib` (proyecto completo, `ventiq_admin_app`) → **No errors**.

**Decisión de alcance:** el flag `mostrar_selector_moneda` **se mantiene**. El TPV lo lee para mostrar el toggle CUP/USD hasta que la Fase 3 lo sustituya por la lista de `app_dat_tienda_moneda`. Quitarlo ahora rompería el checkout actual.

**Producción:** ✅ **aplicado y verificado el 2026-11-04** ([`fase2_monedas_por_tienda.sql`](docs/plan-multimoneda/fase2_monedas_por_tienda.sql)): `app_dat_tienda_moneda` con **296 filas = 148 tiendas × 2 monedas (CUP,USD)** y **0 tiendas sin configuración** (el trigger `trg_seed_tienda_monedas` funciona). Ninguna tienda acepta todavía una tercera divisa.

**Checkpoint 2:** la UI permite activar/desactivar monedas por tienda con CUP bloqueada. Pendiente: click-through y probar con una tercera divisa (requiere crear `EUR` en el catálogo, Fase 1).

### Fase 3 — Cobro multimoneda en el TPV — ✅ **COMPLETADA** (con límites conocidos, ver 3.2; y moneda de venta en 3.3)

Se parte en dos entregas para no tocar el cobro y el esquema a la vez.

#### 3.1 — Esquema de pago genérico — ✅ **APLICADO Y VERIFICADO EN `newa`** (BD sola)

1. ✅ `CHECK (moneda IN ('CUP','USD'))` eliminado.
2. ✅ `tasa_cambio numeric` añadida y rellenada (`COALESCE(tasa_usd, 1)`).
3. ✅ `moneda`: `text` → **`character(3)`** + FK a `monedas(codigo)` (mismo tipo exacto; con `varchar(3)` la FK no valida).
4. ✅ **`fn_registrar_pago_venta_v3`**: idempotente (borra y reescribe los pagos no liquidados) y genérica. Valida catálogo **y** que la tienda acepte la moneda.
5. ✅ **`fn_registrar_pago_venta` y `_v2` endurecidas (3.1c)**: ya **no coaccionan** monedas desconocidas a CUP; ahora lanzan error explícito indicando que se use `_v3`. Era el riesgo crítico R1 de la auditoría: un fallback silencioso habría guardado una fila corrupta. Verificado con test transaccional: EUR bloqueado, USD idéntico a antes.
6. ✅ **Trigger `trg_seed_tienda_monedas` (3.1b)**: toda tienda nueva nace con CUP y USD. Medido en producción: **148 tiendas, 0 sin config**; sin el trigger, una tienda creada después del seed quedaría sin monedas y `_v3` le bloquearía todos los cobros. Verificado con alta transaccional (2 filas sembradas, revertida).

**Cambios respecto al plan original, y por qué:**

| Plan decía | Se hizo | Motivo |
|---|---|---|
| `_v3` (simple) + `_v4` (idempotente) | **una sola `_v3` idempotente** | La app ya usaba `_v2` (idempotente) como primera opción. Mantener una sola función reduce superficie; la cadena de fallback queda `_v3 → _v2 → _v1`. |
| Exponer `tasa_cambio` en `get_sale_payments2` / `fn_listar_ordenes` / `listar_ordenes_mesa` | **no se tocan** | Ya exponen `moneda`, `tasa_usd` y `monto_cup_equivalente`. El cliente puede derivar la tasa como `monto_cup_equivalente / monto`, exacta porque el servidor guardó justo ese producto. Reescribir funciones de 14 KB para añadir una columna era riesgo sin beneficio. |
| `monto_cup_equivalente = round(monto × tasa, 2)` | **sin redondeo** | La app envía USD con toda su precisión (`9.090909090909092 × 550 = 5000.0000…`). Redondear a `9.09` dejaría la suma **por debajo** del total y `es_pagada` quedaría en `false`. Rompería la venta. |

**Por qué 3.1 es seguro de desplegar solo:** la app actual sigue llamando a `_v2`, que no se ha tocado. Quitar el `CHECK` solo amplía lo permitido. Ninguna fila histórica cambia.

**Prueba transaccional (revertida) de `_v3` con una moneda nueva:**

```
operacion 62 · tienda 6 · importe_total 4500.00
pago_insertado: {moneda: EUR, monto: 4.5, tasa_cambio: 1000,
                 tasa_usd_legacy: null, monto_cup_equivalente: 4500.0}
es_pagada_tras_v3: true
CAD bloqueada con: "La moneda CAD no existe o no está activa en el catálogo"
```

Verificado después: `monedas`=2, `pagos`=23, 0 filas EUR. La transacción revirtió entera.

**Producción:** ✅ **aplicado y verificado el 2026-11-04** ([`fase3_1_pago_generico.sql`](docs/plan-multimoneda/fase3_1_pago_generico.sql)): `CHECK (moneda IN ('CUP','USD'))` **eliminado** (solo queda `monto >= 0`), `moneda` es `character(3)`, `tasa_cambio` presente y la FK `app_dat_pago_venta_moneda_fkey → monedas(codigo)` creada. `fn_registrar_pago_venta_v3` existe y su cuerpo es **semánticamente idéntico** al probado en `newa` (la única diferencia son comentarios y espacios).

#### 3.2 — App del TPV — ⬜ **PENDIENTE**

Base: auditoría independiente en [`docs/plan-multimoneda/auditoria-fase3-tpv.md`](docs/plan-multimoneda/auditoria-fase3-tpv.md) (410 líneas, verifica las 13 filas de §6.3 y encuentra 6 puntos de escritura de pagos que el plan no tenía).

**Decisiones tomadas (2026-11-04):**

- **D1 — la moneda va por LÍNEA de pago, no por método.** Un mismo método puede cobrarse en varias monedas en la misma venta (efectivo CUP + efectivo USD). Implica que el estado del checkout deja de ser `Map<idMedioPago, moneda>` y pasa a ser una lista de líneas.
- **D2 — EUR offline: sí en el diseño, no todavía en la práctica.** En 3.2 las divisas distintas de CUP/USD **exigen conexión**; el offline sigue limitado a CUP y USD. El soporte offline de más divisas (y el arqueo multimoneda que necesita) llega en la Fase 4.

**Progreso 3.2:**

| # | Pieza | Estado |
|---|---|---|
| 0 | **Diseño de referencia** (Stitch, proyecto nuevo `16136369387123985393`): pantalla «Modal de Cobro Multimoneda TPV» + sistema «Tactile High-Contrast POS» | ✅ hecho |
| 1 | `price_utils.dart` genérico (12 funciones) conservando la API | ✅ hecho · `dart analyze` limpio · **15/15 tests pasan** |
| 2 | `CurrencyService.getRate(from,to)` (delega en `fn_tasa_cambio`), `getMonedasTienda()`, `getRatesForStore()` | ✅ hecho · `dart analyze` limpio |
| 3 | **Checkout adaptativo**: lee `app_dat_tienda_moneda` + tasas del servidor; selector de moneda por línea que **solo aparece si la tienda tiene ≥2 divisas** (toggle con 2, menú con 3+); validación de tasa por divisa; bloqueo offline de divisas ≠ CUP/USD; payload por `(método, moneda)` | ✅ hecho · `dart analyze` limpio · 24/24 tests |
| 4a | **Arreglo del descuento manual** (`order_service`): elige el pago por **equivalente en moneda base** (no por importe nativo), resta el descuento del equivalente y **recalcula el importe nativo con la tasa del propio pago** | ✅ hecho · 6 tests nuevos · **21/21 pasan** |
| 4b | `order_service`: **lista de líneas** `(método, moneda, monto)` en vez de `Map<método, monto>`; payload con `moneda`+`tasa_cambio`; cadena `_v3 → _v2 → _v1` **sin fallback** si hay divisas ≠ CUP/USD; y **guarda de idempotencia** agrupando por moneda real | ✅ hecho · 10 tests nuevos · **31/31 pasan** |
| 4c | **«Mover montos»** (`order_service`, online + offline): el traspaso se hace por **valor en moneda base**, se recalcula el equivalente en origen y destino, y el `INSERT` declara `moneda` + `monto_cup_equivalente` | ✅ hecho |
| 4d | **`preorder_screen`**: declara `moneda: 'CUP'` en las líneas del desglose offline (antes el sincronizador tenía que adivinarlo) | ✅ hecho |
| 5 | **`auto_sync_service`**: replay con **moneda real** (no colapsa a CUP/USD), reenvía `tasa_cambio`, valida tasa de **cualquier** divisa, y el camino de reparación intenta `_v3` primero sin fallback para divisas nuevas | ✅ hecho |
| 6 | **Impresoras** (bluetooth y wifi): la moneda se lee del sufijo `(XXX)` del rótulo, así un pago en EUR no se imprime como CUP. El ticket web ya usaba `formatPaymentAmount` genérico | ✅ hecho |
| 7 | **Puente de arqueo** (`cierre_screen`): un cobro en divisa ≠ USD suma su **equivalente** al cubo CUP, no el importe nativo (antes 20 EUR entraban como «20 CUP»). El arqueo por divisa es Fase 4 | ✅ hecho · verificado en `cierre_screen:381-398` |

> **Nota de mantenimiento (2026-11-04):** esta tabla tenía tres filas duplicadas
> (5, 6 y 7) marcadas «⬜ pendiente» que eran **restos de la versión anterior** del
> plan. Comprobado en el código antes de borrarlas: `auto_sync_service:3704-4020`
> normaliza la moneda real y reenvía `tasa_cambio` sin colapsar a CUP/USD;
> `bluetooth_printer_service:1366` y `wifi_printer_service` leen la divisa del
> sufijo `(XXX)`; `cierre_screen:381` usa `PriceUtils.paymentCurrency` y suma el
> **equivalente** al cubo CUP. Las tres piezas están hechas.

> **Estado intermedio consciente (histórico):** el paso 1 hizo que
> `paymentCurrency` devolviera el código real y los sitios que ramifican con
> `== 'USD'` se actualizaron en los pasos 3-7. **Ya no queda ninguna pantalla que
> solo ofrezca CUP/USD**: la UI del cobro lee `app_dat_tienda_moneda`.
>
> **El arreglo 4a es desplegable por separado y ya.** Solo lee `id, monto, moneda, tasa_usd, monto_cup_equivalente`, columnas que **existen en producción hoy**: no depende de `tasa_cambio` ni de que la Fase 3.1 esté aplicada. Detiene una corrupción que está ocurriendo.

**Pendientes reales de la Fase 3 (comprobados el 2026-11-04, no están hechos):**

| # | Qué | Dónde | Nota |
|---|---|---|---|
| 12 | `turno_service` sigue eligiendo RPC por la **presencia de un argumento USD** (`efectivoRealUsd != null ? 'fn_cerrar_turno_tpv_usd' : 'fn_cerrar_turno_tpv'`, ídem apertura) en vez de por `por_moneda` | `turno_service.dart:593-605, 760-775` | Necesita las RPC `*_monedas` que son **Fase 4**; no se puede cerrar antes |
| 13 | Cache persistente de **tasas por moneda** (hoy solo `MonedaVentaService` en memoria; `getRatesForStore()` consulta cada vez) | `user_preferences_service` (0 coincidencias de catálogo de monedas) | Afecta al **offline**, que es Fase 4 (D2) |
| 11 | `usd_rate_chip` conserva el nombre y el rótulo «1 USD = X CUP» | `widgets/usd_rate_chip.dart` | Cosmético: el chip sigue siendo útil como referencia del USD |

**Resultado de la auditoría sobre §6.3:** 8 filas exactas · 2 inexactas (fila 2: «30 llamadas» a `getUsdRate` → son **13**; fila 4: `_paymentCurrencyByMethodId` **ya** es `Map<int,String>`) · 3 incompletas (5, 6 y 11). Ninguna apunta a código muerto.

**Ya resuelto en 3.1c (era el riesgo crítico R1):** `fn_registrar_pago_venta` y `_v2` **rechazan** ahora cualquier moneda ≠ CUP/USD en vez de coaccionarla a CUP. Verificado: EUR bloqueado con mensaje explícito; USD sigue registrando idéntico (5 × 900 = 4500 = total). También cierra el camino offline, porque `fn_registrar_pago_venta_offline` delega en `_v1`.

**Cambios necesarios, agrupados:**

| Grupo | Qué | Por qué |
|---|---|---|
| **Núcleo** | `paymentCurrency` deja de colapsar; `paymentCupEquivalent` usa `tasa_cambio` (o deriva `monto_cup_equivalente / monto`); `paymentDisplayCurrency`, `formatTicketMoney`, `cupToTicketAmount`, `formatCupAmountForPayments`, `paymentUsdRate` → genéricos | Son **12** funciones de `price_utils.dart`, no solo la de la fila 3 del plan. Todas heredan el sesgo binario. |
| **Escritores de pagos** | (a) descuento manual `order_service.dart:447-468`: ordena por `monto` **nativo** (comparar CUP con USD no significa nada) y escribe `precioFinal` (CUP) sobre el pago mayor → en venta USD graba 45000 CUP como «45000 USD»; (b) mover montos `order_service.dart:578-812`: `INSERT`/`UPDATE` directos sin `moneda` ni equivalente (el INSERT toma el DEFAULT 'CUP'); (c) `preorder_screen.dart:2460-2470`: 2.º escritor de `pending_orders` sin moneda | El servidor no es el único que escribe pagos. **El descuento manual corrompe datos hoy**, con independencia de esta fase. |
| **UI del cobro** | gate del toggle (`checkout:823-827`) exige `_usdRate > 0 && mostrar_selector_moneda`; el TPV **no lee `app_dat_tienda_moneda`** (0 coincidencias); `_displayTotalsInUsd` exige que *todos* los métodos estén en USD | Sin quitar el gate, el selector nunca aparece si no hay tasa USD. |
| **Lectura** | `get_sale_payments2` no devuelve `tasa_cambio` | Se puede derivar (`equiv / monto`), pero conviene exponerla. Función pequeña (1 KB): bajo coste. |
| **Impresión** | 3 impresoras deciden la moneda con `endsWith('(USD)')`: `bluetooth:1366-1378`, `wifi:1075-1087`, `web:438-441` | Un pago EUR se imprime como «5 CUP». Afecta al ticket del cliente. |
| **Offline** | cuadre `user_preferences_service:2739-2860` suma `paymentCupEquivalent` sin fallback y **no lee `efectivo_inicial_usd`**; apertura/cierre solo CUP+USD (`apertura:2595`, `cierre:3273,3380`, `auto_sync:1357-1360,2153-2155`) | Si se permite EUR offline, el arqueo no cuadra. |

**Dos decisiones (tomadas el 2026-11-04, ya implementadas):**

- **D1 — la moneda va por LÍNEA de pago.** El checkout usa la clave `(método, moneda)`
  y `order_service` envía una lista de líneas. **Parcial en la UI**: la clave lo
  soporta, pero la pantalla asigna una moneda por método (ver límite 1).
- **D2 — EUR offline: no en esta fase.** Las divisas ≠ CUP/USD exigen conexión; el
  offline sigue limitado a CUP/USD y su arqueo es Fase 4.

**Checkpoint 3: ✅ VERIFICADO EN EL SERVIDOR (2026-11-04) — 9/9, con dos salvedades.**

Se ejecutó contra `newa` en **una transacción revertida** (nada persistió: 23 pagos,
2 monedas, 1 pago en la operación 62 antes y después) usando el `_v3` **idéntico al
de producción** — comparado antes de probar: mismo `valida_tienda`, `idempotente`,
fallback `tasa_usd`, sin redondeo y `es_pagada`; la única diferencia con el de
`newa` son comentarios y espacios.

| Caso | Esperado | Obtenido |
|---|---|---|
| 1. EUR 4,5 @1000 | `EUR / 1000 / tasa_usd NULL / 4500 / pagada` | ✅ |
| 2. USD 5 **solo con `tasa_usd`** (app vieja) | `USD / 900 / 900 / 4500 / pagada` | ✅ |
| 3. CUP 4500 | `CUP / 1 / NULL / 4500 / pagada` | ✅ |
| 4. Moneda inexistente `XXX` | error | ✅ `La moneda XXX no existe o no está activa en el catálogo` |
| 5. EUR sin tasa | error | ✅ `La tasa de cambio de EUR debe ser mayor que cero` |
| 6. EUR con tasa 0 | error | ✅ ídem |
| 7. EUR en tienda que no la acepta | error | ✅ `La tienda 6 no acepta pagos en EUR` |
| 8. Reintento ×2 (idempotencia) | 1 fila / 4500 | ✅ |
| 9. Mismo método en 2 monedas (D1) | 2 filas / 4500 / pagada | ✅ |

**Precedencia de tasas en producción (probada con SELECT, solo lectura):** tienda
1000 **gana** a la global 900 (manual primero) ✅ · `CUP→CUP` = 1 ✅ · `EUR→CUP` =
930 y `MLC→CUP` = 698,81 por el escalón automático ✅ · `CUP→USD` = 0,001183
(inverso) ✅.

**Salvedad 1 — el checkpoint NO cubre la app.** Todo esto es el servidor. Que el
TPV *llame* a `_v3` con la moneda y la tasa correctas, que el ticket salga bien y
que el cierre cuadre sigue sin verificarse: requiere `flutter run` y una venta real.

**Salvedad 2 — en producción no se puede cobrar en EUR todavía:** `app_dat_tienda_moneda`
solo habilita `CUP,USD` en las 148 tiendas. Para el end-to-end real hay que habilitar
EUR en una tienda desde el admin — y antes arreglar el `HTTP 403` de la tasa automática
(§4.8) o ponerle tasa manual a EUR, porque hoy su tasa es de hace 7 días.

**Límites conocidos al cerrar la fase (conscientes):**

1. **Partir una línea en dos monedas desde la UI no está implementado.** El modelo lo soporta en las tres capas (clave `(método, moneda)` en checkout, `order_service` y la RPC `_v3`), pero el checkout asigna **una moneda por método**. Falta el control «+» para dividir una línea en tiendas con ≥2 divisas. Sin él, «Efectivo CUP 1.000 + Efectivo USD 20» en el mismo ticket no se puede componer desde la pantalla.
2. **El arqueo por divisa es Fase 4.** El cierre consolida correctamente en CUP (equivalente), pero no cuenta billetes por moneda.
3. **No hay click-through en runtime.** Todo está verificado por `dart analyze` y 31 tests, no ejecutando la app.

#### 3.3 — Moneda de venta (visualización de precios) — ✅ **COMPLETADA**

**Qué es.** Además de cobrar en N divisas (§3.2), el vendedor elige la divisa en la
que **se muestran los precios** de ese teléfono. No cambia el precio del producto
(sigue en `precio_venta_cup`): un producto de 45.000 CUP se ve `$45.000,00` con
moneda de venta CUP y `45,45 EUR` con EUR a tasa 990.

**Diseño (el que desbloquea todo).** El formateo ocurre dentro de `build()`, donde
no se puede esperar a SharedPreferences ni a la red. Por eso la moneda y sus tasas
viven **en memoria** en `MonedaVentaService`, con un **único punto de formateo
síncrono** `formatearPrecio(importeEnCup, {decimales, conSimbolo})`:

| Caso | `conSimbolo: false` | `conSimbolo: true` |
|---|---|---|
| moneda base (CUP) | `45.000,00 CUP` | `$45.000,00` |
| divisa alternativa | `45,45 EUR` | `45,45 EUR` |

`conSimbolo: true` produce en CUP **exactamente** el texto anterior
(`'\$${x.toMoneyString(2)}'`), así que una tienda de una sola divisa no ve ningún
cambio visual al migrar una pantalla. Si la divisa activa no tiene tasa, cae a CUP:
**nunca se inventa una conversión**.

**Piezas entregadas:**

| Pieza | Estado |
|---|---|
| `MonedaVentaService`: persistencia, resolución con caídas, conversión, redondeo al alza (b), formateo síncrono, `cargarDesdeTienda()` | ✅ · **45 tests** en 5 ficheros |
| `MonedaVentaChip`: elige divisa, se oculta con una sola divisa con tasa, **actualiza el estado del formateador** al cambiar | ✅ |
| Cableado: `cargarDesdeTienda()` en el arranque del Home; `limpiar()` en el logout; chip en Home, Productos y Pedidos | ✅ |
| Propagación a precios: Home/catálogo (tiles, rieles, quick add), listado de productos, detalle de producto, servicentro, carrito/pedidos, pedidos pendientes y su FAB, cuenta/detalle de mesa, orden por defecto, listas de precios del admin, lista de ventas y comprobante PDF | ✅ **~85 sitios** en 26 ficheros |
| Checkout: la moneda de venta es la **divisa por defecto** de las líneas de pago, aunque el flag legado `mostrar_selector_moneda` esté apagado | ✅ |

**Decisiones tomadas al integrar (revisión del Lead):**

1. **El comprobante PDF de la venta también va en la moneda de venta.** Primero lo
   dejé en CUP y el usuario lo corrigió: es una vista con precios y debe mostrar
   los mismos importes que el vendedor ve en pantalla. Se convirtieron sus 5
   importes (precio, subtotal, total sin descuento, descuento y total a pagar).
2. **Los rótulos «Equivalente CUP» / «Equiv. CUP»** (`orders_screen:1505`, `:1915`)
   se quedan en CUP: la etiqueta nombra la divisa y el valor no puede
   contradecirla. Son el desglose secundario de un cobro ya hecho, no un precio.
3. **El checkout cobra en la moneda de venta aunque el flag legado
   `mostrar_selector_moneda` esté apagado.** Ese flag gobernaba el antiguo toggle
   CUP/USD; exigirlo dejaría el Home mostrando EUR y el cobro registrándose en
   CUP. Solo aplica si el vendedor eligió **activamente** una divisa distinta de
   la base y la tienda la acepta con tasa.
4. **No se toca lo que no es un precio**: arqueo/caja (`cierre`, `apertura`,
   `venta_total` en sus bloques de efectivo, `cash_count_dialog`,
   `bill_count_dialog`, `settings_screen`, `admin_turnos_offline`,
   `cierre_pendiente_detalle`), egresos, agregados diarios (`sales_monitor_fab`),
   resúmenes de pagos ya cobrados, «mover montos», conversiones informativas a
   USD, y **los tickets de las impresoras** (bluetooth/wifi/web/admin): ahí el
   total va en moneda base y las líneas de pago en su divisa real, que es el
   criterio con el que ya funcionaba el USD.
5. **El «selector al entrar»** se resuelve con el chip (visible en las tres
   pantallas con precios); no se añade un diálogo modal que interrumpa el
   arranque.

**Verificación real:** `analyze_files` (MCP de Dart) sobre los **26 ficheros
tocados** → **No errors**; `flutter test` de la suite completa → **407 pasan, 1
falla**. El único fallo es `test/widget_test.dart` («Counter increments smoke
test»), el test plantilla de Flutter que pide un contador inexistente y arranca
`MyApp` sin inicializar Supabase: **ni `main.dart` ni `widget_test.dart` están
modificados**, así que es preexistente y ajeno a este trabajo.
Nota de tooling: en esta sesión `dart analyze`/`flutter analyze` por CLI **no
funciona** (el sandbox deniega las tuberías del analysis server, `CreateFile
failed 5`); la verificación equivalente válida es la del MCP.

**Límite conocido:** no hay click-through en runtime (no se ha abierto la app).

**Dependencia de despliegue (importante).** El chip lee `app_dat_tienda_moneda`
(Fase 2) y las tasas vía `fn_tasa_cambio` (Fase 1). **En producción ninguna de las
dos está aplicada todavía**, así que allí la consulta falla, `MonedaVentaService`
se queda en CUP y **el chip no se pinta**: la app se comporta exactamente como
hoy. Es decir, **este código es seguro de desplegar antes que el SQL**, y la
funcionalidad se enciende sola cuando se apliquen
[`fase1_catalogo_monedas.sql`](docs/plan-multimoneda/fase1_catalogo_monedas.sql) y
[`fase2_monedas_por_tienda.sql`](docs/plan-multimoneda/fase2_monedas_por_tienda.sql)
(y el [`fase3_1_pago_generico.sql`](docs/plan-multimoneda/fase3_1_pago_generico.sql)
para poder cobrar en una divisa nueva).

### Fase 4 — Caja y arqueo multimoneda (3-4 días)
**Estado 2026-11-04 — partes 1 y 2 aplicadas y verificadas en `newa`.**

| Pieza | Estado |
|---|---|
| Fix de `fn_resumen_diario_cierre_v2` (R4) + `app_dat_caja_turno_moneda` + backfill USD | ✅ en `newa` (verificado) · ⬜ **producción** |
| `registrar_apertura_turno_monedas` / `fn_cerrar_turno_tpv_monedas` (arqueo por divisa) | ✅ en `newa` · probado apertura→cierre: CUP esperado 1000 / real 1500 → +500; USD esperado 20 / real 18 → −2 |
| `fn_resumen_diario_cierre_v4` con `desglose_monedas` jsonb + `total_base` | ✅ en `newa` |
| Equivalentes offline (`fn_apertura_turno_offline_monedas` / `fn_cerrar_turno_offline_monedas`) | ✅ **producción** · probado con EUR: esperado 50 / real 45 → −5 |
| Pantallas: `cash_count_dialog`, `bill_count_dialog`, `turno_service`, `apertura`, `cierre`, `venta_total` | ✅ **código completo** · `analyze_files` sin errores · suite 407/1 (el 1 es el test plantilla preexistente) · ⬜ **sin runtime** |

**Pase a producción — verificado el 2026-11-05.** Las partes 1 y 2 **ya están
aplicadas** en producción (comprobado contra la base viva, no contra el documento):
`fn_resumen_diario_cierre_v2` parcheada (len 7167, marcadores presentes),
`app_dat_caja_turno_moneda` con 3.388 filas, `registrar_apertura_turno_monedas` con la
resolución del id de operación, `fn_cerrar_turno_tpv_monedas`, `fn_resumen_diario_cierre_v4`
y `fn_jsonb_monto` (probada: `{"CUP":1000,"usd":"20.5"}` → 20.5, clave ausente → NULL).

**Falta un hueco que descubrí al verificar: 9 turnos sin ninguna fila de arqueo**
(ids 3413-3421, todos creados DESPUÉS del backfill). Causa: la app desplegada abre
turnos con la RPC legacy `registrar_apertura_turno_usd`, que no escribe el arqueo, y
**no hay trigger** en `app_dat_caja_turno`. SQL de cierre en
[`fase4_caja_trigger_arqueo.sql`](docs/plan-multimoneda/fase4_caja_trigger_arqueo.sql)
(trigger INSERT+UPDATE, backfill y runbook), verificado en `newa`.

**Segundo defecto, encontrado al verificar el pase (2026-11-05).** El trigger
`trg_sync_turno_moneda` heredaba `app_dat_caja_turno.efectivo_esperado`, que es **0 en
todos los turnos** (ninguna RPC lo calcula: lo calcula la app en local). Como
`diferencia` es generada (`real - esperado`), el arqueo quedaba con
`diferencia = efectivo_real` — por ejemplo el turno 3415: esperado 0, real 58.480,
diferencia 58.480. **No significa nada.**

Corregido: el trigger ahora **calcula** el esperado por divisa con
`fn_esperado_turno_por_moneda` (inicial de esa divisa + pagos en efectivo de esa divisa
dentro de la ventana del turno, acotada por `fecha_cierre`). Verificado en `newa`: un
turno con 1.000 de inicial y 4.500 de ventas en efectivo da esperado 5.500 y, cerrado
con real 5.500, **diferencia 0**. SQL: [`fase4_arqueo_esperado.sql`](docs/plan-multimoneda/fase4_arqueo_esperado.sql)
(corrige el trigger y recalcula las 3.396 filas ya escritas).
> **El MCP de producción es de solo lectura** — al intentar aplicarlo devuelve
> `ERROR 25006: cannot execute CREATE FUNCTION in a read-only transaction`. Ese
> fichero lo tiene que ejecutar el usuario (editor SQL de Supabase o `psql`).
> Esperado: filas de arqueo 3.388 → **3.397**, turnos sin arqueo **9 → 0**.
**Pantallas entregadas el 2026-11-05 (4 agentes en paralelo, scopes disjuntos).** Se eliminó
el binario CUP/USD de los 6 ficheros: `cash_count_dialog` y `bill_count_dialog` (conteo),
`turno_service` (RPC por divisa con fallback a las vigentes), `apertura_screen`,
`cierre_screen` y `venta_total_screen`. Contrato congelado entre agentes:
`CashCountDialog` devuelve `Map<String,double>` con **importes nativos por divisa**, y el
consumidor de `cierre` se escribió contra él (los dos cambios tenían que ir juntos: el
analyzer **no** detecta el desajuste porque es un casteo en runtime).

**Verificación del Lead (no la de los agentes):** `analyze_files` sobre los 6 ficheros →
**No errors**; suite completa → **407 pasan, 1 falla** (el mismo `widget_test.dart`
plantilla de antes, ajeno). Restos binarios comprobados: `showDialog<double>` 0,
`contains('(USD)')` 0 (solo un comentario), `_totalEfectivoUsd` 0,
`_montoFinalUsdController` 0.

**Límites declarados por los agentes, verificados contra el modelo:**
1. **Los egresos no tienen divisa en el modelo**: `app_dat_entregas_parciales_caja` no tiene
   columna `moneda` y `Expense` no la expone, así que se descuentan **solo de la moneda
   base**. El código ya está listo para N divisas: cuando el modelo la exponga, cambia una
   línea. Requiere tocar `models/expense.dart` + `turno_service.dart`.
2. **`desglose_monedas` solo llega por `fn_resumen_diario_cierre_v4`**:
   `fn_resumen_turno_por_id` y `fn_resumen_turno_kpi` (fuente primaria del cierre online)
   no lo devuelven. En el caso normal el detalle sale de las órdenes locales; si no hubiera
   órdenes cargadas, una tercera divisa se leería como 0.
3. **`auto_sync_service` sigue con el camino offline legacy** (base+USD). Las RPC nuevas
   existen y el payload ya envía `*_por_moneda`, pero ese fichero no se migró.
4. **Sin runtime**: nada de esto se ha ejecutado. El Checkpoint 4 (turno con efectivo
   CUP+USD+EUR que cuadra por divisa) está probado **en el servidor** con datos inyectados,
   no en la app.
**El fix NO es la línea que decía §5.3.** Cambiar `pv.monto` por `pv.monto_cup_equivalente`
en las dos líneas habría metido el efectivo USD convertido en `efectivo_esperado`, que es
el efectivo **CUP que debe haber en el cajón**: el vendedor que cuenta solo CUP habría
visto un faltante igual al efectivo USD. El reparto correcto es `v_ventas` consolidado en
CUP (monto × tasa, todas las monedas) y `v_tot_efectivo` solo CUP. Para una tienda 100 %
CUP el resultado es idéntico al de hoy. Además **no se usa `monto_cup_equivalente`** como
fuente (está corrupta, R11): se calcula desde `monto × tasa`.

**Cuantificación del bug en producción:** 4 turnos afectados, **131.972 CUP subestimados**
(uno de ellos del 2026-11-04). Ficheros: [`fase4_caja_multimoneda.sql`](docs/plan-multimoneda/fase4_caja_multimoneda.sql) y
[`fase4_caja_monedas_rpc.sql`](docs/plan-multimoneda/fase4_caja_monedas_rpc.sql).

**Dos trampas encontradas al probar:**
1. `registrar_apertura_turno_usd` **devuelve el id de la OPERACIÓN de apertura, no el del
   turno** (la app lo llama `operacion_id`). Hay que resolver el turno por
   `id_operacion_apertura` antes de escribir el arqueo.
2. `cash_count_dialog` devuelve **un único total ya convertido a CUP** y `cierre_screen:2337`
   lo escribe en el campo CUP, dejando `efectivo_real_usd = 0`. Es la causa de que el arqueo
   por divisa no exista hoy.

1. `app_dat_caja_turno_moneda` (§4.6) + RPC de apertura/cierre por moneda.
2. `apertura_screen`, `cierre_screen`, `cash_count_dialog`, `bill_count_dialog`.
3. **Corrección de `fn_resumen_diario_cierre_v2`** (§5.3).

**Checkpoint 4:** turno con efectivo CUP + USD + EUR cuadra por moneda; el cierre no mezcla divisas. **Aquí queda corregido el defecto contable actual.**

### Fase 5 — Contabilización en el admin (4-5 días)
**✅ Ambos SQL APLICADOS EN PRODUCCIÓN (verificado el 2026-11-05):**
`fn_reporte_ventas_por_moneda` · `app_dat_entregas_parciales_caja.moneda` ·
`registrar_egreso_parcial_v3` · `fn_desglose_monedas_turno` ·
`fn_resumen_turno_por_id_v2` + `fn_resumen_turno_kpi_v2` · `_v4` usando el helper ·
`fn_apertura_turno_offline_monedas`. Y el R11 reparado y con trigger (§1.6).
**Estado 2026-11-05 — núcleo SQL hecho y verificado en `newa`.**

`fn_reporte_ventas_por_moneda(p_id_tienda, p_desde, p_hasta, p_id_tpv)` creada:
devuelve por divisa `operaciones`, `importe_nativo` (exacto, no convertible),
`importe_base` (consolidado en CUP), `efectivo_nativo`, `digital_nativo` y
`tasa_promedio` ponderada. **Criterio de aceptación del plan cumplido**: cuadra
exactamente con `SELECT moneda, count(distinct …), sum(monto), sum(monto_cup_equivalente)
FROM app_dat_pago_venta` (verificado: 17 ops · 5.330.900 nativo · 5.330.900 base,
`cuadra = true`). No filtra por estado a propósito: ese es su criterio de cuadre.

Fichero: [`fase5_reporte_por_moneda.sql`](docs/plan-multimoneda/fase5_reporte_por_moneda.sql).
**Pantallas del admin entregadas el 2026-11-05** (2 agentes en paralelo, ficheros disjuntos):

| Pieza | Estado |
|---|---|
| Pestaña **«Por moneda»** en Ventas (`sales_screen` + `sales_service`, +404 líneas) | ✅ · tabla Moneda · Operaciones · Importe nativo · Equivalente CUP · Efectivo · Digital · Tasa media, con pie «Consolidado en CUP» |
| `CajaTurno.desgloseMonedas` + `getDesgloseTurno` (`caja_turno_service`) | ✅ · carga **bajo demanda** al abrir el detalle, `_v2` → fallback a la vigente, nunca lanza |
| Desglose en el detalle de turno (`caja_turnos`, +173 líneas) | ✅ · se oculta con una sola divisa (si no, una tienda 100 % CUP vería una tabla de una fila) |
| Columna por divisa en PDF/Excel | ✅ **acta de cierre** (sección «Por moneda», desglose bajo demanda) · ✅ **export PDF + Excel de la pestaña «Por moneda»** (mismos helpers de formato, `latin1` del PDF saneado) |
| `fn_registrar_egreso_offline_v2(..., p_moneda)` — divisa del egreso **offline** | ✅ verificada en `newa` (EUR → fila `30 EUR`; replay idempotente conserva el id) · ⬜ **FALTA APLICARLA EN PRODUCCIÓN** · [`fase4b_egreso_offline_moneda.sql`](docs/plan-multimoneda/fase4b_egreso_offline_moneda.sql) |
| Sync offline de egresos (cache + subida) con divisa | ✅ el cache guarda `moneda` y la subida usa `fn_registrar_egreso_offline_v2` con fallback |
| `sales_monitor_fab` con divisa · `_transferenciaPorDivisa` desde `digital_nativo` | ✅ hechos por el Lead (el subagente cayó antes de aplicarlos) |

**🎯 FASE 5 COMPLETA EN CÓDIGO Y CON EL SQL EN PRODUCCIÓN (2026-11-05).**
`fn_reporte_ventas_por_moneda` aplicada · pestaña «Por moneda» · export PDF/Excel de esa pestaña ·
desglose por divisa en el detalle de turno y en el acta de cierre. Verificado: `analyze_files`
sin errores en los 6 ficheros del admin y suite **134/1** (el 1 es el `widget_test.dart`
plantilla). Queda solo el **runtime**: ver la guía de prueba al final de esta sección.

**Guía de prueba con datos reales de producción** (las secciones por divisa se ocultan con
una sola divisa, así que hay que abrir una tienda que haya cobrado en USD):

| Qué probar | Dónde | Datos |
|---|---|---|
| Pestaña «Por moneda» + export PDF/Excel | Ventas → pestaña «Por moneda» | Tienda **«Restaurant perla negra»** (id 223), rango **2026-11-04** → 3 operaciones en USD + las CUP del día |
| Alternativa con más volumen | ídem | Tienda **«Una»** (id 179), rango **2026-09-17** → 7 operaciones en USD |
| Desglose en el detalle del turno | Caja/Turnos → abrir un turno de esas tiendas | Necesita ≥2 divisas en la ventana del turno, si no la sección no aparece (correcto) |
| Acta de cierre con «Por moneda» | ídem → imprimir acta | Mismo requisito |

**Qué debe verse**: una fila por divisa con *operaciones · importe nativo (con su código) ·
equivalente CUP · efectivo · digital · tasa media*, y un pie «Consolidado en CUP». El importe
nativo **nunca** se suma entre filas. **Qué indicaría un problema**: que el total consolidado
no cuadre con `sum(importe_base)` de las filas, o que aparezca una tabla de una sola fila.
**Verificación final del Lead (2026-11-05, tras las caídas de conexión):** `analyze_files`
→ **No errors** en los 4 ficheros de `ventiq_app` y en los 6 del admin; suites completas →
`ventiq_app` **407 pasan / 1 falla** y `ventiq_admin_app` **134 pasan / 1 falla**, siendo el
fallo en ambas el mismo `widget_test.dart` plantilla de Flutter (ajeno).

Los agentes se cayeron varias veces por red, pero **el trabajo quedó completo**: el de
`auto_sync` sí había escrito su parte antes de caerse (el cache guarda `moneda` y existe
`_rpcEgresoOfflineConDivisa` con fallback); el de `sales_monitor` entregó su fichero y
dejó el segundo punto sin aplicar por una discrepancia de ruta, y el de caja/PDF solo
necesitaba que el acta **cargue el desglose bajo demanda**. Las tres piezas las cerró el
Lead y están verificadas.
**Verificación del Lead:** `analyze_files` sobre los 5 ficheros del admin → **No errors**;
suite del admin → **134 pasan, 1 falla** (el `widget_test.dart` plantilla, ajeno).

Dos criterios de presentación que los agentes acertaron y conviene no revertir:
1. Los importes **nativos** llevan siempre su código de divisa (`$ 14.00 USD`) porque no son
   sumables entre filas; el **equivalente** no lo lleva porque su columna ya es homogénea.
2. En la fila de total, operaciones/nativo/efectivo/digital van con «—»: `operaciones` es
   `count(distinct id_operacion_venta)` **por moneda**, así que un pago mixto cuenta en dos
   filas y sumarlas inflaría el total.

**Pendiente para cerrar la Fase 5:** aplicar `fase5_reporte_por_moneda.sql` en producción y
la columna por divisa en los exports PDF/Excel. El **Checkpoint 5** («en USD se cobraron N
operaciones por X USD = Y CUP equivalente») ya es demostrable: el RPC devuelve esos cuatro
números por divisa y cuadra contra `app_dat_pago_venta`.


1. `fn_reporte_ventas_por_moneda` (§5.4) y extensión de `fn_listar_turnos_admin` / `fn_reporte_ventas_por_turno` con `desglose_monedas`.
2. Pestaña "Por moneda" en Ventas; desglose en Cierre de turno; `CajaTurno` con `desgloseMonedas`.
3. Exportaciones PDF/Excel con columna por moneda.

**Checkpoint 5:** el admin responde "en USD se cobraron 7 operaciones por 14 USD = 7.700 CUP equivalente" y cuadra contra `app_dat_pago_venta`.

### Fase 6 — Contabilidad financiera multimoneda (5-6 días)

Alcance confirmado: **no se difiere**. Hoy las 14 RPC financieras asumen CUP implícito y no conocen la moneda del cobro.

1. Extender (aditivo, al final del `RETURNS TABLE`) con `desglose_monedas jsonb` y `total_base numeric`:
   - `fn_profit_and_loss`, `fn_sales_metrics`, `fn_inventory_metrics`
   - `fn_product_profitability`, `fn_category_profitability`
   - `fn_cash_flow_projections`, `fn_historical_trends`
   - `fn_profitability_report`, `fn_category_profitability_analysis`
   - `fn_low_profitability_products`, `fn_historical_cash_flow`
   - `fn_historical_comparison`, `fn_trend_analysis`, `fn_budget_variance_analysis`
2. Regla contable única: **todo ingreso se mide por `monto_cup_equivalente`** (dinero cobrado), no por `precio_venta_cup × cantidad` (catálogo). Los reportes de rentabilidad pasan a usar el importe real cobrado y se documenta la diferencia con el precio de lista.
3. UI: `financial_dashboard_screen.dart`, `financial_reports_screen.dart`, `financial_screen.dart` con selector de moneda de presentación y desglose.
4. Exportaciones financieras con columna por moneda.

**Checkpoint 6:** el P&G de un turno con pagos CUP+USD+EUR cuadra con `SUM(monto_cup_equivalente)` del turno; se puede ver el P&G expresado en CUP o en USD equivalente.

### Fase 7 — Convergencia de catálogos de moneda (3-4 días)

1. `dep_nom_moneda` y `prv_nom_moneda`: añadir `codigo` con FK a `monedas(codigo)` y backfill; sus CRUD pasan a elegir del catálogo en vez de crear islas.
2. Retirar las listas hardcodeadas restantes:
   - `ventiq_admin_app/lib/screens/inventory_extractionbysale_screen.dart:885` (`['CUP','USD','EUR','MLC']`)
   - `ventiq_admin_app/lib/models/currency_rate.dart` (trío USD/EUR/MLC + fallbacks numéricos)
   - `ventiq_admin_app/lib/services/currency_display_service.dart:23-27,196-217` (fallback hardcodeado)
   - `ventiq_superadmin/lib/screens/flow_planes_screen.dart:465`
3. Unificar la fuente de la tasa EUR (hoy hay doble: `tasa_cambio_extraoficial`/`tasas_conversion` vs `carnavalapp.configuraciones_admin.valor_euro`).
4. `flutter analyze` limpio en las tres apps tras retirar los hardcodes.

**Checkpoint 7:** crear `MLC` en el superadmin la vuelve disponible en TPV, depósitos, pago a proveedores y planes de suscripción, sin tocar código.

### Fase 8 — Seguridad y endurecimiento (2-3 días, **iniciar en paralelo desde ya**)

1. **Rotar la `service_role` key** expuesta en el cliente de admin y superadmin (`recon-admin-superadmin.md §B9.3`). **Riesgo crítico independiente del plan**, pero escribir catálogo global sin resolverlo deja el control solo en la UI. Además está en el APK: cualquiera puede extraerla.
2. Aplicar RLS de §4.7 y verificar con un usuario `authenticated` no superadmin que **no** puede escribir el catálogo.
3. Restringir `tasa_cambio_extraoficial` por tienda (cerrar el `UPDATE` global del admin).
4. Auditar que ninguna app de tienda pueda modificar `monedas`/`tipos_moneda`/`tasas_conversion`.

**Checkpoint 8:** un usuario de tienda no puede crear ni modificar monedas; solo el superadmin. La clave rotada ya no viaja en los clientes.

### Fase 9 — Cierre: QA integral y documentación (2 días, solapa con 6-8)

1. Suite de §10.1 completa en las tres apps.
2. `docs/plan-multimoneda/` actualizado con el DDL real aplicado y el runbook de creación de una moneda.
3. Verificación de cuadre end-to-end: TPV → pagos → caja → cierre → reportes → P&G.

---

## 9. Retrocompatibilidad y migración

| Regla | Detalle |
|---|---|
| Columnas nuevas | Siempre `DEFAULT`; nunca `NOT NULL` sin default. |
| RPC | Las nuevas son sobrecargas/`_v3`/`_v4`. Las actuales **no se tocan** salvo el fix de `fn_resumen_diario_cierre_v2` (que corrige un cálculo erróneo; se valida contra el histórico). |
| App vieja | Sigue funcionando: todo lo que no envía `tasa_cambio` se interpreta por `tasa_usd` y moneda CUP. |
| App nueva sobre BD sin migrar | Degradación a comportamiento actual con aviso (patrón ya usado: intenta `_v4` → `_v3`/`_v2` → original). |
| Histórico | `UPDATE ... SET tasa_cambio = tasa_usd`, `monto_cup_equivalente = monto WHERE NULL`. Ninguna fila cambia de significado. |
| Pendientes offline | Compatibles (ya llevan `moneda`+`tasa_usd`); normalizador en lectura. |
| Orden de despliegue | **BD primero, apps después.** La app nueva tolera BD vieja; la app vieja tolera BD nueva. |

**Ventana de riesgo:** entre el deploy de la RPC `_v4` y el de la app, `_pagosCoincidenConEsperado` debe usar la misma normalización que el servidor. Se despliega junto (Fase 3).

---

## 10. Pruebas y criterios de aceptación

### 10.1 Pruebas obligatorias

| Ámbito | Caso |
|---|---|
| SQL | Migración ejecutada dos veces (idempotente); ninguna fila histórica alterada; `CHECK` eliminado; FK de moneda activa. |
| Pagos | Venta 100% CUP · 100% USD · 100% EUR · mixta CUP+USD+EUR. Verificar `moneda`, `tasa_cambio`, `monto_cup_equivalente`, `es_pagada`. |
| Validaciones | Moneda inexistente → error. Moneda no habilitada en la tienda → error. Tasa 0 o nula en moneda ≠ CUP → error. |
| Caja | Turno con 3 monedas: efectivo esperado por moneda = inicial + pagos en efectivo de esa moneda; diferencia por moneda. |
| Cierre | `fn_resumen_diario_cierre_v2` corregido: con un pago USD de 2 a tasa 550, los totales CUP suman 1.100, no 2. |
| Reporte | `fn_reporte_ventas_por_moneda` cuadra exactamente con `SELECT moneda, count(*), sum(monto) FROM app_dat_pago_venta`. |
| Admin | La pestaña "Por moneda" cuadra con el TPV; PDF/Excel muestran el desglose. |
| Offline | Cobro EUR offline → sync → fila correcta. Pendientes antiguos CUP/USD siguen sincronizando. |
| Idempotencia | Reintento de sync no duplica pagos. |
| Contabilidad financiera | P&G, márgenes y flujo de caja cuadran con `SUM(monto_cup_equivalente)`; el desglose por moneda coincide con `fn_reporte_ventas_por_moneda`. |
| Catálogos unificados | Crear `MLC` en el superadmin la habilita en TPV, depósitos, pago a proveedores y planes de suscripción **sin tocar código**. |
| Seguridad | Un usuario `authenticated` no superadmin recibe error al intentar escribir `monedas`/`tipos_moneda`. |
| Regresión | Las 129.331 filas CUP y 8 USD anteriores se leen igual que antes (el único cambio es el recálculo documentado de `monto_cup_equivalente`, que **corrige** el valor, no reinterpreta el pago). |
| Estático | `dart analyze` limpio en las tres apps (usar MCP Dart por app, no el proyecto completo: el análisis global agota el timeout). |

### 10.2 Definición de "terminado"

1. Una moneda creada en el superadmin se puede cobrar en el TPV y se contabiliza en el admin, **sin cambios de código**.
2. El admin responde, por moneda: nº de operaciones, importe nativo, equivalente en moneda base, efectivo/digital.
3. Los totales consolidados de cierre cuadran con la suma de los equivalentes de los pagos.
4. Venta 100% CUP se comporta **exactamente** igual que antes del plan.
5. Cero filas históricas reinterpretadas.

---

## 11. Riesgos

| # | Riesgo | Severidad | Mitigación |
|---|---|---|---|
| R1 | ~~`monedas.codigo` es `bpchar(1)`~~ **RESUELTO en Fase 0**: es `character(3)` y sí admite `'USD'`. No hace falta `ALTER COLUMN`. | ~~Alta~~ Cerrado | Verificado contra la base real. |
| R2 | ~~Sin conectividad no se puede confirmar el esquema real~~ **RESUELTO en Fase 0**. Queda por versionar el DDL observado en `supabase/migrations/`. | ~~Alta~~ Baja | DDL real documentado en `diagnostico-resultado.md`. |
| R11 | **`monto_cup_equivalente` corrupto/incompleto**: 666 NULL, 97 filas con el total de la operación, ~129 M CUP sin equivalente. Cualquier reporte que lo sume subestima | **Crítica (datos)** | §4.4.1: medir → respaldar → recalcular fila por fila → verificar. Cerrar el agujero en `fn_registrar_pago_venta_offline`. **Bloquea la Fase 5.** |
| R12 | **RLS permisivo verificado**: cualquier usuario autenticado puede crear monedas y cambiar la tasa global | **Crítica (seguridad)** | §4.7: sustituir las 5 políticas `*_authenticated_all`. |
| R13 | ~1.362 operaciones donde `sum(monto) ≠ importe_total` (desajuste previo, no de moneda) | Media | Lista de revisión para el admin; no se corrige a ciegas. |
| R3 | **`service_role` key en el cliente** de admin y superadmin: RLS se salta en release | **Crítica (seguridad)** | Rotar clave y separar builds; mientras no se haga, el control de escritura del catálogo es solo de UI. Independiente de este plan, pero **lo condiciona**. |
| R4 | `fn_resumen_diario_cierre_v2` suma USD como CUP (bug activo) | **Alta** | Corregir en Fase 4; mientras tanto, documentar que los cierres con pagos USD están mal. |
| R5 | Cambio de normalización rompe `_pagosCoincidenConEsperado` → pagos duplicados en sync | Alta | Misma agrupación a ambos lados; `_v4` idempotente; mismo deploy. |
| R6 | Reportes del admin derivan ingresos del catálogo (`precio_venta_cup × cantidad`), no del cobro | Media | Añadir columna de total por pagos y documentar la diferencia. |
| R7 | Cuatro catálogos de moneda sin sincronizar | Media | Regla "crear moneda escribe `monedas`+`tipos_moneda` atómicamente"; convergencia en Fase 6. |
| R8 | El admin hoy puede `UPDATE` la tasa global de todas las tiendas | Media | Quitar en Fase 2 + RLS por tienda. |
| R9 | Moneda activa con pagos históricos desactivada | Baja | `fn_actualizar_moneda` no permite desactivar con pagos activos. |
| R10 | Redondeo por moneda (CUP entero vs USD 2 decimales) | Media | `monedas.decimales` por divisa; redondeo a moneda base en la RPC. |

---

## 12. Mapa de archivos a tocar (resumen)

**SQL / Supabase**
- `supabase/migrations/` (nuevas): monedas, tipos_moneda puente, pago_venta, tienda_moneda, caja_turno_moneda, RLS, RPCs.
- Corrección: `presentaciones_inventario/30_cierre_vendedor_v2.sql:255-258`.
- Referencia (no se toca): `ventiq_app/sql/venta_usd.sql` (queda como histórico de la fase USD).

**`ventiq_superadmin`**
- Nuevos: `lib/screens/monedas_screen.dart`, `lib/services/monedas_service.dart`.
- Modificar: `lib/main.dart`, `lib/config/app_routes.dart`, `lib/widgets/app_drawer.dart`, `lib/screens/flow_planes_screen.dart:465`.

**`ventiq_admin_app`**
- Nuevos: pantalla "monedas aceptadas por tienda".
- Modificar: `lib/services/personal_rates_service.dart`, `lib/services/currency_service.dart:317-323` (quitar update global), `lib/widgets/global_config_tab_view.dart:732`, `lib/screens/sales_screen.dart`, `lib/widgets/tpv_managements/caja_turnos.dart`, `lib/models/caja_turno.dart`, `lib/services/caja_turno_service.dart`, `lib/services/caja_turno_pdf_service.dart`.
- Contabilidad financiera (Fase 6): `lib/services/financial_dashboard_service.dart`, `lib/services/financial_reports_service.dart`, `lib/services/financial_service.dart`, `lib/screens/financial_dashboard_screen.dart`, `lib/screens/financial_reports_screen.dart`, `lib/screens/financial_screen.dart`.
- Convergencia de catálogos (Fase 7): `lib/services/depositos_bancarios_service.dart`, `lib/services/pago_proveedores_service.dart`, `lib/screens/depositos_bancarios/monedas_depositos_screen.dart`, `lib/screens/pago_proveedores/monedas_proveedores_screen.dart`, `lib/models/currency_rate.dart`, `lib/services/currency_display_service.dart`, `lib/screens/inventory_extractionbysale_screen.dart:885`.

**Seguridad (Fase 8)**
- `ventiq_admin_app/lib/config/supabase_config.dart:9-16` y `ventiq_superadmin/lib/config/supabase_config.dart:9-16`: rotar la clave `service_role` y separar builds por rol.
- Políticas RLS nuevas en `supabase/migrations/`.

**`ventiq_app`**
- Nuevo: `lib/models/currency.dart`.
- Modificar: `currency_service.dart`, `price_utils.dart`, `checkout_screen.dart`, `order_service.dart`, `auto_sync_service.dart`, `cierre_screen.dart`, `apertura_screen.dart`, `cash_count_dialog.dart`, `bill_count_dialog.dart`, `orders_screen.dart`, `venta_total_screen.dart`, `order_product_summary.dart`, `usd_rate_chip.dart`, `turno_service.dart`, `user_preferences_service.dart`.

---

## 13. Glosario (para evitar ambigüedad)

| Término | Definición exacta en este plan |
|---|---|
| **Moneda nativa** | La moneda en que el cliente pagó físicamente (`moneda` + `monto`). Sumar por ella da importes **exactos, sin conversión**. |
| **Moneda base** | La moneda en la que se consolida la contabilidad. Hoy **CUP**. |
| **Tasa de cambio** | Valor de 1 unidad de moneda nativa expresado en moneda base, en el instante del cobro. Congelada por pago. |
| **Equivalente** | `monto × tasa_cambio`. Es `monto_cup_equivalente` en el esquema. Sirve para sumar monedas distintas. |
| **Importe nativo** | Suma de `monto` de una moneda. **No** es comparable entre monedas. |
| **Importe base** | Suma de `monto_cup_equivalente`. **Sí** es comparable y consolidable. |
| **Multimoneda** | Capacidad de cobrar en N monedas y contabilizar cada una por separado. No implica convertir precios. |

---

## 14. Siguiente paso

**Decisiones confirmadas el 2026-11-04** (§3.2): base CUP con desglose nativo y USD bajo demanda · habilitación por tienda desde el admin · operaciones e importes · sin tasa se bloquea el cobro · **alcance completo, fase a fase, sin diferir**.

**Fase 0 COMPLETADA** (§1.5, §1.6 y `diagnostico-resultado.md`) y **Fase 1 (SQL) APLICADA Y VERIFICADA en `newa`**.

**Flujo de despliegue — resuelto.** Hay dos servidores MCP de Supabase configurados en `~/.dsh/profiles/desktop/cordis.patch.yml`:

| `serverName` | proyecto | modo | uso |
|---|---|---|---|
| `supabase` | `vsieeihstajlrdvpuooh` | `read_only=true` | leer **producción** (no puede escribir: lo rechaza el servidor) |
| `supabase-debug` | `qhprswhhfasrikhawjoz` | escritura | aplicar y probar en **newa** |

El de `newa` estaba caído por un token caducado; corregido el 2026-11-04. **El ciclo ahora es autónomo:** escribo el `.sql`, lo aplico en newa, ejecuto la verificación y te enseño la salida real. El `.sql` solo se entrega para producción cuando la verificación en newa pasa.

**Fase 1 CERRADA.** SQL aplicado y verificado en `newa`, pantalla y servicio en la app superadmin, ruta concedida al rol. Lo único pendiente es el *click-through* en runtime (§8, Fase 1).

**Estado consolidado el 2026-11-04 (segunda medición, contra producción):**

| Fase | Estado real |
|---|---|
| 0 — verificación | ✅ completada |
| 1 — catálogo + superadmin | ✅ **SQL aplicado en producción** (`monedas` con 3 divisas, `tipos_moneda.codigo`, 5 RPC) · ⬜ click-through |
| 1b — tasa automática | ✅ **aplicada en producción** · 🔴 **el proveedor responde HTTP 403** y la caché está congelada desde el 29-oct (§4.8) |
| 1d — cron de tasas | ✅ **aplicado**, ambos jobs activos y ejecutándose |
| 2 — monedas por tienda | ✅ **aplicada en producción** (296 filas · 148 tiendas · 0 sin config) · ninguna con EUR |
| 3.1 — esquema de pago genérico | ✅ **aplicada en producción** (CHECK fuera, `character(3)`, FK, `_v3`) |
| 3.2 — app del TPV | ✅ código completo · **Checkpoint 3 ✅ verificado en el servidor (9/9)** · ⬜ end-to-end en la app |
| 3.3 — moneda de venta | ✅ completa (~85 sitios) · ⬜ click-through |

**Fase 4 en adelante:** no arrancar hasta cerrar los tres flecos de la Fase 3, que ya no son de código:

1. **End-to-end en la app** (el trozo que el servidor no puede probar): `flutter run`, habilitar EUR en una tienda, vender en EUR y comprobar `moneda`, `tasa_cambio`, `monto_cup_equivalente` y `es_pagada` desde la UI, más el ticket y el cierre.
2. **Arreglar el `HTTP 403` de la tasa automática** (§4.8) o darle a EUR una tasa manual. Sin esto, habilitar EUR cobra con una tasa de hace 7 días.
3. **Decidir sobre la partición de línea** (límite 1): el modelo soporta dos monedas en el mismo método y el servidor lo acepta (caso 9 del checkpoint), pero el checkout no tiene el control «+». Si es requisito de negocio, va antes de la Fase 4.

**Recordatorio de §3.2/§6.3 que la Fase 4 arrastra:** `turno_service` sigue eligiendo RPC por la presencia de un argumento USD; el arqueo por divisa necesita las RPC `*_monedas` y la tabla `app_dat_caja_turno_moneda` (§4.6).

**Seguridad (§4.7) — REVERIFICADA en producción el 2026-11-04: el hueco está CERRADO.**

Las 5 políticas permisivas `*_authenticated_all` **ya no existen**. Las tablas tienen lectura para autenticados y escritura restringida: `monedas`, `tipos_moneda`, `tasas_conversion` y `app_dat_denominaciones_moneda` → `fn_is_superadmin_full_access()`; `tasa_cambio_extraoficial` → `fn_user_can_access_tienda(id_tienda)` (cerrado también el `UPDATE` global que hacía el admin). ✅

Queda pendiente **R3**: rotar la clave `service_role` que viaja en el cliente de admin y superadmin (Fase 8). Mientras siga ahí, en release estas políticas **no protegen**.

**Orden de ejecución (sin cambios):**

| Orden | Fase | Riesgo para lo que hoy funciona |
|---|---|---|
| 1 | Fase 1 — catálogo + pantalla "Monedas" del superadmin | **Nulo** (no toca apps) |
| 2 | Fase 2 — monedas por tienda + tasas | **Nulo** (aditivo) |
| 3 | Fase 3 — cobro multimoneda en el TPV | Alto → requiere el checkpoint 3 completo antes de avanzar |
| 4 | Fase 4 — caja y arqueo (+ fix del bug contable activo) | Alto |
| 5 | Fase 5 — contabilización en el admin (**requiere R11 reparado antes**) | Medio |
| 6 | Fase 6 — contabilidad financiera | Medio |
| 7 | Fase 7 — convergencia de catálogos | Medio |
| 8 | Fase 8 — seguridad (rotar `service_role`, RLS) | **Iniciar en paralelo desde el principio** |
| 9 | Fase 9 — QA integral y documentación | — |

> **Nota sobre el orden:** las fases 1 y 2 no tocan las apps, así que lo primero que verás funcionando es "monedas administrables desde el superadmin" sin poner en riesgo el cobro actual. La Fase 8 (seguridad) no espera al final.
---

## 15. Pendiente anotado (2026-11-04): respaldo de la tasa automática cuando el proveedor da 403

**Origen:** al verificar el Checkpoint 3 se detectó que el proveedor de la tasa
automática responde `HTTP 403` en **todos** los intentos (ver §4.8). La caché
`flow.tasa_cambio` está congelada desde el 2026-10-29, `fn_tasa_automatica_estado()`
devuelve `vigente: false`, y los jobs de `pg_cron` reportan `succeeded` porque la
ingesta termina aunque no haya datos. Hoy eso hace que EUR y MLC se cobren con una
tasa de hace una semana.

**Encargo:** modificar la pieza que pide las tasas (la que hoy usa `pg_net` hacia el
proveedor primario) para que, **si la respuesta no es 2xx (caso actual: 403), pida
las tasas a una segunda API** — la misma que ya usa `ventiq_admin_app` para «el
toque» — **con un token distinto**.

**Requisitos de diseño:**

1. **El token va como secreto, NO en el repositorio.** Ni en este `plan.md`, ni en
   el `.sql`, ni en el cliente. Debe vivir en `Supabase Vault` o en el secreto de la
   Edge Function / configuración de `flow`, y leerse en tiempo de ejecución.
2. **Degradación en cadena:** primario → secundario → caché vigente → `NULL`
   (que bloquea el cobro, decisión B4). Nunca devolver una tasa inventada.
3. **Marcar la procedencia:** grabar `fuente` en `flow.tasa_cambio` con el nombre
   de la API que respondió, para que `fn_tasa_automatica_estado()` y la tarjeta del
   superadmin digan la verdad.
4. **No silenciar fallos:** si ambas APIs fallan, el job de ingesta debe registrar
   el error y **no** reportar `succeeded` a secas. Hoy un 403 se ve igual que un
   refresco correcto.
5. **Respetar la precedencia existente:** la tasa manual (tienda o global) sigue
   ganando a la automática; esto solo alimenta el último escalón.

**Criterio de aceptación:** con el proveedor primario devolviendo 403,
`fn_tasa_automatica_estado()` devuelve `vigente: true`, `fuente` = la API
secundaria, y `fn_tasa_cambio('EUR','CUP', …)` devuelve la tasa del día.

**Nota de seguridad:** el token que pasó el usuario para esta tarea **no se ha
escrito en ningún fichero del repo**. Hay que rotarlo igualmente si se compartió
por un canal no seguro, y darlo de alta como secreto.

---

## 16. Moneda de venta FORZADA por la tienda — ✅ implementado (2026-11-06)

La moneda de venta era una preferencia **del teléfono**; ahora la tienda puede imponerla.

| Pieza | Estado |
|---|---|
| SQL: `app_dat_configuracion_tienda.forzar_moneda_venta` + `moneda_venta_forzada` + trigger `trg_validar_moneda_forzada` | ✅ verificado en `newa` (4/4: forzar aceptada · sin moneda → error · moneda no aceptada → error · apagar → limpia la moneda sola) · ⬜ **producción** |
| Admin: bloque «Forzar moneda de venta» (switch + selector) bajo la tarjeta de monedas | ✅ código · se oculta con una sola moneda · apagar el switch limpia la divisa |
| Vendedor: chip **bloqueado** (candado + tooltip) y checkout sin selector por línea | ✅ código · si la forzada deja de ser válida se degrada al camino de siempre |

Fichero SQL: [`moneda_venta_forzada.sql`](docs/plan-multimoneda/moneda_venta_forzada.sql).
**Sin forzar, la tienda de siempre no cambia nada** (todas las ramas nuevas quedan inertes).

---

## 17. Fase 5b — el resto de las vistas de Ventas por moneda (pendiente)

La pestaña «Por moneda» es la única que hoy distingue divisas. **El resto sigue sumando
todo como si fuera una sola moneda.** Inventario verificado el 2026-11-06 (recon solo
lectura de `sales_screen.dart`):

| Pestaña | Qué unifica hoy | Qué haría falta | Esfuerzo |
|---|---|---|---|
| **Tiempo Real** | `_totalSales` = fold de `ingresosTotales`; la RPC `fn_reporte_ventas_con_proveedor5` **no devuelve divisa**. Tarjeta, tabla de productos y 2 exports con `$` | desglose en la RPC v5 + campo en `ProductSalesReport` + tarjeta/tabla/exports | RPC + UI |
| **TPVs** | `fn_reporte_ventas_por_turno` hace `SUM(pv.monto)` nativo sin columna de moneda | desglose en la RPC del turno | RPC + UI |
| **TPVs — atajo barato** | `_calculateVendorPaymentTotals` (:483-515), los bottom-sheets de transferencias (:9337) y el PDF «Reporte de Órdenes» ignoran `pago['moneda']` y `monto_cup_equivalente`, **que `listar_ordenes` ya devuelve** | solo leer lo que ya llega | **solo UI** |
| **Proveedores** | todo nace de la misma RPC v5 y se agrega en Dart (`_loadSupplierReports`) | desglose en la RPC + modelo | RPC + UI |
| **Desglose** | `reporte_ordenes_json` no manda `moneda` en `pagos` | extender la RPC (aditivo) + UI | RPC + UI |
| **Análisis** | solo precios/costos de catálogo con etiqueta USD/CUP | nada: no muestra cobros | — |
| **Paquetería** | `'$... CUP'` hardcodeado (`paqueteria_tab.dart:938`) | etiquetar la divisa real | solo UI |

**Código muerto encontrado de paso** (limpiar o cablear, no urgente): `_sales` nunca se
asigna y `todaySales`/`totalToday`/`salesCount` no se usan (Tiempo Real);
`SalesService.getSupplierSalesReport` no tiene llamador; `_showExportMenu` (export del
resumen de proveedores) tampoco.

**Enfoque adoptado (2026-11-06) — menos RPC de las que parecía.** Al revisarlo con
calma, la mayoría de las pestañas **no necesitan RPC nueva**: basta con consumir la
`fn_reporte_ventas_por_moneda` que ya existe y está verificada, y pintar un bloque
«Por moneda» con el mismo formato que la pestaña homónima.

| Pestaña | Pieza real | Estado |
|---|---|---|
| **Tiempo Real** | Bloque «Por moneda» **y** total consolidado en la tarjeta «Ventas» (el nativo no era sumable) | ✅ código |
| **Proveedores** | Ídem: bloque + tarjeta «Ventas Totales» y fila TOTAL consolidadas | ✅ código |
| **TPVs** | Solo UI en las hojas «Órdenes», «Transferencias» y «Órdenes Pendientes» + PDF; y las tarjetas por vendedor usan `fn_reporte_ventas_por_turno_v2` (`desglose_monedas` + `total_base`), con fallback a la vigente | ✅ código · ⬜ **falta aplicar el SQL de la v2 en producción** |
| **Desglose** | `reporte_ordenes_json` emite `moneda` + `monto_cup_equivalente` en cada pago | ✅ **producción** · [`fase5b_desglose_pagos_moneda.sql`](docs/plan-multimoneda/fase5b_desglose_pagos_moneda.sql) |
| **Paquetería** | La divisa real de la orden en vez del CUP hardcodeado | ✅ código |
| **Análisis** | Nada: no muestra cobros | — |

**SQL de la v2**: [`fase5b_informe_por_turno_desglose.sql`](docs/plan-multimoneda/fase5b_informe_por_turno_desglose.sql).
Ojo, tiene una particularidad importante: **`newa` y producción tienen versiones
distintas** de `fn_reporte_ventas_por_turno` (producción 13 columnas **por vendedor**;
`newa` 19 **por turno**). Escribir el `RETURNS TABLE` a mano habría dejado el fichero
sin poder probarse en uno de los dos entornos, así que la envoltura **se construye
contra el contrato desplegado** (`pg_get_function_result`) y elige el desglose según
lo que la vigente tenga. Verificado en `newa`: misma cantidad de filas que la vigente
y desglose que cuadra (292.530 efectivo + 18.950 digital = 311.480).

**⚠️ CORRECCIÓN DE CRITERIO (2026-11-06, leyendo el SQL desplegado).** En §17 se dijo que
Tiempo Real y Proveedores «unifican en una sola moneda» y que hacía falta el desglose en la
RPC v5. **Es falso**, y la conclusión estaba mal:

```sql
-- fn_reporte_ventas_con_proveedor4
-- 5. Enriquecer cada línea con precio cobrado, tasa y costo históricos.
--    Precio de venta = lo cobrado en la operación (no la lista de precios).
importe_op = COALESCE(vd.importe, vd.cantidad * vd.precio_unitario)
SUM(COALESCE(ve.importe_op, ve.precio_venta_cup_op * ve.cantidad)) AS ingresos_totales
```

`ingresos_totales` —lo que suman `_totalSales` y las columnas de Proveedores— **ya está en
moneda base**, porque sale del importe de la línea de la operación, no de los pagos nativos.
No hay nada que consolidar: lo que faltaba era **etiquetar** la cifra como CUP (un `$` sin
código es ambiguo) y, como mucho, mostrar **al lado** el bloque «Por moneda (cobrado)», que
mide otra cosa.

Sustituir esos totales por el consolidado de pagos fue un error: mezclaba dos fuentes
(facturado a precio de operación vs cobrado en pagos) y hacía que el total dejara de cuadrar
con las filas visibles. **Revertido.** Por lo mismo, **la RPC v5 no necesita desglose**:
aquel «RPC + UI» del inventario era una lectura equivocada de la dimensión.

La distinción que sí importa y hay que mantener clara en la UI:
**facturado** (`ingresos_totales`, CUP por construcción) vs **cobrado** (`desglose_monedas`,
nativo por divisa + equivalente). Son dos métricas distintas y no tienen por qué coincidir
(descuentos, pagos parciales, CxC).

Lo que queda de §17 es solo el punto 3: **los exports** (Tiempo Real y Proveedores) con el
bloque «Por moneda (cobrado)».
**Limitación conocida y asumida**: los bloques y consolidados por divisa salen de los
**pagos** del período de la pestaña, así que **no respetan el filtro de almacén** ni
`_productDateFilterMode`. Con ≥2 divisas, la fila TOTAL de Proveedores ya no cuadra con
la suma de las filas visibles. El arreglo de fondo es añadir el desglose a la RPC v5
(`fn_reporte_ventas_con_proveedor5`) para que cada producto/proveedor traiga su divisa;
está pendiente y es lo único que queda de §17 junto con los exports (los de Tiempo Real
y Proveedores siguen usando el total nativo).

Detalle del parche de `reporte_ordenes_json`: devuelve `jsonb` (no una `RETURNS TABLE`),
así que se puede hacer `CREATE OR REPLACE` **sin soltarla** y las claves nuevas son
aditivas. El parche se aplica sobre el texto desplegado (`pg_get_functiondef`) y es
fail-closed: si el cuerpo no es el esperado, aborta sin tocar nada.
**Base reutilizable**: `fn_reporte_ventas_por_moneda` ya devuelve
`moneda, operaciones, importe_nativo, importe_base, efectivo_nativo, digital_nativo,
tasa_promedio`. Las pestañas que necesitan RPC nueva son v5 (Tiempo Real + Proveedores, la
misma), `fn_reporte_ventas_por_turno` (TPVs) y `reporte_ordenes_json` (Desglose).

---

## 18. Moneda de consolidación del admin — 🟡 en curso (2026-11-06)

**Qué resuelve**: en Ventas todo se consolidaba en CUP. Una tienda que vende **solo** en
USD obligaba a convertir mentalmente. Ahora la moneda de consolidación es la que la tienda
**fuerza** (`forzar_moneda_venta` + `moneda_venta_forzada`); **CUP cuando no fuerza nada**
—decisión del usuario, y así las 2.336 tiendas actuales no cambian—.

**Cómo se consolida cada fila, que es lo que importa:**

| Fila | Cómo | Exactitud |
|---|---|---|
| De la propia moneda de consolidación | `importe_nativo` | **exacta** (si vende solo en USD, el consolidado ES lo cobrado en USD) |
| De otra divisa | `importe_base × tasa(CUP→X)` | **aproximada** (la tasa de hoy no es la histórica) |

Reconvertir el equivalente en CUP de un pago que **ya estaba** en la divisa de consolidación
metería un error gratuito: en producción hay USD cobrado a 550, 800 y 900, así que la tasa
histórica no es una sola. Por eso el RPC devuelve `importe_consolidado` **por fila** y la UI
solo suma esa columna; no sabe de tasas.

| Pieza | Estado |
|---|---|
| SQL `fn_moneda_consolidacion(p_id_tienda)` → `(moneda, tasa_cup, es_base)`, fail-safe a CUP | ✅ verificado en `newa` (sin forzar → CUP/1; forzando USD → USD/0,001183) |
| SQL `fn_reporte_ventas_por_moneda` + `moneda_consolidacion` + `importe_consolidado` | ✅ verificado (5.330.900 CUP × 0,001183 = 5.794,69 USD) · ⬜ **producción** |
| Servicio `MonedaConsolidacionService` (carga única, convierte y formatea) | 🟡 en curso |
| `sales_screen.dart`: convertir todo lo que hoy es CUP por construcción + pie del bloque + rótulos + exports | 🟡 en curso |
| `paqueteria_tab.dart`: totales agregados | 🟡 en curso |

Fichero SQL: [`moneda_consolidacion_admin.sql`](docs/plan-multimoneda/moneda_consolidacion_admin.sql).

**Criterio de la UI**: se convierten los importes **CUP por construcción** (facturado a precio
de operación, costos, ganancias, totales). **No** se convierten los importes **nativos** por
divisa del bloque «Por moneda (cobrado)»: ya llevan su código y son lo que se cobró.