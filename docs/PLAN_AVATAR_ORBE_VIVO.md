# Orbe vivo — plan de implementación

## Goal

Convertir el orbe de escritorio (`dsh-plugins/grok-desktop/widget.ps1`) de un adorno que
reacciona al estado del agente en un **compañero que vive solo**: se mueve, mira, se
aburre, se estira y comenta lo que hace el bot cuando no lo estás usando; con un **panel
propio** en lugar del menú de Windows; con **burbujas de texto flotantes** que cuentan la
actividad sin abrir el Harness; y con un **selector de espacios de trabajo y
conversaciones de DeepSeek** que lanza o continúa un hilo sin diálogos de sistema.

Al terminar: haces clic derecho en el orbe y aparece un panel negro con brillo, cuatro
secciones y animación de entrada; eliges `VentIQ-seller-App`, ves tus conversaciones reales
con su título, eliges una, escribes el prompt y el orbe la continúa en segundo plano
mientras una burbuja te dice "Leyendo `widget.ps1`…" y, al acabar, "Listo: 3 archivos
cambiados". Sin que el Harness esté al frente.

**Non-goals:**
- No se migra a Electron, WebView2 ni a un canvas/shader nuevo. El render 3D se queda en
  la clase C# `Orb3D`.
- No se toca el FAB web (`dsh-plugins/grok-fab`), que está retirado a propósito.
- No se reemplaza el TTS existente (`@memef1f1y/dsh-plugin-tts`); a lo sumo se le pasa el
  texto de la burbuja en una fase final opcional.
- No hay multiusuario, ni sincronización entre máquinas, ni telemetría.
- No se anima con shaders la cara: sigue pintada por píxel sobre la esfera.

---

## Progress

| Phase | Status |
|---|---|
| 0. Spike de viabilidad (headless resume · feed · coste) | in progress |
| 1. Esqueleto modular, tema y presupuesto de CPU | in progress |
| 2. Panel futurista + asistente de espacios y conversaciones | not started |
| 3. Vida autónoma (comportamientos y estados de ánimo) | not started |
| 4. Burbujas flotantes + feed en vivo | not started |
| 5. Continuar conversación end-to-end y pulido | not started |

Current phase: 1 · Recommended next: 1

> Executing agent: update this table at the end of your run and note any
> deviation from the plan in one line each, below this block.
>
> Deviations:
>
> - **Consola visible al arrancar (bug reportado por el usuario).** El orbe corría dentro de un
>   `powershell.exe` con consola propia, hospedada por Windows Terminal: cerrarla mataba el orbe.
>   Arreglado en dos capas: `grok-orb/index.js` lanza por `wscript` + `launch.vbs` (sin `cmd /c
>   start`), y `widget.ps1` acepta `-HiddenConsole` para ocultar su propia consola. Verificado:
>   parse OK, selftest OK, `launch.vbs` exit 0. **No verificado en vivo**: el sandbox del agente
>   ve las ventanas del escritorio pero no puede matar sus procesos, así que el reinicio real del
>   orbe lo tiene que hacer el usuario.
> - **Las conversaciones no se cruzan por `sessionIds`.** El plan decía unir `workspace.json` con
>   el projcache por id. En esta instalación divergen: `VentIQ-seller-App` declara 60 ids y
>   **ninguno** tiene proyección, mientras hay 241 proyecciones con ese `workingDirectory`. El
>   catálogo ahora cruza por ruta normalizada y usa los ids solo como respaldo.
> - **Los datos de espacios y conversaciones se leen del disco desde el widget**, no del hub. El
>   hub sigue siendo necesario para el feed en vivo (fase 4), pero así el panel es verificable sin
>   reiniciar el Harness. Reduce acoplamiento.
> - **`lib/Workspaces.ps1` ya existe** con el índice de conversaciones (316 en 493 ms, lista de 8
>   filas en 70 ms) y `lib/Theme.ps1` con los tokens. El resto de `lib/` sigue pendiente.

---

## Decisions & context

### Lo que existe hoy (leer antes de tocar nada)

