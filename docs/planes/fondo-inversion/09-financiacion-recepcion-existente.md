# 09 — Financiación de recepción que ya existe en `multimoneda`

Solo lectura sobre `multimoneda` (HEAD `2bff5b18`). No se editó código ni `PLAN.md`. **HECHO** = verificado
con `archivo:línea`; **OPINIÓN** = juicio del revisor.

## 1. Contrato de `fn_fdi_registrar_recepcion(jsonb, jsonb, uuid)`

**HECHO.** `ventiq_admin_app/lib/sql/fondo_inversion_financiar_recepcion.sql:19-27`: `SECURITY DEFINER`,
`search_path = public, pg_temp`; `REVOKE ... FROM PUBLIC, anon` y `GRANT ... TO authenticated` (`:165-166`).
Migración aditiva que valida dependencias al iniciar (`:3-10`).

- `p_recepcion jsonb`: las claves de la RPC de recepción (`p_entregado_por`, `p_id_tienda`, `p_monto_total`,
  `p_motivo`, `p_observaciones`, `p_productos`, `p_recibido_por`, `p_uuid`, `p_moneda_factura`), reenviadas
  nombradas al final (`:136-148`); de aquí salen tienda (`:29`), total (`:30`) y moneda de factura (`:31`).
- `p_fuentes jsonb`: array `{id_cuenta, id_medio_pago, moneda, monto, tasa_a_ref}` (`:32`, `:100-107`).
- `p_idempotency_key uuid`: obligatoria (`:49`).

**Validaciones** (todas con `RAISE`, nunca devuelven JSON de error): `auth.uid()` no nulo, gerente/superadmin
de la tienda y `p_uuid = auth.uid()` (`:45-48`, 42501); clave no nula, total > 0 finito y **exactamente 2
decimales**, moneda ∈ `USD,CUP,EUR`, `p_id_inversion` ausente (`:49-53`, 22023); `p_fuentes` array no vacío
(`:68-70`) sin fuente repetida `(cuenta, medio, moneda)` (`:71-76`); `p_productos` array no vacío (`:77-80`);
ubicación y producto de la tienda, cantidad > 0, precio ≥ 0 (`:81-97`, 42501/22023); por fuente monto > 0 con
2 decimales, tasa > 0 y `tasa = 1` si la moneda es la de factura (`:103-107`); saldo suficiente con
cuenta/concepto/medio activos (`:108-120`, P0002); y `Σ round(monto × tasa, 2) = total` **exacto al centavo**
(`:121-125`).

**Orden (una sola transacción):**
1. `pg_advisory_xact_lock(hashtextextended('fdi-recepcion:'||clave, 0))` (`:54`).
2. Replay: si ya hay recepción con esa clave y coinciden `id_tienda` + `fdi_solicitud`, devuelve
   `{status: success, id_operacion, id_inversion, duplicada: true}` sin escribir (`:55-67`).
3. Validaciones anteriores, en ese orden.
4. Bucle de fuentes **ordenado por (cuenta, medio, moneda)** (`:98-99`) con `SELECT ... FOR UPDATE OF s` sobre
   `fdi_dat_saldo` (`:108-117`) y acumulación del cubierto redondeado (`:121`).
5. **Mueve el dinero**: `fn_fdi_crear_inversion(..., p_fuentes, p_idempotency_key)` (`:126-131`), que debita
   cada fuente con `_fdi_aplicar_movimiento(..., -monto, 'extraccion_inversion', id_inversion)`
   (`fondo_inversion_schema.sql:1317-1321`). Aborta si la inversión saliera `duplicada` (`:129-131`).
6. Reescribe `monto_ref = round(monto×tasa,2)` por fuente y `monto_total_ref = total` (`:133-135`).
7. **Crea la recepción** con `p_id_inversion => NULL` y `p_confirmar_exceso_inversion => false` (`:136-148`),
   exigiendo `status = 'success'` (`:149-151`).
