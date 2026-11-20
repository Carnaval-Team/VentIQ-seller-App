# Diseño UX/UI — Compras a proveedor, recepción con costo real y saldos

> Documento de diseño. No es código Flutter. Se apoya en lo que ya existe en
> `ventiq_admin_app` y **no propone rediseñar nada en producción**. Las afirmaciones
> sobre el código llevan `ruta:línea`.

## 1. Auditoría del lenguaje visual real

**No hay sistema de diseño formal.** Hay un `AppColors` (`lib/config/app_colors.dart`) +
un `ThemeData` global (`lib/main.dart:122-152`) y, encima, cada módulo repite estilos a mano.
Eso es el sistema: hay que copiarlo, no sustituirlo.

| Token | Valor real | Fuente |
|---|---|---|
| Material 3 | `useMaterial3: true`, `ColorScheme.fromSeed(AppColors.primary)` | `main.dart:123-124` |
| Primario | `#194B8C` (gradiente a `#123A6B`) | `app_colors.dart:6-7,54-58` |
| Fondo de pantalla | `#F8F9FA` | `app_colors.dart:9` |
| Superficie / borde | blanco / `#E5E7EB` | `app_colors.dart:46,48` |
| Texto | `#1F2937` / `#6B7280` / `#9CA3AF` | `app_colors.dart:40-42` |
| Éxito / alerta / error / info | `#10B981` / `#FF6B35` / `Colors.red` / `#4A90E2` | `app_colors.dart:12-15` |
| Card | elevación 2, radio 12, color blanco | `main.dart:145-151` |
| Botón elevado | radio 8, primario | `main.dart:136-144` |
| AppBar | primaria, elevación 0, título 20 w600 centrado | `main.dart:125-135` |
| Panel tipo tarjeta plano (FDI) | `surface` + borde + radio 12, padding 16/12 | `fondo_inversion_screen.dart:219-234` |
| Tipografía de cifras | label 13 secundario + cifra 18 w700 `textPrimary` | `fondo_inversion_screen.dart:236-260` |
| Título de sección | 16 w700 `textPrimary` | `fondo_inversion_screen.dart:262-271` |
| Metadato | 13, altura 1.35, `textSecondary` | `fondo_inversion_screen.dart:273-282` |
| Estado vacío | texto centrado 14 secundario, `vertical: 32` | `fondo_inversion_screen.dart:284-299` |
| Separador de lista | `Divider(height:1, AppColors.border)` | `fondo_inversion_screen.dart:378` |
| Item de drawer | icono 24 en caja 10% primaria radio 8 + título 16 w600 + subtítulo 12 gris | `admin_drawer.dart:1067-1108` |
| Chip de estado | fondo color 15% + borde 40% + radio 12 + texto 12 w600 | `pago_proveedores_screen.dart:2820-2838` |

**Patrones dominantes (lo que hay que reutilizar tal cual):**

1. **Pantalla = AppBar primaria + `TabBar` scrollable blanco + `ListView` de paneles planos.**
   `fondo_inversion_screen.dart:132-186` (7 pestañas: Saldos, Movimientos, Liquidaciones,
   Transferencias, Inversiones, Inversores, Config). Los tabs son el mecanismo de densidad
   del repo; no hay navegación lateral ni panel maestro-detalle real.
2. **Fila-lista en vez de tabla en los módulos de dinero.** FDI pinta
   fila con nombre+metadato a la izquierda y cifra 16 w700 a la derecha, separadas por
   `Divider` (`fondo_inversion_screen.dart:385-420`). No se usan tablas salvo en reportes:
   `DataTable` solo aparece en ventas/HR/importación Excel, siempre envuelto en
   `SingleChildScrollView(scrollDirection: Axis.horizontal)` (`sales_screen.dart:2887-2892`).
3. **"Maestro-detalle" es navegacional, no de panel.** Proveedores es lista de tarjetas →
   push a detalle que es una columna de `Card`s (`suppliers_list_screen.dart:353`,
   `supplier_detail_screen.dart:113-140`). No existe patrón de dos columnas en el repo.
