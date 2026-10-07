# Execution Monitor — plugin de DSH

Panel en vivo del progreso de ejecución de la sesión, dentro de la GUI de DeepSeek Harness.
Muestra **por dónde va la ejecución**, **qué ha hecho**, **qué ha fallado**, **% de completado**
y varios gráficos, todo con los tokens de tema del anfitrión (claro/oscuro) y sin dependencias.

## Qué añade a la interfaz

| Dónde | Qué es |
|---|---|
| **Widget flotante de ejecución** (columna derecha, siempre visible) | Arrastrable por la cabecera y plegable a una píldora. Muestra estado, `%`, turno/paso, tiempo, chips de herramientas/fallos/tokens, mini-cronología de las últimas 24 llamadas, el **checklist del plan**, los **avisos de lo saltado** y los últimos fallos. Recuerda posición y plegado por navegador. |
| **Widget flotante de Supabase MCP** (columna izquierda, siempre visible) | Arrastrable y plegable igual. Lista **todas las llamadas al MCP de Supabase** de la sesión, con el **código de estado**, si son **lectura o escritura**, la herramienta, la SQL y la duración. Al hacer clic en una fila se despliega el detalle: **SQL completa, estado, turno/paso, duración y la respuesta formateada** (tabla si son filas, JSON si es un objeto, texto si no). Un botón filtra a **solo lectura**. |
| Pestaña **Monitor** en la cabecera de la conversación (junto a *Chat* y *Trajectory*) | La pantalla completa: anillo de % completado, tarjetas de KPIs, reparto de resultados, cronología de herramientas, gráfico de tokens, **plan y avisos**, tabla de actividad y tabla de fallos. |
| ~~Franja compacta en la barra inferior~~ (**desactivada**) | El código sigue en `client.js` y sigue cubierto por las pruebas, pero **ya no se registra**: el widget flotante ya muestra esos números. Para recuperarla, pon `SHOW_COMPOSER_STRIP = true` al principio del módulo. |

### El widget de Supabase MCP

Lee el mismo *Trajectory* de la sesión y se queda con las llamadas cuyo nombre de herramienta
pertenece al servidor MCP (`mcp__supabase__*`: `execute_sql`, `list_tables`, `query_logs`,
`get_advisors`, `list_migrations`, `search_docs`…). El resto de herramientas no aparece.

- **Lectura o escritura**: se decide por la SQL cuando la llamada lleva una
  (`select`/`with`/`table`/`show`/`explain`… = lectura; `insert`/`update`/`delete`/`create`/`alter`/… = escritura)
  y, si no la lleva, por la herramienta (`list_*`, `get_*`, `search_*`, `generate_*` = lectura).
- **Código de estado**: el MCP no devuelve una línea HTTP, así que el widget usa
  `meta.statusCode` si la herramienta lo aporta y, si no, **lo deriva** del resultado:
  `200` cuando la llamada termina bien; en un fallo, el código se deduce del SQLSTATE o del
  código PostgREST que aparezca en el mensaje (`42501` → 403, `42xxx` → 400, `23xxx`/`40xxx` → 409,
  `PGRST116` → 404, `53xxx` → 503, `57014` → 499, resto → 500) y, si el mensaje no trae código,
  de su propio texto (interrumpido/cancelado → 499, timeout → 504, permisos → 403, no existe → 404).
  El detalle muestra siempre el código derivado y el motivo en crudo, y la cabecera lo dice:
  *"los códigos de estado se derivan del resultado del MCP"*.
- **Respuesta formateada**: si el texto es un array de objetos JSON (lo normal en
  `execute_sql`) se pinta como tabla; si es un objeto con **un solo** array de objetos dentro
  (como `{"buckets":[…]}` o `{"tables":[…]}`) se desenvuelve ese array y también se pinta como
  tabla, indicando de qué clave salió; si es cualquier otro objeto, como JSON indentado; si no
  es JSON, como texto. La tabla muestra hasta 8 filas × 6 columnas más el total de filas, y los
  errores se pintan en rojo.

### El plan: hecho, saltado y por hacer

El checklist se alimenta de la proyección `todos` de la sesión (la misma lista que produce la
herramienta de tareas del agente), y cada fila tiene su estado visual:

| Estado | Cómo se ve |
|---|---|
| Hecho (`completed`) | ✓ y texto **tachado** en gris |
| En curso (`in_progress`) | ● en azul |
| Por hacer (`pending`) | ○ y texto atenuado: lo que falta por llenar |
| **Saltado** | ⚠ en ámbar y **tachado**: un elemento que salió del plan sin completarse |

Como el plan se reescribe entero en cada turno, el plugin guarda en memoria propia los
elementos que desaparecen **sin estar completados**: esos son los avisos de "saltado". Si el
agente vuelve a añadir el elemento al plan, deja de aparecer como saltado. Es memoria derivada
del plugin (la sesión sigue siendo la única fuente de verdad) y se limita a los últimos 30
elementos por sesión.

Las filas exponen su estado a lectores de pantalla, y cada barra/gráfico lleva su `aria-label`.

## Qué mide

