import 'package:flutter/material.dart';
import '../models/order.dart';
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
    final alternateTotal =
        currency == 'USD'
            ? '${item.subtotal.toMoneyString(2)} CUP'
            : usdRate > 0
            ? '${(item.subtotal / usdRate).toMoneyString(2)} USD'
            : null;
    final alternateUnit =
        currency == 'USD'
            ? '${item.precioUnitario.toMoneyString(2)} CUP / $unit'
            : usdRate > 0
            ? '${(item.precioUnitario / usdRate).toMoneyString(2)} USD / $unit aprox.'
            : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 260 ||
            MediaQuery.textScalerOf(context).scale(14) > 18;
        final prices = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatAmount(item.subtotal),
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _accent,
                height: 1.25,
              ),
            ),
            if (usdRate > 0 && alternateTotal != null) ...[
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
                    '${formatAmount(item.precioUnitario)} c/u',
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
            if (usdRate > 0 && alternateUnit != null) ...[
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