4. **Pantalla "saldo de tercero" ya existe, tres veces, idéntica.** Selector de
   (proveedor/banco) arriba → `TabBar` Saldo/Facturas → tarjeta hero con gradiente
   primario, radio 16, elevación 4, cifra 32 blanca (`pago_proveedores_screen.dart:2081-2095`,
   `importadora_facturas_screen.dart:1357-1432`, `depositos_bancarios_screen.dart:2133`)
   → historial en `showModalBottomSheet` → recarga/cambio de estado en `showDialog`
   → tarjetas de documento con chip de estado. **Es el molde de "Compras".**
5. **Diálogo vs pantalla:** los formularios cortos de dinero (recarga, cambio de estado,
   liquidación) son `showDialog` con `SingleChildScrollView`
   (`fdi_liquidacion_dialog.dart:594-598`). La captura larga es pantalla completa con
   `Stepper` de 5 pasos (`excel_import_screen.dart:201-215`). Recepción es pantalla
   completa con secciones en `Card` (`inventory_reception_screen.dart:613-732`).
6. **Nomencladores con color configurable.** Los estados no llevan color en el código: se
   eligen de una paleta fija de 8 hex guardada en BD (`#FF9800, #2196F3, #9C27B0, #4CAF50,
   #F44336, #607D8B, #795548, #00BCD4` — `estados_factura_proveedores_screen.dart:57-65`)
   y se pintan con `_hexToColor(factura.colorEstado)` (`pago_proveedores_screen.dart:2743`).
   **Compras debe usar ese nomenclador, no hardcodear colores de estado.**
7. **Iconografía:** solo Material Icons, tamaño 18-24, primary o el color del estado.
   Nunca ilustraciones, nunca iconos de librería externa.
8. **Error:** `SnackBar` con `backgroundColor: AppColors.error`
   (`fondo_inversion_screen.dart:2493`); error de carga a pantalla completa = texto
   centrado "Error: …" (`fondo_inversion_screen.dart:165-174`). Ambos son pobres, pero son
   el estándar; mejorarlos es fase 2.
9. **Modo oscuro: NO existe.** Cero coincidencias de `darkTheme`, `ThemeMode` o
   `Brightness.dark` en todo `lib/`; `CardTheme.color` es `Colors.white` literal
   (`main.dart:150`) y `AppColors.surface` es blanco (`app_colors.dart:46`). Diseñar
   **light-first**; el bloque de dinero debe usar tokens (`AppColors`/`colorScheme`), nunca
   hex nuevos, para que un futuro tema oscuro no lo rompa.
10. **Densidad:** no hay modo compacto. La densidad se logra con estructura (paneles
    planos, filas de 12+12 de padding, gaps 24/12 — `fondo_inversion_screen.dart:215-217`).

## 2. Arquitectura de información

"Compras" **es un módulo nuevo de primer nivel, no una pestaña de Fondo de Inversión**:
una compra puede ser pagada por el fondo, por caja o por aportes de inversores, así que
no puede vivir dentro del fondo. Se coloca en el clúster financiero del drawer, entre
"Fondo de Inversión" (`admin_drawer.dart:625-636`) y "Pago a proveedores"
(`admin_drawer.dart:757-768`), porque **la compra precede al pago**: hoy "Pago a
proveedores" registra facturas sueltas contra un saldo; la compra es el documento que las
justifica. Riesgo real de duplicar pantallas: ver §9.

```
Dashboard
Productos · Inventario · Almacenes · TPVs · Cocinas · Servicentro
Marketing · Ventas · Finanzas · CRM
Consignaciones
Cuentas por Cobrar
Fondo de Inversión          /fondo-inversion        (existe)
Compras                     /compras                (NUEVO, icono shopping_cart_outlined)
   ├ Detalle                /compra-detalle          args: idCompra
   ├ Crear / editar         /compra-editar           args: idCompra?
   ├ Asistente de pago      /compra-pago             args: idCompra
   ├ Aportes de inversores  /compra-aportes          args: idCompra
   ├ Recepción contra compra /compra-recepcion       args: idCompra, idLinea?
   └ Conciliación           /compras-conciliacion
Pago a proveedores          /pago-proveedores       (existe — pasa a ser liquidación de compras)
Fondo de Caja · Configuración
```

