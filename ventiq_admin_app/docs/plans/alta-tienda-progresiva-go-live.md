# Alta de tienda progresiva y Go Live — plan de implementación

## Goal

Al terminar este plan, crear una tienda deja de ser un formulario de 4 pasos que
hay que rellenar entero antes de entrar. El **paso 1 (la cuenta) es lo único
obligatorio**: al terminarlo se crea el usuario y la tienda en estado `borrador`,
y el cliente puede **abandonar en cualquier momento, irse y volver a entrar** con
su contraseña, encontrándose el asistente donde lo dejó.

Dentro de la app, una tienda en borrador ve un **checklist de activación estilo
Stripe**: la lista de lo que le falta para poder vender, con las tareas
**personalizadas según el tipo de negocio declarado** (retail, restaurante con
cocina, servicentro, solo catálogo). Cuando el cliente termina, un botón **Go
Live** hace un preflight, le enseña un **resumen de lo que tiene**, y al aceptar
la tienda pasa a `activa`.

**Non-goals:** no se cambia el esquema de inventario, precios, ventas ni
liquidaciones; no se toca el TPV del vendedor (`ventiq_app`); no se promociona
nada a main (solo se dejan los SQL documentados); no se implementa facturación
de suscripciones ni gestión de mesas en el admin.

## Progress

| Phase | Status |
|---|---|
| 1. Esquema: estado de tienda, tipo de negocio y checklist | done |
| 2. Alta progressive: step 1 crea borrador y se puede reanudar | done |
| 3. Pantalla de activación (checklist por tipo de negocio) | done |
| 4. Go Live: preflight, resumen y activación | done |

Current phase: — · Recommended next: revisión y pase a main

> Executing agent: update this table at the end of your run and note any
> deviation from the plan in one line each, below this block.

### Desviaciones registradas

- **Fase 1: la columna se llama `estado_onboarding`, no `estado`.** El plan
  asumía que `app_dat_tienda.estado` estaba libre; no lo está: guarda el código
  de provincia geográfico (`'16'`, `'04'`, `'02'`) y lo escribe
  `store_registration_service.dart:240`. Con el nombre del plan, el `ADD COLUMN
  IF NOT EXISTS` no habría creado nada y el CHECK habría muerto al validar esas
  filas. En Dart el getter debe llamarse `estadoOnboarding`.
- **Fase 1: añadido trigger `trg_tarea_onboarding_touch`** sobre `updated_at`
  (no estaba en el enunciado) para no depender de que cada cliente lo escriba.
- **Fase 3: la tarea `cobro` mide `tieneVendedorAsignado`, no
  `tieneMetodoPago`.** `app_nom_medio_pago` es un catálogo **global** de 4 filas
  compartidas por todas las tiendas: como gate habría sido un pseudo-requisito
  siempre verdadero. Lo que bloquea vender de verdad es que
  `fn_abrir_turno_tpv` exige `p_id_vendedor` no nulo, es decir, un vendedor
  asignado a la caja. La clave sigue siendo `cobro`.
- **Hallazgo de seguridad preexistente (no se parchea aquí):** `public` tiene
  `ALTER DEFAULT PRIVILEGES` que concede a `authenticated` el privilegio
  `TRUNCATE` sobre toda tabla nueva, y `TRUNCATE` no pasa por RLS. Afecta a
  `app_dat_tarea_onboarding` igual que a `app_dat_trabajadores` o
  `app_dat_tienda`. Revocar solo en la tabla nueva daría falsa seguridad; el
  arreglo es de proyecto (`REVOKE TRUNCATE` sobre `public`). Queda documentado
  en `sql_updates/tienda_onboarding_verificar.sql`.
- **Fase 3 (UI): la vista se separa de la pantalla para poder probarla sin
  red.** `widgets/onboarding_checklist_vista.dart` es presentación pura (no
  importa `onboarding_service`), y `screens/activacion_tienda_screen.dart` solo
  aporta las consultas. Sin esa separación, el humo de UI tendría que
  inicializar Supabase en el test.