- `dsh-plugins/grok-desktop/widget.ps1` — 1051 líneas. Mutex `Local\GrokBotOrb`, ventana
  WPF transparente 92×92, clase C# `Orb3D.Render(byte[] px, int size, yaw, pitch, …)` que
  pinta la esfera por píxel, `DispatcherTimer` a 33 ms, `ContextMenu` WPF estándar,
  `Invoke-QuickTask` con `TextBox` + `FolderBrowserDialog` + `MessageBox`.
- `dsh-plugins/grok-orb/index.js` — solo lanza el widget ~3,5 s después de arrancar el
  Harness. No cambia.
- `dsh-plugins/headless/run-task.ps1` — lanza `dsh headless --patch overlay.yml "<tarea>"`
  con las credenciales de `~/.dsh/.credentials.yaml`. Se extiende, no se reescribe.
- Estado actual: `GET /dsh-grok-buddy/state.json` (plugin `dsh-grok-buddy`, ya instalado en
  el perfil `desktop`). Devuelve `{ ok, now, sessions:[{ phase, reason, detail, … }] }`.
  El widget lo sondea cada 900 ms y deriva `thinking | reading | writing | executing |
  waiting | idle | unknown`.
- Capturas de referencia: `docs/preview.png`, `docs/rotation.png`,
  `docs/orb-actividades.png`.

### Lo que se verificó del runtime (no re-investigar)

- `dsh headless --session-id <id> "<mensaje>"` existe y adopta un hilo persistido
  (`@deepseek-ai/dsh-headless/lib/index.js`, `resolveAgent` → `agents.resume`). Condiciones:
  mismo `cwd` que el hilo grabado, sesión no viva en otro proceso, no subagente, y
  **rechaza sesiones cuyo header/preset no compone el runner one-shot** (`assertAdoptable`).
  Ese último punto es el riesgo que la fase 0 mide.
- El host emite `ctx.on('session/event', (session, event) => …)` con tipos
  `turn/start`, `step/start`, `step/end`, `assistant/message`, `tool/call`, `tool/result`,
  `approval/asked`, `approval/decided`, `question/asked`, `question/answered`, `llm/retry`,
  `turn/end`, `session/title`, `working-directory/change`.
  `tool/call` garantiza `{ callId, name }`; los argumentos **no** están garantizados.
- Los metadatos de conversación viven en
  `~/.dsh/storages/session_projcache/sessions/<uuid>.json` → `record.rows.title.val`,
  `record.rows.workingDirectory.val`, `record.identity.cwd`,
  `record.rows.sessionListMetadata`, `record.rows.todos`, `record.rows.plan`.
  Hay 315 conversaciones y 11 espacios de trabajo.
- Los espacios de trabajo viven en `~/.dsh/storages/workspace.json`:
  `global.workspaceIds`, `global.defaultWorkspaceId`,
  `tables.workspaces.<id> = { path, title, sessionIds, createdAt, updatedAt }`.
- **Los ids de sesión del `workspace.json` llevan prefijo `session-`; los nombres de
  archivo del projcache no.** Normalizar quitando el prefijo antes de cruzar ambas fuentes.
- El DeepSeek Harness escucha en un puerto aleatorio por arranque. El widget ya lo descubre
  listando sockets del proceso (`Find-StateUrl`); reutilizar ese mismo procedimiento.

### Decisiones tomadas

- **Continuar = invisible.** El usuario eligió que una conversación elegida se ejecute en
  segundo plano con `dsh headless --session-id` y que el resultado se cuente en burbujas.
  Si la fase 0 demuestra que esas sesiones no se dejan adoptar (preset), el fallback
  registrado es: lanzar una conversación **nueva** en ese espacio de trabajo y que la
  burbuja lo diga explícitamente ("no pude retomar ese hilo; abrí uno nuevo aquí").
  Rechazado: abrir la GUI y esperar a que el usuario escriba — vuelve a depender del Harness
  al frente, que es justo lo que se quiere eliminar.
- **Vida discreta pero viva.** Sin paseos por la pantalla, sin tapar ventanas, sin
  interrumpir. Como máximo un gesto llamativo cada ~40 s y siempre cancelable desde el panel
  (*Vida: discreta / apagada*). Rechazado "modo mascota": cansa a la semana.
