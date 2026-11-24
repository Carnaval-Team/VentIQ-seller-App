-- ============================================================================
-- 06b_aterrizaje.sql — Fase 6b: aterrizaje del cargo de importadora en el costo
--
-- SINCRONIZADO con `newa` (`qhprswhhfasrikhawjoz`) el 2026-11-21 (tercera
-- pasada: los cinco defectos D8-D12 de la revisión de la fase 6).
-- 20/20 en `verify/06_costos.sql` al aplicar 06b (23/23 con 06c). Los dos
-- `ALTER` (columnas `tasa_usd_aplicada` e `id_compra_recepcion`) y el cuerpo de
-- las tres funciones son los que la base tiene aplicados: aplicarlo en otro
-- entorno produce el mismo resultado. Es idempotente: se puede reaplicar sobre
-- una base que ya tiene la versión anterior.
--
-- Verificación de sincronía archivo↔base: se compara el **cuerpo normalizado**
-- de cada función (texto entre los delimitadores del cuerpo, con los espacios
-- en blanco colapsados a uno y sin espacios en los extremos) por `md5`.
-- Huellas vigentes (2026-11-21, `newa`):
--   fn_fdi_compra_recepcion_bases     ad25f27acee669f302818105fd12c797
--   fn_fdi_compra_repartir_aterrizaje abe00f1ac415f57553f40c012fbbae00
--   fn_fdi_recepcion_con_costos       a2b9c4fb299f38e0d44a32347d514473
-- La verificación 4.7 del propio script vuelve a emitir esas huellas al
-- aplicarlo, para contrastarlas sin depender de este comentario. **Las de
-- arriba se sustituyen por las emitidas al aplicar**: si no coinciden, la base
-- tiene otro cuerpo.
--
-- ---------------------------------------------------------------------------
-- HISTORIAL DE LA FASE 6b
-- ---------------------------------------------------------------------------
--   · v1 (primer script aplicado): reparto del cargo de importadora, tasa en
--     la operación y recepción con costos transaccional. Defectos D1-D7
--     cerrados (commit 34eeb0ee).
--   · v2 (este archivo): cierra los cinco defectos que la revisión de la fase
--     encontró después. Todos son de dinero o de auditoría:
--
--     D8  **Una factura no-USD se quedaba sin tasa.** El carril normal sólo
--         escribía `tasa_cambio_aplicada` si había inversión, y el cliente no
--         mandaba `p_tasa_usd`: la operación quedaba con tasa NULL y el
--         aterrizaje abortaba después con 22023. Ahora la recepción con
--         costos **exige** la tasa si la factura no es USD (antes de crear
--         nada) y **siempre** la registra (USD ⇒ 1).
--     D9  **La moneda del vínculo no se comparaba con la de la operación.**
--         Se usaba la de la operación y una discrepancia cambiaba el cargo en
--         silencio. El reparto ahora aborta con 22023 y dice las dos monedas.
--     D10 **Los costos no sabían a qué vínculo pertenecían.** Con
--         `UNIQUE(id_operacion, id_compra)`, dos compras pueden compartir una
--         recepción y el reparto de la segunda borraba los costos de la
--         primera. `app_dat_recepcion_producto_costo` gana
--         `id_compra_recepcion` y el reparto borra, inserta y cuadra **por
--         vínculo**, no por operación; las líneas de cada vínculo se resuelven
--         por `id_recepcion_producto`, por los costos ya atribuidos o, si la
--         operación tiene un solo vínculo, por todas las líneas. Con dos o más
--         vínculos y sin atribución **no adivina**: aborta.
--     D11 **El rollback mentía.** Decía que 06b «no añadió ni una columna» y no
--         retiraba `tasa_usd_aplicada`. Ahora retira las dos columnas.
--     D12 **`fecha_tasa_aplicada` no se re-sellaba al corregir la tasa.** Se
--         conservaba la fecha del primer registro. Ahora se re-sella **sólo
--         cuando la tasa cambia**, que es el acto auditable; un reintento con
--         la misma tasa conserva la fecha original.
--
--
-- REQUIERE: 06a aplicado (catálogo `app_cont_tipo_costo` con sus 4 tipos) y
--           05a/05c aplicados (columnas de importadora en el vínculo).
--
-- CONTRASTADO CONTRA `newa` (`qhprswhhfasrikhawjoz`) ANTES DE ESCRIBIRLO. Lo
-- que la base tiene de verdad, no lo que los documentos dicen:
--
--   · `fdi_dat_compra_recepcion`: id, id_compra, id_tienda, id_operacion,
--     monto_valorizado, moneda, tasa_a_base, created_by, created_at,
--     pct_importadora numeric(7,4), base_importadora numeric(14,2),
--     monto_importadora numeric(14,2), reembolso_importadora numeric(14,2),
--     origen_pago text, confirmada_con_exceso boolean,
--     tasa_usd_aplicada numeric(18,10) NULL.
--     **NO existe `fecha_operacion` en esta tabla.** `fecha_operacion` vive en
--     `app_dat_operacion_recepcion` (la añade 05a y la escribe el trigger
--     `trg_fdi_recepcion_fecha` de 06a). No se usa aquí.
--     `tasa_a_base` es numeric NOT NULL DEFAULT 1 y `fn_fdi_compra_vincular_recepcion`
--     la escribe **siempre como 1**: no es una tasa a USD y no sirve para
--     convertir. La tasa USD sale de la OPERACIÓN
--     (`app_dat_operacion_recepcion.tasa_cambio_aplicada`), no de aquí.
--     `tasa_usd_aplicada` la añade este script (sección 0b) y la escribe
--     `fn_fdi_compra_repartir_aterrizaje` por el `id` del vínculo.
--     CHECK real de `origen_pago`: fondo | wallet_importadora |
--     wallet_proveedor | externo.
--
--   · `app_dat_recepcion_productos` (la tabla que referencia
--     `id_recepcion_producto`): id, id_operacion, id_producto, id_variante,
--     id_opcion_variante, id_proveedor, id_ubicacion, id_presentacion,
--     **cantidad** (NOT NULL), **precio_unitario**, sku_producto, sku_ubicacion,
--     created_at, precio_referencia, descuento_porcentaje, descuento_monto,
--     **costo_real**, bonificacion_cantidad, id_lote.
--     `costo_real` lo rellena el trigger `trg_recepcion_productos_costo_real`:
--         costo_real = (precio_unitario - descuento_monto)
--                      - (precio_referencia * descuento_porcentaje / 100)
--     es decir, es el **costo unitario aplicado** de la línea.
--     **No existe `cantidad_recibida`** en esta tabla: la cantidad recibida es
--     `cantidad`.
--
--   · `app_dat_recepcion_producto_costo`: id, id_recepcion_producto,
--     id_tipo_costo, monto_usd, monto_promedio_anterior, created_at. Sin
--     DEFAULT en monto_usd ni en monto_promedio_anterior (hay que darlos).
--     FK a `app_dat_recepcion_productos(id)` ON DELETE CASCADE y a
--     `app_cont_tipo_costo(id)`.
--     **NO tiene UNIQUE(id_recepcion_producto, id_tipo_costo)**; solo
--     `idx_recepcion_producto_costo_rp`. Ver "idempotencia" abajo.
--     `id_compra_recepcion` la añade este script (sección 0c) y es la
--     atribución de la fila a un vínculo compra↔recepción. NULL a propósito
--     cuando la fila no viene de un aterrizaje (costos del cliente) o cuando
--     la operación cubre varias compras y no se puede atribuir sin adivinar.
--     **El reparto no toca filas de otro vínculo**: borra, inserta y cuadra
--     por `id_compra_recepcion` (D10).
--
--   · `fdi_dat_compra_recepcion_linea` sí tiene `cantidad_recibida`,
--     `costo_unitario_aplicado` y `id_recepcion_producto`. Pero en `newa`
--     **`id_recepcion_producto` está en NULL en todas sus filas** (0 de 1) y
--     `fn_fdi_compra_vincular_recepcion` nunca lo escribe. Por eso el vínculo
--     directo línea-compra ↔ línea-recepción se intenta, y si no está se
--     resuelve por producto/variante y, en último término, con `costo_real`.
--     El orden exacto está en `fn_fdi_compra_recepcion_bases` (abajo).
--
-- Qué añade este script:
--   0. `ALTER TABLE fdi_dat_compra_recepcion ADD COLUMN tasa_usd_aplicada
--      numeric(18,10)` — la tasa efectiva que usó el reparto, para auditoría.
--   0c. `ALTER TABLE app_dat_recepcion_producto_costo ADD COLUMN
--      id_compra_recepcion bigint REFERENCES fdi_dat_compra_recepcion(id)
--      ON DELETE CASCADE` + backfill de las filas de Importadora en
--      operaciones con **un solo** vínculo. Es lo que impide que el reparto de
--      una compra borre los costos de otra (D10).
--   1. `fn_fdi_compra_recepcion_bases(bigint)` — STABLE. Una sola definición
--      del "valor de cada línea" (base del reparto), reutilizable para
--      previsualizar el reparto antes de aplicarlo. Devuelve sólo las líneas
--      del vínculo (D10).
--   2. `fn_fdi_compra_repartir_aterrizaje(bigint, numeric DEFAULT NULL)` —
--      reparte `monto_importadora` entre las líneas **del vínculo**, persiste
--      una fila por línea con el tipo de costo 'Importadora' (atribuida al
--      vínculo), escribe la tasa efectiva en la operación y en el vínculo (por
--      su `id`), y aborta si la moneda del vínculo no es la de la operación
--      (D9).
--   3. `fn_fdi_recepcion_con_costos(jsonb, jsonb, jsonb, uuid)` — recepción +
--      costos en UNA transacción, con clave de idempotencia y registro
--      **siempre** de la tasa en la operación (nunca en el vínculo: eso es del
--      reparto). Exige la tasa si la factura no es USD (D8).
--
-- ---------------------------------------------------------------------------
-- TASA (`p_tasa_usd`) — sentido, fuente única y regla
-- ---------------------------------------------------------------------------
--   `p_tasa_usd` = **unidades de la moneda de la factura por 1 USD**. Es un
--   divisor:
--       monto_usd = round(monto_en_moneda_de_la_factura / p_tasa_usd, 2)
--   Ejemplos: CUP con tasa 320 ⇒ 3200 CUP = 10.00 USD; EUR con tasa 0.92 ⇒
--   92 EUR = 100.00 USD.
--
--   **Fuente única: la operación.** `app_dat_operacion_recepcion` guarda la
--   moneda de la factura (`moneda_factura`) y la tasa usada
--   (`tasa_cambio_aplicada`, con `fecha_tasa_aplicada`).
--     · Si `p_tasa_usd` viene (no NULL), se usa ese valor.
--     · Si no viene, se lee `tasa_cambio_aplicada` de la operación.
--     · Si la moneda de la operación es 'USD' (sin caja ni espacios) la tasa
--       se **fuerza a 1** y se avisa en el jsonb (`tasa_forzada_usd = true`).
--     · Si no es USD y no hay tasa (ni parámetro ni operación), se aborta con
--       22023: no se inventa una conversión.
--   La moneda del VÍNCULO ya no normaliza nada: si discrepaba de la operación,
--   el resultado dependía del orden de llamadas. Se informa en `moneda_vinculo`
--   sólo como dato de auditoría.
--
--   La tasa efectiva se escribe SIEMPRE en la operación (capitalice o no), y
--   en el vínculo sólo cuando hay reparto: `sin_cargo` también la deja escrita;
--   `omitido` (fondo / wallet_proveedor) no toca el costo pero sí la operación.
--   `fecha_tasa_aplicada` es `timestamp without time zone`: se escribe
--   `now() AT TIME ZONE 'UTC'`, nunca `now()` (dependería del TimeZone).
--
--   D8 — de dónde sale la tasa y cuándo es obligatoria:
--     · Recepción con costos (`fn_fdi_recepcion_con_costos`): si la moneda de
--       la factura no es USD, `p_tasa_usd` es **obligatoria**. Sin ella la
--       operación quedaría con tasa NULL y el aterrizaje no podría convertir
--       (22023). Se rechaza **antes** de crear la recepción.
--     · Si es USD, la tasa se **fuerza a 1** y se registra igual.
--     · El reparto acepta `p_tasa_usd` o, si no viene, lee la de la operación.
--
--   D12 — `fecha_tasa_aplicada` se **re-sella cuando la tasa cambia**. Un
--   reintento idempotente con la misma tasa conserva la fecha original; una
--   corrección (tasa distinta) actualiza tasa y fecha. Sin esto la auditoría
--   decía que la tasa vigente se había aplicado en la fecha de la primera vez.
--
--   D9 — la moneda del vínculo ya no se ignora: si está informada y difiere de
--   `app_dat_operacion_recepcion.moneda_factura`, el reparto **aborta** con
--   22023 antes de escribir nada. Antes se usaba la de la operación y el cargo
--   cambiaba en silencio.
--
--   `monto_importadora` está expresado en la moneda de la factura (lo calcula
--   `fn_fdi_compra_vincular_recepcion` como `round(base × pct / 100, 2) − reembolso`).
--
-- ---------------------------------------------------------------------------
-- REPARTO — regla exacta
-- ---------------------------------------------------------------------------
--   Por **valor**, no por cantidad:
--       base_i = cantidad_i × costo_unitario_i
--   y el prorrateo se hace sobre `base_i / Σ base`, redondeando a 2 decimales
--   **por línea**:
--       monto_usd_i = round(cargo_usd × base_i / Σ base, 2)
--
--   **Residuo de redondeo:** `residuo = cargo_usd − Σ monto_usd_i`. Se suma
--   ÍNTEGRO a UNA sola línea: la de **mayor base**; a igual base, la de **menor
--   id_recepcion_producto**. Así `Σ monto_usd` es exactamente `cargo_usd`
--   (la función lo comprueba antes de devolver y aborta si no cuadra).
--
--   Por qué una sola línea y no repartir el céntimo: el residuo está acotado
--   por ±0.005 × n y concentrarlo en la línea más grande es la regla más
--   estable (no depende del orden de inserción ni del número de líneas
--   pequeñas), y deja un rastro trivial de auditar: la línea de mayor base es
--   la única que puede diferir del prorrateo puro.
--
--   Si `Σ base = 0` NO se reparte: se aborta con ERRCODE 22023. Repartir por
--   valor sin valor es indefinido, y caer a "partes iguales" inventaría un
--   costo. El mensaje dice qué líneas no tienen costo.
--
-- ---------------------------------------------------------------------------
-- ATRIBUCIÓN — qué líneas son de este vínculo (D10)
-- ---------------------------------------------------------------------------
--   `fdi_dat_compra_recepcion` tiene `UNIQUE(id_operacion, id_compra)`: una
--   misma carga puede cubrir N compras. Por eso "las líneas de la recepción"
--   NO son "las líneas del vínculo". `fn_fdi_compra_recepcion_bases` resuelve
--   el conjunto, en este orden:
--     1. líneas cuyo `fdi_dat_compra_recepcion_linea.id_recepcion_producto`
--        apunta al vínculo (el camino explícito, hoy sin poblar);
--     2. líneas que ya tienen un costo atribuido al vínculo
--        (`app_dat_recepcion_producto_costo.id_compra_recepcion`);
--     3. si la operación tiene **un solo** vínculo, todas sus líneas.
--   Con dos o más vínculos y sin 1 ni 2, la función **aborta** con 22023: no se
--   adivina por producto/variante, porque dos compras pueden traer el mismo
--   producto y el costo caería en la línea equivocada.
--
--   Todo lo que escribe el reparto —borrar, insertar, cuadrar y la foto del
--   promedio anterior— se filtra por `id_compra_recepcion`. Las filas legadas
--   con `id_compra_recepcion IS NULL` sólo se retiran si su línea pertenece al
--   vínculo según la resolución de arriba; así se curan las de la v1 sin tocar
--   las de otra compra.
--
-- ---------------------------------------------------------------------------
-- ORIGEN DE PAGO — qué se toca y qué no
-- ---------------------------------------------------------------------------
--   · wallet_importadora | externo  → se reparte y se persiste
--                                      (`capitaliza = true`).
--   · fondo                          → NO se toca el costo: lo paga el fondo y
--                                      ya está en su ledger. Se devuelve
--                                      `status = 'omitido'`, `capitaliza =
--                                      false` y el motivo. **La tasa sí queda
--                                      registrada en la operación** (D3).
--   · wallet_proveedor               → tampoco capitaliza. El CHECK del vínculo
--                                      lo admite, pero el encargo sólo autoriza
--                                      los dos anteriores. Se devuelve un aviso
--                                      DISTINTO (`motivo =
--                                      'origen_pago_wallet_proveedor'`) y la
--                                      tasa también se registra en la operación.
--
--   El jsonb de toda respuesta lleva `capitaliza` (true/false) y, si es false,
--   `motivo`; la tasa nunca se descarta en silencio.
--
-- ---------------------------------------------------------------------------
-- IDEMPOTENCIA — reemplaza, no ignora
-- ---------------------------------------------------------------------------
--   `app_dat_recepcion_producto_costo` no tiene UNIQUE(recepción, tipo), así
--   que no hay `ON CONFLICT` posible. La función:
--     1. guarda en memoria el `monto_promedio_anterior` de las filas que ya
--        existan (para no perder la trazabilidad original),
--     2. BORRA todas las filas (id_recepcion_producto, tipo 'Importadora') de
--        la recepción — esto además cura duplicados que hubiera dejado el
--        cliente,
--     3. inserta exactamente una por línea.
--   Resultado: llamarla N veces con la misma tasa deja el mismo estado.
--   **Reemplaza** (no ignora) porque el motivo de existir de 06b es que el
--   importe lo calcule el servidor y no el cliente: si ya había una fila con
--   el importe que mandó el cliente, hay que corregirla, no conservarla.
--   Se **conserva** el `monto_promedio_anterior` de la fila previa: es la foto
--   del promedio anterior a esta recepción y no debe moverse al recalcular.
--
--   IDEMPOTENCIA DEL WRAPPER Y TASA (D4): `fn_fdi_recepcion_con_costos` compara
--   `app_dat_operacion_recepcion.fdi_solicitud` ignorando las claves de tasa
--   (`p_tasa_usd`, `tasa_usd_aplicada`, `tasa_cambio_aplicada`,
--   `fecha_tasa_aplicada`). Corregir la tasa en un reintento con la misma clave
--   no aborta con "la clave ya corresponde a otra solicitud": la solicitud es
--   la misma y la tasa se actualiza en la operación.
--
--   CONCURRENCIA: la función bloquea la fila del vínculo (`FOR UPDATE`), así
--   que dos llamadas simultáneas sobre el mismo vínculo se serializan.
--
--   ORDEN respecto al promedio: `monto_promedio_anterior` se lee de
--   `app_dat_producto_costo.monto_promedio_usd` (producto + tipo), que es
--   exactamente lo que hace `fn_actualizar_precio_promedio_recepcion_v2` en su
--   INSERT. **06b debe ejecutarse ANTES de v2/v3**, que son quienes capitalizan
--   el adicional al promedio; si se ejecuta después, el promedio ya se calculó
--   con el importe viejo y hay que volver a lanzar v2/v3. La función devuelve
--   `orden_sugerido` recordándolo.
--
-- ---------------------------------------------------------------------------
-- NOTA sobre `monto_promedio_anterior` ("el promedio vigente de esa línea")
-- ---------------------------------------------------------------------------
--   No existe un promedio por línea de recepción: el promedio vigente del
--   concepto para esa línea es el del PRODUCTO. Se usa, igual que v2:
--       app_dat_producto_costo.monto_promedio_usd  (id_producto, id_tipo_costo)
--   y 0 si no hay fila. NO se inventa un promedio por `id_presentacion` (el
--   módulo guarda `precio_promedio` por presentación, pero es otra magnitud:
--   costo del producto, no del concepto).
--
-- ---------------------------------------------------------------------------
-- TASA APLICADA — persistida en la operación y en el vínculo
-- ---------------------------------------------------------------------------
--   La tasa efectiva (ya normalizada a 1 si la moneda de la operación es USD)
--   se guarda en:
--     · `app_dat_operacion_recepcion.tasa_cambio_aplicada` +
--       `fecha_tasa_aplicada` (UTC): fuente única, la escribe el wrapper y,
--       cuando hace falta, `fn_fdi_compra_repartir_aterrizaje`.
--     · `fdi_dat_compra_recepcion.tasa_usd_aplicada numeric(18,10)`: la deja
--       el reparto por el `id` del vínculo. NULL a propósito cuando el reparto
--       no ha ocurrido (o en vínculos anteriores a este script): NULL dice
--       "no hay tasa aplicada aquí", no se inventa un 1.
--
--   `verify/06_costos.sql` comprueba que en vínculos USD `tasa_usd_aplicada`
--   no puede ser distinta de 1, y que las operaciones con costos capitalizados
--   tienen `tasa_cambio_aplicada` no nula.
--
-- ROLLBACK: 06b_aterrizaje_rollback.sql
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0) Preflight de dependencias
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v integer;
    v_falta text := '';