- **Fase 3 (UI): la entrada del menú sigue visible con el checklist
  descartado.** `_tiendaEnBorrador()` del drawer mira solo
  `estado_onboarding == 'borrador'`, nunca `onboarding_descartado_en`: la
  entrada es la vía de recuperación exigida por NN/g y Shopify, así que
  ocultarla al descartar la rompería.
- **Fase 3 (UI): el selector de tipo de negocio se abre solo si el tipo es
  nulo.** Con un tipo ya declarado se pinta como texto con «Cambiar», para no
  ocupar media pantalla con 4 tarjetas en cada visita.
- **Fase 4 (SQL): la RPC no deja activar una tienda `suspendida`.** El enunciado
  solo pedía el `UPDATE`. Sin el guard, el Dueño de una tienda suspendida podía
  levantar la suspensión llamando a la RPC: justo el privilegio que una
  suspensión le quiere quitar. Devuelve `42501` y el estado no cambia.
- **Fase 4 (SQL): bug propio encontrado al probar.** `v_faltan := v_faltan ||
  'cobro'` con `text[]` hacía que Postgres resolviera `||` como `text[] ||
  text[]` y fallara con `22P02 malformed array literal: "cobro"`, en vez del
  `22023` con el motivo. Corregido con `array_append(..., ::text)`. Anotado como
  **H14** en `tasks/hallazgos_pruebas_newa.md`. No existe en main: nace corregida.
- **Fase 4 (SQL): un verificador daba falso verde.** El patrón
  `~ E'SET\\s+estado\\s*='` dentro de un E-string dejaba `\s` en `s`, así que
  buscaba `SETs+estados*=` y no podía casar nunca: la comprobación más importante
  (que no se pise la provincia) pasaba por estar rota. Reescrito con
  `[[:space:]]` y con autotest que falla si el patrón deja de morder.
- **Fase 4 (UI): el Go Live es un diálogo, no una ruta.** `main.dart` registra
  `/activacion` pero no `/go-live`: el preflight necesita las tareas ya cargadas
  para explicar qué falta, así que se abre desde el checklist con
  `mostrarGoLive()`. Una ruta suelta tendría que volver a consultarlas.
- **Fase 4 (UI): la RPC devuelve el resumen ANIDADO en la raíz**
  (`{success, resumen: {almacenes: 1, ...}}`), no bajo `data` ni plano. El primer
  `go_live_sheet.dart` leía `resumenInicial['almacenes']` y habría dejado la
  tabla entera en «Sin configurar» tras una activación correcta. Corregido y
  cubierto por test.
- **Fase 4 (UI): el resumen nunca inventa ceros.** Antes de que el servidor
  responda, la tabla se deriva del estado de las tareas: «Configurado» o «Sin
  configurar». Un `0` es una afirmación, y aquí no se ha contado nada.
- **Fase 4 (SQL): `estado_onboarding='activa'` solo se escribe en
  `estado_onboarding`, nunca en `estado`.** El verificador lo comprueba con un
  regex **y** con un autotest del regex: un patrón con `\s` dentro de un
  E-string se degrada a `s` y da un falso verde (no puede casar nunca). Sin el
  autotest, la comprobación más importante del script no valdría nada.
- **Fase 4 (SQL): `v_faltan := v_faltan || 'texto'` falla con `22P02`.** Con un
  literal sin tipo a la derecha, Postgres resuelve `||` como
  `text[] || text[]` e intenta parsear `'cobro'` como literal de array. Se
  detectó al probar en newa y se corrigió con `array_append(...)`. No existe en
  main: la función es nueva.
- **Fase 2: el paso 1 crea el borrador con un nombre provisional.** El asistente
  no pregunta el nombre de la tienda hasta el paso 2, y
  `app_dat_tienda.denominacion` es `NOT NULL`: llamar a la RPC con cadena vacía
  falla con `null value in column "denominacion"`. Se manda `Tienda de <Nombre
  completo>` (o `Mi tienda`) y el paso 2 lo sobrescribe. El precargado ignora ese
  prefijo para no pintarlo como si fuera el nombre real.
