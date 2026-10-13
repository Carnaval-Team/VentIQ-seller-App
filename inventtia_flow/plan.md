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
| Patrocinados | 3 tarjetas estáticas + sello "Verificado" | **Mock** | `flow.campana` real, curada desde `ventiq_superadmin` (Paso 6) |
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
entidad. Se configura en la app **`ventiq_superadmin`** de este monorepo (ver
Paso 6). Por eso este paso se separó en dos: **promociones** (aquí, con CRUD del
admin de la entidad, porque el descuento lo paga el negocio) y **patrocinados**
(destacado de plataforma, curado por el superadmin).

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

- `migraciones/27_promociones.sql` — tabla + RLS + 9 funciones, y **reescribe 2
  RPC personales** (`cliente_reservar_directo` y `admin_crear_reserva_directa`)
  para que usen el envoltorio. No toca los de `pasaje_omnibus`.
- `migraciones/29_bot_promociones.sql` — los **bots de cola** aplican la promo
  vigente al confirmar, y el bot de turnos cotiza con `calcular_precio_turno`.
  Generada desde las definiciones **vivas** de la base (ver Paso 5.c), no desde
  los archivos del repo.
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

**Estado:** `27_promociones.sql` **aplicada y verificada** en la base — tabla con
RLS, su política de SELECT, 9 funciones y `anon` sin `EXECUTE` en ninguna.

**Pendiente:**

1. **Aplicar `29_bot_promociones.sql`** (ver Paso 5.b).
2. Validar en la app: el importe de la hoja debe coincidir con el de
   `agenda.precio_total` tras reservar. Es la comprobación que cierra este paso.
3. Decidir si las promos de entidad se gestionan desde una pantalla propia
   (hoy el CRUD es por servicio; el alcance de entidad existe en la tabla y en
   la resolución, pero no hay UI para crearlas).

#### Paso 5.b — Los bots de cola y el precio mostrado

`flow.sala_espera` **no tiene ninguna columna de precio**: el importe se fija al
crear la fila de `flow.agenda`, y quien la crea es el bot. Los bots lo hacían con
`calcular_precio_reserva` a secas, así que quien veía "-20 %" en el detalle
acababa pagando precio de lista. Con **4 de los 7 servicios** en
`permite_reserva_directa = false`, afectaba a la mayoría de las reservas.

`29_bot_promociones.sql` hace que los dos bots (`bot_procesar_plan` y
`bot_procesar_recurso_dia`) pasen por `_aplicar_promocion(..., true)`: aplican la
promo **vigente al confirmar** y **consumen cupo**. Si el cupo se agotó, caen al
precio de lista (nunca dejan `precio_total` en NULL ni cobran 0).

Decisiones y límites, explícitos:

- Se eligió "promo vigente al confirmar" sobre "no anunciarla en servicios de
  cola" y sobre "guardar el descuento al anotarse". **Consecuencia asumida:** si
  la promo vence mientras el cliente espera en la cola, el importe cobrado puede
  diferir del que se le mostró al anotarse.
- Un servicio con `config_precio = '{}'` devuelve precio NULL (la app muestra
  "Consultar"). Se conserva NULL: `_aplicar_promocion` lo devolvería como 0 y
  convertiría "Consultar" en "gratis".
- Dentro de una misma sentencia las CTE comparten snapshot: si hay dos promos
  solapadas y la mejor se agota a mitad del reparto, las filas siguientes caen a
  precio de lista en vez de pasar a la segunda. Erra siempre hacia cobrar de más,
  nunca de menos.

**Descuadre de precios que ya existía** (independiente de las promos): el bot de
turnos cotizaba con `calcular_precio_reserva`, el genérico del servicio, mientras
`cotizar_reserva` y `cliente_reservar_directo` usan `calcular_precio_turno` cuando
hay turno. Medido en la base de release:

| turno | local_servicio | bot cobraba | la app mostraba |
|---|---|---|---|
| 4, 5, 6 | 7 | 60 | 60 |
| 17 | 11 | **40** | **70** |
| 18 | 11 | **40** | **60** |
| 19 | 11 | **40** | **20** |
| 20, 21 | 12 | **50** | **35** |

Se alineó el bot con lo que la app muestra. Se habían creado **123 agendas** por
ese camino.

#### ⚠️ Paso 5.c — Los archivos del repo NO son la fuente de verdad

Al preparar la migración 29 se descubrió que
`docs/flow_schema/rpc admin/28_recursos_cola_bot.sql` **está desactualizado** y no
refleja lo que hay en producción. La `bot_procesar_recurso_dia` viva tiene una
lógica de candidatos que **no existe en el archivo**: además de los candidatos
con `se.id_turno = p_id_turno`, reclama los que tienen `id_turno is null` cuando
ningún turno **anterior** (por `turno.orden`) puede atenderlos, verificando cupo
por tramo y con un `having count(pt0.id) = (...)` sobre los tramos del turno.

Aplicar la versión del archivo habría **borrado esa lógica**. Por eso la 29 se
generó extrayendo las definiciones de la base con `pg_get_functiondef()` y
sustituyendo solo el bloque de precios, y cada bloque se verificó **por md5**
contra el texto que calculó la propia base.

`bot_procesar_plan` sí coincidía funcionalmente con el archivo (solo cambiaban el
delimitador `$function$` y los saltos CRLF).

**Regla a partir de aquí:** antes de escribir una migración que haga
`create or replace` de una función, extraer la definición viva y partir de ella.
Los archivos de `docs/flow_schema/rpc*/` no son fiables.

