# 01 — Inventario de monetización actual en GoReserva (`inventtia_flow`)

**Fecha del informe:** 29-10-2026.
**Alcance:** app `inventtia_flow/` (paquete `inventtia_flow`, "GoReserva"), panel `ventiq_superadmin/` en su parte "Flow", y el schema `flow` de Supabase.
**Objetivo:** inventario factual, verificado y citado de **qué se cobra hoy, a quién, con qué rail y en qué punto exacto del código/SQL**, más los puntos de inserción candidatos para cobrar al cliente final. No es una propuesta de producto.

**Método y límites**

- Lectura estática del repo (glob/grep/read). Cada afirmación técnica lleva `ruta:línea`.
- Verificación contra la **base de datos viva** vía el MCP de Supabase de esta sesión (solo `select`, sin escrituras): tablas, columnas, funciones (`pg_proc`), triggers, cron (`cron.job`), Edge Functions y conteos. El `entrypoint_path` de las Edge Functions listadas contiene el ref `vsieeihstajlrdvpuooh`, que según `inventtia_flow/PLAN_PRECIOS_PAGOS_CALENDARIO.md:4` es el proyecto **release** (el otro, debug, es `qhprswhhfasrikhawjoz`).
- Los datos de negocio citados (conteos, precios de planes) son los que devolvió la BD en ese momento; se marcan como **verificado en BD** para distinguirlos de lo que solo está en el repo.
- No se ejecutó `flutter analyze` ni tests (fuera de alcance). No se modificó ningún archivo del repo salvo este.

> Hallazgo transversal que cambia la premisa del encargo: **el cobro al cliente final ya existe y está en producción**. La migración 62 crea un circuito completo de "pago por adelantado del servicio" (Transfermóvil del admin + verificación manual), la 67 lo habilita servicio a servicio y la 68/69/71 lo endurecen. En la BD consultada hay 10 intentos de pago de reservas (4 verificados). Lo que **no** existe es cualquier fee/comisión para la plataforma ni ningún cobro al consumidor por usar la app.

---

## 0. Resumen ejecutivo (lo que hay / lo que no)

| # | Hecho | Evidencia |
|---|---|---|
| 1 | El único cobro **a la plataforma** hoy es la **suscripción de la ENTIDAD** (negocio), por días de plan | `inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:245`; `inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:166` |
| 2 | El rail es **deep link de Transfermóvil + confirmación manual del superadmin**; no hay pasarela, ni webhook, ni callback | `inventtia_flow/lib/screens/admin/mi_suscripcion_screen.dart:16`; `inventtia_flow/lib/services/suscripcion_service.dart:110` |
| 3 | Los planes hoy tienen precios de prueba: **1, 2 y 3 CUP** (30/90/365 días) y `modo_prueba = true` | verificado en BD (`flow.suscripcion_plan`, `flow.suscripcion_config`) |
| 4 | Ya existe cobro **al cliente final**: "pago por adelantado de la reserva" con el Transfermóvil **del propio negocio** | `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:1-48` |
| 5 | Ese cobro es **opcional y posterior** a reservar: la reserva nace gratis y sigue ocupando turno sin pagar | `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:34-38`; `inventtia_flow/lib/screens/local_servicio_detail_screen.dart:702` |
| 6 | Está activo en **2 entidades** (una cobra en CUP y otra en USD), 24 h de vigencia | verificado en BD (`flow.cobro_config`) |
| 7 | Hay **10 intentos de pago de reserva**: 4 verificados, 3 rechazados, 2 expirados, 1 anulado | verificado en BD (`flow.reserva_pago`) |
| 8 | **No existe** fee de servicio, comisión, take rate, ledger de ingresos de plataforma ni plan premium de consumidor | grep de `comisi|take.rate|premium` en `inventtia_flow/` no devuelve implementación; solo textos/iconos |
| 9 | Existe infraestructura monetizable **sin explotar comercialmente**: promociones, campañas patrocinadas, fidelidad, métricas de entidad, outbox de WhatsApp | sección 3 |
| 10 | La automatización es parcial: hay cron de suscripciones cada 15 min, **no** hay cron de expiración de pagos de reserva | verificado en BD (`cron.job`); `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:23-25` |

---

## 1. Modelo de cobro vigente: B2B (la entidad paga su suscripción)

### 1.1 Quién paga, por qué concepto y a quién

- **Sujeto que paga:** la **entidad** (negocio). No el cliente final. Decisión cerrada en `inventtia_flow/PLAN_SUSCRIPCIONES.md:109` ("Por `entidad`").
- **Concepto:** días de acceso a la plataforma (`trial | activa | en_gracia | vencida | sin_plan | suspendida | cancelada`), con libro mayor append-only de movimientos. Ver `inventtia_flow/lib/models/suscripcion.dart:17-49` y `inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:251-267`.
- **A quién le paga:** a la plataforma, al **número de proveedor de Transfermóvil** configurado globalmente por el superadmin (`flow.suscripcion_config.transfermovil_numero_proveedor`), plantilla en `inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:172-177`.
- **Cómo se acredita:** manualmente. La app solo *reporta* el pago; el superadmin lo verifica contra el banco y ahí se acreditan los días: `inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:609-703`.
- **Qué pasa si no paga:** `flow.entidad_activa()` decide si la entidad es visible/reservable; sin fila de suscripción devuelve `true` (grandfathering, no se apaga a nadie por la migración). Ver `inventtia_flow/docs/flow_schema/migraciones/44_suscripciones_predicado_trial.sql:84-113` y el consumidor de ese predicado `inventtia_flow/docs/flow_schema/migraciones/44_suscripciones_predicado_trial.sql:126-146`.

**Precios vigentes (verificado en BD el 29-10-2026):**

| id | código | nombre | días | precio | moneda | activo |
|---|---|---|---|---|---|---|
| 1 | `flow_mensual` | Mensual | 30 | 1.00 | CUP | sí |
| 2 | `flow_trimestral` | Trimestral | 90 | 2.00 | CUP | sí |
| 3 | `flow_anual` | Anual | 365 | 3.00 | CUP | sí |

Configuración global (verificado en BD, fila única `flow.suscripcion_config`): `trial_meses_default=3`, `trial_auto=true`, `trial_por_usuario=true`, `dias_gracia=7`, `dias_aviso_previo=7`, `whatsapp_notif_activa=false`, `whatsapp_bot_activo=false`, `moneda_default=CUP`, `intent_horas_vigencia=24`, **`modo_prueba=true`**, número de proveedor configurado. Es decir: **el circuito está vivo pero en modo prueba y con precios simbólicos**. El seed de planes nacía desactivado a propósito (`inventtia_flow/docs/flow_schema/migraciones/46_suscripciones_admin_cron_seed.sql:17-23`); en la BD consultada ya están activos.

### 1.2 Circuito completo (5 pasos, ninguno acredita solo)

Documentado en `inventtia_flow/lib/screens/admin/mi_suscripcion_screen.dart:16-30` y `inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:1-60`.

1. **Elegir plan** → `flow.cliente_crear_intent_suscripcion(p_id_entidad, p_id_plan)`: crea `flow.suscripcion_intent`, arma el deep link y devuelve `url_intent`/`url_http` (`inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:166-275`). La autorización la decide el servidor con `auth.uid()` y `_susc_caller_ve_entidad` (`inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:103-124`).
2. **Abrir Transfermóvil** con `url_launcher`; si el esquema `transfermovil://` falla se intenta el respaldo https y, si tampoco, se muestran los datos para pagar a mano (`inventtia_flow/lib/screens/admin/mi_suscripcion_screen.dart:298-335`, `:337-400`). **No hay callback:** el regreso se detecta por ciclo de vida (`inventtia_flow/lib/screens/admin/mi_suscripcion_screen.dart:85-97`).
3. **"Ya he pagado"** → `flow.cliente_reportar_pago_suscripcion`: exige `codigo_confirmacion` (único) y deja la transacción en `reportado`; avisa al dueño y encola WhatsApp (`inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:282-427`; cliente en `inventtia_flow/lib/screens/admin/mi_suscripcion_screen.dart:453-495`).
4. **Soporte por WhatsApp:** deep link `wa.me` con mensaje redactado por el servidor (`inventtia_flow/lib/services/suscripcion_service.dart:150-174`; uso en `inventtia_flow/lib/screens/admin/mi_suscripcion_screen.dart:549-570`). **No hay bot:** el outbox queda `omitida` si no hay emisor (`inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:116-157`).
5. **Superadmin verifica** → `flow.admin_suscripcion_aprobar_pago`: suma los días del plan, escribe el movimiento y notifica (`inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:609-700`). Acciones del panel en `ventiq_superadmin/lib/services/suscripcion_admin_service.dart:78-124` y botones en `ventiq_superadmin/lib/screens/flow_suscripcion_detalle_screen.dart:110-141`.

### 1.3 Tablas del modelo de suscripción (todas en `flow`)

| Tabla | Para qué | Definición |
|---|---|---|
| `flow.suscripcion_config` | Fila única: trial, gracia, soporte, plantillas Transfermóvil, modo prueba | `inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:128-194` |
| `flow.suscripcion_plan` | Planes comerciales (días, precio, moneda, `limites jsonb`) | `inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:210-230` |
| `flow.suscripcion` | Suscripción viva/histórica por entidad (único índice parcial de fila viva) | `inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:245-285` |
| `flow.suscripcion_intent` | Intento de pago; `id_transaccion` único; inmutable como evidencia | `inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:301-320` |
| `flow.suscripcion_transaccion` | Pago reportado; `codigo_confirmacion` UNIQUE (anti doble acreditación); un intent ↔ una transacción | `inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:338-361` |
| `flow.suscripcion_movimiento` | Libro mayor append-only de días | `inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:381-395` |
| `flow.suscripcion_notificacion` | Outbox in-app/WhatsApp con estado `pendiente|enviada|fallida|omitida` | `inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:405-424` |

