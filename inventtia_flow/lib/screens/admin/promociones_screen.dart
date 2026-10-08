import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../models/config_precio.dart';
import '../../services/auth_service.dart';
import '../../services/promocion_service.dart';

/// Gestión de promociones de un local-servicio.
///
/// El descuento afecta a lo que se cobra, así que la pantalla insiste en la
/// vigencia y el cupo: una promo mal configurada (sin fecha de fin, con cupo
/// agotado) se cobra igual hasta que alguien la desactiva.
class PromocionesScreen extends StatefulWidget {
  final int idLocalServicio;
  final String nombreServicio;

  const PromocionesScreen({
    super.key,
    required this.idLocalServicio,
    required this.nombreServicio,
  });

  @override
  State<PromocionesScreen> createState() => _PromocionesScreenState();
}

class _PromocionesScreenState extends State<PromocionesScreen> {
  List<Promocion> _promos = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final uuid = AuthService.currentUserId;
    if (uuid == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final promos = await PromocionService.listar(
        uuidUsuario: uuid,
        idLocalServicio: widget.idLocalServicio,
      );
      if (!mounted) return;
      setState(() {
        _promos = promos;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  Future<void> _abrirFormulario({Promocion? promo}) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _PromocionSheet(
        idLocalServicio: widget.idLocalServicio,
        nombreServicio: widget.nombreServicio,
        promo: promo,
      ),
    );
    if (guardado != true || !mounted) return;
    await _cargar();
    if (!mounted) return;
    _avisar(promo == null ? 'Promoción creada.' : 'Promoción actualizada.');
  }

  Future<void> _eliminar(Promocion promo) async {
    final uuid = AuthService.currentUserId;
    if (uuid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Eliminar promoción'),
        content: Text(
          '¿Eliminar «${promo.titulo}»? Si quieres conservar el histórico, '
          'desactívala en lugar de borrarla.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await PromocionService.eliminar(uuidUsuario: uuid, id: promo.id);
      await _cargar();
      if (mounted) _avisar('Promoción eliminada.');
    } catch (e) {
      if (mounted) _avisar('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _alternarActivo(Promocion promo) async {
    final uuid = AuthService.currentUserId;
    if (uuid == null) return;
    try {
      await PromocionService.guardar(
        uuidUsuario: uuid,
        idLocalServicio: widget.idLocalServicio,
        id: promo.id,
        titulo: promo.titulo,
        tipo: promo.tipo,
        valor: promo.valor,
        moneda: promo.moneda,
        desde: promo.desde,
        hasta: promo.hasta,
        cupoTotal: promo.cupoTotal,
        activo: !promo.activo,
      );
      await _cargar();
      if (mounted) {
        _avisar(
          promo.activo ? 'Promoción desactivada.' : 'Promoción activada.',
        );
      }
    } catch (e) {
      if (mounted) _avisar('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  void _avisar(String mensaje, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          backgroundColor: error ? AppTheme.error : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Promociones')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva promoción'),
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _cargar,
        child: _cargando && _promos.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _Explicacion(nombreServicio: widget.nombreServicio),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _ErrorCard(mensaje: _error!, onReintentar: _cargar),
                  ],
                  const SizedBox(height: 16),
                  if (_promos.isEmpty && _error == null)
                    const _Vacio()
                  else
                    ..._promos.map(
                      (p) => _PromocionTile(
                        promo: p,
                        onEditar: () => _abrirFormulario(promo: p),
                        onAlternar: () => _alternarActivo(p),
                        onEliminar: () => _eliminar(p),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _Explicacion extends StatelessWidget {
  final String nombreServicio;
  const _Explicacion({required this.nombreServicio});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppTheme.primary),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombreServicio,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'El descuento se aplica al confirmar la reserva. Si la promo '
                  'tiene cupo, cada reserva descuenta uno y al agotarse deja de '
                  'aplicarse automáticamente.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String mensaje;
  final Future<void> Function() onReintentar;
  const _ErrorCard({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No se pudieron leer las promociones',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            mensaje,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onReintentar,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.local_offer_outlined,
            size: 38,
            color: AppTheme.textSecondary,
          ),
          SizedBox(height: 10),
          Text(
            'Sin promociones',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 4),
          Text(
            'Crea una para mostrar un descuento en el servicio.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _PromocionTile extends StatelessWidget {
  final Promocion promo;
  final VoidCallback onEditar;
  final VoidCallback onAlternar;
  final VoidCallback onEliminar;

  const _PromocionTile({
    required this.promo,
    required this.onEditar,
    required this.onAlternar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final agotada = promo.cuposRestantes != null && promo.cuposRestantes == 0;
    final vigente = promo.activo && !agotada;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: vigente
              ? AppTheme.success.withValues(alpha: 0.40)
              : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: vigente
                  ? AppTheme.success
                  : AppTheme.textSecondary.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              promo.etiquetaDescuento,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  promo.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _resumenVigencia(promo),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (promo.tieneCupo)
                  Text(
                    '${promo.cupoUsado} de ${promo.cupoTotal} usados',
                    style: TextStyle(
                      fontSize: 11,
                      color: agotada ? AppTheme.error : AppTheme.textSecondary,
                      fontWeight: agotada ? FontWeight.w700 : null,
                    ),
                  ),
                if (!promo.activo)
                  const Text(
                    'INACTIVA',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Switch.adaptive(
            value: promo.activo,
            activeTrackColor: AppTheme.primary,
            onChanged: (_) => onAlternar(),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opciones',
            onSelected: (v) {
              if (v == 'editar') onEditar();
              if (v == 'eliminar') onEliminar();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'editar', child: Text('Editar')),
              PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
            ],
          ),
        ],
      ),
    );
  }

  static String _resumenVigencia(Promocion p) {
    String f(DateTime d) {
      final dia = d.day.toString().padLeft(2, '0');
      final mes = d.month.toString().padLeft(2, '0');
      return '$dia/$mes';
    }

    if (p.desde == null && p.hasta == null) return 'Sin fecha límite';
    if (p.desde != null && p.hasta != null) {
      return 'Del ${f(p.desde!)} al ${f(p.hasta!)}';
    }
    if (p.hasta != null) return 'Hasta el ${f(p.hasta!)}';
    return 'Desde el ${f(p.desde!)}';
  }
}

/// Formulario de alta/edición de promoción.
class _PromocionSheet extends StatefulWidget {
  final int idLocalServicio;
  final String nombreServicio;
  final Promocion? promo;

  const _PromocionSheet({
    required this.idLocalServicio,
    required this.nombreServicio,
    this.promo,
  });

  @override
  State<_PromocionSheet> createState() => _PromocionSheetState();
}

class _PromocionSheetState extends State<_PromocionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titulo;
  late final TextEditingController _valor;
  late final TextEditingController _cupo;
  late String _tipo;
  late String _moneda;
  DateTime? _desde;
  DateTime? _hasta;
  bool _activo = true;
  bool _guardando = false;

  bool get _esEdicion => widget.promo != null;

  @override
  void initState() {
    super.initState();
    final p = widget.promo;
    _titulo = TextEditingController(text: p?.titulo ?? '');
    _valor = TextEditingController(
      text: p == null ? '' : Promocion.formatearNumero(p.valor),
    );
    _cupo = TextEditingController(text: p?.cupoTotal?.toString() ?? '');
    _tipo = p?.tipo ?? 'porcentaje';
    _moneda = p?.moneda ?? 'USD';
    _desde = p?.desde;
    _hasta = p?.hasta;
    _activo = p?.activo ?? true;
  }

  @override
  void dispose() {
    _titulo.dispose();
    _valor.dispose();
    _cupo.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha({required bool esDesde}) async {
    final inicial = (esDesde ? _desde : _hasta) ?? DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: esDesde ? 'Inicio de la promoción' : 'Fin de la promoción',
    );
    if (fecha == null || !mounted) return;
    setState(() {
      if (esDesde) {
        _desde = fecha;
      } else {
        // El fin se guarda al final del día: una promo que termina "el 10"
        // debe cubrir el día 10 completo. El servidor compara con `< hasta`,
        // así que guardar las 00:00 del día 10 la cortaría un día antes.
        _hasta = DateTime(fecha.year, fecha.month, fecha.day, 23, 59, 59);
      }
    });
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final uuid = AuthService.currentUserId;
    if (uuid == null) return;

    final valor = double.tryParse(_valor.text.replaceAll(',', '.')) ?? 0;
    final cupo = _cupo.text.trim().isEmpty
        ? null
        : int.tryParse(_cupo.text.trim());

    setState(() => _guardando = true);
    try {
      await PromocionService.guardar(
        uuidUsuario: uuid,
        idLocalServicio: widget.idLocalServicio,
        id: widget.promo?.id,
        titulo: _titulo.text.trim(),
        tipo: _tipo,
        valor: valor,
        moneda: _tipo == 'monto' ? _moneda : null,
        desde: _desde,
        hasta: _hasta,
        cupoTotal: cupo,
        activo: _activo,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('$e'.replaceFirst('Exception: ', '')),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + insets.bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _esEdicion ? 'Editar promoción' : 'Nueva promoción',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.nombreServicio,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titulo,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Título visible',
                  hintText: 'Ej: 20 % en tu primera cita',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Escribe un título'
                    : null,
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'porcentaje',
                    label: Text('%'),
                    icon: Icon(Icons.percent_rounded, size: 17),
                  ),
                  ButtonSegment(
                    value: 'monto',
                    label: Text('Monto'),
                    icon: Icon(Icons.attach_money_rounded, size: 17),
                  ),
                ],
                selected: {_tipo},
                onSelectionChanged: (s) => setState(() => _tipo = s.first),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _valor,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _tipo == 'porcentaje'
                            ? 'Descuento (%)'
                            : 'Descuento',
                      ),
                      validator: (v) {
                        final n = double.tryParse(
                          (v ?? '').replaceAll(',', '.'),
                        );
                        if (n == null || n <= 0) return 'Mayor que 0';
                        if (_tipo == 'porcentaje' && n > 100) {
                          return 'Máximo 100';
                        }
                        return null;
                      },
                    ),
                  ),
                  if (_tipo == 'monto') ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _moneda,
                        decoration: const InputDecoration(labelText: 'Moneda'),
                        items: MonedasApp.todas
                            .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _moneda = v);
                        },
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cupo,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Cupo (opcional)',
                  helperText:
                      'Cuántas reservas pueden usarla. Vacío = sin límite.',
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null;
                  final n = int.tryParse(t);
                  if (n == null || n <= 0) return 'Mayor que 0';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _BotonFecha(
                      etiqueta: 'Desde',
                      valor: _desde,
                      onTap: () => _elegirFecha(esDesde: true),
                      onLimpiar: _desde == null
                          ? null
                          : () => setState(() => _desde = null),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BotonFecha(
                      etiqueta: 'Hasta',
                      valor: _hasta,
                      onTap: () => _elegirFecha(esDesde: false),
                      onLimpiar: _hasta == null
                          ? null
                          : () => setState(() => _hasta = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _activo,
                activeTrackColor: AppTheme.primary,
                onChanged: (v) => setState(() => _activo = v),
                title: const Text('Activa'),
                subtitle: const Text(
                  'Solo las activas se aplican al cobrar.',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _esEdicion ? 'Guardar cambios' : 'Crear promoción',
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BotonFecha extends StatelessWidget {
  final String etiqueta;
  final DateTime? valor;
  final VoidCallback onTap;
  final VoidCallback? onLimpiar;

  const _BotonFecha({
    required this.etiqueta,
    required this.valor,
    required this.onTap,
    this.onLimpiar,
  });

  @override
  Widget build(BuildContext context) {
    final texto = valor == null
        ? 'Sin límite'
        : '${valor!.day.toString().padLeft(2, '0')}/'
              '${valor!.month.toString().padLeft(2, '0')}/${valor!.year}';
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.event_outlined, size: 17),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            etiqueta,
            style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(texto, style: const TextStyle(fontSize: 12)),
              if (onLimpiar != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onLimpiar,
                  child: const Icon(Icons.close_rounded, size: 14),
                ),
              ],
            ],
          ),
        ],
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        alignment: Alignment.centerLeft,
      ),
    );
  }
}
