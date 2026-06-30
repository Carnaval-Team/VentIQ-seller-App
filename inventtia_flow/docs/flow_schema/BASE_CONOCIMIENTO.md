# Base de conocimiento — RPC del esquema `flow`

Catálogo de todas las funciones: **qué parámetros llevan**, **qué responden** y **para qué sirven**.
Todas viven en el schema `flow` y devuelven `jsonb`. Llamar con `supabase.schema('flow').rpc(...)`.

Leyenda de tipos de respuesta:
- **Array** → `[]` cuando no hay datos (nunca `null`).
- **Acción** → `{ "ok": true, "data": {...} }` o `{ "ok": false, "error": "..." }`.

---

## 1. RPC Cliente (`rpc clientes/`)

Para la app del cliente final. `security invoker`, concedidas a `authenticated` (y `anon` las de catálogo público).

### `cliente_obtener_locales(p_id_entidad integer = null)`
- **Para qué:** listar locales disponibles para el cliente, con su entidad.
- **Parámetros:** `p_id_entidad` (opcional) → filtra por entidad.
- **Responde:** array de locales.
```json
[
  {
    "id": 1, "nombre": "Sucursal Centro", "descripcion": "...",
    "horario_atencion": "...", "terminos_condiciones": "...",
    "coordenadas": {...}, "direccion": "...", "pais": "...", "provincia": "...", "foto": "...",
    "created_at": "...", "updated_at": "...",
    "entidad": { "id": 2, "denominacion": "...", "direccion": "...", "telefono": "..." }
  }
]
```

### `cliente_obtener_servicios(p_id_local, p_id_servicio, p_id_entidad, p_nombre_local, p_nombre_servicio, p_pais, p_provincia)`
- **Para qué:** servicios ofrecidos en locales (relación `local_servicio`). Es lo que se muestra al elegir "dónde y qué servicio". Pensado para una barra de búsqueda.
- **Parámetros:** todos opcionales y combinables.
  - `p_id_local`, `p_id_servicio`, `p_id_entidad` (int) → filtro exacto por id.
  - `p_nombre_local`, `p_nombre_servicio`, `p_pais`, `p_provincia` (text) → búsqueda **parcial** insensible a mayúsculas (`ILIKE %texto%`).
- **Responde:** array con `id_local_servicio`, `permite_reserva_directa`, `servicio`, `local`, `entidad`.
```json
[
  {
    "id_local_servicio": 7, "created_at": "...", "permite_reserva_directa": true,
    "servicio": { "id": 3, "nombre": "...", "descripcion": "...", "foto": "..." },
    "local":    { "id": 1, "nombre": "...", "direccion": "...", ... },
    "entidad":  { "id": 2, "denominacion": "...", ... }
  }
]
```

### `cliente_listar_servicios(p_id_entidad integer = null)`
- **Para qué:** catálogo plano de servicios (`app_dat_servicios`), sin atarlos a un local. Útil para vistas de "qué servicios existen".
- **Parámetros:** `p_id_entidad` (opcional).
- **Responde:** array de servicios con `entidad` resumida.

### `cliente_obtener_salas_espera(p_uuid_usuario uuid)`
- **Para qué:** ver en qué colas está el usuario y su posición. Cruza con `ultimo_numero` para saber por dónde va la cola.
- **Parámetros:** `p_uuid_usuario` (obligatorio).
- **Responde:** array de colas del usuario.
```json
[
  {
    "id": 10, "fecha_regla": "...", "created_at": "...",
    "numero_cola": 4,            // número del usuario
    "ultimo_otorgado": 2,        // último número llamado en el servicio
    "personas_delante": 2,       // cuántos faltan para su turno
    "es_su_turno": false,
    "id_local_servicio": 7,
    "servicio": {...}, "local": {...}
  }
]
```
> Nota: si se usa el modelo de **cola compacta** (renumera 1..N al salir/agendar), `numero_cola = 1` es siempre el siguiente y `personas_delante` = `numero_cola - 1`.

### `cliente_obtener_agendas(p_uuid_usuario uuid, p_id_estado int = null)`
- **Para qué:** ver las reservas del usuario y su estado.
- **Parámetros:** `p_uuid_usuario` (obligatorio), `p_id_estado` (opcional).
- **Responde:** array de reservas con `estado`, `servicio`, `local`.

