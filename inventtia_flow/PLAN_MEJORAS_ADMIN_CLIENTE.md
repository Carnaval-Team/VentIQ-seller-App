# Plan de mejoras — `inventtia_flow` (GoReserva)

**Estado:** ✅ **ejecutado** — código hecho, migraciones 40/41/42 **aplicadas por el
usuario** y **prueba manual completa: todo OK**. Solo queda, como opcional, el
chequeo de seguridad de §8.5.
**Ámbito:** app Flutter `inventtia_flow` (`lib/`) + esquema `flow` en Supabase de release
(`vsieeihstajlrdvpuooh`)
**Fecha de verificación del backend:** contra la BD **viva** vía MCP Supabase
(`information_schema`, `pg_proc`, `pg_policies`), no contra `docs/flow_schema/*.sql`
—el propio `plan.md` avisa de que ese material está desactualizado.

> Las 10 mejoras son de producto/admin, pero **3, 4, 8, 9 y 10 tocan el contrato que
> ve el cliente**: al activar/desactivar, al subir foto de servicio y al definir el
> horario, la parte cliente también cambia. Este plan incluye ambos lados.

---

## 0.bis Estado de ejecución (al cerrar el trabajo de código)

**Decisiones aplicadas:** migraciones **las aplicas tú** desde el SQL Editor (no se
tocó el DDL del proyecto de release) y **sí** se elimina la política `"update ls"`
(§1.4). Gráfico propio sin dependencias nuevas. Modo simple = "un tramo por turno".

| # | Mejora | Estado | Dónde quedó |
|---|--------|:------:|-------------|
| 1 | Dashboard en Gestión | ✅ | `widgets/dashboard_entidad.dart`, `widgets/grafico_barras.dart`, `services/dashboard_service.dart`, `models/dashboard_entidad.dart`; montado al final de `_GestionBody` |
| 2 | Fix label/placeholder solapados | ✅ | `gestion_locales_screen._GeoDropdown`, `planificacion_screen._SelectorDropdown`, más 3 formularios con el mismo patrón (ver §3.2) |
| 3 | Switch `activo` en locales | ✅ | `Local.activo`, `_LocalFormSheet`, chip `Inactivo` en la lista |
| 4 | Switch `activo` en servicios | ✅ | `Servicio.activo`, `ServicioFormSheet`, chip en la lista, banner en el detalle |
| 5 | Fix: guardar servicio no se reflejaba | ✅ | el sheet devuelve el `Servicio` releído; el detalle pasa a `_servicio` de estado |
| 6 | "Solo configurar turnos" / "No uso tramos" | ✅ | `_ModoGestionCard` + `_AyudaTramos` en `config_recursos_screen`; `_TurnoFormSheet` sin tramos; `admin_config_modo_gestion` / `admin_guardar_turno_auto` |
| 7 | Hora inicio/fin del turno | ✅ | `Turno.horaInicio/horaFin`, `etiquetaHoraTurno` en `models/recurso.dart`; pickers en el form de turno; se pinta en admin, ficha y selector de turno |
| 8 | Desactivar un local-servicio | ✅ | switch "Disponible para clientes" en `_ServicioCalendarTile` + banner y chips |
| 9 | Imagen para servicios (visible en cliente) | ✅ | hero prioriza `servicio.foto`, previews web-safe, cache-busting y la card del catálogo con fallback |
| 10 | Horario: días + apertura/cierre | ✅ | `_HorarioEditor` en `_LocalFormSheet`, `HorarioDetalle`/`parseConDetalle`/`textoDesdeDetalle`, y el bug de `_diasDe` corregido |

**Verificación de código hecha:** `mcp__dart__analyze_files` sobre `lib/` y `test/`
sin **ningún error** (solo avisos/infos preexistentes de `print`, `withOpacity` y
deprecaciones) y `flutter test` → **255 tests, todos en verde**.

**Estado de las migraciones:** 40, 41 y 42 **aplicadas** en
`vsieeihstajlrdvpuooh` desde el SQL Editor, y la app probada manualmente en los
cuatro caminos que dependían de ellas (switch de local, switch de servicio, modo
simple de turnos, horario por días y horas del turno). Resultado: **todo OK**.
Nota: la sesión terminó sin acceso al MCP de Supabase, así que el chequeo de
`get_advisors('security')` de §8.5 quedó sin ejecutar por mi parte; el snippet de
§8.5 lo cubre en un pegado.

**Desviaciones respecto al plan original (y por qué):**

- No se crearon `utils/modo_gestion.dart` ni `widgets/totales_recurso_turno.dart`: la
  lógica pura de #6 vive en `LocalServicio.ocultaTramos` y `Recurso.esCupoInterno`
  (más fácil de testear donde ya está el modelo) y las horas de #7 se pintan con
  `etiquetaHoraTurno`, que ya existía en `models/recurso.dart`.
- `test/modo_gestion_test.dart` se fundió en `test/activo_efectivo_test.dart` (cubre
  `ocultaTramos`, `esCupoInterno` y `activoEfectivo`); en su lugar se añadió
  `test/horas_turno_test.dart` para #7.
- Los nombres reales de las migraciones son
  `41_rpc_admin_dashboard_modo_y_horas.sql` y
  `42_cliente_filtro_activos_y_horas.sql`.
- `promociones_screen.dart:669` ya estaba correcto y no necesitó cambio; en cambio
  aparecieron **4 formularios más** con el patrón de #2 que el plan no listaba (abajo).

**Hecho por el usuario:** migraciones 40/41/42 aplicadas en `vsieeihstajlrdvpuooh`
desde el SQL Editor + checklist manual de §3 recorrido punto por punto. Resultado:
**todo OK**.

**Queda un solo paso, opcional:**

1. El chequeo de seguridad de §8.5. La sesión se quedó sin acceso al MCP de Supabase
   (solo estaba disponible el de Dart), así que no pude lanzar `get_advisors` yo
   mismo. El snippet de §8.5 lo hace en un pegado: confirma que la política
   `"update ls"` desapareció de `flow.local_servicio` y que no hay hallazgos nuevos.
   No bloquea nada — la migración 40 ya hace el `drop policy` —, pero conviene
   mirarlo una vez porque es un cambio de seguridad en producción.

> Recordatorio histórico, ya resuelto: mientras las migraciones no estuvieran
> aplicadas, las **lecturas** del cliente toleraban que faltaran (los filtros Dart
> asumen `activo = true` y el parser caía al texto) pero las **escrituras** del admin
> no (`createServicio`/`createLocal`/`guardarTurno` mandan columnas que solo existen
> tras la 40). Con las migraciones aplicadas, ya no aplica nada de esto.

---

## 0. Resumen y orden de ejecución