Dos trampas al embeber la salida de `pg_get_functiondef()`:

1. **No lleva `;` final.** Embeberla tal cual deja el `CREATE` sin cerrar, y el
   `CREATE` siguiente revienta con `42601: syntax error at or near "CREATE"`.
   Hay que añadirlo a mano.
2. Al verificar por md5 **no** se puede buscar el delimitador a ciegas: el primero
   que aparece es el de **apertura** (`AS $function$`), no el de cierre. Hay que
   localizar el cierre a partir de él o la comparación da un falso OK con solo la
   cabecera.

Y **validar siempre el script como SQL**: trocearlo en sentencias respetando
comentarios, strings y dollar-quotes, y comprobar que no queda texto suelto sin
terminar. Comparar cuerpos por md5 no demuestra que el script parsee.

##### Auditoría de drift (repo vs base, 98 funciones de `flow`)

Se compararon por md5 los cuerpos de las **98 funciones vivas** contra las 108
definiciones de `docs/flow_schema/**/*.sql` (normalizando CRLF→LF y recortando
espacios). Resultado: **82 coinciden, 8 con drift y 8 que no están en el repo**.

**Drift — la base tiene algo que ningún archivo refleja:**

| función | archivos del repo que la definen |
|---|---|
| `admin_listar_locales` | `rpc admin/01_admin_listar_locales.sql` |
| `admin_listar_locales_servicios` | `rpc admin/03_admin_listar_locales_servicios.sql` |
| `admin_listar_salas_espera` | `rpc admin/06_admin_listar_salas_espera.sql` |
| `admin_listar_agendas` | `rpc admin/04_...`, `rpc admin/29_...` |
| `admin_listar_agendas_por_estado` | `rpc admin/33_listar_agendas_por_estado.sql` |
| `vendedor_listar_agendas` | `rpc admin/12_...`, `rpc admin/29_...` |
| `vendedor_listar_agendas_por_estado` | `rpc admin/33_listar_agendas_por_estado.sql` |
| `bot_procesar_recurso_dia` | `rpc admin/28_...`, `migraciones/29_...` |

El patrón es claro: **todas las RPC de listado** están desincronizadas. Se
cambiaron en la base (probablemente al ampliar el panel de administración) sin
actualizar el repo. Escribir una migración nueva desde esos archivos las
revertiría.

`bot_procesar_recurso_dia` sale aquí por diseño: la base todavía tiene la versión
sin parchear y el repo ya tiene la 29. Desaparecerá de la lista al aplicar la 29.

**En el repo pero NO en la base:**

| nombre | archivos |
|---|---|
| `cliente_entrar_sala_espera` | `rpc admin/28_recursos_cola_bot.sql`, `rpc clientes/05_entrar_sala_espera.sql` |

En la base esa función **ya no existe**: está partida en
`cliente_entrar_sala_espera_cola` y `cliente_entrar_sala_espera_reserva`. La app
Flutter ya llama a la nueva (`lib/services/lista_service.dart:22`, con el
comentario `// Updated function name`). El código y la base van por delante; los
`.sql` del repo se quedaron atrás.

Comprobado además que **ninguna de las dos variantes toca `precio`** (no
mencionan `calcular_precio` ni `_aplicar_promocion`), lo que confirma el
diagnóstico del Paso 5.b: al anotarse en la cola **no se guarda ningún importe**,
el precio se fija al confirmar el bot.

**Solo en la base (sin definición en el repo):** `admin_create_user`,
`cliente_actualizar_fecha_regla`, `cliente_entrar_sala_espera_cola`,
`cliente_entrar_sala_espera_reserva`, `es_admin_o_dueño_de_entidad_de_agenda`,
`get_uuid_by_email`, `is_entidad_admin`, `update_updated_at_column`. Varias las
usa la app (p. ej. `cliente_actualizar_fecha_regla` en
`lib/services/lista_service.dart:174`).

**Cómo repetir la auditoría.** Exportar de la base el md5 del cuerpo normalizado
de cada función:

```sql
select p.proname,
       substr(md5(regexp_replace(replace(p.prosrc, E'\r\n', E'\n'),
                                 '^\s+|\s+$', '', 'g')), 1, 8) as h
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow'
order by p.proname;
```

Y del lado del repo: extraer de cada `.sql` el cuerpo entre `as $tag$` y `$tag$`,
aplicar la misma normalización y comparar. Una función viva es fiable solo si su
md5 aparece en **algún** archivo.

#### Pendiente de decisión — candidatos que esperan turno

`bot_procesar_plan` **no filtra por `id_turno`**, así que puede capturar a quien
está esperando un turno y crearle una agenda **sin `id_turno`**, al precio
genérico del servicio y sin descontar `plan_tramo`. `bot_sweep` recorre los
planes legacy **antes** que los turnos, así que gana el legacy.

Hay **3 servicios con los dos caminos abiertos a la vez**:

| servicio | planes legacy con cupo | turnos activos |
|---|---|---|
| 7 | 2 | 3 |
| 19 | 21 | 3 |
| 21 | 3 | 1 |

No se incluyó en la 29 a propósito: la precedencia correcta entre el camino
legacy y el de turnos es una decisión de producto, y la lógica viva del bot de
turnos (que reclama **también** los `id_turno is null`) sugiere que el camino de
turnos debería tener prioridad. La corrección mínima sería añadir
`and se.id_turno is null` al filtro de candidatos de `bot_procesar_plan`, pero
eso solo evita robar a los que **ya eligieron** turno: los no asignados seguirían
en disputa. Va en migración aparte si se decide.