Convención de rutas: **lista y configuración = ruta plana kebab-case en español**
(`/depositos-tipos-extraccion`, `main.dart:301`); **detalle/edición = `onGenerateRoute`
con `settings.arguments`** (`main.dart:154-199`, patrón `/supplier-detail`). Toda ruta nueva
necesita entrada en el mapa de roles de `permissions_service.dart:585-629`
(p. ej. `/compras-recepcion` → gerente, supervisor, almacenero, como
`/inventory-reception:597-601`).

Relaciones: **Fondo de Inversión** aporta y reserva saldo; **Proveedores** es el maestro
del acreedor (`/suppliers`); **Importadora** es uno de los destinos de pago de la
recepción (pago a importadora + costos adicionales); **Recepción** hoy se enlaza a una
*inversión* del fondo, no a una compra (`inventory_reception_screen.dart:687-732`) —
pasa a admitir los dos orígenes sin romper ese vínculo. La "Configuración de costos
adicionales" **ya existe** como nomenclador superadmin
(`cost_types_management_screen.dart`, `docs/PLAN_COSTOS_ADICIONALES.md:88`): se extiende,
no se crea.

## 3. Inventario de pantallas

| # | Pantalla | Objetivo | Usuario | Datos | Acciones | Fase |
|---|---|---|---|---|---|---|
| A | Listado de compras | Ver el compromiso total y qué falta | Dueño, gerente | Proveedor, factura, fecha, moneda, total, pagado, por pagar, recibido, estado | Filtrar (estado/proveedor/fecha/moneda), ordenar, exportar, abrir | MVP |
| B | Crear/editar compra | Dejar la compra en el sistema con su factura | Gerente, supervisor | Proveedor, nº/ fecha/ moneda de factura, líneas (producto, cant., costo, desc., IVA), totales | Añadir línea, escanear/buscar, editar en línea, guardar borrador, emitir | MVP |
| C | Detalle de compra | Una sola verdad: qué compré, qué pagué, qué falta | Dueño, gerente, auditor | Cabecera, líneas con costo real, factura, reserva, recepciones, aportes, historial | Pagar, recibir, aportar, cancelar, imprimir, cambiar estado | MVP |
| D | Asistente de pago multimoneda | Pagar sin equivocarse de moneda ni de tasa | Gerente | Total, ya pagado, disponible por cuenta/moneda, tasa, faltante en vivo | Elegir cuentas, montos, tasa, confirmar; registrar sobrante/faltante | MVP |
| E | Aportes de inversores a la compra | Quién puso dinero y cuánto | Dueño, gerente | Inversor, % , monto, moneda, tasa, estado del aporte | Aportar, editar, revertir con motivo | Fase 2 |
| F | Recepción contra compra | Registrar lo que llegó y a qué costo | Almacenero, supervisor | Línea, pedido, recibido antes, pendiente, cantidad ahora, costo real, costos adicionales | Escanear, editar cantidades, aplicar costos, cerrar recepción | MVP |
| G | Costos adicionales por producto (en recepción) | Repartir flete/aduana/etc. al costo real | Gerente, supervisor | Concepto, monto, moneda, tasa, criterio de reparto, impacto por unidad | Añadir, editar, distribuir, ver prorrateo | MVP |
| H | Configuración de costos adicionales | Definir qué conceptos existen | Superadmin | Concepto, tipo, activo, orden, criterio por defecto | CRUD | MVP (extiende existente) |
| I | Conciliación / control | Cuadrar compra ↔ recepción ↔ pago | Dueño, auditor | Diferencias por compra: pedido vs recibido vs facturado vs pagado; reservas huérfanas | Filtrar, exportar PDF/Excel, marcar revisado | Fase 2 |

## 4. Responsive

