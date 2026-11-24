# Plan de promoción newa → main sin romper a las tiendas en operación

Creado el 2026-11-20. Complementa `tasks/plan_sync_newa_main.md` (qué falta llevar) y `docs/plan-multimoneda/comparacion_funciones_newa_main.md` (qué difiere). Este documento fija **cómo y en qué orden** se aplica en main para que un cliente que no ha actualizado siga funcionando.

> Defectos encontrados probando en newa (y si existen en main): `tasks/hallazgos_pruebas_newa.md`. Es puerta de la fase 1: ninguna fila «pendiente» al aplicar.

## 1. Propuesta evaluada: «función cambiada = nombre nuevo»

**Es correcta para los cuerpos de función** y encaja con la convención que el repositorio ya usa (`_v3`/`_v4` y caer a la anterior solo si PostgREST dice que la función no existe). Pero **no basta por sí sola**: lo que más puede romper a un cliente viejo no son los cuerpos, son permisos, políticas y triggers, y eso no se renombra.

| Cambio de M01 | ¿Se resuelve con nombre nuevo? | Qué hacer |
|---|---|---|
| Cuerpo de una RPC que un cliente viejo llama | Sí | Nombre nuevo (sección 3) |
| `REVOKE UPDATE ON app_dat_trabajadores / app_dat_vendedor FROM authenticated` (R0b) | No | Fase contrato. Hay uso real (ver sección 2) |
| `REVOKE EXECUTE` de `fn_asignar_vendedor`, `fn_desasignar_*`, `fn_asignar_supervisor`, `fn_asignar_jefe_cocina`, `create_gerente_from_email`, `crear_tpv_completo`, `crear_estructura_tienda` (R0d) | No | Fase contrato |
| `REVOKE ... FROM authenticated` de `fn_registrar_venta_offline`, `_v2`, `_v3` (R0i) y de `fn_editar_trabajador_basico`, `fn_agregar_rol_trabajador`, `fn_actualizar_datos_rol_trabajador`, `fn_eliminar_rol_trabajador` (R0f) | No | Fase contrato |
| Políticas nuevas de `app_dat_operaciones`, `app_dat_tienda`, `app_dat_dueno`, `app_dat_recursos_humanos` (R0a, R0b, R0e) | No | Fase contrato, tras comprobar roles (sección 2) |
| Triggers en `app_dat_operacion_venta`, `app_dat_pago_venta`, `app_dat_extraccion_productos` (R12, R15, R16, R17) | No | Solo afectan filas `producto-v1` o con el flag de tienda; mantener el flag apagado hasta que la flota de esa tienda esté actualizada |
| `fn_fdi_crear_liquidacion` 10 → 11 parámetros | Sí (la 10 se queda) | Dejar ambas en expansión; retirar la 10 en contrato |
| Sobrecargas viejas de contabilización (con `anon`) | No | Contrato: Admin viejo aún las llama sin `p_id_tienda` |
| `fn_desvincular_usuario_trabajador` → función M01 | Sí | Mantener la vieja hasta el contrato |

Riesgo extra: **flota mezclada en la misma tienda** (una tablet nueva y otra vieja). Un cliente viejo que intenta cobrar o editar una venta `producto-v1` creada por uno nuevo choca con los triggers R15/R17. La palanca es el flag por tienda `permitir_moneda_por_producto` (apagado por defecto; en main la columna ni existe): se enciende tienda por tienda **cuando todos sus dispositivos estén actualizados**.

## 2. Evidencia de producción (main, ventana 19–20/11, solo lectura)

- **Guardas de lectura nuevas** (`fn_config_tienda_exigir_lectura`: licencia, consolidación, `sync_bundle`): los 18 usuarios que las llamaron en 24 h tienen al menos un rol que la guarda admite (vendedor, gerente, supervisor, etc.). No cubre `recursos_humanos` ni usuarios solo-trabajador: hay que contarlos (puerta G2).
- **Escrituras directas por REST de clientes viejos** (POST/PATCH/DELETE sobre las tablas que M01 toca):

  | Tabla | Método | Llamadas | Usuarios | Efecto con M01 |
  |---|---|---|---|---|
  | `app_dat_caja_turno` | PATCH | 12 | 8 | M01 no cambia sus políticas. Sin efecto |
  | `app_dat_operaciones` | PATCH | 8 | 1 (gerente) | R0e permite UPDATE solo a quien escribe en la tienda: el gerente pasa; **un vendedor haciendo lo mismo no actualizaría nada y sin error** |
  | `app_dat_operacion_venta` | PATCH | 4 | 2 (vendedores) | Solo se bloquea si la venta es `producto-v1` o la tienda tiene el flag |
  | `app_dat_pago_venta` | POST/PATCH | 5 | 5 (vendedores) | Igual |
  | `app_dat_trabajadores` | PATCH | 1 | 1 (gerente y supervisor) | **R0b lo rompería**: `REVOKE UPDATE FROM authenticated` |

  Conclusión: R0b (y R0d/R0f/R0i) **no se pueden aplicar en la primera pasada**. El PATCH silencioso bajo RLS (0 filas, sin error) es el modo de fallo más difícil de detectar.
