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
3. Generar los scripts de promoción con los **nombres nuevos** y probarlos en newa con la regla «newa = main después de la expansión»: en newa, los nombres antiguos de las 14 recuperan el cuerpo de main y los `_m01` llevan el cuerpo nuevo. Así newa ejercita exactamente el estado en que quedará main.
4. Cambiar el cliente (TPV y Admin) para llamar `_m01` primero y caer a la antigua solo si la función no existe (convención de `SPEC-ventiq-app.md`). Un error distinto no se disfraza de «ausente».
5. Regenerar los baselines `md5` de los preflight 14, 17 y 56 contra main.

### Puertas obligatorias antes de aplicar nada
- **G1 — Arnés de compatibilidad.** Para cada función, repetir las cargas que envía el **cliente publicado** (revisar la etiqueta de la última versión en tienda) contra el cuerpo nuevo y contra el viejo, dentro de una transacción que termina en `ROLLBACK`. Criterio: misma respuesta, mismo efecto en filas, o diferencia justificada por escrito. Siempre se ejecuta en newa con el estado espejo de main; en main solo lectura hasta que se apruebe.
- **G2 — Cobertura de la guarda de lectura.** Consulta en main de todos los usuarios con acceso a alguna tienda que **no** cumplirían `fn_config_tienda_puede_leer` (incluye recursos humanos y solo-trabajador). Resultado vacío o aceptado por escrito.
- **G3 — Inventario de dependencias.** Llamadores internos de cada función renombrada, triggers y vistas que las usan.
- **G4 — Respaldo y reversa** (sección 7).

### Fase 1 — Expansión en main (solo aditiva, aplicar en horario de poca carga)
Solo crea o agrega. No altera, revoca ni borra nada existente.
1. Columnas e índices nuevos (`permitir_moneda_por_producto` apagado, `repartir_igual`, etc.), tablas nuevas con RLS y políticas en el mismo script.
2. Funciones nuevas: las 90 que solo están en newa y las 14 `_m01`.
3. Los 7 cuerpos con el mismo nombre (tras G1/G2) y los scripts ya verificados: `add_ticket_caja_a_tickets_a_imprimir.sql` (solo datos: añade `caja` a `tickets_a_imprimir` de las tiendas con `cliente`; **debe ir antes de publicar el TPV** que respeta esa lista, ver C2 en `tasks/hallazgos_pruebas_newa.md`), `fix_reporte_ventas_por_turno_sin_cierre.sql`, `fix_esperado_turno_por_moneda_ventas_offline.sql` (el esperado por moneda del cierre ignora las ventas sincronizadas después del cierre del dispositivo; main tiene el mismo defecto, ver C9), `fix_reportes_turno_ventas_offline.sql` (después del anterior; helper `fn_operacion_en_turno` y reportes de turno por rango de id, ver C12; aborta si el cuerpo de main no coincide con el de newa), `reportes_turno_completadas_y_por_moneda.sql` (después de `fix_reportes_turno_ventas_offline.sql`: solo operaciones completadas y `fn_turnos_por_moneda` que consume el admin, ver C13), `fix_listar_entregas_por_turno_sin_ventana_fecha.sql` (el admin no ve los egresos de un turno offline por la ventana de fechas; antes de publicar el admin, ver C11), `fix_cambio_estado_operacion_mejorado_recepcion.sql` (con la prueba de recepción usada), `newa_traer_funciones_main.sql`.
3b. Clientes que dependen de lo anterior (C14, revisión de `cierre_screen.dart` y `sales_screen.dart`): el TPV (`ventiq_app/lib/screens/cierre_screen.dart`) muestra el resumen del cierre por moneda y se alimenta de `desglose_monedas` (`importe_nativo`, `operaciones`) de `fn_resumen_turno_por_id_v2`; el admin (`sales_screen.dart`) decide la pertenencia de las órdenes de un turno por el rango de ids que lee de `app_dat_caja_turno` y pide `listar_ordenes` hasta hoy. Main no se toca desde estas pantallas: se modifica en el pase, con los scripts del punto 3 ya aplicados y antes de publicar TPV y admin. El egreso 3 del turno 20 de newa (5 000 USD) es un registro de prueba que no existe en main ni se migra; la comprobación de saldo por moneda del egreso sigue siendo solo de cliente (C5): decidir antes del pase si se añade también a las RPC de egreso.
3c. Pendientes offline (C16): solo clientes, sin SQL. Publicar el TPV con `getUnsyncedOfflineCounts`, `asegurarSubidaPendientes`, el cierre de sesión que conserva datos, `PendientesOtraTiendaException` y la omisión de descargas con pendientes; probar en dispositivo antes del pase (logout con y sin red, venta online con pendientes, orden con error permanente, cambio de tienda con pendientes, versión nueva con pendientes).
4. **No** entra: ningún `REVOKE`, `DROP POLICY`, `ENABLE ROW LEVEL SECURITY` sobre tablas que ya existen y están en uso, `DROP FUNCTION`, ni los triggers `m01_*` sobre tablas de ventas (se instalan en la fase 3: con el flag apagado no cambian nada, y así no se añade un trigger al camino de venta antes de necesitarlo).
5. Preservar lo propio de main: `trg_bloquear_operaciones_maria`, WhatsApp, referidos, crons.
6. Verificación inmediata: los conteos de errores 4xx/5xx por ruta en los logs de main deben quedar iguales que la hora anterior; `fn_check_update` y una venta de prueba.

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
