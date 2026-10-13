# Flow — Esquema `flow`

Backend en Supabase/PostgreSQL para gestión de **entidades**, **locales**, **servicios**, **salas de espera** (colas) y **agendas** (reservas). Toda la lógica de negocio vive en funciones RPC que devuelven `jsonb`, y un "bot" en segundo plano mueve gente de la cola a la agenda.

## Estructura de carpetas

```
flow_schema/
├── flow_schemma.sql          # Definición de tablas (solo contexto, no ejecutar)
├── README.md                 # Este archivo
├── BASE_CONOCIMIENTO.md      # Catálogo detallado de cada RPC (entradas/salidas)
├── migraciones/              # Cambios estructurales — ejecutar UNA vez, en orden
│   ├── 01_add_agendados_plan_servicios.sql
│   ├── 02_tabla_fraude.sql
│   ├── 03_seed_estado_agendado.sql
│   ├── 04_indices_entidad.sql
│   ├── 08_local_servicio_reserva_directa.sql   # flag permite_reserva_directa
│   └── 09_tabla_plan_config.sql                # config recurrente + RLS
├── rpc clientes/             # RPC para la app del cliente final + lógica del bot
│   ├── 00_indices_sala_espera.sql
│   ├── 01_obtener_locales.sql
│   ├── 02_obtener_servicios.sql                # ahora incluye permite_reserva_directa
│   ├── 03_obtener_salas_espera.sql
│   ├── 04_obtener_agendas.sql
│   ├── 05_entrar_sala_espera.sql
│   ├── 06_salir_sala_espera.sql
│   ├── 07_procesar_plan_servicio.sql
│   ├── 08_bot_sweep_y_trigger.sql
│   ├── 09_listar_servicios.sql
│   ├── 10_cliente_disponibilidad.sql           # días con cupo (calendario reservar)
│   └── 11_cliente_reservar_directo.sql         # reserva directa sin cola
└── rpc admin/                # RPC para el panel de administración (por entidad)
    ├── 00_helper_entidades_usuario.sql
    ├── 01_admin_listar_locales.sql
    ├── 02_admin_listar_servicios.sql
    ├── 03_admin_listar_locales_servicios.sql
    ├── 04_admin_listar_agendas.sql
    ├── 05_admin_listar_entidades.sql
    ├── 06_admin_listar_salas_espera.sql
    ├── 07_admin_reserva_directa.sql            # toggle permite_reserva_directa
    ├── 08_admin_config_plan.sql                # guardar/obtener config recurrente
    └── 09_admin_generar_plan_mensual.sql       # generar planes del mes en lote
└── pruebas/                  # comprobaciones manuales, NO son migraciones
    └── prueba_reserva_directo_promociones.sql  # precios/promos en BEGIN..ROLLBACK
```

> **`pruebas/` no se aplica nunca.** Son scripts que se pegan en el SQL Editor y
> terminan en `ROLLBACK`: verifican comportamiento sin dejar rastro (ni agenda,
> ni cupo, ni promoción). Si un script de `pruebas/` sale con `fallan > 0`, lo
> que hay que arreglar es el código o la base, no el script.

## Orden de instalación

Ejecutar en el **SQL Editor** de Supabase, en este orden:

1. **`migraciones/`** completo, en orden numérico. Las del marketplace/Home van
   después del esquema base y **en este orden**: `22` (categorías) → `23`
   (reasignar servicios) → `24` (fix IDOR admin) → `25` (favoritos) → `26`
   (reseñas) → `27` (promociones) → `28` (patrocinados) → `29` (bots con promo)
   → `30` (colecciones temáticas) → `31` (fidelidad: puntos y beneficio) → `32`
   (fidelidad: configuración y auditoría del panel) → `33` (interruptor global
   de fidelidad) → `34` (el descuento de bienvenida aplicado al precio) → `35`
   (Home feed) → `36` (ranking semanal) → `37` (Realtime de la agenda) → `38`
   (el turno elegido en la lista de espera) → `39` (arreglo: `resenas_recientes`
   no encontraba el local) → `40` (`_ls_disponible`, el único predicado de
   visibilidad) → `41` (dashboard admin: modo y horas) → `42` (filtro de activos
   y horarios + triggers `trg_agenda_ls_disponible`) → `43` → `44` → `45` → `46`
   (**suscripciones**, en ese orden exacto: ver la sección siguiente).
