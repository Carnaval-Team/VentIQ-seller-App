import 'package:flutter/material.dart';
import '../models/order.dart';
import 'package:intl/intl.dart';

class OrderDetailView extends StatelessWidget {
  final Order order;
  final Color statusColor;
  final Widget? carnavalStatus;
  final Widget? paymentBreakdown;
  final Widget actionButtons;
  final Widget? primaryActions;
  final VoidCallback onClose;
  final Map<String, dynamic> discountData;

  const OrderDetailView({
    Key? key,
    required this.order,
    required this.statusColor,
    this.carnavalStatus,
    this.paymentBreakdown,
    required this.actionButtons,
    this.primaryActions,
    required this.onClose,
    required this.discountData,
  }) : super(key: key);

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final hasDiscount = discountData['hasDiscount'] as bool;
    final displayTotal = discountData['finalTotal'] as double? ?? order.total;
    final originalTotal = discountData['originalTotal'] as double? ?? displayTotal;
    final saved = discountData['saved'] as double? ?? 0;
    final label = discountData['label'] as String? ?? '';
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;
    final pad = isWide ? 28.0 : 16.0;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, 20, pad, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Summary bar ──
                _buildSummaryBar(isWide, hasDiscount, displayTotal, originalTotal, saved, label),
                const SizedBox(height: 20),

                if (carnavalStatus != null) ...[
                  const SizedBox(height: 16),
                  carnavalStatus!,
                ],

                if (paymentBreakdown != null) ...[
                  const SizedBox(height: 20),
                  paymentBreakdown!,
                ],

                // ── Products table ──
                const SizedBox(height: 20),
                _buildProductsTable(isWide),
              ],
            ),
          ),
        ),
        _buildBottomToolbar(pad),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SUMMARY BAR
  // ═══════════════════════════════════════════════════════════════
  Widget _buildSummaryBar(
    bool isWide,
    bool hasDiscount,
    double displayTotal,
    double originalTotal,
    double saved,
    String label,
  ) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 20 : 16, vertical: isWide ? 14 : 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: isWide
          ? Row(
              children: [
                _statusChip(),
                const SizedBox(width: 24),
                _summaryItem(
                  '${order.totalItems}',
                  'Producto${order.totalItems != 1 ? 's' : ''}',
                  Icons.shopping_bag_outlined,
                ),
                const SizedBox(width: 24),
                _summaryItem(
                  _formatDate(order.fechaCreacion),
                  'Fecha',
                  Icons.schedule_outlined,
                ),
                if (order.buyerName != null) ...[
                  const SizedBox(width: 24),
                  _summaryItem(
                    order.buyerName!,
                    'Cliente',
                    Icons.person_outline_rounded,
                  ),
                ],
                if (order.buyerPhone != null && order.buyerPhone!.isNotEmpty) ...[
                  const SizedBox(width: 24),
                  _summaryItem(
                    order.buyerPhone!,
                    'Teléfono',
                    Icons.phone_outlined,
                  ),
                ],
                const Spacer(),
                _totalDisplay(hasDiscount, displayTotal, originalTotal, saved),
                if (primaryActions != null) ...[
                  const SizedBox(width: 20),
                  primaryActions!,
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _statusChip(),
                    const Spacer(),
                    _totalDisplay(hasDiscount, displayTotal, originalTotal, saved),
                  ],
                ),
                if (primaryActions != null) ...[
                  const SizedBox(height: 12),
                  primaryActions!,
                ],
              ],
            ),
    );
  }

  Widget _statusChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        order.status.displayName,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: statusColor),
      ),
    );
  }

  Widget _summaryItem(String value, String label, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF9CA3AF)),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w500),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _totalDisplay(bool hasDiscount, double displayTotal, double originalTotal, double saved) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasDiscount)
          Text(
            '\$${originalTotal.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 11, color: Color(0xFFD1D5DB), decoration: TextDecoration.lineThrough),
          ),
        Text(
          '\$${displayTotal.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: hasDiscount ? const Color(0xFF059669) : const Color(0xFF111827),
            letterSpacing: -0.3,
          ),
        ),
        if (hasDiscount)
          Text(
            '-\$${saved.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFDC2626)),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  PRODUCTS — table inside one card
  // ═══════════════════════════════════════════════════════════
  Widget _buildProductsTable(bool isWide) {
    final items = order.items.where((i) => i.subtotal > 0).toList();

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: _sectionLabel('Productos (${items.length})', Icons.inventory_2_outlined),
          ),
          Divider(height: 1, color: Colors.grey[200]),
          // Column headers
          Container(
            color: const Color(0xFFF9FAFB),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  flex: isWide ? 5 : 6,
                  child: const Text('Producto', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
                ),
                if (isWide)
                  const Expanded(
                    flex: 3,
                    child: Text('Almacén', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
                  ),
                const Expanded(
                  flex: 1,
                  child: Text('Cant.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
                ),
                const Expanded(
                  flex: 2,
                  child: Text('Total', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),
          // Rows
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            return Column(
              children: [
                _buildProductRow(item, isWide),
                if (item.ingredientes != null && item.ingredientes!.isNotEmpty)
                  _buildIngredientRow(item),
                if (i < items.length - 1)
                  Divider(height: 1, color: Colors.grey[100]),
              ],
            );
          }),
          // Summary row
          Divider(height: 1, color: Colors.grey[200]),
          Container(
            color: const Color(0xFFF9FAFB),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  '${items.length} producto${items.length != 1 ? 's' : ''}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                ),
                const Spacer(),
                const Text(
                  'Subtotal',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                ),
                const SizedBox(width: 12),
                Text(
                  '\$${items.fold<double>(0, (sum, i) => sum + i.subtotal).toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF4A90E2)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductRow(OrderItem item, bool isWide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: isWide ? 5 : 6,
            child: Text(
              item.nombre,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF111827)),
            ),
          ),
          if (isWide)
            Expanded(
              flex: 3,
              child: Text(
                item.ubicacionAlmacen,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ),
          Expanded(
            flex: 1,
            child: Text(
              '${item.cantidad}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF374151)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '\$${item.subtotal.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF4A90E2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientRow(OrderItem item) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.restaurant, size: 12, color: Colors.orange[700]),
              const SizedBox(width: 4),
              Text('Ingredientes:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange[800])),
            ],
          ),
          ...item.ingredientes!.map((ing) => Text(
            '${ing['nombre_ingrediente']} (${ing['cantidad_vendida']} ${ing['unidad_medida'] ?? 'und'})',
            style: TextStyle(fontSize: 11, color: Colors.orange[900]),
          )),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  BOTTOM TOOLBAR
  // ═══════════════════════════════════════════════════════════
  Widget _buildBottomToolbar(double horizontalPad) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      padding: EdgeInsets.symmetric(horizontal: horizontalPad, vertical: 12),
      child: SafeArea(
        top: false,
        child: actionButtons,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════
  Widget _sectionLabel(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6B7280)),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
        ),
      ],
    );
  }

}
