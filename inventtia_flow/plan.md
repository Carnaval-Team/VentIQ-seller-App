# Plan de evolución del Home cliente

Última verificación: contra la **base de datos remota** (`flow`) y el código de
`lib/`, no contra `docs/flow_schema/*.sql` — que está desactualizado en varios
puntos.

---

## 1. Qué dice realmente el backend (no los .sql del repo)

Los `docs/flow_schema/*.sql` son material de referencia y avisan que "no están
pensados para ejecutarse". El estado real de Supabase es este:

| Aspecto | Documentado en el repo | Realidad en la BD |
|---|---|---|
| RLS en `app_dat_servicios`, `app_dat_locales`, `local_servicio`, `entidad` | "sin RLS, lectura/escritura anónima" | **RLS activo** con `*_select_all` (lectura pública) y `*_admin`/`*_owner` para escritura |
| RLS en `perfil` | "sin RLS" | **RLS activo**, política `perfil_select_own` → no es legible por terceros |
| RLS desactivado | no se menciona | `nom_tipo_actividad_servicio`, `bot_log`, `sala_espera_fraude` (corregido en la 22) |
| `tipo_actividad` en el feed | — | El RPC solo expone `{id, codigo}`, **no** `nombre` |

Fuente única del feed: `flow.cliente_obtener_servicios(p_id_local, p_id_servicio,
p_id_entidad, p_nombre_local, p_nombre_servicio, p_pais, p_provincia) → jsonb`.

### Datos reales medidos

- `local_servicio`: **8 filas** (ids 7, 11–17) → 8 tarjetas posibles en el feed.
- `app_dat_servicios`: 11 · `app_dat_locales`: 9 · `entidad`: 8.
- `nom_tipo_actividad_servicio`: **14 filas** tras aplicar la migración 22.
- Precios reales mezclan **USD y CUP** (60 / 40 / 50 USD; 1500 / 300 / 2000 / 500
  CUP). 3 servicios tienen `config_precio = '{}'` → **sin precio**.
- `app_dat_locales.coordenadas` está **vacío en los 9 locales**.
- `auth.users` tiene **5261 usuarios** pero `flow.perfil` solo **19 filas**.
- `horario_atencion` es texto libre: `"8-4"`, `"8:00 a 17:00"`,
  `"Lun - Dom, 8:30 - 16:00"`, `"Lun-Sab 8:00am - 6:00pm"`, `"sd"`, `null`.

---

## 2. Auditoría sección por sección del Home

| Sección | Antes | Veredicto | Ahora (Paso 1) |
|---|---|---|---|
| Top bar, saludo, campana | `AuthProvider` + `flow.notificaciones` | **Real** | Sin cambios |
| Badge de reservas | `'2'` fijo en `home_shell.dart` | **Dato mal** | Cuenta real de `agenda` en estado `Reservado` |
| Ubicación | `'Santa Clara, Villa Clara'` fijo | **Dato mal** | Provincias reales de los locales del catálogo |
| Buscador + micrófono | Buscador real; micro solo toast | Real / pendiente | Buscador real; micro tras flag |
| Chips "Cerca de mí" / "Mejor valorados" | Heurística sobre texto inventado | **Imposible hoy** | Ocultos tras flag |
| Chip "Abierto ahora" | `!texto.contains('cerrado')` → todo abierto | **Dato mal** | Parser real de `horario_atencion` |
| Categorías (8 curadas) | Lista fija Belleza/Uñas/Salud… | **Dato mal** | `nom_tipo_actividad_servicio` real (14) |
| Colecciones | 4 tarjetas estáticas | **Mock** | Apagada (`HomeFeatures.colecciones`) |
| Patrocinados | 3 tarjetas estáticas | **Mock** | Apagada (`HomeFeatures.patrocinados`) |
| Ofertas relámpago | Descuentos + "3 cupos" + 2 locales inventados de respaldo | **Mock** | Apagada (`HomeFeatures.ofertasRelampago`) |
| Recomendado para ti | "Basado en tus preferencias" | Copy falso | Renombrada "Servicios disponibles" |
| Establecimientos populares | Rating 4.9 y "1.2 km" inventados | **Dato mal** | "Establecimientos" con provincia/horario reales |
| Ranking semanal | Orden arbitrario | **Mock** | Apagada (`HomeFeatures.rankingSemanal`) |
| Reseña del día | Texto, autor y 5 estrellas fijos | **Mock** | Apagada (`HomeFeatures.resenas`) |
| Beneficio de bienvenida | "20 % de descuento" | **Mock** | Apagada (`HomeFeatures.fidelidad`) |
| Cómo funciona | Genérico | Real | Sin cambios |
| Tarjetas del feed | Rating, reseñas, "45 min", distancia | **Mock** | Precio+moneda, categoría, provincia y horario reales |
| Corazón de favoritos | `Set<int>` con ids 9001/9005 (que no existen) | **Dato mal** | `flow.favorito` real (Paso 3) |
| Catálogo de respaldo | 12 servicios inventados (Luna Studio, Casa Aura…) | **Mock** | Eliminado: si falla la lectura, estado de error |
| Paginación infinita | Caché en memoria sobre una lectura | Real | Sin cambios |