### ✅ Paso 6 — Patrocinados (hecho)

**Corrección de alcance acordada con el usuario:** el espacio patrocinado **no** lo
configura el admin de la entidad ni vive en `inventtia_flow`. Se configura en la
app **`ventiq_superadmin`** de este mismo monorepo (apunta a los mismos dos
proyectos Supabase). Es contenido de **plataforma**, no de un negocio concreto.

**Separación de conceptos, que es lo que evita el bug de precios:**

| | `flow.promocion` (Paso 5) | `flow.campana` (Paso 6) |
|---|---|---|
| Qué es | Descuento | Destacado |
| Afecta al precio | **Sí** | **Nunca** |
| Quién la crea | Admin de la entidad | Superadmin |
| Dónde | `inventtia_flow` (admin) | `ventiq_superadmin` |

Se mantienen en tablas distintas a propósito: si el patrocinio pudiera alterar el
importe, se volvería a mezclar "lo que se muestra" con "lo que se cobra".

#### Backend — `28_patrocinados.sql` (aplicada)

- Tabla `flow.campana` (titulo, subtitulo, colores, icono, imagen, vigencia,
  prioridad, `id_local_servicio` **o** `id_entidad`) con 4 CHECK.
- RLS: SELECT para `authenticated`; INSERT/UPDATE/DELETE **solo** por
  `public.fn_is_superadmin_full_access()` — el helper que ya usaba
  `app_dat_superadmin`, que exige `nivel_acceso = 1` y resuelve por `auth.uid()`.
- 5 RPC `security invoker` (no definer: la autorización vive en RLS, un solo
  sitio). Verificado en la BD: ACL sin `anon`, con `authenticated`; `prosecdef =
  false` en las 5.
- `flow.campanas_activas()` devuelve las vigentes ya resueltas con nombres de
  local/servicio/entidad, ordenadas por prioridad. `hasta` es **exclusivo**.

#### App superadmin — `ventiq_superadmin`

- `services/campana_service.dart`, `models/campana.dart` y
  `screens/patrocinados_screen.dart` (lista, alta/edición, activar, eliminar).