- Los clientes viejos siguen llamando los nombres antiguos de RPC en producción; el parque no se ha movido.
- Main ya tiene el mecanismo para terminar la transición: `app_versiones.version_minima` / `actualizacion_obligatoria` → `fn_check_update` devuelve `obligatoria` y `fn_version_menor` compara. Es la palanca para fijar «fecha de contrato».

## 3. Clasificación de las 21 funciones «newa más nueva»

Regla: **mismo nombre solo si, para toda carga que un cliente publicado envía, la respuesta es idéntica o un superconjunto y no aparece un rechazo nuevo para un usuario legítimo.** Si no, nombre nuevo.

**Nombre nuevo (14).** Sufijo único `_m01` para no chocar con `_vN` existentes (p. ej. `fn_cerrar_turno_offline_m01`). El cliente nuevo llama `_m01` y cae a la antigua solo si la función no existe.

| Función | Motivo |
|---|---|
| `fn_apertura_turno_offline`, `_monedas`, `_usd` | Actor `auth.uid()`, idempotencia M01, fecha alineada (R33). Incluir `sql_updates/fix_apertura_turno_offline_id_turno.sql`: main tiene el mismo defecto (devuelve el id de la operación como `id_turno`); hoy no se nota porque ningún cliente publicado llama `_monedas` |
| `fn_cerrar_turno_offline`, `_monedas`, `_usd` | Idempotencia M01 y la fecha de cierre cambia de valor guardado |
| `fn_cambiar_estado_comanda_item_offline` | Rechaza con 42501 si la clave no coincide; sin `auth.uid()` rechaza |
| `fn_registrar_cambio_estado_offline` | Idempotencia M01 y lock por `client_uuid` |
| `fn_registrar_egreso_offline`, `_v2` | Idempotencia M01; `_v2` valida la moneda contra `monedas` |
| `fn_registrar_pago_venta_offline` | Nueva autorización: quien cobra debe poder escribir en la tienda o ser su vendedor |
| `fn_registrar_venta_offline_v4` | Valida vendedor/TPV/trabajador y acota `p_fecha_creacion` |
| `fn_listar_ordenes` | Cambia el conjunto de filas (`v_tiendas`) y el JSON. Corregir antes `tipo_paago` en newa |
| `fn_actualizar_precio_promedio_recepcion_v2` | Cambia el cálculo y se guarda `costo_real` (no recalcula histórico) |

(Si la puerta G1 demuestra que alguna de las seis de turno devuelve idéntico para todas las cargas reales, puede bajar al grupo siguiente.)

**Mismo nombre (7), con puerta.**

| Función | Condición |
|---|---|
| `fn_registrar_cambio_estado_operacion` | Solo añade la rama `es_base` cuando no viene presentación. G1 |
| `fn_pedir_item_cuenta_offline` | Delega en `fn_pedir_item_cuenta_v2` (misma lógica). G1 |
| `fn_validar_moneda_forzada` | Solo difiere con `permitir_moneda_por_producto`, que en main no existe |
| `fn_fdi_repartir_ganancia` | Necesita antes la columna `repartir_igual` con valor por defecto |
| `fn_obtener_licencia_firmada`, `fn_moneda_consolidacion`, `sync_bundle` | Guarda de lectura nueva. G2 |

Además hay que localizar a los **llamadores internos** de cada función renombrada (`pg_proc.prosrc`): si otra función de main llama a la antigua, no se mueve sola a la nueva, y las nuevas `_m01` deben llamar a las `_m01` internas, no a las antiguas.

## 4. Fases

### Fase 0 — Preparación (sin tocar main)
1. ~~Corregir `tipo_paago` en newa (`sql_updates/fix_listar_ordenes_tipo_pago.sql`).~~ Hecho (comprobado el 20/11).
2. ~~Llevar a newa las 12 funciones donde main es más nueva (lista C del comparativo)~~ (hecho el 20/11, `sql_updates/newa_traer_12_funciones_main.sql`, mismo hash que main) y decidir los criterios de las 8 manuales (hecho: turno, mejorado, FDI; pendiente: `fn_dashboard_carnaval_proveedor`, stock detalle/saldos).
3. ~~Scripts `_m01` + espejo newa + G1~~ — ver `docs/plan-multimoneda/runbook_pase_newa_main.md` y `g1_resultado_2026-11-23.md`. H9 aplicado en newa.
4. ~~Cambiar el cliente (TPV y Admin) para llamar `_m01` primero~~ — hecho 2026-11-23 (`RpcM01` en TPV y Admin; caída solo si la función no existe).
5. ~~Regenerar los baselines `md5` de los preflight 14, 17 y 56 contra main.~~ Hecho 2026-11-23.

