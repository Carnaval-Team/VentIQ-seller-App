# Plan de implementación — Taxi Muevete con precio automático por zonas

> **Módulo**: taxi de pasajeros de `inventtia_muevete` + configuración en `ventiq_superadmin`.
> **Objetivo**: eliminar la negociación cliente↔chofer y sustituirla por un precio calculado por el servidor según zona, distancia y tipo de vehículo; los choferes **toman** el viaje de una lista, el primero gana.
> **Estado: CERRADO (2026-11-14).** Todo implementado y probado: base de datos (`030`–`048`) aplicada y validada en el proyecto de PRUEBAS, apps cliente/chofer y superadmin terminadas, y checklist de H1/H2 cumplido. **Nada está aún en producción**: el orden exacto para ejecutarlo está en [`ORDEN-PRODUCCION.md`](ORDEN-PRODUCCION.md) (runbook detallado en [`14-despliegue-y-cutover.md`](14-despliegue-y-cutover.md)).
> **Fecha**: 2026-11-12 · **Repo**: `C:\Users\cesar\Documents\VentIQ-seller-App` · rama `main`.

---

## Estado de ejecución (actualizado 2026-11-12)

| Bloque | Entregable | Estado |
|---|---|---|
| H0 / H1 / H2 | `030`–`037` (zonas, tarifas, geo, identidad, seguridad, catálogo de vehículos) | ✅ Aplicadas en la BD de pruebas |
| H3 · precio | `038` crear/cancelar solicitud | ✅ Aplicada · 13/13 pruebas |
| H3 · precio | `039` lista de viajes + toma atómica | ✅ Aplicada · 8/8 pruebas E2E |
| H3 · precio | `040` cierre + recarga de wallet | ✅ Aplicada · 8/8 pruebas E2E |
| Cutover | `041` RLS y permisos | ✅ Escrita · **no se aplica hasta publicar las apps nuevas** |
| H4 | App **cliente** sin negociación (desglose congelado, "Buscando conductor…", cancelar con reembolso) | ✅ Implementado · análisis sin errores |
| H5 | App **chofer** (viajes disponibles, tomar, cerrar, deuda) + notificaciones del flujo nuevo | ✅ Implementado · análisis sin errores |
| H6 | Superadmin: zonas poligonales, tarifas y simulador | ✅ Implementado · análisis sin errores · 12/12 tests de geometría |
| H7 | Cierre por QR seguro (secreto fuera del código) + recibo con desglose congelado | ✅ Implementado · 8/8 tests |
| H8 | QA integral, versión mínima forzada y cutover | ✅ Implementado · 10/10 concurrencia |
| H1-UI | **Onboarding KYC + consentimiento + contacto de emergencia + gate en la app** | ✅ Implementado · 0 errores de análisis |

> **Resuelto el 2026-11-13:** las pantallas ya existen. `lib/screens/identidad/`
> (onboarding + consentimiento), `lib/screens/seguridad/` (contactos, hub, reporte
> de incidente), widgets de pánico/compartir/ficha, y el gate enganchado en
> publicar y tomar con rutas por código de error (`P0050`/`P0053`/`P0110`).
> El usuario de debug completó su perfil y ya puede publicar viajes.

### Auditoría 2026-11-13 · cierre al 100%

Estado real tras la implementación (lo que **sí** está y lo que **faltaba**):

| Área | Estado |
|---|---|
| BD: migraciones 030–043 aplicadas y probadas en PRUEBAS | ✅ |
| BD: pepper `seguridad_token_pepper` en Vault (PRUEBAS) | ✅ (prod: paso del runbook) |
| BD: documentos legales con texto real (`042`, v1.1.0 + 1.0.0 histórica) | ✅ |
| BD: consentimientos append-only (`043`, trigger `P0060` + permisos) | ✅ |
| BD: documento `contacto_emergencia` para la declaración de autorización (`044`) | ✅ |
| BD: retención alineada con la política publicada — 90 días / 5 años (`045`) | ✅ |
| BD: **KYC obligatorio también para clientes** (`048`, `requiere_aprobacion_kyc_cliente = true`) | ✅ |
| Superadmin: KYC **de clientes y de choferes** en la misma pantalla | ✅ |
| App: flujo de viaje sin negociación (cliente y chofer) | ✅ |
| App: onboarding KYC, consentimiento y gate visual (`identidad/`) | ✅ |
| App: contacto de emergencia, pánico offline, compartir viaje, ficha de contraparte, 106, incidentes (`seguridad/`) | ✅ |
| App: **FAB persistente de requisitos** con checklist tachado (cliente y chofer) | ✅ |
| App: copy del dinero corregido (comisión se descuenta de la wallet) | ✅ |
| Superadmin: tarifas, zonas y simulador | ✅ |
| Superadmin: catálogo de vehículos (orden/capacidad/visibilidad/nombre) | ✅ |
| Superadmin: documentos legales + auditoría de consentimientos | ✅ |
| Superadmin: incidentes, pánico reciente y suspensión del gate | ✅ |
| H0-A: `service_role` en repo público | ✅ decisión tomada: **no rotar**; riesgo aceptado por escrito en [`10-incidente-credenciales.md`](10-incidente-credenciales.md) §7 |

Decisiones del usuario — **resueltas el 2026-11-13**:
- ✅ Retención de ubicaciones: **90 días** → `045` alineó `configuracion_seguridad`
  (estaba en 30) con la Política de Privacidad v1.1.0.
- ✅ Retención de incidentes: **5 años** (60 meses) → `045` la subió de 24 meses.
- ⏳ Firma legal del documento **KYC** (redactado de cero) e identificación
  registral del responsable: depende del abogado, no del código.

Criterios de H1/H2 que **sólo se pueden validar con las pantallas**:
`ci`+`poblado` completables, re-aceptación al subir versión del documento,
contacto de emergencia con declaración de autorización, pánico encolado sin
red, enlace de viaje que caduca al cerrar, ficha con CI parcial, y bloqueo por
incidente confirmado.

### Checklist de aceptación H1/H2 (verificado 2026-11-13)

`[x]` verificado · `[~]` implementado, pendiente de probar en dispositivo · `[ ]` pendiente

**H1 · confianza**
- [x] Lista Auto · Minivan · Microbús · Moto · Triciclo Eléctrico, en orden, editable en superadmin sin recompilar.
- [x] Un cliente que pide 6 pasajeros no ve Auto ni Moto (filtro por `pasajeros_max`).
- [x] Un chofer con 4 plazas no puede tomar un viaje de 5 (`P0052` + `puede_tomar=false`).
- [x] Nadie publica ni toma sin CI, fotos del carnet, provincia/municipio/poblado, dirección y consentimiento: gate en servidor (13/13) + pantallas bloqueantes.
- [x] **La verificación de identidad es obligatoria para cliente Y chofer**: `requiere_aprobacion_kyc_cliente = true` (`048`); sin aprobación del superadmin el gate devuelve `kyc_pendiente_aprobacion` y no se puede publicar ni tomar.
- [x] El gate no se salta con un cliente modificado (probado llamando la RPC directo).
- [x] Cambiar la versión de un documento obliga a re-aceptar y queda auditado (`042` + `043` append-only).
- [x] Los 3 documentos legales tienen **texto real** (`042`, v1.1.0; la 1.0.0 queda en histórico).
- [x] El gate se puede suspender desde superadmin y reanudar; `drivers.kyc` nunca se suspende.

**H2 · seguridad del viaje**
- [x] Pánico sin red queda en cola local y se envía al recuperar conexión (outbox FIFO idempotente). Validado en pruebas.
- [x] El enlace compartido deja de funcionar al terminar o cancelar y no expone teléfono ni CI completa (revocación por trigger de cierre + ficha con CI parcial). Validado en pruebas.
- [x] Un usuario bloqueado por incidente confirmado no puede publicar ni tomar (`fn_gate_seguridad`; `fn_resolver_incidente` crea el bloqueo).
- [x] El copy del botón deja claro que **no sustituye** a llamar a la policía (y botón directo al 106).
- [x] `seguridad_token_pepper` existe en Vault en PRUEBAS (en producción es paso obligatorio del runbook).
- [x] El contacto se muestra **"sin verificar"** y el OTP nunca se devuelve al cliente.
- [x] El alta del contacto exige **declaración explícita** y queda registrada (`044` + `fn_aceptar_consentimiento`).

**Limitaciones conocidas documentadas (no bloquean el MVP)**
- El muestreo continuo de posición durante un pánico (`fn_registrar_posicion_panico` cada 15 s) no está en la UI; el pánico envía la ubicación del momento.
- El selector de modo discreto/visible del pánico no está expuesto (usa el modo por defecto).
- Las opciones de reporte de incidente no se filtran por rol (pasajero vs chofer).
- La señal de lista negra al chofer no distingue si el bloqueado es él mismo; el texto podría quedar impreciso en ese caso.

> **Estado global: IMPLEMENTADO Y PROBADO. Pendiente únicamente ejecutar el cutover**
> (runbook: [`14-despliegue-y-cutover.md`](14-despliegue-y-cutover.md)). Nada de esto
> está en producción todavía: el proyecto de pruebas es el único que tiene las
> migraciones aplicadas.

### Cierre del plan · 2026-11-14

Los 9 hitos quedaron implementados y probados; los criterios de aceptación de
cada uno figuran abajo como cumplidos. Sólo quedan abiertos cuatro puntos que
**no se cierran desde el código**:

| Punto | Por qué |
|---|---|
| **Ejecutar el cutover** | Es la ventana de despliegue → [`ORDEN-PRODUCCION.md`](ORDEN-PRODUCCION.md) |
| **Firma legal del documento KYC** e identificación registral | Depende del abogado |
| **Repositorio privado** | Decisión del usuario: riesgo aceptado por escrito |
| **Rollback probado** | Sólo se puede validar después del primer despliegue |

