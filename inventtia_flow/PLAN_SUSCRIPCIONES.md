# Plan — Suscripciones por entidad en Inventtia Flow (GoReserva)

**Estado:** plan aprobado; **fase 1 (SQL) implementada y entregada** — el resto en curso.
**Alcance:** `inventtia_flow/` (app + SQL del schema `flow`) y `ventiq_superadmin/` (panel superadmin).

> Este documento existe para **cerrar decisiones**. La Parte A es lo que ya verifiqué en el
> repo (hechos, no supuestos). La Parte B es el modelo que propongo. La Parte C son las
> **preguntas que no puedo decidir yo** — cada una lleva mi recomendación y el valor por
> defecto que aplicaré si el usuario responde "como recomiendes".

---

## Estado de ejecución

| Fase | Alcance | Estado |
|---|---|---|
| **1. SQL** | Migraciones `43` → `46` en `docs/flow_schema/migraciones/` | ✅ **Escritas**. El usuario debe pegarlas en el SQL Editor de **los dos proyectos** (debug y release), en orden. |
| **2. App cliente** | `inventtia_flow`: modelos, `suscripcion_service`, provider, pantalla "Mi suscripción", aviso permanente de impago, intent + "Ya he pagado" | ✅ **Escrita** (`lib/models/suscripcion.dart`, `lib/services/suscripcion_service.dart`, `lib/providers/suscripcion_provider.dart`, `lib/widgets/aviso_suscripcion.dart`, `lib/screens/admin/mi_suscripcion_screen.dart`, ruta `/mi-suscripcion`, aviso montado en `home_shell.dart`, entrada en `perfil_screen.dart`, `<queries>` de Transfermóvil/WhatsApp en el manifiesto). `dart analyze` sin errores. |
| **3. Panel superadmin** | `ventiq_superadmin`: `/flow-suscripciones`, `/flow-planes`, `/flow-config`, guard, drawer y permisos | ✅ **Escrita** (`lib/services/suscripcion_admin_service.dart`, `lib/widgets/suscripcion_ui.dart`, `lib/screens/flow_suscripciones_screen.dart`, `flow_suscripcion_detalle_screen.dart`, `flow_planes_screen.dart`, `flow_config_screen.dart`, rutas + grupo "Flow" en el drawer + `AppRoutes`). `dart analyze` sin errores. |
| **4. Cierre** | `README.md` del esquema ✅, `CHANGELOG.md` ✅, bump de versión ✅ (`1.4.0+8`), ciclo completo | ⏳ **Pendiente**: sólo la prueba manual de extremo a extremo (necesita las migraciones aplicadas). |

### Estado por capa (lo que el usuario ve)

| Pieza | Dónde | Estado |
|---|---|---|
| 7 tablas + config | `migraciones/43_*.sql` | ✅ escrita, **sin aplicar** |
| Predicado `entidad_activa` + trial + estado/planes del cliente | `migraciones/44_*.sql` | ✅ escrita, **sin aplicar** |
| Circuito de pago y acreditación | `migraciones/45_*.sql` | ✅ escrita, **sin aplicar** |
| Panel, CRUD de planes, config, outbox, cron, seed | `migraciones/46_*.sql` | ✅ escrita, **sin aplicar** |
| App del cliente: aviso, planes, intent, "Ya he pagado" | `inventtia_flow` | ✅ escrita, `dart analyze` limpio |
| Panel: bandeja, ficha, verificar/rechazar, acreditar, planes, config | `ventiq_superadmin` | ✅ escrita, `dart analyze` limpio |
| Verificación contra una base real | — | ❌ **imposible en este entorno** (sin Postgres/Docker/CLI) |

### Verificación que SÍ se hizo en las apps (y la que no)

Hecho:
- `dart analyze` sobre los 8 archivos nuevos/modificados de `inventtia_flow` y los 9 de
  `ventiq_superadmin`: **sin errores** (los únicos errores del árbol son dos preexistentes en
  `ventiq_superadmin/test/supplier_payment_service_test.dart`, ajenos a esto).
- **Contraste clave por clave entre cada campo que lee la UI y el `jsonb_build_object` del RPC
  que lo sirve.** Así aparecieron y se corrigieron tres desajustes reales: `admin_plan_eliminar`
  devuelve `motivo` (no `mensaje`), `whatsapp_plantilla_mensaje` no existe en
  `suscripcion_config` (se quitó del formulario) y el botón "Ya he pagado" del cliente se
  apoyaba en un `estado` que el RPC de creación no devuelve.
- Chequeo estructural de los 4 `.sql` (`.dsh/verificar_sql.py`): bloques `$tag$` cerrados,
  paréntesis y comentarios equilibrados.
- **Suite completa de `inventtia_flow`: 280 tests en verde**, incluidos los 25 nuevos de
  `test/suscripcion_modelos_test.dart`, que fijan el contrato JSON de los cuatro RPC del
  cliente (`estado`, `planes`, intent, reporte, mis pagos) con fixtures copiados del SQL. Si
  alguien renombra una clave en las migraciones, el fallo sale ahí y no como una pantalla
  llena de "—".