- **UI en WPF, no en WebView2.** Se mantiene un solo proceso, sin dependencias nuevas.
  WPF no tiene `backdrop-filter`; el glass será **simulado** (gradiente + borde luminoso +
  sombra estática). Se acepta a cambio de no reescribir el avatar entero.
- **Cero efectos WPF animados por frame.** `BlurEffect` y `DropShadowEffect` se
  re-rasterizan cada tick: hoy son la mayor parte del ~30 % de núcleo. Los halos se
  pre-renderizan una vez por skin a `RenderTargetBitmap`; lo que se anima después es
  opacidad y transformadas, que son baratas.
- **El lanzamiento de tareas se queda en el widget**, no en el plugin host. El widget es un
  proceso de usuario sin sandbox y ya sabe lanzar procesos; el host solo lee y sirve datos.
- **Un plugin host nuevo**, `@local/dsh-orb-hub`, es la única fuente de datos en vivo.
  Rechazado parchear `dsh-grok-buddy`: es un paquete en `node_modules` y se sobrescribe al
  actualizar.
- **`-Selftest` es la suite de pruebas.** Renderiza a PNG con estado congelado
  (`-HoldSpin`, sin blink, semilla fija), así que dos ejecuciones del mismo ángulo deben dar
  el **mismo SHA-256**. Eso convierte "no rompí el render" en una comparación de hash.

### Contratos nuevos (el agente ejecutor no debe inventarlos)

Endpoints servidos por `@local/dsh-orb-hub`:

```
GET /dsh-orb/feed.json
{
  "ok": true, "version": 1, "now": 1730000000000, "cursor": 128,
  "sessions": [
    { "id": "session-…", "title": "…", "cwd": "C:\\…",
      "phase": "working", "activity": "executing", "tool": "pwsh",
      "updatedAt": 1730000000000 }
  ],
  "events": [
    { "seq": 121, "at": 1730000000000, "sessionId": "session-…",
      "kind": "tool", "tool": "read", "detail": "src/widget/index.js" },
    { "seq": 122, "at": …, "kind": "turn-end", "ok": true },
    { "seq": 123, "at": …, "kind": "title", "detail": "Refactor del orbe" }
  ]
}
```
- `cursor` es el `seq` más alto entregado; el widget pide `?since=<cursor>` para recibir
  solo lo nuevo. Ring buffer de 100 eventos en memoria.
- `kind` ∈ `turn-start | step | tool | tool-error | approval | question | turn-end |
  title | idle`.
- `detail` es opcional y nunca supera 120 caracteres. Si `tool/call` no trae argumentos,
  el evento sale sin `detail` (nunca inventado).

```
GET /dsh-orb/workspaces.json
{ "ok": true, "workspaces": [
    { "id": "a1091a52-…", "title": "VentIQ-seller-App",
      "path": "C:\\Users\\cesar\\Documents\\VentIQ-seller-App",
      "sessions": 19, "updatedAt": 1730000000000 } ] }

GET /dsh-orb/sessions.json?workspaceId=a1091a52-…&limit=30
{ "ok": true, "sessions": [
    { "id": "session-8fc6ff69-…", "title": "Eres desarrollador Flutter senior…",
      "updatedAt": 1730000000000, "status": "idle" } ] }
```
- `title` vacío se sustituye por `"Conversación sin título"` **en el host**, no en la UI.
- Orden: `updatedAt` descendente. `limit` se acota a 100.
- Todos los endpoints son `GET`/`HEAD`. Sin escritura: nada de crear ni borrar sesiones.

---

## Execution rule

At the start of each phase, verify this plan against the live repo and any deviations
recorded above. Do not reopen settled decisions without new evidence. If an assumption is
invalidated, update this file and say so.

Notas técnicas de esta instalación (ya pagadas, no repetir):

- PowerShell es **5.1**. `@($lista)` sobre un `System.Collections.Generic.List[object]` lanza
  `ArgumentException: Los tipos de argumentos no coinciden`. Usar `.ToArray()`, o `@()` solo
  sobre el resultado de un pipeline.
- `Get-Content -Raw` sin `-Encoding` lee en ANSI y rompe acentos en los títulos. Usar
  `[System.IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)`.