2. **`rpc clientes/00_indices_sala_espera.sql`** (índices de apoyo).
3. El resto de **`rpc clientes/`** (cualquier orden; el 08 depende del 07; el 10 y 11 dependen de las migraciones 08/09).
4. **`rpc admin/00_helper_entidades_usuario.sql`** primero, luego el resto de `rpc admin/` (07/08/09 dependen del helper y de la migración 09).

> El helper `admin_entidades_de_usuario` debe existir antes que las demás RPC admin, porque todas lo usan.

### Suscripciones de entidad (43 → 46)

El módulo que cobra el uso de la plataforma por entidad. **El orden importa**,
porque `44` recompone `_ls_disponible` y `45`/`46` dependen de las tablas y del
helper de autorización:

| # | Archivo | Qué hace |
|---|---------|----------|
| 43 | `43_suscripciones_tablas.sql` | 7 tablas nuevas en `flow`: `suscripcion_config` (1 fila), `suscripcion_plan`, `suscripcion`, `suscripcion_intent`, `suscripcion_transaccion`, `suscripcion_movimiento`, `suscripcion_notificacion`. RLS + grants. |
| 44 | `44_suscripciones_predicado_trial.sql` | `flow.entidad_activa(id)` (predicado único), `_ls_disponible` v2 que lo compone, trial automático al crear la entidad, `cliente_estado_suscripcion`, `cliente_planes_suscripcion`. |
| 45 | `45_suscripciones_pagos.sql` | Circuito de pago: `cliente_crear_intent_suscripcion`, `cliente_reportar_pago_suscripcion` ("Ya he pagado"), `cliente_mis_pagos_suscripcion`, `admin_suscripcion_aprobar/rechazar_pago`, `admin_suscripcion_acreditar`, `suscripcion_expirar`. |
| 46 | `46_suscripciones_admin_cron_seed.sql` | Panel: `admin_suscripcion_listar/detalle/inicializar/suspender/reactivar`, CRUD de planes y config, outbox de WhatsApp, cron cada 15 min, seed de 3 planes **desactivados**. |
| 47 | `47_categorias_reales_subcategorias.sql` | Taxonomía de **dos niveles**: `id_padre` + `orden` en `nom_tipo_actividad_servicio`, trigger de máximo 2 niveles, RLS de escritura abierta al superadmin, RPC de gestión reescritos (`admin_guardar/alternar/eliminar_tipo_actividad`) y seed de las 6 categorías reales con 5 subcategorías cada una. Reasigna los servicios existentes. |
| 48 | `48_home_feed_categorias_subcategorias.sql` | `cliente_home_feed` con `p_id_subcategoria` y nomenclador con `subcategorias` anidadas; `cliente_obtener_servicios` emite `id_padre` y `nombre` dentro de `tipo_actividad`. |
| 49 | `49_campanas_datos_local.sql` | `campanas_activas` devuelve los datos del **local** de cada campaña patrocinada (foto, descripción, dirección, provincia, país, horario, coordenadas, teléfono). |

### Taxonomía de dos niveles (migraciones 47, 48 y 49)

Lo que un futuro lector no puede deducir del código:

- **`id_padre` en la misma tabla, no una tabla de subcategorías.** El servicio
  sigue apuntando a **una sola fila**: si esa fila tiene `id_padre`, es una
  subcategoría y su categoría es el padre. No hay columna nueva en
  `app_dat_servicios` ni migración de datos de servicios.
- **Los códigos de las hojas NO cambian, y eso es obligatorio.** De
  `transporte_omnibus` dependen `LocalServicio.esTransporteOmnibus`
  (`lib/models/servicio.dart`) y los RPC de pasajes. Por eso las filas viejas
  (`unas`, `cejas_pestanas`, `peluqueria`, `estetica_spa`, `transporte_omnibus`,
  `transporte_privado`) se **reutilizan** como subcategorías conservando el
  código: los servicios que ya las usaban quedan reclasificados sin mover una
  fila.
