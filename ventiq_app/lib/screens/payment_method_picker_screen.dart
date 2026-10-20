import 'package:flutter/material.dart';

import '../models/payment_method.dart';

/// Pantalla a pantalla completa para elegir un método de pago.
/// Reemplaza el DropdownButton apretado cuando hay varios métodos.
class PaymentMethodPickerScreen extends StatelessWidget {
  final List<PaymentMethod> methods;
  final PaymentMethod? selected;
  final String title;
  final String? subtitle;

  const PaymentMethodPickerScreen({
    super.key,
    required this.methods,
    this.selected,
    this.title = 'Seleccionar método de pago',
    this.subtitle,
  });

  /// Abre la pantalla y devuelve el método elegido, o `null` si cancela.
  static Future<PaymentMethod?> pick(
    BuildContext context, {
    required List<PaymentMethod> methods,
    PaymentMethod? selected,
    String title = 'Seleccionar método de pago',
    String? subtitle,
  }) {
    return Navigator.of(context).push<PaymentMethod>(
      MaterialPageRoute(
        builder:
            (_) => PaymentMethodPickerScreen(
              methods: methods,
              selected: selected,
              title: title,
              subtitle: subtitle,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF4A90E2),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (subtitle != null && subtitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                subtitle!,
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
            ),
          Expanded(
            child:
                methods.isEmpty
                    ? Center(
                      child: Text(
                        'No hay métodos de pago disponibles',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                    : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: methods.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final method = methods[index];
                        final isSelected = selected?.id == method.id;
                        return _PaymentMethodTile(
                          method: method,
                          isSelected: isSelected,
                          onTap: () => Navigator.pop(context, method),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

/// Campo compacto (misma huella visual del antiguo dropdown) que abre el picker.
class PaymentMethodPickerField extends StatelessWidget {
  final List<PaymentMethod> methods;
  final PaymentMethod? value;
  final String hint;
  final ValueChanged<PaymentMethod> onSelected;
  final Color accentColor;
  final String pickerTitle;
  final String? pickerSubtitle;
  final double height;

  const PaymentMethodPickerField({
    super.key,
    required this.methods,
    required this.value,
    required this.onSelected,
    this.hint = 'Seleccionar método de pago',
    this.accentColor = const Color(0xFF4A90E2),
    this.pickerTitle = 'Seleccionar método de pago',
    this.pickerSubtitle,
    this.height = 40,
  });

  Future<void> _openPicker(BuildContext context) async {
    if (methods.isEmpty) return;
    final picked = await PaymentMethodPickerScreen.pick(
      context,
      methods: methods,
      selected: value,
      title: pickerTitle,
      subtitle: pickerSubtitle,
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    final isSpecialCash = value?.id == 999;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openPicker(context),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color:
                  hasValue
                      ? accentColor.withOpacity(0.45)
                      : Colors.grey[300]!,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (hasValue) ...[
                Icon(
                  value!.typeIcon,
                  size: 18,
                  color: isSpecialCash ? Colors.red[700] : Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value!.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSpecialCash ? FontWeight.w600 : FontWeight.w500,
                      color:
                          isSpecialCash ? Colors.red[700] : Colors.black87,
                    ),
                  ),
                ),
                if (isSpecialCash) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'SIN DESC.',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ] else
                Expanded(
                  child: Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ),
              Icon(Icons.chevron_right, color: Colors.grey[600]),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  final PaymentMethod method;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentMethodTile({
    required this.method,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSpecialCash = method.id == 999;
    final Color accent =
        isSpecialCash
            ? Colors.red
            : isSelected
            ? const Color(0xFF10B981)
            : const Color(0xFF4A90E2);
    final Color iconColor =
        isSpecialCash
            ? Colors.red.shade700
            : isSelected
            ? const Color(0xFF059669)
            : const Color(0xFF2563EB);
    final bg =
        isSelected
            ? accent.withOpacity(0.08)
            : isSpecialCash
            ? Colors.red.withOpacity(0.04)
            : Colors.white;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  isSelected
                      ? accent
                      : isSpecialCash
                      ? Colors.red.withOpacity(0.35)
                      : Colors.grey[300]!,
              width: isSelected ? 2 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(method.typeIcon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method.displayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color:
                            isSpecialCash
                                ? Colors.red[800]
                                : const Color(0xFF1F2937),
                      ),
                    ),
                    if (method.descripcion != null &&
                        method.descripcion!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        method.descripcion!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ] else if (isSpecialCash) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Efectivo sin descuento de oferta',
                        style: TextStyle(fontSize: 13, color: Colors.red[600]),
                      ),
                    ],
                  ],
                ),
              ),
              if (isSpecialCash) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'SIN DESC.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? accent : Colors.grey[400],
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