- El widget es un proceso de **consola**: cualquier lanzador tiene que pasar `-HiddenConsole`
  y arrancarlo con ventana 0, o queda una ventana de terminal a la vista que además mata el
  orbe al cerrarse.

Reglas permanentes de este trabajo:

1. `-Selftest` debe seguir funcionando en cada fase. Un cambio que rompe el selftest no está
   terminado.
2. Nada de `FolderBrowserDialog` ni `MessageBox` en el código final. Si aparecen, es una
   regresión.
3. Toda animación nueva se anima con `Storyboard`/transformadas, nunca dentro del tick de
   render. Si una fase sube el CPU en reposo por encima del presupuesto de la fase 1, esa
   fase no está terminada.
4. Ninguna ruta absoluta del usuario (`C:\Users\cesar\…`) queda escrita a mano en el código
   nuevo: se resuelven con `$env:USERPROFILE` / `[Environment]::GetFolderPath`.
5. Los textos visibles van en español, sin jerga técnica cuando el dato lo permite:
   "Leyendo `widget.ps1`", no "tool:read".

---

## Phase 0 — Spike de viabilidad

**Goal:** saber, con evidencia, si las tres piezas de las que dependen las fases 2 y 4
funcionan en esta máquina. Se hace primero porque si fallan cambia el diseño.

**Build:**
- (nuevo) `dsh-plugins/grok-desktop/scripts/spike-resume.ps1` — toma un `sessionId` real
  del `workspace.json`, lo normaliza, y ejecuta
  `dsh headless --patch dsh-plugins/headless/overlay.yml --session-id <id> "responde solo: OK"`
  con `-WorkingDirectory` igual al `cwd` grabado. Captura stdout, stderr y código de salida.
  Reporta: `adoptada | rechazada por preset | rechazada por cwd | otro`.
- (nuevo) `dsh-plugins/orb-hub/` — cascarón mínimo del plugin (`package.json`,
  `cordis.patch.yml`, `index.js`) que solo monta `GET /dsh-orb/feed.json` devolviendo
  `{ok:true,version:1,events:[],sessions:[]}` y registra en consola cada `session/event`
  recibido (tipo y nombre de tool) durante 60 s.
- (nuevo) `dsh-plugins/grok-desktop/scripts/bench.ps1` — mide 300 frames del render actual y
  reporta media/p95 de ms por frame y % de un núcleo.

**Checklist:**
- [ ] El spike de resume se ejecuta contra al menos 2 conversaciones reales y deja veredicto
- [ ] El cascarón del hub responde en el puerto del Harness y ve llegar `tool/call` con nombre
- [ ] El bench da una línea base numérica
- [ ] Veredicto y fallback escritos en este plan

**Exit criteria:**
- `powershell -NoProfile -ExecutionPolicy Bypass -File dsh-plugins/grok-desktop/scripts/spike-resume.ps1 -SessionId <id>` termina e imprime un veredicto legible.
- `Invoke-RestMethod http://127.0.0.1:<puerto>/dsh-orb/feed.json` devuelve `ok:true`.
- La tabla de decisiones de este archivo tiene una línea nueva con el resultado real.
- Si el resume falla por preset, la decisión de fallback queda escrita **antes** de seguir.

---

## Phase 1 — Esqueleto modular, tema y presupuesto de CPU

**Goal:** que el mismo orbe, con el mismo aspecto, viva en módulos y cueste mucho menos CPU.
Sin esta base, todo lo demás se construye sobre un proceso al 30 %.

**Build:**
- (nuevo) `dsh-plugins/grok-desktop/lib/Theme.ps1` — un solo `$script:Theme` con tokens:
  `bg0 #05070E`, `bg1 #0A0F1A`, `bg2 #101827`, `line #1C2740`, `text #E6EDF8`,
  `muted #7C89A6`, `accent #38BDF8`, `accent2 #8B5CF6`, `gold #E8C97A`, `ok #34D399`,
  `danger #F87171`; radios 14/10; gap 8/12/18; fuentes `Segoe UI Variable Display` (títulos),
  `Segoe UI Variable Text` (cuerpo), `Bahnschrift` (etiquetas y cifras). Y los helpers
  `Brush`, `Rgb`, `New-Glow`.