- **Cableado de las notificaciones revisado en los dos sentidos**: los `perform` de
  `_susc_notificar_inapp` / `_susc_notificar_whatsapp` cubren pago reportado (al que paga y al
  dueño si es otro), plan acreditado por pago, pago rechazado con motivo, acreditación manual
  del superadmin, vence pronto, vencida en gracia y vencida definitiva. En la app, `tipo =
  'suscripcion'` tiene icono y etiqueta propios en la campana (antes caía en el genérico).
- **Revisión PostgreSQL de las 4 migraciones** (lista de comprobación de seguridad/rendimiento).
  Resultado: **sin defectos**, con estos puntos verificados uno a uno:

  | Comprobación | Resultado |
  |---|---|
  | `security definer` sin `set search_path` | 31/31 funciones lo fijan. Las 3 coincidencias de texto de la 43 son comentarios, no código |
  | RPC de admin sin comprobar superadmin | 13/13 llaman a `public.fn_is_superadmin_full_access()` |
  | Un `entidad_admin` no podría pagar | `_susc_caller_ve_entidad` cubre **owner + `flow.admin_entidades_de_usuario`** (Q2/Q8) |
  | Tablas sin RLS | 7/7 con `enable row level security` |
  | Permisos amplios | Todo con `revoke all ... from public` + `grant execute` por función y rol |
  | `timestamp` sin zona | 0; todo `timestamptz` |
  | Precio negativo | `precio numeric(12,2) check (precio >= 0)` (inline) + validación en la UI |
  | Duración absurda | `check (duracion_dias between 1 and 3650)` |
  | Acreditar días negativos | `_susc_acreditar_dias` rechaza `p_dias <= 0` y usa `greatest(..., now())`: nunca acredita hacia atrás |
  | `limites` con forma inesperada | `check (jsonb_typeof(limites) = 'object')` |
  | Coste por fila del predicado | `entidad_activa` se llama una vez por fila del catálogo; su lookup va por `idx_suscripcion_entidad` y `ux_suscripcion_entidad_viva` garantiza una sola fila viva, así que el `order by` es sobre 1–2 filas |

  Desviación consciente de la lista genérica: los estados y orígenes son `text` + `check (...
  in (...))` en vez de tipos `enum` nativos. Es la convención del resto del esquema `flow`, y
  un `enum` obligaría a migrar el tipo cada vez que se añada un estado. El `check` da la misma
  garantía de integridad.

No hecho, y hay que hacerlo al aplicar:
- Ejecutar el SQL contra Postgres. Nombres de columna, tipos y semántica de PL/pgSQL están
  revisados a mano contra `flow_schemma.sql` y las migraciones 40–42, pero **nada se ejecutó**.
- Prueba de extremo a extremo: crear entidad → ver trial → abrir Transfermóvil → "Ya he pagado"
  → aprobar en el panel → comprobar que la entidad vuelve a publicarse.

### Qué falta para que la fase 1 esté "viva"

1. Pegar `43`, `44`, `45`, `46` en el SQL Editor, **en ese orden**, en debug y en release.
2. Ejecutar la sección de verificación de cada archivo (al final de cada `.sql`).
3. Correr `select flow.admin_suscripcion_inicializar();` **una vez** para dar de alta la
   suscripción de las entidades que ya existen (sin esto siguen activas por grandfathering,
   pero no tienen fila ni trial contado).
4. Poner precio y activar los 3 planes semilla (nacen **desactivados** a propósito).

### Aviso honesto sobre la verificación

El entorno de esta sesión **no tiene Postgres, Docker ni la CLI de Supabase**, así que el SQL
se verificó por revisión estática + un chequeo estructural propio
(`.dsh/verificar_sql.py`: bloques `$tag$`, paréntesis, comillas, comentarios). **No se ejecutó
contra una base real.** Los errores que un chequeo así no puede detectar (nombres de columna,
tipos, semántica de PL/pgSQL) se revisaron a mano contra `flow_schemma.sql` y las migraciones
40–42; aun así, el primer pegado en el SQL Editor es la prueba de fuego.

---

## Decisiones ya cerradas (respuestas del usuario)

| # | Decisión | Respuesta |
|---|---|---|
| Q1 | Sujeto de la suscripción | ✅ **Por `entidad`** (cada entidad se suscribe por separado). |
| Q11 | Anti-abuso del trial | ✅ **1 trial por `owner_uuid`**: sólo la primera entidad recibe trial automático; las demás quedan bloqueadas hasta pagar. El superadmin puede forzarlo a mano. |
| Q7 | Desactivación por impago | ✅ **Predicado no destructivo**: `flow.entidad_activa()` compuesto con `_ls_disponible`. No se tocan las banderas `activo`. |
| Q8 | Panel del admin con suscripción vencida | ✅ **Sólo lectura + pagar**, con aviso permanente. |
| Q13 | Confirmación del pago | ✅ **Opción A** (deep link + "Ya he pagado" + código de confirmación + verificación manual del superadmin). El modelo queda preparado para enchufar un webhook (opción B) sin migrar. |
| Q19 | Canal de notificaciones | ✅ **In-app (`flow.notificaciones`) + WhatsApp automático desde el servidor** (Edge Function + WAPI). **Pendiente el número/bot emisor — ver Q33.** |
| Q27 | Migraciones | ✅ **El agente entrega los `.sql`; el usuario los pega** en el SQL Editor, numerados desde 43. |

---

