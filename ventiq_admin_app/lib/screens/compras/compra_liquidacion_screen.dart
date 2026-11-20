/// Asistente de liquidación multimoneda de una compra.
///
/// Aquí es donde el dinero sale del fondo: se eligen cuentas, se reparte el
/// total entre sus monedas y se reserva. La pantalla existe para que no se
/// pueda reservar ni un céntimo de más ni de menos; la decisión la toma
/// [ResumenCobertura] y el servidor la vuelve a validar.
///
/// Diseño: `docs/planes/fondo-inversion/14-ui-liquidacion.md` (+
/// `04-diseno-ux.md` §5 y `13-ui-compras.md`). Se reutilizan las piezas de
/// `compras_widgets.dart`; los grises y azules son de `AppColors`. Los dos
/// rojos del bloqueo (`#B91C1C`) son los que fija el doc 14 y no existen en
/// `AppColors` a propósito: el rojo puro se lee como fallo del sistema.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../models/compra.dart';
import '../../services/compra_service.dart';
import '../../widgets/admin_drawer.dart';
import 'compras_widgets.dart';

/// Único tono admitido para "este dinero no cuadra" (doc 14).
const Color _rojoDinero = Color(0xFFB91C1C);
const Color _rojoDineroFondo = Color(0xFFFEE2E2);
const Color _rojoDineroBorde = Color(0xFFFCA5A5);

/// Ancho del panel de resumen fijo en PC (doc 14: 400 px).
const double _anchoPanelResumen = 400;

/// Por debajo de este ancho la tabla pierde la columna de saldo y lo pasa al
/// pie de la celda de la fuente: 6 columnas no caben sin cortarse.
const double _anchoTablaCompleta = 900;

class CompraLiquidacionScreen extends StatefulWidget {
  const CompraLiquidacionScreen({super.key, required this.compra});

  /// La compra a liquidar. Se necesitan `id`, `monedaTotal`,
  /// `totalFinanciado` e `idTienda` (para leer el disponible).
  final Compra compra;

  @override
  State<CompraLiquidacionScreen> createState() =>
      _CompraLiquidacionScreenState();
}

class _CompraLiquidacionScreenState extends State<CompraLiquidacionScreen> {
  final _service = CompraService();

  bool _cargando = true;
  bool _reservando = false;
  String? _errorCarga;
  String? _errorReserva;

  List<DisponibleFondo> _disponibles = const [];
  final List<_FuenteForm> _fuentes = [];

  /// Clave de idempotencia del envío actual: una por conjunto de fuentes.
  /// Reintentar el mismo conjunto reutiliza la clave (no duplica reservas);
  /// cambiar cualquier monto o tasa estrena clave, porque es otro envío.
  String? _claveIdempotencia;
  String? _huellaClave;

