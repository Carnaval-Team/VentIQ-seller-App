import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/cocina.dart';
import '../../services/cocina_service.dart';
import '../../services/tpv_service.dart';

/// Diálogo para ligar una cocina con los TPVs que pueden enviarle pedidos.
///
/// Es la relación N:M del plan: un TPV puede mandar a varias cocinas y una
/// cocina puede atender a varios TPVs. Se muestra desde la tarjeta de la cocina
/// (perspectiva "quién me manda pedidos").
///
/// Se marcan/desmarcan varios y se guarda una sola vez; el servicio calcula el
/// diff para no borrar y recrear vínculos que no cambiaron.
class CocinaTpvDialog {
  static Future<void> mostrar({
    required BuildContext context,
    required Cocina cocina,
    required VoidCallback onSuccess,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _CocinaTpvSheet(cocina: cocina, onSuccess: onSuccess),
    );
  }
}

class _CocinaTpvSheet extends StatefulWidget {
  const _CocinaTpvSheet({required this.cocina, required this.onSuccess});

  final Cocina cocina;
  final VoidCallback onSuccess;

  @override
  State<_CocinaTpvSheet> createState() => _CocinaTpvSheetState();
}

class _CocinaTpvSheetState extends State<_CocinaTpvSheet> {
  List<Map<String, dynamic>> _tpvs = [];
  late Set<int> _seleccionados;
  late Set<int> _iniciales;

  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _iniciales = widget.cocina.tpvs.map((t) => t.id).toSet();
    _seleccionados = {..._iniciales};
    _cargarTpvs();
  }

  Future<void> _cargarTpvs() async {
    try {
      final tpvs = await TpvService.getTpvsByStore();
      if (!mounted) return;
      setState(() {
        _tpvs = tpvs;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los TPVs: $e';
        _cargando = false;
      });
    }
  }

  bool get _huboCambios =>
      _seleccionados.length != _iniciales.length ||
      !_seleccionados.containsAll(_iniciales);

  Future<void> _guardar() async {
    if (!_huboCambios) {
      Navigator.pop(context);
      return;
    }

    setState(() => _guardando = true);
    try {
      await CocinaService.sincronizarCocinasDeTpvPorCocina(
        idCocina: widget.cocina.id,
        idsTpvsDeseados: _seleccionados,
        idsTpvsActuales: _iniciales,
      );

      if (!mounted) return;
      Navigator.pop(context);

      final agregados = _seleccionados.difference(_iniciales).length;
      final quitados = _iniciales.difference(_seleccionados).length;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensajeResultado(agregados, quitados)),
          backgroundColor: AppColors.success,
        ),
      );
      widget.onSuccess();
    } on CocinaException catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.mensaje), backgroundColor: AppColors.error),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error inesperado: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _mensajeResultado(int agregados, int quitados) {
    final partes = <String>[];
    if (agregados > 0) {
      partes.add('$agregados ${agregados == 1 ? "TPV ligado" : "TPVs ligados"}');
    }
    if (quitados > 0) {
      partes.add(
        '$quitados ${quitados == 1 ? "TPV desligado" : "TPVs desligados"}',
      );
    }
    return partes.isEmpty ? 'Sin cambios' : partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      title: _Cabecera(cocina: widget.cocina),
      content: SizedBox(width: 420, child: _buildContenido()),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: (_guardando || _cargando) ? null : _guardar,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          icon: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check, size: 18),
          label: Text(_huboCambios ? 'Guardar cambios' : 'Cerrar'),
        ),
      ],
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 36),
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_tpvs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(
              Icons.point_of_sale_outlined,
              size: 40,
              color: AppColors.textLight,
            ),
            SizedBox(height: 10),
            Text(
              'La tienda no tiene TPVs.\nCrea un TPV antes de ligar cocinas.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Marca los puntos de venta que pueden enviar platos a esta cocina.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _tpvs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (_, i) => _buildFilaTpv(_tpvs[i]),
          ),
        ),
        if (_seleccionados.isEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.25),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: AppColors.warning,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sin ningún TPV ligado, esta cocina no recibirá comandas '
                    'de nadie.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildFilaTpv(Map<String, dynamic> tpv) {
    final id = (tpv['id'] as num).toInt();
    final marcado = _seleccionados.contains(id);
    final almacen = tpv['almacen'] as Map<String, dynamic>?;
    final vendedores = tpv['vendedor'] as List<dynamic>? ?? const [];

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() {
        if (marcado) {
          _seleccionados.remove(id);
        } else {
          _seleccionados.add(id);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: marcado
              ? AppColors.primary.withValues(alpha: 0.07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: marcado
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: marcado,
              activeColor: AppColors.primary,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _seleccionados.add(id);
                } else {
                  _seleccionados.remove(id);
                }
              }),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tpv['denominacion']?.toString() ?? 'TPV $id',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: marcado ? FontWeight.w600 : FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (almacen != null) ...[
                        const Icon(
                          Icons.warehouse_outlined,
                          size: 11,
                          color: AppColors.textLight,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            almacen['denominacion']?.toString() ?? '',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textLight,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (vendedores.isNotEmpty) ...[
                        const Icon(
                          Icons.person_outline,
                          size: 11,
                          color: AppColors.textLight,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${vendedores.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textLight,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (_iniciales.contains(id) && !marcado)
              const Tooltip(
                message: 'Se desligará al guardar',
                child: Icon(Icons.link_off, size: 15, color: AppColors.warning),
              ),
            if (!_iniciales.contains(id) && marcado)
              const Tooltip(
                message: 'Se ligará al guardar',
                child: Icon(Icons.add_link, size: 15, color: AppColors.success),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.cocina});

  final Cocina cocina;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.point_of_sale,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Puntos de venta',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  cocina.denominacion,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