Pruebas: `inventtia_muevete/docs/migrations/tests/` (`test_038_solicitud.sql`,
`test_039_040_flujo.sql`). Contrato app↔RPC: [`13-contrato-app-rpc.md`](13-contrato-app-rpc.md).

Hallazgos que cambiaron el diseño durante la implementación:

- **D-2b**: el seed del catálogo de vehículos usa una columna marcadora explícita
  (`vehicle_type.catalogo_sembrado_at`); antes infería "ya sembrado" de `orden`/`nombre_ui`
  y podía pisar el orden configurado por el superadmin.
- **Códigos de error**: `P0001`–`P0004` son reservados por PL/pgSQL y `P0004`
  (`assert_failure`) **no se puede capturar** con `EXCEPTION WHEN OTHERS`. El módulo usa
  `P0005` en adelante.
- **Wallet**: `transacciones_wallet.tipo` tiene CHECK y sólo admite
  `recarga | cobro_viaje | pago_viaje | reembolso | comision_viaje`; el convenio de
  retención/reembolso se ajustó a esos valores.
- **Flag de corte**: `taxi_precio_fijo_activo` nace en `false`; hay que encenderlo al
  desplegar (y sólo entonces deja de aceptar publicaciones del flujo viejo).
- **Hotfix 2026-11-13 — permisos de las RPC de cálculo**: la primera llamada real
  de la app (`POST /rest/v1/rpc/fn_cotizar_viaje` como `authenticated`) devolvió
  `42501 permission denied for function fn_punto_en_anillo`. Causa: en `032`,
  `fn_cotizar_viaje`, `fn_zona_de_punto` y `fn_punto_en_poligono` se crearon como
  **SECURITY INVOKER** y delegaban en helpers internos revocados para clientes.
  Corregido en `032` con `SECURITY DEFINER` + `search_path` fijado y sin
  `PARALLEL SAFE`. Se añadió
  [`tests/test_permisos_rpc.sql`](../../inventtia_muevete/docs/migrations/tests/test_permisos_rpc.sql)
  como guardarraíl: las pruebas anteriores corrían como `postgres` y por eso no
  podían detectar fallos de permisos.

---

> 🔴 **P0 — LEER ANTES QUE NADA.** La clave `service_role` de **producción** está embebida en el build de release de **6 apps** y el repositorio de GitHub es **público**. La base de datos completa (CI, fotos de carnet, wallets, ubicaciones históricas) es accesible por cualquiera que descompile un APK o mire el repo. Detalle, evidencia y remediación en [`10-incidente-credenciales.md`](10-incidente-credenciales.md). **H0-A es bloqueante de todo lo demás.**

---

## 0. Resumen para decidir (leer solo esto si tienes 2 minutos)