Todo se deriva del *Trajectory* de la sesión (el mismo dato que alimenta la pestaña
*Trajectory*), leído por los props estándar que el Harness entrega a los slots de sesión
(`useTrajectory`, `useSessionStatus`, `useSession`, `sessionId`) más el asiento de locale `t`.

- **% completado** = llamadas a herramientas terminadas (OK + fallidas) ÷ total de llamadas
  detectadas. Mientras hay llamadas en curso el porcentaje baja, y con la sesión parada llega a 100 %.
- **Fallos** = resultados de herramienta con `isError`/`error` más peticiones al modelo en estado `error`, con su mensaje.
- **Tokens** = suma de `usage` de las respuestas del asistente (entrada/salida); la chispa dibuja los tokens de salida por respuesta.
- **Cronología** = una barra por llamada; la altura es la duración y el color el resultado.
- **Turno / paso** = el mayor turno y paso vistos en nodos y peticiones.

No existe un porcentaje "oficial" en el Harness: el denominador lo define este plugin y se
documenta en la propia tarjeta (*Completion*), para que el número no se malinterprete.

## Instalación

El plugin es un *bundle* local del perfil `desktop`. Quedó instalado con el script
[`../install-execution-monitor.ps1`](../install-execution-monitor.ps1), que hace lo mismo que
el gestor de plugins: enlaza el paquete en `node_modules` del perfil, lo añade a
`dsh.profile.bundles` y respalda antes `package.json`, `pnpm-lock.yaml` y `cordis.patch.yml`
en `../.install-backup/`.

```
pwsh -ExecutionPolicy Bypass -File install-execution-monitor.ps1            # instalar
pwsh -ExecutionPolicy Bypass -File install-execution-monitor.ps1 -Uninstall # quitar
```

Estado instalado (comprobado):

- `C:\Users\cesar\.dsh\profiles\desktop\node_modules\@local\dsh-execution-monitor`
  → enlace simbólico a esta carpeta.
- `dependencies["@local/dsh-execution-monitor"] = link:...`
- `dsh.profile.bundles` termina en `@local/dsh-execution-monitor`.

Tras instalar, **recarga la página** de la GUI: el módulo de cliente se sirve en el arranque
del navegador. Si el panel no aparece tras recargar, reinicia la aplicación DeepSeek Harness
(el host recompone el perfil al arrancar).

Alternativa sin scripts: la página **Plugins** de la barra lateral acepta la ruta absoluta de
esta carpeta como origen y hace la misma instalación desde la propia aplicación.

Para desactivarlo sin desinstalar: la página **Plugins** permite deshabilitar el bundle o la
fila `execution-monitor`; el efecto es inmediato y sobrevive a reinicios.

## Estructura

```
execution-monitor/
  package.json        manifiesto: exports "./client", dsh.bundle.patch, dsh.client
  cordis.patch.yml    inserta la fila del plugin en el perfil
  index.js            mitad Host (vacía: el plugin es solo de cliente)
  client.js           módulo de navegador: registro de slots, datos, componentes, estilos
  icon.svg            icono de la tarjeta en el gestor de plugins
  locale/en.json      título y descripción para el gestor
  locale/zh.json
  test/smoke.mjs      pruebas de activación, derivación y render
```

El módulo de cliente es JavaScript plano: no compila, no importa ningún paquete de cliente
del Harness (solo `react` de la tabla de módulos), registra sus estilos como elementos
`<style>` del propio componente y libera todo con `ctx.effect` / `ctx.slots.inject`.

Registra **tres** superficies, todas en `client.js` y fáciles de quitar por separado:
`conversation.view` (pantalla **Monitor**), `shell.overlay` → `execution-monitor-widget`
(widget flotante de ejecución) y `shell.overlay` → `execution-monitor-supabase` (widget flotante
de Supabase MCP). La cuarta, la franja del compositor (`conversation.composer.dock`), está en el
código pero **no se registra** mientras `SHOW_COMPOSER_STRIP` sea `false`; el módulo exporta los
componentes (`MonitorView`, `MonitorStrip`, `MonitorWidget`, `SupabaseWidget`) para que las
pruebas puedan renderizar también las superficies no registradas. Los widgets viven en una capa
de ámbito *root*, así que no reciben props de sesión: siguen el binding principal de `uiSession`
y leen de ahí los mismos hooks (`trajectory`, `projection('todos')`) que reciben los slots de
sesión. Los dos comparten el marco flotante (`FloatingFrame`) y se colocan en columnas distintas
para no taparse; cada uno recuerda su posición y su plegado bajo su propia clave de `localStorage`.

Los textos pasan por el servicio de locale con el namespace `executionMonitor` (`en` + `zh`
obligatorios). El plugin además declara un pack opcional de **español**: si eliges *Español*
en Ajustes → General, este panel aparece en español (el resto de la interfaz cae a inglés por
la cadena de respaldo). Si prefieres que no aparezca ese idioma, borra el bloque
`addLanguage` de `client.js`.

## Pruebas

```
node test/smoke.mjs
```

Evalúa el `client.js` real con un React mínimo, ejecuta la activación contra un contexto
falso y renderiza ambos slots con trayectorias sintéticas (en curso, terminada, con fallos,
vacía y sin proveedores). Falla si algún texto del panel no existe en los diccionarios.
