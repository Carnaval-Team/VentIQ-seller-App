# Reactivar una reserva cancelada (admin y vendedor) — migración 58

**Ámbito:** app Flutter `inventtia_flow` (GoReserva) + esquema `flow` de Supabase.
**Origen:** bug reportado al probar la app — «al reactivar una reserva cancelada me da
error de que solo puedo cambiarla a cancelado o completado».
**Creado:** 24-10-2026.

---

## 1. El síntoma y la causa

Al tocar **Reactivar** en una reserva cancelada, la app mostraba:

> Estado destino no permitido (use Cancelado o Completado)

**Causa raíz, con evidencia del servidor vivo** (`pg_get_functiondef` contra el proyecto
release):

- `flow.staff_marcar_estado_agenda(p_id_agenda, p_id_estado)` empezaba con
  `if p_id_estado not in (2, 3)` → solo **Cancelado (2)** y **Completado (3)**.
- Las dos pantallas que reactivan mandaban **1 (Reservado)**, que es exactamente lo que
  promete el botón.

O sea: reactivar era **imposible**: la app pedía el único estado que el servidor no
aceptaba.

**Y había un segundo agujero, peor:** completar una cancelada solo se permite si su fecha
es **de hoy o anterior**. Para una cancelada **futura** el servidor rechazaba las dos vías
(`'Solo se pueden completar reservas canceladas de hoy o fechas anteriores'`), así que esas
reservas no se podían sacar de Cancelado de ninguna forma. Estado real de la base al
24-10-2026:

| | filas |
|---|---|
| Reservas canceladas | 42 |
| … de hoy o futuras (**atrapadas**: ni reactivar ni completar) | **3** |
| … pasadas (solo completables) | 39 |

---

## 2. La regla que queda

`destinosReactivacion` (`lib/utils/reactivar_reserva.dart`) espeja la del servidor:

| Fecha de la reserva cancelada | Dejarla pendiente (1) | Marcarla como completada (3) |
|---|:--:|:--:|
| Hoy o futura | ✅ | solo si es **hoy** |
| Pasada | ❌ | ✅ |

Traducido: **una futura solo se puede reactivar** (volver a la cola), **una pasada solo se
puede cerrar como completada**, y **una de hoy admite las dos**. El diálogo ofrece solo lo
que el servidor va a aceptar y **explica la opción que no está** («La reserva ya pasó: no se
puede volver a dejar pendiente»), en vez de esconderla sin más.

---

## 3. Qué cambia

### 3.1 SQL — `docs/flow_schema/migraciones/58_reactivar_reserva_cancelada.sql`

Reescribe **solo** `flow.staff_marcar_estado_agenda` (misma firma, mismas columnas de
retorno, mismos permisos y mismas reglas para cancelar y completar):

1. Acepta el destino **1** además de 2 y 3.
2. Reactivar (1) solo vale **desde Cancelado** y solo si la fecha es **de hoy o futura**.
3. Reactivar **re-consume la capacidad** que liberó la cancelación (los tramos del turno, o
   `plan_servicios`), acotada a la capacidad total: lo mismo que ya hacía el paso de
   cancelada a completada.
4. Al reactivar se **limpia `fecha_hora_atencion`** (vuelve a estar pendiente de atención).
5. Se **notifica al titular** cuando la reserva sale de Cancelado (a pendiente o a
   completada). Antes la app decía «cliente notificado» y era mentira: la función solo
   notificaba al cancelar.

> ⚠️ **Hay que aplicarla a mano** en el SQL Editor de Supabase (el MCP de este entorno está
> en solo lectura, así que no se puede aplicar ni probar la creación desde aquí). Mientras
> no esté, la app **no se rompe**: al intentar reactivar, el SnackBar traduce el error del
> servidor y dice que falta aplicar la migración 58.

### 3.2 App