| # | Qué cambia | Antes (hoy) | Después |
|---|---|---|---|
| 1 | Quién fija el precio | El cliente escribe "Tu Oferta" (`route_preview_screen.dart`) | El servidor calcula zona + km + tipo. El cliente solo ve y acepta |
| 2 | Cómo se asigna | Doble negociación: chofer contraoferta en `ofertas_chofer`, cliente elige en `driver_offers_screen.dart` | Lista de viajes tomables; **el primero que toca se lo lleva** (atómico en BD) |
| 3 | Geografía | Círculo hardcodeado de 2,53 km alrededor del Parque Vidal | **Polígonos** dibujados por el superadmin en un mapa |
| 4 | Tarifa | `vehicle_type.precio_inside_sc` (plano) o `precio_km_default × km` | Zona con modelo `fijo` / `fijo_mas_km` / `por_km` × multiplicador por tipo |
| 5 | Comisión | 15 % hardcodeado en 4 sitios y en el RPC de cierre | 15 % configurable en superadmin, sin recompilar |
| 6 | Chofer con wallet en 0 | No puede ni ofertar (bloqueo por saldo) | **Toma el viaje**; acumula deuda de comisión hasta un tope configurable |
| 7 | Arranque Santa Clara | — | Municipio con **1 500 CUP fijo**; zonas internas con fijo + km |
| 8 | Catálogo de vehículos | 7 tipos activos, sin orden definido | **Auto · Minivan · Microbús · Moto · Triciclo Eléctrico**, orden editable en superadmin; bicicleta y camioneta ocultas |
| 9 | Capacidad | No se valida | El cliente elige cuántos viajan; solo ve tipos que la soportan y el chofer no puede tomar un viaje que exceda sus plazas |
| 10 | Identidad | CI en 3/18 clientes y 1/23 choferes; sin poblado; sin consentimiento | **KYC obligatorio y no evadible**: CI + carnet frente/dorso + provincia/municipio/**poblado** + dirección, también para los 41 usuarios existentes |
| 11 | Seguridad y privacidad | Sin botón de pánico, sin compartir viaje, sin documentos legales | Pánico + compartir en vivo + 106 + verificación mutua + incidentes/bloqueo, y consentimiento versionado que bloquea el viaje sin aceptar |

**Resultado esperado**: viaje publicado en < 2 s, asignado en < 60 s (p50), mismo precio para el mismo trayecto y tipo, y chofer que ve su pago neto antes de decidir.

**Esfuerzo**: **H0-A + 9 hitos (H0–H8)**. Con el equipo de agentes actual: H0-A inmediato (1 sesión de coordinación con acceso al dashboard), 1 sesión para H0, 1 para H1, 1 para H2, 1 para H3, 2 para H4, 2 para H5, 2 para H6, 1 para H7 y 1 para H8.

**Primer entregable**: H0 (migración aditiva + seed + RLS + pruebas SQL), sin tocar todavía las apps.

**Lo que cambió respecto de la versión anterior del plan**: se añadieron H1 (identidad, vehículos y consentimiento) y H2 (seguridad del viaje) **antes** de tocar el flujo de precio, porque son prerequisitos: no se puede asignar un viaje a alguien cuya identidad no está verificada ni publicar sin consentimiento. H0 sigue igual y ya está escrito.

---

## 1. Objetivo y alcance

### 1.1 Dentro del alcance

- Tarifa automática por zonas poligonales para **taxi de pasajeros** (`vehicle_type` de categoría pasajero).
- Publicación del viaje a los choferes elegibles de la zona, con precio al cliente, comisión y neto del chofer.
- Toma atómica del viaje (primer-gana) desde una lista, sin contraofertas.
- Configuración en superadmin: zonas, tarifas, multiplicadores por tipo, parámetros globales, simulador.
- Comisión configurable, deuda de comisión en efectivo con tope y liquidación al completar.
- Cierre del viaje (online, offline y QR) con precio congelado en servidor.
- Migración de datos y estrategia de compatibilidad con apps viejas.

### 1.2 Fuera del alcance (explícito)

- Carga / mudanzas (`muevete.cargas`, `ofertas_carga`, `carrier`, `shipper`): no se tocan.
- Dispatcher (asignación manual desde consola): se deja como está; no se rediseña.
- Multimoneda, conversión CUP/MLC/USD, tarifas dinámicas por demanda (surge), propinas.
- Suscripción mensual para choferes (el económico lo desaconseja para el arranque).
- Cambios en la app de marketplace, TPV, admin de tiendas o flow.

**Diferido por decisión del usuario (2026-11-12)**: el análisis de cumplimiento sobre **alojamiento nacional de datos** (Res. 58/2022 y restricciones de transferencia de la Ley 149/2022). Se redactan términos y condiciones **sin** mencionar ese requisito y sin condicionar el diseño. Queda como tema a revisar con un abogado en el futuro, fuera de este plan.

---

## 2. Decisiones cerradas y parámetros de arranque

### 2.1 Decisiones del usuario (vinculantes)

| ID | Decisión | Consecuencia técnica |
|---|---|---|
| **D1** | Zonas = **polígonos dibujados en el mapa** por el superadmin | `zonas_tarifa.geometria` en `jsonb` (GeoJSON); editor `flutter_map` en superadmin |
| **D2** | **Multiplicador por tipo de vehículo** sobre la tarifa de zona | `vehicle_type.multiplicador_tarifa`: moto 0,60 · auto 1,00 · microbús 1,50 |
| **D3** | "Dentro de la zona se cobra fijo; al salir, km × precio_km (configurable)". Modos por zona | `modo`: `fijo` / `fijo_mas_km` / `por_km` |
| **D4** | Fuera de toda zona: **fijo del municipio, configurable** (1 500 CUP) | `tarifas_municipio` como fallback; no bloquea el viaje |
| **D5** | Comisión **15 % global configurable** | `configuracion_tarifas.comision_pct`; elimina el `0.15` hardcodeado |
| **D6** | Efectivo: **deuda configurable en superadmin** — un interruptor `permite_deuda` (sí/no) y un `limite_deuda_efectivo` | Con `permite_deuda = false` el chofer necesita saldo ≥ comisión (comportamiento actual); con `true` puede quedar negativo hasta el tope |
| **D7** | **Cuentas de empresa**: se admite persona jurídica con **CI del representante legal + documento de la empresa** | `fn_usuario_habilitado` ramifica por `users.tipo_cuenta`: `individual` → CI propio; `empresa` → CI del representante + `doc_empresa_url` |

### 2.2 Fórmula única (contrato del servidor)

```
0) zona_origen  = zona activa de mayor prioridad que contiene el origen
   zona_destino = zona activa de mayor prioridad que contiene el destino
   (si no hay → tarifa del municipio del origen, D4)

1) Regla de la zona del ORIGEN (R5: manda el origen):
   modo = 'fijo'        → si destino dentro de la MISMA zona: precio = monto_fijo
                          si el viaje sale de la zona:          precio = km_total × precio_km
   modo = 'fijo_mas_km' → precio = monto_fijo + km_total × precio_km
   modo = 'por_km'      → precio = km_total × precio_km

2) Multiplicador por tipo (D2):      precio = precio × multiplicador_tarifa
3) Piso por tipo (precio_minimo_*):  precio = max(precio, minimo)
4) Recargos: nocturno 20 % (22:00–06:00), prima > 8 km 500 CUP, espera
5) Redondeo hacia arriba a múltiplos de 50
6) Congelar snapshot: precio_plataforma, comision_pct, precio_chofer, zona_id, tarifa_detalle
```

`km_total` = distancia real de la ruta (`routing_service`), no Haversine en línea recta.

### 2.3 Parámetros de arranque recomendados (todos editables en superadmin)

| Parámetro | Valor arranque | Rango | Nota |
|---|---|---|---|
| `moneda` | `CUP` | — | se muestra como `$` |
| `comision_pct` | **15 %** | 0–30 | D5 |
| `tope_comision_viaje` | **2 500 CUP** | 0–20 000 | evita comisión desproporcionada en viajes largos |
| `multiplicador_moto / auto / microbus` | **0,60 / 1,00 / 1,50** | 0,4–2,0 | D2, validado contra costo por km |
| `monto_fijo_fallback_municipio` | **1 500 CUP** | 500–5 000 | D4 |
| `precio_km_fallback` | **400 CUP/km** | 0–2 000 | salida del casco urbano |
| `precio_minimo_auto / moto / microbus` | **1 500 / 900 / 2 250** | — | piso post-multiplicador |
| `precio_corto_auto` + `umbral_km_corto` | **1 000 CUP** si < **1,5 km** | — | válvula de elasticidad del viaje corto |
| `recargo_nocturno_pct` | **20 %** 22:00–06:00 | 0–50 | no se aplica sobre la espera |
| `tarifa_espera_min` (auto/moto/micro) | **40 / 100 / 60 CUP/min** | — | ya existe en BD; corregir el bug de nombres |
| `gracia_espera_min` / `tope_cobro_espera` | **3 min** / **1 200 CUP** | — | |
| `redondeo_cup` | **50** | 5/25/50 | |
| `permite_deuda` | **true** | on/off | D6 · interruptor de la deuda de comisión |
| `limite_deuda_efectivo` | **1 000 CUP** (lanzamiento 500) | 0–5 000 | D6 · solo aplica si `permite_deuda = true` |
| `dias_max_deuda` | **7 días** | 1–30 | |
| `descuento_pago_wallet_pct` | **5 %** | 0–20 | antídoto contra el regateo fuera de la app |
| `precio_vigente_desde` / `revision_precio_dias` | — / **30 días** | — | el fijo 1 500 solo se sostiene hasta ~2 760 CUP/L de combustible |

### 2.4 Zonas a cargar en el seed inicial

| Código | Zona | Modo | Fijo (CUP) | $/km | Precio típico auto |
|---|---|---|---|---|---|
| MUN | Municipio Santa Clara (base) | `fijo` | 1 500 | 400 | 1 500 · si sale, km × 400 |
| Z1 | Centro | `fijo` | 1 500 | 400 | 1 500 |
| Z2 | Condado–Santa Catalina | `fijo` | 1 500 | 400 | 1 500 |
| Z3 | Reparto Virginia | `fijo_mas_km` | 300 | 400 | 1 900 (4 km) |
| Z4 | Báez | `fijo_mas_km` | 500 | 420 | 3 450 (7 km) |
| Z5 | UCLV | `fijo_mas_km` | 500 | 420 | 3 900 (8 km) |
| Z6 | Aeropuerto | `fijo_mas_km` | 1 000 | 420 | 5 100 (9,7 km) |
| Z7 | Periferia / Circunvalación | `fijo_mas_km` | 300 | 420 | 2 400 (5 km) |
| Z8 | Corredor intermunicipal | `fijo_mas_km` | 800 | 450 | 20 600 (44 km) |
| Z9 | Cayos | `fijo_mas_km` | 800 | 450 | 51 650 (113 km) |
| FB | Fallback | `fijo` | 1 500 | 400 | 1 500 |

> Los polígonos reales los dibuja el superadmin. En el seed solo se cargan MUN y FB como rectángulo aproximado del municipio + la configuración global; Z1–Z9 se cargan como borradores desactivados para que el negocio los ajuste en el editor. **Ninguna zona interna se activa sin que el superadmin la dibuje.**

### 2.5 Punto de partida real (verificado en la BD de producción, 2026-11-12)

Consultado por SQL contra `vsieeihstajlrdvpuooh` (solo lectura), no contra los `.sql` del repo:

| Hecho verificado | Valor real | Consecuencia para el plan |
|---|---|---|
| Extensiones instaladas | `pg_cron, pg_net, pg_stat_statements, pg_trgm, pgcrypto, plpgsql, supabase_vault, unaccent, uuid-ossp, vector, wrappers` | **No hay PostGIS** → point-in-polygon en PL/pgSQL (confirmado) |
| Políticas RLS en `muevete` | **118** | Hay que auditar antes de revocar; el diseño de RLS no puede asumir las migraciones del repo |
| Tablas publicadas en realtime | **Producción**: `muevete.notificaciones, ofertas_chofer, place, solicitudes_transporte, vehicle_type, viajes` (+ flow, carnavalapp). **Desarrollo**: solo `flow.agenda, flow.notificaciones` | **Producción sí emite realtime de Muevete; desarrollo NO.** Antes de probar el flujo nuevo en dev hay que replicar la publicación (`ALTER PUBLICATION supabase_realtime ADD TABLE ...`) o las pantallas parecerán congeladas |
| Volumen de datos | 55 solicitudes · 45 ofertas · 44 viajes · 23 drivers · 8 tipos · 387 351 puntos de track | Migración y backfill triviales; el riesgo es de esquema, no de volumen |
| Tarifa vigente `auto` | `precio_inside_sc` **800 CUP** · `precio_km_default` **200 CUP/km** | El nuevo 1 500 es **+87,5 %** y el 400/km es **+100 %**. Es un cambio de precio real, no cosmético |
| Tarifa vigente `moto` | inside **500** · km **300** | Ojo: hoy la moto sale **más caras que el auto por km** (300 vs 200) → anomalía a corregir con D2 |
| Tarifa vigente `microbús` | inside **800** · km **250** | Queda por debajo del auto en la práctica |
| Tipos pasajeros activos | moto, auto, microbus, **camioneta (km 1,5)**, **bicicleta (0,2)**, **tuktuk (0,4)**, **minivan (1,8)** | Esos 4 últimos tienen precios en **escala USD legacy** → hay que asignarles multiplicador (1,2 / 0,3 / 0,5 / 1,3) y dejar de usar `precio_inside_sc` |
| `solicitudes_transporte.driver_id` | **no existe** (16 columnas) | Confirmado el bloqueante: hay que añadirla en H0 |
| `viajes.driver_id` | **smallint** vs `drivers.id` bigint | Corregir a bigint en la migración |
| `viajes.solicitud_id` | **no existe** | Confirmado el bloqueante de H0 |

**Huecos de RLS confirmados con su definición real** (esto sustituye la versión genérica de §4.3):

| Política real | Definición en producción | Problema |
|---|---|---|
| `drivers_see_solicitudes` | `SELECT USING (true)` | cualquier autenticado ve todas las solicitudes con direcciones y coordenadas |
| `solicitudes_select_own_client` | `USING ((user_id = auth.uid()) OR true)` | el `OR true` la hace inútil |
| `solicitudes_update_own_client` | `USING user_id = auth.uid()` | el cliente puede cambiar **cualquier** columna: precio, estado, `driver_id` |
| `solicitudes_insert_client` | `WITH CHECK user_id = auth.uid()` | el cliente inserta con el precio que quiera |
| `viajes_insert_authenticated` | `INSERT WITH CHECK (true)` | cualquier autenticado crea un viaje sin comprobar propiedad |
| `wallet_drivers_update_own` | `USING/CHECK driver_id IN (mis drivers)` | **el chofer puede editar su propio saldo** — agujero de dinero |
| `transacciones_insert_client` | cliente o chofer pueden insertar | transacciones de wallet falsas |
| `ofertas_update_client` | cliente actualiza ofertas | permite manipular la aceptación hoy |

> Nada de esto bloquea H0 (que es aditivo), pero **la migración de endurecimiento de RLS es obligatoria antes de cobrar con el flujo nuevo** y va en H3/H7. Mientras dure la transición, el precio se congela en servidor y da igual lo que el cliente escriba: el snapshot manda.

---

## 3. Arquitectura de la solución

```
┌──────────────────────────┐        ┌────────────────────────────────────┐
│ ventiq_superadmin        │        │ Supabase · esquema muevete         │
│  Zonas y Tarifas (NUEVA) │──CRUD─▶│  zonas_tarifa (polígonos jsonb)    │
│  · editor de polígono    │        │  tarifas_municipio (fallback D4)   │
│  · modos + multiplicador │        │  configuracion_tarifas (global)    │
│  · simulador de precio   │        │  vehicle_type.multiplicador_tarifa │
└──────────────────────────┘        │                                    │
                                    │  RPCs SECURITY DEFINER:            │
┌──────────────────────────┐        │   fn_cotizar_viaje                 │
│ inventtia_muevete cliente│◀──────▶│   fn_crear_solicitud               │
│  precio fijo, sin editar │        │   fn_viajes_disponibles            │
└──────────────────────────┘        │   fn_tomar_viaje  (atómico)        │
┌──────────────────────────┐        │   fn_completar_viaje               │
│ inventtia_muevete chofer │◀──────▶│   fn_cancelar_solicitud            │
│  lista + "Tomar viaje"   │        │                                    │
└──────────────────────────┘        │  Realtime: solicitudes, viajes     │
                                    └────────────────────────────────────┘
```

**Principio rector**: el cliente **no** envía precio nunca más. Toda escritura de dinero o de asignación pasa por RPC `SECURITY DEFINER`; las tablas quedan en solo lectura para las apps.

### 3.1 Flujo cliente

1. Elige origen/destino → `routing_service` calcula ruta y km.
2. La app llama `fn_cotizar_viaje(lat_o, lon_o, lat_d, lon_d, tipo)` y muestra el **desglose** (zona, tarifa, km, multiplicador, total).
3. Elige pago (efectivo / wallet) → `fn_crear_solicitud(...)` congela la tarifa y devuelve la solicitud.
4. Pantalla "Buscando chofer" con realtime sobre **su** solicitud.
5. Cuando un chofer la toma: UPDATE de `solicitudes_transporte.driver_id` → "Chofer asignado · en camino".
6. Viaje → completado → valoración. El recibo muestra el desglose congelado.

### 3.2 Flujo chofer

1. Se conecta (publica posición en `place`).
2. `fn_viajes_disponibles()` devuelve solicitudes pendientes cuyo **origen cae en su zona**, con tipo compatible, KYC ok, sin viaje activo y con deuda bajo el tope.
3. Tarjeta: tipo requerido · zona · origen · destino · km · **"Cliente paga $X"** · **"Te toca $Y (Z %)"** · deuda disponible.
4. "Tomar viaje" → `fn_tomar_viaje(solicitud_id)` **atómico**; si otro ganó, mensaje "Ese viaje ya fue tomado" y la tarjeta desaparece.
5. Ciclo: en camino → llegué → en viaje → completar (QR o botón).

### 3.3 Flujo superadmin

1. Menú **Muevete → Zonas y Tarifas**.
2. Lista de zonas con estado, modo y precio; crear/editar/desactivar.
3. Editor de polígono: tocar mapa para añadir vértices, deshacer, cerrar, validar (mín. 3 puntos, sin auto-intersecciones), previsualizar.
4. Formulario de tarifa: modo, monto fijo, precio/km, prioridad, multiplicadores, vigencia.
5. Pestaña **Parámetros globales**: comisión, fallback municipal, topes, recargos, redondeo, deuda.
6. **Simulador**: origen/destino/km/tipo/hora → muestra precio al cliente, comisión, neto del chofer y qué zona aplicó.

---

## 4. Contrato de datos

### 4.1 Tablas nuevas

```sql
-- muevete.zonas_tarifa
id bigint identity PK,
nombre text NOT NULL,
provincia text, municipio text,                    -- para reportes y fallback
geometria jsonb NOT NULL,                          -- GeoJSON Polygon {type, coordinates:[[ [lon,lat], ... ]]}
modo text NOT NULL CHECK (modo IN ('fijo','fijo_mas_km','por_km')),
monto_fijo numeric,                                -- requerido si modo <> 'por_km'
precio_km numeric,                                 -- requerido si modo <> 'fijo'
prioridad integer NOT NULL DEFAULT 0,              -- mayor gana en solapes
activo boolean NOT NULL DEFAULT true,
vigente_desde timestamptz NOT NULL DEFAULT now(),
vigente_hasta timestamptz,
created_at timestamptz NOT NULL DEFAULT now(),
updated_at timestamptz NOT NULL DEFAULT now(),
CONSTRAINT zonas_tarifa_geo_valida CHECK (jsonb_typeof(geometria->'coordinates') = 'array')

-- muevete.tarifas_municipio  (fallback D4)
id bigint identity PK,
provincia text NOT NULL, municipio text NOT NULL,
modo text NOT NULL DEFAULT 'fijo',
monto_fijo numeric NOT NULL DEFAULT 1500,
precio_km numeric NOT NULL DEFAULT 400,
activo boolean NOT NULL DEFAULT true,
UNIQUE (provincia, municipio)

-- muevete.configuracion_tarifas  (fila única)
id smallint PK DEFAULT 1 CHECK (id = 1),
moneda text NOT NULL DEFAULT 'CUP',
comision_pct numeric(5,2) NOT NULL DEFAULT 15.00,
tope_comision_viaje numeric NOT NULL DEFAULT 2500,
recarga_pct numeric(5,2) NOT NULL DEFAULT 11.00,
permite_deuda boolean NOT NULL DEFAULT true,      -- D6: interruptor on/off de la deuda
limite_deuda_efectivo numeric NOT NULL DEFAULT 1000,
dias_max_deuda integer NOT NULL DEFAULT 7,
precio_minimo_auto numeric NOT NULL DEFAULT 1500,
precio_minimo_moto numeric NOT NULL DEFAULT 900,
precio_minimo_microbus numeric NOT NULL DEFAULT 2250,
precio_corto_auto numeric NOT NULL DEFAULT 1000,
umbral_km_corto numeric(4,1) NOT NULL DEFAULT 1.5,
recargo_nocturno_pct numeric(5,2) NOT NULL DEFAULT 20,
ventana_nocturna_inicio time NOT NULL DEFAULT '22:00',
ventana_nocturna_fin time NOT NULL DEFAULT '06:00',
gracia_espera_min integer NOT NULL DEFAULT 3,
tope_cobro_espera numeric NOT NULL DEFAULT 1200,
redondeo_cup integer NOT NULL DEFAULT 50,
prima_distancia_cup numeric NOT NULL DEFAULT 500,
umbral_prima_distancia_km numeric(4,1) NOT NULL DEFAULT 8,
descuento_pago_wallet_pct numeric(5,2) NOT NULL DEFAULT 5,
precio_vigente_desde timestamptz NOT NULL DEFAULT now(),
updated_at timestamptz NOT NULL DEFAULT now()
```

### 4.2 Columnas añadidas (aditivas, no rompen apps viejas)

```sql
ALTER TABLE muevete.vehicle_type
  ADD COLUMN multiplicador_tarifa numeric NOT NULL DEFAULT 1;   -- D2

-- Normalización de la escala legacy (ver §2.5):
-- moto 0.60 · auto 1.00 · microbus 1.50 · camioneta 1.20
-- minivan 1.30 · tuktuk 0.50 · bicicleta 0.30
-- A partir de aquí, `precio_inside_sc` y `precio_km_default` quedan DEPRECADOS
-- para taxi de pasajeros: la tarifa vive en las zonas.

ALTER TABLE muevete.solicitudes_transporte
  ADD COLUMN driver_id bigint REFERENCES muevete.drivers(id),   -- quién la tomó
  ADD COLUMN aceptada_at timestamptz,
  ADD COLUMN zona_id bigint REFERENCES muevete.zonas_tarifa(id),
  ADD COLUMN tarifa_modo text,
  ADD COLUMN precio_plataforma numeric,   -- lo que paga el cliente (CONGELADO)
  ADD COLUMN comision_pct numeric,        -- copia del % vigente
  ADD COLUMN precio_chofer numeric,       -- neto (CONGELADO)
  ADD COLUMN moneda text DEFAULT 'CUP',
  ADD COLUMN tarifa_detalle jsonb;        -- snapshot completo del desglose

ALTER TABLE muevete.viajes
  ALTER COLUMN driver_id TYPE bigint,      -- era smallint; drivers.id es bigint
  ADD COLUMN solicitud_id bigint REFERENCES muevete.solicitudes_transporte(id),
  ADD COLUMN precio_plataforma numeric,
  ADD COLUMN precio_chofer numeric,
  ADD COLUMN comision_pct numeric,
  ADD COLUMN metodo_pago text;

CREATE UNIQUE INDEX viajes_solicitud_id_uidx ON muevete.viajes(solicitud_id) WHERE solicitud_id IS NOT NULL;
CREATE INDEX solicitudes_estado_created_idx ON muevete.solicitudes_transporte(estado, created_at DESC);
CREATE INDEX solicitudes_driver_idx ON muevete.solicitudes_transporte(driver_id);
```

> **Bloqueante detectado**: hoy `viajes` no tiene `solicitud_id` y el vínculo depende de `ofertas_chofer`. Añadir la columna y rellenarla es el primer paso de H0.

### 4.3 RLS a cerrar (ya verificado en producción — ver §2.5)

| # | Política real a tocar | Acción |
|---|---|---|
| 1 | `solicitudes_update_own_client` (cliente edita cualquier columna) | revocar `UPDATE` de tabla; el cliente solo cambia estado vía `fn_cancelar_solicitud`; opcional `GRANT UPDATE (estado)` |
| 2 | `solicitudes_insert_client` (precio libre) | revocar `INSERT`; la creación pasa solo por `fn_crear_solicitud` |
| 3 | `solicitudes_select_own_client` con `OR true` | reescribir a `user_id = auth.uid()` |
| 4 | `drivers_see_solicitudes USING(true)` | eliminar; la visibilidad pasa por `fn_viajes_disponibles()` |
| 5 | `viajes_insert_authenticated WITH CHECK(true)` | eliminar; el viaje lo crea `fn_tomar_viaje` |
| 6 | `wallet_drivers_update_own` (¡el chofer edita su saldo!) | eliminar; escrituras solo por RPC |
| 7 | `transacciones_insert_client` | eliminar; solo RPC |
| 8 | `ofertas_update_client` | eliminar junto con la negociación; `ofertas_chofer` queda en solo lectura |
| 9 | `wallet_drivers_select_own` | mantener (el chofer debe ver su saldo y su deuda) |
| 10 | `superadmin_all_*` | mantener y replicar el patrón para las 3 tablas nuevas |

> Orden seguro: primero crear las RPC y publicar las apps nuevas; **después** revocar las políticas viejas. Si se revoca antes del cutover, las apps actuales dejan de funcionar (crean solicitudes y viajes por escritura directa).

---

## 5. RPCs (servidor)

Todas `SECURITY DEFINER`, `SET search_path = muevete`, con `GRANT EXECUTE` solo a `authenticated` (y `service_role` para tareas).

| Función | Firma | Responsabilidad |
|---|---|---|
| `fn_punto_en_poligono` | `(lat float8, lon float8, geojson jsonb) → boolean` | Ray casting en PL/pgSQL (no hay PostGIS en el repo). Sustituible por `ST_Contains` si se habilita |
| `fn_zona_de_punto` | `(lat, lon) → zonas_tarifa` | Zona activa de mayor `prioridad` que contiene el punto; `NULL` si ninguna |
| `fn_cotizar_viaje` | `(lat_o, lon_o, lat_d, lon_d, id_tipo, timestamptz) → jsonb` | Aplica §2.2 completo y devuelve el desglose. **No escribe nada** |
| `fn_crear_solicitud` | `(lat_o, lon_o, lat_d, lon_d, id_tipo, dir_o, dir_d, km, metodo_pago) → solicitud` | Vuelve a cotizar en servidor, **congela** snapshot, inserta `pendiente`. Ignora cualquier precio del cliente |
| `fn_viajes_disponibles` | `() → setof jsonb` | Solicitudes `pendiente` cuyo origen cae en la zona del chofer, tipo compatible, KYC, sin viaje activo, deuda bajo tope, TTL vigente |
| `fn_tomar_viaje` | `(p_solicitud_id bigint) → jsonb` | **Atómico**: `UPDATE ... SET estado='aceptada', driver_id=... WHERE id=p AND estado='pendiente' RETURNING`; si 0 filas → `ya_tomado`; valida deuda; crea `viajes` en la misma transacción; devuelve el viaje |
| `fn_completar_viaje` | `(p_viaje_id bigint, p_espera_min int) → jsonb` | Deriva precio/comisión del **snapshot**, aplica comisión (con tope) y espera, actualiza wallets, inserta transacciones, cierra. Rechaza precios enviados por el cliente |
| `fn_cancelar_solicitud` | `(p_solicitud_id bigint, p_motivo text) → jsonb` | Cancela y libera/reembolsa retención de wallet según estado |
| `fn_recargar_wallet` | `(p_metodo, p_monto, p_evidencia) → jsonb` | Centraliza el 11 % de recarga (hoy hardcodeado en 4 sitios) |

**Pruebas obligatorias de H3**: doble `fn_tomar_viaje` concurrente (una gana, la otra recibe `ya_tomado`), cotización 0/1/2 zonas, solape con prioridad, salida de zona en modo `fijo`, fallback municipal, multiplicadores, redondeo y nocturno, cierre con precio manipulado desde el cliente (debe ignorarse), deuda que cruza el tope.

> **Ya existe y hay que reutilizar**: `muevete.get_my_driver_id()` (SECURITY DEFINER, devuelve el `drivers.id` del usuario autenticado) y `muevete.is_superadmin()`. No duplicarlas en las RPC nuevas; se versionaron en `030` y `006` respectivamente.

---

## 6. Hitos

Cada hito es una unidad verificable. Nada se da por terminado sin su criterio de aceptación cumplido.

> **Diseño visual**: las vistas nuevas de H1, H4, H5 y H6 se diseñan primero en **Stitch** y luego se traducen a Flutter. Proyecto canónico del cliente: "Home Map and Transport Selection". Ver **§14**.

### H0-A · Cambio de credencial en el cliente (decisión: sin rotación)

**Objetivo**: que las versiones nuevas de las apps **no distribuyan** una credencial privilegiada. **La rotación de la `service_role` está descartada** por decisión expresa del usuario (hay app en producción y no se interrumpe).

**Entregables**
- `inventtia_muevete/lib/config/supabase_config.dart` con `anon` en release — **✅ hecho y verificado** (ambas claves del archivo decodifican `role=anon`; cero `service_role`).
- Advertencia en el archivo: **no publicar un release** hasta que el cierre de viaje y la wallet pasen por RPC (H7/`040`), o esas dos operaciones fallarán por RLS.
- Las otras 5 apps con la misma corrección — **fuera del alcance de este plan**, registrado como pendiente.
- Repositorio de GitHub en **privado** (recomendado, no bloqueante).
- Riesgo residual documentado y aceptado en [`10-incidente-credenciales.md`](10-incidente-credenciales.md) §7.

**Criterios de aceptación**
- [x] `grep -R "service_role" --include=*.dart inventtia_muevete/lib` no devuelve ninguna clave.
- [x] Las 2 operaciones que dependían del bypass (cierre de viaje y wallet) pasan por RPC antes del primer release nuevo.
- [ ] Repositorio privado — **decisión del usuario**: no se hace por ahora (riesgo aceptado por escrito en [`10-incidente-credenciales.md`](10-incidente-credenciales.md) §7).

**Depende de**: nada. **Riesgo aceptado**: la clave filtrada sigue viva; el cambio solo protege a las versiones futuras.

---

### H0 · Fundaciones de datos (Supabase)

**Objetivo**: esquema nuevo, aditivo y seguro, sin tocar apps todavía.

**Entregables**
- `propuesta-migraciones/030_baseline_sync_produccion.sql` — **borrador**: versiona lo que existía en producción y faltaba en el repo (`get_my_driver_id`, sobrecarga legacy de `complete_ride_payment`, los 3 triggers de push). Ver [anexo 05](05-sincronizacion-bd-repo.md).
- `031_taxi_zonas_tarifas.sql`: tablas de §4.1, columnas de §4.2, índices, triggers de `updated_at`.
- `032_taxi_geo_y_cotizacion.sql`: `fn_punto_en_poligono`, `fn_zona_de_punto`, `fn_cotizar_viaje`.
- `033_taxi_seed_santa_clara.sql`: `configuracion_tarifas` (valores de §2.3), `tarifas_municipio` Villa Clara/Santa Clara (1500/400), `vehicle_type.multiplicador_tarifa` para **los 7 tipos pasajeros** (0,60 / 1,00 / 1,50 / 1,20 / 1,30 / 0,50 / 0,30 según §2.5), MUN + FB.
- `034_taxi_rls_tarifas.sql`: políticas de lectura y `superadmin_all_*` para las 3 tablas nuevas.
- `docs/plan-taxi-precio-fijo/sql/`: scripts de verificación (volcado de `pg_policies` y `pg_publication_tables`, pruebas de cotización) y el **snapshot real** de §2.5 como línea base.

**Criterios de aceptación**
- [x] Migración idempotente y reversible (up + down documentado).
- [x] `fn_cotizar_viaje` devuelve los imports de la tabla §8.3 del anexo 03 (14 casos) exactos.
- [x] `vehicle_type`: 7 tipos pasajeros con `multiplicador_tarifa`, incluidos camioneta/minivan/tuktuk/bicicleta que hoy tienen precios en escala USD.
- [x] `viajes.driver_id` migrado a `bigint` sin pérdida de datos.
- [x] Un cliente autenticado no puede hacer INSERT/UPDATE de precio en `solicitudes_transporte`.
- [x] Las apps actuales siguen funcionando (solo se añadieron columnas y tablas).
- [x] **En desarrollo**, la publicación `supabase_realtime` incluye las 6 tablas de `muevete` (hoy no tiene ninguna; sin esto H4/H5 parecerán rotos). Detalle en [anexo 05 §2.4](05-sincronizacion-bd-repo.md).

**Depende de**: nada. **Riesgo**: alto (esquema y dinero). **Write scope**: `inventtia_muevete/docs/migrations/030-034*`, `docs/plan-taxi-precio-fijo/sql/`.

---

### H1 · Confianza: identidad, vehículos y consentimiento

**Objetivo**: nadie opera sin identidad verificada, y el catálogo de vehículos queda ordenado y con capacidad real.

**Entregables**
- `035_taxi_vehiculos_catalogo.sql`: `vehicle_type.orden` (orden de la lista del cliente), `vehicle_type.pasajeros_max`, `tuktuk` se muestra como **"Triciclo Eléctrico"**, `bicicleta` y `camioneta` pasan a `status=false` (no se borran). `vehiculos.capacidad_int` obligatoria en el alta.
- `036_taxi_identidad_consentimiento.sql`: `poblado` en `users` y `drivers`; `documentos_legales` (codigo, version, hash, vigente_desde) y `consentimientos` (usuario, tipo, version, hash, aceptado, at, ip, user_agent, plataforma); RLS; `fn_usuario_habilitado()`.
- **App cliente/chofer**: selector de cantidad de pasajeros en `route_preview_screen` que filtra por capacidad; pantalla bloqueante "Completa tu perfil" (CI, foto del carnet frente y dorso, provincia/municipio/poblado, dirección, contacto de emergencia, aceptación de documentos legales); gate también en servidor.
- **Superadmin**: orden y capacidad por tipo, visibilidad de tipos, gestión de versiones de los documentos legales y auditoría de consentimientos.
- **Los 41 usuarios existentes**: quedan marcados como perfil incompleto y no pueden publicar ni tomar viajes hasta completarlo (decisión del usuario: bloqueo, no periodo de gracia).

**Criterios de aceptación**
- [x] La lista muestra exactamente **Auto, Minivan, Microbús, Moto, Triciclo Eléctrico**, en ese orden, y el orden es editable desde superadmin sin recompilar.
- [x] Un cliente que pide 6 pasajeros no ve Auto ni Moto: solo Microbús/Minivan.
- [x] Un chofer con 4 plazas registradas no puede tomar un viaje de 5 pasajeros.
- [x] Ningún usuario —nuevo o existente— puede publicar ni tomar un viaje sin CI, fotos del carnet, provincia/municipio/poblado, dirección y consentimiento vigente.
- [x] El gate se aplica en el servidor: invocar la RPC directamente sin consentimiento devuelve error; no se salta con un cliente modificado.
- [x] Cambiar la versión de un documento obliga a re-aceptar y queda auditado con fecha, IP y dispositivo.
- [x] Los 3 documentos legales del seed tienen **texto real**, no el placeholder: cargarlos es bloqueante del cutover.
- [x] El gate se puede suspender desde superadmin (`fn_suspender_bloqueo_identidad`) y al reanudar se vuelve a exigir; `drivers.kyc` no se suspende nunca.

**Depende de**: H0. **Riesgo**: alto (bloquea a todos los usuarios hasta completar el perfil). **Write scope**: `inventtia_muevete/docs/migrations/035-036*`, `inventtia_muevete/lib/screens/common/`, `ventiq_superadmin/lib/screens/muevete/muevete_vehiculos_screen.dart`.

---

### H2 · Seguridad del viaje

**Objetivo**: proteger a chofer y pasajero en un contexto de violencia en la calle, sin prometer lo que la app no puede dar.

**Entregables**
- `037_taxi_seguridad.sql`: contactos de emergencia, eventos de pánico, enlaces de viaje compartido (token, expiración, permisos), incidentes (tipo, severidad, estado, evidencia) y bloqueos.
- **Botón de pánico** visible durante todo el viaje: alerta a contactos con ubicación, datos del viaje y del otro implicado; deja registro.
- **Compartir viaje en vivo**: enlace con token y expiración que muestra el recorrido en tiempo real hasta que termina.
- **Contacto de emergencia obligatorio**: validado en el gate de H1; sin él no se viaja.
- **Verificación mutua visible**: antes de subir, ambas partes ven foto, nombre, tipo de vehículo, chapa y **CI parcial** del otro.
- **Marcado directo al 106** desde el botón de emergencia, además de la alerta in-app.
- **Historial de incidentes y bloqueo**: bandeja en superadmin, estados, reincidencia y lista negra compartida entre choferes.
- Referencia: [`07-seguridad-del-viaje.md`](07-seguridad-del-viaje.md).

**Criterios de aceptación**
- [x] Un pánico disparado sin red queda en cola local y se envía al recuperar conexión, sin perderse.
- [x] El enlace compartido deja de funcionar al terminar o cancelar el viaje y no expone teléfono ni CI completa.
- [x] Un usuario bloqueado por incidente confirmado no puede publicar ni tomar viajes.
- [x] El copy del botón de emergencia deja claro que **no sustituye** a llamar a la policía.
- [x] **Bloqueante de despliegue**: el secreto `seguridad_token_pepper` existe en Vault (o GUC) antes de producción. Sin él, `fn_token_hash` lanza `pepper_no_configurado` y el enlace compartido **falla cerrado**, no abierto. _(En PRUEBAS ya está creado; en producción es el paso 0 de [`ORDEN-PRODUCCION.md`](ORDEN-PRODUCCION.md).)_
- [x] El contacto de emergencia se muestra como **"sin verificar"** mientras no haya proveedor SMS: el OTP nunca se devuelve al cliente en producción.
- [x] El alta de contacto de emergencia exige una **declaración explícita** del usuario de que tiene autorización de esa persona (es el teléfono de un tercero), y queda registrada en `consentimientos`.

**Depende de**: H0, H1. **Riesgo**: alto (datos sensibles y falsos positivos de pánico).

---

### H3 · RPCs de asignación y cierre

**Objetivo**: la lógica crítica vive en el servidor, no en el cliente.

**Entregables**
- `038_taxi_rpc_solicitud.sql`: `fn_crear_solicitud`, `fn_cancelar_solicitud`.
- `039_taxi_rpc_toma.sql`: `fn_viajes_disponibles`, `fn_tomar_viaje` (atómico + deuda + viaje en la misma transacción).
- `040_taxi_rpc_cierre.sql`: `fn_completar_viaje` (comisión configurable + tope + espera), `fn_recargar_wallet`.
- Revocación de escrituras directas de `wallet_*`, `transacciones_wallet`, `viajes`; ajuste de `complete_ride_payment` viejo (deprecarlo y apuntar al nuevo).
- `docs/plan-taxi-precio-fijo/sql/test_concurrencia.sql`.

**Criterios de aceptación**
- [x] Dos sesiones concurrentes llamando `fn_tomar_viaje` sobre la misma solicitud: exactamente una obtiene el viaje.
- [x] `fn_completar_viaje` ignora cualquier precio enviado desde el cliente.
- [x] Comisión sale de `configuracion_tarifas`; cambiar el 15 % a 12 % cambia el neto sin recompilar.
- [x] Chofer con deuda en el tope no ve ni puede tomar viajes; con deuda por debajo, sí.
- [x] Un viaje en efectivo de 1 500 deja `wallet_drivers.balance` en −225 y una fila `comision_viaje`.

**Depende de**: H0, H1, H2. **Riesgo**: crítico (dinero + concurrencia).

---

### H4 · App cliente sin negociación

**Objetivo**: el cliente ve un precio y un solo botón.

**Entregables**
- `route_preview_screen.dart`: quitar `_offerController`/"Tu Oferta"/`_userEditedPrice`; mostrar desglose y botón "Solicitar viaje a $X"; llamar `fn_crear_solicitud`.
- `transport_provider.dart`: eliminar `setOfferPrice`, `_calculatePrice`, `_isInsideCityZone`, `acceptOffer`, `declineOffer`, `_onNewOffer`, `_onOfertaUpdate`, `pollOffers`; reescribir `sendRequest` (RPC), `restore*`, `cancelRequest`; nuevo estado `searchingDriver` con realtime sobre su solicitud.
- `transport_request_service.dart`: fuera `getExistingOffers`/`subscribeToOffers`/`acceptOffer`/canal de ofertas; dentro RPC de cotización/creación y canal de la solicitud.
- `driver_offers_screen.dart`: **eliminar** (archivo, ruta en `main.dart`, imports, push).
- `ride_confirmed_screen.dart`, `request_history_screen.dart`, `home_map_screen.dart`: chofer y precio desde `solicitud`/`viaje`, no desde `acceptedOffer`.
- `background_service.dart`: canal de ofertas → canal de solicitud; notificación "Chofer asignado".
- `constants.dart`: quitar `cityCenter*`/`cityRadiusKm`.
- Widgets nuevos: `price_breakdown.dart`, `searching_driver_sheet.dart`.

**Criterios de aceptación**
- [x] No queda ningún `TextFormField` de precio en el flujo del cliente.
- [x] `flutter analyze` sin errores nuevos; tests del cálculo (cliente muestra exactamente lo que devuelve el servidor). _(Verificado con el analizador del MCP de Dart: 0 errores; `flutter analyze` no corre en este entorno.)_
- [x] `grep -r "precioOferta\|ofertas_chofer\|DriverOffer" lib/` sin resultados en el flujo activo (solo tipos deprecados).

**Depende de**: H3. **Riesgo**: alto (8 pantallas).

---

### H5 · App chofer: lista y toma

**Objetivo**: el chofer toma viajes; no negocia.

**Entregables**
- Nueva pantalla `available_trips_screen.dart` (reemplaza el diálogo de `incoming_requests_screen.dart:305-445` y el duplicado de `driver_home_screen.dart:537-792`).
- Tarjeta `available_trip_card.dart`: tipo · zona · origen · destino · km · cliente paga · **te toca $Y (Z %)** · deuda disponible.
- `incoming_requests_screen.dart`: reescribir; quitar contraoferta y chequeo de saldo; "Tomar viaje" → `fn_tomar_viaje`; manejo de "ya fue tomado".
- `driver_home_screen.dart`: eliminar `_submitOffer` y realtime de oferta aceptada; integrar la lista.
- `driver_service.dart`: eliminar `makeOffer`/`hasExistingOffer`/`subscribeToMyOfferAcceptances`; añadir `viajesDisponibles()`/`tomarViaje()`.
- `background_service.dart` (rama chofer): notificación "Nuevo viaje disponible en tu zona: se cobran $X, te tocan $Y (Z %)".
- `notification_model.dart`/`notification_service.dart`: tipos `viaje_disponible`, `viaje_tomado`; retirar `nueva_oferta`/`oferta_aceptada`.
- `driver_offer_model.dart`, `driver_offer_card.dart`: deprecar.

**Criterios de aceptación**
- [x] Un chofer con wallet en 0 puede tomar un viaje (D6) y su saldo queda en −comisión.
- [x] Con deuda sobre el tope, la lista viene vacía y se muestra el motivo.
- [x] Dos choferes tocando a la vez: uno entra al viaje, el otro ve "Ese viaje ya fue tomado".
- [x] La tarjeta muestra el neto y el % reales (incluido el tope de comisión si aplica).

**Depende de**: H3. **Riesgo**: alto. **Puede ejecutarse en paralelo con H4** (scopes disjuntos: `screens/driver/`, `screens/client/`).

---

### H6 · Superadmin: Zonas y Tarifas

**Objetivo**: el negocio configura el modelo sin tocar código.

**Entregables**
- `lib/screens/muevete/muevete_zonas_screen.dart`: lista + CRUD + estado; formulario de tarifa (modo, fijo, $/km, prioridad, vigencia, activo).
- `lib/screens/muevete/muevete_zona_editor_screen.dart`: editor con `flutter_map` — tocar para añadir vértice, deshacer, cerrar polígono, validar (≥3 puntos, sin auto-intersección), previsualizar con las otras zonas en capas.
- `lib/screens/muevete/muevete_tarifas_config_screen.dart`: parámetros globales de §2.3 + multiplicadores por tipo + simulador.
- `lib/services/muevete_tarifas_service.dart`: CRUD Supabase + RPC de simulación.
- Registro en `app_routes.dart` (`/muevete/zonas`, `/muevete/tarifas`), `main.dart` con `RouteGuard`, y entrada en `app_drawer.dart`. Permisos por rol.
- `muevete_requests_screen.dart`: tab "Ofertas" → histórico de solo lectura.

**Criterios de aceptación**
- [x] Un superadmin dibuja un polígono, guarda, y `fn_cotizar_viaje` lo aplica en < 1 s (realtime o refresco).
- [x] El simulador muestra precio cliente / comisión / neto chofer y qué zona aplicó.
- [x] No se puede guardar un polígono inválido ni una tarifa incoherente (`fijo` sin `monto_fijo`, etc.).
- [x] `flutter analyze` limpio; los cambios de comisión se reflejan sin recompilar la app del chofer. _(Análisis vía MCP de Dart: 0 errores.)_

**Depende de**: H0. **Riesgo**: alto (desarrollo nuevo; no hay precedente útil: `carnaval_geo_admin_screen.dart` es un stub). **Puede ir en paralelo con H2–H5.**

---

### H7 · Dinero, cierre y offline

**Objetivo**: el cierre del viaje no puede ser manipulado y la deuda se controla.

**Entregables**
- `transport_provider.completeRideWithPayment` → `fn_completar_viaje` sin precios del cliente.
- `wallet_service.dart`: comisión desde config; deuda; `fn_recargar_wallet` para el 11 %; eliminar constantes `0.15`.
- `completion_sync_service.dart`: `_syncOne` sin `precio_final`/`precio_base`.
- `trip_completion_qr_service.dart`: payload con `solicitud_id`/`viaje_id` + precio congelado; secreto HMAC fuera del código (variable de entorno / tabla de secretos).
- `wallet_screen.dart` (cliente) y `driver_wallet_screen.dart`: mostrar deuda disponible y usarla; centralizar el 11 %.
- `ride_confirmed_screen.dart`: recibo con desglose congelado.
- `041_taxi_rls_hardening.sql`: revocación de las 8 políticas de §4.3. **Se aplica en el cutover**, nunca antes de que las apps nuevas estén publicadas. **Dependencia crítica descubierta en H1**: al eliminar `drivers_see_solicitudes`, debe crear `solicitudes_select_driver_asignado` (`driver_id = muevete.get_my_driver_id()`), o el chofer dejará de ver el nombre y el teléfono del cliente en su viaje. También debe decidir el destino de `users_select_conductor_asignado`, que hoy evalúa un EXISTS contra `solicitudes_transporte`.

**Criterios de aceptación**
- [x] Cierre online, offline y por QR producen el mismo resultado y rechazan precios manipulados.
- [x] Deuda visible en la billetera del chofer y liquidada automáticamente al recargar.
- [x] Cambiar `comision_pct` en superadmin altera el neto del siguiente viaje sin desplegar apps.

**Depende de**: H3, H4, H5. **Riesgo**: crítico.

---

### H8 · QA integral, compatibilidad y despliegue

**Objetivo**: liberar sin dejar viajes huérfanos ni apps viejas rompiendo el flujo.

**Entregables**
- Matriz E2E manual (adjunta en el anexo 02 §9): cotizar, publicar, tomar, completar, cancelar, sin choferes, fuera de zona, deuda, dos dispositivos.
- Tests automatizados: `dart test` del cálculo espejo, SQL de concurrencia y de RLS, `flutter analyze` en ambas apps.
- Estrategia de versionado forzado con `update_service.dart` + pantalla `versiones` del superadmin (mínimo de versión obligatorio).
- Orden de despliegue documentado y checklist de rollback.
- Tablero de KPIs mínimos (anexo 02 §8): viajes/día, tiempo de asignación p50/p90, % tomados < 60 s, cancelaciones, viajes sin chofer, comisión cobrada, deuda pendiente.

**Criterios de aceptación**
- [x] Ningún viaje abierto queda huérfano al desplegar (script de limpieza/expiración) → [`sql/00_limpieza_pre_cutover.sql`](sql/00_limpieza_pre_cutover.sql).
- [x] Apps viejas quedan bloqueadas por versión mínima antes de retirar `ofertas_chofer` de escritura.
- [ ] Rollback probado — sólo se puede validar **después del primer despliegue** (apagar el flag devuelve el flujo viejo únicamente si `041` no se aplicó).

**Depende de**: H0–H7.

---

## 7. Orden de ejecución y propiedad de archivos

| Hito | Quién | Write scope (disjunto) | Puede ir en paralelo con |
|---|---|---|---|
| H0-A | Lead + responsable de infra | `lib/config/supabase_config.dart` de las 6 apps, GitHub settings, Supabase dashboard | — |
| H0 | Lead + programador | `inventtia_muevete/docs/migrations/030-034*`, `docs/.../sql/` | H0-A |
| H1 | agente identidad | `inventtia_muevete/docs/migrations/035-036*`, `inventtia_muevete/lib/screens/common/`, `ventiq_superadmin/lib/screens/muevete/muevete_vehiculos_screen.dart` | H2 |
| H2 | agente seguridad | `inventtia_muevete/docs/migrations/037*`, `inventtia_muevete/lib/screens/seguridad/`, `inventtia_muevete/lib/services/seguridad_service.dart` | H1 |
| H3 | programador | `inventtia_muevete/docs/migrations/038-040*` | H6 |
| H4 | agente cliente | `inventtia_muevete/lib/screens/client/`, `providers/`, `services/transport_request_service.dart`, `widgets/` | H5, H6 |
| H5 | agente chofer | `inventtia_muevete/lib/screens/driver/`, `services/driver_service.dart`, `background_service.dart` | H4, H6 |
| H6 | agente superadmin | `ventiq_superadmin/lib/screens/muevete/`, `services/`, `config/`, `widgets/` | H3, H4, H5 |
| H7 | programador + Lead | `services/wallet_service.dart`, `completion_sync_service.dart`, `trip_completion_qr_service.dart` | — |
| H8 | Lead (QA) | `docs/`, sin código de producción | — |

**Regla de oro**: **H0, H1 y H2 son bloqueantes de todo lo demás.** H1 y H2 comparten repo pero no archivos (`seguridad/` y `services/seguridad_service.dart` son nuevos). H4 y H5 comparten repo (`inventtia_muevete`) pero no archivos: `background_service.dart` es la única frontera compartida → lo toca **solo** el agente de H5, y H4 le pide cambios por contrato (canal de solicitud). El botón de pánico de H2 se integra en la pantalla de viaje activo de H5 mediante el servicio, no editando la pantalla desde H2.

---

## 8. Compatibilidad y despliegue

1. **H0 es aditivo**: se aplica en producción sin romper las apps actuales (columnas nuevas con default, tablas nuevas, RPCs nuevas).
2. **H3 también**: las RPC nuevas no se usan hasta que la app nueva esté publicada. Las políticas viejas siguen hasta el cutover.
3. **Cutover** (cuando H2–H7 estén verificados):
   - publicar superadmin primero (config lista),
   - publicar app chofer nueva,
   - publicar app cliente nueva,
   - subir versión mínima obligatoria (bloquea apps viejas),
   - recién entonces revocar escrituras viejas y dejar `ofertas_chofer` en solo lectura.
4. **Datos legacy**: `ofertas_chofer` **no se borra** en esta migración (historial, superadmin y conteo de viajes la leen). Se marca deprecada y se limpia en una migración posterior tras el periodo de gracia.
5. **Solicitudes abiertas el día del cutover**: script que expira las `pendiente` con más de 1 h y libera retenciones de wallet.
6. **Rollback**: flag `taxi_precio_fijo_activo` en `configuracion_tarifas` (o tabla de flags). Apagado, las RPC nuevas rechazan crear solicitudes y la app nueva muestra "servicio en mantenimiento".

---

## 9. Verificación (no negociable antes de liberar)

| Nivel | Qué | Cómo |
|---|---|---|
| SQL unitario | `fn_punto_en_poligono` (dentro, fuera, borde), `fn_cotizar_viaje` (14 casos del anexo 03 §8.3), solapes, fallback | `psql`/script en `docs/.../sql/` |
| SQL concurrencia | Doble `fn_tomar_viaje`, doble `fn_completar_viaje` | dos sesiones con `pg_sleep` |
| RLS | cliente no puede UPDATE precio; chofer no ve toda la tabla; wallet no editable | rol `authenticated` simulado |
| Dart unitario | Cálculo espejo en la app coincide con el servidor; formato/redondeo | `dart test` |
| Flutter | `flutter analyze` en `inventtia_muevete` y `ventiq_superadmin` | `$env:APPDATA=...\.dsh\dart-tool` antes de invocar |
| E2E manual | 12 escenarios de la matriz del anexo 02 §9 | dos dispositivos/emuladores |
| Regresión | Flujo de carga, dispatcher y planes intactos | smoke manual |

---

## 10. Riesgos y mitigaciones

| # | Riesgo | Impacto | Mitigación |
|---|---|---|---|
| 1 | **Desintermediación**: con precio fijo y efectivo, cliente y chofer cierran fuera de la app | Alto (ingresos) | Descuento 5 % pagando con wallet; comisión con tope; monitoreo de viajes cancelados y re-publicados |
| 2 | **Combustible**: el fijo 1 500 solo se sostiene hasta ~2 760 CUP/L | Alto | `precio_vigente_desde` + revisión a 30 días; parámetros editables sin recompilar |
| 3 | **Doble asignación** sin RPC atómico | Alto (visible) | `UPDATE ... WHERE estado='pendiente' RETURNING` + pruebas concurrentes en H3 |
| 4 | **Dinero mal cerrado** (comisión, deuda, QR offline) | Crítico | Snapshot congelado; cierre solo en servidor; tests de precios manipulados |
| 5 | **Apps viejas** siguen creando ofertas | Medio | Versión mínima obligatoria antes de revocar escrituras; `ofertas_chofer` en solo lectura |
| 6 | **RLS/SECURITY DEFINER mal cerrados** | Crítico | Validar `auth.uid()` y rol dentro de cada RPC; volcar `pg_policies` real antes de migrar |
| 7 | **Editor de polígonos** inválido rompe la cotización de una ciudad | Medio | Validación geométrica al guardar; zonas inactivas por defecto; simulador previo a activar |
| 8 | **Realtime silencioso** (`vehicle_type` ya está suscrito pero fuera de la publicación) | Medio | Revisar `supabase_realtime` al añadir tablas; prueba de asignación en dos dispositivos |
| 9 | **Elasticidad**: el mínimo sube a 1 500 y cae la demanda | Medio | `precio_corto` 1 000 para <1,5 km; alternativa a fijo 1 200 si cae >25 % en 30 días |
| 10 | **Fricción de KYC**: exigir CI, fotos, poblado y consentimiento a todos —incluidos los 41 existentes— puede tumbar la conversión y dejar la app sin choferes | Alto | El bloqueo impide **operar**, no **registrarse**; guardado progresivo del perfil; pantalla con progreso y motivo claro; flag para suspender el bloqueo si la oferta de choferes cae más del 30 % |
| 11 | **Falso positivo de pánico**: alertas masivas a contactos por toques accidentales | Medio | Confirmación de 10 s cancelable; registro de quién/cuándo; auditoría en superadmin; el botón no llama al 106 automáticamente |
| 12 | **Privacidad y exposición de la CI**: tratar carnet, ubicación en segundo plano (387 k posiciones históricas) y contactos de emergencia sin base legal ni retención definida | Crítico (legal) | Textos revisados por abogado antes de publicar; minimización (CI parcial en la verificación mutua); definir retención y purga del histórico; consentimiento versionado y auditable |
| 13 | **El gate de identidad dependa de un servicio caído** y deje a todos sin poder viajar | Alto | El gate es una función SQL local (sin dependencia externa); el flag de suspensión permite volver al flujo permisivo mientras se corrige |

---

## 11. Decisiones abiertas (no bloquean H0/H1)

| # | Decisión | Propuesta | Quién |
|---|---|---|---|
| A1 | `precio_km` exacto de la zona municipal | 400 CUP/km (equilibrio del auto en 388) | negocio + económico |
| A2 | Tope de deuda definitivo | 1 000 CUP (arranque 500) | económico → confirmar |
| A3 | ¿Se activan Z1–Z9 en el lanzamiento o solo MUN? | solo MUN + FB; el resto se dibuja y activa en el editor | negocio |
| A4 | Comisión de recarga: 11 % → 6 % | bajar en 60 días (hoy el take real en wallet es 26 %) | económico |
| A5 | Recargo nocturno y prima >8 km en el MVP | sí, ya parametrizados | negocio |

---

## 12. Anexos

| Doc | Contenido |
|---|---|
| [`01-analisis-tecnico.md`](01-analisis-tecnico.md) | Flujo actual archivo:línea, 32 puntos de negociación a eliminar, esquema, RLS, impacto |
| [`02-modelo-negocio.md`](02-modelo-negocio.md) | UX y copy exacto, 11 estados, 28 RF con Gherkin, KPIs, casos borde |
| [`03-modelo-economico.md`](03-modelo-economico.md) | Costos, escenarios, comisión, parámetros numéricos, simulación y riesgos económicos |
| [`04-diseno-tecnico.md`](04-diseno-tecnico.md) | DDL completo, RPCs con cuerpo, pantallas del superadmin, pruebas, hitos técnicos |
| [`05-sincronizacion-bd-repo.md`](05-sincronizacion-bd-repo.md) | Inventario real de producción vs repo, delta de funciones/triggers, deuda de seguridad, baseline `030` |
| [`06-aplicar-migraciones.md`](06-aplicar-migraciones.md) | Cómo aplicar H0 en el proyecto dev: orden, verificación por archivo, realtime, rollback |
| [`07-seguridad-del-viaje.md`](07-seguridad-del-viaje.md) | Modelo de amenazas, pánico, compartir en vivo, verificación mutua, incidentes y bloqueos |
| [`08-privacidad-y-consentimiento.md`](08-privacidad-y-consentimiento.md) | Política de privacidad, términos, consentimiento versionado e ineludible |
| [`09-identidad-y-vehiculos.md`](09-identidad-y-vehiculos.md) | DDL de KYC obligatorio, `poblado`, catálogo ordenado y capacidad por vehículo |
| [`10-incidente-credenciales.md`](10-incidente-credenciales.md) | **P0**: evidencia de la clave `service_role` expuesta, alcance del daño y remediación |
| [`11-impacto-cambio-de-clave.md`](11-impacto-cambio-de-clave.md) | Qué se rompe exactamente al pasar a la clave publishable y cómo rotar sin tumbar la app |

---

## 13. Qué se considera "terminado"

1. Un cliente en Santa Clara pide un viaje de 3,3 km y ve **1 500 CUP** sin poder editarlo.
2. Todos los choferes online dentro del polígono de la zona lo ven con **"Cliente paga $1 500 · Te toca $1 275 (15 %)"**.
3. El primero que toca lo toma; el segundo ve "ya fue tomado".
4. El viaje se completa, el cliente paga (efectivo o wallet) y el chofer queda con la comisión descontada (o en deuda controlada).
5. El superadmin cambia el fijo a 1 200 o la comisión a 12 % y el siguiente viaje lo refleja **sin tocar código**.
6. `flutter analyze` limpio en ambas apps y las pruebas SQL de concurrencia y RLS en verde.

---

## 14. Diseño de vistas con Stitch (MCP de Google)

**Decisión**: cuando una vista del flujo nuevo haya que **rediseñarla o crearla**, se usa primero el **MCP de Stitch** para tener una propuesta visual, y después se traduce a Flutter. No se codifica a ciegas una pantalla nueva.

### 14.1 Proyectos que ya existen (no improvisar)

| Proyecto Stitch | Para qué sirve |
|---|---|
| `projects/902923221769817209` — **"Home Map and Transport Selection"** | **Es el canónico para el cliente.** Tema oscuro, `PLUS_JAKARTA_SANS`, color `#195de6`: coincide exactamente con `AppTheme.primaryColor = #195DE6` y `GoogleFonts.plusJakartaSans`. Aquí se itera el flujo de taxi del cliente |
| `projects/2045399073654688586` — "Live Fleet Tracking Map" | referencia para mapa en vivo y seguimiento |
| `projects/14424237441394435194` — "Muevete Freight Dashboard" | **es de carga**, no de taxi. Tiene su propia guía en [`docs/stitch_muevete_freight_dashboard/DESIGN.md`](../../inventtia_muevete/docs/stitch_muevete_freight_dashboard/DESIGN.md). No se mezcla |
| `projects/16198842290239951724` — "Pantalla de Login" | referencia de registro/entrada |

### 14.2 Regla de oro del tema

El diseño **no inventa identidad visual**. Se configura Stitch con los tokens que la app ya usa:

```
primario   #195DE6   (AppTheme.primaryColor)
fuentes    Plus Jakarta Sans (títulos y body)
radios     8 / 14 / 16
superficies  claro #F5F7FA / #FFFFFF · oscuro #0F1117 / #1A1D27 / #222636
semánticos   success #22C55E · warning #FBBF24 · error #EF4444 · info #3B82F6
```

Si una propuesta de Stitch trae otra paleta o tipografía, **se descarta** o se ajusta: la consistencia con las 6 apps restantes pesa más que una pantalla bonita.

### 14.3 Qué se rediseña y en qué hito

| Hito | Vistas | Por qué |
|---|---|---|
| **H1** | Onboarding de identidad: CI + carnet frente/dorso + provincia/municipio/poblado; pantalla de documentos legales y consentimiento | es un embudo nuevo y sensible; la conversión se gana o se pierde aquí |
| **H4** | Desglose del precio (zona, km, multiplicador, total); "buscando chofer"; viaje confirmado con verificación mutua | es el cambio de producto más visible: el cliente deja de escribir el precio |
| **H5** | Tarjeta de viaje disponible (**"Cliente paga $X · Te toca $Y (Z %)"**); viaje activo con pánico **discreto** y compartir en vivo | el chofer decide en segundos; el neto debe leerse de un vistazo |
| **H6** | Editor de polígonos, tarifas y simulador en superadmin | no hay precedente en el repo (`carnaval_geo_admin_screen.dart` es un stub) |

### 14.4 Flujo de trabajo

1. Cargar la skill `stitch-loop` (o `enhance-prompt` para afinar el prompt) antes de generar.
2. Prompt con el **modelo de datos real** de la pantalla (campos, estados vacío/carga/error, copy en español ya definido en el anexo 02).
3. Iterar en el proyecto `902923221769817209` (cliente). Para superadmin, crear proyecto nuevo con la paleta de `ventiq_superadmin`.
4. Descargar HTML + captura y guardarlas junto al hito (`docs/plan-taxi-precio-fijo/diseno/`).
5. Traducir a Flutter **a mano** (Stitch entrega HTML/CSS, no Dart): usar `AppTheme`, `GoogleFonts.plusJakartaSans` y los widgets que ya existen (`MapWidget`, `DraggableScrollableSheet`, `WalletBalanceCard`…).
6. Verificar con `flutter analyze` y en dispositivo real, no solo en el editor.

### 14.5 Guardrails (evitar el "look genérico de IA")

- Nada de *lorem ipsum* en la entrega: los textos salen del anexo 02.
- Todas las pantallas con **estado vacío, carga y error**, no solo el camino feliz.
- Contraste AA mínimo; el **botón de pánico ≥ 48 dp** y accesible con una mano.
- Modo claro y oscuro: la app tiene `ThemeProvider.isDark` y las dos variantes se revisan.
- Ancho de referencia **360 dp**; probar con texto largo en español ("Triciclo Eléctrico", "Reparto Virginia").
- No rediseñar lo que ya funciona (mapa, wallet, historial) salvo que el hito lo pida.

### 14.6 Criterio de aceptación

- [ ] Diseño en Stitch previo a cada vista — se hizo en las vistas principales (viajes disponibles, confirma tu viaje, buscando conductor, editor de zonas); identidad y seguridad se implementaron directamente con los tokens de `AppTheme`.
- [x] La traducción a Flutter usa solo tokens de `AppTheme` (cero colores sueltos `Color(0xFF…)` nuevos).
- [x] HTML y captura de cada diseño quedan guardados en `docs/plan-taxi-precio-fijo/diseno/`.
- [x] Coste asumido: ~0,5 sesión por pantalla para la traducción manual a Flutter.