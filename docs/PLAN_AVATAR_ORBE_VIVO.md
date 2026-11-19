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
| 0. Spike de viabilidad (headless resume · feed · coste) | done (resume no viable) |
| 1. Esqueleto modular, tema y presupuesto de CPU | done |
| 2. Panel futurista + asistente de espacios y conversaciones | done |
| 3. Vida autónoma (comportamientos y estados de ánimo) | done |
| 4. Burbujas flotantes + feed en vivo | done |
| 5. Pulido | done · "retomar conversación" bloqueado por la fase 0 |

Current phase: ninguna. Plan cerrado el 2026-11-18 salvo "retomar conversación", que depende de la API del host.

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

### Estado tras la primera tanda de implementación (2026-11-17)

Construido y verificado:

- `lib/Theme.ps1`, `lib/Strings.ps1` + `lib/strings.json`, `lib/Workspaces.ps1`,
  `lib/Panel.ps1`, `lib/Bubbles.ps1`, `lib/Life.ps1`.
- El panel sustituye al `ContextMenu`: cabecera, espacios reales con conteo real, conversaciones
  con título y fecha, caja de tarea, `×`, Esc, cierre al perder foco, cerrojo contra doble
  `Close`, entrada animada y navegación interna por selección.
- La vida autónoma pasa `scripts/test-life.ps1`: gestos distintos, reproducible con semilla, se
  apaga con actividad real y con burbuja en pantalla.
- `scripts/test-panel.ps1` abre y cierra el panel real sin excepciones.
- `run-task.ps1` acepta `-SessionId` y `-OnDone`.

Lo que **no** está verificado todavía, y no debe darse por hecho:

- El clic real sobre una fila (cambiar de espacio, elegir conversación) no se ha ejercitado con
  ratón; solo el render y la apertura de la ventana.
- `dsh headless --session-id` sigue sin probarse en esta máquina (el sandbox no puede escribir
  en `~/.dsh`). Es la fase 0 pendiente.
- No hay medición de CPU después del refactor: `-Bench` no se implementó.
- El feed en vivo de herramientas (burbujas con "Leyendo X") necesita el plugin `@local/dsh-orb-hub`,
  que ya existe (`dsh-plugins/orb-hub`). Las burbujas siguen cubriendo lanzamiento y fin de tarea: el feed en vivo por herramienta de otras sesiones sigue pendiente.

Desviación nueva: el determinismo de la vida se comprueba con `scripts/test-life.ps1` (secuencia
de gestos con semilla) y no con el hash del PNG, como proponía la fase 3. El PNG depende del
reloj real del tick (`$elapsed`), así que dos capturas nunca podían ser idénticas sin congelar
además el render.

### Incidente del arranque automático (2026-11-17)

Síntoma: tras reiniciar el Harness no aparecía ningún orbe, y `launch.vbs` salía con código 0
sin lanzar nada.

Causa: `-HiddenConsole` se pasaba **antes** de `-File`, es decir, como argumento de
`powershell.exe` en vez de como parámetro del script. `powershell.exe` no reconoce ese flag,
arranca, falla y muere con **exit 1** en menos de un segundo. Como `WScript.Shell.Run` con
`bWaitOnReturn = False` no devuelve el código del hijo, el fallo era completamente silencioso.

Arreglo: `-File "<ruta>\widget.ps1" -HiddenConsole`, con los parámetros del script detrás de
`-File`. Verificado con `scripts/verify-launch.ps1`: orbe vivo y ninguna ventana de consola
nueva.

Regla para el futuro: **en `powershell.exe`, todo lo que va antes de `-File` es del motor; todo
lo que va después es del script.** Un parámetro del script en el lado equivocado no da error de
sintaxis: mata el proceso sin decir nada.

### Incidente al ejecutar una tarea (2026-11-17)

Síntoma: al pulsar EJECUTAR en el panel, el orbe desapareció y la tarea no se lanzó. No quedó
ningún archivo de resultado en `%TEMP%`, así que el runner nunca llegó a arrancar.

Lo que había: el lanzamiento vivía dentro del widget, `Show-Bubble` se llamaba justo antes de
crear el proceso, y **no existía ningún log**. Un fallo ahí era indistinguible de un cierre
voluntario.

Lo que se cambió:

- `lib/Log.ps1` — log en `%TEMP%\grok-orb.log`, rotación por tamaño, `Invoke-OrbSafe` y los dos
  cazadores de excepciones (`AppDomain` y `Dispatcher`) con `Handled = $true`: una excepción en
  un evento ya no se lleva el proceso.
- `lib/Tasks.ps1` — el lanzamiento sale del widget y se puede probar sin ventana. El prompt va
  por **variable de entorno** (`-TaskEnv`) en vez de por la línea de comandos: comillas, acentos
  y saltos de línea rompían el `Arguments` de `ProcessStartInfo`.
- El panel marca `$state.Busy` durante el envío: al aparecer la burbuja el panel perdía la
  activación y su `Deactivated` cerraba la ventana **en mitad del manejador que la estaba
  usando**. Ese cierre reentrante es el sospechoso principal del fallo original.
- Un único camino de envío (Enter, botón y pruebas usan el mismo `Submit`).

Verificado: `scripts/test-panel-run.ps1` (panel → submit → callback con prompt, espacio y
carpeta correctos) y `scripts/test-panel-task.ps1` (panel → burbuja creada → proceso lanzado,
sin excepciones). El lanzamiento con un prompt que lleva comillas y acentos pasa
`scripts/test-task-launch.ps1` con el texto intacto.

Lección: `$script:` dentro de un closure de WPF no apunta al script global. El registro de
burbujas se movió a `$global:OrbBubbles` porque la lista que veía `Get-BubbleCount` desde el tick
no era la que llenaba `Show-Bubble` desde un closure de evento.

### El visor de ejecución cambia la fase 4 (2026-11-17)

El plan decía que ver el avance en vivo exigía un plugin host (`@local/dsh-orb-hub`) escuchando
`session/event`. No hace falta para las tareas que lanza el orbe: **`dsh headless --json` ya
emite el flujo** y su contrato está verificado en el código del runtime:

```
{"type":"session","sessionId":…,"cwd":…}
{"type":"status","phase":"turn_start|step_start|step_end|turn_end"}
{"type":"thinking","text":…}      {"type":"text","text":…}
{"type":"tool_call","tool":"read","input":{…}}
{"type":"tool_result","status":"completed|error","result":…}
{"type":"final","text":"respuesta completa"}
```

`run-task.ps1 -JsonOut <ruta>` escribe ese NDJSON en streaming (append por línea, stderr aparte)
y `lib/Tasks.ps1` lo lee por índice de línea cada 400 ms, traduciéndolo a frases ("Leyendo
widget.ps1", "Ejecutando npm test") y a una burbuja por paso (máximo una cada 1,4 s, nunca
repetida). Al terminar guarda `%TEMP%\grok-orb-last-run.json` con prompt, pasos, respuesta y
resultado, que el panel muestra en la sección **Última ejecución**.

Consecuencia para el plan: el hub sigue siendo la vía para ver lo que pasa en sesiones que el
usuario tiene abiertas en la GUI, pero **ya no es requisito** para el visor de tareas. La fase 4
queda a medias de forma distinta a la prevista: el feed de las tareas lanzadas desde el orbe está
hecho; el de las sesiones de la GUI sigue pendiente.

Prueba: `scripts/test-run-viewer.ps1` (eventos → frases → resumen).

### "Retomando hi" y nada más (2026-11-17)

El usuario lanzó una tarea sobre una conversación y solo vio la burbuja "Retomando: hi". Nada más.
El NDJSON dejó la respuesta:

```
{"type":"error","message":"session \"session-session-974f...\" does not exist"}
```

Dos fallos independientes, uno tapando al otro:

1. **Doble prefijo en el id.** 105 de los 320 archivos del projcache se llaman
   `session-<uuid>.json` y el resto `<uuid>.json`. El índice anteponía `session-` a
   `$f.BaseName` sin normalizar, así que un tercio de las conversaciones quedaba con
   `session-session-<uuid>`. El panel las ofrecía igual y `dsh headless --session-id`
   las rechazaba al instante. Arreglo: `$bare = $f.BaseName -replace '^session-',''`.
2. **El visor no leía nada.** El `Add_Tick` del visor usaba variables locales de
   `Invoke-OrbTask` sin `.GetNewClosure()`; al ejecutarse el timer, `$state` y `$done`
   llegaban nulos (`"LiteralPath" ... es nulo`, una vez cada 400 ms). Resultado: aunque el
   NDJSON contenía el error, nadie lo miró. Arreglo: el manejador va con `.GetNewClosure()`
   y todo cuelga de `$state`.

Además: `ConvertTo-OrbRunEvent` no traducía el evento `error`, así que incluso leyéndolo no
se habría mostrado. Ahora produce una burbuja roja con el mensaje, y el visor cierra con
`final` o con `error` sin depender de que el runner escriba su archivo de resultado.

### Lo visual cerrado (2026-11-17)

El usuario pidió aparcar la ejecución de tareas y terminar antes lo visual. Hecho:

- Sección **Orbe** en el panel: chasis y vida (Activa / Dormido / Apagada) en caliente, más
  *Abrir DeepSeek Harness* y *Cerrar el avatar*. Ya no hace falta el menú de Ctrl+clic derecho.
- Navegación con ↑ ↓ entre espacios de trabajo y Esc para cerrar, sin robar las flechas al
  cuadro de tarea cuando tiene el foco.
- La vida **habla**: cada gesto arranca con una frase en burbuja ("Uf…", "Cinco minutos más.",
  "A ver si me muevo.", "¿Eh?"). `Update-Life` devuelve `Say` solo en el frame que inicia el
  gesto y el widget compara con la última para no repetirla.

Pendiente y consciente: la fase 5 (ejecutar y continuar tareas) sigue sin cerrarse. El último
intento registrado en el log es el de las 11:27, **anterior** al arreglo del doble prefijo: el
orbe abierto no había cargado el módulo nuevo. No hay evidencia de un fallo posterior al arreglo
porque no ha habido ejecución nueva.

### El orbe huérfano (2026-11-17)

Síntoma: cerrar DeepSeek Harness no cerraba el orbe; seguía en pantalla.

Causa: era **deliberado**. El orbe se quedaba atenuado para no parpadear en cada recarga de
perfil. El efecto secundario costó tres intentos de depuración: al reabrir el Harness, el plugin
lanzaba otro orbe que **moría en el mutex** `Local\GrokBotOrb`, así que el que seguía en pantalla
era el de antes, con los módulos de antes cargados. Reiniciar el Harness no bastaba, y desde
fuera se veía como "el arreglo no funciona".

Arreglo: si el endpoint de estado deja de responder durante 8 s y el orbe **alguna vez** estuvo
conectado, se cierra. El umbral distingue una recarga de perfil (el servidor sigue vivo, no
dispara) de un cierre real del Harness. Un orbe abierto a mano sin Harness nunca se cierra solo.

Herramienta: `scripts/stop-orb.ps1` cierra el orbe por el título de su ventana, para cuando hay
que cargar código nuevo y el mutex está tomado por una instancia vieja.

### Por qué "no mandaba la tarea" (2026-11-17)

Con el orbe ya limpio y las tareas lanzándose, el log mostró `tarea lanzada, pid=…` y **ningún
NDJSON ni archivo de resultado**. El runner moría antes de hacer nada, por dos motivos propios:

1. **Función usada antes de definirla.** Al instrumentar añadí `Write-RunnerLog ('inicio …')`
   justo después de `$started`, y la definición de `Write-RunnerLog` estaba 10 líneas más abajo.
   PowerShell no iza funciones: el script abortaba en esa línea con `$ErrorActionPreference = 'Stop'`.
   Arreglo: la llamada va después de las definiciones.
2. **stderr de un proceso nativo abortaba el script.** `dsh headless` escribe el razonamiento del
   modelo en stderr; con `2>` redirigido y `ErrorActionPreference = 'Stop'`, PowerShell lo trata
   como error terminante y mata el runner aunque el proceso vaya bien. Arreglo: alrededor de la
   llamada al comando nativo se baja a `Continue` y se restaura en el `finally`.