- **Máximo dos niveles** (trigger `trg_nom_tipo_actividad_jerarquia`): una
  subcategoría no puede tener hijas y una categoría con hijas no puede
  convertirse en subcategoría. Sin esa regla, "categoría → subcategoría →
  servicio" dejaría de tener una interpretación única.
- **Nada se borra: se desactiva.** La taxonomía de prueba (`salud`, `hogar`,
  `mascotas`, `eventos`, `tecnologia`, `general`…) queda inactiva porque hay
  reservas históricas y FK que referencian esos códigos. `general` sobrevive como
  cajón de sastre inactivo.
- **Apagar una categoría apaga sus subcategorías** (`admin_alternar_tipo_actividad`):
  dejarlas encendidas las sacaría en un riel que ya no se muestra.
- **La app degrada sin las migraciones.** `TipoActividadService` reintenta la
  lectura sin `id_padre`/`orden` y cae al RPC de 4 argumentos; el Home, el
  catálogo y el detalle se pintan igual, solo que sin segundo nivel.
- **No se aplican solas.** El MCP de Supabase de este proyecto es de **solo
  lectura**, así que los `.sql` se quedan en el repo y se ejecutan a mano en el
  SQL Editor, **en orden 47 → 48 → 49**.

Decisiones que un futuro lector no puede deducir del código:

- **Sin fila de suscripción, la entidad está ACTIVA** (`coalesce(..., true)` en
  `entidad_activa`). Es *grandfathering*: aplicar la migración 44 no apaga a
  todas las entidades existentes. El backfill es explícito y manual:
  `flow.admin_suscripcion_inicializar()`.
- **El corte no depende del cron.** `entidad_activa` compara fechas, así que una
  entidad impagada deja de mostrarse aunque el cron no corra. Si `pg_cron` no
  está disponible, la migración 46 avisa y sigue.
- **El cliente no puede activar nada.** Ningún RPC de cliente acredita tiempo;
  "Ya he pagado" solo encola la verificación, y `admin_suscripcion_*` exige
  `public.fn_is_superadmin_full_access()`.
- **Transfermóvil no da callback.** El flujo es deep link + botón "Ya he pagado"
  + código de confirmación único + verificación manual del superadmin en el
  banco. Sin código no hay acreditación; el `UNIQUE` impide reusar un pago.
- **Acreditar SUMA**, no reinicia: los días se añaden a lo que quede vigente (o a
  `now()` si ya venció).
- **Sin bot de WhatsApp todavía** (`whatsapp_bot_activo = false`): los avisos al
  soporte quedan en el outbox como `omitida` y la app ofrece el deep link
  `wa.me`. La cola `pendiente` se activa sola cuando exista el bot.

Detalle de cada pregunta abierta y su respuesta: `../../PLAN_SUSCRIPCIONES.md`.

### Reserva directa + planificación recurrente (nuevo)

- **Migración 08** añade `flow.local_servicio.permite_reserva_directa` (bool, default false). Si está activo, el cliente puede **reservar directo** (sin cola) cuando hay un `plan_servicios` con cupo ese día.
- **Migración 09** crea `flow.plan_config` (config recurrente de capacidades por día de la semana, 1 fila por `local_servicio`) con su RLS.
- **`cliente_reservar_directo`** crea la agenda al instante (estado `Reservado`) y suma `agendados`, serializando con la cola/bot por el mismo advisory lock.
- **`admin_generar_plan_mensual`** crea/actualiza los `plan_servicios` de un mes a partir de `plan_config`; el trigger del bot reparte la cola pendiente automáticamente.

## Convenciones

- **Todo cambio de escritura (DDL/DML) va a un archivo `.sql` en `migraciones/`,
  con su número y un comentario de cabecera.** El agente **no aplica SQL**: el MCP
  de Supabase de esta sesión está en modo solo lectura, así que las migraciones
  las pega el usuario en el **SQL Editor**. Cada archivo debe ser:
  - **idempotente** (re-ejecutarlo deja el mismo estado),
  - **reversible**, con el SQL de vuelta atrás documentado en la cabecera,
  - con una **consulta de verificación** al final,
  - y con una **comprobación previa** que aborte con un mensaje claro si falta la
    migración de la que depende (en vez de dejar el esquema a medias).