RLS: lectura para dueño/admin de la entidad y superadmin; escritura solo por RPC `security definer` (`inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:438-604`).

**Estado en BD (29-10-2026):** 11 suscripciones (9 `activa`, 2 `trial`), 4 intents, 3 transacciones (2 verificadas + **1 reportada esperando verificación**), 13 movimientos, 5 avisos en outbox.

### 1.4 RPC de suscripción (inventario)

| Función | Archivo:línea | Qué hace | La llama |
|---|---|---|---|
| `cliente_estado_suscripcion` | `inventtia_flow/docs/flow_schema/migraciones/44_suscripciones_predicado_trial.sql:259` | Estado derivado de fechas + plan + días restantes | app cliente (`inventtia_flow/lib/services/suscripcion_service.dart:55-63`) |
| `cliente_planes_suscripcion` | `inventtia_flow/docs/flow_schema/migraciones/44_suscripciones_predicado_trial.sql:398` | Planes activos | `inventtia_flow/lib/services/suscripcion_service.dart:69-80` |
| `cliente_crear_intent_suscripcion` | `inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:166` | Crea intento + deep link | `inventtia_flow/lib/services/suscripcion_service.dart:99-108` |
| `cliente_reportar_pago_suscripcion` | `inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:282` | "Ya he pagado" (no acredita) | `inventtia_flow/lib/services/suscripcion_service.dart:116-131` |
| `cliente_mis_pagos_suscripcion` | `inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:428` | Intents + pagos + movimientos | `inventtia_flow/lib/services/suscripcion_service.dart:83-91` |
| `cliente_marcar_intent_abierto` | `inventtia_flow/docs/flow_schema/migraciones/46_suscripciones_admin_cron_seed.sql:72` | Telemetría de embudo | `inventtia_flow/lib/services/suscripcion_service.dart:137-148` |
| `admin_suscripcion_aprobar_pago` | `inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:609` | Verifica + acredita días + notifica | `ventiq_superadmin/lib/services/suscripcion_admin_service.dart:78-90` |
| `admin_suscripcion_rechazar_pago` | `inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:705` | Rechaza con motivo obligatorio | `ventiq_superadmin/lib/services/suscripcion_admin_service.dart:93-102` |
| `_susc_acreditar_dias` | `inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:520` | Aritmética única de acreditación | interno |
| `admin_suscripcion_acreditar` | `inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:764` | Acredita a mano (cortesía/ajuste) | `ventiq_superadmin/lib/services/suscripcion_admin_service.dart:108-124` |
| `suscripcion_expirar` | `inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:846` | Barrido: vence, avisa, suspende | cron cada 15 min (ver 1.6) |
| `admin_suscripcion_listar` / `detalle` / `inicializar` / `suspender` / `reactivar` | `inventtia_flow/docs/flow_schema/migraciones/46_suscripciones_admin_cron_seed.sql:109`, `:248`, `:348`, `:407`, `:451` | Panel superadmin | `ventiq_superadmin/lib/services/suscripcion_admin_service.dart:55-148` |
| `admin_planes_listar/grabar/eliminar` | `inventtia_flow/docs/flow_schema/migraciones/46_suscripciones_admin_cron_seed.sql:512`, `:546`, `:623` | CRUD de planes | `ventiq_superadmin/lib/services/suscripcion_admin_service.dart:152-191` |
| `admin_config_obtener/guardar` | `inventtia_flow/docs/flow_schema/migraciones/46_suscripciones_admin_cron_seed.sql:658`, `:684` | Config global | `ventiq_superadmin/lib/services/suscripcion_admin_service.dart:195-209` |
| `admin_notificaciones_pendientes/marcar` | `inventtia_flow/docs/flow_schema/migraciones/46_suscripciones_admin_cron_seed.sql:735`, `:768` | Despachador (previsto para WAPI) | — (no hay despachador Flow, ver 3.6) |

### 1.5 Superficie Flutter de la suscripción (app de la entidad)

- Modelos: `inventtia_flow/lib/models/suscripcion.dart:17` (estados), `:93` (estado de la entidad), `:200` (plan), `:280` (intent), `:406` (pago), `:476` (movimiento), `:537` (agregado).
- Servicio: `inventtia_flow/lib/services/suscripcion_service.dart:41-214` (contrato `{ok, data|error}` y tolerancia a esquema ausente).
- Provider global (aviso de impago en toda la app): `inventtia_flow/lib/providers/suscripcion_provider.dart:16-167`; el aviso se monta en `inventtia_flow/lib/screens/home_shell.dart:670` y en la pantalla `inventtia_flow/lib/screens/admin/mi_suscripcion_screen.dart:662`.
- Pantalla "Mi suscripción": `inventtia_flow/lib/screens/admin/mi_suscripcion_screen.dart:16-30` (contrato) y `:111-134` (elegir plan). Entrada desde Gestión: `inventtia_flow/lib/screens/admin/gestion_screen.dart:469-475`.
- Tolerancia a migraciones no aplicadas: `inventtia_flow/lib/utils/esquema_pendiente.dart:21-37` (PGRST202/205, 42P01) y `inventtia_flow/lib/services/suscripcion_service.dart:209-211`.

### 1.6 Superficie del panel superadmin

- Rutas/menú: `ventiq_superadmin/lib/config/app_routes.dart:57-59`, `ventiq_superadmin/lib/widgets/app_drawer.dart:269-278`, `ventiq_superadmin/lib/main.dart:266-268`.
- Servicio: `ventiq_superadmin/lib/services/suscripcion_admin_service.dart:1-237` (todo exige `public.fn_is_superadmin_full_access()` en servidor, `:3-13`).
- Pantallas: bandeja `ventiq_superadmin/lib/screens/flow_suscripciones_screen.dart:9`, ficha `ventiq_superadmin/lib/screens/flow_suscripcion_detalle_screen.dart:15-16`, planes `ventiq_superadmin/lib/screens/flow_planes_screen.dart:4`, config `ventiq_superadmin/lib/screens/flow_config_screen.dart:4`.
- Verificar/rechazar/acreditar desde la ficha: `ventiq_superadmin/lib/screens/flow_suscripcion_detalle_screen.dart:110-160`, `:654-724`.

### 1.7 Automatización real (verificado en BD)

- `pg_cron` job `flow-suscripciones-expirar`, schedule `*/15 * * * *`, activo → `select flow.suscripcion_expirar();` (verificado en `cron.job`; el cron se instala en `inventtia_flow/docs/flow_schema/migraciones/46_suscripciones_admin_cron_seed.sql:16`).
- El corte real **no depende del cron**: lo decide `entidad_activa` comparando fechas (`inventtia_flow/docs/flow_schema/migraciones/44_suscripciones_predicado_trial.sql:96-98`).
- **No hay** cron ni trigger para `flow.reserva_pago_expirar` (ver §2.6).

### 1.8 Lo que NO existe en este modelo

- **No hay pasarela ni webhook**: el único rail es el deep link de Transfermóvil y la verificación humana. No hay confirmación automática de pago en ningún punto (`inventtia_flow/lib/services/suscripcion_service.dart:110-115` lo dice explícitamente: el RPC no acredita nada).
- **No hay cobro recurrente automático**: cada renovación es un intento nuevo + verificación manual.
- **No hay reembolsos** ni estados de reembolso en `suscripcion_transaccion` (`inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:352-353`).
- **No hay facturación/recibo** (ni tabla, ni PDF, ni numeración fiscal).
- **No hay bot de WhatsApp**: `whatsapp_bot_activo=false` en BD y `inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:153-158`.

---

## 2. Flujo completo de una reserva/turno de cliente final

### 2.1 Las dos formas de obtener una reserva

**A) Reserva directa (sin cola).** El cliente elige día/cupo/turno y se llama a `flow.cliente_reservar_directo`. Flutter: `inventtia_flow/lib/services/agenda_service.dart:129-171`; pantalla: `inventtia_flow/lib/screens/local_servicio_detail_screen.dart:500-604`, confirmación `:606-707`. SQL (cuerpo desplegado, verificado con `pg_get_functiondef`): valida disponibilidad, descuenta cupo (`_descontar_tramos_turno`, `inventtia_flow/docs/flow_schema/migraciones/17_fix_descontar_tramos_turno_sin_delete.sql:22` o `plan_servicios` legacy), **calcula el precio en servidor** y lo persiste en `flow.agenda.precio_total`/`moneda` (ver 2.2). Devuelve `data.id_agenda` y `data.precio_total`, pero **el wrapper Dart lo descarta** (`inventtia_flow/lib/services/agenda_service.dart:164-167`: solo mira `json['ok']`), por eso el cobro resuelve el id con otra consulta (`inventtia_flow/lib/services/cobro_service.dart:217-243`).

