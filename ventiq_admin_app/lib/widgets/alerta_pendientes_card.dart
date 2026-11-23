import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/recordatorios_calculo.dart';
import '../services/recordatorios_service.dart';
import '../services/user_preferences_service.dart';

/// Tarjeta del inicio con el recordatorio de **compras sin completar**
/// (Fase 9 del módulo Compras).
///
/// Muestra cuántas compras abiertas esperan recepción, la antigüedad de la más
/// vieja (chip naranja si supera el umbral) y el pendiente **por moneda** —
/// nunca una suma entre monedas distintas.
///
/// Es autónoma: resuelve la tienda (por parámetro o desde las preferencias),
/// carga el resumen, dispara la notificación local una vez al día y permite
/// ajustar el umbral desde el propio diálogo.
class AlertaPendientesCard extends StatefulWidget {
  const AlertaPendientesCard({
    super.key,
    this.idTienda,
    this.rutaPendientes,
    this.notificar = true,
    this.servicio,
  });

  /// Tienda a consultar. Si es `null` se usa la guardada en preferencias.
  final int? idTienda;

  /// Ruta de la pantalla de pendientes. Mientras la pantalla no exista se deja
  /// en `null`: el botón se muestra deshabilitado con una nota, en vez de
  /// inventar una ruta.
  final String? rutaPendientes;

  /// Permite desactivar la notificación (pruebas o pantallas secundarias).
  final bool notificar;

  /// Servicio inyectable para pruebas.
  final RecordatoriosService? servicio;

  /// Clave de la tarjeta (para pruebas de widget).
  static const Key claveTarjeta = Key('alerta_pendientes_card');

  @override
  State<AlertaPendientesCard> createState() => _AlertaPendientesCardState();
}

class _AlertaPendientesCardState extends State<AlertaPendientesCard> {
  static const Color _azulSuave = Color(0xFFE7F0FB);
  static const Color _naranjaSuave = Color(0xFFFFF1EA);
  static const Color _naranjaTexto = Color(0xFFC2410C);
  static const Color _verdeSuave = Color(0xFFECFDF5);
  static const Color _verdeTexto = Color(0xFF047857);
  static const Color _grisSuave = Color(0xFFF9FAFB);
  static const Color _esqueleto = Color(0xFFE5E7EB);
  static const Color _sombra = Color(0x0A000000);

  late final RecordatoriosService _servicio;
  final UserPreferencesService _preferencias = UserPreferencesService();

  ResumenPendientes? _resumen;
  int _umbral = umbralDiasPorDefecto;
  bool _cargando = true;
  bool _sinTienda = false;

  /// Número de carga en curso: descarta respuestas viejas si la tienda cambia
  /// mientras una petición está en vuelo.
  int _cargaActual = 0;

  @override
  void initState() {
    super.initState();
    _servicio = widget.servicio ?? RecordatoriosService();
    _cargar();
  }