---

## 3. Roadmap

### ✅ Paso 1 — Verdad de datos (hecho)

- `lib/utils/horario_atencion.dart` — parser de `horario_atencion` en 6 formatos
  reales; lo no interpretable queda **desconocido**, nunca "abierto".
- `lib/services/home_catalog_service.dart` — reescrito: solo campos que existen;
  sin `rating`, `reviews`, `distance`, `discount`, `durationMinutes`; sin
  catálogo de respaldo inventado; `paginar()` puro y testeable.
- `lib/config/home_features.dart` — una bandera por sección sin respaldo, con la
  tabla/RPC que falta anotada.
- `lib/screens/home_client_screen.dart` — cableado a datos reales; secciones sin
  backend apagadas; estado de error con reintento; selector de provincia real.
- `lib/providers/reservas_provider.dart` + `home_shell.dart` — badge real.

### ✅ Paso 2 — Taxonomía de categorías + gestión en admin (hecho)

- `migraciones/22_categorias_marketplace.sql` — 14 categorías, RLS del
  nomenclador, RLS de `bot_log`/`sala_espera_fraude` y los RPC admin.
- `migraciones/23_reasignar_categorias_servicios.sql` — los 6 servicios a sus
  categorías reales.
- `lib/services/tipo_actividad_service.dart` + `config_categorias_screen.dart` +
  módulo "Categorías" en el grid de gestión.
- Iconos y emoji por código de categoría; riel ordenado alfabéticamente con
  "General" al final (es el cajón de sastre).

### ✅ Paso 3 — Favoritos reales (hecho)

- `migraciones/25_favoritos.sql` — tabla `flow.favorito` con PK compuesta
  `(uuid_usuario, id_local_servicio)`, RLS por `auth.uid()` e índice por fecha.
  La FK va contra **`auth.users`**, no contra `flow.perfil`: con 5261 usuarios y
  19 perfiles, apuntar a `perfil` habría roto el guardado para 5242 personas.
- `lib/services/favorito_service.dart` — CRUD + join de PostgREST para traer los
  favoritos con su local y servicio en **una** consulta (sin N+1).
- `lib/providers/favoritos_provider.dart` — estado global, escrituras optimistas
  con reversión si fallan, y detección de migración pendiente.
- `lib/screens/favoritos_screen.dart` — pantalla con estado vacío y error.
- `_BotonFavorito` en las tarjetas del Home, que se **oculta solo** si la
  migración no está aplicada; entrada "Favoritos" en Perfil.

**Ampliación (corazón en las tres vistas + orden):**

- `lib/widgets/boton_favorito.dart` — corazón y aviso **compartidos**: la regla
  de auto-ocultarse (sin migración / sin sesión) vive en un solo sitio en vez de
  triplicada. `BotonFavorito` para pintar y `alternarFavorito()` para la acción.
- `catalogo_screen.dart` — corazón en cada tarjeta y **favoritos primero**: se
  particiona en dos listas porque `List.sort` de Dart **no es estable**, así que
  ordenar por el booleano desordenaría el catálogo. Chip "Favoritos (N)" para ver
  solo los guardados.
