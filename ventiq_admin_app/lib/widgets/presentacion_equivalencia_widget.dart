import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/product_service.dart';

/// Utilidades para mostrar equivalencias de presentación de un producto.
class PresentacionEquivalenciaHelper {
  PresentacionEquivalenciaHelper._();

  static String resolveBaseName(
    List<Map<String, dynamic>>? presentaciones, {
    String? unidadMedida,
  }) {
    if (presentaciones != null) {
      for (final pres in presentaciones) {
        if (pres['es_base'] == true) {
          return pres['presentacion']?.toString() ?? 'unidad base';
        }
      }
      if (presentaciones.isNotEmpty) {
        return presentaciones.first['presentacion']?.toString() ??
            'unidad base';
      }
    }
    if (unidadMedida != null && unidadMedida.isNotEmpty) return unidadMedida;
    return 'unidad base';
  }

  static Future<void> showEquivalenciasDialog({
    required BuildContext context,
    required int productId,
    String? productName,
    List<Map<String, dynamic>>? productPresentaciones,
    String? unidadMedida,
  }) async {
    final baseName = resolveBaseName(
      productPresentaciones,
      unidadMedida: unidadMedida,
    );

    await showDialog(
      context: context,
      builder: (ctx) => _EquivalenciasDialogContent(
        productId: productId,
        productName: productName,
        unidadBaseNombre: baseName,
      ),
    );
  }
}

/// Botón de información que abre el diálogo de equivalencias.
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
      tooltip: 'Ver equivalencias de cantidades',
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

/// Banner compacto con equivalencias cargadas (para diálogos de cantidad).
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
  List<Map<String, dynamic>> _equivalencias = [];
  bool _isLoading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ProductService.getEquivalenciasPresentacion(
        widget.productId,
      );
      if (mounted) {
        setState(() {
          _equivalencias = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadFailed = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Cargando equivalencias...',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    if (_loadFailed || _equivalencias.isEmpty) {
      return const SizedBox.shrink();
    }

    final baseName = PresentacionEquivalenciaHelper.resolveBaseName(
      widget.productPresentaciones,
      unidadMedida: widget.unidadMedida,
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                'Equivalencias (ref. $baseName)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ..._equivalencias.map((eq) {
            final linea = ProductService.formatEquivalenciaLine(
              presentacionNombre:
                  eq['presentacion'] as String? ?? 'Presentación',
              cantidad: (eq['cantidad'] as num?)?.toDouble() ?? 0,
              unidadBaseNombre: baseName,
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '• $linea',
                style: TextStyle(fontSize: 12, color: Colors.grey[800]),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _EquivalenciasDialogContent extends StatefulWidget {
  final int productId;
  final String? productName;
  final String unidadBaseNombre;

  const _EquivalenciasDialogContent({
    required this.productId,
    this.productName,
    required this.unidadBaseNombre,
  });

  @override
  State<_EquivalenciasDialogContent> createState() =>
      _EquivalenciasDialogContentState();
}

class _EquivalenciasDialogContentState
    extends State<_EquivalenciasDialogContent> {
  List<Map<String, dynamic>> _equivalencias = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ProductService.getEquivalenciasPresentacion(
        widget.productId,
      );
      if (mounted) {
        setState(() {
          _equivalencias = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.swap_horiz, color: AppColors.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.productName != null
                  ? 'Equivalencias — ${widget.productName}'
                  : 'Equivalencias de cantidades',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: _isLoading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Text('Error: $_error', style: const TextStyle(color: Colors.red))
                : _equivalencias.isEmpty
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.info_outline,
                              size: 40, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            'No hay equivalencias configuradas para este producto.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Configúralas en el detalle del producto.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Unidad base: ${widget.unidadBaseNombre}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ..._equivalencias.map((eq) {
                              final linea =
                                  ProductService.formatEquivalenciaLine(
                                presentacionNombre: eq['presentacion']
                                        as String? ??
                                    'Presentación',
                                cantidad:
                                    (eq['cantidad'] as num?)?.toDouble() ?? 0,
                                unidadBaseNombre: widget.unidadBaseNombre,
                              );
                              return Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.grey[300]!),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      linea,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if ((eq['observaciones'] as String?)
                                            ?.isNotEmpty ==
                                        true)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          eq['observaciones'] as String,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
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