- **Fase 2: el paso 1 usa `tipo_rol: 'dueno'`, no `gerente` + `supervisor`.**
  `fn_insertar_trabajador_completo` acepta `dueno` y escribe `app_dat_dueno` **y**
  `app_dat_gerente` en una sola llamada, así que el Dueño queda autorizado también
  para las RPC históricas que miran `app_dat_gerente`. Con `gerente` no se
  escribía `app_dat_dueno` y el login del paso 1 se quedaba sin tienda.
- **Fase 2: en este camino un fallo del Dueño sí aborta.** En
  `registerUserAndCreateStore` el alta sigue aunque el Dueño no se registre. Aquí
  no: sin rol de admin en ninguna tienda, `login_screen.dart:712` lanza
  `NO_ADMIN_PRIVILEGES` y el Dueño no puede ni entrar a completar su tienda. Se
  devuelve error con el detalle y se avisa de que **no** vuelva a crear la tienda.
- **Fase 2: los pasos 2-4 no usan una RPC monolítica nueva.**
  `crear_estructura_tienda` siempre inserta una tienda nueva; llamarla otra vez
  desde el paso 2 habría duplicado la tienda. `completarTiendaBorrador()` añade
  los bloques con las RPC que ya usa el resto del admin
  (`registrar_almacen_completo`, `fn_m01_crear_tpv`,
  `fn_insertar_trabajador_completo`). Se descartó añadir `p_tipo_negocio` a
  `fn_m01_crear_estructura_tienda` —lo que pedía el plan— porque exigía otro
  script SQL y no hacía falta para que el flujo funcione; queda pendiente si se
  quiere que el tipo viaje en el alta.
- **Fase 2: `registrarUsuarioYCrearBorrador()` es un método nuevo del servicio de
  registro, y `registerUserAndCreateStore()` sigue existiendo.** El plan daba a
  entender que se reutilizaría el camino existente; se dejó el viejo intacto para
  no romper a nadie y el nuevo hace solo lo que el paso 1 necesita.
- **Fase 2: la tienda por defecto sin `estado_onboarding` legible cuenta como
  `activa`.** Si la fila no se pudo leer (RLS, error puntual), el login no debe
  encerrar a nadie en un checklist: se cae al comportamiento anterior a esta fase.
  Lo contrario dejaría fuera a quien sí puede vender.
- **Fase 2: el selector de múltiples tiendas no cambia de destino.** Solo se
  propaga `estado_onboarding` en el mapa `userStores`; la decisión
  borrador→`/activacion` se aplica únicamente a la tienda por defecto con una sola
  tienda, que es lo que pedía el encargo. Si un usuario con varias tiendas elige
  una en borrador, sigue entrando al dashboard.
- **Fase 2: el asistente de IA también pasa por el borrador.**
  `_openAiStoreAssistant` llamaba a `_createStore()`, que inserta una tienda
  nueva; con el paso 1 creando ya el borrador, cada alta asistida habría dejado
  dos tiendas. Ahora `_createStore()` crea el borrador si no existe y luego añade
  la estructura con `completarTiendaBorrador()`.
- **Fase 2: los TPV del personal se resuelven por posición, no por id.** En esta
  ruta los TPV se acaban de crear y el cliente no tiene sus ids, así que
  `p_tpv_id` va nulo y `fn_insertar_trabajador_completo` asigna el primero de la
  tienda: en un alta nueva es exactamente la caja que corresponde.



## Decisions & context

Decisiones tomadas con el usuario (2024-11-24), no reabrir sin evidencia nueva:

- **La tienda nace en el step 1 como borrador.** Rechazado «registrar solo la
  cuenta y crear la tienda al final»: el login exige rol de admin en alguna
  tienda (`login_screen.dart:712` lanza `NO_ADMIN_PRIVILEGES`), así que un
  usuario sin tienda no podría entrar. Con el borrador en el step 1, el Dueño ya
  existe y puede volver.