- Ruta `/patrocinados` + entrada en el menú, grupo **Marketing** (junto a
  "Banners inicio", que ya era el precedente de "el superadmin cura lo que ve el
  cliente").
- No hay escritura directa a la tabla desde el cliente: todo pasa por los RPC.

#### Home del cliente — `inventtia_flow`

- `services/campana_service.dart` (solo lectura). Si la migración no está
  aplicada o no hay campañas, devuelve `[]`.
- `HomeFeatures.patrocinados = true`. **Se auto-detecta**: sin campañas vigentes
  la sección no se pinta. Antes mostraba 3 tarjetas inventadas ("Luna Studio",
  "Casa Aura", "Moverte") con un sello "Verificado" que no respaldaba nada.
- El toque abre el servicio: se busca en la página cargada y, si no está, en el
  catálogo completo ya cacheado (`HomeCatalogService.itemPorId`), porque una
  campaña puede destacar un servicio de otra página.
- El sello "Verificado" se sustituyó por el **local real** de la campaña.

#### Pendiente de este paso

- Las campañas de **entidad** (`id_entidad`, sin servicio) se resuelven en el
  backend y se pintan, pero el formulario del superadmin solo ofrece servicios.
  Falta un selector de entidades para crearlas desde la UI.
- No hay presupuesto/impresiones/facturación: solo prioridad y vigencia.

### ✅ Paso 7 — Colecciones temáticas (hecho; falta aplicar el SQL)

- **Backend — `30_colecciones.sql`.** `flow.coleccion` + `flow.coleccion_servicio`
  (PK compuesta `id_coleccion, id_local_servicio`, FK en cascada a
  `flow.local_servicio(id)` como el resto del esquema, y `orden` de posición).
  5 RPC con el patrón **idéntico al de patrocinados**: `security invoker`,
  `auth.uid() is distinct from p_uuid_usuario` → `Sesion no valida`, y
  `public.fn_is_superadmin_full_access()`.
  - `colecciones_activas()` → cliente, array JSON.
  - `admin_listar_colecciones` / `admin_guardar_coleccion` /
    `admin_alternar_coleccion` / `admin_eliminar_coleccion` → superadmin.
- **RLS:** el cliente solo ve colecciones **activas**; las apagadas las ve
  únicamente el superadmin (dos políticas permisivas que se suman). El cliente no
  lee las tablas directamente: usa el RPC.
- **App superadmin:** pantalla `/colecciones` en el grupo *Marketing*, junto a
  *Espacio patrocinado*. Formulario con título, subtítulo, icono, colores (con 6
  paletas sugeridas para no teclear hexadecimales), orden, vigencia, activo y
  selector de servicios con búsqueda.
- **Home del cliente:** `HomeFeatures.colecciones = true`. Las 4 tarjetas
  inventadas ("Pack Novia" con "12 servicios", "Self-care Sunday"…) desaparecen:
  si el superadmin no ha curado ninguna, **la sección no se pinta**.
- **Cómo filtra:** tocar una tarjeta filtra el feed por sus servicios y el
  encabezado pasa a ser el título de la colección con un chip
  "Colección · X" y "Quitar filtro". El filtrado es **en memoria** sobre el
  catálogo ya cacheado (`HomeCatalogService.paginar` acepta `idsPermitidos`),
  exactamente igual que las categorías: el catálogo entero se carga una vez y se
  pagina en el cliente, así que no hace falta una petición por colección.

#### Bugs corregidos de camino

- **`/patrocinados` era inalcanzable.** El `AppDrawer` solo navega si la ruta está
  en una lista blanca; `/patrocinados` no estaba, así que el Paso 6 mostraba el
  diálogo de "próximamente" y la pantalla de patrocinados no se podía abrir desde
  el menú. Añadidas `/patrocinados` y `/colecciones`.
- **Mojibake en `ventiq_superadmin/lib/models/campana.dart`.** El archivo tenía
  `CampaÃ±a`, `promociÃ³n`, `rotaciÃ³n`, ` Â· ` (UTF-8 leído como CP1252).
  Reescrito en UTF-8. Era el único archivo afectado.

#### Pendiente de este paso

- ~~El orden manual dentro de la colección se guarda (`coleccion_servicio.orden`)
  pero **hoy no se refleja**: el Home filtra preservando el orden del catálogo.~~
  → **Resuelto en el Paso 9**: `cliente_home_feed` ordena por `cs.orden` cuando
  hay colección seleccionada.

### ✅ Paso 8 — Fidelidad y beneficio de bienvenida (completo)

Decisiones de producto confirmadas por el usuario:

- El beneficio de bienvenida **descuenta de verdad** en la primera reserva,
  integrado en el mismo camino de precio que las promociones (mostrado ==
  cobrado, la lección del Paso 5).
- Los puntos **se acumulan y se muestran**; el canje por descuento se decide en un
  paso posterior. Dos cambios de precio a la vez en el mismo camino crítico son
  mucho más difíciles de verificar.
- Regla por defecto: **1 punto por cada 10 de moneda gastada**, caducan a los 12
  meses. Configurable.

#### Hecho — migraciones 31 y 32

- **`31_fidelidad.sql` (núcleo).** 4 tablas: `regla_fidelidad` (global o por
  entidad), `puntos_movimiento` (**libro append-only**), `beneficio_bienvenida` y
  `beneficio_canje`.
  - **El saldo no es una columna**: es la suma del libro (`fn_saldo_puntos`), así
    que la auditoría y el saldo no pueden desincronizarse. Sin cron de
    vencimiento: el saldo ya excluye los caducados, se haya asentado o no el
    asiento, y una acumulación ya asentada se cuenta junto a su movimiento
    negativo (no hay doble descuento).
  - **"Una sola vez por usuario" lo impone la base**, no el código:
    `unique (uuid_usuario)` en `beneficio_canje`.
  - `beneficio_canje.id_beneficio` es `on delete restrict`, **no cascade**: con
    cascade, borrar un beneficio habría borrado los canjes y los usuarios habrían
    vuelto a ser elegibles, rompiendo la regla sola. Un beneficio ya canjeado no
    se borra, se desactiva.
  - `cliente_mi_fidelidad()` en **una sola llamada**: saldo, regla, beneficio
    pendiente y últimos 50 movimientos.
- **`32_admin_fidelidad.sql`.** 8 RPC con el patrón de la casa (invoker +
  `auth.uid()` + `fn_is_superadmin_full_access()`): listar/guardar/eliminar reglas
  y beneficios, auditar movimientos de un usuario y ajustar puntos con motivo
  obligatorio (no permite dejar el saldo negativo).

#### Decisión de diseño que evitó el riesgo grande

Los puntos se acreditan con un **trigger en `flow.agenda` sobre `id_estado`**, no
redefiniendo `staff_marcar_estado_agenda`. Motivo: los archivos del repo pueden
estar desviados de la base (lección de la 29) y esa función viva es larga;
redefinirla para añadir un `perform` obliga a reproducirla entera y arriesga
pisar cambios que solo existen en la base. El trigger consigue lo mismo, funciona
venga la transición de donde venga, y **no reescribe ninguna función existente**.

Ventaja adicional: el trigger corre en la misma transacción que la reserva, así
que si la reserva hace rollback los puntos también. Y `_acreditar_puntos_agenda`
**nunca lanza excepción** (devuelve `{ok:false}`): un fallo de puntos no puede
bloquear la operación principal del negocio.

Idempotencia: el ciclo es terminal (solo `Reservado→Completado`,
`Reservado→Cancelado` y `Cancelado→Completado`), y además un índice único parcial
garantiza que una agenda acredita puntos **como máximo una vez**.

#### Hecho — app del cliente

- `fidelidad_service.dart` + `HomeFeatures.fidelidad = true`.
- El banner **ya no miente**: muestra el saldo real y la regla real
  ("Ganas 1 punto por cada 10 USD"), con "Mis movimientos" abriendo el libro
  (`_mostrarMovimientos`). Si la migración no está aplicada, el RPC falla, el
  servicio devuelve `null` y **la sección no se pinta**.
- El texto "20 % de descuento / Actívalo en tu primera reserva" y el botón
  "Activar beneficio" (que solo lanzaba un toast) están fuera.

#### Requisito añadido por el usuario: interruptor global — `33_config_fidelidad.sql`

El superadmin decide si el programa de fidelidad **existe** para los clientes.

- `flow.fidelidad_config` es una **fila única** (`check (id = 1)` + PK): es
  imposible que existan dos configuraciones que se contradigan, y no hay que
  elegir "la última".
- Se distingue de `regla_fidelidad.activo`, que dice "ESTA regla no aplica".
  Hacían falta las dos: sin el interruptor no se puede diferenciar "no hay reglas
  configuradas" de "el programa está apagado a propósito".
- `activa = false` → el trigger no acredita puntos, `cliente_mi_fidelidad`
  devuelve `activa: false` y el Home no pinta la sección.
- **Apagar es pausar, no borrar.** El libro es append-only y se conserva entero;
  al reactivar se sigue acumulando y cada cliente recupera su saldo. Nadie pierde
  puntos por un interruptor, y el panel puede seguir auditando el historial con el
  programa apagado.
- En el cliente, `hayAlgoQueMostrar` exige `activa` **primero**: sin eso, un
  usuario con saldo vería la sección de un programa apagado.
- Al redefinir `_acreditar_puntos_agenda` en la 33, su ACL se **recrea** con el
  grant por defecto a `authenticated`, así que la 33 vuelve a cerrarlo. Es
  exactamente la trampa que provocó el fallo de la 32.

#### Hecho — `34_beneficio_bienvenida_precio.sql` (el descuento real)

- Orden: `total = greatest(lista − promo − bienvenida, 0)`, con el beneficio
  sobre el **resto** para que los dos descuentos no se solapen.
- `_beneficio_bienvenida_aplicable` es de **solo lectura**, así que
  `cotizar_reserva` la usa sin gastar nada. El consumo ocurre solo al reservar.
- **Reclamo atómico**: el canje se inserta con `on conflict (uuid_usuario) do
  nothing` + `row_count` **antes** de descontar. Si dos reservas compiten, solo la
  primera gana el descuento y la segunda cobra sin él, sin fallar. Se prefiere
  cobrar de más que bloquear una reserva por un regalo. Mismo patrón que el cupo
  de las promociones.
- El titular del beneficio es **quien paga** (`p_uuid_usuario`), no el tercero a
  cuyo nombre se reserva: el regalo es de quien gasta.
- **No** se aplica en `admin_crear_reserva_directa` (ahí `auth.uid()` es el admin:
  gastaría su propio beneficio por una venta de mostrador) ni en el camino del bot
  (nadie eligió una oferta, y no debe gastar el único regalo del cliente sin que
  este lo sepa).
- `cotizar_reserva` es **STABLE** en la base; se recreó conservando el modificador
  y el `search_path`. Omitir el `stable` la habría vuelto volátil.
- El cuerpo de `cliente_reservar_directo` se copió del **vivo** y se comprobó que
  las 20 sentencias distintivas del original siguen presentes.
- El descuento añade 3 campos informativos al JSON (`descuento_beneficio`,
  `id_beneficio`, `beneficio_titulo`); los existentes no cambian de significado,
  así que la app vieja no se rompe.
- El beneficio hereda el IDOR conocido de `cliente_reservar_directo`
  (`p_uuid_usuario` sin verificar). No es un agujero nuevo, pero es una razón más
  para aplicar el arreglo de una línea de §5.c.

`HomeFeatures.beneficioBienvenida` está en `true`: la 34 está aplicada, así que el
descuento que el Home anuncia es el mismo que se cobra. Esa era la regla que rompió
el Paso 5, y por eso la bandera esperó a que la migración estuviera en la base.

Y el cliente quedó cableado:

- `CotizacionReserva` aprende `descuentoBeneficio`, `idBeneficio` y
  `beneficioTitulo`, y expone `descuentoTotal` = promoción + bienvenida.
- **Su `tieneDescuento` pasó a mirar el total.** Antes solo miraba la promoción: con
  solo el beneficio (sin promo) `descuento` es 0, así que el precio tachado **no se
  habría pintado** aunque el total fuera menor. Ese era el bug que iba a introducir.
- La etiqueta del detalle usa el descuento **total** y nombra las dos fuentes
  ("Bienvenida + Verano · -12"), porque mostrar solo el de la promoción diría menos
  de lo que se rebaja.
- Compatibilidad: si el servidor no manda los campos nuevos, el comportamiento es
  idéntico al de antes de la 34 (probado).

#### Hecho — panel del superadmin (`ventiq_superadmin`)

- **`lib/screens/fidelidad_screen.dart`**: interruptor global + reglas +
  beneficios + auditoría de puntos, con formularios de alta/edición y borrado
  avisado (el borrado de un beneficio con canjes se explica en vez de fallar).
- **`lib/services/fidelidad_service.dart`**: envuelve las 10 RPC y traduce
  `{ok:false,error}` a excepción para que el mensaje del servidor llegue tal cual.
- **`lib/models/fidelidad.dart`**: modelos tolerantes; solo etiquetas de lectura,
  ningún recálculo de saldos ni descuentos.
- Cableado: `AppRoutes.fidelidad`, ítem en el drawer (grupo Marketing) + su
  whitelist de navegación, import y `RouteGuard` en `main.dart`.
- `CatalogoDestinosService.entidades()` para el selector de alcance: lee
  `flow.entidad`, que tiene `entidad_select_all` para `authenticated`.
- **Test pre-existente arreglado**: `test/widget_test.dart` fallaba con
  `pumpAndSettle timed out` porque `AuthService.isLoggedIn()` espera a
  `SharedPreferences.getInstance()` sin `setMockInitialValues`. Con la suite en
  rojo no se podía verificar nada nuevo: ahora pasan **23** (20 de modelos + 1 de
  widget + 2 de pagos).

**Detalle que evitó un bug de UX:** las 10 RPC exigen
`fn_is_superadmin_full_access()` (`nivel_acceso = 1`), pero
`AuthService.canWrite()` deja pasar hasta nivel 2. Gatear la pantalla con
`canWrite()` habría mostrado botones que el servidor rechaza; se gatea con
`hasFullAccess()` y el nivel 2 ve un aviso de solo lectura.

**`analyze_files` no basta.** Devolvió «No errors» con un
`b.montoMinimo!` que sobre `BeneficioBienvenidaAdmin?` no compila
(`b?.montoMinimo == null` no promociona `b`). Lo cazó la compilación de
`flutter test`: la verificación real es correr los tests, no solo el analizador.

### ✅ Paso 9 — RPC único `cliente_home_feed` (escrito, falta que el usuario aplique la migración 35)

`migraciones/35_home_feed.sql` añade `flow.cliente_home_feed(...)`: una sola
petición que devuelve `items`, `total`, `has_more`, `next_cursor`,
`metadata.categorias`, `colecciones`, `patrocinados` y `contadores`. El Home pasó
de ~6 lecturas a 3 (feed + reseñas recientes + fidelidad).

Decisiones y por qué:

- **Sin cursor todavía.** El catálogo tiene **7 filas**: la carga completa ya evita
  "una petición por tarjeta", que era el motivo del cursor. El contrato
  (`has_more`/`next_cursor`) viaja completo y hoy siempre `false`/`null`, así que
  añadirlo después es aditivo y no rompe al cliente. Decidido con el usuario.
- **El parser de horarios NO se portó a SQL.** `HorarioAtencion` interpreta texto
  libre (`"8-4"`, `"Lun-Sab 8:00am - 6:00pm"`, `"sd"`, la regla de 12h vs 24h) y es
  deliberadamente conservador: si el texto mezcla "cerrado" y horas devuelve
  `desconocido`. Portarlo sería una **segunda implementación** de la misma regla, y
  si diverge el feed diría "abierto" donde el detalle dice "Horario no disponible".
  Por eso `solo_abiertos` sigue en Dart, dentro de `paginar()`.
- **`security invoker`, no `definer`.** El feed lee `agenda` y `notificaciones`
  para los contadores. Con `definer`, RLS se evaluaría como el definidor y un error
  en un `where` filtraría datos de otros usuarios.
- **Los contadores salen de `auth.uid()`, no de un parámetro del cliente**, así que
  el feed no sirve para espiar reservas ni puntos ajenos (a diferencia de las 3 RPC
  con IDOR del §5.c).
- **Compone, no copia.** Reusa `promociones_por_servicio()`,
  `resenas_por_servicio()`, `colecciones_activas()` y `campanas_activas()` con un
  join. Dos implementaciones de "qué promo aplica" es como aparecen los descuadres
  (la lección del Paso 5).
- **Los `items` conservan la forma anidada de `cliente_obtener_servicios`**
  (`servicio`/`local`/`entidad`) más `rating`, `total_resenas`, `categoria_nombre`,
  `categoria_codigo` y `promocion`. Si fueran filas planas, `LocalServicio.fromJson`
  no las leería y la navegación al detalle se rompería.
- **Orden "mejor valorados" alineado con el cliente.** El SQL usa la condición
  exacta del getter `HomeCatalogItem.tieneValoracion`
  (`total_resenas > 0 and rating > 0`), no solo `rating is null`, para que el orden
  del servidor y el "¿pinto estrellas?" del cliente no se contradigan.
- **El feed es solo para `authenticated`.** El Home solo es alcanzable con sesión
  (`/splash` manda a `/login`), y el feed compone funciones que únicamente tienen
  EXECUTE para `authenticated`: dárselo a `anon` haría fallar el feed entero, no
  solo una sección.

**Verificado contra la base en solo lectura, antes de escribir la migración.** La
consulta del feed se ejecutó como `SELECT`: `items = 7`, `total = 7`,
`categorias = 14`, 0 items sin nombre de servicio, de local o de categoría, 0 sin
`tipo_actividad`. Búsqueda: `pestanas`/`Pestañas`/`PESTAÑAS` → 3,
`omnibus`/`ómnibus` → 2, `unas`/`Uñas` → 1, `barber` → 0 y **`%` y `_` → 0** (con
`like` habrían devuelto 7: se usa `strpos` para que un comodín escrito por el
usuario sea literal). Provincia exacta: `'Villa Clara Province'` → 7,
`'Villa Clara'` → 0. Las 12 tablas que lee tienen SELECT para `authenticated`.

**Cliente.** `HomeFeed` + `HomeContadores`; `fetchFeed()` sustituye a
`HomeCatalogService.fetchPage()`; `_loadCatalog()` pide el mismo feed sin filtros
(una sola forma de leer el catálogo); `paginar()` queda reducido a "solo abiertos"
+ troceado, porque el resto lo aplica el servidor. El Home guarda la muestra
completa en `_feedItems`, así que **pasar de página no cuesta una petición**.

**Tests.** `inventtia_flow`: **+139 pasan** (antes 149). La diferencia cuadra: 8
tests de filtros + 3 de orden que se movieron a SQL, más 1 nuevo de "solo abiertos
también se pagina". Esos filtros se comprueban ahora en las consultas de
verificación de la propia migración.

Lo que falta de este paso:

- **Que el usuario aplique `35_home_feed.sql`** en los dos proyectos. ✅ aplicada.
- ~~Cablear los contadores a los badges.~~ → **hecho**: el feed siembra
  `NotificacionProvider` y `ReservasProvider`, y cada uno **ignora la semilla en
  cuanto tiene su propio dato** (`_snapshotInicialRecibido` y `_datosReales`), así
  que el badge no puede contradecir a su lista. Se cerró sin dejar estado intermedio.
- End-to-end en la app: que el riel, el carrusel y las colecciones se pinten desde
  el feed.

### ✅ Paso 10 — Ranking semanal real (migración 36, pendiente de aplicar)

`flow.cliente_ranking_semanal(p_limite)` devuelve los servicios con más demanda
**de la semana natural en curso** (lunes 00:00, hora de La Habana), encendiendo
`HomeFeatures.rankingSemanal`.

Decisiones y por qué:

- **La métrica es "lugares reservados", no "número de reservas".** En los datos
  reales hay dos servicios con 3 reservas cada uno que suman 11 y 3 lugares:
  ordenar por número de reservas los dejaría empatados y el desempate sería
  invisible. Así **el número que se pinta es el que ordena la lista**, que es
  justo lo que faltaba en el mock anterior (`_items.take(3)` con posiciones 1-2-3
  que no significaban nada).
- **Solo cuentan `Reservado` y `Completado`.** Una reserva cancelada no es demanda.
- **La ventana es la semana natural**, que es lo que promete el título del bloque,
  y no "los últimos 7 días", que es otra cosa.
- **No define la forma del item**: reusa la de `cliente_home_feed()` y solo le
  inyecta `lugares_semana`. Repetir la proyección anidada sería volver a tener dos
  definiciones del mismo objeto.
- **No se añadió tabla de vistas.** `home_features.dart` ya documentaba la métrica
  como "reservas reales"; registrar vistas exigiría tabla nueva, política de
  inserción y una escritura en cada apertura de detalle, con implicaciones de
  privacidad. Queda como ampliación aditiva si algún día hace falta.
- **Sin reservas esta semana el bloque no se pinta**, en vez de rellenar con el
  orden del catálogo.

Verificado contra la base en solo lectura: la ventana devuelve LS 21 "Lifting De
Cejas" (11 lugares / 3 reservas) y LS 19 "Depilación De Cejas" (3 / 3), y el
mecanismo de composición (`join` + `jsonb_set`) se probó con datos sintéticos: un
servicio sin reservas en la ventana queda fuera y el resto del item llega intacto.

### ✅ Paso 11 — Realtime solo para contadores (migración 37, pendiente de aplicar)

- **Las notificaciones ya estaban en vivo** (`.stream()` sobre
  `flow.notificaciones`, publicada y con `replica identity full`).
- **Las reservas no:** `flow.agenda` **no estaba** en la publicación
  `supabase_realtime`, así que una suscripción jamás habría disparado. La 37 la
  publica y le pone `replica identity full`.
- **`replica identity full` es obligatorio aquí, no un adorno.** Se filtra por
  `uuid_usuario` / `reservado_por`, que no son la clave primaria: con la identidad
  por defecto, el WAL de un UPDATE solo lleva la PK y las columnas cambiadas, así
  que al cambiar `id_estado` el filtro no se puede evaluar y **el evento se
  descarta** — justo el caso que interesa. La prueba de que este proyecto ya
  necesitaba eso: `flow.notificaciones` está en `full` y `flow.agenda` estaba en
  `default`.
- **Dos suscripciones**, una por columna, porque un filtro de Realtime cubre una
  sola y una reserva puede ser del usuario o haberla hecho él para un tercero.
- **El payload no se usa para contar**: dispara `recargar()`, que es la única que
  sabe qué cuenta como pendiente. Contar en el provider dejaría dos definiciones
  del mismo número.
- **Nunca por tarjeta**: una sola suscripción para el badge, no una por servicio.
- Red de seguridad: al volver a la app (`resumed`) se revalida el badge.

**No verificado desde aquí:** Realtime necesita un websocket vivo. La prueba en
dispositivo está escrita paso a paso en la propia migración. Si el badge no baja,
el sospechoso es `agenda_select_dueno_y_admins`, que llama a una función.

**Tests.** `inventtia_flow`: **+150 pasan** (los 139 anteriores más 11 nuevos de
`home_feed_test.dart` sobre el contrato del feed, los contadores y la etiqueta del
ranking).

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
| `27_promociones.sql` | tabla `flow.promocion` + 9 funciones + RLS, y reescribe 2 RPC de reserva personales | ✅ aplicada |
| `28_patrocinados.sql` | tabla `flow.campana` + 5 RPC + RLS; la configura el superadmin | ✅ aplicada |
| `29_bot_promociones.sql` | los 2 bots de cola aplican la promo vigente y consumen cupo; el bot de turnos cotiza con `calcular_precio_turno`. Generada desde las definiciones **vivas** (los archivos del repo están desactualizados) | ✅ aplicada |
| `30_colecciones.sql` | tablas `flow.coleccion` + `flow.coleccion_servicio` + 5 RPC + RLS; las cura el superadmin desde `ventiq_superadmin` | ✅ aplicada |
| `31_fidelidad.sql` | `flow.regla_fidelidad` + `flow.puntos_movimiento` (libro append-only) + `flow.beneficio_bienvenida` + `flow.beneficio_canje` + trigger de acreditación al completar + `cliente_mi_fidelidad()` | ✅ aplicada |
| `32_admin_fidelidad.sql` | 8 RPC de configuración y auditoría de fidelidad para `ventiq_superadmin`, + el correctivo de permisos de la 31 | ✅ aplicada |
| `33_config_fidelidad.sql` | interruptor global del superadmin: `flow.fidelidad_config` (fila única). Apagar pausa el trigger y oculta la sección, sin borrar nada | ✅ aplicada |
| `34_beneficio_bienvenida_precio.sql` | aplica el descuento del beneficio en `cotizar_reserva` y `cliente_reservar_directo`, con reclamo atómico del canje | ✅ aplicada |
| `35_home_feed.sql` | `flow.cliente_home_feed(...)`: una sola petición con `items` filtrados, `metadata.categorias`, `colecciones`, `patrocinados`, `contadores` y el contrato de cursor (`has_more`/`next_cursor`). Sustituye las ~6 lecturas del Home | ✅ aplicada |
| `36_ranking_semanal.sql` | `flow.cliente_ranking_semanal(p_limite)`: lugares reservados en la semana natural, reusando la forma de item del feed. Enciende `HomeFeatures.rankingSemanal` | ⏳ pendiente |
| `37_realtime_agenda.sql` | publica `flow.agenda` en `supabase_realtime` y le pone `replica identity full` (sin eso el evento de cambio de estado se descarta) | ⏳ pendiente |
| _(sin número)_ panel de fidelidad | `ventiq_superadmin`: pantalla que consume las 10 RPC (reglas, beneficios, auditoría/ajuste y el interruptor global) | ✅ escrita |

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

## 5.b ⚠️ CRÍTICO sin corregir: la `anon key` de release de `ventiq_superadmin` es una `service_role`

Encontrado al integrar los patrocinados. **No lo he tocado**: es una decisión del
usuario y el arreglo requiere una clave que solo él puede copiar del panel.

`ventiq_superadmin/lib/config/supabase_config.dart` llama `_releaseAnonKey` a un
JWT cuyo payload decodificado es:

```json
{"iss":"supabase","ref":"vsieeihstajlrdvpuooh","role":"service_role", ...}
```

Es decir: la clave de **`service_role` del proyecto de release**, embebida en el
binario de release de la app.

**Por qué es grave:** `service_role` **salta RLS por completo**. Cualquiera que
extraiga la cadena del APK (un APK es un ZIP; la clave está en texto plano) obtiene
lectura y escritura totales sobre la base de datos de producción: `auth.users`,
pagos, reservas, todo. No hace falta ni iniciar sesión.

Nótese que esto hace que las políticas RLS de `flow.campana` sean irrelevantes
para ese vector: la app las respeta porque inicia sesión, pero la clave no.

**Cómo comprobarlo:** el campo `role` del JWT. Una `anon` legítima dice
`"role":"anon"`; esta dice `"role":"service_role"`.

**Arreglo:** sustituir esa constante por la **anon key real** del proyecto de
release (Panel → Project Settings → API → `anon public`). La app funciona igual:
`ventiq_superadmin` autoriza con `auth.uid()` contra `public.app_dat_superadmin`
y las políticas RLS ya están puestas para ello. Lo que **no** hay que hacer es
seguir usando `service_role` en un cliente.

Relacionado, del mismo archivo y con el mismo patrón a revisar: la clave de
debug se llama `_debugAnonKey` y sí parece una `anon` legítima (su `ref` es el
proyecto de debug), pero conviene confirmar el campo `role` de ambas.

---

## 5.c ⚠️ Sin corregir: IDOR en 3 RPC de cliente

Al verificar las promociones salió un patrón que **no es de este trabajo** pero
sigue abierto. Son `security definer` y aceptan `p_uuid_usuario` **sin**
compararlo con `auth.uid()`:

| RPC | Qué permite el abuso |
|---|---|
| `cliente_reservar_directo(p_uuid_usuario, …)` | reservar **a nombre de otro**: le quema el cupo, le ocupa la reserva del día y le genera notificaciones |
| `cliente_cancelar_reserva(p_uuid_usuario, p_id_agenda)` | cancelar la reserva de otro |
| `cliente_actualizar_fecha_regla(p_uuid_usuario, …)` | mover la fecha de cola de otro |

Es explotable de verdad: `flow.resena` tiene `SELECT USING(true)` y
`flow.sala_espera` también, así que cualquier usuario autenticado puede cosechar
`uuid_usuario` reales por PostgREST y usarlos luego como parámetro.

**No lo introdujo la migración 27.** El archivo original
`rpc clientes/11_cliente_reservar_directo.sql` tampoco comprobaba `auth.uid()`; la
27 solo le añadió la lógica de promociones. En cambio `cotizar_reserva` (27) y
`cliente_reservar_pasaje_omnibus` (`rpc clientes/13_transporte_omnibus.sql`) **sí**
llevan el check: son el patrón a copiar.

El arreglo es de una línea por función y no rompe nada: `agenda_service.reservarDirecto`
siempre manda el uuid del usuario logueado, y el caso "reservar para un tercero"
debe seguir guardando `reservado_por = auth.uid()`, no el del titular.

**Decisión (usuario): pospuesto.** Se continúa con el plan; queda anotado aquí y
en el aviso de `docs/flow_schema/README.md`.

Relacionado, detectado en la misma verificación: **LS 11 es un callejón sin
salida**. `permite_reserva_directa = true` y tiene 3 turnos activos con precio
(17/18/19), pero `cliente_obtener_disponibilidad(11)` devuelve `[]` porque no
tiene `plan_tramo` para ninguna fecha: el cliente ve el servicio como reservable y
no puede completar nada. Es un problema de configuración de datos, no de código.

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