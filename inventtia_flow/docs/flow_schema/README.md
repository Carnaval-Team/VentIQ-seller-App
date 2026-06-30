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
```

## Orden de instalación

Ejecutar en el **SQL Editor** de Supabase, en este orden:

1. **`migraciones/`** completo (01 → 02 → 03 → 04 → 08 → 09).
2. **`rpc clientes/00_indices_sala_espera.sql`** (índices de apoyo).
3. El resto de **`rpc clientes/`** (cualquier orden; el 08 depende del 07; el 10 y 11 dependen de las migraciones 08/09).
4. **`rpc admin/00_helper_entidades_usuario.sql`** primero, luego el resto de `rpc admin/` (07/08/09 dependen del helper y de la migración 09).

> El helper `admin_entidades_de_usuario` debe existir antes que las demás RPC admin, porque todas lo usan.

### Reserva directa + planificación recurrente (nuevo)

- **Migración 08** añade `flow.local_servicio.permite_reserva_directa` (bool, default false). Si está activo, el cliente puede **reservar directo** (sin cola) cuando hay un `plan_servicios` con cupo ese día.
- **Migración 09** crea `flow.plan_config` (config recurrente de capacidades por día de la semana, 1 fila por `local_servicio`) con su RLS.
- **`cliente_reservar_directo`** crea la agenda al instante (estado `Reservado`) y suma `agendados`, serializando con la cola/bot por el mismo advisory lock.
- **`admin_generar_plan_mensual`** crea/actualiza los `plan_servicios` de un mes a partir de `plan_config`; el trigger del bot reparte la cola pendiente automáticamente.

## Convenciones

- **Todo devuelve `jsonb`.** Las funciones de lista devuelven un array (`[]` si no hay datos). Las de acción (entrar/salir) devuelven `{ ok: bool, data | error }`. Así se puede cambiar la forma de la respuesta sin `DROP`/recrear.
- **`security invoker`** en las RPC de usuario → respetan RLS del que llama.
- **`security definer`** solo en el bot (`bot_procesar_plan`, `bot_sweep`, triggers) → necesita escribir en varias tablas; concedido únicamente a `service_role`.
- **Aislamiento por entidad (admin):** cada RPC admin hace `JOIN admin_entidades_de_usuario(uuid)`, así un admin solo ve datos de **sus** entidades aunque mande otro `id_entidad` por parámetro.
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