**B) Cola / lista de espera.** El cliente se anota con `flow.cliente_entrar_sala_espera_reserva`. Flutter: `inventtia_flow/lib/services/lista_service.dart:14-40`. SQL (verificado desplegado): inserta en `flow.sala_espera`, con bloqueo por servicio y antifraude (`flow.sala_espera_fraude`), y **no calcula ningún precio ni crea agenda**. Cuando se libera cupo, el bot convierte la cola en reserva: `flow.bot_procesar_recurso_dia` (`inventtia_flow/docs/flow_schema/migraciones/29_bot_promociones.sql:353`) / `flow.bot_procesar_plan` (`:119`), que **sí** insertan `precio_total` y `moneda` (`inventtia_flow/docs/flow_schema/migraciones/29_bot_promociones.sql:211-233`, `:476-496`). El bot se dispara al liberar cupo por trigger diferido `trg_agenda_bot_al_cancelar` (`inventtia_flow/docs/flow_schema/migraciones/66_bot_al_cancelar_reserva.sql:43`).

### 2.2 Dónde se calcula el precio (una sola fuente real: el servidor)

**Servidor = fuente de verdad del precio que se cobra:**

- Precio de lista del servicio: `flow.calcular_precio_reserva` (`inventtia_flow/docs/flow_schema/migraciones/15_servicio_precio.sql:27`, redefinida en `inventtia_flow/docs/flow_schema/migraciones/51_precio_turno_con_reglas.sql:189`).
- Precio del turno (transporte/recursos): `flow.calcular_precio_turno` (`inventtia_flow/docs/flow_schema/migraciones/21_precio_turno.sql:8`, redefinida en `inventtia_flow/docs/flow_schema/migraciones/51_precio_turno_con_reglas.sql:221`), que cae al del servicio si el turno no trae `precios` (`inventtia_flow/docs/flow_schema/migraciones/21_precio_turno.sql:36-50`).
- Reglas por datos adicionales: `flow.calcular_precio_con_reglas` (`inventtia_flow/docs/flow_schema/migraciones/51_precio_turno_con_reglas.sql:46`).
- Descuento por promoción: `flow._resolver_promocion` (`inventtia_flow/docs/flow_schema/migraciones/27_promociones.sql:190`) aplicado por `_aplicar_promocion` (`:261`) / `_precio_con_promocion` (`:330`), con consumo atómico de cupo.
- Descuento por beneficio de bienvenida (una vez por usuario): `flow._beneficio_bienvenida_aplicable` (`inventtia_flow/docs/flow_schema/migraciones/34_beneficio_bienvenida_precio.sql:102`), aplicado **después** de la promo.
- Cotización para pantalla: `flow.cotizar_reserva` (`inventtia_flow/docs/flow_schema/migraciones/27_promociones.sql:367`, redefinida en `inventtia_flow/docs/flow_schema/migraciones/34_beneficio_bienvenida_precio.sql:158`), `stable` y `security definer`; **es la misma resolución** que luego cobra `cliente_reservar_directo` (comentario en `inventtia_flow/lib/services/promocion_service.dart:91-96`). Flutter: `inventtia_flow/lib/services/promocion_service.dart:196-224`, usado en la hoja de reserva `inventtia_flow/lib/screens/local_servicio_detail_screen.dart:2643-2669`.

**Dart = solo presentación/preview (no cobra):**

- `inventtia_flow/lib/utils/precio_reserva.dart:19-81` replica la resolución base+reglas para **mostrar**; su propio doc advierte que debe coincidir con `flow.calcular_precio_con_reglas` (`:25-31`). Usos: preview del admin (`inventtia_flow/lib/screens/admin/reservas_screen.dart:2078-2083`, `inventtia_flow/lib/screens/admin/admin_reserva_transporte_sheet.dart:158-166`) y hoja de transporte del cliente (`inventtia_flow/lib/screens/reserva_transporte_sheet.dart:158-166`).
- `inventtia_flow/lib/utils/precio_reserva.dart:101-118` (`precioBaseDe`/`etiquetaPrecioBase`): precio de tarjeta en catálogo/ficha/favoritos; si no hay precio dice "Consultar", nunca 0.
- `inventtia_flow/lib/models/config_precio.dart:101-177`: parsea la columna `app_dat_servicios.config_precio` (jsonb: `moneda_default`, `monedas`, `precios_base`, `reglas`). Definición SQL de la columna en `inventtia_flow/docs/flow_schema/migraciones/15_servicio_precio.sql:10-22`. Monedas soportadas: `USD, EUR, CUP, MLC` (`inventtia_flow/lib/models/config_precio.dart:18`).
- `inventtia_flow/lib/utils/precio_turno.dart:14-21`: resuelve `turno.precios[moneda]` con respaldo a la moneda por defecto, idéntico a `calcular_precio_turno` (columna en `inventtia_flow/docs/flow_schema/migraciones/21_precio_turno.sql:2-6`).
- `inventtia_flow/lib/utils/parse_monto.dart:23-74`: normaliza lo que teclea el admin (`1.500`→1500, `18.5`→18.5). **No** participa en el precio que se cobra; es entrada de formularios (`inventtia_flow/lib/widgets/precios_servicio_editor.dart:269`, `:289`, `:497`; `inventtia_flow/lib/screens/admin/config_recursos_screen.dart:1630`, `:1883`).
- Conversión por tasa ("el toque"): el precio automático se calcula en el editor del admin con `flow.tasa_factor`/`tasas_actuales` (`inventtia_flow/docs/flow_schema/migraciones/60_tasa_cambio_y_precio_config.sql:133`, `:170`) vía `inventtia_flow/lib/utils/conversion_precio.dart:1-9` y `inventtia_flow/lib/services/tasa_cambio_service.dart:6-27` (Edge Function `flow-tasas` + respaldo `pg_net`). **La conversión del precio mostrado se persiste como precio por moneda**; el cobro solo reconvierte si la moneda del cobro difiere (ver 2.3).

### 2.3 Dónde se guarda el precio y qué se cobra

- Al crear la reserva, el precio queda en `flow.agenda.precio_total` + `agenda.moneda` (definición `inventtia_flow/docs/flow_schema/migraciones/15_servicio_precio.sql:13-22`; escritura en `cliente_reservar_directo` y en el bot, ver 2.1).
- El cobro por adelantado toma **ese total** y lo convierte a la moneda del cobro con la tasa cacheada: `flow._monto_cobro_reserva` (`inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:151-195`). En CUP redondea a pesos enteros (`:186-189`).
- Parche reciente: si la reserva tiene `precio_total = 0/NULL`, `flow.cliente_crear_pago_reserva` lo **recalcula desde los datos** de la reserva (turno/servicio/cantidad/datos adicionales) y lo persiste: `flow._precio_agenda_desde_datos` (`inventtia_flow/docs/flow_schema/migraciones/71_monto_cobro_desde_datos.sql:60-114`) y el bloque de auto-corrección (`:192-209`). Está desplegado (verificado en BD: la función existe y la de crear pago la referencia).
- **Estado real del dato (verificado en BD):** 119 de 168 filas de `flow.agenda` tienen `precio_total > 0`; 49 no. La cabecera de la migración 71 documenta el caso encontrado el 29-10-2026: reservas ids 304-315 todas con `precio_total = 0` y el cobro fallando con "Esta reserva no tiene precio configurado" (`inventtia_flow/docs/flow_schema/migraciones/71_monto_cobro_desde_datos.sql:6-23`).

### 2.4 ¿Hoy se cobra algo al reservar? No.

- La reserva **nace gratis** y con el turno ocupado: `agenda.id_estado` sigue siendo `Reservado` aunque haya pago pendiente (`inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:34-38`).
- El pago por adelantado es **opcional** y se ofrece **después** de reservar (o desde "Mis reservas" si quedó pendiente): `inventtia_flow/lib/screens/local_servicio_detail_screen.dart:702-706` y `:711-807`. Hoja del cliente: `inventtia_flow/lib/widgets/pago_adelantado_sheet.dart:14-33`.
- Quién cobra: **el admin de la entidad**, a *su* número de proveedor de Transfermóvil, con *su* WhatsApp de verificación. La config es **por entidad** (`flow.cobro_config`, PK `id_entidad`): `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:52-76`. **La plataforma no toca ese dinero.**
- El interruptor es doble: entidad (`cobro_config.activo`) **y** servicio (`app_dat_servicios.cobro_adelantado`): `inventtia_flow/docs/flow_schema/migraciones/67_cobro_por_servicio.sql:46-95`; guarda a nivel de fila en `trg_reserva_pago_servicio_cobra` (`:99-132`).

**Estado en BD (29-10-2026):** `flow.cobro_config` tiene 2 filas, ambas `activo=true` (id_entidad 7 cobra en CUP, id_entidad 9 en USD), 24 h de vigencia, `cancelar_si_expira=true`, ambas con número de proveedor. `flow.reserva_pago` tiene 10 filas: 4 `verificado`, 3 `rechazado`, 2 `expirado`, 1 `anulado`. Es decir, el circuito se usó de verdad, con verificación manual.

### 2.5 Superficie de datos y UI del pago de reserva

