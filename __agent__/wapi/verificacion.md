# Verificación independiente — `wapi-send-products` (task-4)

**Verificador:** `verificador` (independiente del autor). **Fecha:** 2026-10-23.
**Revisión auditada (congelada y hasheada):**

| Archivo | SHA256 | Líneas |
|---|---|---|
| `ventiq_admin_app/supabase/functions/wapi-send-products/index.ts` | `814A93D14D04D4DE6F4651360E99F679388BE5C0F70B21283D119FEF4EB7F58C` | 2320 |
| `ventiq_admin_app/supabase/functions/_shared/wapi_client.ts` | `75C9623D385205F02A2FC020AC7C09224C59A40872CB796DE58D8C399F936E96` | 562 |

> Nota metodológica: el archivo cambió **dos veces mientras lo leía** (2303 → 2307 → 2320 líneas). Congelé un snapshot en `__agent__/wapi/verify/snapshot/` y verifico ESE hash; el lead confirmó después que `814A93D1…` es la revisión final y que no habrá más ediciones. **Todas las citas de línea son de esa revisión.**

**Método:** lectura completa del motor de envío + arnés de simulación que **extrae bloques verbatim del código real** (bucle principal L1856+, cierre L1971+, `registrarPendientesPares` L1118+, reconstrucción de reanudación L883+, `chatsValidos` L987+, construcción del `plan` L1030+) y los ejecuta con mocks de Supabase/WAPI. No es una reimplementación: el builder falla si el SHA256 no coincide.

```powershell
node __agent__/wapi/verify/build_harness.mjs
# harness.mts generado. hash=814A93D14D04D4DE6F4651360E99F679388BE5C0F70B21283D119FEF4EB7F58C
#   chatsValidos=L987 resume=L883 plan=L1030 registrar=L1118 bucle=L1856 cierre=L1971
node --experimental-strip-types __agent__/wapi/verify/harness.mts
```

---

## 1. Puerta de sintaxis — **OK** (tipos NO verificados)

```powershell
node --experimental-strip-types --experimental-vm-modules __agent__/wapi/check_ts.mjs `
  ventiq_admin_app/supabase/functions/wapi-send-products/index.ts `
  ventiq_admin_app/supabase/functions/_shared/wapi_client.ts
```
```
OK    ventiq_admin_app/supabase/functions/wapi-send-products/index.ts
OK    ventiq_admin_app/supabase/functions/_shared/wapi_client.ts

Sintaxis OK (los tipos NO se validan con esto).
EXIT=0
```
Ejecutado sobre la revisión final (hashes impresos en la misma corrida: `814A93D1…` / `75C9623D…`). **Los tipos NO están verificados**: no hay `deno` ni `tsc` en la máquina y la puerta solo valida sintaxis como módulo. Cualquier error de tipos (`Promise` no resuelto, `any` implícito, propiedad inexistente) pasaría esta puerta sin ser detectado. Ver «Lo que NO pude verificar».

---

## 2. Invariante de no-pérdida — **FALLA (formal) / sin pérdida material**

El enunciado «todo `Par` del `plan` acaba despachado, en `remainingPares` o en `saltadosPares`» **es falso**: hay dos rutas `continue` que no meten el par en ninguno de los tres conjuntos.

- **L1895** `if (descartados.has(par.idProducto)) continue;`
- **L1907** `if (!listo || !listo.chats.includes(par.chatId)) continue;` (rama `!listo`)

Evidencia (arnés, escenario E7 = producto 2 descartado, 3 productos × 2 destinos):

```
E7 producto 2 descartado   plan= 6 llam= 4 ok= 4 fall= 2 pend= 0 rem= 0 salt= 0 mov=0 cont= 0 filas= 6
                           sinBucket=2|111@g.us,2|222@g.us perdidos=0 dup=0 enum=ok
```

`sinBucket=2` confirma la fuga formal. **No hay pérdida material** porque la compensación existe y es correcta: `descartar()` (L1362-1381) registra las filas de ese producto y las marca `fallido` + `SKIPPED` (`perdidos=0` → ambos pares tienen fila). El invariante correcto es de 4 vías:

> despachado ∪ `remainingPares` ∪ `saltadosPares` ∪ **fila cerrada como `fallido`**

Otras rutas que SÍ cierran bien (verificadas con el arnés, `sinBucket=0` en todos los demás escenarios):
- corte por presupuesto → `remainingPares = plan.slice(cursor)` (L1878) — E2: `rem=5`, `cont=5`.
- destino saltado → `saltadosPares.push` (L1891) — E3: `salt=2`, filas `pendiente`.
- `sessionDown` → `remainingPares = plan.slice(cursor+1)` (L1932) e `límite` del par actual queda `pendiente` por `prepararProducto` — E4: `rem=2`, `pend=3` (2 remaining + el par que rompió).
- `pacing` → igual (L1937) — E5 idéntico.
- indeterminado → fila `pendiente`, sigue el bucle — E6: `pend=1`, `sinBucket=0`.