| # | Mejora | BD | Admin | Cliente | Riesgo |
|---|--------|:--:|:-----:|:-------:|:------:|
| 1 | Dashboard de totales + gráfico en Gestión | nueva RPC | nuevo widget | — | bajo |
| 2 | Fix label/placeholder solapados en formularios | — | 2 widgets | — | bajo |
| 3 | Switch `activo` en locales | 1 columna | form + lista | feed/RPCs | **alto** |
| 4 | Switch `activo` en servicios | 1 columna | form + lista | feed/RPCs | **alto** |
| 5 | Fix: guardar servicio no se refleja | — | 2 archivos | — | bajo |
| 6 | "Solo configurar turnos" / "No uso tramos" | 2 columnas + RPC | panel recursos | — | medio |
| 7 | Hora inicio/fin opcional en el turno | 2 columnas + RPC | form turno | fichas de turno | medio |
| 8 | Activar/desactivar un local-servicio | 1 columna | planificación | feed/RPCs | **alto** |
| 9 | Imagen para servicios (se ve en el cliente) | (ya existe `foto`) | preview web | hero del detalle | bajo |
| 10 | Horario de atención: días + apertura/cierre | 1 columna jsonb | form local | parser + ficha | medio |

**Orden de ejecución recomendado** (de menor a mayor riesgo, y agrupando lo que
comparte migración):

1. **Sprint A — fixes sin BD:** #2, #5, #9 (preview web + hero con foto de servicio).
2. **Sprint B — horario y turnos:** #10, #7, #6.
3. **Sprint C — visibilidad (necesita migración de 3 columnas + guards):** #3, #4, #8.
4. **Sprint D — dashboard:** #1.

Cada sprint termina con `flutter analyze` limpio + `flutter test` verde.

---

## 1. Verdad del backend (comprobado hoy)

### 1.1 Columnas que faltan

| Tabla | Columna | Existe | Consecuencia |
|---|---|:--:|---|
| `flow.app_dat_locales` | `activo` | **no** | #3 y #10 requieren migración |
| `flow.app_dat_servicios` | `activo` | **no** | #4 requiere migración |
| `flow.local_servicio` | `activo` | **no** | #8 requiere migración |
| `flow.turno` | `hora_inicio` / `hora_fin` | **no** | #7 requiere migración |
| `flow.app_dat_locales` | `horario_atencion` | sí, **`text` libre** | #10 necesita estructura adicional |
| `flow.app_dat_servicios` | `foto` | **sí** | #9 ya se puede persistir |
| `flow.local_servicio` | `permite_reserva_directa`, `cantidad_default`, `cantidad_max_capacidad` | sí | — |

### 1.2 Datos reales (diagnóstico)

- `flow.app_dat_locales`: 10 filas · `flow.app_dat_servicios`: 10 · `flow.local_servicio`: 8
- `flow.agenda`: 125 filas (8 en estado `Reservado`). Estados: `1 Reservado`, `2 Cancelado`, `3 Completado`.
- `horario_atencion` convive con formatos libres (`"8-4"`, `"Lun - Dom, 8:30 - 16:00"`, `"sd"`, `null`).

### 1.3 Funciones que gobiernan lo que ve el cliente

Confirmado con `pg_get_functiondef` (firma real, no la documentada):

| Función | Firma viva | Uso |
|---|---|---|
| `flow.cliente_home_feed` | `(p_query text, p_id_categoria int, p_provincia text, p_id_coleccion int, p_mejor_valorados bool)` | **única** fuente del Home cliente |
| `flow.cliente_obtener_servicios` | `(p_id_local, p_id_servicio, p_id_entidad, p_nombre_local, p_nombre_servicio, p_pais, p_provincia)` | feed de admin **y** catálogo del cliente **y** superadmin |
| `flow.cliente_obtener_disponibilidad` | `(p_id_local_servicio, p_desde date, p_hasta date)` | turnos reservables del cliente |
| `flow.cliente_reservar_directo` | `(...p_id_turno)` | reserva sin cola |
| `flow.cliente_entrar_sala_espera_cola` / `_reserva` | — | cola / lista de espera |
| `flow._ls_tiene_recursos(int)` | — | conmuta disponibilidad entre cupo-por-día y turnos |
| `flow._admin_puede_local_servicio(uuid, int)` | — | permiso admin; usa `admin_entidades_de_usuario` (owner ∪ `entidad_admin`) |

`flow.cliente_obtener_servicios` **no** se usa solo desde el cliente: la
administración de `inventtia_flow` (Planificación, detalle de servicio) y el
superadmin (patrocinados/colecciones) leen del mismo RPC — y el comentario de
`ventiq_superadmin/lib/services/catalogo_destinos_service.dart` dice explícitamente
que ahí reside la regla "lo que el cliente puede ver". Por eso el filtro de activos
entra con un parámetro nuevo con default, **no** sustituyendo el comportamiento
del admin (ver §2.2).

### 1.4 Hallazgo de seguridad (bloqueante para #3/#4/#8)

`flow.local_servicio` tiene 3 políticas de UPDATE; una de ellas es:

```
policyname = "update ls"   cmd = UPDATE   roles = {public}   qual = true   with_check = true
```

Como `public` incluye `anon`, **cualquiera con la anon key puede modificar
cualquier fila de `local_servicio`** (p. ej. `activo = false` en todo, o
`cantidad_max_capacidad = 999999`). Si #8 se implementa con un `activo` que un
anon puede escribir, la "desactivación" nace vulnerable. Se propone **eliminar esa
política** en la migración 40 (las políticas `*_admin` para `authenticated` cubren
todos los escritores reales del repo: ningún `lib/` de las 7 apps escribe
`local_servicio` fuera de `inventtia_flow`, y ahí ya lo hacen admins). Requiere tu
OK explícito: es un cambio de seguridad en producción.

---

## 2. Decisiones de diseño

### 2.1 Tres banderas de activo, un solo predicado

Se añade `activo boolean not null default true` a `app_dat_locales`,
`app_dat_servicios` y `local_servicio`, y **una** función que define la
visibilidad efectiva para el cliente:

```sql
create or replace function flow._ls_disponible(p_id_local_servicio integer)
returns boolean
language sql stable
set search_path to 'flow','public'
as $$
  select coalesce(l.activo, false) and coalesce(s.activo, false) and coalesce(ls.activo, false)
  from flow.local_servicio ls
  join flow.app_dat_locales l  on l.id = ls.id_local
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  where ls.id = p_id_local_servicio;
$$;
```

Se usa `coalesce(..., false)` porque `service_role` y scripts externos pueden
insertar `null` pese al `default`. `default true` ⇒ **ningún dato existente cambia
de visibilidad**: los 10 locales y 10 servicios siguen visibles tras migrar.

### 2.2 `cliente_obtener_servicios` gana `p_incluir_inactivos boolean default false`

No se puede filtrar dentro del RPC sin cegar al admin. Solución: parámetro con
default, y el admin pasa `true`.

```sql
drop function if exists flow.cliente_obtener_servicios(int,int,int,text,text,text,text);
create function flow.cliente_obtener_servicios(
  p_id_local int default null, p_id_servicio int default null,
  p_id_entidad int default null, p_nombre_local text default null,
  p_nombre_servicio text default null, p_pais text default null,
  p_provincia text default null, p_incluir_inactivos boolean default false) ...
```

`drop` + `create` (no `create or replace`) para **no dejar una sobrecarga** de 7
argumentos: PostgREST no resuelve funciones homónimas con aridad distinta y el
error sería en todas las apps. Es el mismo patrón ya usado en
`18_cliente_reservar_directo_drop_overloads.sql`. Las llamadas con argumentos
nombrados de 7/0 argumentos siguen funcionando (los defaults rellenan).