| Pieza | Ruta:línea |
|---|---|
| Tabla config por entidad + tabla intento | `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:52`, `:81` |
| Columnas de pago en `agenda` | `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:131-145` |
| `cliente_cobro_info` (disponibilidad) | `inventtia_flow/docs/flow_schema/migraciones/67_cobro_por_servicio.sql:46` |
| `cliente_crear_pago_reserva` (crea intento + link) | `inventtia_flow/docs/flow_schema/migraciones/71_monto_cobro_desde_datos.sql:127` |
| `cliente_reportar_pago_reserva` (endurecida en 68) | `inventtia_flow/docs/flow_schema/migraciones/68_anular_pago_al_cancelar.sql:312` |
| `cliente_pago_reserva` (estado) | `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:587` |
| `admin_cobro_config_get/set` | `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:199`, `:240` |
| `admin_listar_pagos_reserva` | `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:646` |
| `admin_verificar_pago_reserva` | `inventtia_flow/docs/flow_schema/migraciones/68_anular_pago_al_cancelar.sql:215` |
| `admin_rechazar_pago_reserva` | `inventtia_flow/docs/flow_schema/migraciones/68_anular_pago_al_cancelar.sql:462` |
| `reserva_pago_expirar` | `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:830` |
| Trigger de anulación al cancelar | `inventtia_flow/docs/flow_schema/migraciones/68_anular_pago_al_cancelar.sql:157-211` |
| `_cobro_disponible` + campo por ticket | `inventtia_flow/docs/flow_schema/migraciones/69_cobro_disponible_en_agendas.sql:65`, `:85-176` |
| Realtime de `reserva_pago` | `inventtia_flow/docs/flow_schema/migraciones/70_realtime_cobro.sql:114` (verificado en BD: `relreplident='f'`) |
| Modelos Dart | `inventtia_flow/lib/models/cobro.dart:22`, `:128`, `:185`, `:378` |
| Servicio Dart | `inventtia_flow/lib/services/cobro_service.dart:25-294` |
| Hoja del cliente | `inventtia_flow/lib/widgets/pago_adelantado_sheet.dart:34-411` |
| Config del admin | `inventtia_flow/lib/screens/admin/cobro_config_screen.dart:8-19` |
| Bandeja de verificación | `inventtia_flow/lib/screens/admin/pagos_reserva_screen.dart:10-209` |
| Chip/botón en "Mis reservas" | `inventtia_flow/lib/utils/estado_pago.dart:16-90`; `inventtia_flow/lib/screens/mis_tickets_screen.dart:37-50`, `:240-280` |
| Entrada admin (config + bandeja) | `inventtia_flow/lib/screens/admin/mi_suscripcion_screen.dart:136-288` |

### 2.6 Gaps verificados en el flujo de pago de reserva

1. **No hay cron de expiración de pagos de reserva.** `reserva_pago_expirar` se ejecuta al abrir la bandeja del admin (`inventtia_flow/lib/screens/admin/pagos_reserva_screen.dart:13`, `:58-69`) y puede llamarse a mano; en `cron.job` **no** hay job que la invoque (solo el de suscripciones). Un intento vencido puede sobrevivir hasta que el admin abra la bandeja.
2. **No hay cargo automático ni retención de la reserva por impago**: si el admin configuró `cancelar_si_expira`, la cancelación ocurre solo cuando corre el barrido (ver punto 1). Mientras tanto la reserva ocupa cupo.
3. **La única prueba de pago es humana**: no hay verificación bancaria, ni OCR de comprobante, ni integración. `codigo_confirmacion` en `reserva_pago` es **opcional y no único** (`inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:93`), a diferencia del de suscripción (`inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:347`).
4. **El estado `anulado` no cabe en `agenda.pago_estado`**: el trigger lo mapea a `'expirado'` porque el CHECK no lo admite (decisión explícita en `inventtia_flow/docs/flow_schema/migraciones/68_anular_pago_al_cancelar.sql:73-88`).
5. **El dinero va a la cuenta del negocio, no a la plataforma** (ver 2.4): cualquier fee de plataforma exige un rail de liquidación aparte.

---

## 3. Funciones de monetización ya presentes y sin explotar

### 3.1 Promociones (`flow.promocion`) — descuento, no ingreso

- Qué hace: descuento por porcentaje o monto, por servicio **o por entidad**, con vigencia y cupo atómico. Tabla: `inventtia_flow/docs/flow_schema/migraciones/27_promociones.sql:103`. Resolución/consumo de cupo: `_resolver_promocion` (`:190`), `_aplicar_promocion` (`:261`), `_precio_con_promocion` (`:330`).
- Dónde se ve: badges en Home/catálogo (`inventtia_flow/lib/services/promocion_service.dart:246-255`), cotización de la hoja de reserva (`:196-224`), panel admin (`inventtia_flow/lib/screens/admin/promociones_screen.dart`; RPC `admin_guardar_promocion`, `inventtia_flow/docs/flow_schema/migraciones/27_promociones.sql:571`).
- Monetización: **ninguna para la plataforma**. El descuento lo asume el negocio; no hay cobro por "promo destacada".
- Qué falta para explotarla: modelo comercial (p. ej. cupo de promos por plan, promo destacada de pago), métrica de conversión por promo y contrato de facturación. No existe ninguna de las tres.

### 3.2 Campañas patrocinadas / espacio patrocinado (`flow.campana`) — el activo vendible más cercano

- Qué hace: tarjetas destacadas en el Home, curadas por el **superadmin**, con alcance a local-servicio o entidad, prioridad, vigencia y aspecto. Tabla: `inventtia_flow/docs/flow_schema/migraciones/28_patrocinados.sql:54-89`; su comentario es explícito: "NO afectan al precio: solo al destacado" (`:91-92`). Lectura: `flow.campanas_activas()` (`inventtia_flow/docs/flow_schema/migraciones/28_patrocinados.sql:158`, redefinida en `inventtia_flow/docs/flow_schema/migraciones/56_patrocinados_y_rls_categorias_ocultas.sql:118`).
- Cliente: `inventtia_flow/lib/services/campana_service.dart:151-181` (solo lectura, tolerante a fallos) y pantalla envoltorio `inventtia_flow/lib/screens/espacio_patrocinado_screen.dart:7-36` (reutiliza la ficha del local, `inventtia_flow/lib/models/ficha_local.dart`).
- Escritura: solo superadmin vía RLS `public.fn_is_superadmin_full_access()` (`inventtia_flow/docs/flow_schema/migraciones/28_patrocinados.sql:116-146`).
- Monetización: **hoy es gratis y manual**. No hay precio, ni contrato, ni cupos vendidos, ni métrica de impresiones/clics, ni vencimiento ligado a pago. Es el punto más natural para un producto de "publicidad/patrocinio", pero **falta todo el negocio**, no la técnica.
- En BD hay 3 campañas.

### 3.3 `espacio_patrocinado_screen.dart` — presentación, sin inventario de espacios

- Es un envoltorio: el cuerpo vive en `FichaLocalScreen` y la campaña activa el modo "ESPACIO PATROCINADO" (`inventtia_flow/lib/screens/espacio_patrocinado_screen.dart:7-36`).
- No existe noción de "slot" vendible (posición, rotación, exclusividad por categoría/provincia, impresiones). El orden lo decide `prioridad` (`inventtia_flow/docs/flow_schema/migraciones/28_patrocinados.sql:75-78`).

### 3.4 Fidelidad (`flow.regla_fidelidad`, `flow.puntos_movimiento`, `flow.beneficio_bienvenida`) — retención, sin dinero

- Puntos por gasto y saldo derivado (append-only): tablas en `inventtia_flow/docs/flow_schema/migraciones/31_fidelidad.sql:85`, `:107`, `:140`, `:167`; saldo `fn_saldo_puntos` (`:252`); acreditación automática al completar reserva `_acreditar_puntos_agenda` (`:344`, v2 en `inventtia_flow/docs/flow_schema/migraciones/33_config_fidelidad.sql:96`) y trigger `trg_agenda_acreditar_puntos` (`:434`).
- Interruptor global `flow.fidelidad_config.activa` (`inventtia_flow/docs/flow_schema/migraciones/33_config_fidelidad.sql:58`).
- Cliente: `inventtia_flow/lib/services/fidelidad_service.dart:265-294` (RPC `cliente_mi_fidelidad`).
- Monetización: **no hay canje monetario ni compra de puntos**; el único uso es descuento en reserva (`_beneficio_bienvenida_aplicable`, ver 2.2). No hay "puntos de plataforma" separados del negocio.
- En BD: 1 regla, 6 movimientos, 1 beneficio de bienvenida, 0 canjes.

### 3.5 Dashboard de entidad (`admin_dashboard_entidad`) — analítica sin dinero

- RPC: `flow.admin_dashboard_entidad` (`inventtia_flow/docs/flow_schema/migraciones/41_rpc_admin_dashboard_modo_y_horas.sql:54`); devuelve conteos de locales/servicios/pares, resumen de reservas, serie por día y top de servicios (`:155-175`). **No devuelve importes**: no hay ingresos, ticket medio, ni pagos.
- Cliente: `inventtia_flow/lib/services/dashboard_service.dart:20-38` y panel `inventtia_flow/lib/widgets/dashboard_entidad.dart:9-14`; modelo `inventtia_flow/lib/models/dashboard_entidad.dart:132-198`.
- Monetización: ninguna. Es la base natural para vender "analítica avanzada" (ingresos, conversión, ocupación) como add-on de plan, pero hoy **no existe ni el dato de dinero en el dashboard**.

### 3.6 Notificaciones WhatsApp — infraestructura de canal, no monetización