Añadido además el fallback que el plan ya preveía: si `dsh` responde `session ... does not exist`,
se relanza como conversación nueva en el mismo espacio y se avisa ("No encontré ese hilo; abrí uno
nuevo aquí") en lugar de dejar un error sin salida.

Regla que sale de esto: un script que instrumenta su propio arranque no puede usar herramientas
que se definen después. Y cualquier `.ps1` que invoque un comando nativo debe asumir que ese
comando escribirá en stderr.

### Fase 0 resuelta, y en contra de lo previsto (2026-11-17)

Con el doble prefijo corregido, el runner llegó a `dsh` y este respondió:

```
session "..." runs under agent preset "standard", which the one-shot runner does not compose
```

Medido sobre las conversaciones reales del espacio VentIQ-seller-App: **0 de 8 son adoptables**
(`scripts/check-continuable.ps1`). Todas las conversaciones creadas desde la GUI llevan
`rows.agentPreset` en la proyección, y `dsh headless` no compone presets.

Consecuencia: **"continuar una conversación" no es viable con `headless` en esta instalación.** No
es un bug a arreglar: es un límite del runner one-shot. Lo que sí funciona es lanzar una
conversación nueva en el mismo espacio de trabajo, que es lo que hace ahora el orbe avisando del
motivo. Para continuar de verdad haría falta enviar el mensaje a la sesión viva a través de la API
del host (`dsh-api-session-controller`), que es otro trabajo y no está verificado.

Cambios de esta tanda:

- `Continuable` en el catálogo, leído de `rows.agentPreset`.
- El panel avisa una sola vez bajo el encabezado ("Ninguna se puede retomar…") en vez de marcar
  cada fila, y conserva la fecha.
- `Invoke-OrbTask` comprueba `Continuable` **antes** de lanzar: no gasta 8 s en un rechazo seguro.
- El fallback por error se amplió a `does not compose|preset`, por si alguna sesión se cuela.

Y el bug de "Probar" que no hacía nada: `Force-LifeGesture` recibía `$script:Life.LastMove` como
`NowMs`, que puede ser 0 o viejo, así que el gesto nacía ya expirado. Ahora marca un `Pending` y el
siguiente `Update-Life` lo arranca con el reloj real. Cubierto en `test-life.ps1`.
### Última tanda: vida visible y coste medido (2026-11-17)

El usuario reportó que la vida "se ve como siempre". Diagnóstico: mientras una sesión está en
`working`, `Update-Life` se retira por diseño, y el orbe ya se mueve por la actividad real. Con
todo, era demasiado sutil:

- Gestos cada **11–24 s** (antes 24–52 s) y el primero a los 6 s.
- Deriva de mirada con el doble de recorrido (`driftX` 0.78 + 0.32).
- `waiting` cuenta como ocio: el agente espera al usuario, no trabaja.
- Chip **Probar** en la sección Orbe: `Set-LifeMode 'test'` fuerza un bostezo y un estiramiento.
  Sin él no hay manera de distinguir "no funciona" de "está trabajando y se retira".

Coste medido con `-BenchFrames`, que era lo único pendiente de la fase 1:

```
bench: 200 frames  media 1.71 ms  p95 2.04 ms  583.5 fps
```

La esfera a 160×160 cuesta ~1,7 ms; el gasto real estaba en los efectos WPF que ya no se animan
por frame. `-Bench` se excluye del mutex igual que `-Selftest`, o no correría con un orbe abierto.

Límite conocido: el panel completa mide ~993 px. En una pantalla de 1080p entra; en un portátil de
768p no, y habría que añadir scroll al contenedor entero o recortar secciones.
### Fase 4 cerrada sin plugin host (2026-11-17)

El plan preveía un `@local/dsh-orb-hub` para el feed de las sesiones abiertas en la GUI. No hizo
falta: el endpoint de estado que el orbe ya consulta (`/dsh-grok-buddy/state.json`) trae el
`detail` de la herramienta en curso. El orbe lo traduce con `Get-OrbToolVerbKey` y suelta una
burbuja ("Leyendo", "Ejecutando", "Organizando") cuando cambia la herramienta de la sesión
activa, como máximo una cada 7 s y nunca con el panel abierto.

Queda como límite conocido: se ve **qué tipo** de herramienta, no el archivo ni el comando, porque
ese endpoint no lleva argumentos. Para el detalle exacto hace falta el NDJSON de una tarea lanzada
desde el orbe, o el hub que el plan describe.
Nota operativa: `lib\*.ps1` se cargan al arrancar el orbe, así que un cambio en `lib` exige
reiniciarlo. `run-task.ps1` es un proceso aparte y se relee en cada ejecución.
Regresiones: `scripts/test-session-ids.ps1` (124 conversaciones, 0 ids mal formados) y
`scripts/check-error-event.ps1`. `run-task.ps1` deja ahora marcas `RUNNER` en el mismo
`grok-orb.log`, para saber si llegó a arrancar cuando el resultado no aparece.

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
---

## Cara viva y estados (2026-11-18)

Encargo: que el orbe tenga la vida y las funciones del sistema de avatar de Grok
Bot descrito en `Qwen_markdown_20261117_vgrgz9cuh.md` (§2 y §3 de ese documento).
No se copia código ni datos del original: se copian las **ideas** que se pueden
verificar (catálogo de expresiones, estados con significado propio, parpadeo como
evento, clips con fecha límite, decoración sobre la superficie).

### Lo construido

| Pieza | Qué es |
|---|---|
| `lib/Face.ps1` | 19 expresiones como vectores de 10 canales, springs a 120 Hz, parpadeo de 0,26 s, decoración con dos springs y crossfade, máquina de estados de ánimo |
| `lib/Clip.ps1` | cubic-bezier con overshoot (Newton + respaldo), pistas con clave por tiempo, tres clips de reposo barajados con semilla y continuidad de offset |
| `lib/Orb3D.cs` | el renderizador sale del inline de `widget.ps1`: ahora pinta cejas, párpados, boca con curva y apertura, rubor, brillo y siete decoraciones sobre la superficie |
| `widget.ps1` | tick reescrito: estado de ánimo → cara/deco/aviso; clips de reposo; hover con la acción actual; `dragging`; aviso ámbar de `blocked`; captura a demanda |
| `scripts/test-face.ps1` | 38 comprobaciones sin abrir ventana |
| `scripts/snapshot-orb.ps1` + `capture-orb.ps1` | foto del orbe **vivo** (se rasteriza él mismo) y diagnóstico de la ventana real |
| `scripts/shot-faces.ps1` | hojas de contactos `docs/caras.png` y `docs/estados.png` |

### Estados: los seis del original, más los ecos

`idle · thinking · reading · writing · executing · waiting · blocked · done ·
waking · sleeping · dragging`. `blocked` deja de fundirse con `waiting`: antes el
orbe decía "esperando" cuando en realidad te estaba pidiendo permiso, y ese es
justo el fallo que el original reprochaba a los tres puntos genéricos.

### Desviaciones (a propósito, con motivo)

- **La expresión se mezcla con springs, no con un clip de 0,28 s.** El original
  puede permitirse un morph con fecha límite porque su cara no depende del estado
  del agente en cada frame; aquí la cara cambia por sucesos impredecibles y un
  spring acepta un objetivo nuevo a mitad de camino sin romper la velocidad. El
  through-blink se conserva: cierra, cambia y abre.
- **`waking` dura 0,7 s, no 1,6 s.** En el original `waking` vuelve a `idle`; aquí
  vuelve a trabajar, y 1,6 s de sorpresa se comían la cara de concentración.
- **La decoración se pinta DEBAJO de la cara.** Encima, la línea de barrido
  cruzaba las pupilas y el anillo parecía un monóculo. Se comprobó en capturas.
- **No hay morph de silueta** (círculo → estrella → gota). El cuerpo es una esfera
  con luz fija; deformar el contorno rompe el sombreado que hace que se lea como
  objeto. La personalidad se cambia con el chasis.
- **Los tres puntos y el cursor salen del XAML.** Eran elementos WPF flotando por
  delante del orbe; ahora son decoración de superficie y giran con él.
- Se añade `-MutexName` para poder levantar un orbe de pruebas junto al real.

### Lecciones técnicas (no repetir)

- **`[string]$Param = $null` no queda nulo: PowerShell lo convierte en `''`.**
  `if ($null -ne $Kind)` era cierto siempre y `Update-Deco` reiniciaba la
  decoración en cada frame (amount se quedaba en 0). Comparar contra `''`.
- **PowerShell no distingue mayúsculas en variables.** En la prueba, `$clips = @{}`
  y `$idle = Update-Idle` machacaban `$script:Clips` y `$script:Idle`. En
  `test-face.ps1` se renombraron a `$clipCounts` y `$pose`; en el tick del widget a
  `$faceCh`, `$decoCh`, `$moodNow`, `$idlePose` para que nadie vuelva a caer.
- **`$pid` es automática y de solo lectura.** Usarla como salida de
  `GetWindowThreadProcessId` lanza `SessionStateUnauthorizedAccessException` dentro
  del delegado. La búsqueda de ventana se hace en C#.
- **La ventana del orbe no se puede capturar desde otro proceso.** `PrintWindow`
  devuelve `true` con el bitmap en blanco y `CopyFromScreen` devuelve blanco en una
  sesión sin escritorio accesible. La única foto honesta es que el orbe se
  rasterice a sí mismo (`snapshot-orb.ps1`), y sale con alfa, que es lo que hace
  falta para compararla con `-Selftest`.
- **`Add-Type -Path lib\Orb3D.cs`** funciona y evita 280 líneas de C# dentro del
  `.ps1`; a cambio, `parse-check.ps1` no lo revisa: un error de compilación solo
  aparece al ejecutar.

### Verificado

- `scripts\parse-check.ps1`: 29 archivos, 0 fallos.
- `scripts\test-face.ps1`: 38 comprobaciones en verde.
- `docs\caras.png` (19 expresiones) y `docs\estados.png` (8 estados) renderizados.
- Captura del orbe vivo: PNG + JSON con `activity`, `expression`, `deco`, `yaw`,
  `tilt`, `roll`, `gaze`, `face[10]`, `decoCh[6]` y `clip` (`tmp\live.png`).
- `-BenchFrames 200`: **2,03 ms/frame** de media, p95 2,55 ms (antes 1,71 ms).

### Sin verificar (no darlo por hecho)

- El **hover real con ratón** y el arrastre con la cara de sorpresa: se han probado
  las funciones, no el gesto físico.
- El estado **`blocked` con una aprobación de verdad** delante: se ha comprobado
  con actividad simulada, no con el agente pidiendo permiso.
- El **retiro a los 8 s** tras cerrar el Harness: el `finally` que lo rompía está
  arreglado, pero no se ha reproducido el cierre.
- El coste del render **dentro del proceso real** con la ventana visible (el bench
  mide el render aislado).
### Sin giro axial al trabajar, y movimiento reducido (2026-11-18)

Cambio de producto pedido por el usuario: `executing` ya no hace girar el orbe
sobre su eje. El motivo es técnico, no estético: girando 6°/frame (una vuelta cada
~2 s) la cara se iba al limbo y la mitad del tiempo se veía el dorso con el aro
grabado, justo cuando el orbe tiene algo que contar. Con el sistema de caras eso
pasó de "raro" a "pierde información": **la cara es el estado**.

Lo que hace en su lugar:

- se mece ±2,2° con periodo más corto que en reposo (insistencia, sin perder la
  cara de vista);
- los anillos exteriores tienen **su propio reloj** (antes derivaban del ángulo de
  giro, que ya no avanza, así que se habrían quedado clavados);
- el resto lo cuentan el visor (anillo orbitando) y el pulso del aura.

El giro axial sigue disponible como anulación manual: Ctrl+clic derecho →
*Movimiento* → *Giro axial 3D*.

Añadido también, del §3.11 del documento de referencia ("ingeniería invisible"):
**movimiento reducido**. Con las animaciones de Windows desactivadas
(`SystemParameters.ClientAreaAnimation`), el orbe queda estático: la cara salta al
objetivo sin springs, no parpadea, no respira, no se mece y la decoración se
congela. Queda anotado en el log al arrancar. Cubierto con 4 comprobaciones nuevas
en `test-face.ps1` (42 en total).

Verificado en vivo sobre el orbe instalado: con `activity: executing`, dos
capturas separadas 3 s dan `yaw -2,13°` y `yaw +1,82°`. Antes, en esos 3 s habría
avanzado unos 540°.
### Cierre del plan (2026-11-18)

Estado de las fases, con lo que falta dicho sin adornos:

| Fase | Estado |
|---|---|
| 0. Spike de viabilidad | **cerrada**: `dsh headless --session-id` rechaza las sesiones de la GUI (`assertAdoptable`), medido 0 de 8 adoptables. No es un bug a arreglar: es un límite del runner one-shot |
| 1. Esqueleto, tema y coste | cerrada. `-BenchFrames 200`: 2,03 ms/frame con cara y decoración (antes 1,71 ms sin cara) |
| 2. Panel y asistente | cerrada. Panel verificado con `test-panel.ps1` y captura `docs/panel.png` |
| 3. Vida autónoma | cerrada. `test-life.ps1` en verde y **render determinista** (ver abajo) |
| 4. Burbujas y feed | cerrada para tareas lanzadas desde el orbe; el feed de sesiones de la GUI se limita al `detail` del endpoint de estado (sin argumentos) |
| 5. Pulido | cerrada **salvo "retomar conversación"**, que queda bloqueada por la fase 0 |

### El render ahora es determinista de verdad (criterio de la fase 3)

El plan pedía que dos `-Selftest` con la misma semilla dieran el mismo SHA-256.
No lo cumplía, y el motivo importa: el tick seguía vivo durante la captura.
Cuatro fuentes de azar, cada una arreglada:

1. **La mirada se sorteaba con `Get-Random`** (sin semilla) → las pupilas caían
   distintas en cada ejecución. Con `$script:FrozenMs` puesto, el bloque de mirada
   no se ejecuta y la mirada va a un valor fijo.
2. **La fase de la decoración dependía del reloj real.** El reloj congelado la
   fija (`1600 % 1400`).
3. **Los springs de decoración no habían terminado de asentarse** cuando se
   congelaba: el primer tick congelado metía un paso de decenas de milisegundos y
   movía `amount` una milésima distinta. `Settle-Deco -NowMs` los deja en reposo y
   pone el reloj del integrador al mismo instante.
4. **El parpadeo y el through-blink** dependían de `[DateTime]::Now`. Congelado,
   no se disparan.

Verificado: `thinking`, `idle`, `executing`, `blocked`, `waiting`, `reading` y
`writing` dan **el mismo hash en dos ejecuciones** (7 de 7).

Comprobaciones que acompañan al cierre:

- `check-error-event.ps1`: un fallo del runner produce burbuja legible
  (`kind=error`, "session no existe"), que era el checklist pendiente de la fase 5.
- Regla permanente 4 cumplida: `0` coincidencias de `C:\Users\` en el código.
- Capturas: `docs/caras.png`, `docs/estados.png`, `docs/panel.png`,
  `docs/bubbles.png`, `docs/life.png` (gesto de dormitar).

### Lo que sigue, y no es "más de lo mismo"

El catálogo de 19 expresiones **no es un menú**: en marcha nadie elige la cara. El
orbe la deduce de la actividad del agente y de la vida, y los springs la mezclan.
Lo que falta para que se sienta natural no es otra cara, es:

- **micro-expresiones**: miradas cortas sin motivo, ceja que se mueve una vez,
  medio parpadeo asimétrico (un ojo antes que el otro);
- **asimetría**: hoy las dos mitades de la cara son idénticas y eso es lo que más
  "dibujo" se ve; el original también es simétrico, pero en un ser vivo la
  simetría perfecta delata;
- **respiración facial**: la boca y el párpado con una deriva lenta propia, no
  solo el cuerpo.

Eso es una capa nueva (`lib/Micro.ps1`), no un rediseño: se enchufa al mismo
vector de 10 canales con un sumando pequeño y deja todo lo demás igual.
### Lo que el orbe cuenta mientras trabaja (2026-11-18)

Pedido del usuario, literal: "cuando mando a hacer una tarea se pone a hacerla,
eso sí, pero no lo veo trabajando; que me diga qué está haciendo en todo momento,
flotante, bonito y elegante como burbuja de chat, con voz".

**Tarjeta de progreso** (`lib/Progress.ps1`). Una burbuja dura 2,6 s y se va; si
te ausentas treinta segundos no sabes si la tarea sigue viva. La tarjeta se queda:

- paso actual, cronómetro y punto que late;
- **el texto del modelo se acumula** según llega del NDJSON (es el stream, no un
  resumen), con scroll y tope de 6.000 caracteres;
- **dos tamaños decididos por el estado del Harness**: compacta si está a la vista
  (ya puedes seguir el chat), completa si está minimizado o en la bandeja;
- se retira sola 9 s después de terminar, con su propio `DispatcherTimer` (el
  visor de la tarea deja de leer en cuanto acaba, así que no se puede colgar de él);
- no roba el foco: `WS_EX_NOACTIVATE`.

**Voz** (`lib/Voice.ps1`), sobre el TTS neuronal que el perfil ya tiene. Freno
deliberado: una frase cada 6,5 s, se descarta lo corto y no se encola nada
mientras suena otra. Si el endpoint falla, se apaga sola en vez de reintentar en
cada paso. Interruptor en Ctrl+clic derecho → *Voz al trabajar*.

**Micro-expresiones** (`lib/Micro.ps1`). Un sumando pequeño y continuo sobre el
vector de cara, con tres canales asimétricos (ojo y ceja desiguales, boca
torcida, medio parpadeo), alimentado por dos deriva lentas con periodos primos y
por eventos cada 4-14 s. No es otra capa de expresiones: es lo que evita que una
pose exacta se lea como un dibujo.

### Contratos medidos (no hay que volver a adivinarlos)

- **TTS**: `POST /dsh-tts-api/speak { text, voice }` → `200 application/json`
  `{"url":"/dsh-tts-audio/<id>"}` (1,7 s); el MP3 se descarga de esa url relativa
  (`scripts\probe-tts.ps1`). No devuelve audio directo, aunque el README del
  perfil lo diera a entender.
- **La tarjeta y el visor comparten alcance**: `Invoke-OrbTask` corre en el hilo
  de interfaz del orbe, así que la tarjeta puede ser WPF sin runspaces; la voz no
  (bloquearía el tick), y va en un runspace con `BeginInvoke` + espera máxima.

### Registro de la tarea como conversación del proyecto: NO resuelto, y por qué

El usuario lo pidió dos veces: lo que manda el orbe debería quedar como chat del
proyecto. Lo medido hoy:

- Las 320 proyecciones de `session_projcache` son **todas** `preset=standard`, es
  decir, creadas por la GUI. `dsh headless` **no deja conversación visible**.
- No hay ruta de envío en los plugins instalados (`dsh-grok-buddy` expone estado,
  espacios, ajustes, colores y script; nada de escribir en una sesión).
- La GUI responde **401** sin token, así que no se puede replicar su llamada.
- El host vive dentro de `app.asar` (209 MB); leer su API exige inspeccionar el
  archivo, no basta un `grep`.

Conclusión: hace falta un **plugin de host** propio (`@local/dsh-orb-hub`, que el
plan ya contemplaba) que, usando la API de sesiones del host, cree una
conversación real y le envíe el mensaje; el orbe le hablaría por una ruta HTTP
sin token, como ya hace con `state.json`. Es la única vía que produce un chat de
verdad y no una proyección falsificada a mano. Queda como trabajo siguiente, y no
se implementa a ciegas: primero hay que leer la API del host.

### Lección: una función que devuelve basura

`Invoke-OrbTask` devolvía el `DispatcherTimer` **dentro de un array**, porque
nueve llamadas a `Show-Bubble` no estaban silenciadas y su valor de retorno se
colaba en el flujo de salida de la función. El síntoma no fue un error: fue que
la prueba de punta a punta esperó 120 s a que el visor se parase, porque
`$poll.IsEnabled` sobre un array no es lo que parece. Arreglo: `[void](Show-Bubble ...)`.
Regla: en una función que devuelve un objeto, todo lo que se llame dentro y no
sea el resultado va con `[void]` o asignado.

### Verificado tras esta tanda

- `parse-check`: 38 archivos, 0 fallos.
- `test-face`: 42 en verde · `test-progress`: 10 en verde · `test-voice`: MP3 real
  de 27 KB en 2,7 s · `probe-tts`: contrato documentado.
- `test-task-e2e`: tarea real (prompt "responde solo HUD_OK_2"), 31,9 s, tarjeta
  creada en modo compacto, respuesta correcta y resumen guardado.
- Render determinista con micro-expresiones: mismo hash con la misma semilla.
- `-BenchFrames 200` con micro: 2,42 ms/frame (antes 2,03 sin micro).

Sin verificar: el **modo completo** de la tarjeta (Harness minimizado, que desde
aquí no se puede provocar), el hover y el arrastre con ratón real. El registro de
conversaciones ya no está bloqueado: ver el anexo de conversaciones al final.

---

### Conversaciones: leer, escribir y crear desde el orbe (2026-11-18)

Pedido del usuario, literal: "intenta que pueda leer las secciones (cuando hablo
de secciones me refiero a chat dentro de los workspace) pueda escribir en una
activa con append a lo que ya está, crear nuevas que se reflejen al abrir el
harness".

Esto cierra el pendiente que el plan dejó abierto: **registrar el trabajo como
conversación del proyecto**. Hasta ahora el orbe veía títulos en disco y lanzaba
`dsh headless` en un hilo aparte — trabajo que no quedaba en ningún chat. Ahora
escribe en el chat real.

#### Por qué hacía falta un plugin de host

La GUI del Harness responde **401** sin token y `dsh headless` no deja
conversación visible. Los datos están en `~/.dsh/storages`, pero son de solo
lectura: el log de una sesión es `session.v4.jsonl.zst` y reconstruirlo a mano
significa inventar proyecciones, lo que produce chats vacíos o rotos. La única
vía honesta es la API de sesiones del host, y para eso hace falta un plugin.

`@local/dsh-orb-hub` (nuevo, en `dsh-plugins/orb-hub`) expone cinco rutas
loopback:

| Ruta | Qué hace |
|---|---|
| `GET /dsh-orb-hub/ping.json` | ¿está? + capacidades |
| `GET /dsh-orb-hub/state.json` | Workspaces + conversaciones del activo |
| `GET /dsh-orb-hub/messages.json?id=` | últimos mensajes |
| `POST /dsh-orb-hub/send.json` | anexar a un hilo existente |
| `POST /dsh-orb-hub/create.json` | crear hilo en un Workspace |

Todas usan métodos públicos de `sessionController` (`list`, `projections`,
`events`, `prompt`, `create`) y de `workspaceRegistry` (`list`,
`archivedSessionIds`, `pinnedSessionIds`). No se escribe ni un evento de sesión a
mano.

#### Lo que se midió (no hay que volver a adivinarlo)

- **Crear**: `create` + primer mensaje = **236 ms**; el agente contestó `HUB_OK`,
  el hilo quedó titulado solo («Prueba del orbe HUB_OK») y **adjunto al
  Workspace** (`attachSession`), o sea que sale en la barra lateral como
  cualquier otro.
- **Anexar**: `prompt` = **75–100 ms**, `accepted: true`; la respuesta llega
  después y se lee con `events`.
- **Leer**: `state.json` completo en **309 ms** con 12 espacios y 113 sesiones.
  Antes tardaba **8,6 s** porque pedía las proyecciones de las 240 sesiones
  declaradas; leer el título es una proyección en frío por sesión.
- **Unicode**: «Prueba UTF-8 numero dos: ñ á é í ó ú ¿qué tal?» llega intacto
  (verificado en el log del host, no solo en la respuesta HTTP).
- **Paginación**: `maxMessages: N` devuelve como mucho N mensajes, a veces N-1
  por dónde cae el corte; nunca de más.

#### Decisiones que no son obvias

- **El catálogo se detalla de a un Workspace.** `state.json` devuelve el
  catálogo completo (con `count` por espacio) y los mensajes/títulos **solo del
  Workspace activo**. El panel enseña uno a la vez, así que leer todos era gastar
  8 s para pintar 6 filas.
- **`running`, `blank` y `cwd` vienen del host**, no del disco: es el único sitio
  donde "en curso" significa algo.
- **El disco sigue siendo respaldo.** Sin el plugin, `lib/Workspaces.ps1` hace lo
  de antes: lista, y el cuadro de *Tarea* lanza `dsh headless`. El panel no
  muestra el cuadro de chat ni el botón de crear si no puede cumplirlos.
- **`Continuable` se sigue leyendo del disco** (una sesión con *agent preset*
  explícito no la adopta `dsh headless`). El puente no lo sabe y no debe
  adivinarlo.
- **El faro.** `Get-NetTCPConnection` pide elevación: sin admin responde "Acceso
  denegado" y devuelve vacío, que es lo mismo que "no hay nada escuchando". Eso
  dejaba al orbe en `phase: unknown` (comprobado en `-Selftest`). El plugin
  escribe `%LOCALAPPDATA%\GrokBotOrb\hub.json` con su puerto y el orbe lo lee;
  `netstat -ano` queda como respaldo. De regalo, el estado del agente y la voz
  vuelven a encontrar el servidor: `Find-StateUrl` prueba la base del faro antes
  de escanear puertos.
- **`send` no espera la respuesta.** Es un `prompt` encolado; el orbe relee con
  un temporizador (1,2 s tras enviar, 2,5 s al abrir). Bloquear ahí sería colgar
  la interfaz del orbe durante toda la respuesta del modelo.
- **Los mensajes inyectados se filtran** por `source.kind`: notas de ficheros,
  skills y avisos de cron no son conversación y en una burbuja serían ruido.

#### Un fallo real que salió de este trabajo

`Get-NetTCPConnection` sin elevación. Estaba en `Find-StateUrl` desde el primer
día y solo se notó al probar el puente: el orbe llevaba tiempo leyendo
`phase: unknown` sin quejarse (el estado se atenúa y ya). Ahora se prueba la base
conocida → el faro → `netstat`, y `-Selftest` pasó de `phase: unknown` a
`phase: working`.

Y uno mío, de laboratorio: en `probe-hub.ps1` la variable del bucle se llamaba
`$text` y **pisaba el parámetro `-Text`** (PowerShell no distingue mayúsculas),
así que el mensaje enviado era el último leído, no el escrito. Es la tercera vez
que esta trampa aparece en el proyecto; de ahí el comentario en el archivo.

#### Cómo se comprueba

```powershell
# núcleo del plugin, sin Harness
cd dsh-plugins\orb-hub; node test/run.mjs            # 31 comprobaciones

# vista de conversación + puente vivo
cd dsh-plugins\grok-desktop
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-chat.ps1   # 28
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\probe-hub.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\probe-hub.ps1 -SendTo session-<id> -Text "hola"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\probe-hub.ps1 -NewChatIn <workspaceId> -Text "primer mensaje"

# capturas
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\shot-panel.ps1 -OutFile docs\panel.png
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\shot-chat.ps1  -OutFile docs\chat.png
```

#### Límites que quedan

- El chat del orbe muestra **16 mensajes** y recorta cada uno a 700 caracteres.
- El refresco automático depende del temporizador: si cierras el Harness, no hay
  refresco ni escritura (el puente vive en el host).
- Las rutas no piden token: cualquier proceso del mismo usuario podría escribir.
  Es el mismo trato que `dsh-grok-buddy` y no amplía lo que ya puede hacer un
  proceso local.
- **Reiniciar el orbe** para que cargue `lib/Hub.ps1` y la vista nueva: el orbe
  que estaba en pantalla se lanzó antes de este cambio y no se recarga solo.

---

### La luciérnaga: el punto de estado se suelta y vuela (2026-11-19)

Pedido del usuario, literal: "viste esa bolita que tiene el bot a la izquierda
arriba, quiero que se mueva de vez en cuando a direcciones aleatorias y que el
bot la siga con la vista, todo bien fluido y elegante y relajante, y otras
animaciones relacionadas con esa bolita".

Se preguntó cuál era la bolita (el LED de estado del orbe o el punto de la
cabecera del panel): **es el LED de estado**. Así que el LED deja de ser un punto
fijo y se convierte en una luciérnaga que ronda el avatar.

#### Por qué una ventana aparte

La ventana del orbe mide 92 px y la esfera los ocupa enteros: dentro no hay un
píxel libre donde volar. Agrandar la ventana del orbe habría creado un cuadrado
transparente que **captura clics** alrededor del avatar, que es peor que el
problema. La luciérnaga vive en su propia ventana de 220 px, transparente y
*click-through* (`WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW`, el
mismo truco que las burbujas): se ve y no existe para el ratón.

La ventana es grande y **se mueve el punto dentro, no la ventana**. Mover una
ventana 30 veces por segundo se nota; mover un `Canvas.Left` no.

#### Vuelo

- Muelle sub-amortiguado (k 0,013 paseo / 0,055 flechazo) más un **rizo
  perpendicular** al avance: eso es lo que convierte la recta en un arco. El rizo
  se apaga al llegar al destino, o el punto no se quedaría quieto nunca.
- **Corona de 50–100 px** alrededor del centro, con rebote en los dos bordes: se
  anula la componente radial de la velocidad y se conserva la tangencial, así el
  rebote se lee como un giro. El borde interior es la esfera: una luciérnaga
  cruzando por delante taparía los ojos, que es lo único que no se puede tapar.
- Velocidad con techo (2,6 px/frame paseando, 7,2 en flechazo) para que nunca
  cruce la caja de golpe.
- Cuatro comportamientos: **pasear** (destino cada 1,5–3,8 s en reposo),
  **flechazo** (26 % de los destinos, viaje rápido y corto), **posarse** en el
  borde de la esfera (8 %, 2,6–5,2 s) y **desaparecer** para reaparecer en otro
  sitio (cada 26–52 s).

#### Seguimiento

`Update-OrbFirefly` devuelve la posición normalizada a `[-1,1]` respecto del
centro del orbe, y esa es la que entra en el canal de mirada (que ya tenía su
propio suavizado a 0,16 por frame). La mezcla vive en `Get-FireflyGazeTarget`
para poder probarla: peso **0,92 en reposo** y **0,40 trabajando** (trabajando
manda la cara de concentración, que es información de estado).

Extra: un **flechazo** abre un poco los ojos y sube las cejas durante 0,42 s
(suma aditiva sobre `eyeOpen`/`eyeWide`/`browRaise`), y la cabeza gira hasta 5°
hacia el lado donde está el bicho — seguir con las pupilas un punto que se va al
extremo se lee como ojos saltones.

#### Lo demás que trae

- **Estela** de cinco puntos que se apaga con la velocidad.
- **Pulso** del halo, más rápido cuando el agente pide atención.
- **El color es el estado**: ámbar (necesita tu OK), verde (terminó), acento del
  chasis el resto. El LED de la esfera baja al 34 % de opacidad y queda como el
  zócalo del que salió: un punto tenue que explica de dónde viene el que vuela.
- **Accesibilidad**: con las animaciones del sistema desactivadas se queda quieta
  en su sitio fijo, sin sorpresa. Y en `-Selftest` también, para que la captura
  siga siendo determinista (mismo sha256 en dos pasadas).

#### Un fallo real de la integración

El primer intento pasaba `-Reduced $rm` **antes** de que `$rm` existiera en el
tick (se asigna más abajo, en la sección de respiración). Pasar `$null` a un
parámetro `[bool]` lanza una excepción de enlace, así que **el tick entero
reventaba en cada frame** y el error solo se veía como `ERROR tick fallo (1)` en
el log. Se descubrió porque el selftest dejó de cambiar de hash y la luciérnaga
no se movía. Corregido usando `$script:ReduceMotion` directamente.

#### Recarga sin privilegios

El avatar lo lanza el Harness y, desde una terminal normal, ese proceso **no se
ve ni se puede cerrar** (mismo muro que `Get-NetTCPConnection` sin elevación). Se
añadió un vigilante: si aparece `%LOCALAPPDATA%\GrokBotOrb\reload.now`, el orbe se
cierra solo. `scripts\reload-orb.ps1` escribe el marcador, espera a que el latido
pare y lo relanza con `launch.vbs`. Un orbe anterior a esta versión no lo tiene.

#### Comprobado

```
scripts\test-firefly.ps1      34 comprobaciones (ventana, corona, velocidad,
                              destinos, estela, sorpresa, mirada, accesibilidad)
```

- Coste: **0,6 ms/frame** de los 33 ms de presupuesto.
- `-Selftest` determinista: `4166a409…` en dos pasadas seguidas.
- Orbe real: log `luciernaga: ventana creada en 1356,732`, sin errores de tick.
- `docs/firefly.png`: tres instantes del vuelo, renderizados del canvas real
  (mismos nodos y opacidades). No es captura de pantalla: `CopyFromScreen`
  devuelve negro en este entorno.

#### Sin verificar

- Cómo se ve **en el escritorio real** con el orbe al lado: mi terminal no puede
  capturar la pantalla ni cerrar el proceso vivo, así que la comprobación visual
  final la tiene que hacer el usuario.
- Que el remolino no moleste con el orbe pegado a un borde de la pantalla: la
  ventana de 220 px se sale del área de trabajo y el punto puede quedar
  parcialmente fuera. Está acotado por la corona, pero con el orbe en una esquina
  el vuelo se ve a medias.

#### Segunda vuelta (mismo día): menos nervio y paso por delante

Feedback del usuario, literal: "me gustó como quedó, ta elegante eso, pero se está
moviendo constantemente; que sea cada ratos aleatorios y vuelva a su sitio un rato
aleatorio también. Y que de ser posible no choque contra él sino que le pase por
delante".

El primer diseño volaba sin parar (destino nuevo cada 1,5–3,8 s). Se cambió por
**excursiones con regreso**:

- **Descanso 9–22 s** en su zócalo (donde estaba el LED), quieta del todo.
- **Excursión de 2–3 puntos** con pausas de 0,5–1,6 s entre ellos.
- **Vuelta a casa** siempre, y otro descanso aleatorio.
- Medido en 10 minutos simulados: **un vuelo cada ~20 s**, **5,5 s** de duración,
  **27 % del tiempo fuera** (antes: 100 %).

Y para que **pase por delante** en vez de chocar:

- Se eliminó el tope interior de la corona (era eso lo que se leía como choque:
  rebotaba en el borde de la esfera).
- Al entrar en el disco se agranda hasta un 42 % y brilla más. Sin profundidad
  real, ese cambio de tamaño es lo que hace que se lea "por delante" y no
  "dentro".
- El único tope que queda es el exterior (96 px), para que el orbe no tenga que
  forzar la mirada al máximo.

Y la mirada: **0,92** de excursión, **0,40** trabajando, **0,22** descansando (en
su zócalo ya forma parte del orbe, así que la mirada vuelve a ser la de siempre).

**Dos fallos que salieron de aquí:**

1. **El rizo impedía llegar.** Con el rizo a tope la velocidad gira 13° por frame
   y el punto se queda **orbitando** el destino en vez de alcanzarlo: la excursión
   no terminaba nunca y la luciérnaga no volvía a casa. Se escala el rizo con la
   distancia (`min(1, dist/45)`) y se añadió un tope de 5 s por tramo como red.
2. **`Canvas.Left/Top` no se aplica hasta organizar.** En los scripts de captura
   el punto salía pegado a la esquina (0,0) aunque sus coordenadas fueran
   correctas: `RenderTargetBitmap.Render` de un árbol que no ha pasado por
   `UpdateLayout` usa las posiciones viejas. En el orbe vivo no pasa (la ventana
   organiza cada frame), pero costó un rato verlo.

**Comprobado:** 36 aserciones (`test-firefly.ps1`), `-Selftest` determinista, y en
el orbe real la recarga por marcador funcionó de punta a punta: `reload-orb.ps1`
→ el orbe se cerró solo → `launch.vbs` → nuevo proceso con
`luciernaga: ventana creada` y sin errores de tick (10:30).
