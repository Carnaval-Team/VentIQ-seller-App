# Fase 0 — Resultado del diagnóstico contra la base real

**Fecha:** 2026-11-04
**Conexión:** MCP de Supabase, usuario `supabase_read_only_user` (solo lectura), PostgreSQL 17.4, 239 tablas en `public`.
**Nota de identidad:** no fue posible leer el `project_ref` desde SQL (`current_setting('request.headers')` y `supabase.project_ref` devuelven `null`). Los datos observados (129.331 pagos, `tasas_conversion` actualizada el 2026-11-03) corresponden a un entorno **con datos vivos**. Se asume **producción**, coherente con lo indicado. Confirmar si se desea precisión.

> Efecto de este documento: **corrige cuatro supuestos del `plan.md`** escritos a partir del volcado `VentiQ.sql` del repo. Los volcados del repo estaban desactualizados; todo lo de abajo es observación directa.

---

## 1. Correcciones al plan

| # | Supuesto del plan (desde el repo) | Realidad verificada | Impacto |
|---|---|---|---|
| C1 | `monedas.codigo` es `character` sin longitud = `bpchar(1)`, no cabe `'USD'` → habría que hacer `ALTER COLUMN` | **`character(3)`** (`character_maximum_length = 3`), `NOT NULL`, PK. `'USD'` **sí** cabe | **Se elimina el `ALTER COLUMN`** de §4.1. El volcado perdía el `(3)`. |
| C2 | `monedas` no tenía seed conocido | Tiene 2 filas: `CUP` (símbolo `cup`, Cuba) y `USD` (símbolo `$`) | La FK `app_dat_pago_venta.moneda → monedas(codigo)` no rompe con los datos actuales (solo hay CUP/USD). |
| C3 | RLS de los catálogos de moneda "NO ENCONTRADO" en el repo | **RLS está habilitado** en las 5 tablas, con políticas **permisivas**: `FOR ALL TO authenticated USING (true) WITH CHECK (true)` | El hueco no es "falta RLS" sino **"RLS demasiado abierto"**: cualquier trabajador de tienda puede crear monedas y cambiar la tasa global. Sube la severidad. |
| C4 | `tipos_moneda` se asumía con `codigo` (puente por añadir) | No tiene `codigo`; sí `id bigint`, `denominacion text`, `simbolo text`, `nombre_corto text`, `pais text`, `activo bool`, `created_at`, `updated_at`. Solo 2 filas: `1`=CUP, `2`=USD | El puente de §4.2 sigue siendo necesario y es viable. |

---

## 2. Esquema real (observado)

### 2.1 Catálogos

```sql
-- public.monedas            (PK codigo)
codigo        character(3)    NOT NULL
nombre        varchar(50)     NOT NULL
simbolo       varchar(10)
pais          varchar(50)
activo        boolean         DEFAULT true
creado_en     timestamp
actualizado_en timestamp
-- Filas: CUP, USD

-- public.tipos_moneda       (PK id, bigint)  ← sin 'codigo'
id, denominacion, simbolo, nombre_corto, pais, activo, created_at, updated_at
-- Filas: (1, Peso Cubano, ₱, CUP, Cuba), (2, Dólar Estadounidense, $, USD, Estados Unidos)

-- public.tasas_conversion   (global)
id, moneda_origen character(3), moneda_destino character(3), tasa numeric, fecha_actualizacion
-- 1 fila: USD→CUP = 900.000000 (2026-11-03)

-- public.tasa_cambio_extraoficial   (POR TIENDA)
id bigint, id_moneda_origen bigint, id_moneda_destino bigint,
valor_cambio numeric, usar_precio_toque bool DEFAULT false, activo bool DEFAULT true,
created_at, updated_at, id_tienda bigint NOT NULL
-- 73 filas, todas USD(2)→CUP(1), una por tienda

-- public.app_dat_denominaciones_moneda
id bigint, codigo_moneda varchar(10) NOT NULL, denominacion numeric NOT NULL,
created_at, updated_at, active bool DEFAULT true
-- CUP: 14 denominaciones [20000,10000,5000,2000,1000,500,200,100,50,20,10,5,3,1]
-- USD: 6  denominaciones [100,50,20,10,5,1]
```

**Conclusión sobre identidad de moneda:** `app_dat_denominaciones_moneda.codigo_moneda` es `varchar(10)` — ya soporta cualquier código y **no** tiene FK. `tasa_cambio_extraoficial` usa **ids bigint** de `tipos_moneda`. El pago usa texto. Los tres espacios de identidad siguen siendo tres; el puente `tipos_moneda.codigo` (§4.2 del plan) es la pieza que los une.

### 2.2 Pago de venta

