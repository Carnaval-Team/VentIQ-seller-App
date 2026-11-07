# Recon: esquema de datos multimoneda (Supabase/SQL)

- **Tarea:** task-1 — "Recon: esquema de datos multimoneda (Supabase/SQL)"
- **Autor:** teammate `recon-esquema` (solo lectura sobre el repo; único archivo escrito: este)
- **Repo:** `C:\Users\cesar\Documents\VentIQ-seller-App`
- **Fecha:** 2026-11-04
- **Restricción de método:** el MCP de Supabase no tiene conectividad (`list_tables` → "fetch failed"), por lo que **todo** se infiere de volcados SQL y del código Dart del repo. No se ejecutó nada contra la base viva, salvo lo que cito como afirmación de un documento del repo (`[DOC]`).

## 0. Clases de evidencia usadas en este documento

| Marca | Significado |
|---|---|
| `[DDL-REPO]` | Sentencia `CREATE TABLE` literal presente en el repo (copiada textualmente). |
| `[ALTER-REPO]` | `ALTER TABLE ... ADD COLUMN` literal presente en el repo. |
| `[DART]` | Esquema **inferido** de las consultas Supabase de la app (`.from(...).select(...)`, `.insert({...})`). No hay DDL en el repo. |
| `[DOC]` | Afirmación escrita en un markdown del repo; **no verificada en vivo por mí**. |
| `[NO ENCONTRADO]` | Búsqueda explícita sin resultados; se indica dónde se buscó. |

### Fuentes SQL inventariadas (para que el recon sea reproducible)

- `VentiQ.sql` (1391 líneas). Verificado por grep: contiene **exactamente 100 `CREATE TABLE`** y **ninguna** sentencia `GRANT`, `POLICY`, `ROW LEVEL SECURITY`, `CREATE INDEX`, `CREATE FUNCTION` ni `CREATE VIEW` (la única coincidencia del grep de esos tokens es el FK de `VentiQ.sql:1115`). Es un volcado **parcial y desactualizado**: le faltan tablas que el propio volcado referencia por FK.
- 16 `*.sql` en la raíz (`a revisar.sql`, `bien.sql`, `detalles_prodcuto.sql`, `get_productos_by_categoria_tpv_search_meta.sql`, `inventario_prodcut_paged*.sql`, `listar_ordenes_mesa.sql`, `mesa_cuenta_abierta.sql`, `mesas_schema.sql`, `products_screen.sql`, `registrar_venta_mesa.sql`, `registrar_venta_reworked.sql`, `registrarventa_ok.sql`, `suscripcion_data.sql`, `VentiQ.sql`, `VentiQ_carnavalapp.sql`).
- `sql_updates/` (50 .sql), `sql_triggers/` (2), `SQL_OPTIMIZATION/` (85), `supabase/migrations/` (8), `ventiq_app/sql` (6) + `ventiq_app/sql_offline` (15) + `ventiq_app/supabase` (10), `ventiq_admin_app/lib/sql` + `ventiq_admin_app/docs/migrations` + `ventiq_admin_app/SQL_OPTIMIZATION`, `presentaciones_inventario/`, `funcionalidad_cocina/`, `funcionalidad_servicentro/`, `carnavalAPP/sql_updates/`, `inventtia_flow/docs/flow_schema/migraciones/`, `inventtia_muevete/docs/migrations/`.
- **NO ENCONTRADO**: ningún `.dump`, `schema.sql`, `*.psql` ni `*.schema`. Búsqueda por listado recursivo de `*.sql,*.dump,*.psql,*.schema` ordenado por tamaño en todo el repo.
- Los archivos más grandes del repo (por si el lector quiere ampliar) son: `inventtia_flow/docs/sync_flow_newa_desde_main.sql` (438 KB), `inventtia_flow/docs/flow_schema/migraciones/_APLICAR_RELEASE_60_67.sql` (158 KB), `funcionalidad_cocina/21_tandas_produccion.sql` (56 KB), `VentiQ.sql` (74 KB). Ninguno de los grandes es un volcado del esquema `public` orientado a moneda/venta.

---

## 1. Tablas y columnas exactas

### 1.1 `public.monedas` — `[DDL-REPO]` `VentiQ.sql:1195-1204`

```sql
CREATE TABLE public.monedas (
  codigo character NOT NULL,
  nombre character varying NOT NULL,
  simbolo character varying,
  pais character varying,
  activo boolean DEFAULT true,
  creado_en timestamp without time zone DEFAULT now(),
  actualizado_en timestamp without time zone DEFAULT now(),
  CONSTRAINT monedas_pkey PRIMARY KEY (codigo)
);
```

- PK: `codigo`. Sin `id_tienda` → **global**. Sin FKs entrantes salvo `tasas_conversion`.
- ⚠️ `codigo character` (sin longitud) = `bpchar(1)`: **no admite `'USD'`**. Ver §7.2.
- No hay `INSERT` semilla en el repo para esta tabla.

### 1.2 `public.tasas_conversion` — `[DDL-REPO]` `VentiQ.sql:1205-1214`

```sql
CREATE TABLE public.tasas_conversion (
  id integer NOT NULL DEFAULT nextval('tasas_conversion_id_seq'::regclass),
  moneda_origen character NOT NULL,
  moneda_destino character NOT NULL,
  tasa numeric NOT NULL,
  fecha_actualizacion timestamp without time zone DEFAULT now(),
  CONSTRAINT tasas_conversion_pkey PRIMARY KEY (id),
  CONSTRAINT tasas_conversion_moneda_origen_fkey FOREIGN KEY (moneda_origen) REFERENCES public.monedas(codigo),
  CONSTRAINT tasas_conversion_moneda_destino_fkey FOREIGN KEY (moneda_destino) REFERENCES public.monedas(codigo)
);
```

- Sin `id_tienda` → **global**. No hay `UNIQUE (moneda_origen, moneda_destino)` → pueden coexistir varias filas del mismo par; el código resuelve "la más reciente" ordenando por `fecha_actualizacion DESC` (`ventiq_app/lib/services/currency_service.dart:38-41,199-207`).
- Los consumidores leen `moneda_origen = 'USD'` y `moneda_destino = 'CUP'` como texto (`currency_service.dart:151-152`), lo que **contradice** el `bpchar(1)` de §1.1 (ver §7.2).

### 1.3 `public.tasa_cambio_extraoficial` — `[DART]` (DDL `[NO ENCONTRADO]`)

**NO ENCONTRADO** el `CREATE TABLE` en el repo: grep de `CREATE TABLE (IF NOT EXISTS )?(public\.)?(app_dat_denominaciones_moneda|tasa_cambio_extraoficial)` en todo el repo → 0 coincidencias. La tabla existe en la base viva (los triggers y las apps la usan). Columnas reconstruidas por uso:

| Columna | Tipo inferido | Evidencia |
|---|---|---|
| `id` | int/bigint | `personal_rates_service.dart:65` (`select('id, ...')`), `:152` (`update` por `id`) |
| `id_moneda_origen` | int con FK → `tipos_moneda.id` | `personal_rates_service.dart:29-35` embebe `moneda_origen: id_moneda_origen (id, denominacion, simbolo, nombre_corto, pais)` |
| `id_moneda_destino` | int con FK → `tipos_moneda.id` | `personal_rates_service.dart:37,50,119,161` (`cupId = 1`) |
| `valor_cambio` | numeric | `currency_service.dart:17,73`; `trigger_actualizar_precios_cup_por_tasa_usd.sql:29,33` |
| `usar_precio_toque` | boolean | `personal_rates_service.dart:104,121,163`; `sync_valor_usd_carnaval.sql:25` |
| `activo` | boolean | `personal_rates_service.dart:39,51,69,122,164`; `:86,151,173` (soft delete/`update {'activo': false}`) |
| `created_at` | timestamptz | `currency_service.dart:17,22`; `personal_rates_service.dart:27,40` |
| `id_tienda` | bigint **NOT NULL** (los inserts siempre lo mandan) | `personal_rates_service.dart:38,48,66,87,123,165`; `trigger_actualizar_precios_cup_por_tasa_usd.sql:34`; `sync_valor_usd_carnaval.sql:22` |

