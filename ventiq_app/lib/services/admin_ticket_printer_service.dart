import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';

import '../utils/platform_utils.dart';
import 'bluetooth_printer_service.dart';
import 'user_preferences_service.dart';

/// Impresión de tickets admin (recepción, extracción, cuadre, IPV, etc.)
/// Reusa Bluetooth de Caja; en web muestra aviso (sin ESC/POS BT).
class AdminTicketPrinterService {
  static final AdminTicketPrinterService _instance =
      AdminTicketPrinterService._internal();
  factory AdminTicketPrinterService() => _instance;
  AdminTicketPrinterService._internal();

  final _bt = BluetoothPrinterService();
  final _prefs = UserPreferencesService();

  /// Pregunta y, si acepta, imprime un ticket de líneas simples.
  Future<bool> confirmAndPrint(
    BuildContext context, {
    required String title,
    required List<String> lines,
  }) async {
    if (PlatformUtils.isWeb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impresión BT de tickets admin no disponible en web',
            ),
          ),
        );
      }
      return false;
    }

    final should = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Imprimir ticket'),
            content: Text('¿Imprimir "$title" en la impresora Bluetooth?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('No'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Imprimir'),
              ),
            ],
          ),
        ) ??
        false;
    if (!should || !context.mounted) return false;

    return printLines(context, title: title, lines: lines);
  }

  Future<bool> printLines(
    BuildContext context, {
    required String title,
    required List<String> lines,
  }) async {
    if (PlatformUtils.isWeb) return false;

    final device = await _bt.showDeviceSelectionDialog(context);
    if (device == null || !context.mounted) return false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Imprimiendo...')),
          ],
        ),
      ),
    );

    try {
      final connected = await _bt.connectToDevice(device);
      if (!connected) {
        if (context.mounted) Navigator.pop(context);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo conectar a la impresora'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      final bytes = await _buildTicketBytes(title: title, lines: lines);
      final ok = await _bt.writeBytesSafe(bytes, jobName: title);
      await Future.delayed(const Duration(milliseconds: 800));
      await _bt.disconnect();

      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok ? 'Ticket enviado a impresora' : 'Falló la impresión',
            ),
            backgroundColor: ok ? Colors.green : Colors.red,
          ),
        );
      }
      return ok;
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error imprimiendo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      try {
        await _bt.disconnect();
      } catch (_) {}
      return false;
    }
  }

  Future<List<int>> _buildTicketBytes({
    required String title,
    required List<String> lines,
  }) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(PaperSize.mm58, profile);
    final bytes = <int>[];

    final storeId = await _prefs.getIdTienda();
    final email = await _prefs.getUserEmail();

    bytes.addAll(g.reset());
    bytes.addAll(g.text(
      'INVENTTIA CAJA',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    ));
    bytes.addAll(g.text(
      title.toUpperCase(),
      styles: const PosStyles(align: PosAlign.center, bold: true),
    ));
    bytes.addAll(g.hr());
    bytes.addAll(g.text(
      _nowLabel(),
      styles: const PosStyles(align: PosAlign.center, bold: false),
    ));
    if (storeId != null) {
      bytes.addAll(g.text('Tienda #$storeId'));
    }
    if (email != null && email.isNotEmpty) {
      bytes.addAll(g.text(_clip(email, 32)));
    }
    bytes.addAll(g.hr());

    for (final line in lines) {
      for (final chunk in _wrap(line, 32)) {
        bytes.addAll(g.text(chunk));
      }
    }

    bytes.addAll(g.hr());
    bytes.addAll(g.text(
      'Admin Lite / offline',
      styles: const PosStyles(align: PosAlign.center),
    ));
    bytes.addAll(g.feed(2));
    bytes.addAll(g.cut());
    return bytes;
  }

  String _nowLabel() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(n.day)}/${two(n.month)}/${n.year} '
        '${two(n.hour)}:${two(n.minute)}';
  }

  String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';

  List<String> _wrap(String text, int width) {
    if (text.length <= width) return [text];
    final out = <String>[];
    var rest = text;
    while (rest.length > width) {
      out.add(rest.substring(0, width));
      rest = rest.substring(width);
    }
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }

  // --- Builders de líneas por tipo de op ---

  static List<String> receptionLines({
    required String entregadoPor,
    required String recibidoPor,
    required List<Map<String, dynamic>> productos,
    String? proveedor,
    String? observaciones,
  }) {
    final lines = <String>[
      'Entrega: $entregadoPor',
      'Recibe: $recibidoPor',
      if (proveedor != null && proveedor.isNotEmpty) 'Prov: $proveedor',
      if (observaciones != null && observaciones.isNotEmpty)
        'Obs: $observaciones',
      '--- Productos ---',
    ];
    for (final p in productos) {
      lines.add(
        '${p['denominacion'] ?? p['id_producto']} x ${p['cantidad']}',
      );
    }
    return lines;
  }

  static List<String> extractionLines({
    required String autorizadoPor,
    required String motivo,
    required List<Map<String, dynamic>> productos,
    String? observaciones,
  }) {
    return [
      'Autoriza: $autorizadoPor',
      'Motivo: $motivo',
      if (observaciones != null && observaciones.isNotEmpty)
        'Obs: $observaciones',
      '--- Productos ---',
      ...productos.map(
        (p) => '${p['denominacion'] ?? p['id_producto']} x ${p['cantidad']}',
      ),
    ];
  }

  static List<String> transferLines({
    required String origen,
    required String destino,
    required String entregadoPor,
    required List<Map<String, dynamic>> productos,
    String? observaciones,
  }) {
    return [
      'Origen: $origen',
      'Destino: $destino',
      'Entrega: $entregadoPor',
      if (observaciones != null && observaciones.isNotEmpty)
        'Obs: $observaciones',
      '--- Productos ---',
      ...productos.map(
        (p) => '${p['denominacion'] ?? p['id_producto']} x ${p['cantidad']}',
      ),
    ];
  }

  static List<String> adjustmentLines({
    required String producto,
    required double anterior,
    required double nueva,
    required String motivo,
    String? observaciones,
  }) {
    return [
      'Producto: $producto',
      'Antes: $anterior',
      'Ahora: $nueva',
      'Delta: ${nueva - anterior}',
      'Motivo: $motivo',
      if (observaciones != null && observaciones.isNotEmpty)
        'Obs: $observaciones',
    ];
  }

  static List<String> saleAgreementLines({
    required String cliente,
    required String medioPago,
    required double total,
    required List<Map<String, dynamic>> productos,
    String? observaciones,
  }) {
    return [
      if (cliente.isNotEmpty) 'Cliente: $cliente',
      'Pago: $medioPago',
      'Total: \$${total.toStringAsFixed(2)}',
      if (observaciones != null && observaciones.isNotEmpty)
        'Obs: $observaciones',
      '--- Productos ---',
      ...productos.map((p) {
        final qty = (p['cantidad'] as num?)?.toDouble() ?? 0;
        final price = (p['precio_unitario'] as num?)?.toDouble() ?? 0;
        return '${p['denominacion'] ?? p['id_producto']} '
            'x $qty @ \$${price.toStringAsFixed(2)}';
      }),
    ];
  }

  static List<String> cuadreLines({
    required Map<String, dynamic> turno,
    required Map<String, dynamic> cuadre,
  }) {
    String money(dynamic v) {
      final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
      return '\$${n.toStringAsFixed(2)}';
    }

    return [
      'Apertura: ${turno['fecha_apertura'] ?? '—'}',
      'Cierre: ${turno['fecha_cierre'] ?? '—'}',
      'Status: ${turno['status'] ?? '—'}',
      'Efectivo ini: ${money(cuadre['efectivo_inicial'])}',
      'Ventas: ${money(cuadre['ventas_totales'])}',
      'Efectivo ventas: ${money(cuadre['total_efectivo'])}',
      'Transfer: ${money(cuadre['total_transferencias'])}',
      'Egresos ef: ${money(cuadre['egresos_efectivo'])}',
      'Egresos dig: ${money(cuadre['egresos_digitales'])}',
      'Esperado: ${money(cuadre['efectivo_esperado'])}',
      if (cuadre['efectivo_final'] != null)
        'Final: ${money(cuadre['efectivo_final'])}',
      if (cuadre['diferencia'] != null)
        'Diferencia: ${money(cuadre['diferencia'])}',
    ];
  }

  static List<String> ipvLines(List<Map<String, dynamic>> products) {
    final lines = <String>['Items: ${products.length}', '---'];
    for (final p in products.take(80)) {
      lines.add('${p['denominacion'] ?? p['id']}: ${p['cantidad'] ?? 0}');
    }
    if (products.length > 80) {
      lines.add('... +${products.length - 80} más');
    }
    return lines;
  }
}
