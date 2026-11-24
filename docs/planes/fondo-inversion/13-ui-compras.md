# UI Compras — pantallas Stitch y decisiones de layout

> Proyecto `projects/4232822798385486487` ("VentiQ — Compras y Fondo de Inversión"), UI en
> <https://stitch.withgoogle.com/projects/4232822798385486487>. Design system generado:
> `assets/c6b06057a9464b0d89f5593a1f4a8a3b` (light only, primario `#194B8C`).
> Las 3 pantallas se generaron en `DESKTOP` (1440×900 lógico): PC es la densidad objetivo.
> Móvil/tablet no se generaron aparte; son las decisiones de abajo, a implementar con
> `LayoutBuilder`. Las 3 devolvieron `screenMetadata.status=COMPLETE` con captura y HTML; el HTML
> de la 1 lo revisé (2×2 de cifras, chips, filas), el de la 2 y la 3 no. `list_screens` devuelve
> `{}` vacío aunque las pantallas existen (el thumbnail del proyecto es la del listado): los
> `screenId` salen de la respuesta de generación, que es la fuente autoritativa.

| Pantalla | `screenId` | Título en Stitch | Render |
|---|---|---|---|
| A · Listado | `699b3ed360114f72880ab3ae14342b6a` | Pedidos de Compra - Listado | 2560×2198 |
| B · Alta / edición | `a52d536731944d5ebba307ce4de00e83` | Compras - Crear / Editar Compra | 2560×2048 |
| C · Detalle | `c26e5148e27f4aa38ccb7b7f0bd31d88` | Compras - Detalle de Compra #A-1042 | 2560×2522 |

Recurso: `projects/4232822798385486487/screens/<screenId>`.

## Transversal

- **Nunca sumar las cuatro cifras.** `total_mercancia`, `total_ajustes`, `total_financiado` y
  `costo_aterrizado`: siempre cuatro valores con etiqueta. El aterrizado va último, tras divisor
  de 2 px, con la tipografía mayor y helper de que incluye lo pagado por la wallet de importadora.
- Ajustes negativos: signo menos **y** el número, nunca solo color.
- **Estado**: color del nomenclador + icono Material + texto (12 w600, fondo 15%, borde 40%).
  creada `#2196F3`, reservada `#9C27B0`, pagada `#00BCD4`, entrega_parcial `#FF9800`,
  completada `#4CAF50`, cancelada `#607D8B`, anulada `#F44336`. Prohibido estado por color solo.
- **Liquidación** (`fondo`/`inversores`) es excluyente: pastilla, nunca dos cifras sumadas.
- **Tasa**: chip visible con valor, fecha-hora y autor. Prohibido `ExpansionTile` cerrado.
- Sin modo oscuro; radios 8/12, elevación 2, solo `AppColors`/`colorScheme`.

## A · Listado

- **PC (>1024):** banda de 4 cifras bajo el AppBar, divididas por 1 px, con pastilla
  FONDO/INVERSORES bajo "Total financiado". Tabla densa: proveedor con "Factura · fecha" en línea
  2; columna **Cifras = micro-rejilla 2×2** (Mercancía/Ajustes, Financiado/Aterrizado; etiqueta
  10 px + valor 13 w600); "3/5 líneas" + barra 4 px; pastilla Liquidación; pastilla Estado; `⋮`.
  Filas 64 px, sin zebra, montos a la derecha con `tabular-nums`. Panel derecho **fijo 340 px**:
  Por pagar 28 w700, recuadro `warning` "Faltan …", Reservado, Pagado, filtros removibles,
  Exportar. El resumen de dinero no se va con el scroll.
- **Tablet (600–1024):** se ocultan `#`, `Moneda` (pasa al pie del proveedor) y `Liquidación`
  (pasa a chip contiguo al estado). El panel derecho deja de ser fila y se convierte en banda
  superior de 2 cifras; nunca una columna lateral menor a 340 px.
- **Móvil (<600):** tarjeta por compra, sin tabla ni scroll horizontal: línea 1 proveedor
  (14 w600) + aterrizado (14 w700) + pastilla de estado; línea 2 "Factura F-2041 · 19/11";
  línea 3 dos cifras (mercancía/financiado) y "recibido 3/5" con barra; ajustes solo si ≠ 0; `⋮`
  al borde. El KPI de 4 cifras **colapsa a 2** (Por pagar, Aterrizado) en banda sticky superior.
  Filtros detrás de "Filtros (2)"; no existe el panel derecho como columna.

## B · Alta / edición

- **PC:** 70/30, izquierda Factura → Líneas → Ajustes, derecha tarjeta sticky de 360 px.
  Líneas: Producto (nombre + "SKU · Unidad"), Cant. y Costo unit. editables en celda; **Costo
  línea calculado, fondo `#F3F4F6`, candado, no editable**. Última fila = input "+ Buscar o
  escanear producto", nunca una línea vacía. Ajustes: fila propia a ancho completo para **Modo de
  liquidación** (Fondo|Inversores, excluyente, helper "Excluyentes: uno u otro"); luego Base
  (Global/Unidad/Porcentaje), Reparto (Valor/Peso/Cantidad), Origen de pago (Fondo/Wallet
  importadora/Wallet proveedor/Externo) + Monto, y la lista de ajustes con chips de base y origen.
  Derecha: cuatro cifras apiladas, Faltante en recuadro `warning`, barra de compromiso de 3
  segmentos con leyenda numérica, "Emitir compra" primario + "Guardar borrador" texto. Strip bajo
  el AppBar: badge "Borrador · sin emitir" + "12 líneas · 1 sin costo".
- **Tablet:** el panel derecho pasa a banda inferior fija en 2×2 cifras; líneas en 4 columnas
  (se oculta `⋮` y el subtítulo SKU).
- **Móvil:** una tarjeta por línea con 3 campos (producto, cantidad, costo); el costo de línea
  calculado se muestra como texto bajo el costo unitario, sin borde de input. Cifras en barra
  inferior fija expandible (2 visibles → 4 + faltante). "Guardar borrador" sube al AppBar; el modo
  de liquidación va en fila propia, no comprimido.

## C · Detalle

- **PC:** banda de cabecera con `Compra #A-1042` 24 w700, pastilla de estado, pastilla
  "Liquidación: FONDO", metadatos y **barra de 4 segmentos** (creada → pagada → recibida →
  completada) con el paso actual sólido y los anteriores llenos. Izquierda: líneas (Producto,
  Cant., Costo unit., **Costo línea read-only con candado**, Recibido, Pendiente —el pendiente > 0
  en `warning` w600) → panel Ajustes read-only con chips → tabs "Recepciones (3)" / "Historial (7)"
  con timeline (avatar, autor, fecha-hora, monto). Derecha **fija 380 px**: cuatro cifras con
  procedencia "por … · fecha hora", faltante en recuadro `warning`, Reservado/Pagado, chip de tasa
  a ancho completo y **exactamente tres acciones** apiladas (Recibir, Pagar, Cancelar outline).
- **Tablet:** dos columnas 60/40 pero el panel derecho deja de ser fijo y baja al final del
  scroll; los tabs se mantienen.
- **Móvil:** una columna con **orden obligatorio**: cabecera → cifras (primero, nunca al final) →
  faltante → chip de tasa → líneas → ajustes → recepciones → historial (secciones apiladas, no
  tabs). Acciones en barra inferior fija: Recibir primario; Pagar y Cancelar en `⋮`. En estados
  terminales (`completada`, `cancelada`, `anulada`) se ocultan las acciones y se muestra
  "cerrada el … por …".