- (nuevo) `dsh-plugins/grok-desktop/lib/Orb3D.ps1` — la clase C# extraída **sin cambios de
  comportamiento** (mismos parámetros de `Render`).
- (nuevo) `dsh-plugins/grok-desktop/lib/State.ps1` — `Find-HubUrl`, `Get-OrbFeed`,
  `Get-OrbState` con fallback al endpoint de `dsh-grok-buddy` cuando el hub no está.
- `dsh-plugins/grok-desktop/widget.ps1` — queda como lanzador: mutex, `Add-Type`, dot-source
  de `lib\*`, ventana, tick, input, y los flags `-Selftest`, `-Bench`, `-Seed`,
  `-Panel`, `-Bubbles`.
- Render: `DispatcherTimer` → `CompositionTarget.Rendering` con acumulador a 30 fps fijos.
- Aura/halo: el `BlurEffect` animado desaparece. Se pre-renderiza un PNG del halo por skin y
  tamaño, y se anima solo `Opacity` + `ScaleTransform`.
- (nuevo) `docs/baseline/` — PNG del selftest **antes** del refactor, por skin y por los
  ángulos 0/45/90/180/270, generado en la tarea 0.

**Checklist:**
- [ ] Baseline capturado antes del primer cambio
- [ ] `widget.ps1` bajo 300 líneas y `lib/` con los cuatro módulos
- [ ] Sin `BlurEffect`/`DropShadowEffect` dentro del tick
- [ ] `-Bench` demuestra la mejora contra la línea base de la fase 0

**Exit criteria:**
- `powershell -NoProfile -ExecutionPolicy Bypass -File widget.ps1 -Selftest -Skin grok -SpinDegrees 45 -OutFile docs/after-f45.png` sale 0 y el SHA-256 coincide con `docs/baseline/grok-45.png`.
- `-Bench` reporta **menos de la mitad** de ms/frame que la fase 0, y en reposo el proceso
  no pasa de ~8 % de un núcleo.
- El orbe se ve idéntico en `docs/preview.png` comparado a ojo contra la captura vieja.

---

## Phase 2 — Panel futurista + asistente de espacios y conversaciones

**Goal:** eliminar el menú de Windows y el `FolderBrowserDialog`. Este es el punto que el
usuario llamó "lo más crudo". Aquí también se conecta el cerebro de datos (el hub).

**Build:**
- `dsh-plugins/orb-hub/index.js` — completa los tres endpoints del contrato. Lee
  `~/.dsh/storages/workspace.json` y `~/.dsh/storages/session_projcache/sessions/*.json` con
  `fs`; normaliza el prefijo `session-`; cachea 2 s; nunca escribe.
- (nuevo) `dsh-plugins/grok-desktop/lib/Panel.ps1` — ventana WPF propia:
  - sin borde, `AllowsTransparency`, `ShowInTaskbar=false`, `Topmost`
  - `Border` radio 14, fondo gradiente casi negro al 96 %, borde 1 px con gradiente
    cian→violeta, sombra estática
  - cabecera con nombre del bot, LED de estado y etiqueta de actividad
  - cuatro secciones: **Espacios de trabajo**, **Conversaciones**, **Tarea rápida**,
    **Orbe** (chasis, movimiento, vida, cerrar)
  - filas con hover por `Storyboard` (barra luminosa que se desliza), selección con
    `BorderBrush` acento
  - teclado: ↑↓, Enter, Esc; cierra al perder foco
  - entrada: `Opacity` 0→1, `TranslateY` 8→0, `ScaleX` 0.98→1 en 180 ms con `CubicEase`
- (nuevo) `dsh-plugins/grok-desktop/lib/TaskWizard.ps1` — asistente de dos pasos dentro del
  mismo panel:
  1. elegir espacio de trabajo (título + ruta corta + nº de conversaciones)
  2. elegir **Nueva conversación** o una existente (título, fecha relativa, estado), y
     escribir el prompt en un `TextBox` multilínea estilizado
  - botón **Ejecutar** → `dsh-plugins/headless/run-task.ps1` extendido con `-SessionId`