- **Hay dos proyectos Supabase:** `qhprswhhfasrikhawjoz` (debug, `flutter run`)
  y `vsieeihstajlrdvpuooh` (release). Las migraciones se aplican en **ambos**, o
  el comportamiento diferirá entre debug y release.
- **Todo devuelve `jsonb`.** Las funciones de lista devuelven un array (`[]` si no hay datos). Las de acción (entrar/salir) devuelven `{ ok: bool, data | error }`. Así se puede cambiar la forma de la respuesta sin `DROP`/recrear.
- **`security invoker`** en las RPC de usuario → respetan RLS del que llama.
- **`security definer`** solo en el bot (`bot_procesar_plan`, `bot_sweep`, triggers) → necesita escribir en varias tablas; concedido únicamente a `service_role`.
- **Autorización: siempre `auth.uid()`, nunca un parámetro.** En una función
  `security definer` el `p_uuid_usuario` que envía el cliente es **suplantable**:
  basta pasar el uuid de otro administrador. Ver `24_fix_idor_rpc_admin.sql`.
  - **Excepción conocida, sin corregir:** `cliente_reservar_directo`,
    `cliente_cancelar_reserva` y `cliente_actualizar_fecha_regla` siguen siendo
    `security definer` y usan `p_uuid_usuario` **sin** compararlo con
    `auth.uid()`. `cotizar_reserva` y `cliente_reservar_pasaje_omnibus` sí lo
    comprueban. Ver §5.c de `plan.md`.
- **Aislamiento por entidad (admin):** cada RPC admin filtra por
  `admin_entidades_de_usuario(auth.uid())`, así un admin solo ve datos de **sus**
  entidades aunque mande otro `id_entidad` por parámetro.
- **Concurrencia de colas:** `entrar`, `salir` y el bot comparten un `pg_advisory_xact_lock(hashtext('flow.sala_espera'), id_local_servicio)` → serializan por servicio sin bloquear la tabla.

## Cómo llamar desde Supabase JS

```js
// Las funciones viven en el schema `flow`
const { data, error } = await supabase
  .schema('flow')
  .rpc('cliente_obtener_locales', { p_id_entidad: 2 });

// Acción con resultado { ok, data | error }
const { data: res } = await supabase
  .schema('flow')
  .rpc('cliente_entrar_sala_espera', {
    p_uuid_usuario: userId,
    p_id_local_servicio: 5,
  });
```

## Lista de espera con turno

Anotarse en la cola pide también el día y, si el servicio trabaja por turnos, el
turno (igual que la reserva directa): la pantalla del servicio llama a
`cliente_obtener_disponibilidad` y guarda la elección en
`flow.sala_espera.id_turno`.

- **Migración 38** hace que `cliente_obtener_salas_espera` y
  `admin_listar_salas_espera` devuelvan `id_turno` y `turno`, y alinea el
  pre-chequeo de duplicado de `cliente_entrar_sala_espera_reserva` con el índice
  real `unique_usuario_servicio_activo`.
- **Sigue habiendo una sola entrada por (usuario, servicio-local).** El turno es
  la *preferencia* dentro de esa entrada, no una segunda cola; el bot
  (`bot_procesar_recurso_dia`) ya lo respeta (`se.id_turno = p_id_turno`, con
  respaldo para las entradas viejas sin turno). El porqué de no ampliar el índice
  está en la cabecera de la migración 38.
- El cliente tolera que la migración no esté aplicada: `SalaEspera.fromJson` lee
  el turno como opcional y la pantalla dice "cualquier turno".

## Feed de reseñas (`resenas_recientes`)

El Home pide las reseñas con comentario vía `flow.resenas_recientes`.

- **Migración 39** (`migraciones/39_resenas_recientes_fix.sql`) arregla un error
  que dejaba el feed **siempre vacío**: la función unía el local con
  `ls.local`, una columna que no existe (la real es `ls.id_local`), así que
  respondía `42703 column ls.local does not exist`.
