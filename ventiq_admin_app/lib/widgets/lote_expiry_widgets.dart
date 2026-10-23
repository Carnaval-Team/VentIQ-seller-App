import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/lote_stock.dart';

Color loteEstadoColor(String estado) {
  switch (estado) {
    case 'expired':
      return Colors.red.shade700;
    case 'expiring':
      return Colors.amber.shade800;
    case 'ok':
      return Colors.green.shade700;
    default:
      return AppColors.textSecondary;
  }
}

String loteEstadoLabel(String estado) {
  switch (estado) {
    case 'expired':
      return 'Vencido';
    case 'expiring':
      return 'Por vencer';
    case 'ok':
      return 'OK';
    default:
      return 'Sin lote';
  }
}

class LoteEstadoChip extends StatelessWidget {
  final String estado;
  final String? customLabel;

  const LoteEstadoChip({super.key, required this.estado, this.customLabel});

  @override
  Widget build(BuildContext context) {
    final color = loteEstadoColor(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        customLabel ?? loteEstadoLabel(estado),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Línea compacta para subtítulos de listas.
class LoteExpirySubtitle extends StatelessWidget {
  final List<LoteStockInfo> lotes;

  const LoteExpirySubtitle({super.key, required this.lotes});

  @override
  Widget build(BuildContext context) {
    if (lotes.isEmpty) return const SizedBox.shrink();

    // FEFO: siempre la fecha de vencimiento más próxima (no el orden de ingreso).
    final proximo = LoteStockInfo.proximoAVencer(lotes)!;
    final total = lotes.fold<double>(0, (s, l) => s + l.cantidadFinal);
    final totalTxt = total == total.roundToDouble()
        ? total.toStringAsFixed(0)
        : total.toStringAsFixed(2);

    final text = lotes.length == 1
        ? proximo.resumenCorto
        : '${lotes.length} saldos · total $totalTxt · próximo ${proximo.fechaLabel}';

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(
            Icons.event_available,
            size: 14,
            color: loteEstadoColor(proximo.estadoCaducidad),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: loteEstadoColor(proximo.estadoCaducidad),
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (proximo.estadoCaducidad == 'expired' ||
              proximo.estadoCaducidad == 'expiring') ...[
            const SizedBox(width: 4),
            LoteEstadoChip(estado: proximo.estadoCaducidad),
          ],
        ],
      ),
    );
  }
}

/// Lista de lotes para detalle / diálogo.
class LoteExpiryList extends StatelessWidget {
  final List<LoteStockInfo> lotes;
  final bool showUbicacion;
  final bool showPresentacion;
  final Map<int, String>? presentacionLabels;
  final String? emptyMessage;
  /// Gerente/supervisor: asignar código+fecha a filas `sin_lote`.
  final ValueChanged<LoteStockInfo>? onAssignSinLote;

  const LoteExpiryList({
    super.key,
    required this.lotes,
    this.showUbicacion = false,
    this.showPresentacion = false,
    this.presentacionLabels,
    this.emptyMessage,
    this.onAssignSinLote,
  });

  String _qty(double n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    if (lotes.isEmpty) {
      return Text(
        emptyMessage ?? 'Sin lotes con stock en esta ubicación',
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey[600],
          fontStyle: FontStyle.italic,
        ),
      );
    }

    // Deduplicar por identidad de saldo (evita listar 2× el mismo lote).
    final seen = <String>{};
    final unique = <LoteStockInfo>[];
    for (final l in LoteStockInfo.ordenadosFefo(lotes)) {
      final id =
          '${l.idProducto}|${l.idUbicacion}|${l.idVariante}|${l.idOpcionVariante}|${l.idPresentacion}|${l.idLote}';
      if (seen.add(id)) unique.add(l);
    }

    // Agrupar por presentación cuando hay varias.
    final byPres = <int?, List<LoteStockInfo>>{};
    for (final l in unique) {
      byPres.putIfAbsent(l.idPresentacion, () => []).add(l);
    }
    final multiPres = showPresentacion && byPres.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in byPres.entries) ...[
          if (multiPres) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text(
                presentacionLabels?[entry.key] ??
                    (entry.key == null
                        ? 'Sin presentación'
                        : 'Presentación #${entry.key}'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
          ...entry.value.map((lote) {
            final color = loteEstadoColor(lote.estadoCaducidad);
            final presLabel = presentacionLabels?[lote.idPresentacion];
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.qr_code_2, size: 16, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          lote.codigoLote.isEmpty
                              ? 'Sin código'
                              : lote.codigoLote,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${_qty(lote.cantidadFinal)} uds',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 6),
                      LoteEstadoChip(estado: lote.estadoCaducidad),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      if (showPresentacion &&
                          !multiPres &&
                          (presLabel?.isNotEmpty ?? false))
                        _meta(Icons.layers_outlined, presLabel!),
                      if (lote.estadoCaducidad != 'sin_lote')
                        _meta(Icons.event, 'Vence ${lote.fechaLabel}'),
                      if (lote.diasRestantes != null)
                        _meta(
                          Icons.timelapse,
                          lote.diasRestantes! < 0
                              ? 'Hace ${-lote.diasRestantes!}d'
                              : '${lote.diasRestantes}d restantes',
                        ),
                      if (showUbicacion &&
                          (lote.ubicacionLabel?.isNotEmpty ?? false))
                        _meta(
                          Icons.location_on_outlined,
                          lote.ubicacionLabel!,
                        ),
                    ],
                  ),
                  if (onAssignSinLote != null &&
                      lote.esPorLotes &&
                      lote.estadoCaducidad == 'sin_lote' &&
                      lote.cantidadFinal > 0) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => onAssignSinLote!(lote),
                        icon: const Icon(Icons.qr_code_2, size: 16),
                        label: const Text('Asignar lote'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Sección con título para embeber en cards/diálogos.
class LoteExpirySection extends StatelessWidget {
  final List<LoteStockInfo> lotes;
  final bool showUbicacion;
  final bool showPresentacion;
  final Map<int, String>? presentacionLabels;
  final String title;
  final bool isLoading;
  final ValueChanged<LoteStockInfo>? onAssignSinLote;

  const LoteExpirySection({
    super.key,
    required this.lotes,
    this.showUbicacion = false,
    this.showPresentacion = false,
    this.presentacionLabels,
    this.title = 'Stock por lote',
    this.isLoading = false,
    this.onAssignSinLote,
  });

  @override
  Widget build(BuildContext context) {
    final total = lotes.fold<double>(0, (s, l) => s + l.cantidadFinal);
    final totalTxt = total == total.roundToDouble()
        ? total.toStringAsFixed(0)
        : total.toStringAsFixed(2);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.event_available,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (lotes.isNotEmpty)
                Text(
                  'Total $totalTxt',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            LoteExpiryList(
              lotes: lotes,
              showUbicacion: showUbicacion,
              showPresentacion: showPresentacion,
              presentacionLabels: presentacionLabels,
              onAssignSinLote: onAssignSinLote,
            ),
        ],
      ),
    );
  }
}
