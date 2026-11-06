import 'package:flutter/material.dart';

import '../services/store_config_service.dart';
import '../services/tienda_monedas_service.dart';

/// Tarjeta de «Monedas aceptadas por la tienda» (Fase 2 del plan multimoneda).
///
/// - Lista el catálogo global (`monedas`) con un interruptor por moneda.
/// - CUP está bloqueada: es la moneda base contable y el servidor la exige.
/// - Debajo, «Forzar moneda de venta»: con más de una moneda aceptada la tienda
///   puede imponer en cuál se vende.
/// - Guarda la lista con `fn_guardar_monedas_tienda` y el bloque de moneda
///   forzada en `app_dat_configuracion_tienda`.
///
/// Nota: el flag antiguo `mostrar_selector_moneda` sigue existiendo y es el que
/// hoy lee el TPV para mostrar el toggle CUP/USD. Esta lista es la fuente que
/// usará el TPV en la Fase 3.
class MonedasTiendaCard extends StatefulWidget {
  const MonedasTiendaCard({super.key, required this.storeId});

  final int storeId;

  @override
  State<MonedasTiendaCard> createState() => _MonedasTiendaCardState();
}

class _MonedasTiendaCardState extends State<MonedasTiendaCard> {
  List<TiendaMoneda> _monedas = const [];
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  /// Moneda de venta impuesta por la tienda. Solo se persiste cuando el bloque
  /// aplica (más de una moneda vendible).
  bool _forzandoMonedaVenta = false;
  String? _monedaVentaForzada;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Una moneda es vendible cuando la tienda la acepta y sigue activa en el
  /// catálogo global: una moneda desactivada no puede ofrecerse, así que
  /// tampoco puede imponerse.
  static bool _esVendible(TiendaMoneda m) => m.aceptada && m.activaGlobal;

  /// Monedas en las que la tienda puede cobrar hoy.
  List<TiendaMoneda> get _monedasVendibles =>
      _monedas.where(_esVendible).toList();

  /// Con una sola moneda no hay nada que forzar: el bloque no se pinta y la
  /// configuración no se toca.
  bool get _aplicaForzado => _monedasVendibles.length > 1;