- **Por qué tardó en verse:** en PostgreSQL el cuerpo de una función `plpgsql` no
  se valida al crearla, solo en la primera ejecución. Un `create or replace`
  aparentemente correcto puede dejar una función rota. Al tocar una función,
  llamarla una vez contra la base es parte de la verificación.
- La migración 26 del repo ya viene corregida, pero en cualquier base donde se
  aplicó antes hay que pegar la **39** (re-despliega solo esa función).

## Publicación, modos de gestión y horario estructurado (migraciones 40, 41 y 42)

Las tres se aplican **en orden** y son aditivas: al migrar, **nada cambia de
visibilidad** (todo arranca `activo = true`). Están escritas para aplicarse a mano
desde el SQL Editor; el detalle funcional está en
`../../PLAN_MEJORAS_ADMIN_CLIENTE.md` §0.bis.

- **40** (`migraciones/40_activo_servicios_locales_turnos_horario.sql`): columnas
  `activo` en `app_dat_locales`, `app_dat_servicios` y `local_servicio`;
  `horario_detalle jsonb`; `solo_turnos`/`sin_tramos`; `turno.hora_inicio/hora_fin`;
  el predicado `flow._ls_disponible(id)` y el helper
  `flow._caller_es_admin_de_ls(id)`. **Incluye un cambio de seguridad**: elimina la
  política `"update ls"` de `flow.local_servicio`, que dejaba el UPDATE abierto a
  `public`/`anon`.
- **41** (`migraciones/41_rpc_admin_dashboard_modo_y_horas.sql`):
  `admin_dashboard_entidad`, `admin_config_modo_gestion`, `admin_guardar_turno_auto`
  y el `drop`+`create` de `admin_guardar_turno` (10 args) y `admin_listar_recursos`
  (con horas).
- **42** (`migraciones/42_cliente_filtro_activos_y_horas.sql`): `drop`+`create` de
  `cliente_obtener_servicios` con `p_incluir_inactivos boolean default false`, el
  filtro `_ls_disponible` en los RPC de cliente, `horario_detalle` en el payload y
  las horas del turno en `cliente_obtener_disponibilidad`, más el trigger
  `trg_agenda_ls_disponible` que bloquea reservar un par desactivado.

Igual que con la 39: **las lecturas del cliente toleran que las migraciones no estén
aplicadas.** `LocalServicio.activoEfectivo` asume publicado cuando la columna `activo`
no viene (nunca oculta de más) y el horario cae al parser de texto si no hay
`horario_detalle`.

**⚠️ Las escrituras del admin no toleran lo mismo.** `createServicio`,
`updateServicio`, `createLocal`, `updateLocal`, `updateLocalServicio(activo:)` y
`guardarTurno(horaInicio:)` mandan columnas que solo existen tras la 40: sin
migrar, PostgREST responde `column "activo" does not exist` y el admin no puede
guardar locales, servicios ni turnos. Aplica la 40 (y la 41, que crea las RPC
nuevas) **antes** de abrir el admin. La 42 es la que permite al admin listar y
reactivar lo desactivado.

## El "bot" en segundo plano

Cuando un admin **crea/edita** un `plan_servicios` (fecha + cantidad para un `id_local_servicio`), el bot mueve candidatos de `sala_espera` a `agenda` mientras `agendados < cantidad`, respetando `plan.fecha >= sala_espera.fecha_regla` y el orden FIFO de la cola.

- **Reactivo:** trigger `trg_plan_servicio_aiu` lo dispara al instante.
- **Programado (pg_cron):** procesa candidatos que entren después de crear el plan.

```sql
-- Activar el sweep periódico (requiere extensión pg_cron)
select cron.schedule('bot-sweep', '* * * * *', $$ select flow.bot_sweep(); $$);
```

## Antifraude

`flow.cliente_entrar_sala_espera` registra en `flow.sala_espera_fraude`:
- `duplicado` — mismo usuario intenta entrar dos veces a la misma cola.
- `local_servicio_inexistente` — id inválido.
- `flood` — más de 5 intentos por minuto del mismo usuario.

Ver detalle completo en **`BASE_CONOCIMIENTO.md`**.
