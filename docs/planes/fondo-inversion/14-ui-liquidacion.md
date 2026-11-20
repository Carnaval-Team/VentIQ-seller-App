# UI Liquidación — asistente de reserva desde el fondo

> Proyecto `projects/4232822798385486487`, design system `assets/c6b06057a9464b0d89f5593a1f4a8a3b`. Las dos salieron
> `COMPLETE`; el primer intento del desktop murió con `fetch failed` y el reintento (uno) funcionó. Los `screenId`
> son los de la respuesta de generación: `list_screens` sigue devolviendo solo las 3 viejas (`13-ui-compras.md`).

| Pantalla | `screenId` | Título en Stitch | Render |
|---|---|---|---|
| D · Liquidación (desktop) | `f245be0f32f5429eafa3782c4fb67389` | Liquidar compra #A-1042 - Asistente de Fondos | 2560×2080 |
| D · Liquidación (móvil) | `a967540a43744ee7baddc4877b75eb98` | Liquidar compra - Asistente Móvil | 780×2926 |

## Transversal

- **Se reutiliza `compras_widgets.dart`**: `panelCompras`, `tituloSeccionCompras`, `cifraCompra`, `chipEstadoCompra`,
  `pastillaCompras`, `avisoCompras`, `formatearImporteMoneda` y los cortes de ancho. Solo son nuevos la barra de
  cobertura (8 px) y el bloque de faltante. Ni radios, ni sombras, ni colores nuevos.
- **Un solo CTA en toda la pantalla**, literal: «Reservar y continuar a pagar». Sin segundo primario, sin FAB y sin
  «Pagar» al lado: el pago es el paso 2 y vive en otra pantalla.
- **Tasa por fuente con el par explícito**: input editable + `1 USD = 1.000,000 CUP` + chip de origen (`manual ·
  César` / `fijo · Sistema`). Nunca un número suelto, nunca en un `ExpansionTile`. Si la moneda de la fuente = moneda
  del total, el input se cambia por el chip `Misma moneda · sin tasa` (el render dejó el input: Stitch no condiciona).
- **Se elige contra el disponible**: fila `Saldo · Reservado · Disponible` en ese orden, y el input se valida contra
  `disponible = saldo − reservado`. Helper: «quedan 400,00 USD disponibles en esta cuenta tras el aporte». Toda cifra
  nativa lleva su moneda pegada; el equivalente va rotulado `= N,NN <moneda del total>`.

## D · Desktop (>1024)

- **Tres zonas.** Banda superior: breadcrumb 11 px + panel de compra (título 20 w700, chips de estado, liquidación y
  moneda, metadatos) con «Total a financiar» **dentro de esa banda al extremo derecho**, no en el panel lateral: el
  total no se va con el scroll. Cuerpo: `Row` con izquierda flexible (fuentes) y **derecha fija de 400 px**.
- **Un único scroll: el de la izquierda.** El panel derecho no scrollea (`04-diseno-ux.md` §4). Por eso mide 400 y no
  340/380: aloja barra + faltante + pasos + botón sin cortarse en 900 px de alto.
- **Fuentes = tarjeta por fuente, no tabla**, con cuatro líneas fijas: (1) checkbox + cuenta + chips de moneda y medio;
  (2) las tres cifras; (3) monto + tasa + equivalente; (4) helper. Cierra con la fila punteada `+ Añadir otra fuente`
  tratada como input.
- **El faltante va en el panel derecho, justo encima de «Cómo sigue» y del botón**: último dato antes de la acción.
  Orden interno: total → aportado → barra → faltante → pasos → botón → helper de bloqueo → «Cancelar» (texto).

## D · Móvil (<600)

- **Orden obligatorio, una columna**: resumen pegado bajo el AppBar → compra → fuentes → «+ Añadir» → «Cómo sigue» →
  barra inferior fija.
- **El resumen no es colapsable y el faltante vive dentro de él**: si queda fuera de pantalla, la regla deja de
  existir. Total y aportado en la misma fila, barra de 6 px, recuadro rojo a ancho completo debajo.
- **Una tarjeta por fuente con campos apilados**: monto a ancho completo (teclado numérico), tasa debajo con el par
  completo, equivalente a la derecha. Cero scroll horizontal, cero tabla. Barra inferior fija con la línea roja
  «Faltan 20,00 USD para poder reservar», el botón deshabilitado a ancho completo y «Cancelar» como texto.

## Cómo se representa el bloqueo (idéntico en las dos)

1. **Recuadro `FALTANTE`**: cifra en 24 px y «No se puede reservar con un céntimo de diferencia». Fondo `#FEE2E2`,
   borde `#FCA5A5`, texto e icono `#B91C1C`.
2. **Botón con `onPressed: null`** + candado + helper «Deshabilitado: faltan 20,00 USD. Ajusta un monto o añade una
   fuente». El motivo se escribe; no se confía en el gris.
3. **Barra de cobertura con tramo rojo proporcional** (98 % `#194B8C` / 2 % `#B91C1C`) y leyenda numérica:
   «980,00 de 1.000,00 USD · 98 %». Nunca una barra sin números.

- **Comparación exacta, sin épsilon**: se habilita solo si `aportado − total == 0`, con los importes redondeados a 2
  decimales por fuente. Nada de tolerancias de 0,01.
- **Faltante = 0**: recuadro fuera, barra 100 % `primary`, botón habilitado, helper «Cubre el total al céntimo».
- **Sobrepago no es faltante**: con `aportado > total` el bloque pasa a `error` con «Sobran X» y el botón sigue
  bloqueado. `#B91C1C` es el único tono de dinero roto (el rojo puro de `AppColors.error` se lee como fallo del
  sistema). Se aparta de `04-diseno-ux.md` §5, que reserva `warning` para el faltante: ahí informa, aquí bloquea.
- **Dos pasos, visibles siempre**: «1 · Reservar congela el disponible de las fuentes» y «2 · Pagar descuenta el
  dinero · son dos pasos separados», con badge `Paso 2`.

## Lo que no se generó

- **Estados**: cobertura exacta con el botón habilitado, sobrepago y fuente en la moneda del total. Tres variantes a
  resolver en Flutter con esta jerarquía; no se inventaron pantallas que el plan no pide. El **paso 2 (pago)** queda
  fuera de alcance.
- No revisé el HTML línea por línea; sí el resumen del agente y las dimensiones.