- `local_servicio_detail_screen.dart` — corazón en el `SliverAppBar`, con fondo
  translúcido sobre el header oscuro (`sobreClaro: false`).
- Tests: `test/catalogo_favoritos_test.dart` fija el contrato de la partición
  (estabilidad, sin pérdidas y con ids favoritos que ya no están en el catálogo).

### ✅ Paso 4 — Reseñas y rating (hecho)

**Decisión de producto acordada:** se reseña una **reserva completada** y la
reseña queda asociada al servicio (visible en el detalle y en el Home).

- `migraciones/26_resenas.sql` — tabla `flow.resena` + RLS + 5 RPC.
  El ancla es la reserva, no el servicio: `id_agenda UNIQUE` impide inflar el
  rating reseñando 10 veces el mismo turno, y el estado debe ser `Completado`
  (no basta con haber reservado). **73 reservas ya están completadas**, así que
  la sección tendrá datos reales desde el primer día.
- `lib/services/resena_service.dart` — modelo, resumen con distribución y CRUD.
- `lib/widgets/resenas.dart` — `Estrellas`, `SelectorEstrellas`,
  `ResumenValoraciones`, `TarjetaResena` y el formulario de escritura.
- **Detalle del servicio**: sección de reseñas con resumen, lista, y el
  formulario que aparece **solo** cuando existe una reserva completada propia sin
  reseñar (`agenda_resenable`). Así el botón nunca falla al pulsar. Se puede
  editar y eliminar la propia.
- **Home**: bloque "Lo que dicen los clientes" con reseñas reales — sustituye a
  la "Reseña del día" inventada (texto, autor y 5 estrellas fijos de un negocio
  que no existe). Estrellas reales en las tarjetas y chip "Mejor valorados"
  funcionando.
- `HomeFeatures.resenas` y `mejorValorados` encendidos.
- Tests: `test/home_valoraciones_test.dart` y ampliación de
  `favorito_service_test.dart` para la detección de migración pendiente.

**Detalle técnico que importa:** las funciones de lectura son `SECURITY DEFINER`
con guarda de rol, no `invoker`. Con `invoker`, RLS (`perfil_select_own` y las
políticas de `agenda`) haría que **todos los autores salieran "Cliente"** y que
nadie pudiera ver su propia reseña. Como saltan RLS, filtran por `auth.uid()`
explícito en SQL.

**Pendiente:**

1. **Aplicar `26_resenas.sql`** en ambos proyectos.
2. **Moderación en admin**: sin pantalla, una reseña ofensiva solo se puede
   borrar por SQL. El autor sí puede borrar la suya.
3. Decidir si se exige un mínimo de reservas para mostrar el promedio (hoy se
   muestra con 1 sola reseña, lo que puede ser ruidoso).

### 🟡 Paso 5 — Promociones (hecho; falta aplicar el SQL)

**Decisión acordada:** el "espacio patrocinado" **no** lo configura un admin de
entidad sino un super admin desde otra app. Por eso este paso se separó en dos:
**promociones** (aquí, con CRUD del admin) y **patrocinados** (después, solo
tablas + RPC de lectura).

#### El problema de precios que había que resolver primero

Antes de esta migración había **una** función que decidía cuánto se cobra
(`calcular_precio_reserva`) y **seis** que la llamaban:

| Función | Quién la dispara |
|---|---|
| `cliente_reservar_directo` | cliente |
| `cliente_reservar_pasaje_omnibus` | cliente |
| `admin_crear_reserva_directa` | admin (mostrador) |
| `admin_reservar_pasaje_omnibus` | admin |
| `bot_procesar_plan` | **BOT** (mueve de la cola a la agenda) |
| `bot_procesar_recurso_dia` | **BOT** |

A la vez, la **app** calculaba el precio por su cuenta en Dart
(`PrecioReserva.calcular`, usada en 5 sitios) para *mostrarlo*, y el servidor lo
recalculaba para *cobrarlo*. **Dos implementaciones de la misma regla**: con
promociones habrían descuadrado en cuanto una cambiara en un solo lado.

#### Cómo quedó

- **`_resolver_promocion`** es la única definición de "qué promo aplica y cuánto
  descuenta". De ahí salen **tanto lo que se muestra como lo que se cobra**.
