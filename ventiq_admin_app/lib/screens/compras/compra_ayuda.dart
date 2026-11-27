/// Textos de ayuda del módulo Compras.
///
/// Cada campo que dependa de un concepto contable (tasa, base del ajuste,
/// origen de pago, financiado...) trae un ⓘ que abre su explicación con un
/// ejemplo numérico.
///
/// Las definiciones no se inventan: salen de
/// `docs/planes/fondo-inversion/02-contabilidad.md` (convención de tasa y
/// R5 diferencias cambiarias) y de las RPC `fn_fdi_compra_*`
/// (`03a_compra_esquema.sql`, `06b_aterrizaje.sql`).
library;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import 'compras_widgets.dart' show formatearCantidad, formatearImporte;

/// Una explicación de concepto: qué es, cómo se calcula y un ejemplo.
class ConceptoAyuda {
  const ConceptoAyuda({
    required this.titulo,
    required this.queEs,
    this.detalles = const [],
    this.ejemplo,
    this.aviso,
  });

  final String titulo;

  /// Frase de una o dos líneas, en lenguaje de mostrador.
  final String queEs;

  /// Puntos de apoyo: reglas que el usuario necesita saber.
  final List<String> detalles;

  /// Ejemplo con números concretos. Es lo que de verdad desatasca.
  final String? ejemplo;

  /// Advertencia honesta sobre un límite del sistema, si lo hay.
  final String? aviso;
}

/// Icono ⓘ que abre la explicación del concepto.
Widget botonAyuda(ConceptoAyuda concepto, {double tamano = 18}) {
  return Builder(
    builder: (context) => IconButton(
      icon: Icon(Icons.info_outline, size: tamano),
      color: AppColors.textSecondary,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      tooltip: '¿Qué es esto?',
      onPressed: () => mostrarAyuda(context, concepto),
    ),
  );
}

/// Abre el diálogo de ayuda.
Future<void> mostrarAyuda(BuildContext context, ConceptoAyuda concepto) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogoAyuda(concepto: concepto),
  );
}

class _DialogoAyuda extends StatelessWidget {
  const _DialogoAyuda({required this.concepto});

  final ConceptoAyuda concepto;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      title: Row(
        children: [
          const Icon(Icons.help_outline, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              concepto.titulo,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                concepto.queEs,
                style: const TextStyle(fontSize: 13, height: 1.45),
              ),
              for (final d in concepto.detalles)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Icon(
                          Icons.circle,
                          size: 5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          d,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (concepto.ejemplo != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'EJEMPLO',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        concepto.ejemplo!,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (concepto.aviso != null) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        concepto.aviso!,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppColors.warning,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendido'),
        ),
      ],
    );
  }
}

// ===========================================================================
// Conceptos
// ===========================================================================

/// Tasa de la factura: unidades de la moneda de la factura por 1 USD.
///
/// Es la convención que fija `06b_aterrizaje.sql` (`p_tasa_usd`) y la que usa
/// `fn_fdi_reporte_cambiario` para el equivalente a tasa de factura.
const ConceptoAyuda ayudaTasaFactura = ConceptoAyuda(
  titulo: '¿Qué es la tasa de la factura?',
  queEs:
      'Es cuántas unidades de la moneda de la factura equivalen a 1 USD. '
      'El sistema la necesita porque todos los costos de inventario se guardan '
      'en dólares y la factura puede venir en CUP, EUR o USD.',
  detalles: [
    'Si la factura está en USD, la tasa es 1: no hay nada que convertir.',
    'Si está en CUP, el sistema toma la tasa extraoficial configurada para la '
        'tienda y la deja bloqueada.',
    'Si necesitas otra tasa, pulsa el botón de editar: queda congelada en esta '
        'compra y no se recalcula después.',
    'Si está en EUR, escríbela a mano.',
  ],
  ejemplo:
      'Factura de 100.000 CUP con la tasa de la tienda 850 → equivale a '
      '117,65 USD. Esos 117,65 USD son los que se comparan después contra lo '
      'que de verdad costó pagar.',
);

/// Ajustes: costos que no son mercancía pero terminan dentro del costo.
const ConceptoAyuda ayudaAjustes = ConceptoAyuda(
  titulo: '¿Qué va en los ajustes?',
  queEs:
      'Los ajustes son los costos de traer la mercancía: flete, aduana, seguro, '
      'el servicio de la importadora. No son productos, pero se suman al costo '
      'de cada línea para saber cuánto te costó de verdad lo que entró al '
      'almacén.',
  detalles: [
    'Se declaran una vez por compra y el sistema los reparte por cantidad de '
        'unidades cuando llega la mercancía.',
    'El «aterrizado» del documento es la mercancía más estos ajustes; los '
        'cargos de la recepción (importadora) se suman aparte.',
    'El «financiado» es la mercancía más solo los ajustes que paga el fondo.',
    'Si no hay ajustes, el aterrizado es igual a la mercancía.',
  ],
  ejemplo:
      'Compras 100 cajas por 1.000 USD y pagas 150 USD de flete. '
      'Mercancía 1.000 · Ajustes 150 · Aterrizado 1.150 USD. '
      'Cada caja no te costó 10 USD, te costó 11,50 USD.',
);