### `cliente_entrar_sala_espera(p_uuid_usuario uuid, p_id_local_servicio int, p_fecha_regla timestamp = null)` — **ACCIÓN**
- **Para qué:** unirse a la cola de un servicio. Asigna `numero_cola = max(actual) + 1`.
- **Obligatorios:** `p_uuid_usuario`, `p_id_local_servicio`. `p_fecha_regla` default = ahora.
- **Antifraude:** rechaza y registra en `sala_espera_fraude` si: duplicado, servicio inexistente, o flood (>5/min).
- **Responde (éxito):**
```json
{ "ok": true, "data": { "id": 10, "uuid_usuario": "...", "id_local_servicio": 7,
                          "fecha_regla": "...", "numero_cola": 4, "created_at": "..." } }
```
- **Responde (error):** `{ "ok": false, "error": "El usuario ya esta en esta cola" }`

### `cliente_salir_sala_espera(p_uuid_usuario uuid, p_id_local_servicio int)` — **ACCIÓN**
- **Para qué:** salir de la cola. Recompacta: los de atrás suben un puesto (cola sin huecos).
- **Obligatorios:** ambos.
- **Responde:**
```json
{ "ok": true, "data": { "id_local_servicio": 7, "numero_liberado": 4, "reordenados": 3 } }
```

### `cliente_obtener_disponibilidad(p_id_local_servicio int, p_desde date = hoy, p_hasta date = hoy+90)`
- **Para qué:** días con cupo libre para **reserva directa**. Pinta el calendario de "Reservar ahora" con la capacidad disponible de cada día. Agrupa por día local (`America/Havana`) y filtra `disponibles > 0`.
- **Responde:** array (`[]` si no hay días con cupo).
```json
[ { "fecha": "2026-07-03", "cantidad": 50, "agendados": 12, "disponibles": 38 } ]
```

### `cliente_reservar_directo(p_uuid_usuario uuid, p_id_local_servicio int, p_fecha date)` — **ACCIÓN**
- **Para qué:** reservar al instante **sin pasar por la cola**, cuando el servicio tiene `permite_reserva_directa = true` y hay un `plan_servicios` con cupo ese día. Crea la agenda en estado `Reservado`, suma `agendados` y emite notificación. `security definer`.
- **Concurrencia:** toma el mismo `pg_advisory_xact_lock(hashtext('flow.sala_espera'), id_ls)` que la cola y el bot → no sobre-reserva.
- **Idempotencia:** si el usuario ya tiene agenda `Reservado` ese día/servicio, no crea otra.
- **Responde (éxito):** `{ "ok": true, "data": { "id_agenda": 30, "fecha": "2026-07-03" } }`
- **Responde (error):** `{ "ok": false, "error": "No hay turnos disponibles" }` · `"Reserva directa no habilitada para este servicio"` · `"Ya tienes una reserva ese dia"`

---

## 2. Bot / segundo plano (`rpc clientes/07` y `08`)

`security definer`, concedidas solo a `service_role`. No las llama el cliente.

### `bot_procesar_plan(p_id_plan bigint)`
- **Para qué:** núcleo del bot. Para **un** plan, mueve hasta `cantidad - agendados` candidatos de `sala_espera` → `agenda`.
- **Reglas:** mismo `id_local_servicio`, `plan.fecha >= fecha_regla`, orden FIFO, todo set-based (un CTE). Suma `agendados` y recompacta la cola.
- **Responde:** `{ "ok": true, "id_plan": 5, "id_local_servicio": 7, "movidos": 3 }`

### `bot_sweep()`
- **Para qué:** recorre **todos** los planes con cupo y llama a `bot_procesar_plan`. Pensado para `pg_cron`.
- **Responde:** `{ "ok": true, "planes_revisados": 4, "agendas_creadas": 9 }`

### Trigger `trg_plan_servicio_aiu` (función `trg_plan_servicio_procesar`)
- **Para qué:** dispara `bot_procesar_plan` automáticamente al `INSERT/UPDATE` de `cantidad`, `fecha` o `id_local_servicio` en `plan_servicios`. Procesamiento reactivo e instantáneo.

---

## 3. RPC Admin (`rpc admin/`)

Para el panel de administración. `security invoker`, concedidas a `authenticated`.
**Todas** filtran por las entidades del usuario vía el helper (no hay fuga entre entidades).

