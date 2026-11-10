# Pre-orden: variante visual (`PreorderScreenStyled`)

Estado: **activa** en la ruta `/preorder` (interruptor `kPreorderStyled = true`).

## Qué es

Una **copia** de `lib/screens/preorder_screen.dart` con la presentación rediseñada.
La lógica es la misma línea por línea: mismos servicios, mismo `OrderService`,
mismo cobro, mismo control de stock, mismas ramas offline/online, mismos
pseudo-métodos de pago (`998` Pago Pendiente, `999` Pago Regular).

| Fichero | Papel |
|---|---|
| `lib/screens/preorder_screen.dart` | Original, **intacto**. Es la red de seguridad. |
| `lib/screens/preorder_screen_styled.dart` | Variante visual: `PreorderScreenStyled` + `kPreorderStyled` |
| `lib/main.dart` | Registra `/preorder` y elige variante según el flag |
| `test/screens/preorder_styled_compile_test.dart` | Guardia: obliga a compilar la variante en cada `flutter test` |

## Cómo volver a la pantalla anterior

Una sola línea, en `lib/screens/preorder_screen_styled.dart`:

```dart
const bool kPreorderStyled = false;   // true = variante nueva, false = original
```

No hay que tocar `main.dart` ni borrar ficheros. Las dos pantallas conviven.

## Qué cambia visualmente

1. **Control global de medio de pago** (cabecera): una **píldora por medio real**
   de la tienda (`PaymentMethodService.getPaymentMethodsWithCache`), en una fila
   con scroll horizontal. Un toque aplica ese medio a **todas** las líneas, en vez
   de ir producto por producto.
   - Si todas las líneas comparten medio, ese medio sale resaltado y el subtítulo
     dice «Se aplica a todos los productos».
   - Si hay mezcla, **ninguna** píldora se resalta y el subtítulo lo explica:
     «Mixto · 2 Efectivo, 1 Transferencia». Tocar una píldora vuelve a unificar.
   - La «x» quita el medio global (mismo `_clearGlobalPaymentMethod` de siempre).
2. **Píldora compacta por línea**: sustituye al bloque grande de cada tarjeta.
   Muestra el medio de esa línea y abre el **mismo** `PaymentMethodPickerScreen`
   para cambiarla. Si la línea se sale del medio de referencia (el global, o el
   mayoritario cuando la orden es mixta) lleva un **punto ámbar**.
3. **Tarjeta de ítem reordenada**: nombre y total arriba; «cantidad × precio
   unitario» en una sola línea; ubicación en gris; al pie, la píldora del medio
   junto a los controles − / + / borrar (38 px cada uno).
4. **Importes**: se mantiene `MonedaVentaService.formatearPrecio(...,
   conSimbolo: true)`, es decir, **en la moneda de venta seleccionada y con su
   símbolo**, igual que la pantalla original.

## Qué NO cambia

Ninguna llamada a servicios, ningún método de mutación de la orden
(`_updateItemQuantity`, `_removeItem`, `_updateItemPaymentMethod`,
`_applyGlobalPaymentMethod`, `_clearGlobalPaymentMethod`), ningún diálogo, la
validación de stock, el chequeo de turno, las ramas offline, la barra inferior ni
la navegación.

## Regla de mantenimiento (importante)

El coste de poder revertir con un flag es la **duplicación**: un arreglo de lógica
hecho en `preorder_screen.dart` **no** llega solo a la variante.

- Si se corrige lógica en una, **replicarla en la otra**.
- Cuando la variante se apruebe definitivamente: borrar
  `preorder_screen.dart` (o dejarlo como envoltorio que devuelva
  `PreorderScreenStyled`) y eliminar el flag. Entonces el test de compilación
  pasa a apuntar al único fichero.

## Pendiente / no incluido

- **Miniatura del producto** en la tarjeta: el mockup la tenía, pero `OrderItem`
  no expone una imagen y no se ha inventado el campo.
- **Chip de stock por línea**: el stock se valida antes de cobrar, pero la tarjeta
  no tiene un valor de stock por ítem disponible; no se ha añadido un dato falso.
- Sin verificación visual en dispositivo: la garantía actual es que compila y que
  la suite pasa. El aspecto hay que verlo con `flutter run`.