### 2.b Fuga real: cuando el INSERT del log falla (escenario E10)

`prepararProducto` ignora el error del insert (L1457-1464: solo `console.error`) y `registrarPendientesPares` **se traga el error del insert en un `try/catch`** (L1138-1160) devolviendo `[]`. Consecuencia en cadena:

```
E10 dup + insert DB falla   plan= 8 llam= 6 ok= 0 fall= 0 pend= 0 rem= 2 salt= 0 mov=0 cont= 0
                            filas= 0  sinBucket=0  idem=0/0(sinLog=6)
```

- 6 mensajes se despachan **sin cabecera `Idempotency-Key`** (`sinLog=6`: `logId` es `null`), así que un reintento tras `TIMEOUT` puede duplicar el mensaje.
- `filas=0`: ningún mensaje queda registrado → el historial no lo ve y el botón «reanudar» no puede recuperarlo.
- `cont=0`: `reinvokeRemaining([])` sale por `if (logIds.length === 0 …) return false;` **sin imprimir el `CADENA ROTA`** que sí aparece cuando el encolado falla con ids. La cadena se rompe en silencio y la respuesta 200 `queued` ya se había enviado al cliente.

**Arreglo mínimo sugerido:** en `registrarPendientesPares`, si el insert falla, no devolver `[]` en silencio: propagar el error (o devolver un flag) para que el cierre llame a `reinvokeRemaining` con los ids que sí existan y, si no hay ninguno, registre `CADENA ROTA` explícitamente. Y en `prepararProducto`, si el insert falla, abortar el chunk (mejor un chunk perdido y reanudable que 8 mensajes sin trazabilidad).

### 2.c El bloque nuevo `deDestinoSaltado` (L1971-1979) es **código muerto** (no rompe nada)

El lead pidió contradecirle justo aquí. Búsqueda exhaustiva sobre el bucle y el cierre extraídos verbatim (planes de 1×1 a 3×3 pares, alfabeto `ok/fallo/pendiente` más una ruptura `sessionDown|pacing` en cada posición, y 4 puntos de corte por presupuesto):

```
=== BÚSQUEDA EXHAUSTIVA deDestinoSaltado>0 ===
ejecuciones=10656  conMovimientoNoVacio=0
```

No es alcanzable, y la razón es estructural: `plan` es destino-mayor, así que cuando `fallosDelDestino >= DESTINO_FALLOS_MAX` **todos** los pares restantes de ese destino ya caen en `saltadosPares` (L1889-1893) mientras el bucle recorre ese destino, y ningún `break` puede ocurrir dentro de un destino ya saltado porque saltar no llama a `dispatchOne` (y solo `dispatchOne` produce `sessionDown`/`pacing`). Por tanto `remainingPares` nunca contiene pares de un destino ya marcado. **El movimiento no deja ningún par sin registrar** (mueve entre dos colecciones que ambas acaban en `registrarPendientesPares`), pero hoy es una defensa que no se ejecuta. No es un defecto; sí conviene saberlo para no confiar en ella como fix.

---

## 3. Invariante de no-duplicado en `app_wapi_envio_log` — **OK por defecto / FALLA con `product_ids` repetidos**

Rutas revisadas (una fila por par en todos los flujos normales):
- `prepararProducto` inserta una vez por producto, protegido por `cacheProductos` (L1491-1499); al reanudar **reutiliza** filas (`logIdPorPar` → update a `pendiente`, L1426-1442).
- `registrarPendientesPares` solo inserta lo que falta en `logIdDePar` (L1120-1126) y mapea de vuelta por `(id_producto, chat_id)`, nunca por posición (L1145-1153).
- Arnés: `dup=0` en E1-E8 y E10; en las cadenas C1-C5 `filasNuevas=0  duplicadas=0` (la reanudación no inserta nada nuevo).

**Pero `handleSendProducts` NO deduplica `product_ids`** (L2096-2099: `.map(Number).filter(isFinite)`, sin `Set`), a diferencia de los destinos, que sí pasan por el `Set` de `chatsValidos` (L987-993). Con `product_ids = [1,2,3,4,4]` el `plan` contiene el par `4|A` dos veces, y si ese destino se salta por fallos, `saltadosPares` acumula el par duplicado y `faltantes` lo inserta dos veces:

```
E9 product_ids dup [1,2,3,4,4]   plan= 5 llam= 3 ok= 0 fall= 3 pend= 2 rem= 0 salt= 2
                                 filas= 5  sinBucket=0  dup=4|111@g.us x2  enum=ok
```

Escenario concreto: 3 fallos consecutivos contra el destino A (que disparan `DESTINO_FALLOS_MAX`, L1889) con `product_ids` conteniendo un duplicado que aún no se había preparado → **dos filas `pendiente` con el mismo `(id_producto, chat_id)`**. El daño colateral es peor que el duplicado: al reanudar, `logIdPorPar` conserva **solo el primer** log del par (L894-898), así que la segunda fila se queda `pendiente` para siempre y la tanda aparece «interrumpida» de forma irrecuperable.

**Arreglo mínimo:** una línea en `handleSendProducts` (L2096-2099): `.map(Number).filter(Number.isFinite)` → `Array.from(new Set(...))`, o deduplicar `effProductIds` al construir el plan (L1030). Mitigante: los flujos de la app envían ids únicos (`wapi_schedule_config_screen.dart:39` usa `Set<int>`), así que hoy es una brecha de robustez del endpoint, no un fallo en producción. No verifiqué `wapi-cron-dispatch` (programados) línea a línea.

---

## 4. Reanudación entre chunks — **Cobertura OK / Orden destino-mayor FALLA**

La cobertura es exacta: la continuación encola por `resume_log_ids` (L1069) y el receptor reusa esas filas sin insertar ninguna nueva.

```
C5 DEFAULTS 5 destinos x 25 productos
  destinos chunk1 (orden)   : 111@g.us → 222@g.us → 444@g.us → 555@g.us → 666@g.us
  destinos reanudación      : 222@g.us → 444@g.us → 555@g.us → 666@g.us → 111@g.us
  pares: chunk1=109 reanudación=109
  mismoConjunto=true  mismoOrden=false  filasNuevas=0  duplicadas=0
```

**El orden NO se conserva.** El comentario del código (L1051-1055) afirma que la continuación «retoma EXACTAMENTE donde se cortó, conservando el orden por destino». Es falso, y el mecanismo es demostrable:

1. `registrarPendientesPares` inserta los pares que faltan en el orden de `remainingPares` (destino-mayor), pero los pares cuyos productos **ya se prepararon** en el chunk anterior ya tienen fila desde `prepararProducto`, y ahí las filas se insertaron **por producto, con todos sus destinos de golpe** (L1443-1456).
2. La reconstrucción de la reanudación (L883-915) deriva el orden de destinos del **orden de `id` de las filas**: `chats` es un `Map` que se llena por primera aparición en la lista ordenada por `id` (L903-911), y `chatsValidos` sale de `Array.from(chats.values())` (L915) → el `plan` se reconstruye sobre ese orden (L1030-1037).
3. Por tanto el primer destino del chunk reanudado es **el destino que tenga la fila pendiente con `id` más bajo**, que típicamente es un destino *posterior* al que se estaba sirviendo (porque los mensajes ya enviados del destino en curso dejaron de estar pendientes).

Casos mínimos reproducidos:

```
C1 corte tras 7 msgs (3dest x 4prod)
  destinos chunk1 (orden)   : 222@g.us → 333@g.us
  destinos reanudación      : 333@g.us → 222@g.us     ← invertido
C3 corte + producto descartado
  destinos chunk1 (orden)   : 111@g.us → 222@g.us
  destinos reanudación      : 222@g.us → 111@g.us     ← invertido
```