Convención de ids de moneda, repetida y hardcodeada: **1 = CUP, 2 = USD** (`ventiq_app/lib/services/currency_service.dart:7-8`; `ventiq_admin_app/lib/services/currency_service.dart:15-16`; `personal_rates_service.dart:6`; `SQL_OPTIMIZATION/trigger_actualizar_precios_cup_por_tasa_usd.sql:17,47`; `sql_triggers/sync_valor_usd_carnaval.sql:2`).

No hay `UNIQUE` conocido (el servicio implementa "solo una activa por par" a mano: `personal_rates_service.dart:99-125`).

### 1.4 `public.tipos_moneda` — `[DART]` (DDL `[NO ENCONTRADO]`)

Única referencia en **todo** el repo (grep `tipos_moneda` → 1 coincidencia):

```
ventiq_admin_app/lib/services/personal_rates_service.dart:11-14
  .from('tipos_moneda')
  .select('id, denominacion, simbolo, nombre_corto, pais, activo')
  .eq('activo', true)
  .order('denominacion');
```

→ Columnas: `id`, `denominacion`, `simbolo`, `nombre_corto`, `pais`, `activo`. Es el catálogo al que apunta la FK de `tasa_cambio_extraoficial` (§1.3). Sin `id_tienda` → **global** (el filtro por tienda se hace con `tasa_cambio_extraoficial.id_tienda`). **NO ENCONTRADO**: DDL, seed, CRUD (ningún `insert/update/delete` a `tipos_moneda` en el repo).

### 1.5 Denominaciones / billetes → **el nombre real es `public.app_dat_denominaciones_moneda`** — `[DART]` (DDL `[NO ENCONTRADO]`)

No existe una tabla llamada `denominaciones`. La tabla real la lee la app del vendedor:

```
ventiq_app/lib/screens/login_screen.dart:730-735
  .from('app_dat_denominaciones_moneda')
  .select('*')
  .eq('active', true)
  .order('codigo_moneda', ascending: true)
  .order('denominacion', ascending: true);
```

Columnas usadas por el código: `id` (`ventiq_app/lib/widgets/bill_count_dialog.dart:128,141,160`), `codigo_moneda` (`login_screen.dart:734,747,754`), `denominacion` (`login_screen.dart:755`), `active` (`login_screen.dart:733`; `user_preferences_service.dart:4744`).

Se cachea offline junto a la tasa: `ventiq_app/lib/services/user_preferences_service.dart:4686-4757` (`saveMonedasDenominacion`, `getMonedasDenominacion`, `getDenominacionesPorMoneda` filtra `codigo_moneda` + `active`).

**NO ENCONTRADO** (buscado en todo el repo): DDL; cualquier `insert`/`update`/`delete`; cualquier pantalla de administración. Grep `app_dat_denominaciones_moneda` → **1 sola coincidencia** (`login_screen.dart:731`). Grep `codigo_moneda` → 6 coincidencias, todas en `login_screen.dart` y `user_preferences_service.dart`.
Tampoco se puede saber si es global o por tienda: el `select` no filtra `id_tienda` (`login_screen.dart:730-735`).

> No confundir con las decenas de columnas `denominacion character varying` de tablas nomencladoras (p. ej. `app_nom_medio_pago.denominacion` en `VentiQ.sql:1091`, `app_nom_unidades_medida.denominacion` en `VentiQ.sql:1285`).

### 1.6 `public.app_dat_pago_venta`

**Base `[DDL-REPO]` `VentiQ.sql:1098-1116`:**

```sql
CREATE TABLE public.app_dat_pago_venta (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_operacion_venta bigint NOT NULL,
  id_medio_pago smallint NOT NULL,
  monto numeric NOT NULL CHECK (monto >= 0::numeric),
  referencia_pago character varying,
  id_institucion_financiera bigint,
  fecha_pago timestamp with time zone NOT NULL DEFAULT now(),
  creado_por uuid NOT NULL,
  tipo_pago bigint,
  importe_sin_descuento numeric,
  created_at timestamp with time zone DEFAULT now(),
  id_liquidacion bigint,
  CONSTRAINT app_dat_pago_venta_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_pago_venta_id_operacion_venta_fkey FOREIGN KEY (id_operacion_venta) REFERENCES public.app_dat_operacion_venta(id_operacion),
  CONSTRAINT app_dat_pago_venta_id_medio_pago_fkey FOREIGN KEY (id_medio_pago) REFERENCES public.app_nom_medio_pago(id),
  CONSTRAINT app_dat_pago_venta_creado_por_fkey FOREIGN KEY (creado_por) REFERENCES auth.users(id),
  CONSTRAINT app_dat_pago_venta_id_liquidacion_fkey FOREIGN KEY (id_liquidacion) REFERENCES public.app_dat_liquidacion_cxc(id)
);
```

**Columnas añadidas después `[ALTER-REPO]`:**

```sql
-- ventiq_app/sql/venta_usd.sql:1-19
ALTER TABLE public.app_dat_pago_venta
  ADD COLUMN IF NOT EXISTS moneda TEXT NOT NULL DEFAULT 'CUP',
  ADD COLUMN IF NOT EXISTS tasa_usd NUMERIC,
  ADD COLUMN IF NOT EXISTS monto_cup_equivalente NUMERIC;
...
UPDATE public.app_dat_pago_venta
SET moneda = 'CUP',
    monto_cup_equivalente = monto
WHERE monto_cup_equivalente IS NULL;

ALTER TABLE public.app_dat_pago_venta
  DROP CONSTRAINT IF EXISTS app_dat_pago_venta_moneda_check;
ALTER TABLE public.app_dat_pago_venta
  ADD CONSTRAINT app_dat_pago_venta_moneda_check CHECK (moneda IN ('CUP', 'USD'));
```

```sql
-- ventiq_admin_app/docs/migrations/10_cuentas_por_cobrar.sql:57-59
ALTER TABLE public.app_dat_pago_venta
  ADD COLUMN IF NOT EXISTS id_liquidacion bigint
    REFERENCES public.app_dat_liquidacion_cxc(id);
```

**Esquema efectivo (unión):** `id`, `id_operacion_venta`, `id_medio_pago`, `monto` (CHECK ≥ 0), `referencia_pago`, `id_institucion_financiera`, `fecha_pago`, `creado_por` (FK `auth.users`), `tipo_pago`, `importe_sin_descuento`, `created_at`, `id_liquidacion` (FK `app_dat_liquidacion_cxc`), **`moneda` TEXT NOT NULL DEFAULT `'CUP'` CHECK IN (`'CUP'`,`'USD'`)**, **`tasa_usd` NUMERIC NULL**, **`monto_cup_equivalente` NUMERIC NULL**.

- **Sin `id_tienda`** (la tienda se deriva vía `app_dat_operacion_venta` → `app_dat_operaciones.id_tienda`; así lo hace el helper de RLS `09_pago_venta_gerente_rls.sql:12-20`).
- `venta_usd.sql` es un script manual ("`APLICAR MANUALMENTE en Supabase SQL Editor`", `fn_registrar_pago_venta_idempotente.sql:15`) **sin timestamp de migración** → su aplicación no es verificable desde el repo. `[DOC]` `docs/payment_methods_pendientes.md:10-12` afirma que la versión con moneda **sí** está desplegada en vivo.

### 1.7 `public.app_dat_operacion_venta` — `[DDL-REPO]` `VentiQ.sql:401-425`

```sql
CREATE TABLE public.app_dat_operacion_venta (
  id_operacion bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tpv bigint NOT NULL,
  denominacion character varying,
  codigo_promocion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_promocion bigint,
  id_cliente bigint,
  importe_total numeric,
  es_pagada boolean NOT NULL DEFAULT true,
  id_turno_apertura bigint,
  precio_con_descuento_total numeric,
  id_mesa bigint,
  foto_operacion_url text,
  pago_sms_json jsonb,
  id_cliente_cxc bigint,
  CONSTRAINT app_dat_operacion_venta_pkey PRIMARY KEY (id_operacion),
  CONSTRAINT app_operacion_extraccion_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_operacion_extraccion_id_tpv_fkey FOREIGN KEY (id_tpv) REFERENCES public.app_dat_tpv(id),
  CONSTRAINT app_dat_operacion_venta_id_promocion_fkey FOREIGN KEY (id_promocion) REFERENCES public.app_mkt_promociones(id),
  CONSTRAINT app_dat_operacion_venta_id_cliente_fkey FOREIGN KEY (id_cliente) REFERENCES public.app_dat_clientes(id),
  CONSTRAINT app_dat_operacion_venta_id_turno_apertura_fkey FOREIGN KEY (id_turno_apertura) REFERENCES public.app_dat_caja_turno(id),
  CONSTRAINT app_dat_operacion_venta_id_mesa_fkey FOREIGN KEY (id_mesa) REFERENCES public.app_dat_mesas(id),
  CONSTRAINT app_dat_operacion_venta_id_cliente_cxc_fkey FOREIGN KEY (id_cliente_cxc) REFERENCES public.app_dat_cliente_cxc(id)
);
```