- **Columna declarativa nueva para el tipo de negocio, flags reales intactos.**
  El tipo declarado solo elige qué tareas recomendar. La capacidad real la
  siguen decidiendo `modo_restaurante`, `cocina_activa` y `app_dat_tpv.modo_servicentro`.
  Rechazado «que el tipo active los flags»: crearía una segunda fuente de verdad
  que puede contradecir la configuración.
- **Go Live bloquea solo por 4 esenciales**; el resto son advertencias que no
  impiden publicar. Rechazado «bloquear por todo lo pendiente»: es justo el
  motivo por el que el usuario abandona hoy.

### Hechos verificados en newa (2026-11-24)

No están en el repo; se comprobaron contra la BD y el código:

- **No existe «tipo de tienda»** en el modelo. No hay `tipo_tienda`, `rubro` ni
  `giro` en `public`. Lo que hay son flags: `app_dat_configuracion_tienda.modo_restaurante`
  y `.cocina_activa` (por tienda), `app_dat_tpv.modo_servicentro` (por TPV),
  `app_dat_tienda.only_catalogo` y `.es_prueba`.
- **`app_dat_configuracion_tienda` no se crea al dar de alta la tienda.**
  `crear_estructura_tienda` no la toca; se crea perezosamente al abrir
  Configuración. 3 de 8 tiendas de newa no tienen fila (ids 1, 5, 14).
- **El backend acepta una tienda sin nada.** `crear_estructura_tienda` envuelve
  cada bloque en `IF x IS NOT NULL`, y `tpv_data`/`almacenes_data`/`layouts_data`/
  `personal_data` son todos nullables en `store_registration_service.dart:212-221`.
  El único guardián hoy es `_validateCurrentStep` en el cliente.
- **No hay pantalla de mesas en el admin** y **no existen los salones**: solo
  `app_dat_mesas.zona`, texto libre. Las mesas se crean desde `ventiq_app`.
- **Las cocinas nacen de convertir un almacén** (`app_dat_almacen.es_cocina`).
  `fn_crear_cocina` crea almacén + layout propia. `listarAlmacenesConvertibles`
  descarta los almacenes que abastecen un TPV, así que en una tienda con 1
  almacén y 1 TPV la lista sale vacía y `fn_crear_cocina` falla con
  `ALMACEN_ES_DE_TPV`.
- **Bug de una palabra que hay que arreglar en el paso 2:** el cliente manda
  `codigo` en `_layoutsData` pero la RPC inserta `item_json->>'sku_codigo'`, así
  que `sku_codigo` queda NULL en todas las zonas creadas por el asistente (8 de
  9 layouts de newa lo tienen NULL).
- **Código muerto:** `store_registration_service.getRoles()` y `getLayoutTypes()`
  apuntan a `app_nom_roll` y `app_nom_tipo_layout`, que **no existen**. No se
  llaman desde ningún sitio. Se eliminan en el paso 2.

### Patrones de industria que el plan sigue

De la investigación con fuentes (Stripe, Shopify, Square, GOV.UK, NN/g):

- **Separar guía de permiso** (Stripe): el checklist *guía*; el gate de
  publicación lo decide un cálculo de requisitos, no un contador de tareas.
- **3 condiciones bloquean, 30 guían** (Shopify: plan, dirección, pago).
- **Tres resultados, no dos**: pasa / pasa con advertencias / no pasa (Framer).
- **Rojo solo para errores reales.** Pendiente = azul; completado = negro sin
  fondo; bloqueado = gris con el motivo visible (GOV.UK).
- **El contador es neutro**: «2 de 5 pasos completados», nunca «te faltan 3».
- **El checklist se puede descartar *y* recuperar** (NN/g; Shopify lo exige
  como requisito de plataforma).
- **Guardado por pasos, no formulario de un tirón**: el anti-patrón documentado
  es el límite de 10 minutos de Square que bloquea 3 días al superarse.

### Archivos que hay que leer antes de empezar

- `ventiq_admin_app/lib/screens/store_registration_screen.dart` — el asistente
  (5013 líneas; métodos clave: `_validateCurrentStep`, `_createStore`, `_nextStep`).