- **El bot no toca promociones.** Si el descuento estuviera dentro de
  `calcular_precio_reserva`, el bot lo aplicaría al mover a alguien de la sala de
  espera —donde nadie eligió una oferta— y gastaría cupos que nadie pidió. Se
  añadió `_aplicar_promocion` como envoltorio que **solo** usan los 4 caminos en
  los que una persona confirma. Consecuencia asumida: una entrada de cola
  promovida por el bot nunca lleva descuento.
- **La app ya no calcula el precio: lo cotiza.** `cotizar_reserva` no consume
  cupo y alimenta la hoja de reserva; el total que se ve es el que se cobra.
- **El cupo se reserva al cobrar, no al cotizar**, con
  `update ... where cupo_usado < cupo_total`. Si la promo se agota entre que el
  cliente ve el precio y confirma, la reserva **se rechaza con un mensaje claro**
  en vez de cobrarle más en silencio.
- La promo puede ser del servicio o de **toda la entidad**; gana la propia del
  servicio y, a igualdad, el porcentaje más alto.

#### Archivos

- `migraciones/27_promociones.sql` — tabla + RLS + 9 funciones, y **reescribe los
  4 RPC personales** para que usen el envoltorio.
- `lib/services/promocion_service.dart` — modelo, `cotizar`, `porServicio`.
- `lib/screens/admin/promociones_screen.dart` — CRUD (alta, edición, activar,
  cupo, vigencia), alcanzable desde el detalle del servicio.
- `lib/screens/local_servicio_detail_screen.dart` — banner de promos y **total
  cotizado** con el precio de lista tachado y el descuento.
- `lib/screens/home_client_screen.dart` — precio rebajado en las tarjetas y
  sección "Ofertas vigentes" que solo lista lo que **realmente** tiene descuento.
- Eliminada la sección falsa: la antigua "Ofertas relámpago" mostraba cualquier
  servicio como oferta, con un contador fijo "4:12:39" y, si no había ofertas,
  dos negocios inventados ("Alma Spa", "Luna Studio").
- Tests: `test/promocion_service_test.dart`.

**Pendiente:**

1. **Aplicar `27_promociones.sql`.** Sin ella el Home se pinta sin badges y la
   hoja de reserva cae al cálculo anterior (sigue funcionando, sin descuentos).
2. Validar en la app: el importe de la hoja debe coincidir con el de
   `agenda.precio_total` tras reservar. Es la comprobación que cierra este paso.
3. Decidir si las promos de entidad se gestionan desde una pantalla propia
   (hoy el CRUD es por servicio; el alcance de entidad existe en la tabla y en
   la resolución, pero no hay UI para crearlas).

### Paso 6 — Colecciones y campañas patrocinadas

- `flow.coleccion` + `flow.coleccion_servicio` (orden) y `flow.campana`
  (ventana de vigencia, prioridad, presupuesto/impresiones).
- CRUD en admin; patrocinado debe ir **etiquetado** y fuera del orden orgánico.

### Paso 7 — Fidelidad y beneficio de bienvenida

- Reglas de acumulación, saldo, vencimiento y auditoría de movimientos.
- `flow.beneficio_bienvenida` aplicable una sola vez por usuario.

### Paso 8 — RPC único `cliente_home_feed`

Consolidar en un solo objeto JSON: `items` paginados con cursor, `has_more`,
`next_cursor`, `metadata` de categorías, contador de notificaciones y reservas,
promos vigentes, colecciones y patrocinados. Incluir `ta.nombre` para no hacer
la segunda lectura del nomenclador. Sustituir `HomeCatalogService._loadCatalog()`.

### Paso 9 — Recomendaciones y ranking semanal

- Señales de interacción (vistas, reservas, favoritos) + RPC de ranking por
  ventana semanal. Encender `HomeFeatures.rankingSemanal`.

### Paso 10 — Realtime solo para contadores

Contador de reservas y notificaciones en vivo; **nunca** por tarjeta del feed.

---

## 4. Migraciones (las pega el usuario)

El MCP de Supabase de esta sesión está en **modo solo lectura**, no hay CLI de
Supabase ni `psql`, y el shell no tiene salida HTTPS. Ninguna migración se aplica
desde el agente.