**Confirmado: NO tiene `moneda`, `tasa_usd` ni `monto_cup_equivalente`.** Grep `ADD COLUMN IF NOT EXISTS moneda` en todo el repo → 1 sola coincidencia, y es sobre `app_dat_pago_venta` (`venta_usd.sql:2`).
ALTER posteriores en el repo: `id_mesa` (`mesas_schema.sql:49-50` + FK `:58-61`), `pago_sms_json` (`ventiq_app/sql_updates/01_pago_sms_confirmacion.sql:27`), `id_cliente_cxc` (`ventiq_admin_app/docs/migrations/11_cuentas_por_cobrar_clientes_independientes.sql:53`).
`pago_sms_json` **no es multimoneda**: es la confirmación de pago por SMS bancario (`01_pago_sms_confirmacion.sql:12,39,89` usa `pago_sms_json ->> 'nro_transaccion_banco'`; `checkout_screen.dart:2142`, `transfer_sms_confirmation_banner.dart:97-183`).

### 1.8 `public.app_nom_medio_pago` — `[DDL-REPO]` `VentiQ.sql:1089-1097`

```sql
CREATE TABLE public.app_nom_medio_pago (
  id smallint NOT NULL,
  denominacion character varying NOT NULL,
  descripcion text,
  es_digital boolean NOT NULL DEFAULT false,
  es_efectivo boolean NOT NULL DEFAULT false,
  es_activo boolean NOT NULL DEFAULT true,
  CONSTRAINT app_nom_medio_pago_pkey PRIMARY KEY (id)
);
```

**NO tiene columna de moneda**: es catálogo de *métodos*, no de monedas. `[DOC]` `docs/payment_methods_pendientes.md:26-29` añade que en vivo solo hay 2 métodos activos (`1` "Pago oferta(Efectivo)" y `4` "Pago regular(Transferencia)") y que `998`/`999` son pseudo-métodos solo del cliente. El servidor clasifica efectivo/digital por esta tabla (`fn_resumen_diario_cierre_v3`, `venta_usd.sql:344,347,355`).

### 1.9 Otras tablas con moneda/derivados de moneda (mapa para no duplicar catálogos)

| Tabla.columna | Definición | Evidencia |
|---|---|---|
| `app_dat_precio_venta.precio_venta_cup` | `numeric NOT NULL DEFAULT 0` | `VentiQ.sql:347` |
| `app_dat_precio_venta.precio_venta_usd` | `numeric` | `VentiQ.sql:352` |
| `app_dat_operacion_recepcion.moneda_factura` | `character DEFAULT 'USD'::bpchar` | `VentiQ.sql:393` |
| `app_dat_operacion_recepcion.tasa_cambio_aplicada` / `fecha_tasa_aplicada` | `numeric` / `timestamp` | `VentiQ.sql:396-397` |
| `app_dat_caja_turno.efectivo_inicial_usd`, `.efectivo_real_usd`, `.diferencia_usd` | `numeric DEFAULT 0` / `numeric` / `numeric` | `ventiq_app/sql/venta_usd.sql:6-9` |
| `app_dat_configuracion_tienda.precio_venta_regido_por_usd` | `boolean NOT NULL DEFAULT false` | `VentiQ.sql:1376` |
| `app_dat_configuracion_tienda.mostrar_selector_moneda` | `boolean NOT NULL DEFAULT false` | `sql_updates/add_mostrar_selector_moneda.sql:2-3` |
| `app_suscripciones_plan.moneda` | `text NOT NULL DEFAULT 'USD'` | `VentiQ.sql:1155` |
| `dep_nom_moneda` | `id, codigo TEXT UNIQUE, denominacion, simbolo, activo, created_at` + seed USD/CUP/EUR | `ventiq_admin_app/lib/sql/depositos_bancarios_schema.sql:14-30` |
| `prv_nom_moneda` | `id, codigo TEXT UNIQUE, denominacion, simbolo, activo, created_at` + seed USD/CUP/EUR | `ventiq_admin_app/lib/sql/pago_proveedores_schema.sql:13-29` |
| `dep_dat_banco.id_moneda`, `prv_dat_proveedor_config.id_moneda` | FK al nomenclador del módulo, **por tienda** (`idtienda`) | `depositos_bancarios_schema.sql:37-41`; `pago_proveedores_schema.sql:36-40` |

**Total: 4 catálogos de moneda distintos en el ecosistema** (`monedas`, `tipos_moneda`, `dep_nom_moneda`, `prv_nom_moneda`) + el dominio cerrado `'CUP'|'USD'` del pago.

---

## 2. Dónde vive hoy la moneda del pago (hallazgo clave)

> **La moneda de un pago de venta vive en la propia línea de pago: `public.app_dat_pago_venta.moneda` (`TEXT`, `'CUP'`/`'USD'`, default `'CUP'`), con `tasa_usd` (tasa aplicada) y `monto_cup_equivalente` (importe normalizado a CUP) como columnas derivadas. NO hay columna de moneda en `app_dat_operacion_venta`, y la moneda NO es atributo del medio de pago. Una misma venta puede tener líneas en CUP y en USD a la vez: la "moneda de la venta" es un valor derivado, no almacenado.**

Evidencia (cadena completa):

1. **DDL aditivo** — `ventiq_app/sql/venta_usd.sql:1-19` (bloque literal en §1.6).
2. **Escritura en servidor (RPC de pago)** — `venta_usd.sql:63` (`v_moneda := CASE WHEN UPPER(COALESCE(v_pago->>'moneda','CUP'))='USD' THEN 'USD' ELSE 'CUP' END`), `:64` (`v_tasa := NULLIF(v_pago->>'tasa_usd','')::NUMERIC`), `:80` (`v_monto_cup := CASE WHEN v_moneda='USD' THEN v_monto*v_tasa ELSE v_monto END`), `:83-97` (INSERT con `moneda, tasa_usd, monto_cup_equivalente`). Idéntico en la variante idempotente `fn_registrar_pago_venta_idempotente.sql:69,86,89-103`.
3. **Lectura en servidor** — `get_sale_payments2` devuelve `moneda`, `tasa_usd`, `monto_cup_equivalente` (`venta_usd.sql:390-392` y `:402`); `fn_listar_ordenes` / `listar_ordenes` fueron parcheados para incluirlos (`ventiq_app/supabase/patch_listar_ordenes_pagos_moneda.sql:32-34` y `:74-76`; versiones locales ya parcheadas: `SQL_OPTIMIZATION/fn_listar_ordenes.sql:262-263`, `SQL_OPTIMIZATION/02_fn_listar_ordenes_optimizada.sql:291-292`, `listar_ordenes_mesa.sql:281-282`).
4. **Escritura en cliente** — `ventiq_app/lib/services/order_service.dart:1692-1693` arma cada pago como `{'moneda': paymentCurrencyByMethod[entry.key] ?? 'CUP', 'tasa_usd': paymentRateByMethod[entry.key], ...}`; `auto_sync_service.dart:3717-3739` normaliza (`USD`/`CUP`) y calcula `monto_cup_equivalente = monto * rate`; llamadas al RPC en `order_service.dart:1731-1740`, `settings_screen.dart:5250-5256` y `:5868-5874`, `admin_inventory_service.dart:1837`.
5. **Interpretación en cliente** — `ventiq_app/lib/utils/price_utils.dart:155-183`: para USD usa `monto * tasa_usd` y **prefiere** el `monto_cup_equivalente` guardado si coincide dentro de tolerancia; `paymentTotalUsd` (`:185-187`) suma solo las líneas USD.
6. **No es atributo del método de pago** — `app_nom_medio_pago` no tiene moneda (§1.8) y `[DOC]` `docs/payment_methods_pendientes.md:166-168` lo formaliza: "la moneda la selecciona el cajero **por venta**, por método de pago — no es atributo del método ni de la tienda. No hace falta cambio de esquema".
7. **No existe tabla hija de pagos ni jsonb de moneda** — grep `pago_sms_json` (único jsonb de la venta) → solo confirmación SMS; grep `ALTER TABLE public.app_dat_operacion_venta` → solo `id_mesa` y `id_cliente_cxc`; grep `ADD COLUMN IF NOT EXISTS moneda` → solo `app_dat_pago_venta`.
8. **Volumen real (dato de documento, no verificado por mí)** — `[DOC]` `docs/payment_methods_pendientes.md:26-29`: "121,877 filas CUP y 7 USD. Los 7 USD usan `id_medio_pago = 1` con `tasa_usd = 550`".

