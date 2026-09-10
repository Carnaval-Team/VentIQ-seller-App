import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/presentacion_cadena_service.dart';

class PresentacionEquivalenciaHelper {
  PresentacionEquivalenciaHelper._();

  static PresentacionCadena? presentacionBase(
    List<PresentacionCadena> presentaciones,
  ) {
    for (final presentacion in presentaciones) {
      if (presentacion.esBase) return presentacion;
    }
    return presentaciones.isEmpty ? null : presentaciones.first;
  }

  static Future<void> showEquivalenciasDialog({
    required BuildContext context,
    required int productId,
    String? productName,
    List<Map<String, dynamic>>? productPresentaciones,
    String? unidadMedida,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _EquivalenciasDialogContent(
        productId: productId,
        productName: productName,
      ),
    );
  }
}

class PresentacionEquivalenciaIconButton extends StatelessWidget {
  final int productId;
  final String? productName;
  final List<Map<String, dynamic>>? productPresentaciones;
  final String? unidadMedida;
  final double iconSize;
  final EdgeInsets? padding;

  const PresentacionEquivalenciaIconButton({
    super.key,
    required this.productId,
    this.productName,
    this.productPresentaciones,
    this.unidadMedida,
    this.iconSize = 20,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: padding ?? EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      tooltip: 'Ver factores de empaque',
      icon: Icon(Icons.info_outline, size: iconSize, color: AppColors.primary),
      onPressed: () => PresentacionEquivalenciaHelper.showEquivalenciasDialog(
        context: context,
        productId: productId,
        productName: productName,
        productPresentaciones: productPresentaciones,
        unidadMedida: unidadMedida,
      ),
    );
  }
}

class PresentacionEquivalenciaBanner extends StatefulWidget {
  final int productId;
  final List<Map<String, dynamic>>? productPresentaciones;
  final String? unidadMedida;

  const PresentacionEquivalenciaBanner({
    super.key,
    required this.productId,
    this.productPresentaciones,
    this.unidadMedida,
  });

  @override
  State<PresentacionEquivalenciaBanner> createState() =>
      _PresentacionEquivalenciaBannerState();
}

class _PresentacionEquivalenciaBannerState
    extends State<PresentacionEquivalenciaBanner> {
  List<PresentacionCadena> _presentaciones = const [];
  bool _isLoading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forzarRecarga = false}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final list = await PresentacionCadenaService.cadena(
        widget.productId,
        forzarRecarga: forzarRecarga,
      );
      if (mounted) setState(() => _presentaciones = list);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_error != null) {
      return _ErrorEquivalencias(onRetry: () => _load(forzarRecarga: true));
    }
    if (_presentaciones.isEmpty) return const SizedBox.shrink();

    final base = PresentacionEquivalenciaHelper.presentacionBase(
      _presentaciones,
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Presentaciones y factores de empaque',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          ..._presentaciones.map(
            (presentacion) => Text(
              '• ${_factorLine(presentacion, base)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }
}

class _EquivalenciasDialogContent extends StatefulWidget {
  final int productId;
  final String? productName;

  const _EquivalenciasDialogContent({
    required this.productId,
    this.productName,
  });

  @override
  State<_EquivalenciasDialogContent> createState() =>
      _EquivalenciasDialogContentState();
}

class _EquivalenciasDialogContentState
    extends State<_EquivalenciasDialogContent> {
  List<PresentacionCadena> _presentaciones = const [];
  bool _isLoading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forzarRecarga = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await PresentacionCadenaService.cadena(
        widget.productId,
        forzarRecarga: forzarRecarga,
      );
      if (mounted) setState(() => _presentaciones = data);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = PresentacionEquivalenciaHelper.presentacionBase(
      _presentaciones,
    );
    return AlertDialog(
      title: Text(
        widget.productName == null
            ? 'Presentaciones y factores de empaque'
            : 'Presentaciones — ${widget.productName}',
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 380,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorEquivalencias(onRetry: () => _load(forzarRecarga: true))
            : _presentaciones.isEmpty
            ? const Text(
                'Este producto no tiene presentaciones configuradas.',
                textAlign: TextAlign.center,
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: _presentaciones.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (_, index) {
                  final presentacion = _presentaciones[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(presentacion.nombre),
                    subtitle: Text(_factorLine(presentacion, base)),
                    trailing: presentacion.esFraccionable
                        ? const Chip(label: Text('Fraccionable'))
                        : null,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _ErrorEquivalencias extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorEquivalencias({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Text('No se pudieron cargar los factores.')),
        TextButton(onPressed: onRetry, child: const Text('Reintentar')),
      ],
    );
  }
}

String _factorLine(PresentacionCadena presentacion, PresentacionCadena? base) {
  if (presentacion.esBase) return 'Presentación base';
  final factor = _formatFactor(presentacion.factorRel);
  final baseName = base?.nombre ?? 'unidad base';
  final fraccionable = presentacion.esFraccionable ? ' · Fraccionable' : '';
  return '1 ${presentacion.nombre} = $factor $baseName$fraccionable';
}

String _formatFactor(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(4)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