  @override
  void didUpdateWidget(covariant AlertaPendientesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.idTienda != widget.idTienda) {
      _cargar();
    }
  }

  Future<void> _cargar() async {
    final carga = ++_cargaActual;
    if (mounted) {
      setState(() {
        _cargando = true;
      });
    }

    int? idTienda = widget.idTienda;
    if (idTienda == null) {
      try {
        idTienda = await _preferencias.getIdTienda();
      } catch (e) {
        debugPrint('⚠️ No se pudo resolver la tienda del recordatorio: $e');
        idTienda = null;
      }
    }

    final umbral = await _servicio.umbralDias();
    if (!mounted || carga != _cargaActual) return;

    if (idTienda == null) {
      setState(() {
        _cargando = false;
        _sinTienda = true;
        _resumen = null;
        _umbral = umbral;
      });
      return;
    }

    ResumenPendientes? resumen;
    try {
      resumen = await _servicio.resumen(idTienda: idTienda);
    } catch (e) {
      // El servicio ya absorbe los fallos de red; esto es la última red.
      debugPrint('⚠️ Error inesperado cargando pendientes: $e');
      resumen = null;
    }
    if (!mounted || carga != _cargaActual) return;

    setState(() {
      _cargando = false;
      _sinTienda = false;
      _resumen = resumen;
      _umbral = resumen?.umbralDias ?? umbral;
    });

    if (widget.notificar) {
      // Opcional por diseño: si la notificación falla, la tarjeta sigue.
      try {
        await _servicio.notificarSiCorresponde(resumen: resumen);
      } catch (e) {
        debugPrint('⚠️ Recordatorio de compras no notificado: $e');
      }
    }
  }

  Future<void> _abrirPendientes() async {
    final ruta = widget.rutaPendientes;
    if (ruta == null || ruta.isEmpty) return;
    try {
      await Navigator.of(context).pushNamed(ruta);
    } catch (e) {
      debugPrint('⚠️ No se pudo abrir $ruta: $e');
    }
  }

  Future<void> _abrirDialogoUmbral() async {
    final nuevo = await showDialog<int>(
      context: context,
      builder: (contexto) => _DialogoUmbral(umbralInicial: _umbral),
    );
    if (nuevo == null || !mounted) return;

    try {
      await _servicio.guardarUmbral(nuevo);
    } catch (e) {
      debugPrint('⚠️ No se pudo guardar el umbral de compras: $e');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('No se pudo guardar el umbral')),
      );
      return;
    }
    if (!mounted) return;
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: AlertaPendientesCard.claveTarjeta,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: _sombra, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: _cargando ? _buildEsqueleto() : _buildContenido(),
    );
  }

  // -------------------------------------------------------------------------
  // Estados
  // -------------------------------------------------------------------------

  Widget _buildEsqueleto() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _caja(44, 44, radio: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _caja(180, 16),
                  const SizedBox(height: 8),
                  _caja(120, 12),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _caja(double.infinity, 20),
        const SizedBox(height: 10),
        _caja(double.infinity, 14),
        const SizedBox(height: 18),
        Row(
          children: [
            _caja(120, 44, radio: 10),
            const SizedBox(width: 10),
            _caja(120, 44, radio: 10),
          ],
        ),
      ],
    );
  }

  Widget _buildContenido() {
    if (_sinTienda) {
      return _buildPanel(
        icono: Icons.storefront_outlined,
        titulo: 'Sin tienda activa',
        detalle: 'Selecciona una tienda para ver los pendientes de compra.',
        color: AppColors.textSecondary,
        mostrarAjuste: false,
      );
    }

    final resumen = _resumen;
    if (resumen == null) {
      return _buildPanel(
        icono: Icons.cloud_off_outlined,
        titulo: 'No se pudieron cargar los pendientes',
        detalle: 'Revisa la conexión. La tarjeta se reintenta al recargar.',
        color: AppColors.warning,
        mostrarReintentar: true,
      );
    }

    if (resumen.vacio) {
      return _buildPanel(
        icono: Icons.check_circle_outline,
        titulo: 'No hay compras pendientes de recibir',
        detalle: 'Todas las compras abiertas están al día.',
        color: AppColors.success,
      );
    }

    return _buildAviso(resumen);
  }

  Widget _buildPanel({
    required IconData icono,
    required String titulo,
    required String detalle,
    required Color color,
    bool mostrarReintentar = false,
    bool mostrarAjuste = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEncabezado(chip: null),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detalle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (mostrarReintentar)
              TextButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reintentar'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            if (mostrarAjuste) _buildEnlaceUmbral(),
          ],
        ),
      ],
    );
  }

  Widget _buildAviso(ResumenPendientes resumen) {
    final dias = resumen.diasMasAntigua ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEncabezado(chip: _buildChipDias(resumen)),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (contexto, restricciones) {
            final cifras = _buildCifras(resumen, dias);
            final monedas = _buildMonedas(resumen);
            if (restricciones.maxWidth < 640) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cifras,
                  const SizedBox(height: 14),
                  monedas,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: cifras),
                const SizedBox(width: 20),
                Expanded(flex: 4, child: monedas),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [_buildBotonVerPendientes(), _buildEnlaceUmbral()],
        ),
        if ((widget.rutaPendientes ?? '').isEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'La pantalla de pendientes todavía no está disponible en esta versión.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Piezas
  // -------------------------------------------------------------------------

  Widget _buildEncabezado({required Widget? chip}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _azulSuave,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.inventory_2_outlined,
            color: AppColors.primary,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Compras sin completar',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Recepciones pendientes',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        if (chip != null) ...[const SizedBox(width: 8), chip],
      ],
    );
  }

  Widget _buildChipDias(ResumenPendientes resumen) {
    final dias = resumen.diasMasAntigua ?? 0;
    final supera = dias > resumen.umbralDias;
    final fondo = supera ? _naranjaSuave : _verdeSuave;
    final color = supera ? AppColors.warning : AppColors.success;
    final texto = supera ? _naranjaTexto : _verdeTexto;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            textoDias(dias),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: texto,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCifras(ResumenPendientes resumen, int dias) {
    final total = resumen.totalCompras;
    final superan = resumen.comprasSobreUmbral;
    final titulo = total == 1
        ? '1 compra sin completar'
        : '$total compras sin completar';
    final verbo = superan == 1 ? 'supera' : 'superan';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'La más antigua hace ${textoDias(dias)}',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        if (superan > 0) ...[
          const SizedBox(height: 2),
          Text(
            '$superan $verbo el umbral de ${textoDias(resumen.umbralDias)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _naranjaTexto,
            ),
          ),
        ] else ...[
          const SizedBox(height: 2),
          Text(
            'Ninguna supera el umbral de ${textoDias(resumen.umbralDias)}',
            style: const TextStyle(fontSize: 12, color: AppColors.success),
          ),
        ],
      ],
    );
  }

  Widget _buildMonedas(ResumenPendientes resumen) {
    if (resumen.porMoneda.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: resumen.porMoneda.map(_buildBloqueMoneda).toList(),
    );
  }

  Widget _buildBloqueMoneda(PendientePorMoneda pendiente) {
    final compras = pendiente.compras == 1
        ? '1 compra'
        : '${pendiente.compras} compras';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _grisSuave,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Pendiente en ${pendiente.moneda}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            formatearMonto(pendiente.montoPendiente),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            compras,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotonVerPendientes() {
    final ruta = widget.rutaPendientes;
    final disponible = ruta != null && ruta.isNotEmpty;
    return ElevatedButton.icon(
      onPressed: disponible ? _abrirPendientes : null,
      icon: const Icon(Icons.receipt_long_outlined, size: 18),
      label: const Text('Ver pendientes'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _esqueleto,
        disabledForegroundColor: AppColors.textSecondary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildEnlaceUmbral() {
    return TextButton.icon(
      onPressed: _abrirDialogoUmbral,
      icon: const Icon(Icons.tune, size: 16, color: AppColors.primary),
      label: const Text('Ajustar umbral', style: TextStyle(fontSize: 13)),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _caja(double ancho, double alto, {double radio = 8}) {
    return Container(
      width: ancho,
      height: alto,
      decoration: BoxDecoration(
        color: _esqueleto,
        borderRadius: BorderRadius.circular(radio),
      ),
    );
  }
}

/// Diálogo para ajustar el umbral de días (1..365), guardado en
/// `SharedPreferences` por [RecordatoriosService.guardarUmbral].
class _DialogoUmbral extends StatefulWidget {
  const _DialogoUmbral({required this.umbralInicial});

  final int umbralInicial;

  @override
  State<_DialogoUmbral> createState() => _DialogoUmbralState();
}

class _DialogoUmbralState extends State<_DialogoUmbral> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _control;

  @override
  void initState() {
    super.initState();
    _control = TextEditingController(text: widget.umbralInicial.toString());
  }

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  void _guardar() {
    if (_formKey.currentState?.validate() != true) return;
    final dias = int.tryParse(_control.text.trim());
    if (dias == null) return;
    Navigator.of(context).pop(acotarUmbral(dias));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajustar umbral de aviso'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se avisa cuando una compra abierta lleva más días que este umbral sin recibirse completa.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _control,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Días sin recepción completa',
                helperText:
                    'Entre $umbralDiasMinimo y $umbralDiasMaximo días',
                border: OutlineInputBorder(),
              ),
              validator: (valor) {
                final dias = int.tryParse((valor ?? '').trim());
                if (dias == null) {
                  return 'Escribe un número de días';
                }
                if (dias < umbralDiasMinimo || dias > umbralDiasMaximo) {
                  return 'Debe estar entre $umbralDiasMinimo y $umbralDiasMaximo';
                }
                return null;
              },
              onFieldSubmitted: (_) => _guardar(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _guardar,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}