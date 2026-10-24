# Ver la app como cliente desde el panel de administración (y volver)

**Ámbito:** app Flutter `inventtia_flow` (GoReserva). Sin cambios de base de datos.
**Origen:** petición del usuario — desde el admin, un botón para pasar a la vista de cliente
«sin que me lleve directo al admin», y desde la vista de cliente poder volver.
**Creado:** 24-10-2026.

---

## 1. El problema

El shell decidía las pantallas por **rol** y sin salida: `EntidadProvider.isAdmin` mandaba
al panel de «Gestión» y ahí te quedabas. El dueño de una entidad también es **cliente** de
otros locales (y de los suyos), y no tenía forma de comprobar cómo ve la app alguien que
entra a reservar: ni el Home nuevo, ni el panel de categorías, ni el listado de
establecimientos.

## 2. La decisión

Un **modo de vista** (`ModoVistaProvider`) que solo existe para quien administra:

| Usuario | `comoCliente` | Pantallas que ve |
|---|:--:|---|
| Cliente puro | — | Home, Servicios, Mis Listas, Reservas, Perfil |
| Admin | `false` | Gestión, Perfil |
| Admin | `true` | **Home, Servicios, Mis Listas, Reservas, Perfil** |
| Admin + vendedor | `false` | Reservas, Gestión, Perfil |
| Admin + vendedor | `true` | Home, Servicios, Mis Listas, Reservas, Perfil |
| Vendedor puro | (se ignora) | Reservas, Perfil |

Detalles que importan:

- **Sin persistencia.** El modo vive en memoria: si se guardara, un admin que cerró la app
  en modo cliente volvería a abrirla en la vista de cliente y podría pensar que perdió su
  panel. Al reiniciar siempre se entra como administrador.
- **El vendedor puro no tiene interruptor** y, si el flag llegara encendido por error,
  `vistaDelShell` lo ignora: no se le puede dejar sin sus pantallas de trabajo.
- Al cambiar de modo se vuelve a la **primera pestaña** de la lista nueva (las dos listas no
  comparten índices: Gestión es la 0 del admin y el Home la 0 del cliente).

## 3. Dónde está el botón

| Vista | Sitio | Qué dice |
|---|---|---|
| Admin | Tarjeta encima del tablero de **Gestión** | «Ver la app como cliente» — *Comprueba cómo la ve un cliente. Puedes volver cuando quieras.* |
| Admin | **Perfil** (sección CUENTA) | La misma entrada, con subtítulo. |
| Cliente (como admin) | Chip «**Admin**» en la cabecera del **Home** | Vuelve al panel (icono `admin_panel_settings`, con tooltip). |
| Cliente (como admin) | **Perfil** (sección CUENTA) | «Volver al panel de administración». |

La tarjeta del admin va en el **cuerpo** y no en la AppBar a propósito: esa AppBar ya lleva
el selector de entidad como título más cuatro acciones repartidas a los dos lados (con
`leadingWidth: 104` documentado), y un quinto icono dejaría el nombre de la entidad
recortado en pantallas estrechas.

El chip «Admin» del Home **solo aparece si el usuario administra algo** (`isAdmin`), así que
un cliente puro nunca ve un botón para ir a un panel que no tiene.

## 4. Qué cambia en el código

| Fichero | Qué |
|---|---|
| `lib/utils/modo_vista.dart` (nuevo) | `VistaShell` y `vistaDelShell({esAdmin, esVendedor, comoCliente})`: la decisión, pura y testeable. |
| `lib/providers/modo_vista_provider.dart` (nuevo) | `ModoVistaProvider` (`ChangeNotifier`): `verComoCliente`, `verComoAdmin`, `alternar`. |
| `lib/screens/home_shell.dart` | El modo decide la lista de pantallas y **la barra inferior** (la de cliente, la misma que usan las vistas apiladas). Lo expone a las pantallas con `ChangeNotifierProvider.value` + `ListenableBuilder` y entra/sale con `_verComoCliente` / `_volverAlAdmin`. `_onTabSelected` pasa a llamarse con «esta vista es la del cliente» (no «el usuario es cliente»): un admin en modo cliente necesita los mismos refrescos de pestaña. |
| `lib/screens/admin/gestion_screen.dart` | `onVerComoCliente` + la tarjeta de acceso. |
| `lib/screens/home_client_screen.dart` | `onVerAdmin` + el chip «Admin» en la cabecera. |
| `lib/screens/perfil_screen.dart` | `onVerAdmin` + las dos entradas del modo; en modo cliente también aparece «Favoritos» (que antes se ocultaba a los admin). |