Asimetría relevante con **compras**: la recepción sí guarda la moneda en la operación (`app_dat_operacion_recepcion.moneda_factura` + `tasa_cambio_aplicada`, `VentiQ.sql:393,396`), y sus RPC la reciben y validan (`ventiq_admin_app/lib/sql/02_lotes_recepcion_rpc.sql:31,84-90`; `SQL_OPTIMIZATION/fn_insertar_recepcion_completa_with_currency.sql:9,23-29`). En ventas ese rol lo cumple la **línea de pago**, no la operación.

---

## 3. RPCs relevantes a venta / pago / contabilización

### 3.1 Registro de venta

| Nombre | Firma | archivo:línea | Qué escribe | ¿moneda? |
|---|---|---|---|---|
| `fn_registrar_venta` | `(p_id_tpv bigint, p_uuid uuid, p_productos jsonb, p_codigo_promocion text DEFAULT NULL, p_denominacion text DEFAULT 'Venta en mostrador', p_observaciones text DEFAULT NULL, p_estado_inicial smallint DEFAULT 1, p_id_cliente bigint DEFAULT NULL) RETURNS jsonb` | `funcionalidad_cocina/11_venta_enrutada.sql:185-194` (copias: `registrarventa_ok.sql:1`, `registrar_venta_reworked.sql:1`, `funcionalidad_cocina/03_fix_descuento_bom_por_almacen.sql:57`, `funcionalidad_cocina/_11_funciones_generadas.sql:1`) | `app_dat_operaciones`, `app_dat_operacion_venta`, `app_dat_extraccion_productos`, estados y descuento de inventario | **No** (ningún parámetro ni columna de moneda) |
| `fn_registrar_venta_mesa` | `(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint)` | `funcionalidad_cocina/11_venta_enrutada.sql:592`; `funcionalidad_cocina/17_cobro_sin_redescontar.sql:96`; `registrar_venta_mesa.sql:6` | idem + `app_dat_operacion_venta.id_mesa` | **No** |
| `fn_registrar_venta_v2` | `(bigint,uuid,jsonb,text,text,text,smallint,bigint)` | **NO ENCONTRADA definición en el repo**. Se invoca y se parchea la viva: `funcionalidad_cocina/34_venta_v3_presentaciones.sql:39,55,58`; `ventiq_app/sql/fn_registrar_venta_offline_v3.sql:58` | (viva) | **No** |
| `fn_registrar_venta_v3` | `(bigint,uuid,jsonb,text,text,text,smallint,bigint)` | **NO ENCONTRADA como `CREATE`**; se crea renombrando la `_v2` viva por `DO`-block: `funcionalidad_cocina/34_venta_v3_presentaciones.sql:55-87` | `_v2` + `fn_ejecutar_entrega_fisica_v3` | **No** |
| `fn_registrar_venta_mesa_v3` | `(bigint,uuid,jsonb,text,text,text,smallint,bigint,bigint)` | **NO ENCONTRADA como `CREATE`**: `funcionalidad_cocina/34_venta_v3_presentaciones.sql:102-132` | idem | **No** |
| `fn_registrar_venta_offline` | `(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint)` y variantes `+timestamptz` y `+timestamptz,+jsonb (p_pagos)` | `ventiq_app/sql_offline/04_fn_registrar_venta_offline.sql:39`; `ventiq_app/sql_offline/07_offline_timestamps.sql:117`; **con `p_pagos`**: `ventiq_app/sql_offline/13_fn_registrar_venta_offline_con_pagos.sql:30-42` | venta + (si `p_pagos`) delega en `fn_registrar_pago_venta`; idempotencia por `client_uuid` en `app_dat_operacion_offline_idempotencia` | **Sí, vía `p_pagos`** (jsonb) |
| `fn_registrar_venta_offline_v2` | — | **NO ENCONTRADA en el repo** (existe en vivo; `[DOC]` `payment_methods_pendientes.md:15-17`) | — | vía `p_pagos` |
| `fn_registrar_venta_offline_v3` | `(p_client_uuid uuid, p_id_tpv bigint, p_uuid uuid, p_productos jsonb, p_codigo_promocion text, p_denominacion text, p_observaciones text, p_estado_inicial smallint, p_id_cliente bigint, p_fecha_creacion timestamptz, p_pagos jsonb) RETURNS jsonb` | `ventiq_app/sql/fn_registrar_venta_offline_v3.sql:18-31` | `fn_registrar_venta_v2` + `fn_registrar_pago_venta_v2`; `app_dat_operacion_offline_idempotencia` (`:62-63`); ajusta `created_at` (`:65-66`) | **Sí, vía `p_pagos`** |
| `fn_registrar_venta_offline_v4` | `(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)` | `funcionalidad_cocina/34_venta_v3_presentaciones.sql:145` (firma en `:145-157`, `GRANT` en `:213`) | idem | vía `p_pagos` |

Cliente que las llama: `ventiq_app/lib/services/order_service.dart:1458` (`fn_registrar_venta_mesa_v3` : `fn_registrar_venta_v3`, con fallback a las vivas), `auto_sync_service.dart:4015-4040` (offline v3 → v2 → original).

**NO ENCONTRADO: `fn_venta_v3`.** Grep `fn_venta_v3` en todo el repo (SQL y Dart) → **0 coincidencias**. Lo más cercano por nombre es `fn_registrar_venta_v3` (§3.1). Si alguien pidió "fn_venta_v3", conviene confirmar el nombre real.

### 3.2 Registro de pagos

| Nombre | Firma | archivo:línea | Qué escribe | Interpretación de moneda |
|---|---|---|---|---|
| `fn_registrar_pago_venta` | `(p_id_operacion_venta BIGINT, p_pagos JSONB) RETURNS BOOLEAN`, `SECURITY DEFINER`, `search_path=public` | `ventiq_app/sql/venta_usd.sql:21-108`; `GRANT` `:110` | INSERT en `app_dat_pago_venta` (`:83-97`); `UPDATE app_dat_operacion_venta SET es_pagada=TRUE` si `v_total_pagos_cup >= importe_total` (`:100-104`) | Normaliza a CUP (`:80`); exige `tasa > 0` si USD (`:76-78`); valida medio activo y `monto > 0` (`:67-75`) |
| `fn_registrar_pago_venta_v2` | `(p_id_operacion_venta BIGINT, p_pagos JSONB) RETURNS BOOLEAN` | `ventiq_app/sql/fn_registrar_pago_venta_idempotente.sql:20-114`; `GRANT` `:116` | **`DELETE` de pagos con `id_liquidacion IS NULL`** (`:62-64`) + mismo INSERT (`:89-103`) + `es_pagada` (`:106-110`) | Igual que v1 |
| `fn_registrar_pago_venta_offline` | `(uuid, bigint, jsonb, uuid)` | `ventiq_app/sql_offline/06_idempotencia_extra.sql:97` (`GRANT` `:199`) | pagos con idempotencia | vía `p_pagos` |
| `get_sale_payments2` | `(p_operacion_venta_id BIGINT) RETURNS TABLE(payment_id, monto, referencia_pago, fecha_pago, institucion_financiera_id, medio_pago_id, medio_pago_denominacion, medio_pago_descripcion, medio_pago_es_digital, medio_pago_es_efectivo, medio_pago_es_activo, importe_sin_descuento, moneda, tasa_usd, monto_cup_equivalente)` | `ventiq_app/sql/venta_usd.sql:375-406` (`DROP` de la vieja en `:375`) | solo lectura | Devuelve moneda/tasa/equivalente |