8. `fn_fdi_vincular_recepcion(op, inv, total, moneda, 1, false)` (`:153`); guarda `fdi_idempotency_key` y
   `fdi_solicitud` (`:157-159`); renombra la inversión a `'Recepción '||id_operacion` (`:160`); devuelve
   `{..., id_inversion, financiada_fondo: true}` (`:161`).

**Escribe:** `fdi_dat_saldo` (−monto), `fdi_dat_movimiento` (`extraccion_inversion`), `fdi_dat_inversion` (nace
`pendiente`, `schema:1290`), `fdi_dat_inversion_fuente`, `fdi_hist_estado_inversion`, `app_dat_operaciones` +
`app_dat_operacion_recepcion` + `app_dat_estado_operacion` (dentro de la RPC de recepción, `patch:241-242`),
`fdi_dat_inversion_recepcion` y `fdi_idempotency_key`/`fdi_solicitud` (`:12-17`).

**Locks e idempotencia.** Clave **por formulario**, no por operación: lock de transacción por clave más `UNIQUE`
parcial (`:15-17`). El saldo se bloquea dos veces (bucle y `_fdi_aplicar_movimiento`, `schema:370-389`), que además
rechaza dejarlo negativo. `fdi_dat_inversion.idempotency_key` es `uuid NOT NULL UNIQUE` (`schema:257`), lo que
respalda el paso 5.

**Momento del dinero — HECHO.** Sale **antes** de que exista la recepción (paso 5 antes del 7). Al vincular con
`monto_ref = total` y `monto_total_ref = total`, `fn_fdi_recalcular_inversion` la deja en `completado`
(`schema:1212-1215`): la inversión nace y se cierra en el mismo acto y por eso no aparece abierta en la UI. La
recepción nace en estado 1 y **no aplica inventario**: «El inventario se aplicará al completar» (`patch:284`).

## 2. Flujo de UI real

**HECHO.** Al abrir se cargan saldos con `saldo > 0` y medio de pago no nulo (`inventory_reception_screen.dart:71-81`).
Con saldos aparece «Financiar con fondo de inversión» (`:733`); activarlo anula `_selectedInversion` y
`_fuentesFondo` (`:735-740`), así que los dos modos son excluyentes. `_claveFondo` se crea **una vez por
instancia de pantalla** y no se regenera (`:66`).

Cada saldo es una casilla que auto-rellena `min(saldo, total − cubierto)` a 2 decimales, o `0` si la moneda
difiere (`fdi_recepcion_fuentes.dart:73-80`). Se editan monto y, con moneda distinta, tasa («1 X equivale a
cuántos Y», `:109-131`). La cobertura se muestra como Cubierto/Pendiente (`:40`, `:139-144`) sumando
`equivalente = round(monto × tasa, 2)` (`fondo_inversion.dart:125-127`). Si no cubre exacto,
`FdiFuenteRecepcion.validar` (`fondo_inversion.dart:138-176`) valida en **centavos enteros**
(`Σ centavos = centavos(total)`); el error se ve en el widget (`fdi_recepcion_fuentes.dart:145-149`) y otra vez
al enviar (`screen:452-455`). No hay ajuste automático: se corrige a mano.

Al enviar se mandan `fuentesFondo` e `idempotencyKey` (`screen:524-525`) y el servicio cambia de RPC:
`fn_fdi_registrar_recepcion` con `{p_recepcion, p_fuentes, p_idempotency_key}` y `p_monto_total` como **cadena**
`toStringAsFixed(2)` (`inventory_service.dart:1366-1390`), rechazando en Dart fuentes sin clave o con inversión
previa (`:1353-1355`).

**Reintento:** con la misma clave y solicitud la RPC devuelve `duplicada: true` y la UI lo trata como éxito
(`screen:566-581`). Si el primero ya se grabó y el usuario **editó** algo, responde «La clave ya corresponde a
otra recepción» (`sql:62-64`). El camino `requires_confirmation` por exceso (`screen:531-564`) no aplica: exige
`inv != null`. **Fricción, no dinero:** `onChanged` solo se emite al marcar casilla o editar monto/tasa
(`fdi_recepcion_fuentes.dart:86`, `:106`, `:129`); si cambia el total, la copia del padre queda obsoleta hasta
tocar una fuente, y `validar` lo bloquea antes de enviar.