  /// Divisa que muestra el selector y que se persiste: la forzada si sigue
  /// siendo vendible y, si no, la base (CUP) o la primera disponible. Evita que
  /// el control quede vacío o apunte a una moneda que la tienda dejó de
  /// aceptar, que es justo lo que el trigger del servidor rechazaría.
  String? get _monedaVentaVigente {
    final vendibles = _monedasVendibles;
    if (vendibles.isEmpty) return null;

    final forzada = _monedaVentaForzada;
    if (forzada != null && vendibles.any((m) => m.codigo == forzada)) {
      return forzada;
    }
    return vendibles
        .firstWhere((m) => m.esBase, orElse: () => vendibles.first)
        .codigo;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final lista = await TiendaMonedasService.listar(widget.storeId);
      // La moneda forzada solo importa con más de una moneda vendible: en el
      // caso mayoritario (una sola) ni se consulta. Los getters no lanzan
      // (devuelven el valor por defecto), así que un fallo aquí no impide
      // listar monedas.
      final hayEleccion = lista.where(_esVendible).length > 1;
      final forzando = hayEleccion
          ? await StoreConfigService.getForzarMonedaVenta(widget.storeId)
          : false;
      final monedaForzada = hayEleccion
          ? await StoreConfigService.getMonedaVentaForzada(widget.storeId)
          : null;
      if (!mounted) return;
      setState(() {
        _monedas = lista;
        _forzandoMonedaVenta = forzando;
        _monedaVentaForzada = monedaForzada;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = TiendaMonedasService.mensajeError(e);
        _cargando = false;
      });
    }
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    var monedasGuardadas = false;
    try {
      // Primero las monedas aceptadas: el trigger de la configuración exige
      // que la divisa forzada ya esté aceptada por la tienda.
      await TiendaMonedasService.guardar(widget.storeId, _monedas);
      monedasGuardadas = true;
      await _guardarMonedaForzada();
      if (!mounted) return;
      _avisar('Configuración de monedas actualizada');
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      _avisar(TiendaMonedasService.mensajeError(e), error: true);
      // Si falló el segundo paso, el primero ya quedó escrito: se recarga para
      // no mostrar un estado que no existe. Si falló el primero no se recarga,
      // para no borrar los cambios que el usuario aún puede reintentar.
      if (monedasGuardadas) await _cargar();
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Persiste el bloque «Forzar moneda de venta» después de la lista.
  ///
  /// Con una sola moneda vendible el bloque no se pinta y la configuración no
  /// se toca… salvo que este mismo guardado haya dejado la moneda forzada sin
  /// ser aceptada: ahí se apaga para no bloquear la venta sin que nadie lo vea.
  Future<void> _guardarMonedaForzada() async {
    if (!_aplicaForzado && !_forzandoMonedaVenta) return;

    final forzar = _aplicaForzado && _forzandoMonedaVenta;
    await StoreConfigService.updateStoreConfig(
      widget.storeId,
      forzarMonedaVenta: forzar,
      // Encender sin elección cae en `_monedaVentaVigente` (la base) y apagar
      // deja NULL: nunca una divisa huérfana lista para re-bloquear la venta.
      monedaVentaForzada: forzar ? _monedaVentaVigente : null,
    );
  }

  void _avisar(String mensaje, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  /// Bloque «Forzar moneda de venta»: interruptor + selector.
  ///
  /// Se guarda con el botón de la tarjeta, no al cambiar: la lista y la divisa
  /// forzada tienen que escribirse en orden (primero las monedas, después la
  /// configuración), y así el guardado es uno solo para el usuario.
  Widget _buildForzarMonedaVenta(ThemeData theme) {
    final apagado = !_forzandoMonedaVenta;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          secondary: Icon(
            Icons.lock_outline,
            size: 18,
            color:
                apagado
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.primary,
          ),
          title: const Text('Forzar moneda de venta'),
          subtitle: Text(
            apagado
                ? 'Si lo activas, el vendedor no podrá elegir otra divisa ni '
                      'cobrar en otra.'
                : 'El vendedor no podrá elegir otra divisa ni cobrar en otra.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          value: _forzandoMonedaVenta,
          onChanged:
              _guardando
                  ? null
                  : (v) => setState(() {
                    _forzandoMonedaVenta = v;
                    // Al encender sin elección previa se arranca en la vigente
                    // (la base): el selector nunca queda vacío y la venta no
                    // se bloquea por falta de moneda.
                    if (v) _monedaVentaForzada = _monedaVentaVigente;
                  }),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: DropdownButtonFormField<String>(
            initialValue: _monedaVentaVigente,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Moneda de venta',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
            items:
                _monedasVendibles
                    .map(
                      (m) => DropdownMenuItem<String>(
                        value: m.codigo,
                        child: Text(m.etiqueta),
                      ),
                    )
                    .toList(),
            onChanged:
                apagado || _guardando
                    ? null
                    : (v) => setState(() => _monedaVentaForzada = v),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aceptadas = _monedas.where((m) => m.aceptada).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.currency_exchange, color: Colors.amber[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monedas aceptadas por la tienda',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _cargando
                            ? 'Cargando...'
                            : 'El cajero solo podrá cobrar en estas monedas '
                                  '($aceptadas de ${_monedas.length}).',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_cargando && _error == null)
                  TextButton.icon(
                    onPressed: _guardando ? null : _guardar,
                    icon: _guardando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Guardar'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text('No se pudo cargar: $_error')),
                    TextButton(onPressed: _cargar, child: const Text('Reintentar')),
                  ],
                ),
              )
            else ...[
              ..._monedas.map((m) {
                final bloqueada = m.esBase || !m.activaGlobal;
                return SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  secondary: m.esBase
                      ? const Icon(Icons.star, size: 18, color: Colors.amber)
                      : null,
                  title: Text(m.etiqueta),
                  subtitle: !m.activaGlobal
                      ? Text(
                          'Inactiva en el catálogo global',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.error,
                          ),
                        )
                      : (m.esBase
                            ? Text(
                                'Moneda base: siempre activa',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            : null),
                  value: m.aceptada,
                  onChanged: bloqueada || _guardando
                      ? null
                      : (v) => setState(() {
                          final i = _monedas.indexOf(m);
                          _monedas = List<TiendaMoneda>.from(_monedas)
                            ..[i] = m.copyWith(aceptada: v);
                        }),
                );
              }),
              const SizedBox(height: 8),
              Text(
                'Las monedas que quites dejarán de ofrecerse al cajero, pero no '
                'se borran: los cobros históricos conservan su moneda.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              // Sin elección real el bloque sería ruido: no se pinta.
              if (_aplicaForzado) ...[
                const Divider(height: 32),
                _buildForzarMonedaVenta(theme),
              ],
            ],
          ],
        ),
      ),
    );
  }
}