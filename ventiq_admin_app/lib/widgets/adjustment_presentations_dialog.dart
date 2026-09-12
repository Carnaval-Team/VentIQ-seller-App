import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_colors.dart';
import '../services/presentacion_cadena_service.dart';
import '../utils/stock_mixto_formatter.dart';

class AdjustmentPresentationItem {
  final int? idPresentacion;
  final String nombre;
  final double stockActual;
  final PresentacionCadena? cadena;

  const AdjustmentPresentationItem({
    required this.idPresentacion,
    required this.nombre,
    required this.stockActual,
    this.cadena,
  });
}

class AdjustmentPresentationValue {
  final AdjustmentPresentationItem item;
  final double cantidad;

  const AdjustmentPresentationValue({
    required this.item,
    required this.cantidad,
  });
}

class AdjustmentPresentationsDialog extends StatefulWidget {
  final String productName;
  final bool isExcess;
  final String stockSummary;
  final List<AdjustmentPresentationItem> presentations;

  const AdjustmentPresentationsDialog({
    super.key,
    required this.productName,
    required this.isExcess,
    required this.stockSummary,
    required this.presentations,
  });

  @override
  State<AdjustmentPresentationsDialog> createState() =>
      _AdjustmentPresentationsDialogState();
}

class _AdjustmentPresentationsDialogState
    extends State<AdjustmentPresentationsDialog> {
  final Map<int, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.presentations.length; i++) {
      _controllers[i] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double? _valueAt(int index) {
    final text = _controllers[index]?.text.trim().replaceAll(',', '.');
    if (text == null || text.isEmpty) return null;
    return double.tryParse(text);
  }

  List<AdjustmentPresentationValue> get _values {
    final result = <AdjustmentPresentationValue>[];
    for (var i = 0; i < widget.presentations.length; i++) {
      final value = _valueAt(i);
      if (value != null && value >= 0.01) {
        result.add(
          AdjustmentPresentationValue(
            item: widget.presentations[i],
            cantidad: value,
          ),
        );
      }
    }
    return result;
  }

  String get _baseName {
    for (final item in widget.presentations) {
      if (item.cadena?.esBase == true) return item.cadena!.nombre;
    }
    return 'base';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: widget.presentations.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) => _buildPresentation(index),
              ),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.tune, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.productName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Cada presentación se ajusta de forma independiente. '
                  'Deje vacío lo que no desea ajustar.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                if (widget.stockSummary.trim().isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    'Saldo en la zona: ${widget.stockSummary}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildPresentation(int index) {
    final item = widget.presentations[index];
    final presentation = item.cadena;
    final value = _valueAt(index) ?? 0;
    final result = item.stockActual + (widget.isExcess ? -value : value);
    final equivalence = presentation == null
        ? null
        : presentation.esBase
        ? 'Presentación base'
        : '1 ${presentation.nombre} = '
              '${StockMixtoFormatter.cantidad(presentation.factorRel)} '
              '${StockMixtoFormatter.plural(_baseName, presentation.factorRel)}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = _buildDetails(item, presentation, equivalence);
          final input = _buildInput(index, item.nombre, result, value > 0);
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [details, const SizedBox(height: 12), input],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: details),
              const SizedBox(width: 20),
              SizedBox(width: 300, child: input),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDetails(
    AdjustmentPresentationItem item,
    PresentacionCadena? presentation,
    String? equivalence,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              item.nombre,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            if (presentation?.esBase == true) _chip('Base', AppColors.primary),
            if (presentation != null)
              _chip(
                presentation.esFraccionable ? 'Fraccionable' : 'Enteros',
                presentation.esFraccionable ? Colors.teal : Colors.blueGrey,
              ),
          ],
        ),
        if (equivalence != null) ...[
          const SizedBox(height: 4),
          Text(
            equivalence,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 7),
        Text(
          'Stock actual: ${StockMixtoFormatter.linea(item.stockActual, item.nombre)}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildInput(
    int index,
    String presentationName,
    double result,
    bool hasValue,
  ) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controllers[index],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*[\.,]?\d{0,2}')),
            ],
            decoration: InputDecoration(
              labelText: widget.isExcess
                  ? 'Cantidad a restar'
                  : 'Cantidad a sumar',
              hintText: 'Vacío = no ajustar',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 94,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Resultado',
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
              Text(
                hasValue ? StockMixtoFormatter.cantidad(result) : '—',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: !hasValue
                      ? Colors.grey
                      : result >= 0
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                ),
              ),
              Text(
                presentationName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    final values = _values;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              values.isEmpty
                  ? 'No ha seleccionado presentaciones'
                  : '${values.length} presentación(es) para ajustar',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: values.isEmpty
                ? null
                : () => Navigator.of(context).pop(values),
            icon: const Icon(Icons.add_task, size: 18),
            label: const Text('Agregar ajustes'),
          ),
        ],
      ),
    );
  }
}
