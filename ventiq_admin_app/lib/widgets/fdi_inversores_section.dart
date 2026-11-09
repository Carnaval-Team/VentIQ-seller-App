import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_colors.dart';
import '../services/fondo_inversion_service.dart';
import '../services/permissions_service.dart';
import 'fdi_inversor_dialog.dart';

enum FdiInversoresVista { configuracion, pagos }

/// Configuración de inversores, o el reporte de repartos y pagos.
/// Las dos vistas comparten permisos y el alta, pero no el mismo contenido:
/// Config solo edita la participación; Inversores muestra resumen e historial.
class FdiInversoresSection extends StatefulWidget {
  final int idTienda;
  final FdiInversoresVista vista;
  final String Function(int? idMedio)? nombreMedio;

  const FdiInversoresSection({
    super.key,
    required this.idTienda,
    this.vista = FdiInversoresVista.configuracion,
    this.nombreMedio,
  });

  @override
  State<FdiInversoresSection> createState() => _FdiInversoresSectionState();
}

class _FdiInversoresSectionState extends State<FdiInversoresSection> {
  final _service = FondoInversionService();
  final _fmt = NumberFormat('#,##0.00');
  final _fecha = DateFormat('dd/MM/yyyy');
  final _fechaHora = DateFormat('dd/MM/yyyy HH:mm');

  List<Map<String, dynamic>> _inversores = [];
  List<Map<String, dynamic>> _historial = [];
  DateTimeRange? _periodo;
  int? _inversor;
  bool _loading = true;
  bool _busy = false;
  bool _allowed = false;
  String? _error;

