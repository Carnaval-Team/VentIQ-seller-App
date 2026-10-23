import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/lote_stock.dart';
import '../services/inventory_service.dart';
import '../utils/stock_mixto_formatter.dart';

/// Diálogo para que gerente/supervisor etiqueten stock sin lote
/// (código + fecha de vencimiento).
Future<bool> showAsignarLoteDialog({
  required BuildContext context,
  required LoteStockInfo loteSinLote,
  String? productName,
  String? presentacionLabel,
}) async {
  final codigoController = TextEditingController();
  DateTime? fechaVencimiento;
  String? errorText;
  var submitting = false;

  final qtyTxt = StockMixtoFormatter.cantidad(loteSinLote.cantidadFinal);
  final subtitleParts = <String>[
    if (productName != null && productName.isNotEmpty) productName,
    if (presentacionLabel != null && presentacionLabel.isNotEmpty)
      presentacionLabel,
    if (loteSinLote.ubicacionLabel?.isNotEmpty ?? false)
      loteSinLote.ubicacionLabel!,
    '$qtyTxt uds sin lote',
  ];

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: !submitting,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Asignar lote'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtitleParts.join(' · '),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Se etiquetará todo el stock sin lote de esta presentación '
                    'con el código y la fecha indicados. El total no cambia.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: codigoController,
                    enabled: !submitting,
                    decoration: const InputDecoration(
                      labelText: 'Código de lote *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: submitting
                        ? null
                        : () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: fechaVencimiento ??
                                  DateTime.now().add(const Duration(days: 30)),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              helpText: 'Fecha de vencimiento',
                            );
                            if (picked != null) {
                              setDialogState(() => fechaVencimiento = picked);
                            }
                          },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha de vencimiento *',
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: Icon(Icons.calendar_today, size: 18),
                      ),
                      child: Text(
                        fechaVencimiento == null
                            ? 'Seleccionar fecha'
                            : '${fechaVencimiento!.day.toString().padLeft(2, '0')}/'
                                '${fechaVencimiento!.month.toString().padLeft(2, '0')}/'
                                '${fechaVencimiento!.year}',
                        style: TextStyle(
                          color: fechaVencimiento == null
                              ? Colors.grey
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: submitting
                    ? null
                    : () async {
                        final codigo = codigoController.text.trim();
                        if (codigo.isEmpty) {
                          setDialogState(
                            () => errorText = 'Indique el código de lote',
                          );
                          return;
                        }
                        if (fechaVencimiento == null) {
                          setDialogState(
                            () =>
                                errorText = 'Indique la fecha de vencimiento',
                          );
                          return;
                        }
                        if (loteSinLote.idPresentacion == null ||
                            loteSinLote.idUbicacion == null) {
                          setDialogState(
                            () => errorText =
                                'Falta presentación o ubicación para asignar',
                          );
                          return;
                        }

                        setDialogState(() {
                          submitting = true;
                          errorText = null;
                        });

                        final result =
                            await InventoryService.asignarLoteAStockSinLote(
                          idProducto: loteSinLote.idProducto,
                          idUbicacion: loteSinLote.idUbicacion!,
                          idPresentacion: loteSinLote.idPresentacion!,
                          codigoLote: codigo,
                          fechaVencimiento: fechaVencimiento!,
                          idVariante: loteSinLote.idVariante,
                          idOpcionVariante: loteSinLote.idOpcionVariante,
                          cantidad: loteSinLote.cantidadFinal,
                        );

                        if (!ctx.mounted) return;

                        if (result['status'] == 'success') {
                          Navigator.of(ctx).pop(true);
                          return;
                        }

                        setDialogState(() {
                          submitting = false;
                          errorText = result['message']?.toString() ??
                              'No se pudo asignar el lote';
                        });
                      },
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Asignar'),
              ),
            ],
          );
        },
      );
    },
  );

  codigoController.dispose();
  return ok == true;
}