/// Base de cálculo del importe de un ajuste.
const ConceptoAyuda ayudaBaseAjuste = ConceptoAyuda(
  titulo: 'Cómo se calcula el importe del ajuste',
  queEs:
      'Con la base le dices al sistema cómo convertir el número que escribes en '
      'dinero. Es lo que decide si el valor es un importe entero, un importe por '
      'caja o un porcentaje.',
  detalles: [
    'Importe fijo total: el número es el dinero y ya está (un flete de 150 USD).',
    'Importe por unidad: el número se multiplica por las unidades compradas '
        '(2 USD por caja × 100 cajas = 200 USD).',
    'Porcentaje de la mercancía: el número es un % de la mercancía '
        '(10 % de 1.000 USD = 100 USD).',
  ],
  ejemplo:
      'La importadora cobra 8 % del valor de la factura. Base «Porcentaje», '
      'valor 8, mercancía 1.000 USD → el ajuste son 80,00 USD.',
);

/// Reparto del ajuste entre las líneas.
const ConceptoAyuda ayudaRepartoAjuste = ConceptoAyuda(
  titulo: 'Cómo se reparte el ajuste entre los productos',
  queEs:
      'Un ajuste es un solo importe para toda la compra, pero el costo tiene que '
      'quedar por producto. El sistema lo reparte siempre por cantidad de '
      'unidades: quien recibe más unidades, más ajuste recibe.',
  detalles: [
    'Se usa la cantidad base de cada línea: una caja de 24 cuenta como 24 '
        'unidades.',
    'El residuo de centavos va a la línea de mayor cantidad.',
    'Si la compra se recibe en varias veces, cada recepción recibe solo la '
        'parte proporcional a lo que entró.',
  ],
  ejemplo:
      'Flete de 100 USD entre una línea de 100 unidades y otra de 300 → '
      '25 USD a la primera y 75 USD a la segunda.',
);

/// Quién paga el ajuste.
const ConceptoAyuda ayudaOrigenPago = ConceptoAyuda(
  titulo: 'Quién paga el ajuste',
  queEs:
      'No todos los ajustes salen del mismo bolsillo. En el alta lo decide el '
      'modo de liquidación de la compra: no se elige a mano.',
  detalles: [
    'Fondo: lo paga la empresa y entra en el «financiado».',
    'Inversores: el ajuste queda como externo; capitaliza al costo pero no sale '
        'del fondo.',
    'En la recepción, el cargo de la importadora tampoco puede pagarse con el '
        'fondo: se declara wallet de la importadora o externo.',
  ],
  ejemplo:
      'Mercancía 1.000 USD con un flete de 150 USD pagado por el fondo: '
      'financiado 1.150 y aterrizado 1.150. '
      'Si ese flete lo paga la importadora: financiado 1.000 y aterrizado 1.150.',
);

/// Cómo leer el panel de costo aterrizado del detalle.
const ConceptoAyuda ayudaCostoAterrizado = ConceptoAyuda(
  titulo: 'Cómo leer el costo aterrizado',
  queEs:
      'Es lo que de verdad te costó lo recibido. Se arma sumando tres cosas '
      'distintas; ninguna se suma dos veces.',
  detalles: [
    'Valor recibido: la factura de lo que entró.',
    'Cargo de importadora: el servicio de la importadora, ya neto. Si no hubo '
        'devolución, el bruto coincide con el neto y NO se suma aparte.',
    'Ajustes aplicados: flete, seguro, aduana… repartidos por cantidad sobre lo '
        'recibido. «Por asignar» es lo que falta recibir.',
    'Total aterrizado = valor recibido + cargo neto + ajustes aplicados.',
  ],
  ejemplo:
      'Factura recibida 1.334,55 + importadora 40,04 + seguro 700 = 2.074,59 USD. '
      'El bruto 40,04 no se suma otra vez.',
  aviso:
      'Si la compra se recibe en varias veces, «por asignar» baja hasta 0 '
      'cuando entra todo.',
);

/// Mercancía, financiado y aterrizado: las cuatro cifras.
const ConceptoAyuda ayudaCifrasCompra = ConceptoAyuda(
  titulo: 'Las cuatro cifras de la compra',
  queEs:
      'Son cuatro números distintos y nunca se suman entre ellos. Cada uno '
      'responde a una pregunta diferente sobre el mismo documento.',
  detalles: [
    'Mercancía: cantidad × costo unitario de todas las líneas.',
    'Ajustes: la suma de los costos de traerla (flete, aduana, importadora...).',
    'Financiado: lo que tiene que poner el fondo. Mercancía + ajustes pagados '
        'por el fondo.',
    'Aterrizado del documento: mercancía + ajustes declarados. Los cargos de '
        'la recepción (importadora) se suman en el panel «Costo aterrizado».',
  ],
  ejemplo:
      'Mercancía 1.000 · Ajustes 150 (de ellos 100 del fondo) → '
      'Financiado 1.100 · Aterrizado 1.150 USD.',
);