## 3. Comparación con el plan (fases 4 y 5)

El plan ordena `compra → reserva (sin mover) → pago (mueve) → recepción` (`PLAN.md:145-155`) y afirma «La
recepción no mueve dinero» (`PLAN.md:155`). Esta RPC hace `recepción → pago inmediato`.

| Pieza del plan | Estado real | Qué falta |
|---|---|---|
| F4 · reserva sin mover, `fn_fdi_disponible` | **no existe**: se debita en el acto (`sql:126`) | reserva, disponible, liberar, anular |
| F4 · liquidación multimoneda bloqueante | **sí, versión simple** (`sql:98-125`) | faltante **por moneda** (`PLAN:472-473`), cordura ±20% (`PLAN:391`), `modo_liquidacion` |
| F4 · pago atómico que consume reserva | **sí, sin reserva y como `extraccion_inversion`** (`schema:1317-1321`) | `id_compra` y `tasa` en el ledger (`PLAN:477`) |
| F4 · liberar / anular con contramovimiento | no existe (riesgo 3) | contramovimiento |
| F5 · recepción atómica con el pago | **sí**: cualquier fallo revierte todo (`sql:19-163`) | quitar `EXCEPTION WHEN OTHERS` (`patch:287-303`; `PLAN:523-524`) |
| F5 · idempotencia de la operación | **sí, más fuerte que el plan**: clave + advisory lock + `UNIQUE` parcial + huella (`sql:54-67`) | extenderla a la ruta sin fondo |
| F5 · vínculo por cantidades, multi-factura, pendiente | **no existe**: vincula por **monto** (`schema:322-333`) | compra, líneas, `UNIQUE(id_operacion, id_compra)` |
| F5 · importadora, `origen_pago`, `pct`, factura | **no existe**; proveedor se registra **fuera** de la transacción (`inventory_service.dart:1396`) | todo |
| F5 · un solo camino de stock con lote | sigue el camino existente (aplica al completar) | deprecar el doble camino (`PLAN:527-529`) |

**¿Conviven sin duplicar dinero?** **HECHO:** sí, estructuralmente. La ruta financiada crea su inversión y
prohíbe `p_id_inversion` (`sql:51`); la clásica exige inversión previa; y `fdi_dat_inversion_recepcion.id_operacion`
es `UNIQUE` (`schema:325`), así que una operación no admite dos vínculos. **OPINIÓN:** correcto *hoy* porque el
modo fondo desactiva el desplegable de inversiones (`screen:735-740`); el hueco aparece al cancelar (riesgo 3).

**Distinguir "suelta" de "contra compra".** **HECHO:** las únicas marcas son `fdi_idempotency_key IS NOT NULL`,
la fila en `fdi_dat_inversion_recepcion` y el identificador `'Recepción <id_operacion>'` (`sql:160`).
**OPINIÓN:** insuficiente; nada dice «no viene de una compra», porque `id_compra` no existe.

**Soportar `id_compra` sin romper el contrato.** Añadir `p_id_compra bigint DEFAULT NULL` como **cuarto parámetro
con default** (regla del plan: obligatoriedad por DEFAULT, `PLAN:139`), validar `p_recepcion->>'p_id_compra'` ausente
como hoy se hace con `p_id_inversion` (`sql:51`) y escribir el vínculo por cantidades en tablas nuevas. No tocar la
firma de tres argumentos ni el bloque de idempotencia.

## 4. Riesgos concretos

1. **Doble financiamiento de la misma factura física.** La RPC no conoce factura ni compra (`sql:19-23`); con dos
   claves (dos pantallas, o cerrar y reabrir el formulario) la misma factura se financia dos veces y el dinero sale
   dos veces. Nada en el esquema lo impide.
2. **Recepción financiada sin compra: es el caso normal, no la excepción.** Se debita antes de que exista
   documento de compra y el costo no queda atado a proveedor ni factura; el plan asume que todo desembolso nace de
   una compra (`PLAN:145-147`).