- En Flow **no hay envío automático**. El outbox `flow.suscripcion_notificacion` encola y marca `omitida` cuando no hay bot (`inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:116-157`); `whatsapp_notif_activa=false` y `whatsapp_bot_activo=false` en BD (verificado).
- Lo que sí funciona es el **deep link `wa.me`** abierto por la app con mensaje redactado por el servidor: suscripción (`inventtia_flow/lib/services/suscripcion_service.dart:150-174`; uso `inventtia_flow/lib/screens/admin/mi_suscripcion_screen.dart:549-570`), comprobante de pago de reserva (`inventtia_flow/lib/widgets/pago_adelantado_sheet.dart:381-411`) y contacto con el cliente desde la bandeja (`inventtia_flow/lib/screens/admin/pagos_reserva_screen.dart:251-276`).
- En el proyecto compartido **sí existen** Edge Functions de WhatsApp (`wapi-session-*`, `wapi-cron-dispatch`, `wapi-webhook`, `wapi-send-products`, `wapi-notify-agotado`) y el cron `wapi_dispatch_diario`/`wapi_session_watchdog` (verificado en `list_edge_functions` y `cron.job`), **pero ninguna lee `flow.suscripcion_notificacion`** (verificado: sus definiciones no mencionan el schema `flow`). Es un rail reutilizable, no conectado.
- Monetización: el canal puede soportar recordatorios de pago/renovación (palanca de cobro), pero hoy no hay bot ni plantillas conectadas a Flow.

### 3.7 Precios automáticos por tasa — infraestructura de moneda

- `flow.tasa_cambio` (caché diaria) y `flow.precio_config` (por entidad): `inventtia_flow/docs/flow_schema/migraciones/60_tasa_cambio_y_precio_config.sql:50-96`; refresco `tasas_refrescar`/`tasas_ingest` (`inventtia_flow/docs/flow_schema/migraciones/64_tasas_refresco_pg_net.sql:135`, `:206`) + Edge Function `flow-tasas` desplegada (verificado, versión 3 activa).
- Cliente: `inventtia_flow/lib/services/tasa_cambio_service.dart:6-27`, `inventtia_flow/lib/utils/conversion_precio.dart:1-9`; editor admin `inventtia_flow/lib/widgets/precios_servicio_editor.dart`.
- No es monetización, pero es la pieza que permite **cobrar en CUP/USD/EUR/MLC** y por tanto la que habilita cualquier fee multi-moneda. En BD: 2 filas de `tasa_cambio`, 2 de `precio_config`.

---

## 4. Superficie de datos disponible

### 4.1 Tablas del schema `flow` (48 tablas; verificado en BD)

**Núcleo de negocio / reservas** (definidas en `inventtia_flow/docs/flow_schema/flow_schemma.sql` y migraciones 16):

| Tabla | Definición | Rol para cobros |
|---|---|---|
| `flow.entidad` (owner_uuid, FK `auth.users`) | `inventtia_flow/docs/flow_schema/flow_schemma.sql:134-145` | Sujeto que paga la suscripción; dueña del dinero del cobro por adelantado |
| `flow.entidad_admin` / `flow.entidad_vendedor` | `:146`, `:194` | Quién puede ver/verificar pagos |
| `flow.perfil` | `:37` | Datos del cliente (nombre/teléfono), FK a `auth.users` |
| `flow.app_dat_locales` | `:20` | Local; enlaza a la entidad (`id_entidad`) |
| `flow.app_dat_servicios` | `:4` | Servicio; **`config_precio` jsonb** (`inventtia_flow/docs/flow_schema/migraciones/15_servicio_precio.sql:10`), **`cobro_adelantado`** (`inventtia_flow/docs/flow_schema/migraciones/67_cobro_por_servicio.sql:38`) |
| `flow.local_servicio` | `:48` | Par local-servicio (unidad reservable) |
| `flow.recurso` / `flow.tramo` / `flow.turno` / `flow.turno_tramo` / `flow.plan_tramo` | `inventtia_flow/docs/flow_schema/migraciones/16_recursos_tramos_turnos.sql:34`, `:57`, `:80`, `:99`, `:111` | Capacidad y **precio propio del turno** (`turno.precios`, `inventtia_flow/docs/flow_schema/migraciones/21_precio_turno.sql:2`) |
| `flow.agenda` | `inventtia_flow/docs/flow_schema/flow_schemma.sql:67` | **La reserva**: `precio_total`, `moneda`, `pago_estado`, `pago_id`, `pago_monto`, `pago_moneda`, motivo/cancelación |
| `flow.sala_espera` / `flow.ultimo_numero` / `flow.sala_espera_fraude` | `:90`, `:105`, `:124` | Cola; **sin precio** |
| `flow.plan_servicios` / `flow.plan_config` | `:114`, `:184` | Cupo legacy por día |
| `flow.nom_estado_agenda` | `:60` | Estados `Reservado/Cancelado/Completado` |
| `flow.notificaciones` | `:168` | Campana in-app (aquí caen los avisos `tipo='pago'`/`'suscripcion'`) |
| `flow.bot_log` | `:157` | Trazabilidad del bot de colas |

**Monetización / engagement:**

| Tabla | Definición |
|---|---|
| `flow.suscripcion_config`, `_plan`, `suscripcion`, `suscripcion_intent`, `suscripcion_transaccion`, `suscripcion_movimiento`, `suscripcion_notificacion` | `inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:128`, `:210`, `:245`, `:301`, `:338`, `:381`, `:405` |
| `flow.cobro_config`, `flow.reserva_pago` | `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:52`, `:81` |
| `flow.promocion` | `inventtia_flow/docs/flow_schema/migraciones/27_promociones.sql:103` |
| `flow.campana` | `inventtia_flow/docs/flow_schema/migraciones/28_patrocinados.sql:54` |
| `flow.coleccion`, `flow.coleccion_servicio` | `inventtia_flow/docs/flow_schema/migraciones/30_colecciones.sql:59`, `:77` |
| `flow.regla_fidelidad`, `flow.puntos_movimiento`, `flow.beneficio_bienvenida`, `flow.beneficio_canje`, `flow.fidelidad_config` | `inventtia_flow/docs/flow_schema/migraciones/31_fidelidad.sql:85`, `:107`, `:140`, `:167`; `inventtia_flow/docs/flow_schema/migraciones/33_config_fidelidad.sql:58` |
| `flow.favorito`, `flow.resena` | `inventtia_flow/docs/flow_schema/migraciones/25_favoritos.sql:45`; `inventtia_flow/docs/flow_schema/migraciones/26_resenas.sql:61` |
| `flow.entidad_categoria_oculta` | `inventtia_flow/docs/flow_schema/migraciones/55_categorias_ocultas_por_entidad.sql:60` |
| `flow.tasa_cambio`, `flow.precio_config`, `flow.tasa_cambio_sondeo` | `inventtia_flow/docs/flow_schema/migraciones/60_tasa_cambio_y_precio_config.sql:50`, `:77`; `inventtia_flow/docs/flow_schema/migraciones/64_tasas_refresco_pg_net.sql:53` |
| `flow.nom_tipo_actividad_servicio` | `inventtia_flow/docs/flow_schema/flow_schemma.sql:205` |

**Columnas añadidas a `flow.agenda` por los circuitos de cobro/cancelación:**

- Pago: `pago_estado`, `pago_id`, `pago_monto`, `pago_moneda` — `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:131-145`.
- Cancelación: `motivo_cancelacion`, `cancelado_por`, `cancelado_por_rol`, `cancelado_at` — `inventtia_flow/docs/flow_schema/migraciones/61_cancelacion_motivo_y_notificacion.sql:42-49`.
- Precio: `precio_total`, `moneda` — `inventtia_flow/docs/flow_schema/migraciones/15_servicio_precio.sql:13-15`.

**Vistas:** no hay ninguna vista ni vista materializada en `flow` (verificado en `information_schema.tables`). Todo es tabla + RPC.

### 4.2 Funciones SQL relevantes (definición en una línea)