## Parte A — Lo que ya verifiqué en el repo

### A.1 Modelo de datos de Flow (el "cliente" de la suscripción)

`flow.entidad` es el **tenant**. Es la unidad que se suscribe:

```
flow.entidad (id, denominacion, direccion, telefono, owner_uuid -> auth.users,
              horas_anticipacion_cancelacion)
  ├── flow.entidad_admin     (id_entidad, uuid_usuario)   ← quién administra
  ├── flow.entidad_vendedor  (id_entidad, uuid_usuario)   ← quién vende
  ├── flow.app_dat_locales   (id_entidad, activo, ...)    ← los "locales"
  │     └── flow.local_servicio (id_local, id_servicio, activo, ...)
  └── flow.app_dat_servicios (activo, ...)
```
Fuente: [flow_schemma.sql:134](inventtia_flow/docs/flow_schema/flow_schemma.sql#L134),
[entidad.dart](inventtia_flow/lib/models/entidad.dart).

### A.2 Ya existe UN predicado único de visibilidad (pieza clave)

La migración **40** introdujo tres banderas de publicación (`app_dat_locales.activo`,
`app_dat_servicios.activo`, `local_servicio.activo`) y **una sola** función que decide si un
local-servicio es visible/reservable para el cliente:

```sql
flow._ls_disponible(p_id_local_servicio) -- = l.activo and s.activo and ls.activo
```
Fuente: [40_activo_servicios_locales_turnos_horario.sql:145](inventtia_flow/docs/flow_schema/migraciones/40_activo_servicios_locales_turnos_horario.sql#L145).

Existe también `flow._caller_es_admin_de_ls(...)`, que permite al admin de la entidad seguir
viendo/operando lo que el cliente no ve. Esto es exactamente el gancho que necesita el
"desactivar la entidad por impago" sin tocar los datos del admin.

### A.3 `flow.plan_config` / `flow.plan_servicios` NO son esto (colisión de nombres)

`flow.plan_config` y `flow.plan_servicios` son la **planificación mensual de cupos por
servicio** (agenda recurrente). No tienen nada que ver con planes comerciales.
→ Los planes de suscripción deben llamarse distinto (`suscripcion_plan`). Ver pregunta **Q4**.

### A.4 Referencias reutilizables que ya existen en el repo

| Sistema | Dónde | Qué aporta |
|---|---|---|
| Licencias por "tienda" | `public.app_suscripciones`, `app_suscripciones_plan`, `app_dat_suscripcion_catalogo` + [licencias_screen.dart](ventiq_superadmin/lib/screens/licencias_screen.dart) + [catalog_subscription_cron.sql](ventiq_superadmin/database/catalog_subscription_cron.sql) | Patrón de estados, historial, renovación, agente asignado, cron de expiración. Es para Inventtia/Carnaval, **no para Flow**. |
| **Planes + solicitudes + aprobación** | `muevete.planes`, `muevete.suscripciones`, `muevete.solicitudes_plan`, `fn_aprobar_solicitud_plan`, `fn_rechazar_solicitud_plan`, `fn_crear_suscripcion_trial` + [muevete_planes_screen.dart](ventiq_superadmin/lib/screens/muevete/muevete_planes_screen.dart) | **La mejor plantilla.** Trial automático, solicitud con evidencia, aprobación manual, código de transferencia único (anti-reúso). |
| WAPI (WhatsApp) | `ventiq_admin_app/supabase/functions/wapi-send-products`, `_shared/wapi_client.ts` (`WAPI_BASE_URL`, `WAPI_API_KEY`), tablas `public.app_wapi_*` | Envío de WhatsApp **desde el servidor**. Está atado a un bot/sesión **por tienda**; Flow no tiene bot. |
| Notificaciones in-app | `flow.notificaciones` + realtime ([07_realtime_notificaciones.sql](inventtia_flow/docs/flow_schema/migraciones/07_realtime_notificaciones.sql)) + [notificacion_provider.dart](inventtia_flow/lib/providers/notificacion_provider.dart) | Canal nativo y ya funcionando para avisar al dueño/admin de la entidad. |
| Tolerancia a "tabla que aún no existe" | [esquema_pendiente.dart](inventtia_flow/lib/utils/esquema_pendiente.dart) | La app debe seguir funcionando antes y después de aplicar las migraciones. Requisito de diseño, no opcional. |

### A.5 El panel superadmin ya escribe en `flow`

`fidelidad_service.dart`, `campana_service.dart`, `coleccion_service.dart` y
`catalogo_destinos_service.dart` ya usan `.schema('flow')`. Añadir pantallas de suscripción de
Flow es continuidad, no una excepción. Rutas protegidas + permisos por rol viven en
[app_routes.dart](ventiq_superadmin/lib/config/app_routes.dart) (`AppRoutes.protected`),
`RouteGuard` y `SuperAdminRole.permisos`.

### A.6 Transfermóvil: **NO hay callback**. Verificado.

El usuario pidió específicamente comprobarlo. Conclusión: **no existe callback ni resultado de
retorno de la app Transfermóvil.** Evidencia:

1. El paquete Flutter público `transfermovil` (pub.dev, Android) sólo hace
   `android_intent_plus` para **abrir** la vista de pago en línea. No devuelve resultado.
2. La implementación de referencia de Carnaval **no** recibe nada: dispara el deep link con
   `launchUrl(..., externalApplication)` y detecta el regreso con
   `didChangeAppLifecycleState → resumed`, que sólo significa "la app volvió al frente".
   Fuente: [validacionform_widget.dart:131](C:/Users/cesar/Documents/carnavalAPP/lib/pages/validacionform/validacionform_widget.dart#L131)
   y [:512](C:/Users/cesar/Documents/carnavalAPP/lib/pages/validacionform/validacionform_widget.dart#L512).
3. El propio `transfermovil.txt` que compartió el usuario resuelve lo mismo a nivel Android:
   `launchIntentAndListenReturn` sólo observa `onResume` del ciclo de vida. **No hay
   `onActivityResult` con estado del pago.**
4. El "Ya he Pagado" de Carnaval sólo cambia `Orders.status = 'En Revision'`. **No manda
   WhatsApp** (eso es nuevo de este plan).

**Opciones reales de confirmación** (decisión del usuario, Q14):

- **(A) Como Carnaval — deep link + `resumed` + botón "Ya he pagado" + verificación manual.**
  Costo 0, sin dependencias. El pago se acredita cuando el superadmin lo comprueba en la
  plataforma bancaria. Es lo que se pide hoy.
- **(B) Agregador externo con confirmación automática.** Existe al menos un servicio
  cubano (CubaPay) que entrega **importe exacto + webhook firmado** confirmando el pago: se
  apoya en un terminal que lee el SMS del banco, no en Transfermóvil. Coste por transacción,
  dependencia de tercero y de un teléfono/servicio externo.
- **(C) Portal oficial de comercio** (p. ej. "Bulevar Mi Transfer" de ETECSA) para conciliar
  pagos a mano. Requiere cuenta de comercio y no expone API pública documentada.

Mi recomendación: implementar **(A) ahora**, dejando la tabla de transacciones preparada para
enchufar (B) por webhook sin cambiar el modelo (un campo `proveedor` y un
`payload_webhook jsonb`). Pregunta Q14.

### A.7 Reglas de trabajo de este repo (restricciones, no preguntas)

- **El agente no aplica SQL.** Las migraciones se escriben en
  `inventtia_flow/docs/flow_schema/migraciones/` y **el usuario las pega** en el SQL Editor.
  Deben ser idempotentes, reversibles, con verificación al final y pre-chequeo de
  dependencias. (Convención ya declarada en
  [README.md:79](inventtia_flow/docs/flow_schema/README.md#L79).)
- **Hay dos proyectos Supabase**: debug `qhprswhhfasrikhawjoz` y release
  `vsieeihstajlrdvpuooh`. Toda migración se aplica en **ambos**.
- La numeración libre en `migraciones/` empieza en **43**.
- **Prohibido** usar `carnavalapp.configuraciones_admin` para el intent de Transfermóvil
  (instrucción explícita del usuario). Todo va en tablas nuevas del schema `flow`.

---

## Parte B — Modelo propuesto (a confirmar)

### B.1 Tablas nuevas en `flow` (nombres propuestos, ver Q4)

```
flow.suscripcion_config          -- 1 fila. Lo que configura el superadmin.
  trial_meses_default, trial_auto, dias_gracia, dias_aviso_previo,
  soporte_whatsapp ('5354590207'), whatsapp_notif_activa,
  transfermovil_intent_template, transfermovil_url_template,
  transfermovil_numero_proveedor, transfermovil_titulo, moneda_default

flow.suscripcion_plan            -- planes comerciales (CRUD superadmin)
  codigo, nombre, descripcion, duracion_dias, precio, moneda,
  limites jsonb, orden, activo

flow.suscripcion                 -- suscripción de la entidad (una vigente + histórico)
  id_entidad, id_plan, estado, fecha_inicio, fecha_vencimiento,
  fecha_gracia_fin, origen, created_by

flow.suscripcion_intent          -- el "intent" de Transfermóvil (lo que pidió el usuario)
  id_entidad, id_plan, uuid_usuario, monto, moneda,
  id_transaccion (UNIQUE), numero_proveedor, url_intent, url_http,
  estado (creado|abierto|reportado|verificado|rechazado|expirado), expira_at

flow.suscripcion_transaccion     -- el pago reportado y verificado
  id_intent, id_entidad, codigo_confirmacion (UNIQUE), monto, moneda, metodo,
  comprobante_url, estado (reportado|verificado|rechazado),
  reportado_por, reportado_at, verificado_por, verificado_at, observaciones

flow.suscripcion_movimiento      -- libro mayor / auditoría (nunca se borra)
  id_entidad, id_suscripcion, id_transaccion, tipo (trial|acreditacion|renovacion|
  ajuste|expiracion), dias, fecha_desde, fecha_hasta, motivo, admin_uuid
```

`estado` de `flow.suscripcion`: `trial` · `activa` · `en_gracia` · `vencida` ·
`suspendida` (manual) · `cancelada`.

### B.2 Funciones RPC (todas devuelven `jsonb`, como el resto de `flow`)

| RPC | Quién | Qué hace |
|---|---|---|
| `flow.entidad_activa(id_entidad)` | interno | Predicado único de "al día". Se compone con `_ls_disponible` (§B.3). |
| `flow.suscripcion_estado_entidad(id_entidad)` | admin de la entidad | Estado, plan, vencimiento, días restantes, en gracia. |
| `flow.suscripcion_crear_intent(id_entidad, id_plan)` | owner/admin | Valida permisos, calcula monto, genera `id_transaccion` único (referencia interna; el link lleva `ESTATICO` fijo) y las 2 URLs desde la config. |
| `flow.suscripcion_reportar_pago(id_intent, codigo, comprobante)` | owner/admin | Crea la transacción `reportado` + notifica. |
| `flow.suscripcion_aprobar_pago(id_transaccion, ...)` | superadmin | Verifica, acredita días, renueva suscripción, escribe movimiento, notifica. |
| `flow.suscripcion_rechazar_pago(id_transaccion, motivo)` | superadmin | Rechaza con motivo; notifica. |
| `flow.suscripcion_acreditar(id_entidad, id_plan, dias, motivo)` | superadmin | Acreditación manual (incluye trial manual y "rellenar" plan). |
| `flow.suscripcion_otorgar_trial(id_entidad)` | trigger / superadmin | Otorga los X meses gratis por entidad nueva. |
| `flow.suscripcion_expirar()` | `pg_cron` | Pasa `activa → en_gracia → vencida`, notifica avisos. |

### B.3 Cómo se "desactiva la entidad" (sin romper nada)

**Recomendación: predicado, no bandera destructiva.**

Extender el único predicado que ya existe:

```sql
flow._ls_disponible(id) := l.activo and s.activo and ls.activo
                           and flow.entidad_activa(l.id_entidad)
```

Ventajas: reactivación instantánea al acreditar el pago; no se pierde la configuración de
publicación que el admin ya había hecho; no hay que recorrer ni reescribir locales/servicios;
es reversible y auditable. La alternativa (poner `activo = false` en todas las filas y
guardar un snapshot para restaurar) es destructiva, no atómica y puede pisar decisiones del
admin. Ver Q7.

### B.4 Superadmin — pantallas nuevas

- Ruta `/flow-suscripciones` (grupo nuevo **"Flow"** en `AppRoutes.protected`), con
  `RouteGuard`: listado de entidades con estado, plan, vencimiento, días restantes y filtros
  (*por vencer*, *en gracia*, *vencidas*, *con pago reportado*).
- Detalle de entidad: historial de suscripciones, transacciones, movimientos; acciones
  **Acreditar meses**, **Aprobar pago**, **Rechazar pago**, **Cambiar plan**, **Suspender/Reactivar**.
- Sub-pantallas: **Planes** (CRUD `flow.suscripcion_plan`) y **Configuración**
  (`flow.suscripcion_config`: trial, gracia, WhatsApp de soporte, plantillas del intent).

### B.5 Flow — pantallas y aviso permanente

- **"Mi suscripción"** en el panel de la entidad: estado, vencimiento, días restantes, tarjetas
  de planes, botón **Pagar con Transfermóvil**, número de transacción visible, botón
  **"Ya he pagado"**, historial.
- **Aviso permanente** ("no ha pagado la suscripción") en el panel mientras el estado sea
  `trial por vencer`, `en_gracia` o `vencida` — es requisito explícito del usuario.
- Comportamiento en `vencida`: el catálogo del cliente ya no muestra la entidad (vía §B.3);
  el admin sigue entrando pero queda restringido (Q8).

### B.6 Notificaciones (requisito explícito)

| Evento | Destinatario | Canal propuesto |
|---|---|---|
| Pago reportado ("Ya he pagado") | Soporte `54590207` + cliente | WhatsApp + `flow.notificaciones` |
| Pago aprobado / plan acreditado | Cliente | WhatsApp + `flow.notificaciones` |
| Próximo a vencer (X días antes) | Cliente | `flow.notificaciones` (+ WhatsApp si Q13 = sí) |
| Entró en gracia / vencida | Cliente | Ambas |
| Pago rechazado | Cliente | Ambas |

### B.7 Mensaje de WhatsApp de "Ya he pagado" (borrador a aprobar, Q20)

```
Yo {nombre del owner} he pagado el plan {plan} para la entidad {entidad}
por {monto} {moneda}. Referencia de soporte: {id_transaccion}.
Código de confirmación: {codigo_confirmacion}.
Espero por la acreditación del plan. Gracias.
```
Enviado a `wa.me/5354590207` (o el número que responda Q5/Q18).
La referencia `{id_transaccion}` es la interna (`FLW-…`), para que soporte localice el
intento en el panel; el id que muestra la app de Transfermóvil siempre es `ESTATICO`.

---

## Parte C — Preguntas pendientes

Responder por número. **"OK"** = aplico la recomendación.
Las preguntas **Q1, Q7, Q8, Q11, Q13, Q19 y Q27 ya están cerradas** (ver tabla al inicio);
quedan abiertas las demás. Lo que no se responda, se implementa con la recomendación indicada.

### Bloque 1 — Sujeto y reglas de negocio

**Q1. ¿La suscripción se ata a la `entidad` o al `owner_uuid`?**
El usuario dijo "por cada entidad". Para un owner con 3 entidades: ¿3 trials y 3 suscripciones
independientes? **Recomiendo: sí, por `entidad`** (es lo coherente con "por cada entidad" y con
que se desactiva "su entidad y todos sus locales").

**Q2. ¿Quién puede pagar la suscripción de una entidad?**
(a) sólo el `owner_uuid`; (b) el owner y cualquier `entidad_admin`; (c) owner, admins y
vendedores. **Recomiendo (b).** Cliente real: el dueño delega y el admin de la entidad es quien
paga en la práctica.

**Q3. ¿Los planes se diferencian sólo por duración/precio, o también por límites funcionales?**
Ejemplos de límite: nº de locales, nº de servicios, nº de usuarios de staff, acceso a
promociones/patrocinados/colecciones. **Recomiendo: nace con `limites jsonb` aunque hoy sólo se
usen duración y precio**, para no migrar después. ¿Qué límites quiere realmente en v1?

**Q4. Nombres de las tablas.**
`flow.plan_config` y `flow.plan_servicios` **ya existen** y son otra cosa (cupos mensuales), así
que usar "plan" a secas es ambiguo. **Recomiendo** `flow.suscripcion_plan`, `flow.suscripcion`,
`flow.suscripcion_intent`, `flow.suscripcion_transaccion`, `flow.suscripcion_movimiento`,
`flow.suscripcion_config`. ¿Se aprueba o prefiere otros nombres?

**Q5. ¿Mes gratis = días o mes calendario?**
"Meses gratis" ¿son 30 días exactos o "hasta el mismo día del mes siguiente"? Y el vencimiento
de un plan de 1 mes, ¿30 días desde el pago o fecha fija de calendario? **Recomiendo días
exactos** (30/90/365) con hora, que es lo más predecible y no depende del mes en que se pague.
Fuente: muevete hace lo contrario (fuerza "día 2 del mes"), por eso lo pregunto.

**Q6. ¿La semana de gracia son 7 días fijos o configurables?**
**Recomiendo: configurables por superadmin con default 7**, y que el usuario vea exactamente la
fecha/hora en que se corta.

**Q7. Al vencer + gracia, ¿cómo se "desactiva la entidad"?**
(a) **predicado no destructivo** (§B.3); (b) poner `activo = false` en locales/servicios/pares
y guardar snapshot para restaurar. **Recomiendo (a)** por reactivación instantánea y por no
pisar la configuración del admin. ¿De acuerdo?

**Q8. Con la suscripción vencida, ¿qué puede hacer el admin de la entidad?**
(a) entra y sólo puede pagar (todo lo demás bloqueado); (b) entra en **sólo lectura** y puede
pagar; (c) sin restricción en el panel, sólo se oculta al cliente final. **Recomiendo (b):**
sólo lectura + pagar. Pregunto también: ¿qué pasa con las **reservas ya creadas** y la
**agenda futura** al vencer? ¿Se cancelan, se mantienen, o se mantienen pero no se admiten
nuevas?

**Q9. "Rellenar su plan" = ¿acreditar más tiempo?**
¿Se **suma** al vencimiento actual o se **reinicia** desde hoy? **Recomiendo sumar** (más justo
si paga antes de vencer). ¿Aplica también a los meses de trial, o el trial se "pierde" al
comprar un plan?

**Q10. ¿El trial se otorga automáticamente o a mano?**
El usuario dijo "configurable por el superadmin se le dará a los usuarios x meses gratis por
cada entidad". Dos lecturas:
(a) al crear la entidad, el sistema le acredita automáticamente los X meses configurados;
(b) el superadmin los acredita manualmente cuando quiere.
**Recomiendo (a) con interruptor `trial_auto` en la config** (permite las dos).

**Q11. Anti-abuso del trial.**
El trial "por entidad" es farmeable: crear 10 entidades = 10 trials. ¿Poner límite?
**Recomiendo: 1 trial por `owner_uuid`** (las entidades 2ª, 3ª… no reciben trial automático y
quedan bloqueadas hasta pagar), y que el superadmin pueda forzarlo a mano. ¿De acuerdo?

**Q12. Moneda y precios.**
Transfermóvil opera en CUP (y MLC). ¿Los planes se definen en **CUP**, en **USD**, o en **ambas
monedas** (como Carnaval, que tenía flujos separados CUP/USD/EUR)? **Recomiendo CUP** en v1,
con el campo `moneda` en `suscripcion_plan` para añadir MLC/USD después sin migrar.

### Bloque 2 — Pago con Transfermóvil

**Q13. Confirmación del pago: ¿(A) manual, (B) agregador con webhook, o (C) portal de comercio?**
Ver §A.6. **Recomiendo (A) ahora**, con el modelo preparado para (B). Si elige (B) o (C),
necesito saber: ¿ya tiene contrato/cuenta con ese servicio?, ¿quién paga la comisión?, y ¿tiene
el `numero_proveedor` de comercio de Flow?

**Q14. Datos del comercio para el intent de Flow.**
Carnaval usaba `numero_proveedor=4055432` y `titulo/set_title=Carnaval Alimentos`. ¿Cuál es el
**número de proveedor** y el **título** de Flow (GoReserva)? Sin estos datos el intent no se
puede armar. ¿Se configuran desde el superadmin (`flow.suscripcion_config`) o se fijan en el código?
**Recomiendo configurarlos desde el superadmin**, como en Carnaval.

**Q15. ¿Se pide al cliente el código/número de confirmación de Transfermóvil?**
Es la principal defensa anti-fraude (y lo que ya hace muevete con `codigo_transferencia`
`UNIQUE`; Carnaval muestra el nº de confirmación al usuario). **Recomiendo sí, obligatorio**,
único en `flow.suscripcion_transaccion.codigo_confirmacion`, y que el superadmin lo use para
verificar. ¿De acuerdo?

**Q16. ¿Se obliga a subir foto del comprobante?**
muevete lo exige (Supabase Storage). **Recomiendo opcional en v1** (obligarlo mete fricción y
la verificación real la hace el superadmin contra el banco), pero el campo y el bucket quedan
creados. ¿Obligatorio, opcional o fuera de v1?

**Q17. Duración del intent.**
¿Cuánto vale un intent antes de expirar? **Recomiendo 24 h** y que al expirar se marque
`expirado` y se pueda generar otro.

> **Resuelto con un dato del usuario (12/10/2026):** el `id_transaccion` del link de pago es
> SIEMPRE el literal `"ESTATICO"` — un bug de la app de Transfermóvil, que ignora el id que se
> mande (en carnavalAPP se llegó a generar un txId único por pago y se acabó comentando:
> `validacionform_widget.dart:530`). El link lleva `id_transaccion=ESTATICO` fijo; el
> `FLW-…` que genera el servidor queda como **referencia interna**: soporte la pide para
> localizar el intento en el panel, y no viaja en el link.

**Q18. ¿Sólo Transfermóvil en v1, o también Zelle/Stripe/TropiPay?**
Carnaval tiene `stripe_payment`, `numero_zelle_pagos`, `enlace_pago_tropipay`.
**Recomiendo sólo Transfermóvil en v1**, dejando `metodo` en la tabla de transacciones.

### Bloque 3 — Notificaciones y WhatsApp

**Q19. Canal para "notificar al cliente cuando paga y cuando se le activa/rellena el plan".**
(a) `flow.notificaciones` in-app (ya existe, con realtime) + WhatsApp por deep link/manual;
(b) (a) + **WhatsApp automático desde el servidor** (reusar la infra WAPI con una Edge Function
nueva, requiere un bot/sesión de Flow y un número emisor);
(c) sólo in-app.
**Recomiendo (b) para pago reportado y acreditación, y (a) para el resto** — pero necesita un
número emisor de WhatsApp con WAPI y saber quién lo opera. ¿Hay bot para Flow? Si no, (a).

**Q20. Número de soporte `54590207`.**
¿Se normaliza a `+53 54590207` (`wa.me/5354590207`)? ¿Va como **default en
`flow.suscripcion_config`** editable por el superadmin? **Recomiendo sí a ambas.** ¿El mensaje
de "Ya he pagado" lo aprueba tal cual lo redacté en §B.7?

**Q21. ¿Al superadmin le llega aviso en la app cuando un cliente reporta un pago?**
Además del WhatsApp al 54590207. **Recomiendo sí:** la bandeja de `flow-suscripciones` con
contador de "pagos por verificar" (es lo que evita que un pago quede olvidado). ¿De acuerdo?

### Bloque 4 — Superadmin y roles

**Q22. ¿Qué roles/permisos del superadmin pueden ver y acreditar?**
`SuperAdminRole.permisos` ya existe. **Recomiendo un permiso nuevo `flow_suscripciones`** (ver)
y `flow_suscripciones_gestionar` (acreditar/aprobar), y que el rol "super admin" los tenga por
defecto. ¿Nombres de permiso preferidos? ¿Algún rol debe quedar fuera?

**Q23. ¿La acreditación manual debe permitir saltarse el flujo de pago?**
Es decir: botón "Acreditar N meses" sin transacción asociada (cortesía, compensación, error).
**Recomiendo sí, con `motivo` obligatorio y registro en `suscripcion_movimiento`** (auditoría).

**Q24. ¿Dónde va la sección en el menú del superadmin?**
Grupo nuevo **"Flow"** (coherente con "Muévete"/"Carnaval"), con rutas `/flow-suscripciones`,
`/flow-planes`, `/flow-config`. ¿De acuerdo, o prefiere colgarlo del grupo "Licencias"?

**Q25. ¿Los planes los crea el superadmin desde la app o se siembran por SQL?**
**Recomiendo CRUD completo en el superadmin** (como Muévete) + un seed inicial en la migración
con planes de ejemplo desactivados.

### Bloque 5 — Alcance, entrega y verificación

**Q26. ¿Alcance = sólo `inventtia_flow` + `ventiq_superadmin`?**
¿O la entidad de Flow también se muestra en `ventiq_marketplace` (catálogo de la suite) y ahí
debe aparecer el estado de impago? **Recomiendo limitar a Flow + superadmin en v1.** Si el
marketplace lista entidades de Flow, hay que decidir qué hacer con las vencidas.

**Q27. Migraciones: ¿se entregan para pegar o se pueden aplicar?**
La convención del repo dice que **el agente no aplica SQL**; el usuario pega en el SQL Editor y
hay **dos proyectos** (debug y release). **Recomiendo seguir la convención**: entrego
`migraciones/43_*.sql` … `migraciones/NN_*.sql` idempotentes, reversibles y con verificación, y
el usuario los aplica. ¿Confirma? ¿Los aplico también en el proyecto debug para poder probar?

**Q28. ¿Cómo probamos sin cobrar de verdad?**
**Recomiendo:** un flag en `flow.suscripcion_config` (`modo_prueba`) que permita generar intents
de monto mínimo o simulados, más scripts en `docs/flow_schema/pruebas/` que terminen en
`ROLLBACK`. ¿De acuerdo? ¿Hay un usuario/entidad de pruebas en el proyecto debug?

**Q29. ¿Versionado y changelog?**
`inventtia_flow/CHANGELOG.md` está en `1.1.0+2` y `pubspec.yaml` en `1.3.3+7` (desincronizados).
¿Subo `pubspec.yaml` a `1.4.0+N` y añado la entrada del changelog, o lo dejo en manos del
usuario? **Recomiendo que sí lo actualice yo.** ¿Y el `assets/changelog.json` del superadmin?

**Q30. ¿Prioridad/fases de entrega?**
**Recomiendo 4 fases:** (1) SQL + RPC + trial + expiración; (2) pantalla "Mi suscripción" y
aviso permanente en Flow; (3) intent Transfermóvil + "Ya he pagado" + WhatsApp; (4) panel
superadmin de acreditación. ¿Otro orden? ¿Alguna fase que deba entrar en v1 sí o sí?

**Q31. ¿La suscripción vencida afecta al personal de la entidad (vendedores) o a los datos
históricos?**
**Recomiendo: sólo se corta la visibilidad/reserva en el catálogo y las escrituras del admin;
las reservas históricas, reportes y datos se conservan íntegros** (nada se borra). ¿De acuerdo?

**Q32. Vacaciones/períodos sin cobro.**
¿Hace falta **suspender voluntariamente** una entidad (temporada cerrada) sin que cuente como
impago? **Recomiendo sí, estado `suspendida`** distinto de `vencida`. ¿Lo quiere en v1?

**Q33. (nueva, derivada de Q19) ¿Qué número/bot emite los WhatsApp automáticos de Flow?**
Se decidió WhatsApp automático desde el servidor. La infraestructura WAPI del repo
(`wapi_client.ts`, `WAPI_BASE_URL` + `WAPI_API_KEY`) trabaja con **una sesión/bot por tienda**,
dada de alta escaneando un QR. Para Flow necesito saber:
(a) ¿existe ya un **número de WhatsApp dedicado a Flow** que podamos conectar como bot?, o
(b) ¿se reutiliza un bot existente (¿cuál?), o
(c) mientras no haya bot, ¿el WhatsApp automático degrada a deep link `wa.me` abierto por la app?
**Recomiendo (a) y, si no está disponible aún, (c) como respaldo** — nunca bloquear la
acreditación porque falle un envío de WhatsApp (se registra el intento y se sigue).

**Q34. (nueva) Datos del comercio Transfermóvil de Flow** (bloquea la implementación del intent).
¿Cuál es el **`numero_proveedor`** y el **título** (`titulo` / `set_title`) de Flow para el pago
en línea? Carnaval usa `4055432` + "Carnaval Alimentos"; necesito los de GoReserva. ¿Se cargan
desde el superadmin o los fijo en el código? **Recomiendo cargarlos desde el superadmin**
(`flow.suscripcion_config`), con valores iniciales en el seed de la migración.

---

## Parte D — Cuando Q1–Q32 estén cerradas, el plan de ejecución es

1. **Migraciones** (`inventtia_flow/docs/flow_schema/migraciones/`, numeradas desde 43):
   tablas + RLS + índices + `flow.entidad_activa` + composición con `_ls_disponible` +
   triggers de trial + `flow.suscripcion_expirar()` + `pg_cron` + seed de config y planes.
   Cada archivo: idempotente, reversible con SQL de vuelta atrás en la cabecera, pre-chequeo de
   dependencias y consulta de verificación al final.
2. **RPC** en `docs/flow_schema/rpc admin/` (nuevos archivos) y `rpc clientes/` si aplica.
3. **Flow (Dart)**: modelos, `suscripcion_service.dart`, `suscripcion_provider.dart`,
   pantalla "Mi suscripción", banner permanente, intent Transfermóvil + retorno por
   `WidgetsBindingObserver`, botón "Ya he pagado", integración con `flow.notificaciones`.
   Todo tolerante a esquema ausente con `esquema_pendiente.dart`.
4. **Superadmin (Dart)**: `suscripcion_service.dart`, ruta + `RouteGuard` + drawer + permisos,
   pantallas de listado/detalle/planes/configuración.
5. **Verificación**: migraciones aplicadas en debug, `flutter analyze` en las dos apps,
   pruebas de `pruebas/` con `ROLLBACK`, y prueba manual end-to-end del ciclo
   `trial → por vencer → gracia → vencida → pago reportado → acreditación → reactivada`.

**Criterio de aceptación (borrador, se cierra con las respuestas):**
una entidad sin pagar deja de aparecer y de poder reservarse en Flow exactamente al terminar la
gracia; el admin ve en todo momento que no está al día; al acreditar el pago se reactiva al
instante sin perder configuración; y queda traza completa y auditable de cada intent,
transacción, movimiento y notificación.