```sql
-- public.app_dat_pago_venta: constraints reales
app_dat_pago_venta_moneda_check  CHECK (moneda = ANY (ARRAY['CUP','USD']))   ← EL BLOQUEANTE
app_dat_pago_venta_monto_check   CHECK (monto >= 0)
app_dat_pago_venta_pkey          PRIMARY KEY (id)
+ 4 FKs (operacion_venta, medio_pago, creado_por, id_liquidacion)
```

`moneda` sigue siendo `TEXT`. Nota técnica: al crear la FK `moneda → monedas(codigo)` hay **desajuste de tipos** (`text` vs `bpchar(3)`). Postgres no garantiza esa FK; hay que `ALTER COLUMN moneda TYPE character varying(3)` primero (coste trivial: 129.331 filas).

### 2.3 Caja/turno

`app_dat_caja_turno` tiene **`efectivo_inicial_usd`**, **`efectivo_real_usd`**, **`diferencia_usd`** (las tres `numeric` nullable), más una columna que no está en el repo: **`cierre_solicitado_at`**.

Uso real: de **3.385 turnos**, `0` tienen `efectivo_inicial_usd ≠ 0` y **solo 1** tiene `efectivo_real_usd`. → **El arqueo USD está prácticamente sin usar.** Migrar a multimoneda por tabla hija es casi greenfield, con riesgo de datos mínimo.

### 2.4 RLS (evidencia)

```
tabla                             rls_habilitado  política
monedas                           true            monedas_authenticated_all                       ALL authenticated USING true / WITH CHECK true
tipos_moneda                      true            tipos_moneda_authenticated_all                   ALL authenticated USING true / WITH CHECK true
tasas_conversion                  true            tasas_conversion_authenticated_all               ALL authenticated USING true / WITH CHECK true
tasa_cambio_extraoficial          true            tasa_cambio_extraoficial_authenticated_all       ALL authenticated USING true / WITH CHECK true
app_dat_denominaciones_moneda     true            app_dat_denominaciones_moneda_authenticated_all  ALL authenticated USING true / WITH CHECK true
```

**Cualquier usuario autenticado puede INSERT/UPDATE/DELETE el catálogo global de monedas y la tasa global.** Los helpers para corregirlo **ya existen** en producción y son `SECURITY DEFINER`:

- `public.fn_is_superadmin_full_access()`
- `public.fn_user_can_access_tienda(p_id_tienda bigint)`
- `public.fn_get_tienda_by_operacion_venta(p_id_operacion_venta bigint)`

Tablas de permisos: `app_dat_superadmin(uuid, activo, nivel_acceso, id_rol)`, `app_dat_superadmin_roles(permisos jsonb)`.

### 2.5 Funciones desplegadas (relevantes)

Existen: `fn_registrar_pago_venta`, `fn_registrar_pago_venta_v2`, `fn_registrar_pago_venta_offline`;
`fn_registrar_venta` / `_v2` / `_v3` / `_mesa` / `_mesa_v2` / `_mesa_v3`;
`fn_registrar_venta_offline` (2 sobrecargas) / `_v2` / `_v3` / `_v4`;
`registrar_apertura_turno` / `_v2` / `_v3` / `_usd`; `fn_cerrar_turno_tpv` / `_usd` / `_offline` / `_offline_usd`;
`fn_resumen_diario_cierre` / `_v2` / `_v3`; `fn_listar_turnos_admin`; `fn_reporte_ventas_*` (14 variantes).

**`fn_registrar_pago_venta_v3` NO existe** → el nombre propuesto en el plan está libre. `fn_resumen_diario_cierre_v4` tampoco existe.

---

## 3. Calidad de datos: `monto_cup_equivalente` NO es fiable

Este es el hallazgo más serio y **no** estaba en el plan original.

### 3.1 Volumen por moneda

| moneda | pagos | operaciones | importe nativo | equivalente CUP | tasa |
|---|---:|---:|---:|---:|---|
| CUP | 129.331 | 128.053 | 3.779.969.621,44 | 3.631.263.202,44 | — |
| USD | 8 | 8 | 230,1454545 | 129.080,00 | 550 (7) y 800 (1) |

### 3.2 Inconsistencia detectada

| Métrica | Valor |
|---|---:|
| Filas CUP con `monto_cup_equivalente` **NULL** | **666** |
| Filas CUP con `monto_cup_equivalente = monto` | 128.298 |
| Filas CUP con `monto_cup_equivalente ≠ monto` | 1.033 (= 666 NULL + 367 distintas) |
| Filas donde el equivalente **es el total de la operación** mientras `monto` es una parte | **97** |
| Operaciones con al menos una fila NULL | 664 |
| …de esas, donde el total ya está en otra fila | 116 |
| …de esas, donde **hoy descuadra** | **548** |
| `monto` acumulado en esas 664 operaciones | **133.304.184** |
| `monto_cup_equivalente` acumulado en esas 664 operaciones | **3.781.280** |