| Función | Archivo:línea | Define |
|---|---|---|
| `entidad_activa(id)` | `inventtia_flow/docs/flow_schema/migraciones/44_suscripciones_predicado_trial.sql:84` | Único predicado "esta entidad tiene suscripción vigente"; sin fila ⇒ `true` |
| `_ls_disponible(id)` | `:126` | Único predicado "este local-servicio es visible/reservable" (incluye suscripción) |
| `_suscripcion_trial_entidad()` (trigger) | `:163` | Trial automático y anti-abuso por `owner_uuid` |
| `cliente_estado_suscripcion(id)` | `:259` | Estado derivado de fechas del plan |
| `cliente_planes_suscripcion()` | `:398` | Planes activos para el cliente |
| `_susc_notificar_inapp(...)` / `_susc_notificar_whatsapp(...)` | `inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:77`, `:116` | Campana in-app / outbox WhatsApp |
| `cliente_crear_intent_suscripcion(...)` | `:166` | Intento de pago + deep link |
| `cliente_reportar_pago_suscripcion(...)` | `:282` | "Ya he pagado" (sin acreditar) |
| `cliente_mis_pagos_suscripcion(id)` | `:428` | Intents, pagos y movimientos |
| `_susc_acreditar_dias(...)` | `:520` | Aritmética de acreditación de días |
| `admin_suscripcion_aprobar_pago(...)` / `_rechazar_pago(...)` / `_acreditar(...)` | `:609`, `:705`, `:764` | Verificación manual / rechazo / ajuste |
| `suscripcion_expirar()` | `:846` | Barrido de vencimientos y avisos |
| `admin_suscripcion_listar/detalle/inicializar/suspender/reactivar` | `inventtia_flow/docs/flow_schema/migraciones/46_suscripciones_admin_cron_seed.sql:109`, `:248`, `:348`, `:407`, `:451` | Gestión global |
| `admin_planes_listar/guardar/eliminar`, `admin_config_obtener/guardar`, `admin_notificaciones_pendientes/marcar` | `:512`, `:546`, `:623`, `:658`, `:684`, `:735`, `:768` | Planes, config y outbox |
| `admin_dashboard_entidad(...)` | `inventtia_flow/docs/flow_schema/migraciones/41_rpc_admin_dashboard_modo_y_horas.sql:54` | Conteos + serie + top (sin dinero) |
| `cotizar_reserva(...)` | `inventtia_flow/docs/flow_schema/migraciones/27_promociones.sql:367` (v2 `inventtia_flow/docs/flow_schema/migraciones/34_beneficio_bienvenida_precio.sql:158`) | Precio mostrado = precio cobrado |
| `_resolver_promocion` / `_aplicar_promocion` / `_precio_con_promocion` | `inventtia_flow/docs/flow_schema/migraciones/27_promociones.sql:190`, `:261`, `:330` | Resolución y consumo de cupo de promo |
| `_beneficio_bienvenida_aplicable` | `inventtia_flow/docs/flow_schema/migraciones/34_beneficio_bienvenida_precio.sql:102` | Descuento único de bienvenida |
| `calcular_precio_con_reglas` / `calcular_precio_reserva` / `calcular_precio_turno` | `inventtia_flow/docs/flow_schema/migraciones/51_precio_turno_con_reglas.sql:46`, `:189`, `:221` | Motor de precio (reglas, moneda, turno) |
| `cliente_reservar_directo(...)` | `inventtia_flow/docs/flow_schema/migraciones/27_promociones.sql:789` (desplegada con beneficios, ver `:283` de la 34) | Crea reserva y **persiste precio** |
| `cliente_entrar_sala_espera_reserva(...)` | `inventtia_flow/docs/flow_schema/migraciones/38_sala_espera_turno.sql:211` | Cola; sin precio |
| `bot_procesar_recurso_dia` / `bot_procesar_plan` | `inventtia_flow/docs/flow_schema/migraciones/29_bot_promociones.sql:353`, `:119` | Cola → reserva con precio |
| `_descontar_tramos_turno` | `inventtia_flow/docs/flow_schema/migraciones/17_fix_descontar_tramos_turno_sin_delete.sql:22` | Consumo de cupo |
| `cliente_obtener_agendas(...)` | `inventtia_flow/docs/flow_schema/migraciones/69_cobro_disponible_en_agendas.sql:85` | Tickets del cliente + `cobro_disponible` |
| `cliente_cobro_info(...)` | `inventtia_flow/docs/flow_schema/migraciones/67_cobro_por_servicio.sql:46` | ¿Se puede pagar por adelantado? (servicio **y** entidad) |
| `_monto_cobro_reserva(...)` | `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:151` | Total de la reserva convertido a la moneda de cobro |
| `_precio_agenda_desde_datos(...)` | `inventtia_flow/docs/flow_schema/migraciones/71_monto_cobro_desde_datos.sql:60` | Recalcula el precio si `precio_total=0` |
| `cliente_crear_pago_reserva(...)` | `inventtia_flow/docs/flow_schema/migraciones/71_monto_cobro_desde_datos.sql:127` | Intento de pago de una reserva (1 vivo por reserva) |
| `cliente_reportar_pago_reserva(...)` | `inventtia_flow/docs/flow_schema/migraciones/68_anular_pago_al_cancelar.sql:312` | Reporta + exige reserva activa + cobro habilitado |
| `cliente_pago_reserva(...)` | `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:587` | Estado del pago de una reserva |
| `admin_cobro_config_get/set(...)` | `:199`, `:240` | Config del cobro (número, WhatsApp, moneda, plazo) |
| `admin_listar_pagos_reserva(...)` | `:646` | Bandeja del admin |
| `admin_verificar_pago_reserva(...)` | `inventtia_flow/docs/flow_schema/migraciones/68_anular_pago_al_cancelar.sql:215` | Verifica (exige reserva activa) |
| `admin_rechazar_pago_reserva(...)` | `inventtia_flow/docs/flow_schema/migraciones/68_anular_pago_al_cancelar.sql:462` | Rechaza con motivo |
| `reserva_pago_expirar()` | `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:830` | Cierra vencidos y cancela reserva si aplica |
| `trg_reserva_pago_servicio_cobra()` | `inventtia_flow/docs/flow_schema/migraciones/67_cobro_por_servicio.sql:99` | Impide cobrar en servicio no habilitado |
| `trg_agenda_anular_pago()` | `inventtia_flow/docs/flow_schema/migraciones/68_anular_pago_al_cancelar.sql:157` | Anula intentos vivos al cancelar la reserva |
| `_cobro_disponible(id)` | `inventtia_flow/docs/flow_schema/migraciones/69_cobro_disponible_en_agendas.sql:65` | Booleano para no hacer N+1 desde el cliente |
| `campanas_activas()` / `colecciones_activas()` | `inventtia_flow/docs/flow_schema/migraciones/28_patrocinados.sql:158`; `inventtia_flow/docs/flow_schema/migraciones/30_colecciones.sql:162` | Feed de destacados |
| `cliente_mi_fidelidad()` / `fn_saldo_puntos()` / `_acreditar_puntos_agenda()` | `inventtia_flow/docs/flow_schema/migraciones/33_config_fidelidad.sql:194`; `inventtia_flow/docs/flow_schema/migraciones/31_fidelidad.sql:252`, `:344` | Puntos y saldo |
| `cliente_home_feed(...)` | `inventtia_flow/docs/flow_schema/migraciones/55_categorias_ocultas_por_entidad.sql:218` | Feed del Home (incluye campañas/colecciones) |
| `tasas_actuales()` / `tasa_factor()` / `tasas_refrescar()` / `tasas_ingest()` | `inventtia_flow/docs/flow_schema/migraciones/60_tasa_cambio_y_precio_config.sql:133`, `:170`; `inventtia_flow/docs/flow_schema/migraciones/64_tasas_refresco_pg_net.sql:135`, `:206` | Tasa de cambio y conversión |
| `_puede_ver_entidad(id)` | `inventtia_flow/docs/flow_schema/migraciones/60_tasa_cambio_y_precio_config.sql:107` | Autorización de entidad reutilizada por los RPC de cobro |

### 4.3 Schema `public` (lo compartido)

- **Lo que Flow usa de `public`:** `public.fn_is_superadmin_full_access()` como guardián en RLS y RPC `admin_*` de suscripción/cobro/promos/campañas (`inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:454`; `inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:626`; `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:934-954`; `inventtia_flow/docs/flow_schema/migraciones/68_anular_pago_al_cancelar.sql:215`) y `auth.users` por FKs (`inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:305`, `:354`).
- **No hay acceso directo a tablas `public` desde la app Flow:** un grep de `.schema('public')` en `inventtia_flow/lib` no devuelve resultados; todos los servicios usan `_schema = 'flow'` (p. ej. `inventtia_flow/lib/services/cobro_service.dart:19`).
- **Tablas `public` adyacentes del mismo proyecto (otro producto, no Flow):** `app_suscripciones`, `app_suscripciones_plan`, `app_suscripciones_historial`, `app_suscripciones_renovaciones_resumen`, `app_dat_suscripcion_catalogo`, `app_dat_pago_venta`, `app_nom_medio_pago` (verificado en BD). Se consumen desde `ventiq_superadmin` (p. ej. `ventiq_superadmin/lib/services/agente_service.dart:132`, `ventiq_superadmin/lib/screens/configuracion_screen.dart:86`) y representan el licenciamiento de la **otra** suite, no el cobro de GoReserva.
- **Edge Functions del proyecto (verificado con `list_edge_functions`):** `flow-tasas` (tasas, activa) y, del ecosistema compartido, `stripe-create-payment-intent`, `stripe-create-checkout-session`, `stripe-calculate-tax`, `stripe-check-payment`, `stripe-cancel-order`, `wapi-*` (WhatsApp), `send-push-notification`. **Ninguna está cableada a `flow` por el lado de la app**: el único `functions.invoke` en `inventtia_flow/lib` es el de `flow-tasas` (`inventtia_flow/lib/services/tasa_cambio_service.dart:81`), y el despachador SQL de WhatsApp `public.fn_wapi_dispatch_diario` no menciona el schema `flow` en su definición (verificado con `pg_get_functiondef`), por lo que no vacía `flow.suscripcion_notificacion`.
- **Vistas `public`:** todas pertenecen a inventario/ventas de la otra suite (`vista_precios_productos`, `vw_resumen_financiero`, etc.); ninguna es de Flow.

### 4.4 Monedas y tasas

- Monedas soportadas por la app: `USD, EUR, CUP, MLC` (`inventtia_flow/lib/models/config_precio.dart:18-34`), con símbolo/formato por moneda (`inventtia_flow/lib/utils/precio_reserva.dart:83-89`).
- Monedas aceptadas en cobros: `flow.cobro_config.moneda` y `flow.reserva_pago.moneda` con CHECK `('CUP','USD','EUR','MLC')` (`inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:73`, `:103`); suscripción usa `suscripcion_plan.moneda` libre con default `CUP` (`inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:218`).
- Conversión: solo por `flow.tasa_factor` desde la caché (`inventtia_flow/docs/flow_schema/migraciones/60_tasa_cambio_y_precio_config.sql:170-218`); se usa **exclusivamente** al cobrar por adelantado (`inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:180`) y no en la suscripción (el precio del plan ya está en su moneda, `inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:209-210`).

