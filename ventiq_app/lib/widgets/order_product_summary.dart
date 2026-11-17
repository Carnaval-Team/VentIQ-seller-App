import 'package:flutter/material.dart';
import '../models/order.dart';
import '../money/ticket_v1.dart';
import '../services/moneda_venta_service.dart';
import '../utils/price_utils.dart';

class OrderProductSummary extends StatelessWidget {
  final OrderItem item;
  final String Function(double) formatAmount;
  final String currency;
  final double usdRate;
  final bool showSku;

  const OrderProductSummary({
    super.key,
    required this.item,
    required this.formatAmount,
    required this.currency,
    required this.usdRate,
    this.showSku = false,
  });

  static const _accent = Color(0xFF1D4ED8);
  static const _ink = Color(0xFF0F172A);
  static const _secondary = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    final quantity = PriceUtils.formatQuantity(item.cantidad);
    final presentation = item.presentacionNombre?.trim();
    final unit =
        presentation == null || presentation.isEmpty ? 'unid.' : presentation;
    // Linea v1: `subtotal`/`precioUnitario` ya son nativos de su moneda; el
    // "aprox." es el equivalente CUP de la linea, con la tasa de su snapshot.
    final monedaLinea = item.seleccion?.monedaVenta;
    final String? alternateTotal;
    final String? alternateUnit;
    if (monedaLinea != null && monedaLinea != 'CUP') {
      final cupLinea = TicketV1.equivalenteCupItem(item);
      alternateTotal = '${cupLinea.toMoneyString(2)} CUP';
      alternateUnit =
          item.cantidad > 0
              ? '${(cupLinea / item.cantidad).toMoneyString(2)} CUP / $unit aprox.'
              : null;
    } else if (monedaLinea == 'CUP') {
      alternateTotal =
          usdRate > 0
              ? '${(item.subtotal / usdRate).toMoneyString(2)} USD'
              : null;
      alternateUnit =
          usdRate > 0
              ? '${(item.precioUnitario / usdRate).toMoneyString(2)} USD / $unit aprox.'
              : null;
    } else {
      alternateTotal =
          currency == 'USD'
              ? MonedaVentaService.formatearPrecio(item.subtotal)
              : usdRate > 0
              ? '${(item.subtotal / usdRate).toMoneyString(2)} USD'
              : null;
      alternateUnit =
          currency == 'USD'
              ? '${MonedaVentaService.formatearPrecio(item.precioUnitario)} / $unit'
              : usdRate > 0
              ? '${(item.precioUnitario / usdRate).toMoneyString(2)} USD / $unit aprox.'
              : null;
    }
    final totalLabel =
        monedaLinea != null
            ? '${item.subtotal.toMoneyString(2)} $monedaLinea'
            : formatAmount(item.subtotal);
    final unitLabel =
        monedaLinea != null
            ? '${item.precioUnitario.toMoneyString(2)} $monedaLinea c/u'
            : '${formatAmount(item.precioUnitario)} c/u';

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 260 ||
            MediaQuery.textScalerOf(context).scale(14) > 18;
        final prices = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              totalLabel,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _accent,
                height: 1.25,
              ),
            ),
            if (alternateTotal != null) ...[
              const SizedBox(height: 4),
              Text(
                '≈ $alternateTotal',
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 11, color: _secondary),
              ),
            ],
          ],
        );
        final metadataInset = stacked ? 0.0 : 44.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  label: 'Cantidad: $quantity',
                  child: ExcludeSemantics(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${quantity}x',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 6,
                  child: Text(
                    item.nombre,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                      height: 1.3,
                    ),
                  ),
                ),
                if (!stacked) ...[
                  const SizedBox(width: 12),
                  Flexible(flex: 5, child: prices),
                ],
              ],
            ),
            if (stacked) ...[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: prices),
            ],
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.only(left: metadataInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (item.ubicacionAlmacen.trim().isNotEmpty)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth - metadataInset,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.warehouse_outlined,
                                  size: 13,
                                  color: _secondary,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    item.ubicacionAlmacen,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: _ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (presentation != null && presentation.isNotEmpty)
                        Text(
                          presentation,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _secondary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    unitLabel,
                    style: const TextStyle(fontSize: 12, color: _accent),
                  ),
                  if (showSku && (item.producto.sku?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 6),
                    Text(
                      'SKU: ${item.producto.sku}',
                      style: const TextStyle(fontSize: 12, color: _secondary),
                    ),
                  ],
                  if (showSku &&
                      (item.producto.descripcion?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.producto.descripcion!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _secondary),
                    ),
                  ],
                ],
              ),
            ),
            if (alternateUnit != null) ...[
              const Divider(height: 24, color: Color(0xFFE2E8F0)),
              Text(
                alternateUnit,
                style: const TextStyle(
                  fontSize: 11,
                  color: _secondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