- Cliente (`catalogo_screen`, favoritos, superadmin): sin cambios → solo activos.
- Admin `inventtia_flow`: `CatalogoService.getLocalServicios(..., incluirInactivos: true)`.

### 2.3 Horario: estructura + texto, sin divergencia

`horario_atencion` sigue siendo la columna de lectura humana y del parser viejo.
Se añade `horario_detalle jsonb` **solo** cuando el admin usa el constructor
estructurado:

```json
{ "dias": [1,2,3,4,5], "apertura": "08:00", "cierre": "17:00" }
```

Reglas:
- El admin edita con **selector de días + hora apertura + hora cierre**. Al
  guardar se genera el texto canónico (`"Lun-Vie 08:00-17:00"`) en
  `horario_atencion` y el json en `horario_detalle`.
- Si el admin usa el campo **texto libre** (toggle "Horario avanzado / texto
  libre"), se guarda `horario_detalle = null` y manda el parser antiguo. **Nunca
  los dos a la vez**: sin ambigüedad, sin datos duplicados desincronizados.
- El cliente interpreta con `HorarioAtencion.parseConDetalle(texto, detalle)`:
  si `detalle` es válido usa días como **conjunto explícito** y una franja exacta;
  si no, cae al parser de texto.

**Bug real que esto además corrige:** `_diasDe()` en
`lib/utils/horario_atencion.dart:190-213` interpreta "el primero y el último día
mencionados" y rellena el **rango**. Un horario `"Lun, Mié, Vie 8:00-17:00"` se
lee hoy como **lunes a viernes** (abierto el martes y el jueves por error). Con
`horario_detalle` el conjunto de días es exacto.

### 2.4 Modo de gestión de recursos: `solo_turnos` y `sin_tramos`

Dos columnas en `flow.local_servicio`:

| Columna | Efecto en la UI admin | Efecto en BD |
|---|---|---|
| `sin_tramos` | oculta Tramos; el formulario de turno no pide tramos | recurso oculto `Cupo` (si `solo_turnos`) y **un tramo oculto por turno**, creados automáticamente |
| `solo_turnos` | oculta Recursos **y** Tramos; la pantalla es una lista plana de turnos | garantiza el recurso oculto `Cupo` y que todos los turnos cuelguen de él |

`check (not solo_turnos or sin_tramos)` en BD: `solo_turnos` implica `sin_tramos`.

Los objetos "virtuales" son filas normales (`recurso`/`tramo`), solo que no se
pintan. Así **no se rompe nada** de la lógica existente: `_ls_tiene_recursos`,
`plan_tramo`, `turno_tramo`, la disponibilidad por turno y la cola siguen
funcionando sin tocar una sola regla.

Con un tramo por turno, el cupo de cada turno pasa a ser **independiente**
(`plan_tramo` es por tramo). `admin_generar_plan_mensual` en modo "por recurso" da
la misma capacidad a todos los tramos del recurso ⇒ todos los turnos comparten la
misma cifra por día. Se documenta en la UI para no prometer lo que no hace.

### 2.5 Dashboard sin dependencias nuevas

`pubspec.yaml` no tiene gráficos. Se descarta añadir `fl_chart` (build sin red y
`pubspec.lock` de 7 apps). El gráfico es un `CustomPainter` propio
(`lib/widgets/grafico_barras.dart`): barras de reservas por día, últimos 30 días,
con ejes mínimos, tooltip al toque y sin animación costosa.

### 2.6 Tramos: qué son, explicado para todo el mundo

El texto actual (`config_recursos_screen.dart:401-407`) habla solo de transporte.
Se sustituye por una tarjeta de ayuda **"¿Qué es un tramo?"** con ejemplos por
oficio, y por un modo simple que lo esconde cuando no aplica:

> **Recurso** = la unidad que atiende. Ej.: *Carro 1* (transporte), *Mesa 3*
> (restaurante), *Habitación 4* (hospedaje), *Sillón de uñas* (belleza).
> **Tramo** = una capacidad que se gasta por separado dentro del recurso. Solo
> hace falta si un mismo turno consume **varias** cosas a la vez: *Ida* y
> *Vuelta* de un ómnibus, *Entrada* y *Salida* de un hospedaje. Si tu negocio no
> tiene ese caso (uñas, corte de pelo, consulta), **no necesitas tramos**: activa
> "Solo configurar turnos" y el sistema los gestiona solo.

---

## 3. Detalle por punto

### Punto 1 — Dashboard en la vista de admin

**Dónde:** al final de `_GestionBody`, justo después del `GridView` de módulos
(`lib/screens/admin/gestion_screen.dart:255-268`), bajo el título "Gestión".

**Qué muestra**
- Fila de KPIs: **Locales** (activos / total), **Servicios** (activos / total),
  **Local-servicio publicados**, **Reservas** (total y por estado:
  Reservado / Completado / Cancelado).
- **Gráfico de barras**: reservas por día, últimos 30 días.
- **Top 5** servicios por reservas (nombre · local · nº).

**Nuevo RPC** `flow.admin_dashboard_entidad(p_uuid_usuario uuid, p_id_entidad integer) returns jsonb`
— una sola petición, con el mismo permiso que el resto
(`p_id_entidad in (select id_entidad from flow.admin_entidades_de_usuario(p_uuid_usuario))`).
Forma:

```json
{
  "ok": true,
  "locales":  { "total": 10, "activos": 9 },
  "servicios": { "total": 10, "activos": 8 },
  "local_servicios": { "total": 8, "activos": 7, "inactivos": 1 },
  "reservas": { "total": 125, "reservado": 8, "completado": 110, "cancelado": 7 },
  "reservas_por_dia": [ { "fecha": "2026-02-01", "total": 4, "canceladas": 0 }, ... ],
  "top_servicios": [ { "id_local_servicio": 12, "servicio": "Corte", "local": "Salon 1", "total": 22 } ]
}
```

**Archivos**
- `docs/flow_schema/migraciones/41_rpc_admin_dashboard_y_modo.sql` (nuevo)
- `lib/services/dashboard_service.dart` (nuevo)
- `lib/models/dashboard_entidad.dart` (nuevo)
- `lib/widgets/dashboard_entidad.dart` (nuevo: KPIs + gráfico + top)
- `lib/widgets/grafico_barras.dart` (nuevo: `CustomPainter`)
- `lib/screens/admin/gestion_screen.dart` (montar la sección)

**Criterios de aceptación**
1. Con una entidad con datos, los 4 KPIs coinciden con un `count(*)` manual en SQL.
2. El gráfico pinta 30 barras (incluidos días con 0) y la altura es monótona con el total.
3. Cambiar de entidad en el selector de la AppBar refresca el dashboard.
4. Si la RPC falla, la sección muestra un aviso y **no** rompe el resto de la pantalla.

---

### Punto 2 — Label y placeholder solapados en los formularios

**Diagnóstico (verificado en el SDK de Flutter instalado).** El patrón culpable es
`InputDecorator` + `DropdownButton` con `contentPadding` vertical diminuto:

```dart
// lib/screens/admin/gestion_locales_screen.dart:605-619
InputDecorator(
  decoration: InputDecoration(
    labelText: label,
    prefixIcon: ...,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), // ←
  ),
  isEmpty: value == null,
  child: DropdownButton<Map<String, dynamic>>(..., isDense: true, hint: Text(hint, ...)),
)
```

`AppTheme.light` fija `inputDecorationTheme.border = OutlineInputBorder` y
`contentPadding` vertical **14** (`lib/config/app_theme.dart:53-60`). Al forzar
vertical **4**, `InputDecorator` dibuja la etiqueta flotante centrada en el borde
superior (`input_decorator.dart:1620-1624`: `floatingY = -labelHeight*scale/2 -
strokeOffset/2`) mientras el contenido arranca en `contentPadding.top` + altura de
etiqueta: con solo 4 px, la etiqueta se monta **encima** del valor/placeholder.
Es exactamente "el texto y por detrás el placeholder, uno sobre otro".

**Ocurrencias reales** (el resto de los `InputDecorator` del repo usan el
`contentPadding` del tema, vertical 14, y están bien):

| Archivo | Línea | Síntoma |
|---|---|---|
| `lib/screens/admin/gestion_locales_screen.dart` | 605-643 (`_GeoDropdown`) | **País** y **Estado/Provincia** |
| `lib/screens/admin/planificacion_screen.dart` | 1441-1473 (`_SelectorDropdown`) | selectores Local/Servicio del alta de plan |

**Fix.** Convertir ambos a `DropdownButtonFormField<T>` con el `decoration` del
tema (mismo widget que ya usa el resto de la app, p. ej.
`gestion_servicios_screen.dart:703`), sin `contentPadding` manual:

```dart
DropdownButtonFormField<Map<String, dynamic>>(
  initialValue: value,                    // `value:` está deprecado en Flutter 3.44
  isExpanded: true,
  decoration: InputDecoration(
    labelText: label,
    prefixIcon: loading ? spinner : Icon(icon),
    border: const OutlineInputBorder(),
  ),
  hint: Text(hint, style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
  items: ...,
  onChanged: enabled && !loading ? onChanged : null,
)
```

`isEmpty` deja de ser responsabilidad del widget: `DropdownButtonFormField` lo
deriva y usa el `contentPadding` del tema, que ya está calibrado.

**Auditoría pedida ("en todos los formularios") — resultado real.** Se barrió todo
`lib/` buscando `InputDecoration` con `labelText` **y** `contentPadding` vertical < 12.
Aparecieron **5 sitios**, todos ya corregidos, y los dos del plan eran solo el
principio:

| Archivo | Sitio | Cambio |
|---|---|---|
| `gestion_locales_screen.dart` | `_GeoDropdown` (País, Estado/Provincia) | `InputDecorator` → `DropdownButtonFormField` |
| `planificacion_screen.dart` | `_SelectorDropdown` (Local/Servicio) | idem |
| `reservas_screen.dart:1386-1429` | filtros Local / Servicio | fuera `contentPadding` y `isDense` |
| `mis_tickets_screen.dart:630-673` | filtros Local / Servicio | idem |
| `vendedor/vendedor_screen.dart:1427-1470` | filtros Local / Servicio | idem |

Además, en `planificacion_screen.dart:2207` el `InputDecorator` de "Local - Servicio"
preajustado no llevaba `isEmpty: false`, así que etiqueta y texto podían compartir
banda; se marca explícito. Y su `DropdownButtonFormField` gemelo pasa a
`initialValue` **solo si el valor está entre los items**, para que una lista aún
cargando no deje etiqueta flotante y placeholder a la vez.

Los `isDense: true` **con** `labelText` que quedan (`config_plan_mensual`,
`gestion_servicios`, `local_servicio_detail`, `mis_tickets`) toman el `contentPadding`
del tema (`vertical: 14`): `isDense` no lo sobreescribe
(`input_decorator.dart:4063`), y `test/dropdown_sin_solape_test.dart` fija ese caso.

**Criterios de aceptación**
1. Con un valor seleccionado, la etiqueta flota por encima del borde y **no** toca el texto.
2. Sin valor, se lee el `hint` en el mismo renglón donde irá el valor.
3. `Pais`/`Estado/Provincia` en "Nuevo Local" y el selector "Local - Servicio" en
   Planificación → alta de plan: sin solape con el valor puesto y con el campo vacío.
4. Sin overflow horizontal con nombres largos (`isExpanded: true`).
5. `flutter test test/dropdown_sin_solape_test.dart` verde: con valor no se pinta el
   placeholder, etiqueta y valor no se solapan, y el tema mantiene `vertical ≥ 10`.

---

### Punto 3 — Switch `activo` en locales

**BD:** `alter table flow.app_dat_locales add column activo boolean not null default true;`

**Admin**
- `Local.activo` en `lib/models/servicio.dart` (clase `Local`).
- `CatalogoService.createLocal/updateLocal` aceptan y persisten `activo`.
- `_LocalFormSheet` (`gestion_locales_screen.dart`): `SwitchListTile("Local activo")`
  con texto de ayuda: *"Si lo desactivas, este local y **todos** sus servicios
  dejan de aparecer y de poder reservarse."* En creación arranca en `true`.
- La lista de locales (`gestion_locales_screen.dart:124-171`): chip
  `Inactivo` + el tile atenuado. Se sigue listando (el admin debe poder reactivarlo).

**Cliente**
- `cliente_home_feed`: `where l.activo and s.activo and ls.activo`.
- `cliente_obtener_servicios` (default activos): igual, salvo `p_incluir_inactivos`.
- `cliente_obtener_disponibilidad`, `..._transporte`, `..._fechas_transporte`,
  `cliente_reservar_directo`, `cliente_reservar_pasaje_omnibus`,
  `cliente_entrar_sala_espera_cola`, `cliente_entrar_sala_espera_reserva`:
  guarda `if not flow._ls_disponible(p_id_local_servicio)` → `[]` o
  `{"ok": false, "error": "Este servicio no está disponible por ahora"}`.
- `cliente_ranking_semanal`: excluir inactivos.
- Cliente "defensivo": `catalogo_screen._filtered`, favoritos
  (`favorito_service.getLocalServiciosFavoritos`) y `local_servicio_detail_screen`
  descartan ítems con `!activoEfectivo` por si llega una fila vieja en caché.

**Criterios de aceptación**
1. Desactivar el local X ⇒ sus N servicios desaparecen del Home, del catálogo y de
   favoritos, y `cliente_obtener_disponibilidad` de cualquiera de sus
   local-servicio responde `[]`.
2. Un intento de reserva directa sobre ese local-servicio devuelve error explícito,
   no una reserva creada.
3. Reactivar ⇒ todo vuelve, sin tocar nada más.
4. Los datos previos a la migración siguen visibles (`default true`).

---

### Punto 4 — Switch `activo` en servicios

Idéntico al punto 3, pero en la otra dimensión:

**BD:** `alter table flow.app_dat_servicios add column activo boolean not null default true;`

**Admin**
- `Servicio.activo`; `CatalogoService.createServicio/updateServicio` con `activo`.
- `ServicioFormSheet` (`gestion_servicios_screen.dart:139+`): `SwitchListTile("Servicio activo")`
  con ayuda *"Si lo desactivas, no se mostrará en ningún local ni podrá reservarse."*
- Lista de servicios: chip `Inactivo` y tile atenuado.
- `ServicioDetailScreen`: fila "Estado: Activo/Inactivo" y **banner** cuando está
  inactivo indicando que ningún cliente lo ve (hoy nada lo dice y el admin cree
  que está publicado).

**Cliente:** mismo predicado `_ls_disponible` (que ya incluye `s.activo`).

**Criterios de aceptación:** equivalentes a #3 — desactivar un servicio oculta
**todas** sus combinaciones local-servicio, en todos los locales.

---

### Punto 5 — (fix) Guardar en el servicio no se refleja al momento

**Causa raíz (confirmada en el código).** El sheet de servicio cierra sin
resultado:

```dart
// lib/screens/admin/gestion_servicios_screen.dart:589
Navigator.pop(context);          // ← pop(context, null)
```

pero el detalle solo se refresca si recibe `true`:

```dart
// lib/screens/admin/servicio_detail_screen.dart:94-106
final res = await showModalBottomSheet<bool>(...);
if (res == true && mounted) {
  Navigator.pop(context, true);  // nunca entra: res == null
}
```

Resultado: el detalle conserva `widget.servicio` (un `final` inmutable,
`servicio_detail_screen.dart:13`), así que sigue pintando nombre, descripción,
foto y tipo **viejos**. Solo al volver al listado (cuyo `onTap` hace
`.then((_) => _cargar())`, línea 129) y reabrir el servicio se ve el cambio.
Coincide al 100 % con lo reportado.

**Fix (3 partes)**

1. `ServicioFormSheet._submit` → `Navigator.pop(context, true)` y devolver además
   el `Servicio` actualizado por el retorno (`pop<Servicio>(context, actualizado)`),
   reconstruido desde la respuesta de `updateServicio` (que ya hace `.select().single()`).
2. `ServicioDetailScreen` deja de leer `widget.servicio` en el `build`: pasa a
   `Servicio _servicio` en el `State`. Tras editar:
   `setState(() => _servicio = devuelto)` **sin** cerrar el detalle, más un
   `SnackBar("Cambios guardados")`. Sigue devolviendo `true` a la lista cuando el
   usuario sale por atrás (`PopScope`/`Navigator.pop`), para que la lista recargue.
3. **Invalidación de la foto.** `ImagenService.pathServicio(id)` es fijo
   (`servicios/<id>.jpg`) con `upsert: true` ⇒ la URL no cambia al reemplazar la
   imagen y `NetImage`/`CachedNetworkImage` sigue sirviendo la vieja. Se añade
   `?v=<timestamp>` al `foto` guardado tras subir (`ImagenService.subirImagen`
   devuelve la URL con `v=` o se compone en el llamador), de modo que el cambio de
   imagen se ve al instante. **Mismo arreglo para locales** (`locales/<id>.jpg`).

**Criterios de aceptación**
1. Editar nombre/descripción/tipo/precio y guardar ⇒ el detalle se actualiza **sin
   salir** de la pantalla.
2. Al volver al listado, el listado también está actualizado.
3. Cambiar la foto ⇒ la nueva imagen se ve de inmediato (admin y cliente) sin
   purgar caché a mano.
4. `flutter test test/detalle_hero_header_test.dart` y el resto siguen verdes.

---

### Punto 6 — "Solo configurar turnos" / "No uso tramos"

**BD** (migración 40): `flow.local_servicio.solo_turnos boolean not null default false`,
`flow.local_servicio.sin_tramos boolean not null default false`,
`check (not solo_turnos or sin_tramos)`.

**UI — `lib/screens/admin/config_recursos_screen.dart`**
- Arriba del panel, tarjeta **"Modo de configuración"**:
  - `CheckboxListTile("Solo configurar turnos")` — *"El sistema crea un cupo
    interno y un tramo por turno. No verás recursos ni tramos."*
  - Si está apagado: `CheckboxListTile("No uso tramos")` — *"Mantienes tus
    recursos, pero sin gestionar tramos: cada turno recibe su propio cupo."*
- `sin_tramos == true`:
  - `_RecursoCard` no pinta la sección Tramos ni el botón "Tramo".
  - `_TurnoFormSheet` sustituye la lista de checkboxes de tramos por una línea
    informativa ("Cada turno reserva su propio cupo, sin tramos.") y **no** exige
    `_tramosSel` (hoy es obligatorio, `config_recursos_screen.dart:958-961`).
- `solo_turnos == true`: no se pinta la lista de recursos. Se pinta un único
  bloque **"Turnos"** con los turnos del recurso interno y "+ Turno".
- Se ocultan filtros/avisos de transporte que no apliquen y se mantiene el aviso
  de mínimos de ida/vuelta **solo** en `transporte_omnibus` (lógica existente,
  `config_recursos_screen.dart:71-101`).
- **Reemplazo del texto de ayuda** por la tarjeta "¿Qué es un tramo?" de §2.6.

**Nuevas RPC** (migración 41):
- `flow.admin_config_modo_gestion(p_uuid_usuario, p_id_local_servicio, p_solo_turnos boolean, p_sin_tramos boolean) returns jsonb`
  - valida con `_admin_puede_local_servicio`;
  - actualiza las 2 banderas;
  - si `solo_turnos`: garantiza el recurso oculto `'Cupo'`
    (`activo = true`, `capacidad = cantidad_max_capacidad`) y **mueve** ahí todos
    los turnos del local_servicio (con `turno_tramo` reconstruido);
  - si `sin_tramos`: para cada turno sin tramo, crea el tramo oculto
    (nombre = nombre del turno, `capacidad null` = hereda) y lo enlaza;
  - idempotente (segunda llamada no duplica nada).
- `flow.admin_guardar_turno_auto(p_uuid_usuario, p_id_local_servicio, p_nombre, p_orden, p_activo, p_precios, p_hora_inicio, p_hora_fin, p_id) returns jsonb`
  - en un solo viaje: asegura recurso oculto + tramo oculto del turno + crea/edita
    el turno y su `turno_tramo`. Es lo que usa la UI cuando `sin_tramos = true`.

**Criterios de aceptación**
1. Marcar "Solo configurar turnos" con 0 recursos y crear 3 turnos ⇒ en BD hay
   1 `recurso` (oculto) y 3 `tramo` (ocultos, uno por turno), 3 `turno`,
   3 `turno_tramo`. La UI solo muestra los 3 turnos.
2. La disponibilidad del cliente devuelve los 3 turnos con cupo.
3. Desmarcar el modo ⇒ vuelven a verse recursos y tramos; **no se ha perdido nada**.
4. Marcar/desmarcar dos veces seguidas no duplica recursos, tramos ni enlaces.
5. Una reserva creada en modo simple sigue siendo válida (no se toca `agenda`).
6. El recurso oculto y sus tramos **nunca** aparecen en `_RecursoCard` ni con nombre
   de usuario en `config_plan_mensual_screen`: ahí se rotula **"Cupo del día"** y la
   cabecera dice "Capacidad por día" con la explicación de que el cupo se comparte
   entre todos los turnos (`Recurso.esCupoInterno`).

---

### Punto 7 — Hora de inicio/fin opcional en el turno

**BD:** `alter table flow.turno add column hora_inicio time; add column hora_fin time;`
(ambas nullable, con `check (hora_fin is null or hora_inicio is null or hora_fin > hora_inicio)`).

**Admin**
- `Turno.horaInicio/horaFin` (`String?` en formato `HH:mm`) en `lib/models/recurso.dart`.
- `_TurnoFormSheet`: dos `showTimePicker` ("Hora de inicio", "Hora de fin"),
  opcionales, con `✕` para limpiar. Validación: si se pone una, pide la otra; fin > inicio.
- `RecursoService.guardarTurno(... horaInicio, horaFin)` y el nuevo
  `guardarTurnoAuto(...)`.
- `_RecursoCard` pinta `09:00 – 11:00` junto al nombre del turno.
- `admin_listar_recursos` devuelve `hora_inicio` y `hora_fin` (recreate de la
  función, forma actual + 2 campos).

**Cliente**
- `cliente_obtener_disponibilidad` (rama recursos) añade `hora_inicio`/`hora_fin`
  al jsonb de cada turno.
- `TurnoDisponible` gana `horaInicio/horaFin`; los selectores de turno
  (`local_servicio_detail_screen.dart`, `mis_tickets_screen`, `reserva_*`) y
  `widgets/totales_recurso_turno.dart` muestran `"09:00 – 11:00 · 3 libres"`.
- Nuevo helper puro en `lib/utils/turnos_servicio.dart`:
  `String? etiquetaHoraTurno(String? inicio, String? fin)` → `null` si ambas son
  nulas, `"09:00"` si solo hay inicio, `"09:00 – 11:00"` si hay las dos. Testeable.

**Criterios de aceptación**
1. Crear un turno sin horas ⇒ en BD `null`/`null`, y la UI no pinta ni un guion suelto.
2. Crear un turno 09:00–11:00 ⇒ se ve en el admin, en la ficha del cliente y en la
   lista de turnos; el cupo y la reserva no cambian de comportamiento.
3. Editar un turno quitando las horas ⇒ vuelven a `null`.
4. Turno con hora fin ≤ inicio ⇒ error de validación en el formulario, sin escritura.

---

### Punto 8 — Desactivar un local-servicio en Planificación

**BD:** `alter table flow.local_servicio add column activo boolean not null default true;`

**Admin**
- En `_ServicioCalendarTile` (`planificacion_screen.dart:333+`), junto al switch de
  "Reserva directa" (`_toggleReservaDirecta`, línea 362), un switch
  **"Disponible para clientes"** (`activo`), que llama a
  `CatalogoService.updateLocalServicio(id, activo: ...)` y recarga.
- El grupo por local (`_LocalGroup`) y el tile muestran chip `Inactivo` y quedan
  atenuados. Un local-servicio inactivo **no** permite planificar día: se avisa y
  se ofrece activarlo (hoy el calendario seguiría dejando planificar algo invisible).
- La lista de Planificación muestra un filtro rápido "Ocultar inactivos" (por
  defecto: se ven, para poder reactivarlos).

**Cliente:** el predicado `_ls_disponible` (que ya incluye `ls.activo`) lo saca del
Home, del catálogo, de la disponibilidad y bloquea la reserva.

**Criterios de aceptación**
1. Desactivar el par (Local A · Servicio B) ⇒ desaparece del Home y del catálogo,
   `cliente_obtener_disponibilidad` de ese id responde `[]`, y reservar da error.
2. Otros pares del mismo local/servicio **no** se ven afectados.
3. Reactivar ⇒ vuelve exactamente donde estaba.

---

### Punto 9 — Imagen para servicios (y que el cliente la vea)

**Hallazgo.** La subida **ya existe** en el admin: `ServicioFormSheet` tiene
selector de imagen y sube a `flow-imagenes` con `ImagenService.pathServicio`
(`gestion_servicios_screen.dart:452-484, 536-579`), y `Servicio.foto` ya viaja en
`cliente_obtener_servicios`/`cliente_home_feed`. Lo que falta es que **se vea**:

1. **La ficha del cliente ignora la foto del servicio.**
   `DetalleHeroHeader` sólo usa `local.foto`
   (`lib/widgets/detalle_hero_header.dart:91`). El feed sí prioriza
   `servicio.foto` (`home_catalog_service.dart:544`), así que hoy la tarjeta del
   Home enseña la foto del servicio y, al abrirla, cambia a la del local: parece
   que "no se guardó". Fix: `preferir servicio.foto` y caer a `local.foto`, con
   `_FallbackFoto` si no hay ninguna.
2. **La preview rompe en web.** `Image.file(File(_imagenFile!.path))` no es válido
   en web (`gestion_servicios_screen.dart` y `gestion_locales_screen.dart:437`).
   Fix: helper `previewImagenLocal(XFile)` en `lib/widgets/preview_imagen.dart` →
   `Image.memory(await xfile.readAsBytes())` en web y `Image.file` en nativo.
3. **URL cacheada** tras reemplazar la imagen → ver punto 5, parte 3.

**Criterios de aceptación**
1. Crear un servicio con imagen ⇒ la foto se ve en el listado admin, en la tarjeta
   del Home **y** en el hero de la ficha del cliente.
2. Un servicio sin foto sigue mostrando la foto del local (no hay regresión).
3. En web (`flutter run -d chrome`) elegir y previsualizar imagen no lanza.
4. Reemplazar la imagen de un servicio existente se ve sin recargar la app.

---

### Punto 10 — Horario de atención: días + apertura y cierre

**BD:** `alter table flow.app_dat_locales add column horario_detalle jsonb;`
(forma en §2.3; `check` opcional de forma).

**Admin — `_LocalFormSheet`**
- Bloque "Horario de atención":
  - Fila de `FilterChip` **Lun · Mar · Mié · Jue · Vie · Sáb · Dom** (multi-selección).
  - Botones **Hora de apertura** / **Hora de cierre** (`showTimePicker`).
  - Vista previa en vivo: `"Lun-Vie 08:00-17:00"`.
  - Botón **"Duplicar a todos los días"** (atajo frecuente).
  - Toggle **"Horario avanzado (texto libre)"** que oculta el constructor y
    muestra el `TextFormField` actual (`gestion_locales_screen.dart:505-512`). Al
    usarlo se guarda `horario_detalle = null` (fallback al parser).
- Generación de texto canónica (nueva función pura en
  `lib/utils/horario_atencion.dart`):
  `String textoDesdeDetalle(HorarioDetalle d)` → agrupa días **contiguos** en
  rangos: `[1,2,3,4,5] → "Lun-Vie 08:00-17:00"`, `[1,3,5] → "Lun, Mié, Vie 08:00-17:00"`.
- Validación: al menos 1 día y `cierre > apertura` (o modo 24h si apertura == cierre).

**Cliente**
- `Local.horarioDetalle` (`Map<String, dynamic>?`), leído de
  `app_dat_locales.horario_detalle`.
- `cliente_home_feed` y `cliente_obtener_servicios` devuelven
  `local.horario_detalle`.
- `HorarioAtencion.parseConDetalle(texto, detalle)`: si `detalle` es válido, usa
  los **días como conjunto** y la franja exacta (sin la heurística de rangos);
  si no, `parse(texto)`.
- Se usa en `home_catalog_service._desdeItemFeed` (línea 530),
  `home_client_screen` (línea 253, filtro "Solo abiertos"),
  `catalogo_screen` (línea 227) y la ficha `local_servicio_detail_screen` (línea 1442),
  que además pinta una tabla de días → horario cuando hay `horario_detalle`.

**Criterios de aceptación**
1. Local con Lun-Vie 08:00-17:00 ⇒ `horario_atencion = "Lun-Vie 08:00-17:00"` y
   `horario_detalle = {"dias":[1,2,3,4,5],"apertura":"08:00","cierre":"17:00"}`.
2. Un miércoles a las 10:00 el local sale "Abierto ahora"; un sábado, no.
3. `[Lun, Mié, Vie]` ⇒ el **martes** sale cerrado (hoy el parser antiguo lo da por
   abierto: regresión corregida).
4. Modo texto libre ⇒ `horario_detalle` queda `null` y el comportamiento es el de hoy.
5. Los 10 locales existentes (texto libre) siguen mostrando su horario tal cual.

---

## 4. Migraciones SQL propuestas

Se crean en `inventtia_flow/docs/flow_schema/migraciones/` (numeración siguiente a
la 39). Se aplican **manualmente** por ti, o por MCP si lo autorizas (ver §7).
Cada archivo es idempotente (`if not exists`, `drop function if exists`, `create or
replace`) y documenta al principio su reversibilidad, igual que las 39 anteriores.

### `40_activo_servicios_locales_turnos_horario.sql`
```sql
-- DDL de columnas nuevas (ver §1.1) + check de coherencia + _ls_disponible()
alter table flow.app_dat_locales   add column if not exists activo boolean not null default true;
alter table flow.app_dat_locales   add column if not exists horario_detalle jsonb;
alter table flow.app_dat_servicios add column if not exists activo boolean not null default true;
alter table flow.local_servicio    add column if not exists activo boolean not null default true;
alter table flow.local_servicio    add column if not exists solo_turnos boolean not null default false;
alter table flow.local_servicio    add column if not exists sin_tramos  boolean not null default false;
alter table flow.turno             add column if not exists hora_inicio time;
alter table flow.turno             add column if not exists hora_fin    time;

alter table flow.local_servicio drop constraint if exists local_servicio_modo_chk;
alter table flow.local_servicio add  constraint local_servicio_modo_chk
  check (not solo_turnos or sin_tramos);

alter table flow.turno drop constraint if exists turno_horas_chk;
alter table flow.turno add  constraint turno_horas_chk
  check (hora_inicio is null or hora_fin is null or hora_fin > hora_inicio);

-- SEGURIDAD (requiere tu OK, §1.4): elimina el UPDATE abierto a `public`/anon.
drop policy if exists "update ls" on flow.local_servicio;

-- Visibilidad efectiva para el cliente (reutilizada por todos los RPC cliente).
create or replace function flow._ls_disponible(p_id_local_servicio integer) ...
```

### `41_rpc_admin_dashboard_modo_y_horas.sql`
- `admin_dashboard_entidad` (nuevo, §Punto 1)
- `admin_config_modo_gestion` (nuevo, §Punto 6)
- `admin_guardar_turno_auto` (nuevo, §Punto 6)
- `admin_guardar_turno` (recreate: `+ p_hora_inicio time, + p_hora_fin time`; se
  hace `drop function` + `create` porque cambia la aridad y sólo lo llama esta app)
- `admin_listar_recursos` (recreate: `+ hora_inicio`, `+ hora_fin` en cada turno)

### `42_cliente_filtro_activos_y_horas.sql`
- `cliente_obtener_servicios`: `drop` + `create` con `p_incluir_inactivos default false`
  y filtro `l.activo and s.activo and ls.activo` cuando no se piden inactivos
  (+ `local.horario_detalle`).
- `cliente_home_feed`: se **reescribe partiendo del cuerpo vivo** obtenido con
  `pg_get_functiondef` (la copia del repo, migración 35, está desactualizada:
  la firma viva tiene `p_query/p_id_categoria/p_provincia/p_id_coleccion/p_mejor_valorados`,
  no la documentada) para añadir el filtro de activos, `horario_detalle` y las
  horas del turno.
- `cliente_ranking_semanal`: **no se toca**, a propósito. Su cuerpo vivo cruza la
  ventana de `agenda` con `jsonb_array_elements(flow.cliente_home_feed() -> 'items')`,
  así que hereda el filtro de activos y los campos del feed (comprobado con
  `pg_get_functiondef`: no menciona `activo` ni `local_servicio`).
- Guards de `_ls_disponible` en: `cliente_obtener_disponibilidad`,
  `cliente_obtener_disponibilidad_transporte`,
  `cliente_obtener_fechas_disponibles_transporte`, `cliente_reservar_directo`,
  `cliente_reservar_pasaje_omnibus`, `cliente_entrar_sala_espera_cola`,
  `cliente_entrar_sala_espera_reserva`.

> **Regla de trabajo:** antes de reescribir cualquiera de estas funciones se
> extrae su definición viva con `pg_get_functiondef` y se reescribe **sobre ella**,
> no sobre el `.sql` del repo. La lección está en `plan.md` §1.

---

## 5. Archivos afectados (mapa de escritura)

| Capa | Archivos |
|---|---|
| SQL | `docs/flow_schema/migraciones/40_*.sql`, `41_*.sql`, `42_*.sql` |
| Modelos | `models/servicio.dart` (Local/Servicio/LocalServicio), `models/recurso.dart` (Turno/Recurso), `models/disponibilidad_dia.dart`, `models/dashboard_entidad.dart` (nuevo) |
| Utilidades | `utils/horario_atencion.dart` (HorarioDetalle + parseConDetalle + textoDesdeDetalle + fix de `_diasDe`). La lógica pura de #6 vive en `models/servicio.dart` (`LocalServicio.ocultaTramos`) y `models/recurso.dart` (`Recurso.esCupoInterno`), así que **no** hay `utils/modo_gestion.dart` |
| Servicios | `catalogo_service.dart`, `recurso_service.dart`, `home_catalog_service.dart`, `favorito_service.dart`, `dashboard_service.dart` (nuevo), `imagen_service.dart` (cache-busting) |
| Admin | `gestion_screen.dart`, `gestion_locales_screen.dart`, `gestion_servicios_screen.dart`, `servicio_detail_screen.dart`, `config_recursos_screen.dart`, `planificacion_screen.dart`, `config_plan_mensual_screen.dart`, `reservas_screen.dart` |
| Widgets | `detalle_hero_header.dart`, `net_image.dart`, `dashboard_entidad.dart` (nuevo), `grafico_barras.dart` (nuevo), `preview_imagen.dart` (nuevo) |
| Cliente | `home_client_screen.dart`, `catalogo_screen.dart`, `local_servicio_detail_screen.dart`, `mis_tickets_screen.dart`, `vendedor/vendedor_screen.dart` |
| Tests | `test/horario_atencion_test.dart`, `test/turnos_servicio_test.dart`, `test/detalle_hero_header_test.dart` (ampliados) + `test/dashboard_entidad_test.dart`, `test/activo_efectivo_test.dart`, `test/horas_turno_test.dart`, `test/dropdown_sin_solape_test.dart` (nuevos) |

---

## 6. Plan de pruebas

**Unitarias (puras, sin red — es el estilo del repo, 20 archivos en `test/`)**
- `horario_atencion_test.dart`:
  - `textoDesdeDetalle([1,2,3,4,5], 08:00, 17:00) == "Lun-Vie 08:00-17:00"`.
  - `textoDesdeDetalle([1,3,5], ...) == "Lun, Mié, Vie ..."`.
  - `parseConDetalle` con días no contiguos: el martes **no** está en `dias` (hoy sí: regresión).
  - `parseConDetalle(texto, null)` cae al parser antiguo (mismo resultado que `parse`).
  - JSON malformado / claves ausentes / horas inválidas ⇒ `desconocido`, nunca excepción.
- `turnos_servicio_test.dart`: `etiquetaHoraTurno(null,null) == null`,
  `("09:00",null) == "09:00"`, `("09:00","11:00") == "09:00 – 11:00"`, y que la
  combinación de turnos con hora no rompa `combinarTurnosConConfig`.
- `activo_efectivo_test.dart` (nuevo): `LocalServicio.activoEfectivo` es `false` si
  cualquiera de los tres es `false`; `true` si los tres lo son; tolera `null`.
- `modo_gestion_test.dart` (nuevo): qué secciones se muestran con
  `(solo_turnos, sin_tramos)` en sus 4 combinaciones, y que `solo_turnos` fuerce
  `sin_tramos` en el payload que se manda a la RPC.
- `dashboard_entidad_test.dart` (nuevo): parseo de la respuesta de la RPC
  (jsonb con `num` como double, listas ausentes, división por cero en el % de activos).

**De widget**
- `test/dropdown_sin_solape_test.dart` (nuevo): monta un formulario con
  `_GeoDropdown` con y sin valor y comprueba con `tester.getRect` que el rect de la
  etiqueta flotante **no se solapa** con el del valor/hint, en 2 anchos (320 y 400 px).

**Manual (checklist de aceptación)**
- Los criterios de aceptación de cada punto (§3), sobre datos reales de la entidad.
- `flutter analyze` sin errores nuevos (`mcp__dart__analyze_files`).
- `flutter test` completo verde.
- Prueba cruzada: desactivar local → mirar la app cliente; reactivar → comprobar
  que vuelve; crear turno con hora → reservarlo desde el cliente.

**Verificación de datos (SQL)**
- `select count(*) from flow.app_dat_locales where activo` antes/después de migrar ⇒
  10 (no cambia nada).
- Tras cada prueba de activo/inactivo, `cliente_home_feed` y
  `cliente_obtener_disponibilidad` por `id_local_servicio` para confirmar el filtro.
- `select * from flow.get_advisors('security')` tras el DDL (el MCP lo expone:
  `mcp__supabase__get_advisors`), para confirmar que no aparece una tabla sin RLS y
  que la política `update ls` desapareció.

---

## 7. Riesgos, decisiones pendientes y fuera de alcance

### Riesgos
| Riesgo | Mitigación |
|---|---|
| El DDL se aplica al proyecto de **producción** (`vsieeihstajlrdvpuooh`) | migraciones aditivas con `default true`; nada cambia de visibilidad al migrar; reversibilidad documentada en cada archivo |
| Cambiar la aridad de `cliente_obtener_servicios` rompe a otra app | `drop` + `create` con defaults; ninguna sobrecarga; se verifica `ventiq_superadmin` (`catalogo_destinos_service`) tras aplicar |
| El modo simple conmuta el servicio al camino "con recursos" | es **requisito** para que los turnos sean reservables (`_ls_tiene_recursos`); se avisa en la UI y se verifica con un local-servicio real |
| `cliente_home_feed` reescrito sobre una copia obsoleta | se parte siempre de `pg_get_functiondef` en vivo |
| `Navigator.pop(context, true)` cambia el flujo en otros llamadores del sheet | `ServicioFormSheet` tiene 1 solo punto de creación y 1 de edición; se revisan ambos |

### Decisiones que necesito de ti antes de tocar la BD
1. **¿Aplico las migraciones 40/41/42 yo por MCP** contra `vsieeihstajlrdvpuooh`, o
   las aplicas tú a mano desde el SQL Editor? (por defecto: **te las dejo listas y
   las aplicas tú**).
2. **¿Elimino la política `"update ls"` de `flow.local_servicio`** (§1.4)? Es una
   escritura abierta a `anon` sobre una tabla que ahora gobierna la visibilidad de
   todo el catálogo. Recomendado: **sí**.
3. **Gráfico**: ¿te vale un gráfico propio sin dependencias nuevas (§2.5), o
   prefieres añadir `fl_chart` (requiere `pub get` con red)?
4. **Modo simple**: ¿"un tramo por turno" (cupo independiente por turno) o "un
   tramo por día" (cupo compartido)? El plan asume **por turno**, que es lo que
   pediste ("un tramo por cada turno que crea el admin").

### Fuera de alcance (lo señalo, no lo toco)
- `ventiq_superadmin` seguirá listando destinos inactivos en patrocinados y
  colecciones salvo que se actualice también allí. Con el filtro por defecto de
  `cliente_obtener_servicios` (§2.2) **queda resuelto solo**, porque ese servicio
  llama al RPC sin parámetros. Se verificará.
- `lib/screens/admin/crear_planificacion_screen.dart` es **código muerto** (no se
  importa desde ningún sitio). No se toca; se propone borrarlo en un PR aparte.
- La `anon key` de release de `ventiq_superadmin` que es `service_role` (plan.md
  §5.b) sigue pendiente y es ajena a este plan, pero conviene recordarlo: mientras
  exista, ninguna política RLS protege de verdad los datos.

---

## 8. Definition of Done

1. ~~Las 10 mejoras implementadas~~ ✅ código hecho y verificado contra la BD real.
2. ~~`flutter analyze` sin errores y `flutter test` verde~~ ✅ 0 errores y 255 tests
   en verde (incluidos `dashboard_entidad_test`, `activo_efectivo_test`,
   `horas_turno_test` y `dropdown_sin_solape_test`).
3. ~~Migraciones 40/41/42 en `docs/flow_schema/migraciones/`, idempotentes y con
   reversibilidad documentada~~ ✅ escritas y **aplicadas por el usuario**.
4. ~~Checklist de aceptación de §3 punto por punto~~ ✅ recorrido a mano: **todo OK**.
5. ⏳ `get_advisors('security')` sin hallazgos nuevos. Único paso abierto (opcional):
   la sesión se quedó sin MCP de Supabase para lanzarlo. Snippet abajo.
6. ~~Este documento actualizado con el estado real al terminar~~ ✅ §0.bis.

### 8.5 Comprobación de seguridad pendiente (1 pegado, 10 segundos)

```sql
-- (a) La política "update ls" ya no debe existir: la 40 la elimina porque dejaba
--     el UPDATE de local_servicio abierto a public/anon.
select policyname, cmd, roles
from pg_policies
where schemaname = 'flow' and tablename = 'local_servicio'
order by policyname;

-- (b) Recordatorio: la 40 debe seguir siendo la única que tocó este permiso.
select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'flow' and table_name = 'local_servicio'
order by grantee, privilege_type;
```

Y en el panel: **Database → Advisors → Security** para el parte completo.

Resultado esperado:

1. En (a) **no** aparece ninguna política llamada `update ls`.
2. Si aparece un `UPDATE` para `anon` o `public` sobre `local_servicio` en (b),
   hay que revisarlo: es exactamente lo que la migración 40 vino a cerrar.