- `dsh-plugins/headless/run-task.ps1` — añadir `-SessionId` (pasa `--session-id <id>`) y
  `-OnDone <ruta>` para dejar un JSON con el resultado.
- `widget.ps1` — clic derecho abre el panel; desaparece `ContextMenu` y `Invoke-QuickTask`.

**Checklist:**
- [ ] El panel lista los 11 espacios de trabajo reales con su título
- [ ] Elegir uno lista sus conversaciones reales, con título y fecha
- [ ] Lanzar una tarea nueva funciona desde el panel
- [ ] Continuar una conversación funciona, o cae al fallback registrado en fase 0
- [ ] Ni `FolderBrowserDialog` ni `MessageBox` en el árbol
- [ ] Navegable con teclado

**Exit criteria:**
- `widget.ps1 -Selftest -Panel -OutFile docs/menu.png` renderiza el panel y devuelve 0.
- `Invoke-RestMethod http://127.0.0.1:<puerto>/dsh-orb/workspaces.json` devuelve ≥ 10 espacios con `title` y `path` no vacíos.
- `…/dsh-orb/sessions.json?workspaceId=<el de VentIQ-seller-App>` devuelve ≥ 5 conversaciones con `title` legible.
- Prueba manual: clic derecho → espacio → conversación → prompt → "Ejecutar" → la tarea arranca y el panel se cierra sin colgarse.

---

## Phase 3 — Vida autónoma

**Goal:** que el orbe haga cosas cuando nadie lo mira. Aquí está el punto 1 del pedido.

**Build:**
- (nuevo) `dsh-plugins/grok-desktop/lib/Life.ps1` — motor de tres capas:
  - **postura** (siempre): respiración, deriva de 4 px en ~30 s que regresa, giro lento
  - **mirada**: parpadeo, sacudidas oculares, seguimiento del cursor si está a < 400 px
  - **gesto** (evento puntual, presupuesto de uno cada ~40 s): `bostezo`, `estirarse`,
    `nota mental` (icono que aparece y se va), `curiosidad` (mira arriba), `dormitar`
    (tras 5 min sin actividad del agente ni del usuario: ojos entrelazados, respiración
    lenta)
- Modos: `presencia` (default), `dormido`, `apagada`. Selector en el panel.
- Semilla: `$script:Life.rng` con `-Seed` para que una sesión de selftest sea reproducible;
  sin `-Seed` usa el reloj.
- Reacciones a eventos reales: `turn-end` → flash de ojos + gesto corto; `tool` nueva →
  atención; error → ceja.
- Supresión: mientras el panel está abierto o hay una burbuja visible, la vida se pausa. Si
  hay actividad real del agente, la actividad manda sobre la vida.
- `widget.ps1` — `Update-Life` dentro del tick; los modos sustituyen los viejos
  `AutoMode/AxialSpin/Quantum/HeadShake` (que se conservan como override manual).

**Checklist:**
- [ ] Al menos 6 gestos distintos implementados y elegidos por pesos
- [ ] La vida se pausa con panel abierto y con burbuja visible
- [ ] No compite con la actividad real del agente
- [ ] Reproducible con `-Seed`

**Exit criteria:**
- `widget.ps1 -Selftest -DemoActivity idle -Seed 7 -HoldSpin` dos veces seguidas produce el **mismo** PNG (vida determinista).
- `-Selftest -DemoActivity idle -Seed 7 -Frames 120 -OutDir tmp/life` produce 120 frames y un `life.csv` con el gesto activo por frame; se puede leer que hay ≥ 6 gestos distintos.
- Prueba manual de 3 minutos sin tocar nada: el orbe se mueve, no se queda congelado y no tapa ninguna ventana.

---

## Phase 4 — Burbujas flotantes + feed en vivo

**Goal:** que el orbe cuente lo que pasa, sin abrir el Harness.