### 3.3 Turno / caja

| Nombre | Firma | archivo:línea | Qué escribe |
|---|---|---|---|
| `registrar_apertura_turno_usd` | `(p_efectivo_inicial NUMERIC, p_id_tpv BIGINT, p_id_vendedor BIGINT, p_usuario UUID, p_maneja_inventario BOOLEAN, p_productos JSONB, p_observaciones TEXT, p_efectivo_inicial_usd NUMERIC DEFAULT NULL) RETURNS BIGINT` | `venta_usd.sql:112-146` | delega en `registrar_apertura_turno_v3` y actualiza `app_dat_caja_turno.efectivo_inicial_usd` (`:140-142`) |
| `fn_cerrar_turno_tpv_usd` | `(p_id_tpv BIGINT, p_efectivo_real NUMERIC, p_usuario UUID, p_productos JSONB, p_observaciones TEXT, p_efectivo_real_usd NUMERIC DEFAULT NULL) RETURNS BOOLEAN` | `venta_usd.sql:148-204` | `efectivo_real_usd` y `diferencia_usd = real_usd - (efectivo_inicial_usd + SUM(pagos USD efectivo))` (`:174-181,191-200`) |
| `fn_apertura_turno_offline_usd` | `(p_client_uuid UUID, p_efectivo_inicial NUMERIC, p_id_tpv BIGINT, p_id_vendedor BIGINT, p_usuario UUID, p_maneja_inventario BOOLEAN DEFAULT FALSE, p_productos JSONB DEFAULT '[]', p_observaciones TEXT DEFAULT NULL, p_fecha_apertura TIMESTAMPTZ DEFAULT NULL, p_efectivo_inicial_usd NUMERIC DEFAULT NULL) RETURNS JSONB` | `venta_usd.sql:209-242` | idem offline |
| `fn_cerrar_turno_offline_usd` | `(p_client_uuid UUID, p_id_tpv BIGINT, p_efectivo_real NUMERIC, p_usuario UUID, p_productos JSONB DEFAULT '[]', p_observaciones TEXT DEFAULT NULL, p_fecha_cierre TIMESTAMPTZ DEFAULT NULL, p_efectivo_real_usd NUMERIC DEFAULT NULL) RETURNS JSONB` | `venta_usd.sql:244-297` | `efectivo_real_usd` + `diferencia_usd` (`:284-293`) |
| `fn_apertura_turno_offline` | `(uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text[, timestamptz])` | `ventiq_app/sql_offline/05_turno_offline.sql:25`; `:07_offline_timestamps.sql:20`; `:12_apertura_idempotente_turno_abierto.sql:13` | apertura con idempotencia |
| `fn_cerrar_turno_offline` | `(uuid, bigint, numeric, uuid, jsonb, text[, timestamptz])` | `ventiq_app/sql_offline/05_turno_offline.sql:113`; `07_offline_timestamps.sql:199` | cierre |
| `fn_cerrar_turno_tpv` | `(p_id_tpv bigint, p_efectivo_real numeric, p_usuario uuid, p_productos jsonb DEFAULT NULL, p_observaciones text DEFAULT NULL) RETURNS boolean` — **sin parámetro USD** | `sql_updates/fn_cerrar_turno_tpv_idempotent.sql:8-15`; también `sql_updates/fn_cerrar_turno_tpv_limit_open.sql:6` | cierre idempotente / límite de turnos abiertos. El soporte USD es un **wrapper aparte**: `fn_cerrar_turno_tpv_usd` (`venta_usd.sql:148-204`) |
| `fn_resumen_diario_cierre_v2` | `(id_tpv_param bigint DEFAULT NULL, id_usuario_param uuid DEFAULT NULL) RETURNS TABLE(19 columnas)` | `presentaciones_inventario/30_cierre_vendedor_v2.sql:94-120` | solo lectura (totales del turno) |
| `fn_resumen_diario_cierre_v3` | `(id_tpv_param BIGINT DEFAULT NULL, id_usuario_param UUID DEFAULT NULL) RETURNS TABLE(…, ventas_usd NUMERIC, efectivo_usd_esperado NUMERIC, digital_usd NUMERIC)` | `venta_usd.sql:302-371` | solo lectura; envuelve a v2 (`:334-337`) y añade el bloque USD (`:338-357`) |

Cliente: `ventiq_app/lib/services/turno_service.dart:596` (`fn_cerrar_turno_tpv_usd` con fallback), `:763` (`registrar_apertura_turno_usd`), `auto_sync_service.dart:2863` (`fn_resumen_diario_cierre_v3`).

### 3.4 Contabilización / recepción con moneda

| Nombre | Firma | archivo:línea | Nota |
|---|---|---|---|
| `fn_contabilizar_operacion` | `(p_id_operacion bigint, p_uuid uuid, p_comentario text)` — **firma inferida por llamadas nombradas** | Cuerpo **NO ENCONTRADO con cabecera**: `SQL_OPTIMIZATION/fn_contabilizar_operacion.sql:1-288` empieza directamente en `DECLARE` (falta el `CREATE FUNCTION`). Llamadas: `SQL_OPTIMIZATION/fn_transferir_inventario_personas.sql:292`, `sql_updates/fix_transfer_reception_destination_inventory.sql:27`, `ventiq_admin_app/lib/services/inventory_service.dart:2890` | `RETURNS jsonb` con `{'status': 'success'|'error', 'message'}` (`:23-26,37-40`) |
| `fn_contabilizar_recepcion_inventario` | `(bigint, boolean, boolean)` | `sql_updates/fn_contabilizar_recepcion_inventario.sql:283` (`GRANT` `:616`) | contabiliza recepción |
| `fn_contabilizar_linea_recepcion_inventario` | `(bigint)` | `sql_updates/fn_contabilizar_recepcion_inventario.sql:110` (`GRANT` `:614`) | por línea |
| `fn_registrar_recepcion_con_inventario` | `(…, p_moneda_factura text DEFAULT 'USD')` | `ventiq_admin_app/lib/sql/02_lotes_recepcion_rpc.sql:22-31` | valida `'USD'|'EUR'|'CUP'` (`:84-90`) y escribe `app_dat_operacion_recepcion.moneda_factura` (`:116-119`) |
| `fn_insertar_recepcion_completa_with_currency` | `(…, p_moneda_factura text …)` | `SQL_OPTIMIZATION/fn_insertar_recepcion_completa_with_currency.sql:1-160` (fragmento sin cabecera en el archivo; valida moneda en `:23-29`) | compras |

### 3.5 Reportes con totales (ver §4)

`fn_reporte_ventas_con_proveedor4(BIGINT,DATE,DATE,BIGINT,TEXT)` — `SQL_OPTIMIZATION/fn_reporte_ventas_con_proveedor3.sql:23`; `fn_reporte_ventas_con_proveedor5(...)` — `presentaciones_inventario/29_reporte_ventas_v5.sql:123`; `fn_reporte_ventas_con_proveedor_por_turno_v2(bigint,date,date,bigint)` — `presentaciones_inventario/48_reporte_ventas_equiv_y_turno_v2.sql:150`; `fn_reporte_ventas_por_turno(uuid,date,date,bigint)` — `ventiq_admin_app/lib/sql/fn_reporte_ventas_por_turno.sql:4`; `fn_reporte_ventas_con_proveedor_por_turno(bigint,date,date,bigint)` — `ventiq_admin_app/lib/sql/fn_reporte_ventas_con_proveedor_por_turno.sql:18`.

---

## 4. Agregaciones / contabilidad existentes

### 4.1 Totales de turno