| Fichero | Qué |
|---|---|
| `lib/utils/reactivar_reserva.dart` (nuevo) | `DestinoReactivacion` (pendiente=1, completado=3, con etiqueta/ayuda/mensaje de éxito), `destinosReactivacion`, `motivoNoDisponible`, `motivoSinOpciones`, `puedeCompletarReserva`, `puedeReactivarReserva` y `mensajeErrorCambioEstado`. Todo puro y con `ahora` inyectable. |
| `lib/widgets/dialogo_reactivar_reserva.dart` (nuevo) | `mostrarDialogoReactivarReserva(...)`: un botón por destino válido (con su explicación debajo), el motivo de los no válidos y «Cerrar». Antes era un «¿seguro? Sí/No» que adivinaba el estado. |
| `lib/screens/admin/reservas_screen.dart` | «Reactivar» abre el diálogo y aplica `destino.idEstado`; el error del SnackBar pasa por `mensajeErrorCambioEstado`. `_puedeCompletar`/`_puedeDescancelar` delegan en los helpers puros. |
| `lib/screens/vendedor/vendedor_screen.dart` | Exactamente lo mismo (misma regla, una sola copia). |
| `test/reactivar_reserva_test.dart` (nuevo) | 19 tests: los tres casos de fecha, el límite por día (no por hora), los ids como contrato con la RPC, los motivos, la traducción de errores y el diálogo (opciones ofrecidas y destino devuelto). |

**Arreglo del caso muerto:** `puedeCompletarReserva` ahora permite confirmar el consumo de
una cancelada **pasada** (antes devolvía `false` siempre para canceladas, así que no había
ningún botón que las cerrara y la rama `eraCancelada` del confirmador era código muerto).
Es la vía que desatasca las 39 filas.

**Lo que NO cambia:** cancelar sigue exigiendo que la reserva esté activa; completar una
activa sigue sin mirar la fecha; los permisos (owner/admin/vendedor de la entidad) y el
JSON de retorno son los mismos.

---

## 4. Verificación

- `mcp__dart__analyze_files`: **0 errores** en los cinco ficheros tocados.
- `reactivar_reserva_test.dart` + `appbar_contraste_test.dart` juntos: **27/27**.
- Suite completa: **651/651 en verde**. Una corrida intermedia marcó
  `appbar_contraste_test` como fallo por el problema ya documentado en
  `test/flutter_test_config.dart`: `google_fonts` no puede descargar Inter en el entorno
  de test y el runner le adjudica el error asíncrono al test que esté corriendo; esos
  ficheros pasan aislados y la suite volvió a pasar entera. No es del producto ni de este
  cambio.
- **Auditoría de todas las llamadas que cambian el estado de una reserva** (hecha por un
  compañero, con `fichero:línea`): `marcarEstadoAgenda` en
  `vendedor_screen.dart:261`, `admin/reservas_screen.dart:308` y
  `mis_tickets_screen.dart:224`. **Ninguna otra reactiva con 1** ni se salta la regla
  nueva. `admin_cancelar_agenda` (`services/agenda_service.dart:250`) no tiene llamadores:
  código muerto.

### Prueba manual (después de aplicar la 58)

1. Cancelar una reserva **futura** → «Reactivar» → el diálogo ofrece «Dejarla pendiente» y
   explica por qué no puede completarse. Al aceptar, vuelve a Reservado, ocupa capacidad y
   el cliente recibe la notificación.
2. La misma reserva **de hoy** → el diálogo ofrece las dos opciones.
3. Una cancelada **pasada** → el botón es «Confirmar consumo» (ya no hay opción de
   pendiente) y al confirmar queda Completado.
4. Sin la 58 aplicada → el aviso dice que falta la migración, no un error críptico.

---

## 5. Bitácora

| Fecha | Paso | Resultado |
|-------|------|-----------|
| 24-10-2026 | Diagnóstico | `pg_get_functiondef` de la RPC viva: solo acepta 2 y 3. Conteo real: 42 canceladas, 3 de hoy/futuras atrapadas, 39 pasadas. |
| 24-10-2026 | SQL | Migración **58** escrita (reactivar a 1 con regla de fecha, re-consumo de capacidad, limpieza de atención y notificación). **Pendiente de aplicar por el usuario.** |
| 24-10-2026 | App | Helpers puros + diálogo compartido + las dos pantallas (admin y vendedor). Auditoría de llamadas de estado: ninguna otra reactivaba con 1. |
| 24-10-2026 | Extra | `puedeCompletarReserva` desatasca las canceladas pasadas (antes no ofrecían ninguna acción). |
| 24-10-2026 | Verificación | Analyze 0 errores; 19 tests nuevos en verde; suite **651/651** (una corrida intermedia falló por el flake de fuentes ya documentado). |