**Build:**
- (nuevo) `dsh-plugins/grok-desktop/lib/Bubbles.ps1`:
  - ventana WPF `Topmost`, `ShowActivated=false`, `WS_EX_NOACTIVATE` +
    `WS_EX_TRANSPARENT` (click-through): nunca roba el foco ni el clic
  - placa redondeada con borde dorado suave, filo luminoso, ornamento de esquina y línea de
    separación fina; tipografía serif para el nombre del hablante y sans para el cuerpo
  - entrada `Opacity` 0→1 + `Scale` 0.92→1 + `TranslateY` 10→0 en 220 ms; salida en 160 ms
  - cola apuntando al orbe; posición relativa que se voltea si se sale de pantalla
  - máximo 3 apiladas, FIFO, autocierre 4–6 s según longitud; hover pausa el cierre
  - texto truncado a 64 caracteres y sin rutas completas
- (nuevo) `dsh-plugins/grok-desktop/lib/Phrases.ps1` — catálogo de frases por
  `{kind, tool}` con 3–5 variantes y tono seco: `read` → "Leyendo `X`",
  `pwsh` → "Ejecutando", `edit` → "Escribiendo en `X`", `turn-end` → "Listo",
  error → "Se atascó en `X`".
- `State.ps1` — `Get-OrbFeed -Since <cursor>` con cache de cursor y reintento silencioso.
- `widget.ps1` — el poll del feed (500 ms) alimenta la cola de burbujas.

**Checklist:**
- [ ] Las burbujas no roban foco (escribir en otra ventana mientras salen)
- [ ] No se solapan con el borde de pantalla ni se cortan
- [ ] Como máximo 3 a la vez
- [ ] El feed usa `since` y no repite eventos
- [ ] Con el Harness cerrado no aparece nada y el orbe no falla

**Exit criteria:**
- `widget.ps1 -Selftest -Bubbles -OutFile docs/bubbles.png` renderiza tres burbujas de
  ejemplo (`Leyendo widget.ps1`, `Ejecutando pruebas`, `Listo: 3 archivos cambiados`) y sale 0.
- Prueba manual: lanzar una tarea desde el panel y comprobar que aparecen ≥ 3 burbujas con
  la actividad real y una final al terminar.
- `Compare-Process`: el proceso del orbe no gana más de ~2 % de núcleo con una burbuja visible.

---

## Phase 5 — Continuar conversación end-to-end y pulido

**Goal:** el flujo completo del punto 4, cerrado y sin sorpresas.

**Build:**
- `TaskWizard.ps1` — al elegir una conversación existente, pasar `-SessionId` al runner y
  mostrar en la burbuja de confirmación el título del hilo, no una ruta.
- `run-task.ps1` — `-OnDone` escribe `{ ok, exitCode, sessionId, cwd, durationMs, tail }`;
  el widget lo lee y emite la burbuja final ("Terminó correctamente" / "Falló: <motivo>").
- Fallback de preset, si la fase 0 lo confirmó: reintentar como conversación nueva en el
  mismo espacio de trabajo y decirlo en la burbuja.
- README de `grok-desktop` actualizado: gestos, panel, burbujas, cómo apagar la vida, cómo
  desinstalar el hub.
- `docs/` — capturas finales `docs/menu.png`, `docs/bubbles.png`, `docs/life.png`.

**Checklist:**
- [ ] Una conversación existente se continúa y el resultado llega en burbuja
- [ ] Un fallo del runner produce una burbuja de error legible, no un silencio
- [ ] El README describe lo que hay, no lo que había
- [ ] Nada de rutas absolutas hardcodeadas

**Exit criteria:**
- Flujo manual completo: clic derecho → `VentIQ-seller-App` → una conversación de la lista →
  "resume el estado del repo" → la burbuja confirma → pasan los minutos → llega una burbuja
  con el resultado → el panel muestra esa conversación primero en la lista.
- `dsh headless` no deja procesos huérfanos: `Get-Process` tras el flujo no muestra
  intérpretes extra colgados.
- Este plan queda con todas las fases en `done` y las desviaciones anotadas.

---

## Open questions

Ninguna bloqueante. Las dos decisiones de producto que había quedaron cerradas:
continuar se ejecuta invisible y la vida es discreta. Si la fase 0 demuestra que las
sesiones de la GUI no se dejan adoptar, el fallback ya está decidido arriba y no requiere
volver a preguntar.