BEGIN
    IF to_regclass('public.fdi_dat_compra_recepcion') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_recepcion;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_recepcion_linea') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_recepcion_linea;';
    END IF;
    IF to_regclass('public.fdi_dat_compra_linea') IS NULL THEN
        v_falta := v_falta || ' fdi_dat_compra_linea;';
    END IF;
    IF to_regclass('public.app_dat_recepcion_productos') IS NULL THEN
        v_falta := v_falta || ' app_dat_recepcion_productos;';
    END IF;
    IF to_regclass('public.app_dat_recepcion_producto_costo') IS NULL THEN
        v_falta := v_falta || ' app_dat_recepcion_producto_costo;';
    END IF;
    IF to_regclass('public.app_dat_producto_costo') IS NULL THEN
        v_falta := v_falta || ' app_dat_producto_costo;';
    END IF;
    IF to_regclass('public.app_cont_tipo_costo') IS NULL THEN
        v_falta := v_falta || ' app_cont_tipo_costo;';
    END IF;
    IF v_falta <> '' THEN
        RAISE EXCEPTION '06b: faltan tablas:%. Aplique 05a, 05c y 06a antes.', v_falta
            USING ERRCODE = '42P01';
    END IF;

    -- D6: la tasa vive en la OPERACIÓN, no en el vínculo. Sin estas dos
    -- columnas la función fallaría EN EJECUCIÓN (no en el preflight) en un
    -- entorno nuevo, así que se comprueban aquí, antes de crear nada.
    IF to_regclass('public.app_dat_operacion_recepcion') IS NULL THEN
        RAISE EXCEPTION '06b: falta app_dat_operacion_recepcion; no se puede registrar la tasa de la operación.'
            USING ERRCODE = '42P01';
    END IF;

    SELECT count(*) INTO v FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'app_dat_operacion_recepcion'
       AND column_name IN ('tasa_cambio_aplicada','fecha_tasa_aplicada');
    IF v <> 2 THEN
        RAISE EXCEPTION '06b: app_dat_operacion_recepcion no tiene tasa_cambio_aplicada y fecha_tasa_aplicada (% de 2). Aplique el esquema base y 05a antes.', v;
    END IF;

    -- D5: la función escribe `now() AT TIME ZONE 'UTC'`; la columna debe ser
    -- timestamp SIN zona. Si alguien la cambia a timestamptz, la escritura
    -- vuelve a depender del TimeZone de la sesión y se avisa aquí.
    SELECT count(*) INTO v FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'app_dat_operacion_recepcion'
       AND column_name = 'fecha_tasa_aplicada'
       AND data_type = 'timestamp without time zone';
    IF v <> 1 THEN
        RAISE EXCEPTION '06b: app_dat_operacion_recepcion.fecha_tasa_aplicada debe ser timestamp without time zone (la función escribe UTC explícito).';
    END IF;

    -- Columnas del vínculo que 05a añadió.
    SELECT count(*) INTO v FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'fdi_dat_compra_recepcion'
       AND column_name IN ('pct_importadora','base_importadora','monto_importadora',
                           'reembolso_importadora','origen_pago');
    IF v <> 5 THEN
        RAISE EXCEPTION '06b: el vínculo no tiene las 5 columnas de importadora (% de 5). Falta 05a.', v;
    END IF;

    -- `costo_real` escribible: la base del reparto depende de él.
    SELECT count(*) INTO v FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'app_dat_recepcion_productos'
       AND column_name IN ('cantidad','precio_unitario','costo_real','id_variante','id_operacion','id_producto');
    IF v <> 6 THEN
        RAISE EXCEPTION '06b: app_dat_recepcion_productos no tiene las 6 columnas esperadas (% de 6).', v;
    END IF;

    -- Catálogo sembrado por 06a y tipo 'Importadora' resoluble.
    SELECT count(*) INTO v FROM public.app_cont_tipo_costo
     WHERE lower(btrim(denominacion)) IN ('aduana','flete','importadora','seguro');
    IF v <> 4 THEN
        RAISE EXCEPTION '06b: el catálogo de tipos de costo tiene % de los 4 tipos. Falta 06a.', v;
    END IF;

    SELECT count(*) INTO v FROM public.app_cont_tipo_costo
     WHERE lower(btrim(denominacion)) = 'importadora';
    IF v = 0 THEN
        RAISE EXCEPTION '06b: no hay tipo de costo con denominación Importadora.' USING ERRCODE = 'P0002';
    END IF;
    IF v > 1 THEN
        RAISE EXCEPTION '06b: hay % filas con denominación Importadora; el tipo es ambiguo y no se puede aterrizar sin elegir una.', v
            USING ERRCODE = '22023';
    END IF;

    -- Funciones de las que depende el carril transaccional.
    IF to_regprocedure('public.fn_registrar_recepcion_con_inventario(text,bigint,numeric,integer,text,jsonb,text,uuid,text,bigint,numeric,boolean)') IS NULL THEN
        RAISE EXCEPTION '06b: falta fn_registrar_recepcion_con_inventario con su firma de 12 argumentos.' USING ERRCODE = 'P0002';
    END IF;
    IF to_regprocedure('public.fn_fdi_registrar_recepcion(jsonb,jsonb,uuid,bigint)') IS NULL THEN
        RAISE EXCEPTION '06b: falta fn_fdi_registrar_recepcion(jsonb,jsonb,uuid,bigint). Falta 05c.' USING ERRCODE = 'P0002';
    END IF;
    IF to_regprocedure('public.fn_user_is_gerente_or_superadmin(bigint)') IS NULL THEN
        RAISE EXCEPTION '06b: falta fn_user_is_gerente_or_superadmin(bigint).' USING ERRCODE = 'P0002';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 0b) Columna de auditoría de la tasa efectiva