### 4.5 Lo que NO existe en la superficie de datos

- No hay tabla de **comisiones/fees** de plataforma, ni de **liquidaciones**, ni de **ingresos** consolidados.
- No hay tabla de **consumidor/suscriptor final** (ni plan, ni entitlement, ni cupo de uso por cliente).
- No hay **wallet/saldo** del cliente dentro de Flow.
- No hay **historial de precios** por reserva más allá de `agenda.precio_total` (si cambia la config del servicio, la reserva vieja conserva su importe; no hay desglose de promo/beneficio guardado en la reserva).
- No hay **reembolsos** ni **contracargos**.
- No hay **métricas de patrocinio** (impresiones/clics) ni **inventario de slots publicitarios**.

---

## 5. Puntos de inserción candidatos

> Convención: "ancla" = función/tabla concreta donde el cambio es posible sin reescribir el flujo; "riesgo" = lo que puede romperse o cobrarse mal.

### (a) Fee de servicio al cliente final (cobrar al cliente por usar GoReserva)

**Anclas candidatas**

1. **Dentro del intento de pago existente** — `flow.cliente_crear_pago_reserva` (`inventtia_flow/docs/flow_schema/migraciones/71_monto_cobro_desde_datos.sql:127`, líneas de monto en `:211-260`) y/o `_monto_cobro_reserva` (`inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:151-195`). Hoy el monto es exactamente el total de la reserva; añadir una línea de fee exige **guardar el desglose** (hoy `reserva_pago.monto` es un único importe, `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:86`).
2. **Nuevo intento separado** (recomendable si el fee es de la plataforma): tabla nueva `flow.plataforma_pago` / `flow.fee_intento` con su propio `numero_proveedor` (el del superadmin), enlazada a `id_agenda`, creada justo después de `cliente_reservar_directo` (que ya devuelve `id_agenda`, aunque el wrapper Dart lo descarte: `inventtia_flow/lib/services/agenda_service.dart:164-167`).
3. **Al confirmar la reserva** (`flow.agenda` AFTER INSERT + precio > 0) para un fee que se difiere al mostrador; riesgo alto de fee no cobrado.
4. **Gate de visibilidad**: `flow._ls_disponible` (`inventtia_flow/docs/flow_schema/migraciones/44_suscripciones_predicado_trial.sql:126`) o `cliente_cobro_info` (`inventtia_flow/docs/flow_schema/migraciones/67_cobro_por_servicio.sql:46`) para condicionar el fee a plan del cliente/entidad.

**Riesgos concretos**

- **Doble cobro:** el total de la reserva ya se cobra con el número del negocio (`flow._monto_cobro_reserva`). Un fee sumado al mismo intento va al bolsillo del negocio, no a la plataforma: sin split, la plataforma tendría que facturarlo aparte.
- **Idempotencia:** solo se bloquea **un intento vivo por reserva** (`inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:392-401`, repetido en `inventtia_flow/docs/flow_schema/migraciones/71_monto_cobro_desde_datos.sql:166-175`). Tras `rechazado`/`expirado` se puede crear otro intento ⇒ si el fee se calcula al crear, hay que sellarlo por `(id_agenda, tipo)` con UNIQUE para no cobrarlo dos veces.
- **Moneda y redondeo:** el fee se sumaría sobre un monto ya convertido y redondeado (`round` a entero en CUP, `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:186-190`); definir si el fee se calcula antes o después de la conversión cambia el importe.
- **Reserva sin precio:** 49/168 reservas de la BD no tienen precio; un fee fijo no puede depender de que exista precio (el RPC ya rechaza sin precio, `inventtia_flow/docs/flow_schema/migraciones/71_monto_cobro_desde_datos.sql:211-219`).
- **RLS/grants:** cualquier tabla nueva debe replicar el patrón `enable row level security` + `grant select to authenticated` + escritura solo por RPC definer y `public.fn_is_superadmin_full_access()` (`inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:929-983`).
- **UX:** cobrar fee antes de reservar obliga a cambiar el orden actual (reservar → pagar) y a decidir qué pasa si el cliente no paga (hoy la reserva ya ocupa cupo, `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:34-38`).

### (b) Prepago / garantía de reserva — **ya construido**, faltan piezas

**Anclas**

- Config: `flow.cobro_config` (`inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:52`); interruptor por servicio `flow.app_dat_servicios.cobro_adelantado` (`inventtia_flow/docs/flow_schema/migraciones/67_cobro_por_servicio.sql:38`).
- Importe: `flow._monto_cobro_reserva` (`inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:151`); recálculo `flow._precio_agenda_desde_datos` (`inventtia_flow/docs/flow_schema/migraciones/71_monto_cobro_desde_datos.sql:60`).
- Ciclo: `cliente_crear_pago_reserva` (`inventtia_flow/docs/flow_schema/migraciones/71_monto_cobro_desde_datos.sql:127`) → `cliente_reportar_pago_reserva` (`inventtia_flow/docs/flow_schema/migraciones/68_anular_pago_al_cancelar.sql:312`) → `admin_verificar_pago_reserva` (`:215`) / rechazar (`:462`) → `reserva_pago_expirar` (`inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:830`).

**Qué falta (gaps reales, no hipótesis)**

1. **Cron de expiración:** no existe en `cron.job`; solo se barre al abrir la bandeja (`inventtia_flow/lib/screens/admin/pagos_reserva_screen.dart:58-69`). Añadir `select flow.reserva_pago_expirar();` cada N minutos es el cambio mínimo.
2. **Garantía como política configurable** (porcentaje del total, mínimos, no-show, devolución): hoy `cobro_config` solo tiene moneda/plazo/cancelar-si-expira (`inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:52-76`). No hay `%`, ni política de devolución, ni estado de reembolso.
3. **Cobro obligatorio vs opcional:** hoy es 100 % opcional y la reserva se crea igual. Convertirlo en obligatorio requiere decidir qué pasa con la reserva antes de pagar (hoy ocupa cupo y solo se cancela al expirar el pago).
4. **Estados:** `agenda.pago_estado` no admite `'anulado'` (`inventtia_flow/docs/flow_schema/migraciones/68_anular_pago_al_cancelar.sql:73-88`); si el producto quiere "reembolsado/garantía retenida", hay que ampliar CHECK y vocabulario Dart (`inventtia_flow/lib/utils/estado_pago.dart:19-91`).

**Riesgos:** doble intento tras rechazo/expirado (ver (a)); carrera verificación↔expiración con posible deadlock 40P01 (documentado en `inventtia_flow/docs/flow_schema/migraciones/68_anular_pago_al_cancelar.sql:100-108`); `codigo_confirmacion` no único en `reserva_pago` (`inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:93`) ⇒ el mismo comprobante podría "verificar" dos pagos distintos si el admin no mira; el dinero entra en la cuenta del negocio, no de la plataforma.

### (c) Plan premium del consumidor (cliente final paga por ventajas)

**Anclas candidatas**

- **Nueva tabla** `flow.consumidor_suscripcion` (+ `_plan`, `_intent`, `_transaccion`, `_movimiento`), calcada del módulo de entidad pero con `uuid_usuario` en vez de `id_entidad`. **No se puede reutilizar `flow.suscripcion`**: su PK lógica es `id_entidad` NOT NULL con FK a `flow.entidad` (`inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:245-249`) y su autorización es `_susc_caller_ve_entidad` (`inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:103-121`).
- **Reutilizable:** plantillas Transfermóvil y outbox (`flow.suscripcion_config`, `inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:128-194`), el patrón `{ok,data|error}` (`inventtia_flow/lib/services/suscripcion_service.dart:176-214`), y las pantallas de "intent + Ya he pagado" (`inventtia_flow/lib/screens/admin/mi_suscripcion_screen.dart`).
- **Gates de valor premium:** fee de servicio exento → `flow.cliente_cobro_info` (`inventtia_flow/docs/flow_schema/migraciones/67_cobro_por_servicio.sql:46`) o `_cobro_disponible` (`inventtia_flow/docs/flow_schema/migraciones/69_cobro_disponible_en_agendas.sql:65`); descuento adicional → `flow.cotizar_reserva` (`inventtia_flow/docs/flow_schema/migraciones/34_beneficio_bienvenida_precio.sql:158`) o `_beneficio_bienvenida_aplicable` (`:102`); prioridad en cola → `flow.cliente_entrar_sala_espera_reserva` (`inventtia_flow/docs/flow_schema/migraciones/38_sala_espera_turno.sql:211`); visibilidad de promos/campañas → `flow.campanas_activas` (`inventtia_flow/docs/flow_schema/migraciones/56_patrocinados_y_rls_categorias_ocultas.sql:118`).

**Riesgos**