> ⚠️ **Hay dos proyectos Supabase.** `lib/config/supabase_config.dart` usa
> `qhprswhhfasrikhawjoz` (rama *debug*, `flutter run`) y
> `vsieeihstajlrdvpuooh` (rama *release*, `flutter build --release`). El
> diagnóstico de este plan se hizo contra el de **release**. Las migraciones van
> en **los dos** o el comportamiento diferirá.

| Archivo | Qué hace | Estado |
|---|---|---|
| `22_categorias_marketplace.sql` | 14 categorías + RLS + RPC admin | ✅ aplicada |
| `23_reasignar_categorias_servicios.sql` | 6 servicios a su categoría | ✅ aplicada |
| `24_fix_idor_rpc_admin.sql` | cierra el IDOR (§5) | ✅ aplicada |
| `25_favoritos.sql` | tabla `flow.favorito` + RLS | ✅ aplicada |
| `26_resenas.sql` | tabla `flow.resena` + 5 RPC + RLS | ✅ aplicada |
| `27_promociones.sql` | tabla `flow.promocion` + 9 RPC + RLS, y reescribe los 4 RPC de reserva personales | ⬜ **pendiente** |

Verificado tras aplicar las tres primeras: 14 categorías activas, 6 servicios
reasignados, RLS activo en las 4 tablas, los 6 RPC con `auth.uid()` y sin
`EXECUTE` para `anon`.

Nota sobre `sala_espera_fraude`: activar RLS ahí **sin** políticas habría roto la
entrada a la cola, porque la escriben `cliente_entrar_sala_espera_cola` y
`..._reserva`, que son `SECURITY INVOKER`. La 22 replica sus dos accesos exactos.

---

## 5. Seguridad: IDOR en los RPC de listado (corregido)

Encontrado al verificar el RPC del Paso 2. **No era del Home**: afectaba al panel
admin y era **anterior** a este trabajo.

La función es `SECURITY DEFINER` (salta RLS) pero autorizaba con el **parámetro**
que envía el cliente en vez de `auth.uid()`. `admin_listar_agendas` tenía además
`EXECUTE` para `anon`, así que se podía explotar **sin iniciar sesión** y devolvía
`perfil.ci`, teléfono, nombre y apellidos de clientes de cualquier entidad.

Corregido en `24_fix_idor_rpc_admin.sql`: las 4 funciones de agendas autorizan con
`auth.uid()`, `admin_listar_admins`/`admin_listar_vendedores` comprueban entidad, y
la familia `admin_*`/`vendedor_*`/`staff_*` deja de ser ejecutable por `anon`
(concediendo a `service_role` explícitamente, porque `bypassrls` no otorga
`EXECUTE`).

---

## 6. Convención de migraciones

Los cambios de escritura **no se aplican desde el agente**: van a un `.sql` en
`docs/flow_schema/migraciones/` y los pega el usuario en el SQL Editor. También
queda escrito en `docs/flow_schema/README.md`. Requisitos de cada archivo:

- **Idempotente** (re-ejecutarlo deja el mismo estado).
- **Reversible**, con el SQL de vuelta atrás en la cabecera.
- **Comprobación previa** que aborte con un mensaje claro si falta la migración
  de la que depende.
- **Consulta de verificación** al final.
- Recordar que hay **dos proyectos** (debug y release) y que se aplica en ambos.

---

## 7. Checks de producto pendientes

- **Decidir el naming**: "Mis Listas" en la barra inferior es la **sala de espera**
  (`flow.sala_espera`), no favoritos. Favoritos vive en Perfil para no meter una
  sexta pestaña en 390 px.
- Confirmar el nombre final de marca y el texto de ubicación predeterminado.
- Cerrar la lista de categorías definitiva (la sembrada es una propuesta).
- Reemplazar los degradados de vista previa por `foto` de Storage: hoy solo 1
  local y 1 servicio tienen foto.
- Validar en viewport móvil de 390 x 844 y en Android con texto grande.
- Añadir tests de interacción para búsqueda, categorías, favoritos, carga
  infinita y navegación al detalle.
- Tests del RPC paginado antes de habilitar datos comerciales.