### Puertas obligatorias antes de aplicar nada
- **G1 — Arnés de compatibilidad.** Para cada función, repetir las cargas que envía el **cliente publicado** (revisar la etiqueta de la última versión en tienda) contra el cuerpo nuevo y contra el viejo, dentro de una transacción que termina en `ROLLBACK`. Criterio: misma respuesta, mismo efecto en filas, o diferencia justificada por escrito. Siempre se ejecuta en newa con el estado espejo de main; en main solo lectura hasta que se apruebe.
- **G2 — Cobertura de la guarda de lectura.** Consulta en main de todos los usuarios con acceso a alguna tienda que **no** cumplirían `fn_config_tienda_puede_leer` (incluye recursos humanos y solo-trabajador). Resultado vacío o aceptado por escrito.
  - **Decidido y aplicado 2026-11-23:** ampliar `puede_leer` con **RH y trabajador** de la tienda. Script `sql_updates/fn_config_tienda_puede_leer_g2.sql` aplicado en **newa**; S01 (`configuracion_tienda_rls_propuesta.sql`) ya lleva el mismo cuerpo para el pase. Simulación en main con la nueva regla: **0 pares fuera**. Puerta G2 cerrada para licencia / consolidación / `sync_bundle` (mismo nombre tras S01+G2).
- **G3 — Inventario de dependencias.** Llamadores internos de cada función renombrada, triggers y vistas que las usan.
  - **Main 2026-11-23 (solo lectura):** sin triggers/vistas que las invoquen. Llamadores en `pg_proc`:
    - `fn_apertura_turno_offline` ← `_usd`, `_monedas` (y `_monedas` → `_usd`)
    - `fn_cerrar_turno_offline` ← `_usd`, `_monedas` (y `_monedas` → `_usd`)
    - `fn_registrar_egreso_offline` ← `fn_registrar_egreso_offline_v2`, `fn_registrar_egreso_fondo_caja`
    - El resto de las 14 (comanda/estado/pago/venta_v4/listar_ordenes/precio_promedio) **sin** llamador interno en main.
  - **Newa extra / pase:** `fn_registrar_egreso_fondo_caja_v2` → `fn_registrar_egreso_offline_v2_m01` (repo 2026-11-23); `fn_actualizar_precio_promedio_recepcion_v2` ← FDI (en main Fase 1 el cálculo nuevo es `*_v2_m01`, no REPLACE del antiguo).
  - Al crear `_m01`, las cadenas `_monedas`/`_usd`/fondo/`_v2` deben apuntar a `_m01` internas, no a las antiguas.
- **G4 — Respaldo y reversa** (sección 7). Checklist operativo: `sql_updates/promocion_m01/g4_respaldo_y_reversa.md`. **Pendiente en el día del pase:** snapshot de main + volcado md5 real.

### Fase 1 — Expansión en main (solo aditiva, aplicar en horario de poca carga)
Solo crea o agrega. **Orden canónico y exclusiones:** `docs/plan-multimoneda/runbook_pase_newa_main.md` (audit regla de oro 2026-11-23).
1. Helpers aditivos (sin tocar la tabla): `sql_updates/fn_config_tienda_helpers_aditivos.sql` (G2 incluido). **No** aplicar S01 completo (`ENABLE RLS` + `REVOKE` en `app_dat_configuracion_tienda`) en esta oleada.
2. Columnas/tablas nuevas: R0i idempotencia, `costos_adicionales_producto_tablas_fase1.sql` (solo tablas; no el archivo completo), columnas v1 sin triggers `m01_*`, flag apagado, etc.
3. Reportes same-name (bugfixes C9–C13 / C11 / turno sin cierre) **en este orden:** `fix_reporte_ventas_por_turno_sin_cierre` → `fix_esperado_turno_por_moneda_ventas_offline` (**C9**) → `fix_reportes_turno_ventas_offline` (**C12**) → `reportes_turno_completadas_y_por_moneda` (**C13**) → `fix_listar_entregas_por_turno_sin_ventana_fecha` (**C11**). Luego `add_ticket_caja_a_tickets_a_imprimir` (**C2**, antes de publicar TPV).
4. Las 14 `_m01` (`promocion_m01/01…06`). **C14** solo en `fn_registrar_egreso_offline_v2_m01` (+ helper en 01). **No** aplicar `fn_egreso_validar_saldo_caja.sql` (REPLACE del nombre publicado → Fase 3).
5. Post-`_m01` aditivos: `fn_registrar_egreso_fondo_caja_v2_moneda.sql` (**C6**, llama `_v2_m01`), `fn_reporte_ventas_producto_por_moneda.sql` (**C17a**), `fn_fdi_crear_liquidacion_depositar_inversion.sql` (**C17b**: 11 params **sin** DEFAULT en `p_repartir_igual`; conserva la de 10; no usar `fondo_inversion_schema.sql`).
6. Recepción `fix_cambio_estado_operacion_mejorado_recepcion.sql`: rechazo nuevo `RECEPCION_INVENTARIO_USADO` — solo con OK explícito / Admin listo.
7. Clientes (C14 UI, C16, C17 sesión): publicar TPV+Admin con `RpcM01` tras el SQL. El egreso 3 del turno 20 de newa no se migra.
8. **No** entra: `REVOKE`/`DROP`/`ENABLE RLS` sobre tablas en uso, `DROP FUNCTION`, triggers `m01_*` (R15/R16/R17/H9), `costos_adicionales_producto.sql` completo, `newa_traer_*`, R0b/R0d/…, S01 RLS completo.
9. Preservar lo propio de main: `trg_bloquear_operaciones_maria`, WhatsApp, referidos, crons.
10. Verificación: 4xx/5xx ≈ hora anterior; cliente viejo sin `EGRESO_SIN_SALDO`; cliente nuevo con `_m01`.