- `ventiq_admin_app/lib/services/store_registration_service.dart` — RPC y flujo.
- `ventiq_admin_app/lib/screens/login_screen.dart:700-760` — el gate de roles.
- `ventiq_admin_app/lib/services/permissions_service.dart` — `getUserRolesByStore`.
- `ventiq_admin_app/lib/services/store_config_service.dart` — flags de config.
- `ventiq_admin_app/lib/services/cocina_service.dart:487-570` — flags de cocina.
- `ventiq_admin_app/lib/widgets/admin_drawer.dart:138-147, 369-377` — visibilidad por modo.
- `sql_updates/fn_m01_crear_estructura_tienda_dueno.sql` — el wrapper que ya
  escribe el Dueño (base para el paso 2).
- `ventiq_admin_app/lib/widgets/tutorial_guiado.dart` — piezas reutilizables.

## Execution rule

At the start of each phase, verify this plan against the live repo and any
deviations recorded above. Do not reopen settled decisions without new evidence.
If an assumption is invalidated, update this file and say so.

---

## Phase 1 — Esquema: estado de tienda, tipo de negocio y checklist

**Goal:** la base de datos puede representar una tienda en borrador, su tipo de
negocio declarado y el estado de cada tarea del checklist, y todo el SQL queda
en un script aplicado en newa y documentado para main.

**Build:**

- (nuevo) `sql_updates/tienda_onboarding.sql` — un solo script idempotente con:
  - `ALTER TABLE public.app_dat_tienda ADD COLUMN IF NOT EXISTS estado_onboarding text NOT NULL DEFAULT 'borrador'`
    con `CHECK (estado IN ('borrador','activa','suspendida'))`. **Alternativa
    descartada:** reutilizar `app_suscripciones.estado`; mide la suscripción, no
    si la tienda puede vender.
  - `ADD COLUMN IF NOT EXISTS tipo_negocio text` con
    `CHECK (tipo_negocio IS NULL OR tipo_negocio IN ('retail','restaurante','servicentro','catalogo'))`.
    Declarativa: **no** enciende flags.
  - `ADD COLUMN IF NOT EXISTS activada_en timestamptz`, nullable. Timestamp, no
    booleano, para poder medir cuánto tarda una tienda en activarse.
  - `ADD COLUMN IF NOT EXISTS onboarding_descartado_en timestamptz`, nullable,
    para el «descartar y recuperar» del checklist.
  - Backfill: `UPDATE app_dat_tienda SET estado_onboarding='activa', activada_en=created_at
    WHERE estado_onboarding='borrador'` para las tiendas **ya operativas** (todas las
    actuales salvo las que el usuario marque). Sin este backfill, todas las
    tiendas vivas aparecerían como borrador al desplegar. Va envuelto en un
    `DO $$` que solo ejecuta si la columna se acaba de crear.
  - `CREATE TABLE IF NOT EXISTS public.app_dat_tarea_onboarding` con
    `id, id_tienda, clave text, estado text CHECK IN ('pendiente','completada','omitida'), completada_en, updated_at`
    y `UNIQUE(id_tienda, clave)`.
  - RLS espejo de `app_dat_configuracion_tienda`: SELECT para quien puede leer
    la tienda (`fn_config_tienda_puede_leer`), INSERT/UPDATE/DELETE para
    (`fn_config_tienda_puede_escribir`). Copiar el patrón exacto de las
    políticas `m01_*` ya existentes; no inventar una nueva función de permiso.
  - Verificaciones de solo lectura al final, en el mismo estilo que
    `sql_updates/rol_dueno.sql`.
- (nuevo) `sql_updates/tienda_onboarding_verificar.sql` — comprobaciones sin
  escritura: columnas y CHECKs presentes, tabla con RLS activa, políticas
  listadas, backfill aplicado (0 tiendas `borrador` al desplegar).

**Checklist:**

- [ ] Script escrito y aplicado en newa con el MCP `supabase-debug`
- [ ] Backfill deja las tiendas existentes en `activa`
- [ ] Un `SELECT` de prueba confirma que se puede insertar una tarea y que RLS
      la oculta a un usuario ajeno a la tienda

