# Spec: Estudio de recuperación de la inversión de un producto

- Module id: `estudio-inversion-producto`.
- Estado: aprobada el 2026-11-16. El stock en cero suma todas las variantes y el estudio es histórico. El plan está en `tasks/plan_estudio_inversion_producto.md`. No se implementa hasta pedir el plan.
- Entorno de referencia: newa, solo catálogo. No se ejecutó SQL de escritura.
- Pantalla: `ventiq_admin_app/lib/screens/sales_screen.dart`, pestaña Tiempo real.

## 1. Objetivo

Quien mira Tiempo real abre un producto y, desde esa vista, un estudio que responde cuánto de lo invertido en ese producto ya se recuperó con sus ventas.

El clic en el producto sigue abriendo el historial cronológico que ya existe. En la cabecera de ese diálogo aparece **Estudio de inversión**, visible solo si el usuario puede ver costos (`_canViewGanancias`). El estudio es histórico: incluye todas las recepciones completadas del producto en la tienda, sin recortarlas al rango de fechas de la pestaña, para que ninguna inversión quede fuera.

Una inversión es un tramo de recepciones. La meta del tramo es la suma de `cantidad × costo` de sus recepciones. Lo recaudado es el dinero de las ventas atribuibles a ese tramo, expresado en la misma moneda que el costo. El cumplimiento es `recaudado / meta`.

Ejemplo de aceptación: el 10/05/2026 entran 5.000 unidades a 0,30 USD. Meta = 1.500 USD. De esa fecha hasta hoy se venden 2.000 unidades a un precio de referencia de 0,60 USD. Recaudado = 1.200 USD. Cumplimiento = 80 %.

## 2. Decisiones que esta spec da por hechas

1. El costo de recepción que se guarda en `app_dat_recepcion_productos.precio_unitario` ya está en USD. El diálogo de recepción convierte antes de guardar. `costo_real` es el total de la línea. La meta usa `costo_real` cuando es mayor que cero y, si no, `cantidad × precio_unitario`. `precio_referencia` de la recepción no es el costo: es otro dato y no entra en la meta.
2. La moneda del estudio es la del costo guardado, USD. No se suman CUP con USD.
3. El porcentaje es de dinero, no de unidades. Puede pasar de 100 % cuando lo vendido supera lo invertido. Con meta 0 no hay porcentaje: se muestra «sin costo».
4. Dos recepciones son la misma inversión mientras el stock del producto no haya llegado a 0 entre ellas. Ese stock suma todas las variantes y todas las ubicaciones de la tienda, en unidades base. Si una variante se agota y otra todavía tiene existencia, no se abre un tramo nuevo. Si el total llegó a 0 antes de la recepción siguiente, esa recepción abre otra inversión. Una devolución posterior no vuelve a pegar el tramo cerrado.
5. Las ventas del tramo son las completadas desde su primera recepción hasta que el stock llega a 0, o hasta ahora si no ha llegado. Una venta no se reparte entre dos tramos: las unidades se consumen en orden, y al cerrarse el tramo las ventas siguientes pertenecen al siguiente.
6. El historial cronológico, sus exportaciones y el filtro de fechas de Tiempo real no cambian.
7. No hay tabla nueva ni RPC nueva. El cálculo es una función pura en Dart sobre lecturas que el admin ya puede hacer. Si una lectura no cabe en el cliente, se pide antes de escribir SQL.

## 3. Cómo se convierte cada venta a USD

Lo recaudado es lo cobrado en esa venta, no el precio de catálogo de hoy y no la tasa de hoy.

- Venta en USD (`moneda_venta = USD`): se toma el neto nativo de la línea (`precio_unitario_neto_nativo × cantidad`, o el neto de la línea si ya viene cerrado). No se vuelve a multiplicar por la tasa.
- Venta en CUP, que es el caso habitual: la tasa de esa venta es `precio_venta_cup / precio_venta_usd` de la fila de `app_dat_precio_venta` vigente en la fecha de la venta (mayor `id` entre las que cubren esa fecha). No se usa `app_v_precio_venta_vigente`: esa vista es el precio de hoy. `recaudado_usd = importe_cobrado_cup / tasa`.
- Esa tasa es el puente del que habla el pedido. Si el precio cobrado en CUP es el de referencia, `importe_cup / tasa` coincide con `precio_venta_usd × cantidad`. Si hubo descuento, entra lo cobrado, no el de referencia.
- Una línea CUP sin par de precios USD/CUP para esa fecha no aporta a lo recaudado. El tramo se marca incompleto y no se presenta el porcentaje como si fuera el cumplimiento. Un dato ausente no es cero.
- Líneas anteriores al multimoneda, sin `moneda_venta`, se tratan como CUP y siguen la misma regla.
- Bonificación: las unidades bonificadas entran al stock (pueden impedir o retrasar el 0) y no suman a la meta. Lo que se venda de ellas sí suma a lo recaudado.

Cantidades de recepción y de venta se pasan a unidades base con el factor de la presentación antes de decidir si el stock llegó a 0. El dinero de la meta sigue siendo el total de la línea, no un costo recomputado por unidad.

Recepciones y ventas anuladas o no completadas no entran. El criterio de completada es el mismo que ya usa el reporte de ventas: último estado de la operación completado.

## 4. Qué se ve