### Fase 2 — Publicar los clientes
- App de ventas y Admin nuevos (llaman `_m01` con caída a la antigua). Los clientes viejos siguen en las funciones antiguas sin cambios.
- Seguimiento diario con los logs de main: llamadas por nombre `_m01` vs. antiguo y usuarios distintos de cada uno.
- Para tiendas piloto: encender el flag `permitir_moneda_por_producto` solo cuando todos sus dispositivos estén en la versión nueva.

### Fase 3 — Contrato (semanas después, por tienda o por versión mínima)
Condición de entrada: **7 días con cero llamadas** (por logs) a cada nombre antiguo, o `version_minima` forzada y cumplida. Cada paso es un script separado, reversible y con su propia puerta.
1. Triggers `m01_*` sobre ventas y activación de modo por tienda.
2. R0b (revocar UPDATE en `app_dat_trabajadores`/`app_dat_vendedor`, políticas), R0e, R0a, RH. Antes, volver a medir escrituras directas por REST con la consulta de la sección 2.
3. Revocar (no borrar) los nombres antiguos de las 14 y de R0d/R0f/R0i; un ciclo después, borrar.
4. `fn_fdi_crear_liquidacion` de 10 parámetros y sobrecargas viejas de contabilización: retirar cuando Admin viejo ya no las llame.
5. Retirar `anon` de lo que lo tenga.

## 5. Qué se descarga y qué se lee online (regla de sincronización)

- Sin tablas satélite nuevas que necesiten sync dedicado: el flag va en `app_dat_configuracion_tienda` y llega por `StoreConfigService`/`syncStoreConfig`. Los precios usan el pipeline de productos existente.
- Cache vacío con el flag encendido: el TPV debe comportarse como flag apagado (comportamiento actual de `store_config_service.dart`).
- Verificar antes de dar por lista cada fase: online, offline con cache fresco, offline con cache vacío o viejo, con cliente nuevo **y** con cliente viejo.

## 6. Qué cambia si se elige exactamente la propuesta original (todo con nombre nuevo)

- Cuesta más: hay que renombrar también en newa, rehacer las pruebas ya hechas con los nombres actuales y mantener dos cuerpos de cada función hasta el contrato.
- No cubre el punto de la sección 1 (permisos, políticas, triggers). Por eso la recomendación es **nombre nuevo para las 14 de riesgo + mismas funciones en su sitio para las 7 compatibles + contrato en fases**.
- Una sobrecarga con parámetros opcionales **no** es alternativa: con PostgREST dos sobrecargas que aceptan el mismo subconjunto de parámetros dan error de ambigüedad.

## 7. Reversa

- Antes de la fase 1: copia de seguridad de main y volcado de `pg_get_functiondef` de las ~100 funciones afectadas más grants y políticas (diferencia por `md5`).
- Fase 1 es aditiva: la reversa es `DROP` de lo nuevo; el estado anterior no se tocó.
- Fase 3: cada script guarda sus grants/políticas anteriores y trae su script inverso probado en newa.
- Criterio de parada: aumento sostenido de 4xx/5xx en las rutas de venta, turno o sincronización, o un solo caso de escritura perdida.

## 8. Pendiente de decisión del dueño

1. ¿Sufijo `_m01` para las 14, o seguir `_vN`?
2. ¿Fecha o versión mínima para la fase 3?
3. ¿Tienda piloto para el primer encendido del flag en main?