- **`fn_resumen_diario_cierre_v2`** (`presentaciones_inventario/30_cierre_vendedor_v2.sql:94-120`). Columnas de totales: `ventas_totales`, `efectivo_inicial`, `efectivo_real`, `efectivo_esperado`, `ticket_promedio`, `porcentaje_efectivo`, `porcentaje_otros`, `operaciones_totales`, `conciliacion_estado`, `efectivo_real_ajustado`, `diferencia_ajustada`, `turno_id`, `horas_transcurridas`.
  **Cálculo** (`:255-278`):
  ```sql
  SELECT
      COALESCE(SUM(CASE WHEN mp.es_efectivo     THEN pv.monto ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN NOT mp.es_efectivo THEN pv.monto ELSE 0 END), 0)
  INTO v_tot_efectivo, v_tot_otros
  FROM app_dat_operaciones o
  JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
  JOIN app_dat_pago_venta pv ON ov.id_operacion = pv.id_operacion_venta
  JOIN app_nom_medio_pago mp ON pv.id_medio_pago = mp.id
  WHERE ov.id_tpv = id_tpv_param ...
  ```
  → **NO filtra ni convierte por moneda**: un pago USD entra a los totales CUP 1:1 (`v_ventas := v_tot_efectivo + v_tot_otros`, `:276`). Es el riesgo ya anotado en `tasks/plan_venta_usd.md:97`.
- **`fn_resumen_diario_cierre_v3`** (`venta_usd.sql:302-371`) corrige **solo la parte USD** sin tocar v2:
  ```sql
  COALESCE(SUM(pv.monto) FILTER (WHERE pv.moneda = 'USD'), 0) AS ventas_usd,
  COALESCE(MAX(ct.efectivo_inicial_usd), 0) +
    COALESCE(SUM(pv.monto) FILTER (WHERE pv.moneda = 'USD' AND mp.es_efectivo = TRUE), 0) AS efectivo_usd_esperado,
  COALESCE(SUM(pv.monto) FILTER (WHERE pv.moneda = 'USD' AND mp.es_efectivo = FALSE), 0) AS digital_usd
  ```
  (`:341-348`). Las columnas CUP heredan la contaminación de v2.
- **`fn_cerrar_turno_tpv_usd` / `fn_cerrar_turno_offline_usd`**: `efectivo_usd_esperado = SUM(pv.monto) WHERE pv.moneda='USD' AND mp.es_efectivo` (`venta_usd.sql:174-181` y `:270-277`), y `diferencia_usd` (`:194-198`, `:287-291`).

### 4.2 Tablas de caja / contabilidad con columnas de totales

| Tabla | Columnas de totales | Evidencia |
|---|---|---|
| `app_dat_caja_turno` | `efectivo_inicial`, `efectivo_esperado`, `efectivo_real`, `diferencia` (+ `_usd`) | `VentiQ.sql:1123-1126`, `venta_usd.sql:6-9` |
| `app_dat_entregas_parciales_caja` | `monto_entrega` (CHECK > 0), `id_medio_pago`, `id_turno` | `VentiQ.sql:1215-1229` |
| `app_dat_liquidacion_cxc` | `monto_total` (CHECK > 0), `id_medio_pago`, `id_cliente`, `id_tienda` | `ventiq_admin_app/docs/migrations/10_cuentas_por_cobrar.sql:41-51` |
| `app_cont_egresos_procesados` | `id_egreso`, `estado`, `fecha_procesado`, `procesado_por` | `VentiQ.sql:1255-1266` |
| `app_cont_historial_actividades` | `monto`, `entidad_id`, `id_tienda`, `metadata` | `VentiQ.sql:1267-1282` |
| `app_cont_gastos` | `monto` (y `id_tienda`) | `VentiQ.sql:584-604` |
| `app_dat_operacion_contabilizacion_historial` | creada por | `ventiq_admin_app/docs/migrations/fn_listar_operaciones_inventario_new_apertura_cierre.sql:6` |
| `dep_dat_saldo`, `prv_dat_saldo`, `imp_dat_saldo` | saldos por tienda: `dep_dat_saldo(idtienda, id_banco, saldo_disponible)` con la moneda en `dep_dat_banco.id_moneda`; `prv_dat_saldo(idtienda, id_proveedor, saldo_disponible)` con la moneda en `prv_dat_proveedor_config.id_moneda`; `imp_dat_saldo(idtienda UNIQUE, saldo_disponible)` **sin columna de moneda** (comentario: "Saldo actual en USD") | `ventiq_admin_app/lib/sql/depositos_bancarios_schema.sql:111-119` y `:41`; `pago_proveedores_schema.sql:83-91` y `:40`; `importadora_facturas_schema.sql:46-55` |

### 4.3 Reportes que usan tasa histórica

- `fn_reporte_ventas_con_proveedor3/4`: CTE `tasa_historica` que toma la tasa activa más reciente de `tasa_cambio_extraoficial` por fecha de operación (`SQL_OPTIMIZATION/fn_reporte_ventas_con_proveedor3.sql:140-150`; mismo patrón en `presentaciones_inventario/48...:263-275`, `ventiq_admin_app/lib/sql/fn_reporte_ventas_con_proveedor_por_turno.sql:65`, `ventiq_admin_app/docs/migrations/fn_reporte_cronologico_producto.sql:126-137`). Devuelven `valor_usd`, `precio_costo_cup`, `precio_costo`, `ingresos_totales`, etc. (`presentaciones_inventario/29...:137-147`).
- `SQL_OPTIMIZATION/trigger_actualizar_precios_cup_por_tasa_usd.sql:18-88`: trigger `trg_actualizar_precios_cup_por_tasa` sobre `tasa_cambio_extraoficial` que recalcula `app_dat_precio_venta.precio_venta_cup = ROUND(precio_venta_usd * tasa, 2)` solo si `app_dat_configuracion_tienda.precio_venta_regido_por_usd = TRUE` (`:37-43,48-57`).
- `sql_triggers/sync_valor_usd_carnaval.sql:11-60`: trigger que sincroniza `carnavalapp.configuraciones_admin.valor_usd` (solo tienda 177) desde `tasa_cambio_extraoficial` o, si `usar_precio_toque`, desde `tasas_conversion` (`:29-42`).
- `[DART]` Fuente externa de tasas del admin: `ventiq_admin_app/lib/services/currency_service.dart:9-11` consume `https://tasas.eltoque.com/v1/trmi` con token **hardcodeado** en el código.

**NO ENCONTRADO**: ninguna vista ni vista materializada que agregue ventas por moneda. Grep `CREATE (OR REPLACE )?VIEW|CREATE MATERIALIZED VIEW` en `*.sql` → 7 coincidencias, todas ajenas a moneda/venta (`funcionalidad_cocina/07_schema_cocinas.sql:397`, `inventtia_muevete/.../015:55`, `022:194`, `SQL_OPTIMIZATION/ignorar_precio_promedio_devoluciones.sql:231`, `SQL_OPTIMIZATION/implementar_devoluciones_consignacion.sql:646`, `sql_updates/carnaval_orderdetails_bitacora.sql:117`).

---

## 5. RLS / políticas

### 5.1 Con RLS y políticas en el repo

| Tabla | Estado | Evidencia |
|---|---|---|
| `app_dat_pago_venta` | `ENABLE ROW LEVEL SECURITY` + 4 políticas (`pago_venta_admin_insert/select/update/delete`) para `authenticated` usando `fn_user_can_access_tienda(fn_get_tienda_by_operacion_venta(id_operacion_venta))` | `ventiq_admin_app/docs/migrations/09_pago_venta_gerente_rls.sql:9-73` (helper en `:12-20`) |
| `app_dat_liquidacion_cxc` | RLS + `liquidacion_cxc_admin_all` (`FOR ALL TO authenticated USING fn_user_can_access_tienda(id_tienda)`) | `ventiq_admin_app/docs/migrations/10_cuentas_por_cobrar.sql:63-70` |
| `dep_nom_moneda` | RLS + `"Acceso autenticado - dep_nom_moneda"` `FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE)` | `ventiq_admin_app/lib/sql/depositos_bancarios_schema.sql:406,418-419` |
| `prv_nom_moneda` | RLS + `"Acceso autenticado - prv_nom_moneda"` `FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE)` | `ventiq_admin_app/lib/sql/pago_proveedores_schema.sql:198,209-210` |

### 5.2 Sin RLS/políticas encontradas — **[NO ENCONTRADO]**

**NO ENCONTRADO** ninguna `CREATE POLICY` ni `ENABLE ROW LEVEL SECURITY` para: `public.monedas`, `public.tasas_conversion`, `public.tasa_cambio_extraoficial`, `public.tipos_moneda`, `public.app_dat_denominaciones_moneda`.