/// Modo de liquidación.
const ConceptoAyuda ayudaModoLiquidacion = ConceptoAyuda(
  titulo: 'Fondo o inversores',
  queEs:
      'Decide de dónde sale el dinero para pagarle al proveedor. Es excluyente: '
      'una compra se paga con uno u otro, nunca con los dos a medias.',
  detalles: [
    'Fondo: se reserva y se paga con las cuentas de la empresa.',
    'Inversores: el total se cubre con aportes de inversores, y el fondo no se '
        'toca.',
    'Se elige al crear la compra; después ya no se cambia.',
  ],
  ejemplo:
      'Una compra de 5.000 USD en modo inversores no descuenta ni un centavo de '
      'las cuentas de la empresa: registra aportes por 5.000 USD.',
);

/// Política de pago.
const ConceptoAyuda ayudaPoliticaPago = ConceptoAyuda(
  titulo: 'Cuándo se le paga al proveedor',
  queEs:
      'Es el acuerdo con el proveedor: pagar de una vez al hacer la orden, o '
      'pagar cuando llegue la mercancía.',
  detalles: [
    'Al pagar: el pago se hace junto con la compra.',
    'Por recepción: el pago espera a que se recepcione la mercancía.',
    'No cambia los importes: cambia el momento en que sale el dinero.',
  ],
);

/// Moneda del total.
const ConceptoAyuda ayudaMonedaFactura = ConceptoAyuda(
  titulo: 'Moneda de la factura',
  queEs:
      'Es la moneda en la que el proveedor emitió la factura. Los importes de '
      'las líneas y de los ajustes se escriben en esa misma moneda.',
  detalles: [
    'Si cambias de moneda, revisa los costos: no se convierten solos.',
    'La tasa de la factura solo hace falta cuando la moneda no es USD.',
    'El total de la compra vive en esta moneda; el fondo puede pagarla con '
        'cuentas de otra, con su propia tasa.',
  ],
);

/// Líneas de compra: cantidad y costo unitario.
const ConceptoAyuda ayudaLineasCompra = ConceptoAyuda(
  titulo: 'Las líneas de la compra',
  queEs:
      'Cada línea es un producto con la cantidad que compraste y el costo '
      'unitario pactado. El costo de la línea lo calcula el sistema y no se '
      'edita: es cantidad × costo unitario.',
  detalles: [
    'El costo unitario es lo que pagas por UNA unidad, no por el lote.',
    'Si compras 12 cajas por 120 USD, el costo unitario es 10, no 120.',
    'Después, al recepcionar, se compara lo pedido con lo que llegó.',
  ],
  ejemplo:
      '3 líneas de 10, 20 y 5 unidades a 2, 3 y 4 USD → '
      'costo de línea 20, 60 y 20; mercancía 100 USD.',
);

// ===========================================================================
// Explicación de un ajuste en una frase
// ===========================================================================

/// Cómo se llama al que paga, en palabras de mostrador.
String quienPagaAjuste(String origenPago) => switch (origenPago) {
  'fondo' => 'lo paga el fondo (entra en el financiado)',
  'wallet_importadora' => 'lo paga la wallet de importadora',
  'wallet_proveedor' => 'lo asume el proveedor',
  _ => 'se pagó por fuera del fondo',
};

/// Resume un ajuste en una frase con la cuenta hecha: qué se multiplicó, cuánto
/// da y quién lo paga.
///
/// Es pura y no toca la red: el importe ya viene calculado con
/// `montoAjusteCompra`, así que aquí solo se redacta.
///
/// Ejemplos:
/// - `10 % de 1.000,00 = 100,00 USD y lo paga el fondo (entra en el financiado).`
/// - `2 × 100 unidades = 200,00 USD y lo paga la wallet de importadora.`
/// - `importe fijo 150,00 USD y lo paga el fondo (entra en el financiado).`
String explicacionAjusteCompra({
  required String base,
  required double valor,
  required double monto,
  required double mercancia,
  required double cantidad,
  required String moneda,
  required String origenPago,
}) {
  final valorTexto = formatearCantidad(valor);
  final importe = formatearImporte(monto);
  final quien = quienPagaAjuste(origenPago);

  final como = switch (base) {
    'porcentaje' =>
      '$valorTexto % de ${formatearImporte(mercancia)} = $importe',
    'unidad' =>
      '$valorTexto × ${formatearCantidad(cantidad)} '
          '${cantidad == 1 ? 'unidad' : 'unidades'} = $importe',
    _ => 'importe fijo $importe',
  };

  return 'Cuesta $como $moneda y $quien.';
}