Impacto: **no hay pérdida ni duplicado de pares** (`mismoConjunto=true` en C1, C2, C3, C5; `filasNuevas=0`; `duplicadas=0`), y dentro de cada chunk todos los destinos siguen recibiendo el mismo orden de productos (`efecto de `posDeProducto` sobre `effProductIds`). Lo que cambia es *qué grupo se sirve primero*: con los defaults, el grupo que recibió los primeros 16 productos pasa a ser **el último** de la cadena (C5: `111` va al final), y su catálogo se completa más tarde. Además rompe la promesa del comentario y altera el patrón anti-ban (el «destino en curso» cambia entre chunks).

**Arreglo mínimo:** en la rama de reanudación, ordenar `effDestinations` según el `destinations` recibido (la continuación **sí lo manda**, `destinations: effDestinations`, L1068) en vez de por primera aparición en los logs; p. ej. `effDestinations = destinations.filter(d => chats.has(d.chat_id))`, con el fallback actual para la reanudación manual (que manda `destinations: []`, `wapi_notification_service.dart:343`). Alternativa equivalente: añadir `orden_destino`/`orden_par` al payload o persistir la posición.

C4 ilustra además el efecto esperado de una reanudación **manual**: la app manda `tanda.logIdsSinEnviar` (pendientes **y fallidos**, `wapi_notifications_service.dart:325-347`, `wapi_notifications_screen.dart:1445`) y el receptor filtra solo `.neq("estado","enviado")` (L877), así que el plan reanudado incluye los `fallido` de un destino saltado (`mismoConjunto=false` es correcto aquí). En la cadena automática eso no ocurre: los destinos saltados **no** se encolan (L1981-1997).

---

## 5. `ReferenceError: ses is not defined` — **OK**

- `ses` es ahora argumento obligatorio de `dispatchProducts` (L828-832) y se desestructura (L850).
- La rama de recuperación lo usa en L1703 (`ses.last_recovery_at`), L1704 (`ses.recovery_attempts`) y L1711 (`ses.id`), todo dentro de `dispatchOne`, que es un closure de `dispatchProducts` → **en scope**.
- `handleSendProducts` lo pasa en L2255-2258 (`ses: { id, last_recovery_at, recovery_attempts }`).
- `dispatchProducts` tiene **un único** punto de llamada (L2247, en el mismo archivo). `wapi-cron-dispatch` delega por HTTP y no lo importa (grep en todo `supabase/functions`: solo comentarios). No queda ningún otro uso de `ses` fuera de scope: los de L2135-2258 pertenecen a `handleSendProducts`, donde `ses` es la fila de `app_wapi_sesion` (L2135).

---

## 6. Referencias muertas / rotas — **OK (cero)**

```powershell
# Select-String sobre ventiq_admin_app/supabase/functions/**/*.ts
remainingIds => 0
registrarPendientes( => 0
productosDespachados => 0
seedCounter => 0
reservaProductoMs => 0
PRODUCT_MAX_MS => 0
corteDeProducto => 0
envios => 0
PRODUCT_TIMEOUT => 0
productosEnviados => 0
pendientesRegistrados => 0
```
Se buscaron además las variantes `reservaMensajeMs`/`PRODUCT_TIMEOUT` (eliminadas en el cambio): la única aparición de `PRODUCT_TIMEOUT` es 0 y las nuevas constantes son `MENSAJE_MAX_MS` (L141) y `DESTINO_FALLOS_MAX` (L149). `registrarPendientesPares` (con nombre completo) sí existe y es la única función de registro.

---

## 7. Valores escritos en `estado` — **OK**

Sitios de escritura (grep de `estado:` en `index.ts`), todos dentro del enum:
`pendiente` L1136, L1168, L1440, L1451, L1565, L1820 · `enviado` L1595 · `fallido` L1376, L1827.
La lectura usa `.neq("estado","enviado")` (L877), que no escribe. La restricción existe en la BD (consulta al catálogo real, solo lectura):

```
app_wapi_envio_log_estado_check  CHECK ((estado = ANY (ARRAY['pendiente'::text,'enviado'::text,'fallido'::text])))
app_wapi_envio_log_tipo_envio_check  CHECK ((tipo_envio = ANY (ARRAY['manual'::text,'programado'::text])))
```

El arnés comprueba además el estado final de cada fila: `enum=ok` en los 10 escenarios. **Matiz (riesgo residual):** `tipo_envio` sí puede violar su CHECK porque llega sin validar (`body.tipo_envio ?? "manual"`, L2248/2265) y un CHECK violado reproduce exactamente la ruta de E10 (insert fallido → sin filas → cadena rota en silencio).

---

## 8. Clave de idempotencia — **OK (con dos cautelas)**

- Se construye **solo** a partir del `logId` de la fila: `e.logId ? \`wa-log-${e.logId}\` : undefined` (L1588), y `e.logId` se fija una vez por mensaje en L1916 (`listo.logIdPorChat.get(par.chatId)`).
- Es estable entre reintentos: la expresión está **dentro** del bucle de reintentos (L1577-1797) y `e.logId` no cambia en todo `dispatchOne`.
- Es estable entre chunks: al reanudar, `logIdPorChat` se llena desde la fila reutilizada (L1432-1435 en reanudación, L1467-1471 en alta) y el receptor reconstruye `logIdPorPar` desde `app_wapi_envio_log.id` (L895-898) → mismo id, misma clave.
- Arnés: `idem=53/53` (todas las llamadas con clave, todas distintas) en los escenarios normales; `idem=0/0(sinLog=6)` solo en E10 (insert fallido).
- El resumen usa `wa-sum-${chatId}-${fnv1a(text)}` (L767), también estable e independiente de la fila (y cambia si cambia el texto, que es lo deseado).

Cautelas: (a) si `logId` es `null` (insert fallido) no hay cabecera y un reintento intra-invocación puede duplicar (E10); (b) reanudar con la MISMA clave supone que OpenWA conserva la respuesta guardada — **no verificable desde aquí** (ver sección final): si OpenWA tiene TTL y olvida la clave, una reanudación tardía reenvía el mensaje.

---

## 9. Riesgo anti-ban del orden por destino — **OK con matiz cuantitativo (el ritmo por chat se multiplica ×5)**

```
node __agent__/wapi/verify/ritmo.mjs
delay medio=7.5s  destinos=5  productos=25  pausa entre destinos=20s+0-5s
sEnvio | gap/chat ANTES | gap/chat AHORA | factor | msgs/h/chat ANTES -> AHORA | msgs/min sesion ANTES -> AHORA | rafaga de 25 al mismo grupo
    8s |         77.5s |         15.5s |    5.0x |   46 ->  232 |   3.87 ->   3.68 | 32.3min -> 6.5min
   16s |        117.5s |         23.5s |    5.0x |   31 ->  153 |   2.55 ->   2.47 | 49.0min -> 9.8min
   27s |        172.5s |         34.5s |    5.0x |   21 ->  104 |   1.74 ->   1.70 | 71.9min -> 14.4min
   45s |        262.5s |         52.5s |    5.0x |   14 ->   69 |   1.14 ->   1.13 | 109.4min -> 21.9min
```

- **Por sesión: sin cambio** (≈3.9 → 3.7 msgs/min con envío de 8s; 1.1 msgs/min con 45s). Sigue holgadamente por debajo del techo de 20 msgs/min/sesión que cita el propio archivo (L32-33) — de 5× a 17× por debajo.
- **Por chat: ×5** exacto (el factor es `N = nº de destinos`). El hueco entre mensajes al mismo grupo pasa de `N×(envío+delay)` a `(envío+delay)`. El suelo real es 5s de delay + tiempo de envío; con la latencia optimista de 8s son 13-18s entre mensajes al mismo grupo, y una ráfaga de 25 productos entra en **~6.5 minutos** (antes 32 min).
- Con la latencia realmente medida (16-50s/imagen, citada en el propio código L1005-1007 y L2222-2225) el riesgo prácticamente no cambia: 23-52s entre mensajes al mismo chat.

**Veredicto cuantitativo:** el riesgo de bloqueo **sube de forma moderada**, y solo en el escenario optimista de envíos rápidos (~8s). El factor limitante de WhatsApp es más por-chat que por-sesión, así que concentrar 25 mensajes en un grupo multiplica por 5 la densidad de mensajes que ese chat ve por minuto; no obstante el patrón es «catálogo» (captions distintos, sin texto repetido), el delay aleatorio se mantiene y el propio OpenWA tiene un breaker (`SEND_PACING_LIMITED` / 429) que el código respeta (L1750-1769). Recomendación (no bloqueante): un suelo de pausa por-chat además del delay (p. ej. `max(delay, 15s)`) o repartir en rondas de 5-6 productos por destino, que recupera el ritmo por sesión sin la ráfaga.

---

## Lo que NO pude verificar

1. **Tipos.** No hay `deno`, ni `tsc`, ni `bun` funcional; `check_ts.mjs` solo valida sintaxis. Cualquier error de tipos queda sin detectar.
2. **Ejecución real contra OpenWA.** No tengo acceso al servidor (lo tiene `ing-servidor`). Sin verificar: que la build instalada acepte `Idempotency-Key`, **cuánto tiempo conserva la respuesta guardada** (TTL) — de eso depende que reanudar `pendiente` no duplique —, y la semántica exacta de `IDEMPOTENCY_KEY_IN_PROGRESS` / `IDEMPOTENCY_OUTCOME_UNKNOWN`.
3. **Límite real de `.in("id", resume_log_ids)` en PostgREST/Kong.** La cadena manda los ids en el body (JSON, sin problema), pero el receptor construye una query string `id=in.(…)` (L875). Con ~1500 pendientes son ~10 KB de URL y podría fallar con 414/400 (entonces `dispatchResume` lanzaría `Error cargando logs a reanudar`, L880, y la cadena moriría con las filas en `pendiente`). Con los defaults (109 pendientes en C5, ~760 bytes) está holgado. Es una estimación por umbral (≈1000 ids), no una prueba.
4. **Comportamiento de la UI** ante `pendiente` con `error_code`, y si el auto-refresh/«tanda interrumpida» se cierra correctamente. Solo revisé el llamador (`wapi_notification_service.dart`, `wapi_notifications_screen.dart`) para confirmar qué manda la reanudación.
5. **`wapi-cron-dispatch`/planificador** (si puede enviar `product_ids` duplicados o `tipo_envio` inválido) y **la retención real de `app_wapi_envio_log`**.
6. **Los 400s de Supabase Edge**: `WORKER_BUDGET_MS=270_000` es una convención; la medición real del techo no está reproducida aquí.
7. **`MENSAJE_MAX_MS` como “techo”.** El comentario (L136-141) lo llama «techo de reloj para UN mensaje»; por inspección **no es un techo duro**: el guarda se evalúa *entre* intentos (L1778) y antes de esperar (L1630/L1660), así que un mensaje puede llegar a ~184s (90s de `TIMEOUT_MEDIA_MS` + backoff + 90s) superando los 150s. No lo pude medir en vivo; lo reporto como discrepancia comentario/código, no como pérdida.

---

## Riesgos residuales (ordenados por impacto)

1. **Insert fallido del log ⇒ pérdida silenciosa** (E10): sin filas, sin `Idempotency-Key`, sin «CADENA ROTA», y la tanda no es reanudable desde la UI. Es la fuga más seria que encontré.
2. **`product_ids` sin deduplicar** ⇒ filas duplicadas del mismo `(producto, chat)` cuando un destino se salta (E9), y una de ellas queda `pendiente` para siempre (la reanudación solo conserva el primer log del par). Arreglo de una línea.
3. **Orden destino-mayor no preservado entre chunks** (C1/C3/C5): el grupo que se estaba sirviendo pasa al final de la cadena; contradice el comentario y cambia el patrón anti-ban por chat.
4. **`tipo_envio` y demás campos del body sin validar** contra los CHECK de la tabla: un valor inválido reproduce el fallo 1.
5. **`id_producto` con `ON DELETE SET NULL`**: si se borra un producto a mitad de tanda, sus filas quedan `pendiente` con `id_producto = NULL`; la reconstrucción las descarta (`Number(row.id_producto)` no finito → `continue`, L892) y nunca podrán reanudarse, dejando la tanda «interrumpida» de forma permanente.
6. **Cadenas largas**: con latencias de 16-50s por imagen, un chunk de 270s despacha ~5-16 mensajes; una tanda de 125 mensajes necesita ~8-25 workers encadenados y cada salto depende de que el worker anterior llegue vivo al cierre. No hay watchdog que reencadene si la cadena muere.
7. **Ráfaga por chat ×5** (punto 9): aceptable, pero sin suelo de pausa por-chat.

---

### Artefactos reproducibles (write scope del verificador)

- `__agent__/wapi/verify/snapshot/index.ts`, `snapshot/wapi_client.ts` — revisión congelada (hash en el encabezado).
- `__agent__/wapi/verify/build_harness.mjs` — extrae los bloques verbatim y aborta si el hash no coincide.
- `__agent__/wapi/verify/runner.js` — escenarios, cadenas y búsqueda exhaustiva.
- `__agent__/wapi/verify/harness.mts` — generado (no editar).
- `__agent__/wapi/verify/ritmo.mjs` — cálculo del punto 9.
- `__agent__/wapi/verify/salida_harness.txt` — salida completa y literal del arnés (citas de arriba).

---

# Re-verificación — revisión 2 (`index.ts` SHA256 `C94F8257…`, 2429 líneas)

**Verificador:** el mismo, independiente. **Fecha:** 2026-10-23. `_shared/wapi_client.ts` sin cambios (`75C9623D…`).
Snapshot congelado: `__agent__/wapi/verify/snapshot2/index.ts` (el builder `build_harness.mjs` aborta si el hash no coincide). El arnés de la revisión 1 queda reproducible en `build_harness_r1.mjs` / `runner_r1.js`.
Delta real medido con `git diff --no-index snapshot/index.ts snapshot2/index.ts`: **129 inserciones / 20 borrados** (solo en `index.ts`).
Artefactos de esta ronda: `snapshot2/index.ts` (hash verificado), `build_harness.mjs` → `harness.mts`, `runner.js`, salida literal en `salida_harness_r2.txt`.

**Puerta de sintaxis (revisión 2):**
```
C94F8257EF3A1F2FDD44736B6579F76A5621D844ED5CF110B5F21FFD68A8FC4D  index.ts (2429 líneas)
75C9623D385205F02A2FC020AC7C09224C59A40872CB796DE58D8C399F936E96  wapi_client.ts
OK    ventiq_admin_app/supabase/functions/wapi-send-products/index.ts
OK    ventiq_admin_app/supabase/functions/_shared/wapi_client.ts
Sintaxis OK (los tipos NO se validan con esto).   EXIT=0
```

| Punto | Revisión 1 | Revisión 2 | Evidencia |
|---|---|---|---|
| 1 Puerta | OK | **OK** | arriba |
| FALLA 1 (E10) | FALLA | **OK** | `E10 … CR=1 reinv=0 cont=NO` |
| FALLA 2 (E9) | FALLA | **OK** | `E9 … dup=0 filas=4 pend=1` |
| FALLA 3 (orden) | FALLA | **OK** | C1/C2/C3/C5/C4b `mismoOrden=true` |
| 2 Cubos (E7) | FALLA formal | **OK por diseño** | `E7 … sinBucket=2\|111,2\|222 perdidos=0` |
| deDestinoSaltado | «código muerto» | **corrijo: alcanzable** | `E11 … mov=1` + 2907/101 700 casos |
| 5-9 | OK / ver notas | **OK** (re-verificado) | greps abajo |

### FALLA 1 corregida — OK
`registrarPendientesPares` devuelve `{ ids, ok }` (L1164-1242): `ok=false` si el insert lanza (L1208-1216) y **además** comprueba que cada clave de `faltantes` acabó en `logIdDePar` (L1217-1223). Los tres consumidores hacen `const { ids, ok }` (L1437 `descartar`, L2076 saltados, L2115 continuación). La rama de continuación ya no llama a `reinvokeRemaining` cuando no hay ids y grita:
```
E10 insert DB falla   plan= 8 llam= 6 rem= 2 mov=0 CR=1 reinv=0 cont=NO filas= 0
                      pendSinFila=3|222@g.us,4|222@g.us  idem=0/0(sinLog=6)
```
`CR=1` = se emitió «CADENA ROTA: no se pudieron registrar …» (L2115-2130) y `reinv=0` = no se encoló nada a medias con la lista vacía (antes: silencio total). `pendSinFila` sigue apareciendo porque si la BD rechaza el insert no hay fila que crear; ya no es silencioso, que era el fallo. Matiz menor: las dos llamadas de las ramas `pacing`/`sessionAbort` (L2100, L2111) ignoran el objeto devuelto — correcto, porque esas ramas no encolan continuación y el error ya se registra dentro de `registrarPendientesPares`.

### FALLA 2 corregida — OK (doble cierre)
- Endpoint: `product_ids` y `summary_product_ids` pasan por `Array.from(new Set(...))` (L2215-2226).
- `registrarPendientesPares`: `faltantes` es un `Map<string, Par>` por `clavePar` (L1173-1182), así que dos pares repetidos no insertan dos filas.
Evidencia con el caso que antes duplicaba (llamando a `dispatchProducts` directamente con `[1,2,3,4,4]`, salteando el `Set` del endpoint, para probar la segunda capa):
```
E9  rev1: dup=4|111@g.us x2  filas=5   (2 filas del mismo par; 1 quedaba pendiente para siempre)
E9  rev2: dup=0              filas=4  pend=1  salt=2
```
Las dos entradas repetidas de `saltadosPares` siguen existiendo en memoria, pero `registrarPendientesPares` devuelve un único id (`implicados` es un `Set`) y hay una sola fila.

### FALLA 3 corregida — OK (orden canónico al reanudar)
El reordenado nuevo (L915-960) usa el índice en `destinations` para los destinos y el índice en `args.summaryProductIds` para los productos, con `Array.sort` estable y `MAX_SAFE_INTEGER` para lo desconocido (no se pierde nada si algún chat_id no está en la petición). Resultados:
```
C1  destinos: 222 → 333 | pares reanudación idénticos a chunk1   mismoOrden=true
C3  destinos: 111 → 222 | pares reanudación idénticos            mismoOrden=true
C5  DEFAULTS 5dest x 25prod: 111 → 222 → 444 → 555 → 666  (antes terminaba en 111)  mismoOrden=true
C4b (destino caído + corte, semántica de CADENA): mismoConjunto=true mismoOrden=true
```
- `mismoConjunto=true` en C1/C2/C3/C4b/C5/C6/C7 y `filasNuevas=0 duplicadas=0` en todos → ni pérdida ni duplicado.
- **Fallback manual** (la app manda `destinations: []`): C6 (con `summary_product_ids`) y C7 (sin nada) siguen dando `mismoConjunto=true`, `mismoOrden=true` y cero filas nuevas. C4 sigue con `mismoConjunto=false` **a propósito**: la reanudación manual incluye también los `fallido` (`.neq("estado","enviado")`, L921) y esos sí se re-despachan. No es regresión.
- Efecto lateral positivo: al fijar `effProductIds` al orden original, `posDeProducto` deja de desplazarse entre chunks: el icono/posición del caption del mismo producto es ahora idéntico en el primer chunk y en los reanudados.

### Cubos (punto 2) — OK por diseño, con el aviso nuevo
`E7 … sinBucket=2|111@g.us,2|222@g.us  perdidos=0` (el `continue` de `descartados` sigue sin cubo, y es correcto: `descartar()` ya dejó esas filas `fallido`/SKIPPED). La otra rama (`!listo.chats.includes`) ahora escribe un `console.error` explícito antes de omitir (L1990-1994), así que ninguna omisión es ya silenciosa.

### Corrección de MI veredicto de la revisión 1: `deDestinoSaltado` NO es código muerto
El lead tenía razón y yo estaba equivocado. Mi argumento («`sinPresupuesto` no puede pasar de falso a verdadero dentro de un destino saltado porque no se llama a `dispatchOne`») ignora que `elapsed() = Date.now() - startedAt` **avanza en cada llamada**, aunque el bucle no despache. Reproducción explícita (E11) con deriva de 1 ms por llamada a `elapsed()`:
```
E11 deriva de reloj 1ms  plan=10 llam=3 fall=3 pend=7 rem=6 salt=2 mov=1 cont=ok reinv=1
                         filas=10 sinBucket=0 perdidos=0 pendSinFila=0
```
Y la búsqueda exhaustiva con esa deriva lo encuentra sistemáticamente:
```
SIN deriva de reloj : ejecuciones=4824    conMovimientoNoVacio=0
CON deriva (1ms/llamada) : ejecuciones=101700  conMovimientoNoVacio=2907
EJEMPLO: chats=[111@g.us] products=[1..5] outs=[fallo,fallo,fallo,ok,ok] budget=7
         → plan=5 llam=3 rem=1 salt=2 mov=1 sinBucket=0 perdidos=0
```
Cuando el bloque se ejecuta **hace lo correcto**: mueve esos pares de `remainingPares` a `saltadosPares` (los dos acaban en `registrarPendientesPares`), no pierde ninguno (`sinBucket=0`, `perdidos=0`) y la continuación sigue con lo demás (`cont=ok`). **Recomendación: consérvalo** — cuesta 4 líneas y protege ante un futuro reordenamiento de las comprobaciones del bucle. Salvedad: con `elapsed()` real la ventana de disparo es de ~1 ms por chunk; no es un bug.

### Puntos 5-9 de la revisión 1 (re-verificados sobre el hash nuevo)
- **5 `ses`**: sigue en scope — `ses.last_recovery_at` L1777, `ses.recovery_attempts` L1778, `ses.id` L1785; punto de llamada único L2356 con `ses: {…}` en L2362-2366. El diff no toca esa rama.
- **6 referencias muertas**: `remainingIds`, `registrarPendientes(`, `productosDespachados`, `seedCounter`, `reservaProductoMs`, `PRODUCT_MAX_MS`, `corteDeProducto`, `envios`, `PRODUCT_TIMEOUT` → **0** en todo `supabase/functions/**/*.ts`.
- **7 `estado`**: 9 escrituras, todas `pendiente` (L1190, 1235, 1514, 1525, 1639, 1894) / `enviado` (L1669) / `fallido` (L1450, 1901) + CHECK real de la tabla. `enum=ok` en los 11 escenarios del arnés.
- **8 idempotencia**: sin cambios en los sitios de la clave (`wa-log-${e.logId}`); arnés `56 llamadas / 56 claves distintas`, 0 sin logId salvo el caso E10 (insert fallido).
- **9 anti-ban**: el orden por destino no cambia delays ni pausas, así que el cálculo del informe anterior (×5 por chat, sin cambio por sesión) sigue vigente.

### Lo que NO pude verificar (revisión 2)
Igual que antes: **tipos** (sin deno/tsc), **TTL de idempotencia en OpenWA**, y el límite real de URL de `.in("id", resume_log_ids)` (≈1000 ids ≈ 10 KB; con los defaults C5 son 109). El delta no toca esos frentes.

### Veredicto global para `C94F8257EF3A1F2FDD44736B6579F76A5621D844ED5CF110B5F21FFD68A8FC4D`
**Las 3 FALLA están corregidas y verificadas con el arnés sobre el hash congelado; las 6 verificaciones previas siguen OK.** No encuentro regresión nueva en el delta (cobertura exacta de la cadena, cero duplicados, cero pérdidas materiales, solo los 3 valores de `estado`). Quedan dos residuales de entorno, no de este cambio: mensajes sin fila si la BD rechaza el insert (ahora reportado con «CADENA ROTA», E10) y el límite de URL con colas de reanudación de ~1000+ ids. **Apto para desplegar** desde el punto de vista de esta verificación.

No se modificó ningún archivo de la edge function ni de la app.