import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../models/hr/hr_salary_day.dart';
import '../../models/hr/hr_salary_report.dart';
import '../../services/hr/hr_attendance_service.dart';
import '../../services/hr/hr_salary_report_service.dart';
import 'hr_modalidad_badge.dart';

/// Hoja desplegable con los días trabajados de UN trabajador en el período
/// del reporte de salarios.
///
/// Es la pantalla de corrección de RR.HH.: lista día a día lo que se le pagó
/// (salario base y PPR) y permite editar o quitar el PPR de un día pasado,
/// cambiar el importe de ese día, o eliminar la jornada completa.
///
/// Cada corrección afecta solo a esa jornada: la tarifa configurada al
/// trabajador no se toca.
class HRWorkerSalaryDaysSheet extends StatefulWidget {
  final HRSalaryReportEntry entry;
  final int storeId;
  final String userUuid;
  final DateTime fechaDesde;
  final DateTime fechaHasta;

  /// Se invoca tras cada corrección aplicada, para que el reporte de fondo
  /// se refresque con los nuevos totales.
  final VoidCallback onChanged;

  const HRWorkerSalaryDaysSheet({
    super.key,
    required this.entry,
    required this.storeId,
    required this.userUuid,
    required this.fechaDesde,
    required this.fechaHasta,
    required this.onChanged,
  });