**Exit criteria:**

- `SELECT column_name FROM information_schema.columns WHERE table_name='app_dat_tienda'`
  incluye `estado`, `tipo_negocio`, `activada_en`, `onboarding_descartado_en`
- `SELECT count(*) FROM app_dat_tienda WHERE estado_onboarding='borrador'` devuelve 0
- `SELECT relrowsecurity FROM pg_class WHERE oid='public.app_dat_tarea_onboarding'::regclass`
  devuelve `true`
- El script queda documentado en `ventiq_admin_app/docs/registro_tienda_dueno_tutorial.md`
  (o doc propio) con la nota de que **pendiente de aplicar en main**

---

## Phase 2 — Alta progresiva: el step 1 crea el borrador y se puede reanudar

**Goal:** terminar el paso 1 crea usuario + tienda en `borrador` y lleva al
checklist; los pasos 2-4 pasan a ser opcionales y reanudables, y abandonar en
cualquier punto no pierde la cuenta.

**Build:**

- `sql_updates/fn_m01_crear_estructura_tienda_dueno.sql` — extender el wrapper
  para que acepte crear la tienda **sin almacenes, TPV, zonas ni personal**
  (ya lo acepta de hecho) y devuelva `estado: 'borrador'`. El wrapper ya existe y
  ya escribe el Dueño; no crear otra RPC. Añadir `p_tipo_negocio` opcional.
- (nuevo) `ventiq_admin_app/lib/services/onboarding_service.dart` —
  - `leerEstadoTienda()` → `({String estado, String? tipoNegocio, DateTime? activadaEn})`
  - `listarTareasPendientes()` → lee `app_dat_tarea_onboarding` + calcula en
    cliente las tareas derivadas (ver fase 3)
  - `guardarTipoNegocio(String tipo)`
  - `marcarTarea(idTienda, clave, estado)`
  - `activarTienda()` → llama a la RPC de la fase 4
  - `descartarOnboarding()` / `restaurarOnboarding()`
- `store_registration_screen.dart`:
  - `_nextStep` del paso 1: tras validar, **crear la tienda en borrador** y
    navegar al checklist (no al paso 2). Un diálogo intermedio con dos salidas:
    «Configurar mi tienda ahora» (va al paso 2) y «Entrar a la app» (va al
    dashboard). Es la decisión del usuario en el momento crítico.
  - El paso 2 pasa a ser opcional: sin `_storeFormKey.validate()` obligatorio,
    pero con validación por campo al rellenar.
  - El paso 3 pierde el bloqueo de «al menos un TPV / almacén / zona / personal».
    Pasa a avisar y permitir continuar.
  - Eliminar `getRoles()` y `getLayoutTypes()` de `store_registration_service.dart`
    (código muerto contra tablas inexistentes).
  - Arreglar la clave `codigo` → `sku_codigo` en `_layoutsData`.
- `login_screen.dart:700-760` — tras autenticar, si la tienda está en `borrador`
  navegar a `/activacion` en vez de `/dashboard`. Si hay varias tiendas, el
  selector existente ya filtra; añadir el estado al mapa de tiendas.
- `main.dart` — registrar `/activacion` y `/go-live`.

**Checklist:**

- [ ] Terminar el step 1 crea la tienda con `estado_onboarding='borrador'` y el Dueño
- [ ] Cerrar la app en el paso 2, volver a entrar con la contraseña, y aterrizar
      en el checklist
- [ ] Una tienda existente (`estado_onboarding='activa'`) sigue entrando al dashboard
- [ ] `flutter analyze` limpio

**Exit criteria:**

- Prueba manual en newa: alta nueva → abandonar en el paso 2 → cerrar sesión →
  entrar de nuevo → aparece el checklist, con la tienda aún en `borrador`
- `flutter test --no-pub test/store_registration_dueno_tutorial_test.dart test/app_compile_test.dart`
  pasa, incluyendo un caso nuevo: «el paso 1 solo crea una tienda en borrador»