  bool get _esPagos => widget.vista == FdiInversoresVista.pagos;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final conservar = _inversores.isNotEmpty || _historial.isNotEmpty;
    setState(() {
      if (!conservar) _loading = true;
      _error = null;
    });
    try {
      final allowed = await PermissionsService().canViewGanancias();
      if (!allowed) {
        if (mounted) {
          setState(() {
            _allowed = false;
            _loading = false;
          });
        }
        return;
      }
      final inversores = await _service.listInversores(widget.idTienda);
      final historial = _esPagos
          ? await _service.historialInversores(
              widget.idTienda,
              desde: _periodo?.start,
              hasta: _periodo?.end,
            )
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _allowed = true;
        _inversores = inversores;
        _historial = historial;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _editar([Map<String, dynamic>? inversor]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => FdiInversorDialog(inversor: inversor),
    );
    if (result != null && mounted) {
      await _run(
        () => _service.guardarInversor(
          widget.idTienda,
          id: (inversor?['id'] as num?)?.toInt(),
          nombre: result['nombre'] as String,
          porcentaje: result['porcentaje'] as double,
          activo: result['activo'] as bool,
        ),
      );
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pagar(Map<String, dynamic> reparto) async {
    final referencia = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar pago realizado'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${reparto['nombre_snapshot']} · ${_fmt.format(reparto['monto'])} ${reparto['moneda']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Confirma únicamente si el inversor ya recibió este importe. No se realizará una transferencia bancaria.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: referencia,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Referencia o comprobante',
                    border: OutlineInputBorder(),
                  ),
                  validator: (s) => s == null || s.trim().isEmpty
                      ? 'Indique la referencia'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Confirmar pago'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _run(
        () => _service.pagarInversor(
          (reparto['id'] as num).toInt(),
          referencia.text.trim(),
        ),
      );
    }
    referencia.dispose();
  }

  Future<void> _elegirPeriodo() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _periodo,
    );
    if (result == null || !mounted) return;
    setState(() => _periodo = result);
    await _load();
  }

  List<Map<String, dynamic>> get _filas => _historial
      .where(
        (r) =>
            _inversor == null ||
            (r['id_inversor'] as num?)?.toInt() == _inversor,
      )
      .toList();

  String _nombreDe(Map<String, dynamic> reparto) {
    final id = (reparto['id_inversor'] as num?)?.toInt();
    for (final i in _inversores) {
      if ((i['id'] as num?)?.toInt() == id) {
        return i['nombre']?.toString() ?? '';
      }
    }
    return reparto['nombre_snapshot']?.toString() ?? 'Inversor';
  }

  String _medioDe(Map<String, dynamic> reparto) {
    final id = (reparto['id_medio_pago'] as num?)?.toInt();
    final nombre = widget.nombreMedio?.call(id);
    if (nombre != null && nombre.isNotEmpty) return nombre;
    return id == null ? 'Medio no indicado' : 'Medio #$id';
  }

  String _dia(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return value?.toString() ?? '';
    return _fecha.format(parsed.toLocal());
  }

  String _momento(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return value?.toString() ?? '';
    return _fechaHora.format(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _estado(const CircularProgressIndicator(color: AppColors.primary));
    }
    if (!_allowed && _error == null) {
      if (!_esPagos) return const SizedBox.shrink();
      return _mensaje(
        'No tienes permiso para ver los pagos a inversores.',
        accion: null,
      );
    }
    if (_esPagos) return _pagos();
    return _configuracion();
  }

  Widget _estado(Widget child) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(child: child),
    );
    if (!_esPagos) return body;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [body],
    );
  }

  Widget _mensaje(
    String texto, {
    VoidCallback? accion,
    String accionLabel = 'Reintentar',
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          texto,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        if (accion != null)
          TextButton(onPressed: accion, child: Text(accionLabel)),
      ],
    );
    if (!_esPagos) {
      return Padding(padding: const EdgeInsets.only(top: 8), child: content);
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [content],
    );
  }

  Widget _configuracion() {
    final total = _inversores
        .where((i) => i['activo'] == true)
        .fold<double>(
          0,
          (s, i) => s + ((i['porcentaje'] as num?)?.toDouble() ?? 0),
        );
    final completa = (total - 100).abs() < 0.0001;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(child: Text('Inversores', style: _titulo)),
            TextButton.icon(
              onPressed: _busy ? null : () => _editar(),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Agregar'),
            ),
          ],
        ),
        const Text(
          'Quién participa del fondo y con qué porcentaje. Los pagos y el historial están en la pestaña Inversores.',
          style: _ayuda,
        ),
        const SizedBox(height: 8),
        Text(
          completa
              ? 'Participación activa: ${total.toStringAsFixed(4)}%. Lista para liquidar.'
              : 'Participación activa: ${total.toStringAsFixed(4)}%. Debe sumar 100% para liquidar.',
          style: const TextStyle(color: AppColors.textPrimary, height: 1.35),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: AppColors.error)),
          TextButton(onPressed: _load, child: const Text('Reintentar')),
        ],
        if (_inversores.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'Agrega los inversores y sus porcentajes antes de crear una liquidación.',
              style: _ayuda,
            ),
          )
        else
          for (final i in _inversores)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                i['nombre']?.toString() ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: Text(
                '${i['porcentaje']}% · ${i['activo'] == true ? 'Activo' : 'Inactivo'}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              trailing: IconButton(
                tooltip: 'Editar inversor',
                onPressed: _busy ? null : () => _editar(i),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
      ],
    );
  }

  Widget _pagos() {
    final filas = _filas;
    final resumen = _resumen(filas);
    final pendientes = filas
        .where(
          (r) =>
              r['pagado_at'] == null &&
              ((r['monto'] as num?)?.toDouble() ?? 0) > 0,
        )
        .length;
    final pagados = filas.where((r) => r['pagado_at'] != null).length;
    final periodo = _periodo == null
        ? 'Filtrar período'
        : '${_fecha.format(_periodo!.start)} – ${_fecha.format(_periodo!.end)}';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.primary,
              backgroundColor: AppColors.border,
            ),
          ),
        const Text('Pagos a inversores', style: _titulo),
        const SizedBox(height: 4),
        const Text(
          'Repartos generados por las liquidaciones y los pagos que ya se registraron. Cada moneda se suma por separado.',
          style: _ayuda,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          key: ValueKey('inversor-$_inversor'),
          initialValue: _inversor,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Inversor',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<int>(
              value: null,
              child: Text('Todos los inversores'),
            ),
            for (final i in _inversores)
              DropdownMenuItem(
                value: (i['id'] as num).toInt(),
                child: Text(
                  i['nombre']?.toString() ?? '',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _busy ? null : (v) => setState(() => _inversor = v),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed: _busy ? null : _elegirPeriodo,
              icon: const Icon(Icons.date_range),
              label: Text(periodo),
            ),
            if (_periodo != null)
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        setState(() => _periodo = null);
                        _load();
                      },
                child: const Text('Historial completo'),
              ),
          ],
        ),
        const Text(
          'El período incluye liquidaciones que se solapan con esas fechas.',
          style: _ayuda,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.error)),
          TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('Reintentar'),
          ),
        ],
        const SizedBox(height: 24),
        const Text('Resumen', style: _titulo),
        const SizedBox(height: 4),
        Text(
          filas.isEmpty
              ? 'Sin repartos en este filtro.'
              : '$pendientes pendientes · $pagados pagados',
          style: const TextStyle(color: AppColors.textSecondary, height: 1.35),
        ),
        if (resumen.isNotEmpty) ...[
          const SizedBox(height: 12),
          _tablaResumen(resumen),
        ],
        const SizedBox(height: 24),
        const Text('Historial', style: _titulo),
        const SizedBox(height: 12),
        if (filas.isEmpty)
          const Text(
            'No hay repartos para este filtro. Las liquidaciones anteriores a esta actualización no se reparten de forma retroactiva.',
            style: _ayuda,
          )
        else
          for (var i = 0; i < filas.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            _filaHistorial(filas[i]),
          ],
      ],
    );
  }

  List<_Acumulado> _resumen(List<Map<String, dynamic>> filas) {
    final map = <String, _Acumulado>{};
    for (final r in filas) {
      final id = (r['id_inversor'] as num?)?.toInt();
      final moneda = r['moneda']?.toString() ?? '';
      final key = '$id|$moneda';
      final item = map.putIfAbsent(key, () => _Acumulado(_nombreDe(r), moneda));
      final monto = (r['monto'] as num?)?.toDouble() ?? 0;
      if (r['pagado_at'] == null) {
        item.pendiente += monto;
      } else {
        item.pagado += monto;
      }
    }
    final items = map.values.toList()
      ..sort((a, b) {
        final nombre = a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
        if (nombre != 0) return nombre;
        return a.moneda.compareTo(b.moneda);
      });
    return items;
  }

  Widget _tablaResumen(List<_Acumulado> items) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${items[i].nombre} · ${items[i].moneda}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _monto('Asignado', items[i].asignado, items[i].moneda),
                  const SizedBox(height: 6),
                  _monto('Pendiente', items[i].pendiente, items[i].moneda),
                  const SizedBox(height: 6),
                  _monto('Pagado', items[i].pagado, items[i].moneda),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _monto(String label, double valor, String moneda) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.2,
            ),
          ),
        ),
        Expanded(
          child: Text(
            '${_fmt.format(valor)} $moneda',
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }

  Widget _filaHistorial(Map<String, dynamic> r) {
    final pagado = r['pagado_at'] != null;
    final monto = (r['monto'] as num?)?.toDouble() ?? 0;
    final puedePagar = !pagado && monto > 0;
    final referencia = r['referencia_pago']?.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _nombreDe(r),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${_fmt.format(monto)} ${r['moneda'] ?? ''}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Liquidación #${r['id_liquidacion']} · ${r['porcentaje_snapshot']}% · ${_medioDe(r)}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          Text(
            '${_dia(r['fecha_desde'])} – ${_dia(r['fecha_hasta'])}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            pagado
                ? 'Pagado ${_momento(r['pagado_at'])}'
                      '${referencia != null && referencia.isNotEmpty ? ' · $referencia' : ''}'
                : 'Pendiente de pago',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (puedePagar)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy ? null : () => _pagar(r),
                child: const Text('Registrar pago'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Acumulado {
  _Acumulado(this.nombre, this.moneda);

  final String nombre;
  final String moneda;
  double pendiente = 0;
  double pagado = 0;

  double get asignado => pendiente + pagado;
}

const _titulo = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w700,
  color: AppColors.textPrimary,
);

const _ayuda = TextStyle(
  fontSize: 13,
  height: 1.4,
  color: AppColors.textSecondary,
);