- **Apilar descuentos:** ya hay dos descuentos encadenados (promo → bienvenida). Un tercero (premium) debe definir orden y tope, o el precio puede bajar a 0 (`greatest(...,0)` en `inventtia_flow/docs/flow_schema/migraciones/34_beneficio_bienvenida_precio.sql:474`).
- **Autorización:** el módulo de entidad se apoya en `id_entidad` + `owner/admin`; el de consumidor debe usar `auth.uid()` y RLS por `uuid_usuario`, no parámetros del cliente (patrón correcto en `inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:187-195`).
- **Superficie app:** `SuscripcionProvider` es de entidad y se monta en el shell del admin (`inventtia_flow/lib/providers/suscripcion_provider.dart:16-18`; `inventtia_flow/lib/screens/home_shell.dart:670`). El aviso/gestión del premium del consumidor necesita provider/pantalla propios.
- **Precio real:** el único rail vivo es Transfermóvil manual; un premium de consumidor con cobro recurrente automático **no tiene hoy soporte** (no hay pasarela, ver §1.8).
- **Tiendas de apps:** si el premium desbloquea funciones dentro de la app, Google Play/Apple pueden exigir facturación in-app. No hay ninguna integración IAP/RevenueCat en el repo (grep negativo), así que es un frente nuevo, no una extensión.

### (d) Comisión / take rate al negocio

**Anclas candidatas**

1. **Al verificar el pago de la reserva** — `flow.admin_verificar_pago_reserva` (`inventtia_flow/docs/flow_schema/migraciones/68_anular_pago_al_cancelar.sql:215`): es el único punto donde el sistema "sabe" que el dinero se cobró. Insertar ahí un asiento de comisión (tabla nueva `flow.comision_movimiento` o `flow.plataforma_ingreso`) con `(id_entidad, id_reserva_pago, base, tasa, monto, moneda)` y UNIQUE por `id_reserva_pago` para idempotencia.
2. **Trigger AFTER UPDATE en `flow.reserva_pago`** cuando `estado` pasa a `'verificado'`: cubre también verificaciones desde SQL/panel y es idempotente por transición. Patrón ya usado por el proyecto: `trg_agenda_anular_pago` (`inventtia_flow/docs/flow_schema/migraciones/68_anular_pago_al_cancelar.sql:205-211`).
3. **Sobre la suscripción**: hoy el precio del plan es fijo (`flow.suscripcion_plan.precio`, `inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:217`). Un "plan % de comisión" se modelaría en `limites jsonb` (`:223-224`, hoy sin uso funcional) o en una columna nueva.
4. **Base de cálculo:** `flow.reserva_pago.monto` (lo que el cliente pagó, `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:86`) o `flow.agenda.precio_total` (precio de la reserva). **No** usar `agenda.pago_monto` como fuente de verdad: es denormalizado (`:141-145`).

**Riesgos**

- **La plataforma no recibe el dinero:** el cobro va al número del negocio (`flow.cobro_config.transfermovil_numero_proveedor`, `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:56-57`). Una comisión solo puede ser **cuenta por cobrar** (factura/liquidación al negocio) o exigir un cambio de rail (cobro a la cuenta de la plataforma + liquidación al negocio). Sin eso, "cobrar comisión" es un registro contable, no un cobro.
- **Doble contabilización** si convive con la suscripción: hay que decidir si la comisión sustituye o complementa el plan; el libro de suscripción es append-only y no admite "descuentos por comisión" (`inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:381-398`).
- **Moneda/FX:** la comisión se calcularía sobre un monto ya convertido; si la comisión se factura en otra moneda, hay que congelar la tasa usada (hoy `tasa_factor` puede cambiar al día siguiente, `inventtia_flow/docs/flow_schema/migraciones/60_tasa_cambio_y_precio_config.sql:170-218`).
- **Idempotencia:** sin UNIQUE por `(tipo, id_referencia)` un reintento del admin o un trigger duplicado genera doble comisión.
- **Reservas sin pago por adelantado:** la mayoría de reservas no tienen `reserva_pago`; si la comisión se calcula por reserva completada, el ancla correcta es el cambio a `Completado` en `flow.staff_marcar_estado_agenda` (`inventtia_flow/docs/flow_schema/migraciones/19_staff_descancelar_agenda.sql:26`, redefinida en `inventtia_flow/docs/flow_schema/migraciones/61_cancelacion_motivo_y_notificacion.sql:100`), no el pago.

---

## 6. Riesgos transversales (aplican a cualquier punto de inserción)

1. **Un solo rail, manual.** No hay confirmación automática de ningún pago: suscripción (`inventtia_flow/lib/services/suscripcion_service.dart:110-115`) ni reserva (`inventtia_flow/lib/services/cobro_service.dart:48-53`). Cualquier cobro nuevo hereda la dependencia de una persona verificando en el banco.
2. **Deep link sin retorno.** Transfermóvil no devuelve resultado; el "ya pagué" se infiere por ciclo de vida de la app (`inventtia_flow/lib/screens/admin/mi_suscripcion_screen.dart:81-97`). Un fee con cobro obligatorio no puede confiar en el deep link como prueba.
3. **Bug conocido del `id_transaccion`:** la app de Transfermóvil lo trata como estático; por eso el link lleva `ESTATICO` y la referencia interna (`FLW-...`) queda solo para auditoría (`inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:218-225`; mismo criterio en `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:432-451`).
4. **Idempotencia asimétrica:** suscripción tiene `codigo_confirmacion UNIQUE` (`inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:347`); reserva **no** (`inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:93`). Cualquier fee/comisión debe traer su propia clave de idempotencia.
5. **Autorización:** el patrón del repo es `security definer` + `set search_path = flow, public` + `auth.uid()` + `_puede_ver_entidad`/`fn_is_superadmin_full_access()` (ver `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:696-718`). No crear tablas nuevas sin RLS ni RPC sin revoke/grant explícito (patrón `:956-983`).
6. **Degradación por esquema ausente:** la app tolera que falten tablas/RPC y oculta secciones (`inventtia_flow/lib/utils/esquema_pendiente.dart:21-37`). Un cobro nuevo debe seguir ese contrato o romperá en release antes de migrar.
7. **Modo prueba activo:** `flow.suscripcion_config.modo_prueba = true` en BD. Cualquier métrica de ingresos actual es de prueba, no real.
8. **Estado de migraciones:** la BD consultada (release, ver cabecera) **ya tiene** 43-46 y 60-71 aplicadas (verificado por existencia de tablas, columnas, triggers, `_cobro_disponible`, `_precio_agenda_desde_datos`, `relreplident='f'` en `reserva_pago`). El documento `inventtia_flow/PLAN_PRECIOS_PAGOS_CALENDARIO.md:92-96` y `:417-432` dice que en release estaba pendiente: **ese punto del documento está desactualizado** a fecha de este informe.

---

## 7. Anexo — consultas de verificación usadas (reproducibles)

Ejecutadas vía MCP de Supabase (solo lectura) el 29-10-2026. Sirven para re-verificar antes de decidir nada:

```sql
-- 1. Funciones de cobro desplegadas
select p.proname, pg_get_function_identity_arguments(p.oid)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='flow'
  and (p.proname like '%cobro%' or p.proname like '%pago%'
       or p.proname like '%suscrip%' or p.proname like '%precio%');

-- 2. Qué versión está realmente desplegada
select proname,
       pg_get_functiondef(p.oid) like '%cobro_disponible%'      as v69,
       pg_get_functiondef(p.oid) like '%ya no esta activa%'     as v68,
       pg_get_functiondef(p.oid) like '%_precio_agenda_desde_datos%' as v71
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='flow'
  and p.proname in ('cliente_obtener_agendas','admin_verificar_pago_reserva',
                    'cliente_reportar_pago_reserva','cliente_crear_pago_reserva');

-- 3. Precios reales de los planes y config
select id, codigo, nombre, duracion_dias, precio, moneda, activo from flow.suscripcion_plan order by orden;
select * from flow.suscripcion_config;

-- 4. Uso real del circuito de pago de reservas
select estado, count(*) from flow.reserva_pago group by 1;
select count(*) filter (where coalesce(precio_total,0)>0) as con_precio, count(*) from flow.agenda;

-- 5. Automatización
select jobid, schedule, jobname, active, command from cron.job order by jobid;

-- 6. Realtime
select relname, relreplident from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='flow' and relname in ('reserva_pago','agenda','notificaciones');
```

---

## 8. Índice de documentos vecinos (contexto ya escrito en el repo)

| Documento | Qué aporta |
|---|---|
| `inventtia_flow/PLAN_SUSCRIPCIONES.md` | Decisiones del modelo B2B, estado de fases, verificación hecha |
| `inventtia_flow/PLAN_PRECIOS_PAGOS_CALENDARIO.md` | Contratos de precios/tasas/pago por adelantado/calendario y bitácora de ejecución |
| `inventtia_flow/docs/flow_schema/README.md` | Convenciones del schema y del flujo de migraciones |
| `inventtia_flow/docs/flow_schema/BASE_CONOCIMIENTO.md` | Modelo de datos base de Flow |
| `inventtia_flow/docs/flow_schema/migraciones/_APLICAR_RELEASE_60_67.sql` | Bundle idempotente de migraciones 60-67 |
| `inventtia_flow/docs/flow_schema/migraciones/_APLICAR_RELEASE_68.sql` | Bundle idempotente de la 68-71 |

**Conclusión de una línea:** el sistema ya sabe *cobrar a un negocio* (suscripción manual por Transfermóvil) y *registrar un prepago opcional del cliente* (con el Transfermóvil del negocio); **no sabe cobrar a la plataforma**. Los puntos de inserción más baratos son (b) —porque el circuito existe— y los más caros son (a)/(c)/(d), porque exigen un rail de cobro distinto del de la entidad o un modelo de liquidación que hoy no existe.