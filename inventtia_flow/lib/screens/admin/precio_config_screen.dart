import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../models/config_precio.dart';
import '../../models/precio_config.dart';
import '../../models/tasa_cambio.dart';
import '../../services/precio_config_service.dart';
import '../../services/tasa_cambio_service.dart';

/// Ajustes de los precios automáticos de una entidad (punto 4 del plan).
///
/// El admin escribe UN precio y la app calcula el resto de monedas con la tasa
/// del día. Aquí decide si ese cálculo es automático, desde qué moneda se
/// escribe, cuántos decimales se aplican a CUP y a las divisas, y puede ver
/// (y refrescar) la tasa que se está usando.
///
/// Se abre desde la AppBar de `GestionServiciosScreen`.
class PrecioConfigScreen extends StatefulWidget {
  /// Entidad cuyos precios se configuran.
  final int idEntidad;

  /// Nombre de la entidad, sólo para el subtítulo.
  final String? denominacion;

  const PrecioConfigScreen({
    super.key,
    required this.idEntidad,
    this.denominacion,
  });

  @override
  State<PrecioConfigScreen> createState() => _PrecioConfigScreenState();
}

class _PrecioConfigScreenState extends State<PrecioConfigScreen> {
  PrecioConfig? _config;
  bool _cargando = true;
  bool _guardando = false;

  TasasDia? _tasas;
  bool _cargandoTasa = true;
  String? _errorTasa;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final leida = await PrecioConfigService.getSeguro(widget.idEntidad);
    if (!mounted) return;
    setState(() {
      _config = _normalizar(leida);
      _cargando = false;
    });
    await _cargarTasa();
  }

  /// Deja la moneda de origen en una de las que admite la app: si la fila
  /// trae un código raro (dato escrito a mano en la BD), el desplegable
  /// reventaría al no encontrar su `value` y la RPC rechazaría el guardado.
  PrecioConfig _normalizar(PrecioConfig config) {
    if (MonedasApp.todas.contains(config.monedaOrigen)) return config;
    return config.copyWith(monedaOrigen: MonedasApp.todas.first);
  }

  /// Lee la tasa (de la caché de la sesión si ya es de hoy).
  Future<void> _cargarTasa({bool forzar = false}) async {
    setState(() {
      _cargandoTasa = true;
      _errorTasa = null;
    });
    final tasas = await TasaCambioService.obtener(forzar: forzar);
    if (!mounted) return;
    setState(() {
      _tasas = tasas;
      _cargandoTasa = false;
      if (tasas == null) {
        _errorTasa =
            'No se pudo obtener la tasa de cambio. Los precios se pueden '
            'seguir escribiendo a mano.';
      }
    });
  }

  Future<void> _guardar() async {
    final config = _config;
    if (config == null) return;
    setState(() => _guardando = true);
    try {
      final guardada = await PrecioConfigService.set(
        idEntidad: widget.idEntidad,
        config: config,
      );
      if (!mounted) return;
      setState(() => _config = _normalizar(guardada));
      _avisar(
        'Configuración guardada. Se aplicará la próxima vez que edites un '
        'precio.',
      );
    } catch (e) {
      _avisar('No se pudo guardar: $e', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _avisar(String mensaje, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: error ? AppTheme.error : AppTheme.success,
        ),
      );
  }

  void _cambiar(PrecioConfig nuevo) {
    setState(() => _config = nuevo);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Precios automáticos'),
        bottom: widget.denominacion == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    widget.denominacion!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
      ),
      body: _cargando || config == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _TarjetaTasa(
                  tasas: _tasas,
                  cargando: _cargandoTasa,
                  error: _errorTasa,
                  onActualizar: _cargandoTasa
                      ? null
                      : () => _cargarTasa(forzar: true),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: config.autoActivo,
                  activeThumbColor: AppTheme.primary,
                  onChanged: (v) => _cambiar(config.copyWith(autoActivo: v)),
                  title: const Text(
                    'Calcular los precios automáticamente',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Al escribir el precio en la moneda de origen, la app '
                    'rellena el resto de monedas con la tasa del día. Siempre '
                    'puedes corregirlas a mano.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 4),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Moneda de origen',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  'La moneda en la que escribes el precio «de verdad»; el '
                  'resto se calcula desde ella.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: config.monedaOrigen,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Moneda de origen',
                    prefixIcon: Icon(Icons.attach_money),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final m in MonedasApp.todas)
                      DropdownMenuItem(
                        value: m,
                        child: Text(MonedasApp.etiqueta(m)),
                      ),
                  ],
                  onChanged: (m) {
                    if (m != null) _cambiar(config.copyWith(monedaOrigen: m));
                  },
                ),
                const SizedBox(height: 20),
                const Text(
                  'Redondeo',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Los precios calculados se redondean antes de escribirse en '
                  'el formulario. CUP suele ir sin decimales; las divisas, con '
                  'dos.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: config.redondeoCup,
                        decoration: const InputDecoration(
                          labelText: 'Decimales CUP',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('0')),
                          DropdownMenuItem(value: 1, child: Text('1')),
                          DropdownMenuItem(value: 2, child: Text('2')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            _cambiar(config.copyWith(redondeoCup: v));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: config.redondeoDivisa,
                        decoration: const InputDecoration(
                          labelText: 'Decimales divisas',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('0')),
                          DropdownMenuItem(value: 1, child: Text('1')),
                          DropdownMenuItem(value: 2, child: Text('2')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            _cambiar(config.copyWith(redondeoDivisa: v));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _guardando ? null : _guardar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _guardando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Guardar configuración',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ],
            ),
    );
  }
}

/// Tarjeta con el estado de la tasa del día y el botón de refresco.
class _TarjetaTasa extends StatelessWidget {
  final TasasDia? tasas;
  final bool cargando;
  final String? error;
  final VoidCallback? onActualizar;

  const _TarjetaTasa({
    required this.tasas,
    required this.cargando,
    required this.error,
    required this.onActualizar,
  });

  @override
  Widget build(BuildContext context) {
    final t = tasas;
    final deHoy = t?.esDeHoy ?? false;
    final color = deHoy ? AppTheme.success : AppTheme.warning;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.currency_exchange, size: 18, color: color),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Tasa de cambio del día',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (cargando)
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (t == null) ...[
            Text(
              error ??
                  'Sin tasa disponible. Los precios no se calculan '
                      'automáticamente.',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ] else ...[
            Row(
              children: [
                Text(
                  'Fecha: ${t.fechaTexto}',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    deHoy ? 'Hoy' : 'De otro día',
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Hora: ${t.horaTexto}',
              style: const TextStyle(fontSize: 13),
            ),
            if (t.fuente != null) ...[
              const SizedBox(height: 4),
              Text(
                'Fuente: ${t.fuente}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            if (t.aviso != null) ...[
              const SizedBox(height: 6),
              Text(
                t.aviso!,
                style: const TextStyle(fontSize: 12, color: AppTheme.warning),
              ),
            ],
            if (!deHoy) ...[
              const SizedBox(height: 6),
              const Text(
                'La tasa no es de hoy: se usa la última disponible. Pulsa '
                '«Actualizar tasa» para intentar refrescarla.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onActualizar,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Actualizar tasa'),
            ),
          ),
        ],
      ),
    );
  }
}