Lo que **no** cambia: los permisos (el admin sigue siendo admin; el servidor no ve ninguna
diferencia), el tutorial (sigue siendo el del rol), la suscripción de la entidad y el aviso
de impago —un admin en modo cliente sigue viendo su aviso de pago, que es información suya,
no de la vista—.

## 5. Verificación

- `mcp__dart__analyze_files`: **0 errores** en los siete ficheros tocados.
- Suite completa: **676/676** (651 + los 25 de la verificación independiente).
- Verificación independiente (`task-8`, compañero aparte, sin tocar `lib/`):
  `test/modo_vista_verificacion_test.dart` con **25 tests** — la matriz 8/8 de
  `vistaDelShell` (incluido el caso feo: vendedor puro con el interruptor encendido por
  error sigue viendo su panel), el provider con contador de notificaciones, y 4 tests de
  widget que comprueban que la pantalla se repinta al cambiar el modo por las dos vías
  (`ListenableBuilder` y `context.watch`) y que repetir la acción no repinta.

### Bugs que encontró la verificación (y cómo quedaron)

| # | Bug | Arreglo |
|---|---|---|
| 1 | **Regresión de este cambio**: `_irAPestanaDesdeUnaPantalla` pasaba `isAdmin` como «es vista cliente», así que un **cliente puro** dejó de refrescar Catálogo/Mis Listas/Reservas al cambiar de pestaña desde una vista apilada (badge incluido). | El handler resuelve la **vista** con `vistaDelShell(...)` + `esVistaCliente(...)`, que es lo que `_onTabSelected` necesita. |
| 2 | El tile del Perfil llamaba a `modo.verComoCliente` directamente, saltándose el reseteo de pestaña: el admin entraba al modo cliente en «Servicios» (pestaña 1) o en «Mis Listas» (admin+vendedor), no en Inicio. | El Perfil recibe `onVerComoCliente` del **shell** (como ya hacía con `onVerAdmin`) y todos los accesos pasan por `_verComoCliente`. |
| 3 | `mis_tickets_screen._esVendedor` se decidía por «tengo entidad de vendedor», ignorando el modo: un **admin+vendedor** en modo cliente veía la agenda del local y sus acciones de staff en la pestaña Reservas. | `_esVendedor` pasa a significar «esta vista es la del staff» y devuelve `false` en modo cliente. Se lee con `listen: false` (se usa también en `_load()`, fuera de build) y la reactividad la aporta el `watch` de `build`, que es necesario porque los hijos del `IndexedStack` son instancias fijas y no se reconstruyen con el padre. |

### Decisión sobre la «rareza» que reportó

La vista de cliente de un admin **no es idéntica** a la de un cliente puro: sigue viendo el
**aviso de impago** de su entidad, la sección de administración del Perfil y «Mi suscripción».
Es intencionado: el cambio de vista es para *ver el catálogo como lo ve un cliente* (Home,
categorías, establecimientos, top 10, reservar), no para fingir que se ha perdido el panel.
Además, el aviso de impago es información que le afecta y esconderla le haría daño.

## 6. Prueba manual


1. Entrar como admin → «Gestión» → tarjeta **Ver la app como cliente**.
2. Aparece el Home del cliente (rejilla «Exploración rápida», categorías, establecimientos,
   top 10) con el chip **Admin** arriba; se navega por las cinco pestañas.
3. Desde el chip (o desde Perfil → «Volver al panel») se vuelve a «Gestión», en la pestaña
   de administración.
4. Entrar como cliente puro: no hay chip «Admin» ni entradas de modo en Perfil.
5. Entrar como vendedor: sigue viendo Reservas y Perfil, sin interruptor.

## 7. Bitácora

| Fecha | Paso | Resultado |
|-------|------|-----------|
| 24-10-2026 | Diseño | Modo de vista en memoria, decisión extraída a `vistaDelShell` (matriz documentada), interruptor solo para admins. |
| 24-10-2026 | App | Shell + Gestión + Home + Perfil; barra inferior del cliente también en modo cliente; `_onTabSelected` con la semántica correcta. |
| 24-10-2026 | Verificación | Analyze 0 errores; verificación independiente (25 tests) que encontró **3 bugs reales** (uno de ellos regresión) y los dejó documentados. Suite 676/676. |
| 24-10-2026 | Arreglos | (1) `_irAPestanaDesdeUnaPantalla` resuelve la vista; (2) el Perfil pide el cambio por callback del shell para no perder la pestaña; (3) la pestaña Reservas respeta el modo cliente. Analyze 0 errores y suite 676/676. |

Pendiente **fuera del código**: nada. Esta función no necesita migración; la
[migración 57](docs/flow_schema/migraciones/57_categorias_y_locales_cliente.sql) sigue
pendiente de aplicar para que los contadores de categorías y establecimientos tengan datos
reales.