- `SELECT estado FROM app_dat_tienda WHERE id = <la recién creada>` devuelve `borrador`

---

## Phase 3 — Pantalla de activación con checklist por tipo de negocio

**Goal:** una tienda en borrador ve una pantalla con lo que le falta para
vender, con las tareas ordenadas y personalizadas según su tipo de negocio, en
tono informativo y descartable.

**Build:**

- (nuevo) `ventiq_admin_app/lib/models/onboarding_tareas.dart` — modelo puro y
  testeable: `TareaOnboarding { clave, titulo, beneficio, obligatoria, estado, motivoBloqueo, ruta }`
  y `construirTareas({required String tipoNegocio, required HechosTienda hechos})`
  que devuelve la lista. `HechosTienda` es un value object con lo que se
  consulta: `tieneAlmacen`, `tieneZona`, `tieneTpv`, `tieneProducto`,
  `tieneMetodoPago`, `tienePersonal`, `tieneCocina`, `tieneMesa`, `modoRestaurante`…
  **Sin widgets dentro**: la lista se puede probar sin Flutter.
- (nuevo) `ventiq_admin_app/lib/screens/activacion_tienda_screen.dart`
  - Cabecera: «Pon tu tienda en marcha», subtítulo que dice el beneficio, y el
    contador neutro «2 de 5 pasos completados».
  - Una fila por tarea con icono, título, beneficio, y estado por color según
    GOV.UK: completada (negro, sin fondo), pendiente (azul), bloqueada (gris,
    sin enlace, con el motivo visible), error (rojo, solo errores reales).
  - Acción primaria única por fila; secundaria solo si hay una alternativa real.
  - Botón «Descartar» (X) y forma de recuperarla desde el menú cuando se
    descarta.
  - Sin modales automáticos al cargar.
- (nuevo) `ventiq_admin_app/lib/widgets/onboarding_tarea_tile.dart` — la fila.
- `admin_drawer.dart` — entrada «Pon en marcha tu tienda» visible mientras el
  estado sea `borrador`, **también cuando el checklist se ha descartado**.
- `dashboard_screen.dart` — si `estadoOnboarding == 'borrador'`, una tarjeta compacta
  arriba con el contador y el acceso, no el dashboard con ceros (hoy
  `_loadMockData` muestra ceros sin avisar: `dashboard_screen.dart:221-294`).

**Tareas por tipo de negocio** (todas derivadas de hechos reales, ninguna marca
casilla a mano):

| Clave | retail | restaurante | servicentro | catalogo | ¿Bloquea el Go Live? |
|---|---|---|---|---|---|
| `almacen` | sí | sí | sí | no | **sí** |
| `zona` | sí | sí | sí | no | no |
| `tpv` | sí | sí | sí | no | **sí** |
| `producto` | sí | sí | sí | sí | **sí** |
| `cobro` | sí | sí | sí | no | **sí** |
| `personal` | sí | sí | sí | no | no |
| `cocina` | — | sí | — | — | no |
| `mesas_restaurante` | — | aviso (se crean en el TPV) | — | — | no |
| `modo_restaurante` | — | sí (activa el flag) | — | — | no |
| `servicentro_tpv` | — | — | sí | — | no |
| `inventario` | sí | sí | sí | — | no |
| `moneda` | sí | sí | sí | sí | no |

Reglas de las tareas condicionales:
- `cocina` solo aparece si `modo_restaurante` ya está activo, y avisa del caso
  real: hace falta un almacén que **no** abastezca a un TPV, o `fn_crear_cocina`
  fallará con `ALMACEN_ES_DE_TPV`. Si la tienda tiene 1 almacén y 1 TPV, la
  tarea debe explicarlo en vez de ofrecer un desplegable vacío.
- `mesas_restaurante` es una tarea informativa, no accionable desde el admin:
  enlaza a las instrucciones de `ventiq_app` porque no hay pantalla de mesas aquí.

**Checklist:**