### `admin_entidades_de_usuario(p_uuid_usuario uuid)` — **HELPER**
- **Para qué:** devuelve los `id_entidad` que el usuario administra: como **admin asignado** (`entidad_admin`) **o como owner** (`entidad.owner_uuid`). Lo usan todas las demás RPC admin como `JOIN` de seguridad.
- **Responde:** tabla `(id_entidad integer)` — no es jsonb, es de uso interno.

### `admin_listar_entidades(p_uuid_usuario uuid)`
- **Para qué:** entidades que administra, marcando si es dueño.
- **Responde:** array con `denominacion`, `direccion`, `telefono`, `es_owner` (bool).

### `admin_listar_locales(p_uuid_usuario uuid, p_id_entidad int = null)`
- **Para qué:** locales de sus entidades.
- **Responde:** array de locales con `entidad`.

### `admin_listar_servicios(p_uuid_usuario uuid, p_id_entidad int = null)`
- **Para qué:** catálogo de servicios de sus entidades.
- **Responde:** array de servicios con `entidad`.

### `admin_listar_locales_servicios(p_uuid_usuario uuid, p_id_entidad int = null, p_id_local int = null)`
- **Para qué:** asignaciones servicio↔local (`local_servicio`) de sus entidades.
- **Responde:** array con `id_local_servicio`, `servicio`, `local`, `entidad`.

### `admin_listar_agendas(p_uuid_usuario uuid, p_id_entidad, p_id_local, p_id_local_servicio, p_id_estado, p_desde, p_hasta)`
- **Para qué:** ver todas las reservas de sus entidades, con **todos los datos** del cliente.
- **Parámetros:** primero obligatorio; resto opcionales (entidad, local, local_servicio, estado, rango de fechas `fecha_hora_reserva`).
- **Responde:** array completo `agenda → estado / servicio / local / entidad / cliente(perfil completo)`.
```json
[
  {
    "id": 22, "fecha_hora_reserva": "...", "fecha_hora_atencion": null,
    "estado": { "id": 1, "nombre": "Agendado", ... },
    "id_local_servicio": 7,
    "servicio": {...}, "local": {...}, "entidad": {...},
    "cliente": {
      "id": 5, "uuid_usuario": "...", "nombre": "...", "apellidos": "...",
      "ci": "...", "telefono": "...", "created_at": "...", "updated_at": "..."
    }
  }
]
```

### `admin_listar_salas_espera(p_uuid_usuario uuid, p_id_entidad, p_id_local, p_id_local_servicio)`
- **Para qué:** ver las colas en vivo de sus servicios: quién espera, con qué número y sus datos de contacto.
- **Responde:** array con `numero_cola`, `servicio`, `local`, `entidad`, `cliente` (perfil resumido), ordenado por `numero_cola`.

### `admin_set_reserva_directa(p_uuid_usuario uuid, p_id_local_servicio int, p_permite bool)` — **ACCIÓN**
- **Para qué:** habilitar/deshabilitar la **reserva directa** de un `local_servicio` (flag `permite_reserva_directa`). Valida pertenencia con el helper (no fuga entre entidades).
- **Responde:** `{ "ok": true, "data": { "id_local_servicio": 7, "permite_reserva_directa": true } }` o `{ "ok": false, "error": "local_servicio inexistente o sin permiso" }`.

### `admin_guardar_config_plan(p_uuid_usuario uuid, p_id_local_servicio int, p_config jsonb, p_activo bool = true)` — **ACCIÓN**
- **Para qué:** guardar (upsert) la **config recurrente** de capacidades por día de la semana (`flow.plan_config`). Una fila por `local_servicio`.
- **Formato de `p_config`:** `{ "default": 30, "por_dia": { "1": 50, "4": 60 } }` — día ISO 1=lunes…7=domingo. Día sin entrada → usa `default`; capacidad `0` → ese día no se planifica.
- **Responde:** `{ "ok": true, "data": { ...config persistida... } }`.

### `admin_obtener_config_plan(p_uuid_usuario uuid, p_id_local_servicio int)`
- **Para qué:** leer la config recurrente guardada de un `local_servicio` (o `null` si no hay / sin permiso).
- **Responde:** objeto `{ id, id_local_servicio, config, activo, updated_at }` o `null`.