  String get _monedaTotal => widget.compra.monedaTotal;
  double get _total => widget.compra.totalFinanciado;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final f in _fuentes) {
      f.dispose();
    }
    super.dispose();
  }

  // ==========================================================================
  // Carga del disponible
  // ==========================================================================

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _errorCarga = null;
    });
    try {
      final filas = await _service.disponible(widget.compra.idTienda);
      if (!mounted) return;
      setState(() {
        _aplicarDisponible(filas);
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCarga = _mensajeDe(e);
        _cargando = false;
      });
    }
  }

  /// Refresca el snapshot de cada fuente con el disponible recién leído. Las
  /// cuentas que ya no aparecen en el fondo se quitan de la liquidación.
  void _aplicarDisponible(List<DisponibleFondo> filas) {
    final porLlave = {for (final d in filas) _llave(d): d};
    final fuera = <_FuenteForm>[];
    _disponibles = filas;
    _fuentes.removeWhere((f) {
      final d = porLlave[f.llave];
      if (d == null) {
        fuera.add(f);
        return true;
      }
      f.saldo = d;
      return false;
    });
    if (fuera.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final f in fuera) {
        f.dispose();
      }
    });
  }

  // ==========================================================================
  // Fuentes
  // ==========================================================================

  void _agregarFuente(DisponibleFondo d) {
    final mismaMoneda = d.moneda == _monedaTotal;
    // Solo se precarga cuando la tasa no hay que inventarla: en otra moneda el
    // monto se deja vacío hasta que el usuario escriba la tasa.
    final prelleno = mismaMoneda ? _sugerencia(d) : null;
    setState(() {
      _fuentes.add(
        _FuenteForm(
          saldo: d,
          monedaTotal: _monedaTotal,
          montoInicial: (prelleno == null || prelleno <= 0)
              ? ''
              : prelleno.toStringAsFixed(2),
        ),
      );
      _errorReserva = null;
    });
  }

  /// Lo que falta, sin pasarse del disponible de esa cuenta.
  double _sugerencia(DisponibleFondo d) {
    final falta = _resumen.faltante;
    if (falta <= 0) return 0;
    return falta > d.disponible ? redondear2(d.disponible) : falta;
  }

  void _quitarFuente(_FuenteForm f) {
    setState(() {
      _fuentes.remove(f);
      _errorReserva = null;
    });
    // Se libera cuando el campo ya salió del árbol.
    WidgetsBinding.instance.addPostFrameCallback((_) => f.dispose());
  }

  Future<void> _elegirFuente() async {
    final ya = _fuentes.map((f) => f.llave).toSet();
    final opciones = _disponibles.where((d) => !ya.contains(_llave(d))).toList();
    if (opciones.isEmpty) {
      _snack('Todas las cuentas del fondo ya están en la liquidación.');
      return;
    }
    final elegida = await showDialog<DisponibleFondo>(
      context: context,
      builder: (_) =>
          _ElegirFuenteDialog(opciones: opciones, monedaTotal: _monedaTotal),
    );
    if (elegida != null && mounted) _agregarFuente(elegida);
  }

  void _alCambiarFuente() {
    if (!mounted) return;
    setState(() => _errorReserva = null);
  }

  // ==========================================================================
  // Cobertura y bloqueo
  // ==========================================================================

  ResumenCobertura get _resumen => ResumenCobertura(
    fuentes: [
      for (final f in _fuentes)
        if (f.reserva != null) f.reserva!,
    ],
    total: _total,
  );

  /// Motivo por el que esta compra no se puede reservar aunque el dinero
  /// cuadre. Espeja las validaciones de `fn_fdi_compra_reservar`.
  String? get _bloqueoDeEstado {
    final c = widget.compra;
    if (c.estado != 'creada') {
      return 'Esta compra está en «${c.estadoLegible}»: solo se reserva una '
          'compra en «Creada».';
    }
    if (c.modoLiquidacion != 'fondo') {
      return 'Esta compra se liquida con inversores: no se reserva del fondo.';
    }
    if (_total <= 0) return 'La compra no tiene total a financiar.';
    return null;
  }

  /// Texto del bloqueo. Vacío = se puede reservar (cubre exacto y sin peros).
  String get _motivoBloqueo {
    if (_reservando) return 'Procesando la reserva…';
    final estado = _bloqueoDeEstado;
    if (estado != null) return estado;
    if (_fuentes.isEmpty) return 'Añade al menos una fuente del fondo.';
    if (_fuentes.any((f) => f.problema != null)) {
      return 'Corrige las fuentes marcadas: hay montos o tasas inválidas.';
    }
    if (_fuentes.any((f) => f.reserva == null)) {
      return 'Completa el monto y la tasa de todas las fuentes.';
    }
    final r = _resumen;
    if (r.cubreExacto) return '';
    if (r.sobra > 0) {
      return 'Sobran ${formatearImporteMoneda(r.sobra, _monedaTotal)}: no se '
          'puede reservar con un céntimo de diferencia.';
    }
    return 'Faltan ${formatearImporteMoneda(r.faltante, _monedaTotal)} para '
        'poder reservar.';
  }

  bool get _puedeReservar =>
      !_reservando &&
      _bloqueoDeEstado == null &&
      _fuentes.isNotEmpty &&
      _fuentes.every((f) => f.reserva != null && f.problema == null) &&
      _resumen.cubreExacto;

  String _clavePara(List<FuenteReserva> fuentes) {
    final huella = fuentes
        .map(
          (f) =>
              '${f.idCuenta}|${f.idMedioPago}|${f.moneda}|${f.monto}|${f.tasaATotal}',
        )
        .join(';');
    if (_claveIdempotencia == null || _huellaClave != huella) {
      _claveIdempotencia = _service.newIdempotencyKey();
      _huellaClave = huella;
    }
    return _claveIdempotencia!;
  }

  // ==========================================================================
  // Reserva
  // ==========================================================================

  Future<void> _reservar() async {
    if (!_puedeReservar) return;
    final idCompra = widget.compra.id;
    setState(() {
      _reservando = true;
      _errorReserva = null;
    });
    try {
      // Se relee el disponible justo antes de tocar el dinero: la RPC lo
      // valida igual, pero así el fallo se ve aquí y no a medio camino.
      final frescas = await _service.disponible(widget.compra.idTienda);
      if (!mounted) return;
      setState(() => _aplicarDisponible(frescas));

      final faltas = <String>[];
      for (final f in _fuentes) {
        final monto = f.montoValor;
        if (monto == null || monto <= 0) {
          faltas.add('Hay una fuente sin monto.');
          continue;
        }
        if (f.reserva == null) {
          faltas.add('Falta la tasa de ${f.saldo.moneda}.');
          continue;
        }
        if (monto > f.saldo.disponible) {
          faltas.add(
            'Disponible insuficiente en ${f.saldo.cuenta} '
            '(${f.saldo.moneda}): hay ${formatearImporte(f.saldo.disponible)}, '
            'se piden ${formatearImporte(monto)}.',
          );
        }
      }
      if (faltas.isNotEmpty) {
        setState(() {
          _reservando = false;
          _errorReserva = faltas.join('\n');
        });
        return;
      }

      final fuentes = [
        for (final f in _fuentes)
          if (f.reserva != null) f.reserva!,
      ];
      if (!ResumenCobertura(fuentes: fuentes, total: _total).cubreExacto) {
        setState(() {
          _reservando = false;
          _errorReserva =
              'Las fuentes ya no cubren el total exacto: revisa los montos.';
        });
        return;
      }

      final clave = _clavePara(fuentes);
      final r = await _service.reservar(
        idCompra: idCompra,
        fuentes: fuentes,
        idempotencyKey: clave,
      );
      if (!mounted) return;
      final duplicada = r['duplicada'] == true;
      Navigator.pop(
        context,
        duplicada
            ? 'La compra ya estaba reservada con esta misma clave: no se '
                  'duplicó nada.'
            : 'Compra reservada: el disponible de las fuentes quedó congelado.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reservando = false;
        _errorReserva = _mensajeDe(e);
      });
    }
  }

  // ==========================================================================
  // Utilidades
  // ==========================================================================

  String _mensajeDe(Object e) {
    // Las RPC lanzan `RAISE EXCEPTION` con texto útil en español: se muestra
    // tal cual, sin envolverlo en el `PostgrestException(...)`.
    if (e is PostgrestException && e.message.trim().isNotEmpty) {
      return e.message;
    }
    final texto = e.toString().replaceFirst('Exception: ', '');
    return texto.isEmpty ? 'No se pudo completar la operación.' : texto;
  }

  void _snack(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  void _salir() => Navigator.pop(context);

  // ==========================================================================
  // Build
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final movil = ancho < comprasAnchoCompacto;
    final conBarra = movil && !_cargando && _errorCarga == null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Liquidar compra #${widget.compra.numeroCompra}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar disponible',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      drawer: const AdminDrawer(),
      body: _cuerpo(),
      bottomNavigationBar: conBarra ? _barraFija() : null,
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorCarga != null) return _pantallaError();

    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        if (ancho >= comprasAnchoPanelLateral) return _layoutEscritorio(ancho);
        return _layoutUnaColumna(ancho);
      },
    );
  }

  /// PC (≥1280): fuentes a la izquierda, resumen fijo a la derecha. Los dos
  /// lados scrollean por separado para que el resumen no se vaya con el scroll.
  Widget _layoutEscritorio(double ancho) {
    final anchoIzquierda = ancho - 32 - _anchoPanelResumen - 16;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _panelCompra(conTotal: true),
                  const SizedBox(height: 12),
                  _tablaFuentes(anchoIzquierda - 32),
                  const SizedBox(height: 12),
                  _panelPasos(),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: _anchoPanelResumen,
            child: SingleChildScrollView(
              child: _panelResumen(conAcciones: true, banda: false),
            ),
          ),
        ],
      ),
    );
  }

  /// Tablet (600-1280): resumen arriba, tabla a ancho completo.
  /// Móvil (<600): resumen arriba, una tarjeta por fuente y barra fija abajo.
  Widget _layoutUnaColumna(double ancho) {
    final movil = ancho < comprasAnchoCompacto;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _panelResumen(conAcciones: !movil, banda: true),
          const SizedBox(height: 12),
          _panelCompra(conTotal: false),
          const SizedBox(height: 12),
          if (movil) _tarjetasFuentes() else _tablaFuentes(ancho - 64),
          if (movil) ...[const SizedBox(height: 12), _panelPasos()],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _pantallaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.red[300]),
            const SizedBox(height: 12),
            const Text(
              'No se pudo leer el disponible del fondo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _errorCarga ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // Cabecera de la compra
  // ==========================================================================

  Widget _panelCompra({required bool conTotal}) {
    final c = widget.compra;
    final titulo = Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Compra #${c.numeroCompra}',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        chipEstadoCompra(c.estado),
        pastillaCompras(
          'Liquidación: '
          '${CompraModoLiquidacion.etiquetaDe(c.modoLiquidacion).toUpperCase()}',
          icono: Icons.account_balance,
          color: AppColors.primary,
        ),
        pastillaCompras(
          'Moneda del total: ${_monedaTotal.isEmpty ? '—' : _monedaTotal}',
          icono: Icons.payments_outlined,
        ),
      ],
    );

    final bloqueo = _bloqueoDeEstado;

    return panelCompras(
      children: [
        if (conTotal)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titulo),
              const SizedBox(width: 16),
              cifraCompra(
                'Total a financiar',
                formatearImporte(_total),
                moneda: _monedaTotal,
                destacada: true,
                alineacion: TextAlign.right,
              ),
            ],
          )
        else
          titulo,
        if (bloqueo != null) ...[
          const SizedBox(height: 10),
          avisoCompras(
            bloqueo,
            icono: Icons.lock_outline,
            color: AppColors.secondary,
          ),
        ],
      ],
    );
  }

  // ==========================================================================
  // Panel de resumen y bloqueo (el único CTA vive aquí)
  // ==========================================================================

  Widget _panelResumen({required bool conAcciones, required bool banda}) {
    final r = _resumen;
    return panelCompras(
      children: [
        tituloSeccionCompras(
          'Resumen de cobertura',
          trailing: pastillaCompras(
            _monedaTotal.isEmpty ? '—' : _monedaTotal,
            denso: true,
            icono: Icons.payments_outlined,
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: cifraCompra(
                'Total a financiar',
                formatearImporte(r.total),
                moneda: _monedaTotal,
                destacada: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: cifraCompra(
                'Aportado',
                formatearImporte(r.totalFinanciado),
                moneda: _monedaTotal,
                alineacion: banda ? TextAlign.right : TextAlign.left,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _barraCobertura(r, alto: banda ? 6 : 8),
        const SizedBox(height: 12),
        _bloqueCobertura(r),
        if (_errorReserva != null) ...[
          const SizedBox(height: 10),
          avisoCompras(
            _errorReserva!,
            icono: Icons.error_outline,
            color: AppColors.error,
          ),
        ],
        if (conAcciones) ...[
          const SizedBox(height: 14),
          _panelPasos(),
          const SizedBox(height: 14),
          _botonReservar(),
          const SizedBox(height: 6),
          _helperBoton(),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: _reservando ? null : _salir,
              child: const Text('Cancelar'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _barraCobertura(ResumenCobertura r, {required double alto}) {
    final centavosTotal = (r.total * 100).round();
    final centavosFinanciado = (r.totalFinanciado * 100).round();
    final cubierto = centavosTotal <= 0
        ? 0.0
        : (centavosFinanciado / centavosTotal).clamp(0.0, 1.0);
    final porcentaje = centavosTotal <= 0
        ? 0
        : (centavosFinanciado * 100 / centavosTotal).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(alto / 2),
          child: SizedBox(
            height: alto,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final ancho = constraints.maxWidth;
                final lleno = ancho * cubierto;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(color: AppColors.border),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: lleno,
                      child: ColoredBox(color: AppColors.primary),
                    ),
                    if (r.faltante > 0)
                      Positioned(
                        left: lleno,
                        top: 0,
                        bottom: 0,
                        width: ancho - lleno,
                        child: const ColoredBox(color: _rojoDinero),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${formatearImporte(r.aportado)} de '
          '${formatearImporteMoneda(r.total, _monedaTotal)} · $porcentaje %',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _bloqueCobertura(ResumenCobertura r) {
    if (r.cubreExacto) {
      return avisoCompras(
        'Cubre el total al céntimo: la reserva está habilitada.',
        icono: Icons.check_circle_outline,
        color: AppColors.success,
      );
    }
    final sobran = r.sobra > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: _rojoDineroFondo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _rojoDineroBorde),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: _rojoDinero),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sobran ? 'SOBRAN' : 'FALTANTE',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: _rojoDinero,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatearImporteMoneda(
                    sobran ? r.sobra : r.faltante,
                    _monedaTotal,
                  ),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: _rojoDinero,
                    height: 1.1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sobran
                      ? 'No se puede reservar con un céntimo de diferencia. '
                            'Quita o ajusta una fuente.'
                      : 'No se puede reservar con un céntimo de diferencia.',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: _rojoDinero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonReservar() {
    final habilitado = _puedeReservar;
    return SizedBox(
      height: 46,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: habilitado ? _reservar : null,
        icon: Icon(
          habilitado ? Icons.lock_open_outlined : Icons.lock_outline,
          size: 18,
        ),
        label: Text(_reservando ? 'Reservando…' : 'Reservar'),
      ),
    );
  }

  /// El motivo del bloqueo se escribe; no se confía en el gris del botón.
  Widget _helperBoton() {
    final motivo = _motivoBloqueo;
    final libre = motivo.isEmpty;
    return Text(
      libre ? 'Cubre el total al céntimo. El pago es otro paso.' : 'Deshabilitado: $motivo',
      style: TextStyle(
        fontSize: 11.5,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: libre ? AppColors.success : _rojoDinero,
      ),
    );
  }

  Widget _panelPasos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paso(
          '1',
          'Reservar',
          'Congela el disponible de las fuentes elegidas. La compra pasa a '
              '«Reservada».',
        ),
        const SizedBox(height: 8),
        _paso(
          '2',
          'Pagar',
          'Descuenta el dinero del fondo. Son dos pasos separados: se hace '
              'después, desde el detalle.',
          badge: 'Paso 2',
        ),
      ],
    );
  }

  Widget _paso(String numero, String titulo, String detalle, {String? badge}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Text(
            numero,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (badge != null)
                    pastillaCompras(badge, denso: true, icono: Icons.flag),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                detalle,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // Fuentes: tabla (PC/tablet) y tarjetas (móvil)
  // ==========================================================================

  Widget _panelFuentesBase({required List<Widget> hijos}) {
    return panelCompras(
      children: [
        tituloSeccionCompras(
          'Fuentes del fondo',
          trailing: pastillaCompras(
            '${_fuentes.length}',
            denso: true,
            icono: Icons.account_balance_wallet_outlined,
          ),
        ),
        textoMetaCompras(
          'Solo se puede elegir contra el disponible de cada cuenta: '
          'saldo menos lo ya reservado.',
        ),
        const SizedBox(height: 10),
        if (_disponibles.isEmpty) ...[
          avisoCompras(
            'El fondo no tiene saldos configurados en esta tienda. Sin saldo '
            'no hay nada que reservar.',
            icono: Icons.account_balance_outlined,
            color: AppColors.warning,
          ),
          const SizedBox(height: 8),
        ],
        ...hijos,
      ],
    );
  }

  Widget _tablaFuentes(double ancho) {
    final compacta = ancho < _anchoTablaCompleta;
    final anchos = _AnchosTabla.de(compacta);
    return _panelFuentesBase(
      hijos: [
        if (_fuentes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: textoMetaCompras(
              'Todavía no hay fuentes. Añade la primera con la fila de abajo.',
            ),
          )
        else ...[
          _cabeceraTabla(anchos),
          for (final f in _fuentes) _filaFuente(f, anchos),
        ],
        const SizedBox(height: 10),
        _filaAgregar(),
      ],
    );
  }

  Widget _cabeceraTabla(_AnchosTabla a) {
    const estilo = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Expanded(
            flex: 3,
            child: Text('Cuenta · medio · moneda', style: estilo),
          ),
          if (!a.compacta)
            SizedBox(
              width: a.saldo,
              child: const Text('Saldo · reservado · disponible', style: estilo),
            ),
          const SizedBox(width: 8),
          SizedBox(
            width: a.monto,
            child: const Text(
              'Monto nativo',
              textAlign: TextAlign.right,
              style: estilo,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: a.tasa,
            child: Text(
              'Tasa a ${_monedaTotal.isEmpty ? 'la moneda del total' : _monedaTotal}',
              style: estilo,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: a.equivalente,
            child: const Text(
              'Equivalente',
              textAlign: TextAlign.right,
              style: estilo,
            ),
          ),
          if (!a.compacta) const SizedBox(width: 32),
        ],
      ),
    );
  }

  Widget _filaFuente(_FuenteForm f, _AnchosTabla a) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: _celdaFuente(
              f,
              inlineQuitar: a.compacta,
              conSaldo: a.compacta,
            ),
          ),
          if (!a.compacta) SizedBox(width: a.saldo, child: _celdaSaldo(f)),
          const SizedBox(width: 8),
          SizedBox(
            width: a.monto,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _campoMonto(f),
                if (f.problemaMonto != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      f.problemaMonto!,
                      style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.2,
                        color: _rojoDinero,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'quedan ${formatearImporteMoneda(f.disponibleRestante, f.saldo.moneda)}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.2,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: a.tasa, child: _celdaTasa(f)),
          const SizedBox(width: 8),
          SizedBox(
            width: a.equivalente,
            child: _celdaEquivalente(f),
          ),
          if (!a.compacta)
            SizedBox(
              width: 32,
              child: IconButton(
                tooltip: 'Quitar fuente',
                visualDensity: VisualDensity.compact,
                onPressed: () => _quitarFuente(f),
                icon: const Icon(Icons.close, size: 16),
              ),
            ),
        ],
      ),
    );
  }

  Widget _celdaFuente(
    _FuenteForm f, {
    required bool inlineQuitar,
    required bool conSaldo,
  }) {
    final chips = Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          f.saldo.cuenta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        pastillaCompras(
          f.saldo.moneda,
          denso: true,
          icono: Icons.currency_exchange,
          color: AppColors.primary,
        ),
        pastillaCompras(f.saldo.medioPago, denso: true, icono: Icons.payments),
        if (inlineQuitar)
          IconButton(
            tooltip: 'Quitar fuente',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () => _quitarFuente(f),
            icon: const Icon(Icons.close, size: 14),
          ),
      ],
    );

    if (!conSaldo) return chips;

    // En tabla compacta el saldo no tiene columna propia: va bajo la fuente.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        chips,
        const SizedBox(height: 4),
        Text(
          'Saldo ${formatearImporteMoneda(f.saldo.saldo, f.saldo.moneda)} · '
          'Reservado ${formatearImporteMoneda(f.saldo.reservado, f.saldo.moneda)} · '
          'Disponible ${formatearImporteMoneda(f.saldo.disponible, f.saldo.moneda)}',
          style: const TextStyle(
            fontSize: 10.5,
            height: 1.3,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _celdaSaldo(_FuenteForm f) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _filaCifraNativa('Saldo', f.saldo.saldo, f.saldo.moneda),
        const SizedBox(height: 2),
        _filaCifraNativa('Reservado', f.saldo.reservado, f.saldo.moneda),
        const SizedBox(height: 2),
        _filaCifraNativa(
          'Disponible',
          f.saldo.disponible,
          f.saldo.moneda,
          negrita: true,
        ),
      ],
    );
  }

  Widget _filaCifraNativa(
    String etiqueta,
    double valor,
    String moneda, {
    bool negrita = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            etiqueta,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
        Text(
          formatearImporteMoneda(valor, moneda),
          style: TextStyle(
            fontSize: 12,
            fontWeight: negrita ? FontWeight.w700 : FontWeight.w500,
            color: AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// Cifra apilada para la tarjeta del móvil: la columna es estrecha y un Row
/// etiqueta+importe se desborda.
  Widget _cifraApilada(
    String etiqueta,
    double valor,
    String moneda, {
    bool negrita = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          formatearImporte(valor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: negrita ? FontWeight.w700 : FontWeight.w500,
            color: AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          moneda,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, color: AppColors.textLight),
        ),
      ],
    );
  }

  Widget _campoMonto(_FuenteForm f, {TextAlign alineacion = TextAlign.right}) {
    return TextField(
      controller: f.monto,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [_ImporteInputFormatter(decimales: 2)],
      onChanged: (_) => _alCambiarFuente(),
      textAlign: alineacion,
      style: const TextStyle(
        fontSize: 13,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Monto',
        hintText: '0,00',
        suffixText: f.saldo.moneda,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
    );
  }

  Widget _campoTasa(_FuenteForm f) {
    return TextField(
      controller: f.tasa,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [_ImporteInputFormatter(decimales: 6)],
      onChanged: (_) => _alCambiarFuente(),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Tasa',
        hintText: '0,000000',
        suffixText: _monedaTotal,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
    );
  }

  String get _parTasaTexto => _monedaTotal.isEmpty ? 'la moneda del total' : _monedaTotal;

  Widget _celdaTasa(_FuenteForm f) {
    if (f.mismaMoneda) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pastillaCompras(
            'Misma moneda · sin tasa',
            denso: true,
            icono: Icons.link,
            color: AppColors.secondary,
          ),
          const SizedBox(height: 4),
          Text(
            'La tasa se fija en 1 y no se edita.',
            style: const TextStyle(
              fontSize: 10.5,
              height: 1.2,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
    }
    final tasa = f.tasaValor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '1 ${f.saldo.moneda} = '
          '${tasa == null ? '—' : formatearCantidad(tasa)} $_parTasaTexto',
          maxLines: 2,
          style: const TextStyle(
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        _campoTasa(f),
        if (f.problemaTasa != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              f.problemaTasa!,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.2,
                color: _rojoDinero,
              ),
            ),
          ),
      ],
    );
  }

  Widget _celdaEquivalente(_FuenteForm f) {
    final reserva = f.reserva;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          reserva == null ? '—' : '= ${formatearImporte(reserva.montoEqTotal)}',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 13,
            fontWeight: reserva == null ? FontWeight.w500 : FontWeight.w700,
            color: reserva == null ? AppColors.textLight : AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          _monedaTotal,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 10, color: AppColors.textLight),
        ),
      ],
    );
  }

  Widget _filaAgregar() {
    final habilitado = _disponibles.isNotEmpty;
    return InkWell(
      onTap: habilitado ? _elegirFuente : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.add_circle_outline,
              size: 18,
              color: habilitado ? AppColors.primary : AppColors.textLight,
            ),
            const SizedBox(width: 8),
            Text(
              'Añadir otra fuente',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: habilitado ? AppColors.primary : AppColors.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // Fuentes en móvil: una tarjeta por fuente
  // ==========================================================================

  Widget _tarjetasFuentes() {
    return _panelFuentesBase(
      hijos: [
        if (_fuentes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: textoMetaCompras(
              'Todavía no hay fuentes. Añade la primera con la fila de abajo.',
            ),
          )
        else
          for (final f in _fuentes) _tarjetaFuente(f),
        const SizedBox(height: 10),
        _filaAgregar(),
      ],
    );
  }

  Widget _tarjetaFuente(_FuenteForm f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _celdaFuente(
                    f,
                    inlineQuitar: true,
                    conSaldo: false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _cifraApilada('Saldo', f.saldo.saldo, f.saldo.moneda),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _cifraApilada(
                    'Reservado',
                    f.saldo.reservado,
                    f.saldo.moneda,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _cifraApilada(
                    'Disponible',
                    f.saldo.disponible,
                    f.saldo.moneda,
                    negrita: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _campoMonto(f, alineacion: TextAlign.left),
            const SizedBox(height: 4),
            if (f.problemaMonto != null)
              Text(
                f.problemaMonto!,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: _rojoDinero,
                ),
              )
            else
              Text(
                'quedan ${formatearImporteMoneda(f.disponibleRestante, f.saldo.moneda)} '
                'disponibles en esta cuenta tras el aporte',
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: AppColors.textSecondary,
                ),
              ),
            const SizedBox(height: 12),
            if (f.mismaMoneda)
              Align(
                alignment: Alignment.centerLeft,
                child: pastillaCompras(
                  'Misma moneda · sin tasa',
                  denso: true,
                  icono: Icons.link,
                  color: AppColors.secondary,
                ),
              )
            else ...[
              Text(
                'Tasa a $_parTasaTexto',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              _campoTasa(f),
              const SizedBox(height: 4),
              Text(
                '1 ${f.saldo.moneda} = '
                '${f.tasaValor == null ? '—' : formatearCantidad(f.tasaValor!)} '
                '$_parTasaTexto',
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: AppColors.textSecondary,
                ),
              ),
              if (f.problemaTasa != null)
                Text(
                  f.problemaTasa!,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: _rojoDinero,
                  ),
                ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                f.reserva == null
                    ? '= —'
                    : '= ${formatearImporteMoneda(f.reserva!.montoEqTotal, _monedaTotal)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: f.reserva == null
                      ? AppColors.textLight
                      : AppColors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // Barra fija del móvil
  // ==========================================================================

  Widget _barraFija() {
    final motivo = _motivoBloqueo;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (motivo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  motivo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: _rojoDinero,
                  ),
                ),
              ),
            _botonReservar(),
            TextButton(
              onPressed: _reservando ? null : _salir,
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Piezas de apoyo
// ===========================================================================

/// Llave de una fila del disponible: cuenta + medio + moneda.
String _llave(DisponibleFondo d) =>
    '${d.idCuenta}|${d.idMedioPago}|${d.moneda}';

/// Importes tecleados. El formateador de entrada deja como mucho un separador
/// y los decimales permitidos, así que aquí basta con tratar la coma como
/// decimal (mismo criterio que `compra_form_screen._parseNumero`).
double? _parseNumero(String texto) {
  final limpio = texto.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (limpio.isEmpty) return null;
  final valor = double.tryParse(limpio);
  return (valor != null && valor.isFinite) ? valor : null;
}

/// Formato de un campo de importe: rechaza (no recorta) lo que no sea un
/// número con hasta [decimales] decimales. `FilteringTextInputFormatter.allow`
/// no sirve aquí: concatenaría trozos y cambiaría el dinero en silencio.
class _ImporteInputFormatter extends TextInputFormatter {
  const _ImporteInputFormatter({this.decimales = 2});

  final int decimales;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final patron = RegExp('^\\d*([.,]\\d{0,$decimales})?\$');
    return patron.hasMatch(newValue.text) ? newValue : oldValue;
  }
}

/// Una fuente en edición. `monto` está en la moneda nativa de la cuenta;
/// `tasa` la lleva a la moneda del total.
class _FuenteForm {
  _FuenteForm({
    required this.saldo,
    required this.monedaTotal,
    String montoInicial = '',
  }) : monto = TextEditingController(text: montoInicial);

  DisponibleFondo saldo;
  final String monedaTotal;
  final TextEditingController monto;
  final TextEditingController tasa = TextEditingController();

  String get llave => _llave(saldo);
  bool get mismaMoneda => saldo.moneda == monedaTotal;

  double? get montoValor => _parseNumero(monto.text);

  /// En la moneda del total la tasa es 1 por definición: no se pide ni se edita.
  double? get tasaValor {
    if (mismaMoneda) return 1;
    final t = _parseNumero(tasa.text);
    return (t == null || t <= 0) ? null : t;
  }

  double get disponibleRestante =>
      redondear2(saldo.disponible - (montoValor ?? 0));

  String? get problemaMonto {
    if (monto.text.trim().isEmpty) return null;
    final m = montoValor;
    if (m == null || m <= 0) return 'Monto no válido.';
    if (m > saldo.disponible) {
      return 'Supera el disponible: hay '
          '${formatearImporteMoneda(saldo.disponible, saldo.moneda)}.';
    }
    if (redondear2(m) != m) return 'Máximo dos decimales.';
    return null;
  }

  String? get problemaTasa {
    if (mismaMoneda) return null;
    if (tasaValor == null) return 'Indica la tasa a $monedaTotal.';
    return null;
  }

  String? get problema => problemaMonto ?? problemaTasa;

  /// Fuente lista para `p_fuentes`, o `null` si le falta el monto o la tasa.
  FuenteReserva? get reserva {
    final m = montoValor;
    final t = tasaValor;
    if (m == null || m <= 0 || t == null) return null;
    return FuenteReserva(
      idCuenta: saldo.idCuenta,
      idMedioPago: saldo.idMedioPago,
      moneda: saldo.moneda,
      monto: redondear2(m),
      tasaATotal: t,
    );
  }

  void dispose() {
    monto.dispose();
    tasa.dispose();
  }
}

/// Anchos de la tabla de fuentes: dos juegos, con y sin columna de saldo.
class _AnchosTabla {
  const _AnchosTabla({
    required this.monto,
    required this.tasa,
    required this.equivalente,
    required this.saldo,
    required this.compacta,
  });

  final double monto;
  final double tasa;
  final double equivalente;
  final double saldo;
  final bool compacta;

  factory _AnchosTabla.de(bool compacta) => compacta
      ? const _AnchosTabla(
          monto: 110,
          tasa: 132,
          equivalente: 110,
          saldo: 0,
          compacta: true,
        )
      : const _AnchosTabla(
          monto: 118,
          tasa: 150,
          equivalente: 118,
          saldo: 190,
          compacta: false,
        );
}

/// Selector de cuenta/medio/moneda contra el disponible (nunca contra el saldo
/// bruto). Las cuentas sin disponible se listan, pero deshabilitadas.
class _ElegirFuenteDialog extends StatelessWidget {
  const _ElegirFuenteDialog({required this.opciones, required this.monedaTotal});

  final List<DisponibleFondo> opciones;
  final String monedaTotal;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      title: const Text('Añadir fuente del fondo'),
      contentPadding: const EdgeInsets.only(top: 8),
      content: SizedBox(
        width: ancho < comprasAnchoCompacto ? ancho * 0.8 : 520,
        height: 380,
        child: ListView.separated(
          itemCount: opciones.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            final d = opciones[i];
            return ListTile(
              enabled: d.tieneDisponible,
              title: Text(
                d.etiqueta,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Saldo ${formatearImporteMoneda(d.saldo, d.moneda)} · '
                    'Reservado ${formatearImporteMoneda(d.reservado, d.moneda)} · '
                    'Disponible ${formatearImporteMoneda(d.disponible, d.moneda)}',
                    style: const TextStyle(fontSize: 11, height: 1.3),
                  ),
                  if (d.moneda != monedaTotal)
                    Text(
                      'Otra moneda: se pedirá la tasa a $monedaTotal',
                      style: const TextStyle(fontSize: 11, height: 1.3),
                    ),
                ],
              ),
              trailing: d.tieneDisponible
                  ? const Icon(Icons.chevron_right)
                  : const Icon(Icons.block, size: 18),
              onTap: d.tieneDisponible ? () => Navigator.pop(ctx, d) : null,
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Volver'),
        ),
      ],
    );
  }
}