El diálogo del estudio, abierto encima del historial, muestra un tramo por inversión, del más reciente al más antiguo:

- Intervalo: fecha de la primera recepción y «agotado el …» o «en curso».
- Cada recepción del tramo: fecha, cantidad en unidades base, costo unitario USD, total USD.
- Meta: suma de esos totales.
- Recaudado: suma USD de las ventas del tramo, con el conteo de unidades vendidas.
- Cumplimiento: `recaudado / meta`, en porcentaje con un decimal. Oculto si el tramo está incompleto; en su lugar, «Recaudado incompleto: hay ventas sin tasa de ese día».
- Al expandir un tramo, cada venta: fecha, cantidad, moneda cobrada, importe en esa moneda, tasa usada y equivalente USD. Así se puede ver por qué 510 CUP no son 510 USD.

No se ofrece un total que sume los tramos entre sí como si fueran una sola inversión. Cada tramo tiene su propio par meta/recaudado.

## 5. Tech stack

Flutter del admin (`ventiq_admin_app`), Dart. Sin dependencias nuevas. Lectura con el cliente Supabase que la pantalla ya usa. Formato de dinero: el mismo `NumberFormat` de la pantalla, con el código USD al lado del importe.

## 6. Commands

Desde `ventiq_admin_app`, en PowerShell:

```
flutter.bat test --no-pub test/estudio_inversion_test.dart
flutter.bat analyze lib/models/estudio_inversion.dart lib/services/estudio_inversion_service.dart lib/screens/estudio_inversion_producto_dialog.dart
```

## 7. Project structure

```
ventiq_admin_app/lib/models/estudio_inversion.dart
    tramos, meta, recaudado y el corte por stock en cero
ventiq_admin_app/lib/services/estudio_inversion_service.dart
    lee recepciones, ventas, precios vigentes por fecha y movimientos de stock
ventiq_admin_app/lib/screens/estudio_inversion_producto_dialog.dart
    la vista
ventiq_admin_app/lib/screens/sales_screen.dart
    el botón en la cabecera del historial cronológico
ventiq_admin_app/test/estudio_inversion_test.dart
tasks/SPEC-estudio-inversion-producto.md
    esta spec
```

`sales_screen.dart` solo gana el botón. El cálculo no se escribe dentro de ese archivo.

## 8. Code style

El corte y el dinero viven en una función pura. La pantalla no decide tasas.

```dart
EstudioInversion estudiarInversion({
  required List<RecepcionInversion> recepciones,
  required List<MovimientoStock> movimientos,
  required List<VentaInversion> ventas,
}) {
  final tramos = partirPorAgotado(recepciones, movimientos);
  return EstudioInversion(
    tramos: [
      for (final tramo in tramos)
        tramo.conVentas(ventasAtribuibles(tramo, ventas)),
    ],
  );
}
```

`cumplimiento` devuelve `null` cuando la meta es 0 o cuando alguna venta del tramo no tiene tasa. El texto de la pantalla sale de ese `null`, no de un 0 inventado.

## 9. Testing strategy

`flutter_test`, sin red. El servicio de lectura no se prueba contra newa en esta fase. Los casos de la función pura:

- El ejemplo de la cerveza: 5.000 × 0,30 = 1.500; 2.000 vendidas en CUP con referencia 0,60 y tasa 850 recaudan 1.200 USD; cumplimiento 0,80.
- La misma venta cobrada en USD suma 1.200 USD y no se divide por la tasa.
- Una segunda recepción con stock todavía positivo se suma a la misma meta.
- Una segunda recepción después de stock 0 abre otro tramo; las ventas posteriores no cambian el 80 % del primero.
- Una venta CUP sin precio USD vigente deja el tramo incompleto y `cumplimiento` en null.
- Una recepción anulada no entra en la meta.
- Una caja y unidades sueltas se comparan en unidades base al medir el cero; el total USD de la línea no se recalcula.

## 10. Boundaries

- Always: la meta y lo recaudado en la misma moneda; la tasa es la de la fecha de la venta; un tramo nuevo solo cuando el stock llegó a 0; el porcentaje ausente cuando falta la tasa.
- Ask first: cualquier SQL nuevo, RPC o tabla; cambiar el historial cronológico; incluir servicios o elaborados que no tienen recepción.
- Never: reescribir ventas, costos o precios históricos; usar la tasa o el precio de hoy para una venta vieja; sumar el CUP cobrado como si fuera USD; presentar un tramo incompleto con un porcentaje.

## 11. Success criteria

- Desde el historial del producto en Tiempo real se abre el estudio, y el historial sigue mostrando lo mismo de antes.
- Quien no puede ver costos no ve el botón.
- El ejemplo de las 5.000 unidades a 0,30 y las 2.000 a 0,60 da 80 % en el test.
- Dos recepciones separadas por un stock en 0 se muestran como dos inversiones, con sus propias metas y sus propios recaudos.
- Una venta en CUP y una en USD del mismo tramo aparecen cada una con su moneda, y el recaudado del tramo está solo en USD.
- Una venta sin tasa de ese día no baja el porcentaje a un número falso.

## 12. Open questions

Ninguna. El 2026-11-16 quedó cerrado que el cero es el stock del producto con todas sus variantes, y que el estudio recorre toda la historia.