### `admin_generar_plan_mensual(p_uuid_usuario uuid, p_id_local_servicio int, p_anio int, p_mes int)` — **ACCIÓN**
- **Para qué:** generar los `plan_servicios` de **un mes** a partir de `plan_config`. Por cada día: capacidad = `por_dia[isodow]` o `default`; capacidad `0` se omite (día cerrado). Si no existe plan ese día → `insert`; si existe → `update cantidad = greatest(nueva, agendados)` (respeta el mínimo ya reservado). El trigger `trg_plan_servicio_aiu` reparte la cola pendiente automáticamente.
- **Responde:** `{ "ok": true, "creados": 22, "actualizados": 4, "omitidos": 0, "dias_sin_cupo": 4 }`.

---

## 4. Tablas de apoyo creadas por las migraciones

| Tabla / columna | Para qué |
|---|---|
| `plan_servicios.agendados` (col) | Contador de agendas creadas por el bot para ese plan. Bot trabaja mientras `agendados < cantidad`. |
| `sala_espera_fraude` (tabla) | Registro de intentos sospechosos: `motivo` (`duplicado`/`flood`/`local_servicio_inexistente`) + `detalle` jsonb. |
| Estado `'Agendado'` en `nom_estado_agenda` | Estado con el que el bot crea las agendas. |
| `local_servicio.permite_reserva_directa` (col) | Si `true`, el cliente puede reservar directo (sin cola) cuando hay plan con cupo. Migración 08. |
| `plan_config` (tabla) | Config recurrente de capacidades por día de la semana (1 fila por `local_servicio`) para generar `plan_servicios` en lote. Migración 09. |

## 5. Índices creados

| Índice | Acelera |
|---|---|
| `idx_sala_espera_ls_numero (id_local_servicio, numero_cola)` | `MAX(numero_cola)` al entrar y recompactar al salir |
| `idx_sala_espera_ls_usuario (id_local_servicio, uuid_usuario)` | Verificar duplicado en cola |
| `idx_plan_servicios_con_cupo (fecha) WHERE agendados < cantidad` | Sweep del bot solo lee planes con cupo |
| `idx_fraude_usuario`, `idx_fraude_created` | Consultas de auditoría de fraude |
| `idx_locales_entidad`, `idx_servicios_entidad` | Filtros por entidad en cliente y admin |
| `idx_entidad_admin_usuario`, `idx_entidad_owner` | Helper `admin_entidades_de_usuario` |

---

## Resumen rápido (cheat sheet)

| Función | Rol | Devuelve | Sirve para |
|---|---|---|---|
| `cliente_obtener_locales` | cliente | array | listar locales (+entidad, filtro entidad) |
| `cliente_obtener_servicios` | cliente | array | servicios en locales (filtros local/servicio/entidad) |
| `cliente_listar_servicios` | cliente | array | catálogo de servicios |
| `cliente_obtener_salas_espera` | cliente | array | mis colas y mi posición |
| `cliente_obtener_agendas` | cliente | array | mis reservas |
| `cliente_entrar_sala_espera` | cliente | acción | unirme a una cola |
| `cliente_salir_sala_espera` | cliente | acción | salir de una cola |
| `cliente_obtener_disponibilidad` | cliente | array | días con cupo para reserva directa |
| `cliente_reservar_directo` | cliente | acción | reservar al instante (sin cola) |
| `bot_procesar_plan` | service | objeto | mover cola→agenda de un plan |
| `bot_sweep` | service | objeto | procesar todos los planes (cron) |
| `admin_entidades_de_usuario` | admin | tabla | helper de seguridad |
| `admin_listar_entidades` | admin | array | mis entidades |
| `admin_listar_locales` | admin | array | locales de mis entidades |
| `admin_listar_servicios` | admin | array | servicios de mis entidades |
| `admin_listar_locales_servicios` | admin | array | asignaciones local-servicio |
| `admin_listar_agendas` | admin | array | reservas + perfil del cliente |
| `admin_listar_salas_espera` | admin | array | colas en vivo + cliente |
| `admin_set_reserva_directa` | admin | acción | habilitar/deshabilitar reserva directa |
| `admin_guardar_config_plan` | admin | acción | guardar config recurrente por día |
| `admin_obtener_config_plan` | admin | objeto | leer config recurrente guardada |
| `admin_generar_plan_mensual` | admin | acción | generar plan_servicios de un mes |