3. **Cancelación: el dinero no vuelve y la inversión queda huérfana y re-vinculable.** El trigger desvincula en
   estados 3/4/5 (`patch:329-351`) y `fn_fdi_desvincular_recepcion` solo borra el vínculo y recalcula
   (`schema:1454-1471`): sin contramovimiento, coherente con `AGENTS.md` §«Recepciones financiadas». La inversión
   vuelve a `pendiente` con `monto_total_ref = total` y el dinero ya fuera, así que **puede enlazarse a otra
   recepción** desde el desplegable y el mismo desembolso acaba justificando dos. La clave sigue en la fila
   cancelada: reintentar devuelve `duplicada: true` sobre una operación cancelada (`sql:55-67`) y la UI lo muestra
   como éxito (`screen:566-581`).
4. **Redondeo en dos motores.** Servidor: `Σ round(monto×tasa,2) = total` sobre `numeric` (`sql:121-125`). Cliente:
   centavos enteros sobre `double` (`fondo_inversion.dart:125-127`, `:157-176`). `round()` de Dart y de `numeric`
   pueden discrepar en el tercer decimal (`x.xx5`); el efecto es un rechazo que la pantalla no explica, no un
   descuadre.
5. **Tasa sin cordura.** `tasa_a_ref` viene del cliente y solo se valida `> 0` (`sql:103-105`); resolverla en
   servidor y la banda ±20% son fase 2 (`PLAN:391-395`). Un cero de más cambia cuánto se debita de la moneda nativa
   aunque la equivalencia cuadre.
6. **Ledger del módulo legado.** Sale como `extraccion_inversion` (`schema:1317-1321`), no `pago_compra`, y sin
   `id_compra` ni `tasa`; la conciliación de fase 8 verá estas recepciones como inversiones, no como pagos.
7. **Crea inversiones nuevas contra la decisión de congelar `fdi_dat_inversion`.** El plan la declara legado
   congelado, sin altas y con el alta retirada en fase 8 (`PLAN:119-120`); esta RPC inserta una por recepción
   financiada (`schema:1285-1291`). Colisión de arquitectura, no bug.
8. **`EXCEPTION WHEN OTHERS` en la RPC interna** (`patch:287-303`) convierte errores en JSON: aquí el `RAISE`
   externo (`sql:149-151`) salva la atomicidad, pero se pierde el mensaje real (`PLAN:523-524` ya pide quitarlo).
9. **Operativos.** Esta RPC ordena sus fuentes (`sql:99`) y el resto del módulo no: puede interbloquear con una
   transferencia o liquidación concurrente (**OPINIÓN:** improbable con un gerente por tienda, pero no impedido). Y
   proveedor / costos adicionales se escriben **después**, fuera de la transacción (`inventory_service.dart:1396`,
   `:1409-1416`, con `catch` que solo imprime): si fallan, la recepción queda sin proveedor o sin costos, en silencio.

## 5. Cinco preguntas que el plan debe resolver

1. ¿La financiación directa es **ruta oficial** («pago contra entrega, sin compra previa») o parche temporal? De eso
   depende que fase 8 pueda retirar el alta de `fdi_dat_inversion`.
2. Si es oficial, ¿qué documento sustituye a la compra: una compra implícita de una línea por recepción, o se admite
   `id_compra NULL` y la conciliación lo tolera?
3. ¿Cómo se impide financiar dos veces la misma factura física sin `numero_factura` ni `id_compra`? (¿proveedor +
   número + fecha? ¿huella de líneas?)
4. Al cancelar una recepción financiada: ¿contramovimiento que devuelve el saldo, inversión bloqueada para que no se
   re-vincule, o pérdida aceptada con marca de revisión?
5. ¿La inversión que crea esta RPC se migra a `fdi_dat_compra` cuando exista, o queda como histórico congelado con su
   `extraccion_inversion`? Y si se migra, ¿qué pasa con lo ya financiado en `newa`?