import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/monedas_service.dart';
import '../utils/platform_utils.dart';
import '../widgets/app_drawer.dart';

/// Pantalla de administración del catálogo global de monedas.
///
/// Fase 1 del plan multimoneda. Consume las RPC creadas por
/// `docs/plan-multimoneda/fase1_catalogo_monedas.sql`:
///   - `fn_crear_moneda` / `fn_actualizar_moneda`
///   - `fn_guardar_denominaciones`
///   - `fn_guardar_tasa_global`
///   - `fn_tasa_cambio` (lectura)
///
/// Nota: la escritura se gatea con [AuthService.hasFullAccess] (nivel 1) porque
/// el RPC comprueba `fn_is_superadmin_full_access()`, que exige `nivel_acceso = 1`.
/// Gatear con `canWrite()` (nivel <= 2) mostraría el botón a usuarios que la base
/// rechazaría.
class MonedasScreen extends StatefulWidget {
  const MonedasScreen({super.key});

  @override
  State<MonedasScreen> createState() => _MonedasScreenState();
}

class _MonedasScreenState extends State<MonedasScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final List<Map<String, dynamic>> _monedas = [];
  final List<Map<String, dynamic>> _tasas = [];

  /// Estado de la tasa automática («el toque»). `null` si no está disponible.
  Map<String, dynamic>? _estadoAuto;

  bool _cargando = true;
  String? _error;

  bool get _puedeEscribir => AuthService.hasFullAccess();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final monedas = await MonedasService.listar();
      final tasas = await MonedasService.listarTasasGlobales();
      final estadoAuto = await MonedasService.estadoTasaAutomatica();
      if (!mounted) return;
      setState(() {
        _monedas
          ..clear()
          ..addAll(monedas);
        _tasas
          ..clear()
          ..addAll(tasas);
        _estadoAuto = estadoAuto;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.toString();
      });
    }
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

  Future<void> _abrirFormulario({Map<String, dynamic>? moneda}) async {
    final guardado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MonedaFormDialog(moneda: moneda),
    );
    if (guardado == true) {
      _avisar(moneda == null ? 'Moneda creada' : 'Moneda actualizada');
      await _cargar();
    }
  }

  Future<void> _abrirDenominaciones(Map<String, dynamic> moneda) async {
    final codigo = (moneda['codigo'] ?? '').toString();
    final guardado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DenominacionesDialog(codigo: codigo),
    );
    if (guardado == true) {
      _avisar('Denominaciones de $codigo guardadas');
    }
  }

  Future<void> _alternarActivo(Map<String, dynamic> moneda, bool valor) async {
    final codigo = (moneda['codigo'] ?? '').toString();
    try {
      await MonedasService.actualizar(codigo: codigo, activo: valor);
      _avisar(valor ? '$codigo activada' : '$codigo desactivada');
      await _cargar();
    } catch (e) {
      _avisar('No se pudo cambiar el estado: ${_mensajeError(e)}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monedas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: _cargar,
          ),
          if (_puedeEscribir)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Nueva moneda',
              onPressed: () => _abrirFormulario(),
            ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: theme.colorScheme.primary,
            tabs: const [
              Tab(icon: Icon(Icons.currency_exchange), text: 'Catálogo'),
              Tab(icon: Icon(Icons.trending_up), text: 'Tasas globales'),
            ],
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _buildError()
                : TabBarView(
                    controller: _tabController,
                    children: [_buildCatalogo(), _buildTasas()],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            const Text(
              'No se pudo cargar el catálogo de monedas',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('$_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- catálogo

  Widget _buildCatalogo() {
    final width = MediaQuery.of(context).size.width;
    final esEscritorio = PlatformUtils.shouldUseDesktopLayout(width);

    if (_monedas.isEmpty) {
      return const Center(child: Text('No hay monedas en el catálogo.'));
    }

    if (esEscritorio) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text('Código')),
              DataColumn(label: Text('Nombre')),
              DataColumn(label: Text('Símbolo')),
              DataColumn(label: Text('País')),
              DataColumn(label: Text('Dec.')),
              DataColumn(label: Text('Orden')),
              DataColumn(label: Text('Base')),
              DataColumn(label: Text('Activa')),
              DataColumn(label: Text('Acciones')),
            ],
            rows: _monedas.map((m) {
              final codigo = (m['codigo'] ?? '').toString();
              final esBase = m['es_base'] == true;
              final activa = m['activo'] == true;
              return DataRow(
                cells: [
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          codigo,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (m['es_sistema'] == true) ...[
                          const SizedBox(width: 6),
                          const Tooltip(
                            message: 'Moneda de sistema',
                            child: Icon(Icons.lock_outline, size: 14),
                          ),
                        ],
                      ],
                    ),
                  ),
                  DataCell(Text((m['nombre'] ?? '').toString())),
                  DataCell(Text((m['simbolo'] ?? '—').toString())),
                  DataCell(Text((m['pais'] ?? '—').toString())),
                  DataCell(Text(_num(m['decimales'])?.toInt().toString() ?? '—')),
                  DataCell(Text(_num(m['orden'])?.toInt().toString() ?? '—')),
                  DataCell(
                    esBase
                        ? const Icon(Icons.star, size: 18, color: Colors.amber)
                        : const Text('—'),
                  ),
                  DataCell(
                    _puedeEscribir
                        ? Switch(
                            value: activa,
                            onChanged: esBase
                                ? null
                                : (v) => _alternarActivo(m, v),
                          )
                        : Text(activa ? 'Sí' : 'No'),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Editar',
                          onPressed: _puedeEscribir
                              ? () => _abrirFormulario(moneda: m)
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.payments_outlined),
                          tooltip: 'Denominaciones',
                          onPressed: _puedeEscribir
                              ? () => _abrirDenominaciones(m)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
      itemCount: _monedas.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildTarjetaMoneda(_monedas[index]),
    );
  }

  Widget _buildTarjetaMoneda(Map<String, dynamic> m) {
    final codigo = (m['codigo'] ?? '').toString();
    final esBase = m['es_base'] == true;
    final activa = m['activo'] == true;
    return Card(
      child: ListTile(
        title: Row(
          children: [
            Text(
              codigo,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Text('${m['nombre'] ?? ''}'),
            if (esBase) ...[
              const SizedBox(width: 6),
              const Icon(Icons.star, size: 16, color: Colors.amber),
            ],
          ],
        ),
        subtitle: Text(
          '${m['simbolo'] ?? '—'} · orden ${_num(m['orden'])?.toInt() ?? '—'} · '
          '${_num(m['decimales'])?.toInt() ?? '—'} decimales · '
          '${activa ? 'activa' : 'inactiva'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed:
                  _puedeEscribir ? () => _abrirFormulario(moneda: m) : null,
            ),
            IconButton(
              icon: const Icon(Icons.payments_outlined),
              onPressed: _puedeEscribir ? () => _abrirDenominaciones(m) : null,
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- tasas

  Widget _buildTasas() {
    return ListView(
      padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
      children: [
        _buildTarjetaTasaAutomatica(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tasa global',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'Se usa como respaldo cuando la tienda no tiene tasa propia '
                  'para el par. Cada guardado inserta una versión nueva: el '
                  'histórico no se sobrescribe.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _puedeEscribir
                        ? () => _abrirFormularioTasa()
                        : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Registrar tasa'),
                  ),
                ),
                if (!_puedeEscribir) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Solo lectura: tu usuario no tiene nivel de acceso 1.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_tasas.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No hay tasas globales registradas.\n'
              'En la rama de desarrollo esto es normal: `tasas_conversion` '
              'está vacía. Las tiendas usan su tasa propia '
              '(`tasa_cambio_extraoficial`).',
              textAlign: TextAlign.center,
            ),
          )
        else
          ..._tasas.map(
            (t) => Card(
              child: ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: Text(
                  '${t['moneda_origen']} → ${t['moneda_destino']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Actualizada: ${_fecha(t['fecha_actualizacion'])}',
                ),
                trailing: Text(
                  _num(t['tasa'])?.toStringAsFixed(4) ?? '—',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _refrescando = false;

  /// Tarjeta con el estado de la tasa automática («el toque»).
  ///
  /// Es informativa: la tasa automática solo entra en juego cuando NO hay tasa
  /// manual configurada para el par (ver `fn_tasa_cambio`).
  Widget _buildTarjetaTasaAutomatica() {
    final theme = Theme.of(context);
    final estado = _estadoAuto;

    if (estado == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.cloud_off),
          title: const Text('Tasa automática no disponible'),
          subtitle: const Text(
            'El esquema `flow` no está accesible desde este proyecto. '
            'Configura las tasas manualmente.',
          ),
        ),
      );
    }

    final disponible = estado['disponible'] == true && estado['ok'] == true;
    if (!disponible) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.info_outline, color: theme.colorScheme.error),
          title: const Text('Tasa automática sin datos'),
          subtitle: Text((estado['error'] ?? 'Sin tasas en caché').toString()),
          trailing: _puedeEscribir
              ? TextButton(
                  onPressed: _refrescando ? null : _refrescarTasas,
                  child: const Text('Actualizar'),
                )
              : null,
        ),
      );
    }

    final vigente = estado['vigente'] == true;
    final tasas = estado['tasas_cup'];
    String valor(String codigo) {
      if (tasas is! Map) return '—';
      final v = _num(tasas[codigo]);
      return v == null ? '—' : v.toStringAsFixed(2);
    }

    final cubiertas = estado['monedas_cubiertas'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  vigente ? Icons.verified : Icons.warning_amber_rounded,
                  color: vigente ? Colors.green : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tasa automática («el toque»)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_puedeEscribir)
                  TextButton.icon(
                    onPressed: _refrescando ? null : _refrescarTasas,
                    icon: _refrescando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: const Text('Actualizar'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Fecha ${estado['fecha'] ?? '—'} · ${estado['hora'] ?? ''} · '
              'fuente ${estado['fuente'] ?? '—'}'
              '${vigente ? '' : ' · NO es de hoy'}',
              style: TextStyle(
                fontSize: 12,
                color: vigente
                    ? theme.colorScheme.onSurfaceVariant
                    : Colors.orange,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _chipTasa('USD → CUP', valor('USD')),
                _chipTasa('EUR → CUP', valor('EUR')),
                _chipTasa('MLC → CUP', valor('MLC')),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Cobertura del proveedor: '
              '${(cubiertas is List ? cubiertas.join(', ') : '—')}. '
              'Las monedas SIN tasa manual usan esta automáticamente; la tasa '
              'manual, si existe, siempre tiene prioridad.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipTasa(String etiqueta, String valor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(etiqueta, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          Text(
            valor,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Future<void> _refrescarTasas() async {
    setState(() => _refrescando = true);
    try {
      final res = await MonedasService.refrescarTasas(forzar: true);
      if (!mounted) return;
      final ingeridos = (res?['ingeridos'] as num?)?.toInt() ?? 0;
      final vigente = res?['vigente'] == true;
      final ok = res?['ok'] == true;

      if (ingeridos > 0 || vigente) {
        _avisar('Tasa actualizada');
      } else if (res?['disponible'] == false) {
        _avisar(
          (res?['error'] ?? 'Tasa automática no disponible').toString(),
          error: true,
        );
      } else if (ok) {
        _avisar(
          'El proveedor aún no ha respondido. La caché anterior sigue en uso; '
          'vuelve a intentarlo en unos segundos.',
        );
      } else {
        _avisar(
          (res?['error'] ?? 'No se pudo actualizar la tasa').toString(),
          error: true,
        );
      }
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      _avisar(_MonedasScreenState._mensajeError(e), error: true);
    } finally {
      if (mounted) setState(() => _refrescando = false);
    }
  }

  Future<void> _abrirFormularioTasa() async {
    final guardado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TasaGlobalDialog(monedas: _monedas),
    );
    if (guardado == true) {
      _avisar('Tasa global registrada');
      await _cargar();
    }
  }

  // ----------------------------------------------------------------- helpers

  String _fecha(dynamic valor) {
    final raw = valor?.toString();
    if (raw == null || raw.isEmpty) return '—';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static String _mensajeError(Object e) {
    final texto = e.toString();
    // Postgres devuelve "P0001: <RAISE EXCEPTION mensaje>"; se muestra el mensaje.
    final idx = texto.indexOf('P0001:');
    if (idx >= 0) {
      final resto = texto.substring(idx + 6).trim();
      final corte = resto.indexOf('\n');
      return corte > 0 ? resto.substring(0, corte).trim() : resto;
    }
    return texto.length > 220 ? '${texto.substring(0, 220)}…' : texto;
  }
}

/// Lee un valor numérico venga como `num` o como `String` (Postgres `numeric`).
num? _num(dynamic valor) {
  if (valor == null) return null;
  if (valor is num) return valor;
  return num.tryParse(valor.toString());
}

// ============================================================================
// Diálogo de alta / edición de moneda
// ============================================================================

class _MonedaFormDialog extends StatefulWidget {
  const _MonedaFormDialog({this.moneda});

  final Map<String, dynamic>? moneda;

  @override
  State<_MonedaFormDialog> createState() => _MonedaFormDialogState();
}

class _MonedaFormDialogState extends State<_MonedaFormDialog> {
  late final TextEditingController _codigo;
  late final TextEditingController _nombre;
  late final TextEditingController _simbolo;
  late final TextEditingController _pais;
  late final TextEditingController _decimales;
  late final TextEditingController _orden;

  late bool _activo;
  bool _guardando = false;

  bool get _esEdicion => widget.moneda != null;

  @override
  void initState() {
    super.initState();
    final m = widget.moneda;
    _codigo = TextEditingController(text: (m?['codigo'] ?? '').toString());
    _nombre = TextEditingController(text: (m?['nombre'] ?? '').toString());
    _simbolo = TextEditingController(text: (m?['simbolo'] ?? '').toString());
    _pais = TextEditingController(text: (m?['pais'] ?? '').toString());
    _decimales = TextEditingController(
      text: _num(m?['decimales'])?.toInt().toString() ?? '2',
    );
    _orden = TextEditingController(
      text: _num(m?['orden'])?.toInt().toString() ?? '100',
    );
    _activo = m?['activo'] != false;
  }

  @override
  void dispose() {
    _codigo.dispose();
    _nombre.dispose();
    _simbolo.dispose();
    _pais.dispose();
    _decimales.dispose();
    _orden.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final codigo = _codigo.text.trim().toUpperCase();
    final nombre = _nombre.text.trim();

    if (codigo.length != 3 || !RegExp(r'^[A-Z]{3}$').hasMatch(codigo)) {
      _avisar('El código debe ser ISO-4217: exactamente 3 letras (ej. USD).');
      return;
    }
    if (nombre.isEmpty) {
      _avisar('El nombre es obligatorio.');
      return;
    }

    final decimales = int.tryParse(_decimales.text.trim()) ?? 2;
    final orden = int.tryParse(_orden.text.trim()) ?? 100;
    if (decimales < 0 || decimales > 6) {
      _avisar('Los decimales deben estar entre 0 y 6.');
      return;
    }

    setState(() => _guardando = true);
    try {
      if (_esEdicion) {
        await MonedasService.actualizar(
          codigo: codigo,
          nombre: nombre,
          simbolo: _simbolo.text,
          pais: _pais.text,
          decimales: decimales,
          orden: orden,
          activo: _activo,
        );
      } else {
        await MonedasService.crear(
          codigo: codigo,
          nombre: nombre,
          simbolo: _simbolo.text,
          pais: _pais.text,
          decimales: decimales,
          orden: orden,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _avisar(_MonedasScreenState._mensajeError(e), error: true);
    }
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

  @override
  Widget build(BuildContext context) {
    final edicion = _esEdicion;
    return AlertDialog(
      title: Text(edicion ? 'Editar moneda' : 'Nueva moneda'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _codigo,
              enabled: !edicion && !_guardando,
              textCapitalization: TextCapitalization.characters,
              maxLength: 3,
              decoration: const InputDecoration(
                labelText: 'Código ISO-4217',
                hintText: 'USD',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nombre,
              enabled: !_guardando,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Dólar Estadounidense',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _simbolo,
              enabled: !_guardando,
              maxLength: 10,
              decoration: const InputDecoration(
                labelText: 'Símbolo',
                hintText: '\$',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pais,
              enabled: !_guardando,
              decoration: const InputDecoration(
                labelText: 'País (opcional)',
                hintText: 'Estados Unidos',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _decimales,
                    enabled: !_guardando,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Decimales',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _orden,
                    enabled: !_guardando,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Orden',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            if (edicion) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activa'),
                subtitle: const Text(
                  'No se puede desactivar la moneda base ni una con pagos.',
                ),
                value: _activo,
                onChanged: _guardando
                    ? null
                    : (v) => setState(() => _activo = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(edicion ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }
}

// ============================================================================
// Diálogo de denominaciones
// ============================================================================

class _DenominacionesDialog extends StatefulWidget {
  const _DenominacionesDialog({required this.codigo});

  final String codigo;

  @override
  State<_DenominacionesDialog> createState() => _DenominacionesDialogState();
}

class _DenominacionesDialogState extends State<_DenominacionesDialog> {
  final TextEditingController _nueva = TextEditingController();

  /// Lista local editable: {denominacion: num, active: bool}
  final List<Map<String, dynamic>> _items = [];
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nueva.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final filas = await MonedasService.listarDenominaciones(widget.codigo);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(
            filas.map(
              (f) => {
                'denominacion': _num(f['denominacion']) ?? 0,
                'active': f['active'] != false,
              },
            ),
          );
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _avisar(_MonedasScreenState._mensajeError(e), error: true);
    }
  }

  void _agregar() {
    final valor = num.tryParse(_nueva.text.trim().replaceAll(',', '.'));
    if (valor == null || valor <= 0) {
      _avisar('Introduce un valor numérico mayor que cero.');
      return;
    }
    if (_items.any((i) => _num(i['denominacion']) == valor)) {
      _avisar('Esa denominación ya está en la lista.');
      return;
    }
    setState(() {
      _items.add({'denominacion': valor, 'active': true});
      _items.sort(
        (a, b) => (_num(b['denominacion']) ?? 0).compareTo(
          _num(a['denominacion']) ?? 0,
        ),
      );
    });
    _nueva.clear();
  }

  Future<void> _guardar() async {
    if (_items.isEmpty) {
      _avisar('Añade al menos una denominación.');
      return;
    }
    setState(() => _guardando = true);
    try {
      await MonedasService.guardarDenominaciones(widget.codigo, _items);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _avisar(_MonedasScreenState._mensajeError(e), error: true);
    }
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Denominaciones · ${widget.codigo}'),
      content: SizedBox(
        width: 420,
        child: _cargando
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nueva,
                          enabled: !_guardando,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Nueva denominación',
                            hintText: '500',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _agregar(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _guardando ? null : _agregar,
                        icon: const Icon(Icons.add),
                        tooltip: 'Añadir',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: _items
                            .map(
                              (item) => CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${_num(item['denominacion'])} '
                                  '${widget.codigo}',
                                ),
                                value: item['active'] == true,
                                onChanged: _guardando
                                    ? null
                                    : (v) => setState(
                                        () => item['active'] = v ?? false,
                                      ),
                                secondary: IconButton(
                                  icon: const Icon(Icons.close),
                                  tooltip: 'Quitar de la lista',
                                  onPressed: _guardando
                                      ? null
                                      : () => setState(
                                          () => _items.remove(item),
                                        ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Desmarcar deja la denominación inactiva (no se borra, '
                    'para no romper referencias históricas).',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: (_guardando || _cargando) ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

// ============================================================================
// Diálogo de tasa global
// ============================================================================

class _TasaGlobalDialog extends StatefulWidget {
  const _TasaGlobalDialog({required this.monedas});

  final List<Map<String, dynamic>> monedas;

  @override
  State<_TasaGlobalDialog> createState() => _TasaGlobalDialogState();
}

class _TasaGlobalDialogState extends State<_TasaGlobalDialog> {
  final TextEditingController _tasa = TextEditingController();

  String _origen = 'USD';
  String _destino = 'CUP';
  bool _guardando = false;

  List<String> get _codigos => widget.monedas
      .map((m) => (m['codigo'] ?? '').toString())
      .where((c) => c.isNotEmpty)
      .toList();

  @override
  void initState() {
    super.initState();
    final codigos = _codigos;
    if (codigos.contains('USD')) _origen = 'USD';
    if (codigos.contains('CUP')) _destino = 'CUP';
  }

  @override
  void dispose() {
    _tasa.dispose();
    super.dispose();
  }

  /// Rellena el campo con la tasa automática del par (punto de partida para
  /// que el usuario ajuste su «custom»). No guarda nada.
  Future<void> _traerAutomatica() async {
    try {
      final valor = await MonedasService.tasaAutomatica(
        origen: _origen,
        destino: _destino,
      );
      if (!mounted) return;
      if (valor == null || valor <= 0) {
        _avisar(
          'No hay tasa automática para $_origen → $_destino. '
          'El proveedor solo cubre USD, EUR y MLC.',
        );
        return;
      }
      setState(() => _tasa.text = valor.toStringAsFixed(4));
      _avisar('Tasa automática aplicada: ${valor.toStringAsFixed(4)}');
    } catch (e) {
      if (!mounted) return;
      _avisar(_MonedasScreenState._mensajeError(e), error: true);
    }
  }

  Future<void> _guardar() async {
    final valor = double.tryParse(_tasa.text.trim().replaceAll(',', '.'));
    if (valor == null || valor <= 0) {
      _avisar('La tasa debe ser un número mayor que cero.');
      return;
    }
    if (_origen == _destino) {
      _avisar('Origen y destino deben ser monedas distintas.');
      return;
    }
    setState(() => _guardando = true);
    try {
      await MonedasService.guardarTasaGlobal(
        origen: _origen,
        destino: _destino,
        tasa: valor,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _avisar(_MonedasScreenState._mensajeError(e), error: true);
    }
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

  @override
  Widget build(BuildContext context) {
    final codigos = _codigos;
    return AlertDialog(
      title: const Text('Registrar tasa global'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: codigos.contains(_origen) ? _origen : null,
            decoration: const InputDecoration(
              labelText: 'Moneda origen',
              border: OutlineInputBorder(),
            ),
            items: codigos
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: _guardando
                ? null
                : (v) => setState(() => _origen = v ?? _origen),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: codigos.contains(_destino) ? _destino : null,
            decoration: const InputDecoration(
              labelText: 'Moneda destino',
              border: OutlineInputBorder(),
            ),
            items: codigos
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: _guardando
                ? null
                : (v) => setState(() => _destino = v ?? _destino),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tasa,
            enabled: !_guardando,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Tasa',
              hintText: '1 USD = ? CUP',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _guardando ? null : _traerAutomatica,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Traer tasa automática'),
            ),
          ),
          Text(
            'La automática («el toque») solo cubre USD, EUR y MLC. '
            'Si la ajustas, se guarda como tasa manual y pasa a tener prioridad.',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}