- [ ] `construirTareas` cubre los 4 tipos y tiene pruebas unitarias sin Flutter
- [ ] Una tienda en borrador sin nada ve las 6 tareas esenciales
- [ ] Cambiar el tipo de negocio cambia las tareas sin tocar los flags
- [ ] Descartar el checklist no borra las tareas ni la entrada del menú

**Exit criteria:**

- `flutter test --no-pub test/onboarding_tareas_test.dart test/app_compile_test.dart`
  pasa, con casos por tipo de negocio y el caso «1 almacén + 1 TPV bloquea cocina»
- Prueba manual: una tienda `borrador` navega, completa `almacen` y el contador
  sube sin recargar
- `flutter analyze` limpio

---

## Phase 4 — Go Live: preflight, resumen y activación

**Goal:** el botón Go Live verifica, enseña un resumen de lo que hay y solo
entonces activa la tienda, con bloqueo exclusivamente por los cuatro esenciales.

**Build:**

- (nuevo) `sql_updates/fn_m01_activar_tienda.sql` — RPC
  `fn_m01_activar_tienda(p_id_tienda bigint)` `SECURITY DEFINER`, con las
  mismas comprobaciones de permiso que `fn_m01_asignar_dueno_por_email`
  (`fn_user_is_dueno` o superadmin), que:
  - valida los 4 esenciales en servidor (**no confiar solo en el cliente**):
    ≥1 almacén, ≥1 TPV, ≥1 producto, ≥1 método de pago configurado;
  - si falta algo, lanza con `ERRCODE='22023'` y devuelve el detalle en el
    mensaje, sin activar;
  - si está todo, `UPDATE app_dat_tienda SET estado_onboarding='activa', activada_en=now()`;
  - devuelve un JSON con el resumen que enseñó el preflight, para que cliente y
    servidor no puedan discrepar.
- (nuevo) `ventiq_admin_app/lib/screens/go_live_sheet.dart` — el preflight:
  - 3 resultados visualmente distintos: listo / con advertencias / bloqueado.
  - Resumen de solo lectura por secciones (tienda, almacenes, cajas, catálogo,
    equipo, modo de negocio), con «Cambiar» por sección en vez de volver al
    asistente.
  - Los campos opcionales vacíos se muestran como «Sin configurar», no se
    esconden (GOV.UK).
  - Si hay bloqueos: el botón de activar deshabilitado y **cada bloqueo con su
    enlace para resolverlo**, no un mensaje genérico.
  - Si solo hay advertencias: se puede activar, con el aviso listado.
- `activacion_tienda_screen.dart` — botón Go Live en la cabecera cuando no hay
  bloqueos; si los hay, el mismo botón abre el preflight mostrando qué falta.
- `onboarding_service.activarTienda()` — llama a la RPC y refresca el estado.

**Checklist:**

- [ ] La RPC rechaza activar sin almacén, sin TPV, sin producto o sin cobro
- [ ] El preflight y la RPC coinciden en el veredicto (misma lista de esenciales)
- [ ] Activar deja `estado_onboarding='activa'` y `activada_en` no nulo
- [ ] Tras activar, el login lleva al dashboard normal

**Exit criteria:**

- Prueba en newa dentro de una transacción revertida: activar una tienda
  incompleta falla con el detalle; completa, pasa y deja `activa`
- `flutter test --no-pub test/go_live_preflight_test.dart test/onboarding_tareas_test.dart test/app_compile_test.dart`
  pasa, con el caso «los 4 esenciales bloquean, las advertencias no»
- `flutter analyze` limpio
- El script de la RPC queda documentado junto a los de la fase 1 como
  **pendiente de aplicar en main**

---

## Open questions

Ninguna bloqueante. Las tres decisiones de alcance ya están tomadas arriba.

Una decisión diferida, que la fase 1 no necesita resolver: **qué pasa con las
8 tiendas actuales de newa**. El backfill las deja `activa` para no romper nada.
Si se quiere medir el checklist con datos reales, hay que elegir a mano 1-2 para
marcarlas `borrador` y probar el flujo con una tienda que ya tiene datos.