El repo **no tiene puntos de quiebre centralizados** (`utils/platform_utils.dart` distingue
web/móvil, no ancho). Los valores de facto son **600** (una decena de usos:
`add_product_screen.dart:8938`, `inventory_operations_screen.dart:1022` usa 640,
`financial_screen.dart:708`, `promotion_form_screen.dart:1265`…) y **640/720** en captura.
Se adopta el de facto y se documenta como constante nueva en `lib/config/` (única adición
al sistema, no un rediseño):

- **compact** `< 600` — móvil vertical
- **medium** `600–1024` — tablet vertical / móvil horizontal
- **expanded** `> 1024` — PC (objetivo: máxima información)

| Pantalla | compact <600 | medium 600–1024 | expanded >1024 |
|---|---|---|---|
| A Listado | Tarjeta: proveedor + total + estado + por pagar; meta "Factura · Fecha"; "recibido 3/5"; acciones en `⋮`. Totales en 2 cifras sobre la lista. | 6 columnas (Proveedor, Total, Por pagar, Recibido, Estado, ⋮); filtros en una fila `Wrap` (patrón `inventory_operations_screen.dart:1019-1120`); totales en banda de 4 cifras. | **10 columnas** (#, Proveedor, Factura, Fecha, Moneda, Total, Pagado, Por pagar, Recibido, Estado) + acciones; **panel derecho fijo 340 px** con totales, faltante y filtros activos; filtros en barra superior, no en panel. |
| B Crear/editar | 1 línea por tarjeta con 3 campos (producto, cant., costo); totales como barra inferior fija; "Guardar borrador" en AppBar. | Línea = fila de 4 campos; totales en panel de 320 px **debajo** de la tabla. | Tabla de líneas con 7 columnas editable inline; **panel derecho 360 px fijo** con factura + totales + IVA + faltante; teclado: Tab entre celdas, Enter añade línea. |
| C Detalle | Una columna: cabecera → bloque de saldos → líneas → recepciones → historial; acciones en barra inferior. | Dos columnas: izquierda líneas, derecha saldos + acciones. | Tres zonas: izquierda líneas (flex), **derecha 380 px fija** con saldos, estado, tasa y acciones; historial y recepciones en pestañas dentro de la zona izquierda. |
| D Asistente de pago | Pasos apilados (monto → cuenta → tasa → confirmar) con el faltante siempre visible arriba, sticky. | Dos columnas: izquierda cuentas, derecha resumen sticky. | Cuentas a la izquierda (flex), resumen sticky 400 px a la derecha con total, pagado, faltante y tasa; **nunca** dos scrolls. |
| E Aportes | Lista de aportes + botón "Aportar" en FAB. | Tabla 5 columnas + totales arriba. | Tabla 7 columnas + barra de reparto y % a la derecha. |
| F Recepción | Tarjeta por línea pendiente: producto, pedido/recibido/pendiente, stepper de cantidad, costo. Solo pendientes visibles por defecto. | Tabla 5 columnas editable; costos adicionales en bottom sheet. | Tabla 8 columnas (producto, pedido, recibido, pendiente, ahora, costo, adicional, subtotal) + panel derecho 320 px con total recepción y avance. |
| G Costos adicionales | Formulario + lista; prorrateo en bottom sheet expandible. | Tabla 4 columnas + preview de prorrateo debajo. | Tabla de conceptos a la izquierda, prorrateo por producto a la derecha (mitad y mitad). |
| H Config costos | Lista + FAB. | Lista + FAB. | Lista + panel de edición lateral (reusar el patrón de nomencladores existente). |
| I Conciliación | Tarjeta por compra con las 3 cifras y el semáforo. | Tabla 6 columnas. | Tabla 9 columnas + resumen de diferencias fijo a la derecha. |

Regla transversal: **el resumen de dinero nunca se va con el scroll en PC ni en móvil**
(sticky / barra inferior fija); en tablet sí puede ir al final del bloque.

## 5. El problema del dinero

**Disponible ≠ saldo.** El error a evitar es mostrar el saldo del fondo como si fuera
gastable. Patrón obligatorio: **bloque de cuatro cifras + barra de compromiso**.

- **Cifras:** Total · Reservado · Pagado · Ejecutado, y **Faltante** solo si `> 0`.
  Cada cifra: label 13 `textSecondary` + valor 18-24 w700 (reusa
  `fondo_inversion_screen.dart:236-260`). "Disponible" se calcula y se rotula
  "Disponible (no comprometido)".
- **Barra de compromiso:** una barra de 8 px, radio 4, tres segmentos —
  pagado (`primaryDark`) · reservado (`primary` al 40%) · pendiente (`border`) — con leyenda
  numérica al lado. **Nunca** una barra sin números.
- **Chip de tasa, siempre visible, nunca colapsado:**
  `1 USD = 320,00 CUP · 19/11 10:08 · manual (César)`. Anti-patrón actual a no repetir:
  la tasa vive dentro de un `ExpansionTile` cerrado y en 10 px gris
  (`reception_total_widget.dart:132` y `:327-334`).
- **Quién y cuándo:** toda cifra de dinero lleva debajo "por <usuario> · <fecha hora>",
  estilo metadato 13 `textSecondary`. Sin eso no hay confianza.
- **Faltante en vivo:** recuadro con `AppColors.warning` al 10% de fondo + borde 30% +
  `Icons.error_outline`, texto "Faltan 1.240,00 CUP". Cambia a `AppColors.error` solo si el
  usuario intenta pagar de más (sobrepago), no por faltante normal.
- **Reglas de color:** positivos y neutros en `textPrimary`; faltante/deuda en
  `warning`; sobrepago, descuadre y edición destructiva en `error`. Todo monto negativo
  lleva **signo menos y palabra**, nunca solo color (`AppColors.error` es `Colors.red`
  puro, `app_colors.dart:14`: no usar ese rojo para "falta dinero", es agresivo y se lee
  como error de sistema).
- **Modo oscuro:** no existe hoy (§1.9). El bloque se construye con `AppColors` +
  `colorScheme`; si algún día se agrega `darkTheme`, el único ajuste necesario será el par
  superficie/texto, no los colores semánticos.

## 6. Estados de la compra

Chip = color del nomenclador + icono + **texto**, nunca color solo. Se reusa el chip exacto
de `pago_proveedores_screen.dart:2820-2838` y, en el detalle, se añade una barra de 4
segmentos con el paso actual resaltado.

| Estado | Color | Icono | Barra | Acción primaria | Acciones destructivas |
|---|---|---|---|---|---|
| `creada` | `#2196F3` azul | `receipt_long` | 1/4 | **Pagar** | Cancelar (solo si reserva = 0) |
| `pagada` | `#00BCD4` cian | `payments` | 2/4 | **Recibir mercancía** | Cancelar (exige motivo + revierte pago) |
| `entrega_parcial` | `#FF9800` naranja | `inventory_2` | 3/4 | **Completar recepción** | Cancelar (bloqueada: hay reserva activa) |
| `completada` | `#4CAF50` verde | `check_circle` | 4/4 | Ver conciliación | Ninguna (terminal) |
| `cancelada` | `#607D8B` gris | `cancel` | — | — | — (terminal) |

Transiciones y bloqueos explícitos en la UI, no en un mensaje de error: el botón que no
aplica **no se muestra**; el que aplica pero está bloqueado se muestra deshabilitado con
tooltip que dice la razón ("no se puede cancelar: hay 3.000 CUP reservados de la cuenta
Banco USD; libera la reserva primero").

**Cancelar con reserva activa** = doble confirmación con consecuencia enumerada: lista de
qué se libera (monto y cuenta), campo **Motivo** obligatorio (nomenclador, no texto libre),
y confirmación escribiendo el monto o el nº de factura. Reusar `_confirmDialog`
(`fondo_inversion_screen.dart:2472`) como base, no `AlertDialog` suelto. **Completada y
cancelada son irreversibles**: el detalle debe decir "cerrada el … por …" y ocultar acciones.

## 7. Captura larga (muchas líneas)

Ya hay dos precedentes que se reutilizan **sin inventar**: `Stepper` de 5 pasos para
importación (`excel_import_screen.dart:201-215`) y selector de producto con búsqueda
debounced 700 ms (`product_selector_widget.dart:335-339`).

- **Nunca una línea vacía al final**: el campo de búsqueda es la fila "+ añadir"; al elegir
  producto se crea la línea y el foco vuelve al buscador.
- **Autocompletado de costo**: último costo del proveedor > costo del catálogo > 0, marcado
  con un icono de origen ("sugerido") que el usuario puede ignorar. Nunca sobrescribir un
  valor ya escrito.
- **Edición en línea:** cantidad y costo son campos en la fila, no diálogos. Hoy la cantidad
  se edita en diálogo (`reception_edit_dialog.dart`) — en la pantalla nueva, inline.
- **Escaneo:** el componente existe (`barcode_scanner_screen.dart`) pero hoy solo se usa en
  productos (`products_screen.dart:2140`); se reutiliza en compra y recepción con lector
  físico + cámara.
- **Borrador:** guardado local por compra (`/compra-editar` reabre el borrador), badge
  "Borrador · sin emitir" en el listado, y aviso al salir con cambios.
- **Progreso y total siempre a la vista**: contador "12 líneas · 3 sin costo" y total
  sticky; la recepción lleva "7 de 9 líneas · 82 %" con el pendiente total.
- **Duplicar compra** (fase 2) es lo que más ahorra en este dominio: mismas líneas,
  cantidades en cero.

## 8. Prompts para Stitch (copiar tal cual)

> Todos en inglés, autocontenidos. Paleta y tipografía fijas: primary `#194B8C`, dark
> `#123A6B`, background `#F8F9FA`, surface `#FFFFFF`, border `#E5E7EB`, texto `#1F2937` /
> `#6B7280`, success `#10B981`, warning `#FF6B35`, info `#4A90E2`. Tipografía del sistema
> (Roboto), cifras w700, labels 13 px. Densidad: alta, secciones planas con borde, sin
> sombras grandes. Light mode only.

**1. Purchases list** — `Purchases list, admin ERP for a small retail business (Spanish UI text). DESKTOP 1440px. Top app bar in primary #194B8C with title "Compras", 4 KPI numbers in a row (Total comprometido, Reservado, Pagado, Por pagar) at 24px bold each with 13px grey labels. Below: filter bar (estado chips, proveedor, date range, moneda) then a dense data table, 10 columns (#, Proveedor, Factura, Fecha, Moneda, Total, Pagado, Por pagar, Recibido, Estado) with right-aligned tabular amounts and a status pill (15% tinted background, 40% border, 12px). Fixed right panel 340px: "Faltante" in warning #FF6B35 on 10% tint, active filters, export button. Row height 56px, 1px #E5E7EB dividers, no zebra, no card per row. AVOID: cards inside the table, more than one CTA per row, decorative gradients, dark mode.` — *Mobile delta:* single column of cards: provider + total + status pill + "por pagar" on line 1, "Factura · Fecha" and "recibido 3/5" on line 2, ⋮ menu; KPI block collapses to 2 numbers (Total, Por pagar) above the list; filters behind a "Filtros (2)" button.

**2. Create / edit purchase** — `Purchase creation form, Spanish UI. DESKTOP 1440px. Left 70%: invoice header card (proveedor picker, número, fecha, moneda) then an editable line table (Producto, Cant., Costo unit., Desc. %, IVA, Subtotal, ⋮) with a "+ Buscar o escanear producto" row at the bottom that looks like an input. Right 30% sticky card: Subtotal, Descuentos, IVA, TOTAL in 28px bold, "Reservado" in primary tint, "Faltante de saldo" in warning if >0, primary button "Emitir compra" + text button "Guardar borrador". Badge "Borrador · sin emitir" near the title. Dense inputs, 40px height, 8px radius. AVOID: line editing in modal dialogs, totals not visible while scrolling, empty line placeholders, currency symbols mixed in one column.` — *Mobile delta:* one card per line with 3 fields (producto, cantidad, costo), totals in a fixed bottom sheet bar with expand-to-detail, "Guardar borrador" in the app bar.

**3. Purchase detail** — `Purchase detail, Spanish UI, DESKTOP 1440px. Header: "Compra #A-1042" + status pill "entrega_parcial" (#FF9800) + a 4-segment progress bar (creada → pagada → recibida → completada) with current step solid and previous filled. Left column: lines table with ordered / received / pending / real cost / additional cost / subtotal; below, tabs for Recepciones and Historial (timeline with user + timestamp). Right fixed 380px: money block stacked — Total compra, Reservado, Pagado, Ejecutado, and "Faltan 1.240,00 CUP" in warning tint; below, exchange-rate chip "1 USD = 320,00 CUP · 19/11 10:08 · manual (César)" with a small info icon; then actions "Recibir", "Pagar", outline "Cancelar". AVOID: hiding the rate in a collapsible, showing gross balance as available, more than 3 primary buttons, modals for the money summary.` — *Mobile delta:* single column, money block first (not last), actions in a fixed bottom bar, recepciones/historial as stacked sections instead of tabs.

**4. Multi-currency payment assistant** — `Payment wizard, Spanish UI, DESKTOP 1440px, two columns. Left: "Cuentas" list of selectable rows, each with account name, currency badge, "Disponible 12.400,00 USD" and an amount input with the currency prefix; a "tasa" input appears per non-base currency with helper text "1 USD = 320,00 CUP". Right sticky 400px: "Total a pagar 4.800,00 USD", "Ya pagado 1.000,00", "Aportes de inversores 500,00", separator, live "Faltante 3.300,00 USD" in warning #FF6B35 on 10% tint that recalculates per keystroke, then "Cubrir desde el fondo" toggle and primary button "Confirmar pago" disabled while a discrepancy exists, with a plain-language line saying why it is disabled. Step numbers 1-2-3 with light grey titles. AVOID: confirming with a shortfall, rate as small grey footnote, currency mixing without badges, auto-converting without showing the rate, a modal for the final confirmation.` — *Mobile delta:* vertical steps (Monto → Cuenta → Tasa → Confirmar), shortfall pinned at the top of the screen, one sticky "Confirmar pago" bar at the bottom.

**5. Investor contributions to a purchase** — `Investor contributions screen, Spanish UI, DESKTOP 1440px. Top: purchase reference and "Faltan por cubrir 3.300,00 USD" in warning tint. Table: Inversor, % participación, Monto aportado, Moneda, Tasa, Equivalente, Fecha, Estado (pill) — amounts right-aligned, total row pinned at the bottom of the table with a darker background. Right 320px: donut or stacked bar of participation with numeric legend beside it (never a chart without numbers), and a primary button "Registrar aporte". Row actions: edit, revert (revert opens a confirmation requiring a reason). AVOID: charts without numbers, percentages without the resulting amount, hiding the exchange rate per row, red for "pending".` — *Mobile delta:* list of contribution cards (inversor, monto, equivalente, estado) with the participation bar on top and FAB "Registrar aporte".

**6. Receive against purchase** — `Goods reception, Spanish UI, DESKTOP 1440px, dense. Header: "Recepción de Compra #A-1042" + progress "7 de 9 líneas · 82 %" + right-side search/scan field. Main table, 8 columns: Producto, Pedido, Recibido, Pendiente, Recibir ahora (editable number), Costo unit., Costo adicional, Subtotal; pending rows first, fully received rows dimmed and collapsed at the bottom; each row has a scan icon. Right 320px sticky: "Total recepción 3.180,00 USD", "Costo adicional 120,00", "Total real", and the exchange-rate chip. Sticky bottom action bar: "Cancelar" text + primary "Confirmar recepción" with badge count. AVOID: modal per product to set quantity, over-receiving above the ordered quantity without an explicit warning state, hiding already-received rows, losing the pending count.` — *Mobile delta:* one card per line with pedido/recibido/pendiente as three small figures, a stepper for the quantity, expandable cost fields, total in a sticky bottom bar.

**7. Additional costs per product** — `Additional costs allocation, Spanish UI, DESKTOP 1440px, split 50/50. Left: list of cost concepts (Flete, Aduana, Seguro) each with monto, moneda, tasa, and an allocation rule selector (por valor, por cantidad, manual); "+ Añadir concepto". Right: preview table of how the total is distributed per product with unit cost before/after and a delta column showing the impact in warning colour. Top strip: total purchase cost, total additional, real unit cost. AVOID: hiding the allocation criterion, showing the allocation without the resulting unit cost, per-product manual editing without a reset, more than 6 concepts visible.` — *Mobile delta:* concepts as cards with an expandable "ver reparto" per concept; the global preview lives at the end of the screen with a sticky total.

**8. Additional costs configuration (admin)** — `Admin nomenclature screen, Spanish UI, DESKTOP 1024px. Simple master list: Conceptual name, type, default allocation rule, active switch, order, actions. Right-side edit panel (not a modal) with name, tipo, criterio por defecto, activo, orden, and "Guardar". Superadmin banner at the top: "Solo superadministrador". Dense rows 48px, 1px dividers. AVOID: modals for edition, deleting without confirmation, mixing this screen with the per-purchase cost capture.` — *Mobile delta:* list + full-screen edit form pushed from a FAB.

**9. Reconciliation / control report** — `Reconciliation report, Spanish UI, DESKTOP 1440px. Filter bar (rango de fechas, proveedor, estado, "solo con diferencias" toggle). Table: Compra, Proveedor, Total pedido, Total recibido, Total facturado, Total pagado, Diferencia, Semáforo (green/amber/red dot WITH a text label), Revisado checkbox. Sticky right 300px: "3 compras con diferencias · 1 reserva huérfana" and export buttons PDF/Excel. Rows with differences keep a 3px left border in warning/error. AVOID: colour-only status, exporting without the applied filters noted, hiding the totals of the filtered set.` — *Mobile delta:* card per purchase with the four totals stacked, the difference emphasised, and the semaphore as a labelled chip.

## 9. Errores de UX que hay que evitar

1. **Mostrar saldo bruto como disponible.** Siempre `disponible = saldo − reservado`, y
   rotularlo "no comprometido".
2. **Ocultar la tasa.** Es la única cifra que el dueño no puede verificar solo; va visible,
   con fecha, autor y si fue manual o automática (`reception_total_widget.dart:327-334` es
   exactamente lo que no se hace).
3. **Permitir confirmar con faltante.** El botón se deshabilita y dice por qué; el faltante
   se puede cubrir con fondo o aportes, pero nunca "seguir igual".
4. **Tablas que se cortan en móvil.** `SingleChildScrollView` horizontal
   (`sales_screen.dart:2887`) solo medio resuelve: en compact se convierte a tarjeta, no se
   scrollea.
5. **Duplicar "Pago a proveedores".** Ya existen tres pantallas casi idénticas de
   saldo+facturas (§1.4); Compras **no** debe ser la cuarta: reutiliza el molde, y el pago
   sigue viviendo donde vive hoy.
6. **Diálogo para todo.** Formularios de más de 4 campos en `AlertDialog` se vuelven
   inusables en móvil; pantalla completa con `Stepper`.
7. **Estado por color solamente.** Chip con icono + texto; hay daltonismo y hay impresión.
8. **Cerrar la compra en la primera recepción parcial.** Las cantidades se acumulan
   (`docs/planes/fondo-inversion/05-referencia-industria.md:27-31`); la UI debe mostrar
   "recibido 3/5" siempre.
9. **Cancelar sin decir qué se libera.** Toda acción destructiva enumera consecuencias
   (monto, cuenta, reserva) y pide motivo; nada de "¿Está seguro?" a secas.
10. **Inventar un design system paralelo.** No introducir radios, sombras, verdes ni rojos
    nuevos: `AppColors` + radios 8/12/16 + elevación 2/4 ya cubren todo lo que pide este
    módulo.