**Consecuencia:** hay del orden de **129 millones de CUP de pagos cuyo equivalente no está registrado**. Cualquier reporte que sume `monto_cup_equivalente` (es decir, la mayoría) **subestima**.

### 3.3 Patrón de la anomalía (muestras reales)

```
op 182478  fila 129340  medio 1  monto  9.020  equivalente 43.020   (12:36:53)
           fila 129341  medio 4  monto 34.000  equivalente   NULL   (12:37:08)
op 182416  fila 129282  medio 4  monto 31.500  equivalente 63.000
           fila 129283  medio 1  monto 31.500  equivalente   NULL
op 182553  fila 129408  medio 1  monto      0  equivalente 63.000
```

En los casos de dos filas, **una fila lleva el total de la operación** (`equiv = suma de los montos`) y la otra queda `NULL`. No es "falta el dato" solamente: es que **el equivalente se escribió con la granularidad equivocada** (total de la operación en una línea de pago).

### 3.4 Reconciliación por operación contra `importe_total`

| Métrica (128.053 operaciones CUP) | Valor |
|---|---:|
| `sum(monto)` coincide con `importe_total` | 126.691 |
| `sum(monto_cup_equivalente)` coincide con `importe_total` | 126.045 |
| Ninguno de los dos coincide | **1.277** |

`importe_total` nunca es NULL (0 casos).

### 3.5 Causa raíz — parcial

- **Confirmado (código):** `fn_registrar_pago_venta_offline` **no escribe** `monto_cup_equivalente` ni usa `tasa_usd` (su definición no menciona ninguna de las dos). Es un agujero latente: todo pago registrado por esa RPC queda con `NULL`.
- **Descartado:** las 666 filas NULL **no** tienen registro en `app_dat_operacion_offline_idempotencia` (0 de 666). Es decir, **no** vienen de ese camino.
- **Hipótesis pendiente:** hay un **segundo camino de escritura** que crea/edita líneas de pago con granularidad incorrecta. El candidato más probable es el flujo de edición de órdenes (`ventiq_app/supabase/pending_order_edit_v2.sql`, que hace `UPDATE ... SET monto_cup_equivalente = monto_cup_equivalente + v_diferencia` y reescribe `monto`). **Requiere investigación dedicada antes de la Fase 3.**

### 3.6 Impacto en el plan

1. **La reparación correcta es recalcular fila por fila** `monto_cup_equivalente = round(monto * COALESCE(tasa_cambio,1), 2)`. Es determinista y arregla a la vez los 666 NULL y las 97 filas infladas.
   **Lo que NO hay que hacer** es un backfill *parcial* (rellenar solo los NULL copiando `monto`): en las 116 operaciones donde el total inflado ya vive en una fila hermana, eso dejaría la suma al doble. *(Corrección de una afirmación previa de este documento, que atribuía el riesgo de duplicación al backfill completo y no al parcial.)*
2. La migración necesita **medir → respaldar → recalcular → verificar**, con comparación contra `importe_total`.
3. Hay que **corregir el defecto de granularidad en el camino de escritura** (identificar el segundo escritor) y cerrar el agujero de `fn_registrar_pago_venta_offline`, que no escribe el equivalente.
4. `monto_cup_equivalente` **no puede** ser la única fuente del importe base hasta que esté reparado. En la Fase 3 conviene calcular el equivalente de forma explícita (`monto × tasa`) y tratar el valor almacenado como caché verificable.

---

## 4. Lo que NO se pudo verificar

- **`project_ref`**: no legible desde SQL. Confirmar si esta conexión es producción o la rama `newa`.
- **Contenido de las definiciones de función**: solo se comprobó presencia/ausencia de las cadenas `monto_cup_equivalente` y `tasa_usd` en `fn_registrar_pago_venta*`; no se auditó el cuerpo completo de cada RPC.
- **Políticas RLS de `app_dat_caja_turno` y `app_dat_pago_venta`**: RLS habilitado, políticas no listadas en esta pasada.
- **`dep_nom_moneda` / `prv_nom_moneda`**: existencia confirmada; contenido y RLS no auditados en esta pasada.
- **`tipos_moneda` sin `codigo`**: la migración de §4.2 añade la columna, pero **hay que confirmar que `newa` comparte el mismo esquema** antes de aplicar.

---

## 5. Estado de la Fase 0

**COMPLETADA** en lo esencial. Desbloquea las fases 1 y 2 (catálogo + superadmin), que no dependen de las incógnitas restantes.

**Pendiente antes de la Fase 3** (no bloquea empezar):
- Investigar el segundo camino de escritura de pagos (§3.5).
- Diseñar la reconciliación por operación (§3.6).
- Confirmar esquema de `newa`.