Búsquedas realizadas:
- grep `ON public\.(monedas|tasas_conversion|app_dat_pago_venta|tasa_cambio_extraoficial|app_dat_denominaciones_moneda)` en todo el repo → solo `01_indices_listar_ordenes.sql:16` (un índice), `gestión de triggers` sobre `tasa_cambio_extraoficial` (`trigger_actualizar_precios_cup_por_tasa_usd.sql:82,86`) y las políticas de `app_dat_pago_venta` (§5.1). Nada de `monedas`/`tasas_conversion`/`tipos_moneda`/`app_dat_denominaciones_moneda`.
- grep `CREATE POLICY|ROW LEVEL SECURITY` en todo el repo (362 coincidencias) → todas corresponden a otros esquemas (`carnavalapp`, `flow`, `muevete`, `servicentro`, `storage`) o a las tablas de §5.1. Ninguna sobre los catálogos de moneda del core.
- `VentiQ.sql` **no contiene ninguna sentencia `POLICY`, `GRANT` ni `ROW LEVEL SECURITY`** (verificado en §0).

Consecuencia práctica: en el repo **no hay evidencia de quién puede insertar/actualizar en `monedas`, `tasas_conversion`, `tipos_moneda` ni `tasa_cambio_extraoficial`**. La única escritura de tasas documentada es del admin app por tienda (`personal_rates_service.dart:117,159`) y no lleva filtro de autoría (depende del RLS de la BD, no reproducible aquí).

---

## 6. Global vs por tienda

| Objeto | ¿Global o por tienda? | Evidencia |
|---|---|---|
| `public.monedas` | **GLOBAL** (sin `id_tienda`) | `VentiQ.sql:1195-1204` |
| `public.tasas_conversion` | **GLOBAL** (sin `id_tienda`) | `VentiQ.sql:1205-1214` |
| `public.tipos_moneda` | **GLOBAL** (el filtro por tienda ocurre en la tasa) | `[DART]` `personal_rates_service.dart:11-14` |
| `public.tasa_cambio_extraoficial` | **POR TIENDA** (`id_tienda` obligatorio en inserts) | `[DART]` `personal_rates_service.dart:38,48,66,87,123,165` |
| `public.app_dat_denominaciones_moneda` | **INDETERMINADO** (el `select` no filtra tienda; sin DDL no se puede saber) | `login_screen.dart:730-735` |
| `public.app_nom_medio_pago` | **GLOBAL** | `VentiQ.sql:1089-1097` |
| `public.app_dat_pago_venta` | **Sin `id_tienda`**; tienda derivada de la operación | `VentiQ.sql:1098-1116`; `09_pago_venta_gerente_rls.sql:12-20` |
| `app_dat_configuracion_tienda.mostrar_selector_moneda` | **POR TIENDA** | `sql_updates/add_mostrar_selector_moneda.sql:2-3` |
| `app_dat_configuracion_tienda.precio_venta_regido_por_usd` | **POR TIENDA** | `VentiQ.sql:1376` |
| `app_dat_precio_venta.precio_venta_usd` | **POR TIENDA** (vía `app_dat_producto.id_tienda`) | `VentiQ.sql:130,343-356` |
| `dep_nom_moneda`, `prv_nom_moneda` | **GLOBAL** (nomenclador del módulo) | `depositos_bancarios_schema.sql:14-21`; `pago_proveedores_schema.sql:13-20` |
| `dep_dat_banco`, `prv_dat_proveedor_config` | **POR TIENDA** (`idtienda`) | `depositos_bancarios_schema.sql:37-40`; `pago_proveedores_schema.sql:36-40` |

### ¿Dónde puede crear monedas el superadmin hoy?

**NO ENCONTRADO.** En `ventiq_superadmin/lib` no hay **ninguna** referencia a `monedas`, `tipos_moneda`, `tasa_cambio_extraoficial` ni a CRUD de monedas: grep de `monedas|tasas_conversion|tipos_moneda|tasa_cambio_extraoficial` en `ventiq_superadmin/lib/**/*.dart` (213 coincidencias) devuelve solo usos de la palabra `denominacion` como nombre de entidad (tiendas, planes, almacenes) y **dos lecturas** de tipos de cambio: `ingresos_service.dart:11` y `inventtia_payment_service.dart:23` (ambos `.from('tasas_conversion')`, solo lectura).

Lo único que **crea** monedas/tasas en el ecosistema repo es:
- `ventiq_admin_app/lib/services/personal_rates_service.dart:117-124` y `:159-166`: `insert` en `tasa_cambio_extraoficial` **con `id_tienda`** (es decir, tasa por tienda, no catálogo global).
- Los seeds de `dep_nom_moneda` / `prv_nom_moneda` (nomencladores de módulo, con RLS `authenticated USING TRUE`).

Implicación de diseño para el plan multimoneda: si el superadmin debe **crear una moneda nueva** (p. ej. MLC/EUR) en un catálogo global, hoy **no existe ni UI ni RPC en el repo** para `monedas` ni `tipos_moneda`; y el pago no podría usarla sin quitar/ampliar el CHECK `moneda IN ('CUP','USD')` (`venta_usd.sql:18-19`) y sin resolver el problema de identidad de §7.1.

---

## 7. Huecos y contradicciones detectadas

1. **Cuatro catálogos de moneda con tres espacios de identidad distintos.**
   - `monedas.codigo` (char) + `tasas_conversion` (char) — global, ISO-like.
   - `tipos_moneda.id` (int) + `tasa_cambio_extraoficial.id_moneda_origen/destino` (int, **por tienda**) — el que usa el admin.
   - `dep_nom_moneda` / `prv_nom_moneda` (codigo text, con seed EUR) — nomencladores de módulo.
   - Y el pago usa un **dominio cerrado de texto** `'CUP'|'USD'` **sin FK a ninguno** (`venta_usd.sql:2,18-19`).
   No hay tabla de mapeo entre `monedas.codigo` y `tipos_moneda.id`.

2. **`public.monedas.codigo` es `character` sin longitud = `bpchar(1)`** (`VentiQ.sql:1196`). Con `bpchar(1)` no se puede insertar `'USD'` (fallaría con `value too long`), y sin embargo el trigger de Carnaval compara `moneda_origen = 'USD'` en `tasas_conversion` (`sync_valor_usd_carnaval.sql:33-34`) y el vendedor compara `rate['moneda_origen'] == 'USD'` (`currency_service.dart:92-93`). **O la definición real en la BD tiene longitud (y `VentiQ.sql` está desactualizado), o `tasas_conversion` está vacía y todo el código cae al fallback cache/extraoficial.** Verificar contra la BD es el primer paso del plan. (En `app_dat_operacion_recepcion` el volcado sí escribe `character DEFAULT 'USD'` — `VentiQ.sql:393` — lo que refuerza la sospecha de que el volcado perdió los `(n)` de longitud o de que la columna no puede contener 'USD'.)

3. **`tasas_conversion` no tiene `UNIQUE (moneda_origen, moneda_destino)`** (`VentiQ.sql:1205-1214`) → pueden existir varias tasas del mismo par y cada consumidor elige "la última por fecha" con criterios ligeramente distintos (`currency_service.dart:38-41` vs `:151-153` vs `presentaciones_inventario/48...:203-207`).

4. **El repo no reproduce el esquema real.** `VentiQ.sql` es un volcado parcial (100 tablas) y define FKs hacia tablas que **no** incluye: `app_dat_liquidacion_cxc` (`:1115`), `app_dat_mesas` (`:423`), `app_dat_cliente_cxc` (`:424`), `app_dat_agente` (`:1178`). Y falta todo el DDL de `tasa_cambio_extraoficial`, `tipos_moneda`, `app_dat_denominaciones_moneda`, `app_dat_mesas`, `app_dat_operacion_offline_idempotencia`, `app_dat_cliente_cxc`. El esquema solo es reconstruible uniendo `VentiQ.sql` + docenas de scripts sueltos en `sql_updates/`, `SQL_OPTIMIZATION/`, `ventiq_app/sql{,_offline}/`, `ventiq_admin_app/{lib/sql,docs/migrations}/`. El core **no** usa `supabase/migrations` (solo 8 archivos, todos de nov-2026 y ajenos a moneda).