  /// Abre la hoja. Se usa `isScrollControlled` para que el
  /// DraggableScrollableSheet pueda ocupar casi toda la pantalla.
  static Future<void> show(
    BuildContext context, {
    required HRSalaryReportEntry entry,
    required int storeId,
    required String userUuid,
    required DateTime fechaDesde,
    required DateTime fechaHasta,
    required VoidCallback onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HRWorkerSalaryDaysSheet(
        entry: entry,
        storeId: storeId,
        userUuid: userUuid,
        fechaDesde: fechaDesde,
        fechaHasta: fechaHasta,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<HRWorkerSalaryDaysSheet> createState() =>
      _HRWorkerSalaryDaysSheetState();
}

class _HRWorkerSalaryDaysSheetState extends State<HRWorkerSalaryDaysSheet> {
  bool _isLoading = true;
  String? _error;
  HRWorkerSalaryDetail? _detail;

  final _currencyFormat = NumberFormat('#,##0.00');
  // Sin locale: la app no llama a initializeDateFormatting, así que un
  // DateFormat con 'es' lanzaría LocaleDataException al formatear.
  final _dateFormat = DateFormat('dd/MM/yyyy');
  final _timeFormat = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final detail = await HRSalaryReportService.getWorkerSalaryDetail(
        storeId: widget.storeId,
        workerId: widget.entry.trabajadorId,
        fechaDesde: widget.fechaDesde,
        fechaHasta: widget.fechaHasta,
      );
      if (mounted) {
        setState(() {
          _detail = detail;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _isLoading = false;
        });
      }
    }
  }

  void _snack(String mensaje, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: color),
    );
  }

  // ---------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------

  /// Aplica una corrección y refresca la hoja y el reporte de fondo.
  Future<void> _aplicar({
    required HRSalaryDay dia,
    double? salarioTotal,
    double? cantidad,
    bool? aplicaPPR,
    double? ppr,
    String? motivo,
  }) async {
    try {
      await HRSalaryReportService.updateAttendancePay(
        asistenciaId: dia.asistenciaId,
        storeId: widget.storeId,
        modificadoPor: widget.userUuid,
        salarioTotal: salarioTotal,
        cantidad: cantidad,
        aplicaPPR: aplicaPPR,
        ppr: ppr,
        motivo: motivo,
      );
      _snack('Día actualizado correctamente', AppColors.success);
      widget.onChanged();
      await _loadDetail();
    } catch (e) {
      _snack('Error: $e', AppColors.error);
    }
  }

  /// Quitar el PPR de un día concreto. Atajo de un toque, porque es la
  /// corrección más frecuente de RR.HH.
  Future<void> _quitarPPR(HRSalaryDay dia) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Quitar el PPR de este día?',
            style: TextStyle(fontSize: 17)),
        content: Text(
          'Se le descontarán \$${_currencyFormat.format(dia.pagoPorResultado)} '
          'del día ${dia.horaEntrada != null ? _dateFormat.format(dia.horaEntrada!) : '—'}. '
          'El salario base de ese día no cambia.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sí, quitar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    await _aplicar(
      dia: dia,
      aplicaPPR: false,
      motivo: 'PPR retirado desde el reporte de salarios',
    );
  }

  /// Eliminar la jornada completa. Confirmación en dos pasos, igual que en el
  /// historial de asistencia: es irreversible.
  Future<void> _eliminarDia(HRSalaryDay dia) async {
    final fecha = dia.horaEntrada != null
        ? _dateFormat.format(dia.horaEntrada!)
        : '—';

    final paso1 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final controller = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final coincide =
                controller.text.trim().toUpperCase() == 'ELIMINAR';
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Confirmar eliminación',
                        style: TextStyle(fontSize: 17)),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vas a eliminar el día $fecha de '
                    '${widget.entry.nombreCompleto}. Se descontará '
                    '\$${_currencyFormat.format(dia.totalDia)} del reporte y '
                    'no se puede deshacer.',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  const Text('Escribe ELIMINAR para continuar:',
                      style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'ELIMINAR',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      errorText: controller.text.isNotEmpty && !coincide
                          ? 'Escribe exactamente: ELIMINAR'
                          : null,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: coincide
                      ? () => Navigator.of(ctx).pop(true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.red.withOpacity(0.3),
                  ),
                  child: const Text('Sí, eliminar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (paso1 != true || !mounted) return;

    try {
      await HRAttendanceService.deleteAttendance(
        asistenciaId: dia.asistenciaId,
        eliminadoPor: widget.userUuid,
        storeId: widget.storeId,
      );
      _snack('Día eliminado correctamente', AppColors.success);
      widget.onChanged();
      await _loadDetail();
    } catch (e) {
      _snack('Error al eliminar: $e', AppColors.error);
    }
  }

  /// Abre el editor completo del día (cantidad, salario base y PPR).
  Future<void> _editarDia(HRSalaryDay dia, int numeroDia) async {
    final resultado = await showDialog<_EdicionDia>(
      context: context,
      builder: (ctx) => _HREditarDiaDialog(
        dia: dia,
        numeroDia: numeroDia,
        nombreTrabajador: widget.entry.nombreCompleto,
        pprConfigurado: _detail?.pprConfigurado ?? 0,
      ),
    );
    if (resultado == null) return;
    await _aplicar(
      dia: dia,
      salarioTotal: resultado.salarioTotal,
      cantidad: resultado.cantidad,
      aplicaPPR: resultado.aplicaPPR,
      ppr: resultado.ppr,
      motivo: resultado.motivo,
    );
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(
            children: [
              _buildHandle(),
              _buildHeader(),
              const Divider(height: 1),
              Expanded(child: _buildBody(scrollController)),
            ],
          ),
        );
      },
    );
  }

  /// Asa de arrastre: señal visual de que la hoja se puede expandir.
  Widget _buildHandle() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  /// Cabecera: quién es, con qué modalidad cobra y qué acumula en el período.
  Widget _buildHeader() {
    final d = _detail;
    final totalBase = d?.totalBase ?? widget.entry.totalSalarioBase;
    final totalPPR = d?.totalPPR ?? widget.entry.totalPPR;
    final totalGeneral = d?.totalGeneral ?? widget.entry.totalGeneral;
    final cantidadDias = d?.diasCerrados.length ?? 0;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text(
                  widget.entry.nombres.isNotEmpty
                      ? widget.entry.nombres[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.entry.nombreCompleto,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        HRModalidadBadge(
                          tipoSalario: widget.entry.tipoSalario,
                          fontSize: 9,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${widget.entry.rolNombre ?? 'Sin rol'} · '
                            '${_dateFormat.format(widget.fechaDesde)} - '
                            '${_dateFormat.format(widget.fechaHasta)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Cerrar',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _totalChip('$cantidadDias días', Icons.event_available,
                  AppColors.info),
              const SizedBox(width: 8),
              _totalChip('\$${_currencyFormat.format(totalBase)}',
                  Icons.payments, AppColors.primary),
              const SizedBox(width: 8),
              _totalChip('PPR \$${_currencyFormat.format(totalPPR)}',
                  Icons.emoji_events, AppColors.success),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                const Text(
                  'Total del período',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  '\$${_currencyFormat.format(totalGeneral)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalChip(String texto, IconData icono, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 13, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                texto,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ScrollController scrollController) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.error),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loadDetail,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final dias = _detail?.dias ?? [];
    if (dias.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              'Sin jornadas en este período',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Los días cerrados se numeran para que RR.HH. hable el mismo idioma que
    // el trabajador: "el día 3 te pagamos tanto".
    int numero = 0;
    final items = <Widget>[];
    for (final dia in dias) {
      if (!dia.abierta) numero++;
      items.add(_buildDayCard(dia, dia.abierta ? null : numero));
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: items,
    );
  }

  /// Tarjeta de un día: qué se pagó y las acciones para corregirlo.
  Widget _buildDayCard(HRSalaryDay dia, int? numeroDia) {
    final fecha = dia.horaEntrada != null
        ? _dateFormat.format(dia.horaEntrada!)
        : '—';
    final rango = dia.horaEntrada == null
        ? '—'
        : dia.horaSalida == null
            ? 'desde ${_timeFormat.format(dia.horaEntrada!)}'
            : '${_timeFormat.format(dia.horaEntrada!)} - '
                '${_timeFormat.format(dia.horaSalida!)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: dia.abierta
              ? AppColors.warning.withOpacity(0.5)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Línea 1: número de día, fecha, horario y menú de acciones
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: dia.abierta
                        ? AppColors.warning.withOpacity(0.12)
                        : AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: dia.abierta
                      ? const Icon(Icons.hourglass_top,
                          size: 15, color: AppColors.warning)
                      : Text(
                          '$numeroDia',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            fecha,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          HRModalidadBadge(
                            tipoSalario: dia.tipoSalario,
                            fontSize: 8,
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        dia.abierta
                            ? '$rango · jornada abierta'
                            : '$rango · ${dia.cantidadFormatted} '
                                'a ${dia.tarifaFormatted}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildDayMenu(dia, numeroDia),
              ],
            ),
            const SizedBox(height: 8),
            // Línea 2: desglose del importe
            if (dia.abierta)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Sin hora de salida: todavía no tiene pago. Ciérrela en '
                  'Firmar salida para poder corregirla.',
                  style: TextStyle(fontSize: 11, color: AppColors.warning),
                ),
              )
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _importe('Salario', dia.salarioTotal, AppColors.textPrimary),
                    Container(
                      width: 1,
                      height: 26,
                      color: AppColors.border,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    _importe(
                      'PPR',
                      dia.aplicaPagoResultado ? dia.pagoPorResultado : null,
                      dia.aplicaPagoResultado
                          ? AppColors.success
                          : AppColors.textLight,
                    ),
                    Container(
                      width: 1,
                      height: 26,
                      color: AppColors.border,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    _importe('Total', dia.totalDia, AppColors.primary,
                        destacado: true),
                  ],
                ),
              ),
            // Atajo para la corrección más común: quitar el PPR de ese día.
            if (!dia.abierta && dia.aplicaPagoResultado) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _quitarPPR(dia),
                  icon: const Icon(Icons.remove_circle_outline, size: 16),
                  label: const Text('Quitar PPR de este día',
                      style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Una celda del desglose. `null` en el monto significa "no tuvo".
  Widget _importe(String etiqueta, double? monto, Color color,
      {bool destacado = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            etiqueta,
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 1),
          Text(
            monto == null ? '—' : '\$${_currencyFormat.format(monto)}',
            style: TextStyle(
              fontSize: destacado ? 14 : 13,
              fontWeight: destacado ? FontWeight.w700 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayMenu(HRSalaryDay dia, int? numeroDia) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
      tooltip: 'Acciones del día',
      onSelected: (valor) {
        switch (valor) {
          case 'editar':
            _editarDia(dia, numeroDia ?? 0);
            break;
          case 'quitar_ppr':
            _quitarPPR(dia);
            break;
          case 'eliminar':
            _eliminarDia(dia);
            break;
        }
      },
      itemBuilder: (context) => [
        if (!dia.abierta)
          const PopupMenuItem(
            value: 'editar',
            child: Row(
              children: [
                Icon(Icons.edit, size: 18, color: AppColors.primary),
                SizedBox(width: 10),
                Text('Editar pago del día'),
              ],
            ),
          ),
        if (!dia.abierta && dia.aplicaPagoResultado)
          const PopupMenuItem(
            value: 'quitar_ppr',
            child: Row(
              children: [
                Icon(Icons.remove_circle_outline,
                    size: 18, color: AppColors.warning),
                SizedBox(width: 10),
                Text('Quitar PPR'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'eliminar',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.red),
              SizedBox(width: 10),
              Text('Eliminar día', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Lo que el diálogo de edición devuelve. Un campo en `null` significa "no
/// tocar", que es exactamente lo que la RPC interpreta.
class _EdicionDia {
  final double? salarioTotal;
  final double? cantidad;
  final bool? aplicaPPR;
  final double? ppr;
  final String? motivo;

  _EdicionDia({
    this.salarioTotal,
    this.cantidad,
    this.aplicaPPR,
    this.ppr,
    this.motivo,
  });

  bool get sinCambios =>
      salarioTotal == null &&
      cantidad == null &&
      aplicaPPR == null &&
      ppr == null;
}

/// Diálogo de corrección de un día.
///
/// Se edita el TOTAL del día, no la tarifa: es como piensa RR.HH. ("ese día
/// hizo 450 en total"). La tarifa de la jornada la deriva la base de datos.
class _HREditarDiaDialog extends StatefulWidget {
  final HRSalaryDay dia;
  final int numeroDia;
  final String nombreTrabajador;

  /// PPR configurado al trabajador: valor sugerido si el día no tenía ninguno.
  final double pprConfigurado;

  const _HREditarDiaDialog({
    required this.dia,
    required this.numeroDia,
    required this.nombreTrabajador,
    required this.pprConfigurado,
  });

  @override
  State<_HREditarDiaDialog> createState() => _HREditarDiaDialogState();
}

class _HREditarDiaDialogState extends State<_HREditarDiaDialog> {
  late final TextEditingController _cantidadCtrl;
  late final TextEditingController _salarioCtrl;
  late final TextEditingController _pprCtrl;
  final _motivoCtrl = TextEditingController();

  late bool _aplicaPPR;

  final _currencyFormat = NumberFormat('#,##0.00');
  final _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    final d = widget.dia;
    _cantidadCtrl = TextEditingController(text: _num(d.cantidadPagada));
    _salarioCtrl = TextEditingController(text: _num(d.salarioTotal));
    _aplicaPPR = d.aplicaPagoResultado;
    _pprCtrl = TextEditingController(
      text: _num(d.pagoPorResultado > 0
          ? d.pagoPorResultado
          : widget.pprConfigurado),
    );
  }

  @override
  void dispose() {
    _cantidadCtrl.dispose();
    _salarioCtrl.dispose();
    _pprCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  /// Sin decimales innecesarios: '1' en lugar de '1.00'.
  String _num(double v) => v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(2);

  double? _parse(TextEditingController ctrl) {
    final texto = ctrl.text.trim().replaceAll(',', '.');
    if (texto.isEmpty) return null;
    return double.tryParse(texto);
  }

  /// Total del día resultante con lo que hay escrito ahora mismo.
  double get _totalPrevisto {
    final base = _parse(_salarioCtrl) ?? widget.dia.salarioTotal;
    final ppr = _aplicaPPR ? (_parse(_pprCtrl) ?? 0) : 0;
    return base + ppr;
  }

  /// Tarifa que quedará en la jornada: se muestra para que RR.HH. entienda
  /// por qué la columna Tarifa del reporte puede cambiar.
  double? get _tarifaPrevista {
    final base = _parse(_salarioCtrl);
    final cantidad = _parse(_cantidadCtrl);
    if (base == null || cantidad == null || cantidad <= 0) return null;
    return base / cantidad;
  }

  String? get _errorValidacion {
    final cantidad = _parse(_cantidadCtrl);
    if (cantidad == null || cantidad <= 0) {
      return 'Indica una cantidad de '
          '${widget.dia.tipoSalario.unidadPlural} mayor que cero';
    }
    final base = _parse(_salarioCtrl);
    if (base == null || base < 0) {
      return 'Indica un salario válido para el día';
    }
    if (_aplicaPPR) {
      final ppr = _parse(_pprCtrl);
      if (ppr == null || ppr < 0) return 'Indica un PPR válido';
    }
    return null;
  }

  void _guardar() {
    final d = widget.dia;
    final cantidad = _parse(_cantidadCtrl);
    final base = _parse(_salarioCtrl);
    final ppr = _parse(_pprCtrl);

    // Solo se envía lo que realmente cambió: así la RPC no reescribe
    // (ni audita) campos intactos.
    final resultado = _EdicionDia(
      cantidad: (cantidad != null && !_igual(cantidad, d.cantidadPagada))
          ? cantidad
          : null,
      salarioTotal: (base != null && !_igual(base, d.salarioTotal))
          ? base
          : null,
      aplicaPPR: _aplicaPPR != d.aplicaPagoResultado ? _aplicaPPR : null,
      ppr: (_aplicaPPR && ppr != null && !_igual(ppr, d.pagoPorResultado))
          ? ppr
          : null,
      motivo: _motivoCtrl.text.trim().isEmpty
          ? 'Corrección desde el reporte de salarios'
          : _motivoCtrl.text.trim(),
    );

    if (resultado.sinCambios) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(resultado);
  }

  bool _igual(double a, double b) => (a - b).abs() < 0.005;

  @override
  Widget build(BuildContext context) {
    final d = widget.dia;
    final error = _errorValidacion;
    final tarifa = _tarifaPrevista;
    final fecha =
        d.horaEntrada != null ? _dateFormat.format(d.horaEntrada!) : '—';

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Día ${widget.numeroDia} · $fecha',
              style: const TextStyle(fontSize: 17)),
          const SizedBox(height: 2),
          Text(
            widget.nombreTrabajador,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: AppColors.textSecondary),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cantidad pagada (horas o días según la modalidad de la jornada)
            TextField(
              controller: _cantidadCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              decoration: InputDecoration(
                labelText: d.tipoSalario.labelCantidadAPagar,
                helperText: d.esPorDia
                    ? 'Un día completo es 1; medio día, 0.5'
                    : 'Ajustar las horas mueve la hora de salida',
                helperMaxLines: 2,
                suffixText: d.tipoSalario.unidadCorta,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            // Total del salario base de ese día
            TextField(
              controller: _salarioCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              decoration: InputDecoration(
                labelText: 'Salario del día (sin PPR)',
                helperText: tarifa == null
                    ? null
                    : 'Queda a \$${_currencyFormat.format(tarifa)}'
                        '${d.tipoSalario.tarifaSufijo} en esta jornada',
                helperMaxLines: 2,
                prefixText: '\$ ',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            // PPR de ese día
            SwitchListTile(
              value: _aplicaPPR,
              onChanged: (v) => setState(() => _aplicaPPR = v),
              title: const Text('Cobra PPR este día',
                  style: TextStyle(fontSize: 14)),
              subtitle: Text(
                _aplicaPPR ? 'Se suma al total del día' : 'No tuvo PPR',
                style: const TextStyle(fontSize: 11),
              ),
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppColors.success,
            ),
            if (_aplicaPPR)
              TextField(
                controller: _pprCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: InputDecoration(
                  labelText: 'Monto del PPR',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _motivoCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Motivo (opcional)',
                hintText: 'Queda en la auditoría de salarios',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 14),
            // Resumen del resultado antes de guardar
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Text('Total del día',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                  const Spacer(),
                  Text(
                    '\$${_currencyFormat.format(_totalPrevisto)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 15, color: AppColors.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: error == null ? _guardar : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