--
--     La escriben las dos funciones de abajo: `fn_fdi_compra_repartir_aterrizaje`
--     deja la tasa que usó realmente el reparto (normalizada a 1 si la moneda
--     de la OPERACIÓN es USD, y escrita por el `id` del vínculo), y
--     `fn_fdi_recepcion_con_costos` la registra en la OPERACIÓN cuando el
--     llamador manda una (ya no escribe esta tabla). Es NULL-able y sin DEFAULT
--     a propósito: un vínculo que aún no ha pasado por el reparto no tiene tasa
--     aplicada y NULL lo dice, no un 1 inventado.
-- ---------------------------------------------------------------------------
ALTER TABLE public.fdi_dat_compra_recepcion
    ADD COLUMN IF NOT EXISTS tasa_usd_aplicada numeric(18,10);

-- ---------------------------------------------------------------------------
-- 0c) Atribución del costo a su vínculo (D10)
--
--     Sin esta columna, "los costos de la recepción" = "los costos de la
--     operación", y una operación puede cubrir N compras: el reparto de la
--     segunda borraba los de la primera. NULL-able a propósito:
--       · el cliente escribe costos por su cuenta (sin vínculo todavía), y
--       · una operación con varios vínculos no se atribuye sin adivinar.
--     El reparto siempre la rellena.
--
--     ON DELETE CASCADE como `fdi_dat_compra_recepcion_linea`: si alguna vez
--     se retira un vínculo, sus costos no quedan huérfanos apuntando a un id
--     inexistente.
-- ---------------------------------------------------------------------------
ALTER TABLE public.app_dat_recepcion_producto_costo
    ADD COLUMN IF NOT EXISTS id_compra_recepcion bigint
        REFERENCES public.fdi_dat_compra_recepcion(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_recepcion_producto_costo_vinculo
    ON public.app_dat_recepcion_producto_costo (id_compra_recepcion);

-- Backfill idempotente: las filas del tipo Importadora en una operación con
-- **un solo** vínculo pasan a estar atribuidas a ese vínculo. Con dos o más no
-- se tocan (quedan NULL) porque no hay forma de saber a cuál pertenecen sin
-- `id_recepcion_producto`; el reparto de cada vínculo las ignora y escribe las
-- suyas.
UPDATE public.app_dat_recepcion_producto_costo c
   SET id_compra_recepcion = v.id_link
  FROM (
        SELECT c2.id           AS id_costo,
               min(r.id)       AS id_link,
               count(r.id)     AS n_vinculos
          FROM public.app_dat_recepcion_producto_costo c2
          JOIN public.app_dat_recepcion_productos rp ON rp.id = c2.id_recepcion_producto
          JOIN public.fdi_dat_compra_recepcion r ON r.id_operacion = rp.id_operacion
         WHERE c2.id_compra_recepcion IS NULL
           AND c2.id_tipo_costo IN (
               SELECT t.id FROM public.app_cont_tipo_costo t
                WHERE lower(btrim(t.denominacion)) = 'importadora')
         GROUP BY c2.id
       ) v
 WHERE c.id = v.id_costo
   AND v.n_vinculos = 1;

-- ---------------------------------------------------------------------------
-- 1) Base del reparto: valor de cada línea DEL VÍNCULO
--
--    Devuelve, por línea recibida del vínculo, el costo unitario aplicado y su
--    valor (`cantidad × costo_unitario`). El conjunto de líneas no es "todas
--    las de la operación": se resuelve como dice "ATRIBUCIÓN" arriba (D10).
--    Precedencia del costo unitario, en orden:
--      1. `fdi_dat_compra_recepcion_linea.costo_unitario_aplicado` con
--         `id_recepcion_producto` apuntando a la línea (vínculo explícito).
--         Hoy nunca está poblado, pero es el camino bueno si 05x lo rellena.
--      2. `costo_unitario_aplicado` de la compra **sólo si hay una única**
--         línea de compra candidata para ese (producto, variante) en esa
--         recepción. Con dos candidatas no se adivina: se baja al paso 3.
--      3. `app_dat_recepcion_productos.costo_real` (el costo aplicado que
--         calculó el trigger).
--      4. `precio_unitario`.
--      5. 0.
--    `origen_costo` deja escrito cuál de los cinco se usó, por línea.
--
--    STABLE: no escribe. Se puede llamar para previsualizar el reparto.
--    **Aborta** (22023) si la operación cubre varias compras y el vínculo no
--    tiene líneas atribuibles: una previsualización que devolviera 0 líneas
--    ahí mentiría.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_recepcion_bases(p_id_compra_recepcion bigint)
RETURNS TABLE (
    id_recepcion_producto bigint,
    id_producto           bigint,
    cantidad              numeric,
    costo_unitario        numeric,
    base                  numeric,
    origen_costo          text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id_operacion bigint;
    v_vinculos     integer;
    v_ids          bigint[];
BEGIN
    SELECT r.id_operacion INTO v_id_operacion
      FROM public.fdi_dat_compra_recepcion r
     WHERE r.id = p_id_compra_recepcion;

    IF NOT FOUND THEN
        RAISE EXCEPTION '06b: vínculo compra↔recepción % no encontrado', p_id_compra_recepcion
            USING ERRCODE = 'P0002';
    END IF;

    SELECT count(*) INTO v_vinculos
      FROM public.fdi_dat_compra_recepcion r
     WHERE r.id_operacion = v_id_operacion;

    -- D10: líneas atribuibles a ESTE vínculo. Dos fuentes explícitas; si no hay
    -- ninguna y la operación cubre una sola compra, son todas las de la
    -- operación. Con varias compras y sin atribución no se adivina.
    SELECT array_agg(x.id_rp) INTO v_ids
      FROM (
            SELECT crl.id_recepcion_producto AS id_rp
              FROM public.fdi_dat_compra_recepcion_linea crl
             WHERE crl.id_compra_recepcion = p_id_compra_recepcion
               AND crl.id_recepcion_producto IS NOT NULL
            UNION
            SELECT c.id_recepcion_producto
              FROM public.app_dat_recepcion_producto_costo c
             WHERE c.id_compra_recepcion = p_id_compra_recepcion
           ) x;

    IF v_vinculos > 1 AND COALESCE(array_length(v_ids, 1), 0) = 0 THEN
        RAISE EXCEPTION '06b: la recepción % cubre % compras y el vínculo % no tiene líneas atribuidas; no se puede repartir sin adivinar (poblar id_recepcion_producto en fdi_dat_compra_recepcion_linea).',
            v_id_operacion, v_vinculos, p_id_compra_recepcion
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH linea AS (
        SELECT rp.id              AS id_rp,
               rp.id_producto     AS id_prod,
               rp.cantidad        AS cant,
               (SELECT crl.costo_unitario_aplicado
                  FROM public.fdi_dat_compra_recepcion_linea crl
                 WHERE crl.id_compra_recepcion = p_id_compra_recepcion
                   AND crl.id_recepcion_producto = rp.id
                 ORDER BY crl.id
                 LIMIT 1)         AS costo_explicito,
               (SELECT CASE WHEN count(*) = 1
                            THEN min(crl.costo_unitario_aplicado) END
                  FROM public.fdi_dat_compra_recepcion_linea crl
                  JOIN public.fdi_dat_compra_linea cl ON cl.id = crl.id_compra_linea
                 WHERE crl.id_compra_recepcion = p_id_compra_recepcion
                   AND crl.id_recepcion_producto IS NULL
                   AND cl.id_producto = rp.id_producto
                   AND cl.id_variante IS NOT DISTINCT FROM rp.id_variante) AS costo_unico,
               rp.costo_real      AS costo_real,
               rp.precio_unitario AS precio
          FROM public.app_dat_recepcion_productos rp
         WHERE rp.id_operacion = v_id_operacion
           AND (v_vinculos = 1 OR rp.id = ANY(COALESCE(v_ids, '{}'::bigint[])))
    ),
    resuelto AS (
        SELECT li.id_rp,
               li.id_prod,
               li.cant,
               COALESCE(li.costo_explicito, li.costo_unico, li.costo_real, li.precio, 0) AS costo,
               CASE WHEN li.costo_explicito IS NOT NULL THEN 'compra_linea_vinculada'
                    WHEN li.costo_unico     IS NOT NULL THEN 'compra_linea_unica'
                    WHEN li.costo_real      IS NOT NULL THEN 'costo_real'
                    WHEN li.precio          IS NOT NULL THEN 'precio_unitario'
                    ELSE 'ninguno' END                                                AS origen
          FROM linea li
    )
    SELECT res.id_rp,
           res.id_prod,
           res.cant,
           res.costo,
           round(res.cant * res.costo, 6),
           res.origen
      FROM resuelto res
     ORDER BY res.id_rp;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_compra_recepcion_bases(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_recepcion_bases(bigint) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) Reparto del cargo de importadora entre las líneas de la recepción
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_repartir_aterrizaje(
    p_id_compra_recepcion bigint,
    p_tasa_usd            numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_link         record;
    v_op_moneda    character varying;
    v_op_tasa      numeric;
    v_moneda_op    text;
    v_moneda_link  text;
    v_tasa         numeric;
    v_tasa_origen  text;
    v_tasa_forzada boolean := false;
    v_id_tipo      bigint;
    v_n_tipos      integer;
    v_cargo_usd    numeric;
    v_lineas       integer;
    v_base_total   numeric;
    v_prev         jsonb := '{}'::jsonb;
    v_borradas     integer := 0;
    v_insertadas   integer := 0;
    v_suma         numeric;
    v_filas        integer;
    v_sin_costo    integer;
BEGIN
    -- --- Vínculo (bloqueado: serializa llamadas concurrentes) ---------------
    SELECT r.id, r.id_compra, r.id_operacion, r.id_tienda,
           r.monto_importadora, r.origen_pago, r.moneda
      INTO v_link
      FROM public.fdi_dat_compra_recepcion r
     WHERE r.id = p_id_compra_recepcion
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION '06b: vínculo compra↔recepción % no encontrado', p_id_compra_recepcion
            USING ERRCODE = 'P0002';
    END IF;

    IF auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_link.id_tienda), false) THEN
        RAISE EXCEPTION '06b: sólo gerente o superadmin pueden aterrizar el costo de la recepción %', v_link.id_operacion
            USING ERRCODE = '42501';
    END IF;

    -- --- Fuente única: la operación ----------------------------------------
    -- D1: la moneda y la tasa salen de app_dat_operacion_recepcion, no del
    -- vínculo. El vínculo sólo aporta el cargo y el origen de pago.
    SELECT o.moneda_factura, o.tasa_cambio_aplicada
      INTO v_op_moneda, v_op_tasa
      FROM public.app_dat_operacion_recepcion o
     WHERE o.id_operacion = v_link.id_operacion;

    IF NOT FOUND THEN
        RAISE EXCEPTION '06b: la operación % no tiene fila en app_dat_operacion_recepcion; no se puede resolver la moneda ni la tasa de la factura.', v_link.id_operacion
            USING ERRCODE = 'P0002';
    END IF;

    v_moneda_op   := upper(btrim(COALESCE(v_op_moneda, '')));
    v_moneda_link := upper(btrim(COALESCE(v_link.moneda, '')));

    -- D9: la moneda del vínculo tiene que ser la de la operación. El vínculo la
    -- guarda al enlazar (`fn_fdi_compra_vincular_recepcion` copia
    -- `fdi_dat_compra.moneda_total`); si no coincide con la factura, el cargo
    -- —que está en la moneda del vínculo— se convertiría con la tasa de otra
    -- moneda y el importe cambiaría sin avisar. Se aborta ANTES de escribir.
    IF v_moneda_link <> '' AND v_moneda_op <> ''
       AND v_moneda_link IS DISTINCT FROM v_moneda_op THEN
        RAISE EXCEPTION '06b: la moneda del vínculo (%) no coincide con la de la operación % (%). Corrija la recepción o la compra: el cargo no se convierte con la tasa de otra moneda.',
            v_moneda_link, v_link.id_operacion, v_moneda_op
            USING ERRCODE = '22023';
    END IF;

    -- --- Tasa: el parámetro si viene; si no, la registrada en la operación --
    IF p_tasa_usd IS NOT NULL THEN
        IF NOT (p_tasa_usd > 0) OR p_tasa_usd >= 'Infinity'::numeric THEN
            RAISE EXCEPTION '06b: p_tasa_usd debe ser un número finito > 0 (recibido: %). Recuerde: moneda de la factura por 1 USD.', p_tasa_usd
                USING ERRCODE = '22023';
        END IF;
        v_tasa        := p_tasa_usd;
        v_tasa_origen := 'parametro';
    ELSIF v_op_tasa IS NOT NULL THEN
        IF NOT (v_op_tasa > 0) OR v_op_tasa >= 'Infinity'::numeric THEN
            RAISE EXCEPTION '06b: la tasa registrada en la operación % no es un número finito > 0 (%). Corríjala en app_dat_operacion_recepcion o pase p_tasa_usd.', v_link.id_operacion, v_op_tasa
                USING ERRCODE = '22023';
        END IF;
        v_tasa        := v_op_tasa;
        v_tasa_origen := 'operacion';
    END IF;

    -- Normalización por la moneda de la OPERACIÓN (no por la del vínculo).
    IF v_moneda_op = 'USD' THEN
        IF v_tasa IS NOT NULL AND v_tasa <> 1 THEN
            v_tasa_forzada := true;
        END IF;
        IF v_tasa IS NULL THEN
            v_tasa_origen := 'moneda_usd';
        END IF;
        v_tasa := 1;
    END IF;

    IF v_tasa IS NULL THEN
        RAISE EXCEPTION '06b: la operación % no tiene tasa registrada (tasa_cambio_aplicada NULL) y su moneda de factura es %; registre la tasa de la operación o pase p_tasa_usd.', v_link.id_operacion, COALESCE(v_op_moneda, 'NULL')
            USING ERRCODE = '22023';
    END IF;

    -- --- La tasa se registra SIEMPRE en la operación (D3) -------------------
    -- Antes se descartaba, en silencio, cuando origen_pago era fondo o
    -- wallet_proveedor porque la función retornaba antes de escribir nada.
    -- `fecha_tasa_aplicada` es timestamp WITHOUT time zone (D5): se escribe
    -- now() AT TIME ZONE 'UTC' para que no dependa del TimeZone de la sesión.
    -- D12: la fecha se re-sella SÓLO si la tasa cambia (corrección); un
    -- reintento con la misma tasa conserva la fecha del primer registro.
    UPDATE public.app_dat_operacion_recepcion
       SET tasa_cambio_aplicada = v_tasa,
           fecha_tasa_aplicada  = CASE
               WHEN tasa_cambio_aplicada IS DISTINCT FROM v_tasa
                   THEN now() AT TIME ZONE 'UTC'
               ELSE COALESCE(fecha_tasa_aplicada, now() AT TIME ZONE 'UTC')
           END
     WHERE id_operacion = v_link.id_operacion;

    -- --- Quién paga: sin cargo a la recepción si lo paga el fondo -----------
    IF v_link.origen_pago = 'fondo' THEN
        RETURN jsonb_build_object(
            'status', 'omitido',
            'motivo', 'origen_pago_fondo',
            'capitaliza', false,
            'aviso', 'El cargo lo paga el fondo y ya está en su ledger: no se toca el costo de la recepción. La tasa sí queda registrada en la operación.',
            'id_compra_recepcion', p_id_compra_recepcion,
            'id_compra', v_link.id_compra,
            'id_operacion', v_link.id_operacion,
            'origen_pago', v_link.origen_pago,
            'moneda_operacion', v_moneda_op,
            'moneda_vinculo', v_moneda_link,
            'tasa_usd', v_tasa,
            'tasa_usd_aplicada', v_tasa,
            'tasa_origen', v_tasa_origen,
            'tasa_forzada_usd', v_tasa_forzada,
            'tasa_registrada_en_operacion', true,
            'monto_importadora', v_link.monto_importadora);
    END IF;

    IF v_link.origen_pago = 'wallet_proveedor' THEN
        RETURN jsonb_build_object(
            'status', 'omitido',
            'motivo', 'origen_pago_wallet_proveedor',
            'capitaliza', false,
            'aviso', 'origen_pago = wallet_proveedor no capitaliza (decisión del dueño): sólo wallet_importadora y externo aterrizan. La tasa sí queda registrada en la operación.',
            'id_compra_recepcion', p_id_compra_recepcion,
            'id_compra', v_link.id_compra,
            'id_operacion', v_link.id_operacion,
            'origen_pago', v_link.origen_pago,
            'moneda_operacion', v_moneda_op,
            'moneda_vinculo', v_moneda_link,
            'tasa_usd', v_tasa,
            'tasa_usd_aplicada', v_tasa,
            'tasa_origen', v_tasa_origen,
            'tasa_forzada_usd', v_tasa_forzada,
            'tasa_registrada_en_operacion', true,
            'monto_importadora', v_link.monto_importadora);
    END IF;

    -- El CHECK del vínculo sólo admite los 4 valores; si aparece otro, cerramos.
    IF v_link.origen_pago IS DISTINCT FROM 'wallet_importadora'
       AND v_link.origen_pago IS DISTINCT FROM 'externo' THEN
        RAISE EXCEPTION '06b: origen_pago inesperado (%) en el vínculo %. No se toca el costo.',
            COALESCE(v_link.origen_pago, 'NULL'), p_id_compra_recepcion
            USING ERRCODE = '22023';
    END IF;

    -- --- Tipo de costo por denominación (nunca por id) ----------------------
    SELECT count(*), min(t.id)
      INTO v_n_tipos, v_id_tipo
      FROM public.app_cont_tipo_costo t
     WHERE lower(btrim(t.denominacion)) = 'importadora';

    IF v_n_tipos = 0 THEN
        RAISE EXCEPTION '06b: no hay tipo de costo Importadora en app_cont_tipo_costo.' USING ERRCODE = 'P0002';
    END IF;
    IF v_n_tipos > 1 THEN
        RAISE EXCEPTION '06b: % filas con denominación Importadora; el tipo es ambiguo y no se aterriza a ciegas.', v_n_tipos
            USING ERRCODE = '22023';
    END IF;

    -- --- Cargo a USD --------------------------------------------------------
    IF v_link.monto_importadora < 0 THEN
        RAISE EXCEPTION '06b: el cargo de importadora del vínculo % es negativo (%); no se reparte un abono.',
            p_id_compra_recepcion, v_link.monto_importadora
            USING ERRCODE = '22023';
    END IF;

    v_cargo_usd := round(v_link.monto_importadora / v_tasa, 2);

    -- --- Persistencia de la tasa efectiva en el VÍNCULO, por su id (D1/D2) --
    -- Con varias compras en una misma carga, filtrar por id_operacion pisaría
    -- vínculos ajenos: se escribe por id. El wrapper ya no escribe esta tabla.
    UPDATE public.fdi_dat_compra_recepcion
       SET tasa_usd_aplicada = v_tasa
     WHERE id = p_id_compra_recepcion;

    -- --- Sin cargo: se limpia lo que hubiera (idempotencia) ------------------
    -- D10: sólo lo de ESTE vínculo. Las filas legadas sin atribución se retiran
    -- únicamente si su línea pertenece al vínculo según `bases`; nunca las de
    -- otra compra de la misma carga.
    IF v_cargo_usd = 0 THEN
        DELETE FROM public.app_dat_recepcion_producto_costo c
         WHERE c.id_tipo_costo = v_id_tipo
           AND (c.id_compra_recepcion = p_id_compra_recepcion
                OR (c.id_compra_recepcion IS NULL
                    AND c.id_recepcion_producto IN (
                        SELECT b.id_recepcion_producto
                          FROM public.fn_fdi_compra_recepcion_bases(p_id_compra_recepcion) b)));
        GET DIAGNOSTICS v_borradas = ROW_COUNT;

        RETURN jsonb_build_object(
            'status', 'sin_cargo',
            'motivo', CASE WHEN v_link.monto_importadora = 0
                           THEN 'cargo_cero'
                           ELSE 'cargo_redondeado_a_cero' END,
            'capitaliza', false,
            'aviso', 'No hay cargo que aterrizar; se retiraron las filas previas del tipo Importadora del vínculo. La tasa quedó registrada en la operación y en el vínculo.',
            'id_compra_recepcion', p_id_compra_recepcion,
            'id_compra', v_link.id_compra,
            'id_operacion', v_link.id_operacion,
            'origen_pago', v_link.origen_pago,
            'moneda_operacion', v_moneda_op,
            'moneda_vinculo', v_moneda_link,
            'monto_importadora', v_link.monto_importadora,
            'tasa_usd', v_tasa,
            'tasa_usd_aplicada', v_tasa,
            'tasa_origen', v_tasa_origen,
            'tasa_forzada_usd', v_tasa_forzada,
            'tasa_registrada_en_operacion', true,
            'cargo_usd', v_cargo_usd,
            'id_tipo_costo', v_id_tipo,
            'filas_retiradas', v_borradas);
    END IF;

    -- --- Bases del reparto --------------------------------------------------
    SELECT count(*),
           COALESCE(sum(b.base), 0),
           count(*) FILTER (WHERE b.base <= 0)
      INTO v_lineas, v_base_total, v_sin_costo
      FROM public.fn_fdi_compra_recepcion_bases(p_id_compra_recepcion) b;

    IF v_lineas = 0 THEN
        RAISE EXCEPTION '06b: la recepción % no tiene líneas en app_dat_recepcion_productos; no hay entre qué repartir.',
            v_link.id_operacion USING ERRCODE = 'P0002';
    END IF;

    IF v_base_total <= 0 THEN
        RAISE EXCEPTION '06b: no se puede repartir por valor: la recepción % tiene base total % (% de % líneas sin costo). Cargue el costo unitario de las líneas y reintente.',
            v_link.id_operacion, v_base_total, v_sin_costo, v_lineas
            USING ERRCODE = '22023';
    END IF;

    -- --- Foto del promedio anterior de las filas que ya existan -------------
    -- D10: mismo alcance que el borrado (vínculo + legadas sólo si la línea es
    -- del vínculo).
    SELECT COALESCE(jsonb_object_agg(x.id_rp::text, x.prev), '{}'::jsonb)
      INTO v_prev
      FROM (
            SELECT DISTINCT ON (c.id_recepcion_producto)
                   c.id_recepcion_producto AS id_rp,
                   c.monto_promedio_anterior AS prev
              FROM public.app_dat_recepcion_producto_costo c
             WHERE c.id_tipo_costo = v_id_tipo
               AND (c.id_compra_recepcion = p_id_compra_recepcion
                    OR (c.id_compra_recepcion IS NULL
                        AND c.id_recepcion_producto IN (
                            SELECT b.id_recepcion_producto
                              FROM public.fn_fdi_compra_recepcion_bases(p_id_compra_recepcion) b)))
             ORDER BY c.id_recepcion_producto, c.id
           ) x;

    -- --- Limpieza (reemplaza; cura duplicados) ------------------------------
    -- D10: nunca las filas de otro vínculo de la misma operación.
    DELETE FROM public.app_dat_recepcion_producto_costo c
     WHERE c.id_tipo_costo = v_id_tipo
       AND (c.id_compra_recepcion = p_id_compra_recepcion
            OR (c.id_compra_recepcion IS NULL
                AND c.id_recepcion_producto IN (
                    SELECT b.id_recepcion_producto
                      FROM public.fn_fdi_compra_recepcion_bases(p_id_compra_recepcion) b)));
    GET DIAGNOSTICS v_borradas = ROW_COUNT;

    -- --- Reparto y persistencia --------------------------------------------
    WITH bases AS (
        SELECT b.id_recepcion_producto, b.id_producto, b.base
          FROM public.fn_fdi_compra_recepcion_bases(p_id_compra_recepcion) b
    ),
    tot AS (
        SELECT COALESCE(sum(b.base), 0) AS base_total FROM bases b
    ),
    destino AS (
        -- Residuo: la línea de MAYOR base; empate → MENOR id.
        SELECT b.id_recepcion_producto
          FROM bases b
         ORDER BY b.base DESC, b.id_recepcion_producto ASC
         LIMIT 1
    ),
    prorr AS (
        SELECT b.id_recepcion_producto,
               b.id_producto,
               b.base,
               round(v_cargo_usd * b.base / t.base_total, 2) AS monto
          FROM bases b
          CROSS JOIN tot t
    ),
    residuo AS (
        SELECT v_cargo_usd - COALESCE(sum(p.monto), 0) AS r FROM prorr p
    ),
    plan AS (
        SELECT p.id_recepcion_producto,
               p.id_producto,
               p.monto + CASE WHEN p.id_recepcion_producto = (SELECT id_recepcion_producto FROM destino)
                              THEN (SELECT r FROM residuo)
                              ELSE 0 END AS monto
          FROM prorr p
    )
    INSERT INTO public.app_dat_recepcion_producto_costo
        (id_recepcion_producto, id_tipo_costo, monto_usd, monto_promedio_anterior,
         id_compra_recepcion)
    SELECT pl.id_recepcion_producto,
           v_id_tipo,
           pl.monto,
           COALESCE(
               (v_prev ->> (pl.id_recepcion_producto::text))::numeric,
               (SELECT pc.monto_promedio_usd
                  FROM public.app_dat_producto_costo pc
                 WHERE pc.id_producto = pl.id_producto
                   AND pc.id_tipo_costo = v_id_tipo),
               0),
           p_id_compra_recepcion
      FROM plan pl;

    GET DIAGNOSTICS v_insertadas = ROW_COUNT;

    -- --- Cuadre antes de devolver ------------------------------------------
    -- D10: el cuadre es del vínculo, no de la operación.
    SELECT count(*), COALESCE(sum(c.monto_usd), 0)
      INTO v_filas, v_suma
      FROM public.app_dat_recepcion_producto_costo c
     WHERE c.id_tipo_costo = v_id_tipo
       AND c.id_compra_recepcion = p_id_compra_recepcion;

    IF v_filas <> v_lineas THEN
        RAISE EXCEPTION '06b: quedaron % filas de costo para % líneas en la recepción %. Se aborta.',
            v_filas, v_lineas, v_link.id_operacion USING ERRCODE = 'P0001';
    END IF;

    IF abs(v_suma - v_cargo_usd) >= 0.005 THEN
        RAISE EXCEPTION '06b: el reparto no cuadra en la recepción %: Σ monto_usd = %, cargo = %. Se aborta.',
            v_link.id_operacion, v_suma, v_cargo_usd USING ERRCODE = 'P0001';
    END IF;

    RETURN jsonb_build_object(
        'status', 'ok',
        'id_compra_recepcion', p_id_compra_recepcion,
        'id_compra', v_link.id_compra,
        'id_operacion', v_link.id_operacion,
        'origen_pago', v_link.origen_pago,
        'capitaliza', true,
        'moneda', v_link.moneda,
        'moneda_operacion', v_moneda_op,
        'moneda_vinculo', v_moneda_link,
        'tasa_usd', v_tasa,
        'tasa_usd_aplicada', v_tasa,
        'tasa_origen', v_tasa_origen,
        'tasa_forzada_usd', v_tasa_forzada,
        'tasa_registrada_en_operacion', true,
        'monto_importadora', v_link.monto_importadora,
        'cargo_usd', v_cargo_usd,
        'id_tipo_costo', v_id_tipo,
        'lineas', v_lineas,
        'lineas_sin_costo', v_sin_costo,
        'base_total', v_base_total,
        'filas_retiradas', v_borradas,
        'filas_insertadas', v_insertadas,
        'suma_monto_usd', v_suma,
        'idempotencia', 'reemplazo',
        'orden_sugerido', 'Ejecute fn_actualizar_precio_promedio_recepcion_v2/v3 DESPUÉS de 06b para capitalizar el adicional al promedio.');
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_compra_repartir_aterrizaje(bigint, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_compra_repartir_aterrizaje(bigint, numeric) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) Recepción + costos en UNA transacción
--
--    El problema que resuelve: hoy el cliente llama a la RPC de recepción y
--    después persiste los costos en un `catch { print }`. Si esa segunda parte
--    falla, la recepción queda creada y el costo se pierde.
--
--    Por qué SÍ es viable sin tocar la RPC compartida:
--      · No modifica `fn_registrar_recepcion_con_inventario` ni
--        `fn_fdi_registrar_recepcion`: sólo las llama.
--      · Reutiliza el carril idempotente que ya existe (carril fondo) en vez de
--        inventar otro.
--      · La RPC de recepción inserta una línea por elemento de `p_productos`,
--        **en el orden del array**. Eso da un mapeo determinista
--        (`row_number() over (order by id)`) entre `p_productos[k]` y la
--        k-ésima línea de `app_dat_recepcion_productos`. No se usa el heurístico
--        frágil de v2 ("primero por id_presentacion, luego por id_producto"),
--        que con dos líneas del mismo producto pega el costo en la línea
--        equivocada.
--
--    Trampa detectada y cubierta: `fn_registrar_recepcion_con_inventario` tiene
--    `EXCEPTION WHEN OTHERS` y **devuelve** un jsonb con status 'error' en vez
--    de lanzar. Su bloque de excepción es una subtransacción, así que cuando
--    devuelve 'error' no persistió nada; pero el llamador que no mire `status`
--    seguiría adelante. Aquí se mira y se ABORTA (`RAISE`), para que no queden
--    costos colgando de una recepción que no existe.
--
--    Idempotencia: se replica el patrón de `fn_fdi_registrar_recepcion`
--    (advisory lock por clave + memo en `app_dat_operacion_recepcion`). Hace
--    falta porque `app_dat_operaciones.uuid` **no es único** (sólo hay un
--    índice no-único `idx_operaciones_uuid`): reintentar con el mismo `p_uuid`
--    no protege de nada. Se usa el MISMO espacio de lock (`fdi-recepcion:`)
--    para serializar contra el carril del fondo.
--
--    En un reintento con la misma clave NO se duplica la recepción y **sí se
--    completan los costos que falten** (la inserción es idempotente). Eso es
--    justo lo que arregla el "costo perdido": reintentar la misma operación
--    termina de aplicar el costo.
--
--    Forma de `p_recepcion` (la misma que ya usa `fn_fdi_registrar_recepcion`,
--    para no inventar un contrato nuevo): p_id_tienda, p_monto_total,
--    p_moneda_factura, p_motivo, p_entregado_por, p_recibido_por,
--    p_observaciones, p_uuid, p_productos[].
--
--    Tasa (opcional, `p_tasa_usd` o `tasa_usd_aplicada` dentro de
--    `p_recepcion`): mismo sentido que en el reparto, unidades de la moneda de
--    la factura por 1 USD. Se normaliza a 1 con la moneda de la OPERACIÓN
--    (`app_dat_operacion_recepcion.moneda_factura`), no con la del jsonb. Si
--    viene, se registra en `app_dat_operacion_recepcion.tasa_cambio_aplicada` /
--    `fecha_tasa_aplicada` (UTC) **siempre**, capitalice o no; el wrapper NO
--    escribe `fdi_dat_compra_recepcion` (lo hace el reparto, por id).
--
--    Forma de `p_costos` (array; puede venir vacío):
--        [{ "id_tipo_costo": 3, "monto_usd": 12.34, "orden_linea": 1 }, ...]
--      · `orden_linea` (1-based) es opcional: si falta, se usa la posición del
--        elemento en el array. Debe caer en [1, no de líneas].
--      · `monto_promedio_anterior` NO se acepta del cliente: lo calcula el
--        servidor con la misma regla que el resto del módulo.
--
--    `p_fuentes`: si trae elementos, la recepción se financia con el fondo y se
--    delega en `fn_fdi_registrar_recepcion` (que valida saldos, cubre la
--    factura al céntimo y crea la inversión). Si viene vacío o NULL, la
--    recepción se registra por el carril normal.
--
--    NO capitaliza al promedio: eso sigue siendo de
--    `fn_actualizar_precio_promedio_recepcion_v2/v3`, que debe llamarse después.
--
--    LÍMITE HEREDADO (no se corrige aquí a propósito): en el carril normal,
--    `fn_registrar_recepcion_con_inventario` es SECURITY INVOKER y **no**
--    valida que `id_producto` / `id_ubicacion` pertenezcan a la tienda (el
--    carril del fondo sí lo valida, en `fn_fdi_registrar_recepcion`). 06b no
--    añade esa comprobación para no cambiar de tapadillo el contrato de un
--    carril que ya está en producción: endurecerlo es una decisión aparte, con
--    su propio script.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_recepcion_con_costos(
    p_recepcion       jsonb,
    p_costos          jsonb,
    p_fuentes         jsonb,
    p_idempotency_key uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tienda      bigint := NULLIF(p_recepcion ->> 'p_id_tienda', '')::bigint;
    v_costos      jsonb;
    v_sol_full    jsonb;
    v_sol_fondo   jsonb;
    v_cmp_full    jsonb;
    v_cmp_fondo   jsonb;
    v_previa      record;
    v_previa_sol  jsonb;
    v_res         jsonb;
    v_operacion   bigint;
    v_id_inversion bigint;
    v_duplicada   boolean := false;
    v_fondo       boolean := false;
    v_lineas      integer;
    v_insertadas  integer := 0;
    v_dup         integer;
    v_malo        bigint;
    v_tasa        numeric;
    v_tasa_recibida boolean := false;
    v_op_moneda   character varying;
    v_op_tasa     numeric;
    v_moneda_op   text;
    v_tasa_forzada boolean := false;
    v_link_unico  bigint;
BEGIN
    -- --- Validaciones de forma ---------------------------------------------
    IF p_idempotency_key IS NULL THEN
        RAISE EXCEPTION '06b: p_idempotency_key es obligatoria' USING ERRCODE = '22023';
    END IF;

    IF p_recepcion IS NULL OR jsonb_typeof(p_recepcion) <> 'object' THEN
        RAISE EXCEPTION '06b: p_recepcion debe ser un objeto jsonb' USING ERRCODE = '22023';
    END IF;

    IF p_costos IS NULL OR jsonb_typeof(p_costos) = 'null' THEN
        v_costos := '[]'::jsonb;
    ELSIF jsonb_typeof(p_costos) <> 'array' THEN
        RAISE EXCEPTION '06b: p_costos debe ser un array jsonb' USING ERRCODE = '22023';
    ELSE
        v_costos := p_costos;
    END IF;

    IF v_tienda IS NULL THEN
        RAISE EXCEPTION '06b: p_recepcion->>p_id_tienda es obligatorio' USING ERRCODE = '22023';
    END IF;

    -- Mismo control que la RPC del fondo, y aquí es OBLIGATORIO: esta función es
    -- SECURITY DEFINER, así que se salta las políticas RLS de las tablas que
    -- toca. Sin la comprobación, cualquier usuario autenticado podría crear
    -- recepciones en cualquier tienda.
    IF auth.uid() IS NULL
       OR NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_tienda), false) THEN
        RAISE EXCEPTION '06b: sólo gerente o superadmin de la tienda %', v_tienda USING ERRCODE = '42501';
    END IF;

    -- Sin AND de por medio: `jsonb_array_length` sobre algo que no sea array
    -- lanza, y PostgreSQL no garantiza cortocircuito en las expresiones SQL.
    IF p_fuentes IS NULL OR jsonb_typeof(p_fuentes) <> 'array' THEN
        v_fondo := false;
    ELSIF jsonb_array_length(p_fuentes) > 0 THEN
        v_fondo := true;
    ELSE
        v_fondo := false;
    END IF;

    IF NOT v_fondo AND NULLIF(p_recepcion ->> 'p_motivo', '') IS NULL THEN
        RAISE EXCEPTION '06b: p_recepcion->>p_motivo es obligatorio cuando no se financia con el fondo'
            USING ERRCODE = '22023';
    END IF;

    -- El carril fondo exige `p_uuid = auth.uid()`. Se valida aquí para dar un
    -- mensaje útil: si falta, fn_fdi_registrar_recepcion responde "Solo gerente
    -- o superadmin", que despista.
    IF v_fondo AND NULLIF(p_recepcion ->> 'p_uuid', '') IS NULL THEN
        RAISE EXCEPTION '06b: p_recepcion->>p_uuid es obligatorio en el carril fondo y debe ser el usuario autenticado'
            USING ERRCODE = '22023';
    END IF;

    -- --- Tasa USD aplicada (opcional; se PROPAGA a la operación) -----------
    -- Se acepta `p_tasa_usd` (mismo nombre que el reparto) o `tasa_usd_aplicada`.
    -- Sentido: unidades de la moneda de la factura por 1 USD. La normalización
    -- a 1 se hace DESPUÉS, con la moneda de la OPERACIÓN (D1: fuente única),
    -- no con la del jsonb de entrada.
    IF COALESCE(NULLIF(p_recepcion ->> 'p_tasa_usd', ''),
                NULLIF(p_recepcion ->> 'tasa_usd_aplicada', '')) IS NOT NULL THEN
        v_tasa := COALESCE(NULLIF(p_recepcion ->> 'p_tasa_usd', '')::numeric,
                           NULLIF(p_recepcion ->> 'tasa_usd_aplicada', '')::numeric);
        IF v_tasa IS NULL OR NOT (v_tasa > 0) OR v_tasa >= 'Infinity'::numeric THEN
            RAISE EXCEPTION '06b: p_tasa_usd debe ser un número finito > 0 (recibido: %)', v_tasa
                USING ERRCODE = '22023';
        END IF;
        v_tasa_recibida := true;
    END IF;

    -- D8: una factura que no es USD no puede entrar por este carril sin tasa.
    -- Antes la operación quedaba con `tasa_cambio_aplicada` NULL (el carril
    -- normal sólo la escribía si había inversión) y el aterrizaje posterior
    -- abortaba con 22023, dejando la recepción creada y el costo sin poder
    -- aterrizar. Se rechaza AQUÍ, antes de crear nada. La moneda se lee del
    -- payload con la misma coerción que `fn_registrar_recepcion_con_inventario`
    -- (vacío/NULL ⇒ USD).
    v_moneda_op := upper(btrim(COALESCE(NULLIF(p_recepcion ->> 'p_moneda_factura', ''), 'USD')));
    IF v_moneda_op <> 'USD' AND NOT v_tasa_recibida THEN
        RAISE EXCEPTION '06b: la factura está en % y no se recibió la tasa (p_recepcion->>p_tasa_usd, unidades de la moneda de la factura por 1 USD). Sin tasa la operación quedaría con tasa NULL y el aterrizaje no podría convertir.',
            v_moneda_op
            USING ERRCODE = '22023';
    END IF;

    v_sol_full  := jsonb_build_object('recepcion', p_recepcion, 'costos', v_costos, 'fuentes', p_fuentes);
    v_sol_fondo := jsonb_build_object('recepcion', p_recepcion, 'fuentes', p_fuentes);

    -- D4: corregir la tasa en un reintento debe ser posible. La comparación
    -- idempotente ignora las claves de tasa (`p_tasa_usd`, `tasa_usd_aplicada`,
    -- `tasa_cambio_aplicada`, `fecha_tasa_aplicada`): si cambian, la solicitud
    -- sigue siendo la misma y no se aborta con "la clave ya corresponde a otra
    -- solicitud". El resto del payload —productos, montos, costos, fuentes— se
    -- sigue comparando exacto.
    v_cmp_full := jsonb_set(
        v_sol_full, '{recepcion}',
        (v_sol_full -> 'recepcion')
          - 'p_tasa_usd' - 'tasa_usd_aplicada'
          - 'tasa_cambio_aplicada' - 'fecha_tasa_aplicada');
    v_cmp_fondo := jsonb_set(
        v_sol_fondo, '{recepcion}',
        (v_sol_fondo -> 'recepcion')
          - 'p_tasa_usd' - 'tasa_usd_aplicada'
          - 'tasa_cambio_aplicada' - 'fecha_tasa_aplicada');

    -- --- Idempotencia ------------------------------------------------------
    PERFORM pg_advisory_xact_lock(hashtextextended('fdi-recepcion:' || p_idempotency_key::text, 0));

    SELECT r.id_operacion, r.fdi_solicitud, o.id_tienda, ir.id_inversion, e.estado
      INTO v_previa
      FROM public.app_dat_operacion_recepcion r
      JOIN public.app_dat_operaciones o ON o.id = r.id_operacion
      LEFT JOIN public.fdi_dat_inversion_recepcion ir ON ir.id_operacion = r.id_operacion
      LEFT JOIN LATERAL (SELECT est.estado
                           FROM public.app_dat_estado_operacion est
                          WHERE est.id_operacion = r.id_operacion
                          ORDER BY est.id DESC
                          LIMIT 1) e ON true
     WHERE r.fdi_idempotency_key = p_idempotency_key;

    IF FOUND THEN
        IF COALESCE(v_previa.estado, 0) IN (3, 4, 5) THEN
            RAISE EXCEPTION '06b: la recepción con esa clave está cancelada o anulada; genere una clave nueva'
                USING ERRCODE = '22023';
        END IF;
        IF v_previa.id_tienda IS DISTINCT FROM v_tienda THEN
            RAISE EXCEPTION '06b: la clave ya corresponde a una recepción de otra tienda' USING ERRCODE = '22023';
        END IF;
        -- Se normaliza también la solicitud guardada para comparar sin tasas.
        v_previa_sol := CASE
            WHEN v_previa.fdi_solicitud IS NULL THEN NULL
            WHEN jsonb_typeof(v_previa.fdi_solicitud -> 'recepcion') = 'object'
                THEN jsonb_set(
                         v_previa.fdi_solicitud, '{recepcion}',
                         (v_previa.fdi_solicitud -> 'recepcion')
                           - 'p_tasa_usd' - 'tasa_usd_aplicada'
                           - 'tasa_cambio_aplicada' - 'fecha_tasa_aplicada')
            ELSE v_previa.fdi_solicitud
        END;

        -- Se aceptan las dos formas: la de este wrapper (con costos) y la que
        -- escribe fn_fdi_registrar_recepcion (sin costos).
        IF v_previa_sol IS DISTINCT FROM v_cmp_full
           AND v_previa_sol IS DISTINCT FROM v_cmp_fondo THEN
            RAISE EXCEPTION '06b: la clave ya corresponde a otra solicitud; revise la operación guardada'
                USING ERRCODE = '22023';
        END IF;

        v_operacion    := v_previa.id_operacion;
        v_id_inversion := v_previa.id_inversion;
        v_duplicada    := true;
    ELSE
        -- --- Alta de la recepción ------------------------------------------
        IF v_fondo THEN
            -- Carril fondo: valida saldos, cubre la factura al céntimo, crea la
            -- inversión y lanza si algo falla (es atómica de por sí).
            -- D4 (carril fondo): se le pasa la recepción SIN las claves de tasa.
            -- `fn_fdi_registrar_recepcion` guarda la solicitud y la compara
            -- exacta; si la tasa viajara, corregirla en un reintento abortaría
            -- con "la clave ya corresponde a otra solicitud". La tasa la
            -- registra este wrapper en la operación, después.
            v_res := public.fn_fdi_registrar_recepcion(
                p_recepcion - 'p_tasa_usd' - 'tasa_usd_aplicada'
                            - 'tasa_cambio_aplicada' - 'fecha_tasa_aplicada',
                p_fuentes, p_idempotency_key);
            v_operacion    := NULLIF(v_res ->> 'id_operacion', '')::bigint;
            v_id_inversion := NULLIF(v_res ->> 'id_inversion', '')::bigint;

            IF v_operacion IS NULL THEN
                RAISE EXCEPTION '06b: el carril fondo no devolvió id_operacion: %', v_res
                    USING ERRCODE = 'P0001';
            END IF;
        ELSE
            v_res := public.fn_registrar_recepcion_con_inventario(
                p_entregado_por             := p_recepcion ->> 'p_entregado_por',
                p_id_tienda                 := v_tienda,
                p_monto_total               := NULLIF(p_recepcion ->> 'p_monto_total', '')::numeric,
                p_motivo                    := (p_recepcion ->> 'p_motivo')::integer,
                p_observaciones             := p_recepcion ->> 'p_observaciones',
                p_productos                 := COALESCE(p_recepcion -> 'p_productos', '[]'::jsonb),
                p_recibido_por              := p_recepcion ->> 'p_recibido_por',
                p_uuid                      := auth.uid(),
                p_moneda_factura            := COALESCE(NULLIF(p_recepcion ->> 'p_moneda_factura', ''), 'USD'),
                p_id_inversion              := NULL::bigint,
                p_tasa_inversion            := NULL::numeric,
                p_confirmar_exceso_inversion := false);

            -- OJO: esta RPC devuelve el error, no lo lanza.
            IF COALESCE(v_res ->> 'status', '') <> 'success'
               OR NULLIF(v_res ->> 'id_operacion', '') IS NULL THEN
                RAISE EXCEPTION '06b: no se registró la recepción [%]: %',
                    COALESCE(v_res ->> 'sqlstate', '?'), COALESCE(v_res ->> 'message', v_res::text)
                    USING ERRCODE = '22023';
            END IF;

            v_operacion := (v_res ->> 'id_operacion')::bigint;

            UPDATE public.app_dat_operacion_recepcion
               SET fdi_idempotency_key = p_idempotency_key,
                   fdi_solicitud       = v_sol_full
             WHERE id_operacion = v_operacion;
        END IF;
    END IF;

    -- --- Propagación de la tasa: SIEMPRE a la operación, capitalice o no ---
    -- D2: el wrapper deja de escribir el vínculo (`fdi_dat_compra_recepcion`).
    -- `repartir_aterrizaje` es quien lo escribe, por su `id`. Aquí sólo se
    -- registra la tasa a nivel de operación; con varias compras en una carga,
    -- un UPDATE por `id_operacion` sobre el vínculo pisaría vínculos ajenos.
    -- D3: se registra aunque el origen de pago del vínculo sea fondo o
    -- wallet_proveedor (no capitalice); quién capitaliza se decide después.
    -- D5: `fecha_tasa_aplicada` es timestamp WITHOUT time zone; now() es
    -- timestamptz y dependería del TimeZone de la sesión. Se fija UTC.
    -- D8: ya no hay rama "sólo si vino la tasa". Si la factura es USD la tasa
    -- es 1 por definición y se escribe igual: la auditoría no admite un NULL
    -- que signifique "nadie lo registró". Si no es USD, la tasa vino
    -- (validado arriba) o la operación ya la tenía de un intento anterior.
    SELECT o.moneda_factura, o.tasa_cambio_aplicada
      INTO v_op_moneda, v_op_tasa
      FROM public.app_dat_operacion_recepcion o
     WHERE o.id_operacion = v_operacion;

    IF NOT FOUND THEN
        RAISE EXCEPTION '06b: la recepción % no tiene fila en app_dat_operacion_recepcion; no se puede registrar la tasa.', v_operacion
            USING ERRCODE = 'P0002';
    END IF;

    v_moneda_op := upper(btrim(COALESCE(v_op_moneda, '')));
    IF v_moneda_op = 'USD' THEN
        IF v_tasa IS NOT NULL AND v_tasa <> 1 THEN
            v_tasa_forzada := true;
        END IF;
        v_tasa := 1;
    ELSIF v_tasa IS NULL THEN
        -- No vino en el payload: se conserva la que la operación ya tenía (un
        -- reintento de una recepción registrada). Si tampoco hay, es un error:
        -- no se inventa una conversión.
        v_tasa := v_op_tasa;
        IF v_tasa IS NULL THEN
            RAISE EXCEPTION '06b: la operación % está en % y no tiene tasa registrada; pase p_recepcion->>p_tasa_usd.', v_operacion, v_moneda_op
                USING ERRCODE = '22023';
        END IF;
    END IF;

    -- D12: la fecha se re-sella sólo si la tasa cambia. Un reintento con la
    -- misma tasa conserva la fecha del primer registro; una corrección la
    -- actualiza, que es lo que la auditoría debe poder leer.
    UPDATE public.app_dat_operacion_recepcion
       SET tasa_cambio_aplicada = v_tasa,
           fecha_tasa_aplicada  = CASE
               WHEN tasa_cambio_aplicada IS DISTINCT FROM v_tasa
                   THEN now() AT TIME ZONE 'UTC'
               ELSE COALESCE(fecha_tasa_aplicada, now() AT TIME ZONE 'UTC')
           END
     WHERE id_operacion = v_operacion;

    -- --- Validación de los costos ------------------------------------------
    IF jsonb_array_length(v_costos) > 0 THEN
        -- Tipo obligatorio y existente.
        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(v_costos) e
             WHERE NULLIF(e ->> 'id_tipo_costo', '') IS NULL
        ) THEN
            RAISE EXCEPTION '06b: cada costo necesita id_tipo_costo' USING ERRCODE = '22023';
        END IF;

        SELECT (e ->> 'id_tipo_costo')::bigint
          INTO v_malo
          FROM jsonb_array_elements(v_costos) e
         WHERE NOT EXISTS (SELECT 1 FROM public.app_cont_tipo_costo t
                            WHERE t.id = (e ->> 'id_tipo_costo')::bigint)
         LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION '06b: id_tipo_costo % no existe en app_cont_tipo_costo', v_malo
                USING ERRCODE = 'P0002';
        END IF;

        -- Monto: obligatorio, finito y no negativo.
        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(v_costos) e
             WHERE NULLIF(e ->> 'monto_usd', '') IS NULL
        ) THEN
            RAISE EXCEPTION '06b: cada costo necesita monto_usd' USING ERRCODE = '22023';
        END IF;

        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(v_costos) e
             WHERE (e ->> 'monto_usd')::numeric < 0
                OR (e ->> 'monto_usd')::numeric >= 'Infinity'::numeric
        ) THEN
            RAISE EXCEPTION '06b: monto_usd debe ser finito y >= 0 (un abono no es un costo de la recepción)'
                USING ERRCODE = '22023';
        END IF;

        -- Líneas disponibles y orden en rango.
        SELECT count(*) INTO v_lineas
          FROM public.app_dat_recepcion_productos rp
         WHERE rp.id_operacion = v_operacion;

        IF v_lineas = 0 THEN
            RAISE EXCEPTION '06b: la recepción % no tiene líneas; no hay dónde poner los costos', v_operacion
                USING ERRCODE = 'P0002';
        END IF;

        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(v_costos) WITH ORDINALITY AS x(e, o)
             WHERE COALESCE(NULLIF(e ->> 'orden_linea', '')::integer, o::integer) NOT BETWEEN 1 AND v_lineas
        ) THEN
            RAISE EXCEPTION '06b: orden_linea fuera de rango (la recepción % tiene % líneas)', v_operacion, v_lineas
                USING ERRCODE = '22023';
        END IF;

        -- Sin pares (línea, tipo) repetidos en la carga.
        SELECT count(*) INTO v_dup
          FROM (
                SELECT y.t, y.o
                  FROM (
                        SELECT (e ->> 'id_tipo_costo')::bigint AS t,
                               COALESCE(NULLIF(e ->> 'orden_linea', '')::integer, o::integer) AS o
                          FROM jsonb_array_elements(v_costos) WITH ORDINALITY AS x(e, o)
                       ) y
                 GROUP BY y.t, y.o
                HAVING count(*) > 1
               ) z;
        IF v_dup > 0 THEN
            RAISE EXCEPTION '06b: hay % par(es) (línea, tipo de costo) repetido(s) en p_costos', v_dup
                USING ERRCODE = '22023';
        END IF;

        -- --- Persistencia (idempotente: no duplica) ------------------------
        -- D10: si la operación ya tiene exactamente un vínculo, el costo nace
        -- atribuido; con 0 o con 2+ se deja NULL (no se adivina a cuál
        -- pertenece). El reparto del aterrizaje reemplaza estas filas del tipo
        -- Importadora por las suyas, ya atribuidas.
        SELECT min(r.id) INTO v_link_unico
          FROM public.fdi_dat_compra_recepcion r
         WHERE r.id_operacion = v_operacion
        HAVING count(*) = 1;

        WITH rl AS (
            SELECT rp.id,
                   row_number() OVER (ORDER BY rp.id) AS orden
              FROM public.app_dat_recepcion_productos rp
             WHERE rp.id_operacion = v_operacion
        ),
        pedido AS (
            SELECT (e ->> 'id_tipo_costo')::bigint AS id_tipo_costo,
                   (e ->> 'monto_usd')::numeric    AS monto_usd,
                   COALESCE(NULLIF(e ->> 'orden_linea', '')::integer, o::integer) AS orden
              FROM jsonb_array_elements(v_costos) WITH ORDINALITY AS x(e, o)
        )
        INSERT INTO public.app_dat_recepcion_producto_costo
            (id_recepcion_producto, id_tipo_costo, monto_usd, monto_promedio_anterior,
             id_compra_recepcion)
        SELECT rl.id,
               pd.id_tipo_costo,
               pd.monto_usd,
               COALESCE(
                   (SELECT pc.monto_promedio_usd
                      FROM public.app_dat_producto_costo pc
                     WHERE pc.id_producto = rp.id_producto
                       AND pc.id_tipo_costo = pd.id_tipo_costo),
                   0),
               v_link_unico
          FROM pedido pd
          JOIN rl ON rl.orden = pd.orden
          JOIN public.app_dat_recepcion_productos rp ON rp.id = rl.id
         WHERE NOT EXISTS (
               SELECT 1 FROM public.app_dat_recepcion_producto_costo c
                WHERE c.id_recepcion_producto = rl.id
                  AND c.id_tipo_costo = pd.id_tipo_costo);

        GET DIAGNOSTICS v_insertadas = ROW_COUNT;
    END IF;

    RETURN jsonb_build_object(
        'status', 'success',
        'id_operacion', v_operacion,
        'id_inversion', v_id_inversion,
        'financiada_fondo', v_fondo,
        'duplicada', v_duplicada,
        'costos_insertados', v_insertadas,
        'costos_solicitados', jsonb_array_length(v_costos),
        'tasa_recibida', v_tasa_recibida,
        'tasa_usd_aplicada', v_tasa,
        'moneda_operacion', v_moneda_op,
        'tasa_forzada_usd', v_tasa_forzada,
        'tasa_registrada_en_operacion', true,
        'id_compra_recepcion', v_link_unico,
        'orden_sugerido', 'Ejecute fn_actualizar_precio_promedio_recepcion_v2/v3 después, para capitalizar los costos al promedio.');
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_recepcion_con_costos(jsonb, jsonb, jsonb, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_recepcion_con_costos(jsonb, jsonb, jsonb, uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) Verificación del script
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v integer;
    v_id_link bigint;
    v_res jsonb;
BEGIN
    -- 4.1) Las 3 funciones existen con su firma exacta.
    IF to_regprocedure('public.fn_fdi_compra_recepcion_bases(bigint)') IS NULL THEN
        RAISE EXCEPTION '06b: no se creó fn_fdi_compra_recepcion_bases(bigint)';
    END IF;
    IF to_regprocedure('public.fn_fdi_compra_repartir_aterrizaje(bigint,numeric)') IS NULL THEN
        RAISE EXCEPTION '06b: no se creó fn_fdi_compra_repartir_aterrizaje(bigint,numeric)';
    END IF;
    IF to_regprocedure('public.fn_fdi_recepcion_con_costos(jsonb,jsonb,jsonb,uuid)') IS NULL THEN
        RAISE EXCEPTION '06b: no se creó fn_fdi_recepcion_con_costos(jsonb,jsonb,jsonb,uuid)';
    END IF;

    -- 4.2) La columna de la tasa efectiva existe, con el tipo exacto y NULL-able.
    SELECT count(*) INTO v
      FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'fdi_dat_compra_recepcion'
       AND column_name = 'tasa_usd_aplicada'
       AND data_type = 'numeric'
       AND numeric_precision = 18
       AND numeric_scale = 10
       AND is_nullable = 'YES';
    IF v <> 1 THEN
        RAISE EXCEPTION '06b: fdi_dat_compra_recepcion.tasa_usd_aplicada no quedó numeric(18,10) NULL';
    END IF;

    -- 4.2b) D10: la atribución del costo a su vínculo existe, NULL-able, con FK
    --       al vínculo y con índice. Sin ella el reparto vuelve a borrar los
    --       costos de otra compra de la misma carga.
    SELECT count(*) INTO v
      FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'app_dat_recepcion_producto_costo'
       AND column_name = 'id_compra_recepcion'
       AND data_type = 'bigint'
       AND is_nullable = 'YES';
    IF v <> 1 THEN
        RAISE EXCEPTION '06b: app_dat_recepcion_producto_costo.id_compra_recepcion no quedó bigint NULL';
    END IF;

    SELECT count(*) INTO v
      FROM pg_constraint c
      JOIN pg_class t ON t.oid = c.conrelid
      JOIN pg_class f ON f.oid = c.confrelid
      JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY (c.conkey)
     WHERE c.contype = 'f'
       AND t.relname = 'app_dat_recepcion_producto_costo'
       AND f.relname = 'fdi_dat_compra_recepcion'
       AND a.attname = 'id_compra_recepcion';
    IF v <> 1 THEN
        RAISE EXCEPTION '06b: falta la FK app_dat_recepcion_producto_costo.id_compra_recepcion → fdi_dat_compra_recepcion';
    END IF;

    SELECT count(*) INTO v
      FROM pg_indexes
     WHERE schemaname = 'public'
       AND tablename = 'app_dat_recepcion_producto_costo'
       AND indexname = 'idx_recepcion_producto_costo_vinculo';
    IF v <> 1 THEN
        RAISE EXCEPTION '06b: falta el índice idx_recepcion_producto_costo_vinculo';
    END IF;

    -- 4.3) SECURITY DEFINER y valor de retorno jsonb donde toca.
    SELECT count(*) INTO v
      FROM pg_proc p
     WHERE p.oid IN (to_regprocedure('public.fn_fdi_compra_repartir_aterrizaje(bigint,numeric)'),
                     to_regprocedure('public.fn_fdi_recepcion_con_costos(jsonb,jsonb,jsonb,uuid)'))
       AND p.prosecdef
       AND pg_get_function_result(p.oid) = 'jsonb';
    IF v <> 2 THEN
        RAISE EXCEPTION '06b: se esperaban 2 funciones jsonb SECURITY DEFINER, hay %', v;
    END IF;

    -- 4.4) El DEFAULT de p_tasa_usd es NULL (D1: sin tasa, se lee la operación).
    SELECT count(*) INTO v
      FROM pg_proc p
     WHERE p.oid = to_regprocedure('public.fn_fdi_compra_repartir_aterrizaje(bigint,numeric)')
       AND p.pronargdefaults = 1
       AND pg_get_expr(p.proargdefaults, 0) = 'NULL::numeric';
    IF v <> 1 THEN
        RAISE EXCEPTION '06b: p_tasa_usd no quedó con DEFAULT NULL';
    END IF;

    -- 4.4b) Las dos columnas de tasa de la operación siguen ahí: la función
    --       las lee y las escribe; sin ellas fallaría en ejecución (D6).
    SELECT count(*) INTO v FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'app_dat_operacion_recepcion'
       AND column_name IN ('tasa_cambio_aplicada','fecha_tasa_aplicada');
    IF v <> 2 THEN
        RAISE EXCEPTION '06b: app_dat_operacion_recepcion perdió las columnas de tasa (% de 2)', v;
    END IF;

    -- 4.5) La base del reparto es consultable y no rompe con un vínculo real.
    IF EXISTS (SELECT 1 FROM public.fdi_dat_compra_recepcion) THEN
        SELECT min(r.id) INTO v_id_link FROM public.fdi_dat_compra_recepcion r;

        SELECT count(*) INTO v
          FROM public.fn_fdi_compra_recepcion_bases(v_id_link) b;
        IF v = 0 THEN
            RAISE NOTICE '06b: el vínculo % no tiene líneas de recepción visibles; no se prueba el reparto.', v_id_link;
        END IF;
    END IF;

    -- 4.6) Prueba de humo con ROLLBACK: se ejecuta el reparto de verdad y se
    --      deshace con una subtransacción. Así se comprueba que compila, corre
    --      y cuadra, sin dejar ni una fila. Sólo se lanza si hay un vínculo
    --      cuyo reparto tenga sentido (cargo > 0 y base total > 0): sin eso,
    --      la función aborta con razón y no es un defecto del script.
    SELECT min(r.id) INTO v_id_link
      FROM public.fdi_dat_compra_recepcion r
      JOIN public.app_dat_operacion_recepcion o ON o.id_operacion = r.id_operacion
     WHERE r.origen_pago IN ('wallet_importadora', 'externo')
       AND r.monto_importadora > 0
       -- D1: la tasa se resuelve por la operación. Sólo hay reparto posible
       -- si la operación es USD (se normaliza a 1) o ya tiene tasa > 0.
       AND (upper(btrim(COALESCE(o.moneda_factura, ''))) = 'USD'
            OR o.tasa_cambio_aplicada > 0)
       AND (SELECT COALESCE(sum(b.base), 0)
              FROM public.fn_fdi_compra_recepcion_bases(r.id) b) > 0;

    IF v_id_link IS NOT NULL THEN
        BEGIN
            -- Sin tasa: el DEFAULT NULL debe leerla de la operación.
            v_res := public.fn_fdi_compra_repartir_aterrizaje(v_id_link);
            -- Se fuerza el rollback de la subtransacción: la prueba no persiste.
            RAISE EXCEPTION 'PROBE_ROLLBACK_06B';
        EXCEPTION
            WHEN raise_exception THEN
                IF SQLERRM <> 'PROBE_ROLLBACK_06B' THEN
                    RAISE;
                END IF;
        END;

        IF COALESCE(v_res ->> 'status', '') NOT IN ('ok', 'sin_cargo') THEN
            RAISE EXCEPTION '06b: la prueba de humo devolvió status %', COALESCE(v_res ->> 'status', 'NULL');
        END IF;

        -- La tasa aplicada viaja en la respuesta del reparto.
        IF v_res ->> 'tasa_usd_aplicada' IS NULL THEN
            RAISE EXCEPTION '06b: el reparto no devolvió tasa_usd_aplicada';
        END IF;
    ELSE
        RAISE NOTICE '06b: no hay vínculos con cargo > 0 y base repartible; se omite la prueba de humo del reparto.';
    END IF;

    -- 4.7) Huellas del cuerpo normalizado (mismo criterio que la sincronía
    --      archivo↔base): se emiten para contrastarlas con las de la cabecera.
    RAISE NOTICE '06b huellas md5 (cuerpo normalizado): bases=% repartir=% recepcion_con_costos=%',
        md5(btrim(regexp_replace(split_part(pg_get_functiondef(to_regprocedure('public.fn_fdi_compra_recepcion_bases(bigint)')), '$function$', 2), '\s+', ' ', 'g'))),
        md5(btrim(regexp_replace(split_part(pg_get_functiondef(to_regprocedure('public.fn_fdi_compra_repartir_aterrizaje(bigint,numeric)')), '$function$', 2), '\s+', ' ', 'g'))),
        md5(btrim(regexp_replace(split_part(pg_get_functiondef(to_regprocedure('public.fn_fdi_recepcion_con_costos(jsonb,jsonb,jsonb,uuid)')), '$function$', 2), '\s+', ' ', 'g')));

    RAISE NOTICE '06b aplicado: bases + reparto de importadora + recepción con costos transaccional (tasa_usd_aplicada e id_compra_recepcion incluidas).';
END;
$$;

COMMIT;