5. **`fn_resumen_diario_cierre_v2` mezcla USD y CUP en los mismos totales** (§4.1, `presentaciones_inventario/30_cierre_vendedor_v2.sql:255-278`). `v3` añade columnas USD separadas pero no corrige las CUP. Cualquier reporte/cierre que use v2 (o la app vieja) sobreestima ventas si hay pagos USD.

6. **Ids de moneda hardcodeados y repetidos** (`1=CUP`, `2=USD`) sin FK ni catálogo que los valide: `ventiq_app/lib/services/currency_service.dart:7-8`, `ventiq_admin_app/lib/services/currency_service.dart:15-16`, `personal_rates_service.dart:6`, `SQL_OPTIMIZATION/trigger_actualizar_precios_cup_por_tasa_usd.sql:17,47`, `sql_triggers/sync_valor_usd_carnaval.sql:2`. Divergen del texto `'CUP'`/`'USD'` del pago.

7. **RLS inconsistente.** Un comentario del repo afirma "El proyecto no usa RLS: la barrera es esta [el guard]" (`presentaciones_inventario/29_reporte_ventas_v5.sql:164`), pero `app_dat_pago_venta` y `app_dat_liquidacion_cxc` **sí** tienen RLS habilitado y políticas (§5.1), mientras que los catálogos de moneda y tasas **no tienen ninguna** (§5.2).

8. **`app_dat_denominaciones_moneda` es una caja negra**: sin DDL, sin CRUD, sin política, sin saber si es global o por tienda, y es la que alimenta el contador de billetes del TPV (`bill_count_dialog.dart`) y el cache offline (`user_preferences_service.dart:4686-4757`).

9. **Histórico no moneda-consciente.** El backfill `UPDATE ... SET moneda='CUP', monto_cup_equivalente=monto WHERE monto_cup_equivalente IS NULL` (`venta_usd.sql:11-14`) marca como CUP todo pago previo. La distinción CUP/USD solo es fiable desde la aplicación de ese script; no hay `created_at` de migración que lo date.

10. **`pago_sms_json` (jsonb) no es multimoneda** (`VentiQ.sql:415`), para evitar que un futuro lector lo confunda con un sitio donde "podría vivir la moneda": es la confirmación de un pago por SMS bancario (`ventiq_app/sql_updates/01_pago_sms_confirmacion.sql:12,39,89`).

11. **`fn_contabilizar_operacion` no tiene cuerpo con cabecera en el repo** (`SQL_OPTIMIZATION/fn_contabilizar_operacion.sql` empieza en `DECLARE`); su firma solo se infiere de las llamadas nombradas `p_id_operacion`/`p_uuid`/`p_comentario`. No se puede auditar si contabiliza importes ni en qué moneda.

12. **Los cuerpos "vivos" de `fn_registrar_venta_v2`, `fn_registrar_venta_mesa_v2` y `fn_registrar_venta_offline_v2` no están en el repo**: se parchean/renombran vía `DO`-block sobre la definición viva (`funcionalidad_cocina/34_venta_v3_presentaciones.sql:39,55,102`) y se invocan desde SQL del repo (`ventiq_app/sql/fn_registrar_venta_offline_v3.sql:58`). No es auditable qué firma/cuerpo tienen hoy.

13. **`fn_venta_v3` no existe** en el repo (grep en todo el repo, SQL y Dart: 0 coincidencias). El nombre probablemente sea `fn_registrar_venta_v3`.

---

## 8. Preguntas abiertas

1. ¿Cuál es la **definición real** en la BD de `tasas_conversion.moneda_origen/moneda_destino` y `monedas.codigo` (longitud de `bpchar`)? ¿Contiene `tasas_conversion` filas `'USD'→'CUP'`? (Decide si `monedas`/`tasas_conversion` son usables o solo legacy.)
2. ¿Cuál es el DDL real de `tasa_cambio_extraoficial`, `tipos_moneda` y `app_dat_denominaciones_moneda` (columnas, tipos, PK/FK, UNIQUE, defaults, `NOT NULL`)? ¿Tienen RLS habilitado? ¿Qué políticas?
3. ¿`app_dat_denominaciones_moneda` es global o por tienda? ¿Quién la administra (no hay UI ni insert en el repo)? ¿`codigo_moneda` referencia `monedas.codigo` o `tipos_moneda.id`/`codigo`?
4. ¿Existe el CHECK `app_dat_pago_venta_moneda_check CHECK (moneda IN ('CUP','USD'))` en producción? ¿Cuántas filas tienen `moneda` distinta de `'CUP'` y cuál es su `tasa_usd`? (El `[DOC]` dice 7 filas USD con tasa 550.)
5. ¿Se aplicó `venta_usd.sql` completo en **todos** los entornos (main/newa/debug)? ¿Coinciden las firmas de `fn_registrar_pago_venta` y `fn_resumen_diario_cierre_v3`?
6. ¿Qué consumidores reales (app vieja desplegada, reportes del admin) siguen usando `fn_resumen_diario_cierre_v2` y por tanto suman USD como CUP hoy?
7. Para crear una moneda nueva (EUR/MLC): ¿la fuente de verdad debe ser `monedas` (global, char) o `tipos_moneda` (global, int)? ¿Hay que unificarlas o mapear? ¿Quién tendría permiso de escritura (RLS inexistente)?
8. ¿El pago debe soportar más de CUP/USD? Si sí, el CHECK de `venta_usd.sql:18-19` y los hardcodes `1=CUP/2=USD` son un bloqueo.
9. `app_dat_operacion_venta` no guarda moneda: ¿se acepta que "la moneda de la venta" sea siempre derivada de sus líneas de pago, incluso para ventas mixtas y para reimpresión de tickets?
10. ¿`fn_venta_v3` era un nombre inexacto por `fn_registrar_venta_v3`, o existe una función con ese nombre en algún proyecto que no vi?
11. ¿`dep_*` y `prv_*` deben converger a un único catálogo de monedas con el core, o se mantienen como nomencladores independientes de módulo (hoy tienen EUR en el seed y RLS abierto a todo `authenticated`)?
12. ¿Cómo se debe tratar el vuelto en moneda cruzada? `tasks/plan_venta_usd.md:98` lo declara fuera de alcance ("el vendedor ajusta montos manualmente"); ¿sigue vigente?

---

### Anexo A — Búsquedas negativas explícitas (para auditoría del recon)

| Qué busqué | Patrón | Resultado |
|---|---|---|
| DDL de `tasa_cambio_extraoficial` / `app_dat_denominaciones_moneda` | `CREATE TABLE (IF NOT EXISTS )?(public\.)?(...)` | 0 coincidencias |
| CRUD de `app_dat_denominaciones_moneda` | `app_dat_denominaciones_moneda` (todo el repo) | 1 coincidencia (`login_screen.dart:731`), solo lectura |
| `tipos_moneda` | `tipos_moneda` (todo el repo) | 1 coincidencia (`personal_rates_service.dart:11`), solo lectura |
| `fn_venta_v3` | `fn_venta_v3` (todo el repo) | 0 coincidencias |
| Columna de moneda en la operación de venta | `ALTER TABLE public\.app_dat_operacion_venta` / `ADD COLUMN IF NOT EXISTS moneda` | solo `id_mesa`, `id_cliente_cxc`; `moneda` solo en `app_dat_pago_venta` |
| RLS sobre catálogos de moneda | `ON public\.(monedas\|tasas_conversion\|tasa_cambio_extraoficial\|app_dat_denominaciones_moneda)` | 0 políticas |
| Vistas de agregación por moneda | `CREATE (OR REPLACE )?VIEW\|CREATE MATERIALIZED VIEW` | 7 vistas, ninguna de moneda/ventas |
| Volcados adicionales | listado recursivo `*.sql,*.dump,*.psql,*.schema` por tamaño | ningún `.dump`/`schema.sql`/`.psql` |
| DDL/RLS/funciones en `VentiQ.sql` | `POLICY\|ROW LEVEL\|GRANT\|CREATE INDEX\|CREATE FUNCTION\|CREATE VIEW` | 1 coincidencia (FK de `:1115`) → el volcado solo tiene tablas |
