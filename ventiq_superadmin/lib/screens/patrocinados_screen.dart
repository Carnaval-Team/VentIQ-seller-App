import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/campana.dart';
import '../services/auth_service.dart';
import '../services/campana_service.dart';
import '../widgets/app_drawer.dart';

/// Espacio patrocinado del Home del cliente.
///
/// **No es lo mismo que una promoción.** Una promoción descuenta el precio y la
/// crea el admin de la entidad para sus servicios; una campaña **destaca** un
/// servicio o una entidad en el Home y la cura el superadmin. Una campaña jamás
/// cambia el importe que paga el cliente.
class PatrocinadosScreen extends StatefulWidget {
  const PatrocinadosScreen({super.key});

  @override
  State<PatrocinadosScreen> createState() => _PatrocinadosScreenState();
}

class _PatrocinadosScreenState extends State<PatrocinadosScreen> {
  List<Campana> _campanas = const [];
  List<({int id, String etiqueta})> _destinos = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final campanas = await CampanaService.listar(
        uuidUsuario: AuthService.currentSuperAdmin?.uuid ?? '',
      );
      if (!mounted) return;
      setState(() {
        _campanas = campanas;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _mensajeError(e);
        _cargando = false;
      });
    }
  }

  /// Traduce el fallo más probable (migración sin aplicar) a algo accionable.
  String _mensajeError(Object e) {
    final t = e.toString();
    if (t.contains('PGRST202') || t.contains('Could not find the function')) {
      return 'Falta aplicar la migración 28_patrocinados.sql en Supabase.';
    }
    return t.replaceFirst('Exception: ', '');
  }

  Future<void> _abrirFormulario({Campana? campana}) async {
    // Los destinos se cargan bajo demanda: no hacen falta para abrir la lista.
    if (_destinos.isEmpty) {
      try {
        _destinos = await CampanaService.destinosServicio();
      } catch (e) {
        if (mounted) _avisar('No se pudo leer el catálogo: $e', error: true);
        return;
      }
    }
    if (!mounted) return;

    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => _CampanaDialog(
        campana: campana,
        destinos: _destinos,
      ),
    );
    if (guardado != true || !mounted) return;
    await _cargar();
    if (!mounted) return;
    _avisar(campana == null ? 'Campaña creada.' : 'Campaña actualizada.');
  }

  Future<void> _alternar(Campana c) async {
    try {
      await CampanaService.alternar(
        uuidUsuario: AuthService.currentSuperAdmin?.uuid ?? '',
        id: c.id,
        activo: !c.activo,
      );
      await _cargar();
      if (mounted) _avisar(c.activo ? 'Campaña desactivada.' : 'Campaña activada.');
    } catch (e) {
      if (mounted) _avisar('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _eliminar(Campana c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar campaña'),
        content: Text('¿Eliminar «${c.titulo}»? No se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await CampanaService.eliminar(
        uuidUsuario: AuthService.currentSuperAdmin?.uuid ?? '',
        id: c.id,
      );
      await _cargar();
      if (mounted) _avisar('Campaña eliminada.');
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
          backgroundColor: error ? AppColors.error : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final puedeEscribir = AuthService.canWrite();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Espacio patrocinado'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _cargar,
            tooltip: 'Recargar',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      floatingActionButton: puedeEscribir
          ? FloatingActionButton.extended(
              onPressed: () => _abrirFormulario(),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nueva campaña'),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const _ExplicacionCard(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _ErrorCard(mensaje: _error!, onReintentar: _cargar),
                  ],
                  if (!puedeEscribir)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: _SinPermisoCard(),
                    ),
                  const SizedBox(height: 16),
                  if (_campanas.isEmpty && _error == null)
                    const _VacioCard()
                  else
                    ..._campanas.map(
                      (c) => _CampanaCard(
                        campana: c,
                        puedeEscribir: puedeEscribir,
                        onEditar: () => _abrirFormulario(campana: c),
                        onAlternar: () => _alternar(c),
                        onEliminar: () => _eliminar(c),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _ExplicacionCard extends StatelessWidget {
  const _ExplicacionCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.primary.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.20)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.campaign_outlined, color: AppColors.primary),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Las campañas activas se muestran en el carrusel de espacio '
                'patrocinado del Home del cliente. Destacan un servicio o una '
                'entidad, y NO modifican el precio de la reserva: para '
                'descuentos usa las promociones del panel de la entidad.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
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
    return Card(
      elevation: 0,
      color: AppColors.error.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline, color: AppColors.error),
                SizedBox(width: 8),
                Text(
                  'No se pudieron cargar las campañas',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(mensaje, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onReintentar,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SinPermisoCard extends StatelessWidget {
  const _SinPermisoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_outline, color: AppColors.warning),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tu nivel de acceso es de solo lectura: puedes ver las campañas '
              'pero no modificarlas.',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _VacioCard extends StatelessWidget {
  const _VacioCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: const [
            Icon(Icons.campaign_outlined, size: 44, color: AppColors.textHint),
            SizedBox(height: 12),
            Text(
              'Todavía no hay campañas',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            SizedBox(height: 6),
            Text(
              'Crea la primera para destacar un servicio en el Home del cliente.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampanaCard extends StatelessWidget {
  final Campana campana;
  final bool puedeEscribir;
  final VoidCallback onEditar;
  final VoidCallback onAlternar;
  final VoidCallback onEliminar;

  const _CampanaCard({
    required this.campana,
    required this.puedeEscribir,
    required this.onEditar,
    required this.onAlternar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final vigente = campana.vigente;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: vigente ? AppColors.success : AppColors.divider,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vista previa del color con el que se pintará en el Home.
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  colors: [
                    _parseColor(campana.colorInicio) ?? AppColors.primary,
                    _parseColor(campana.colorFin) ?? AppColors.primaryLight,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: campana.tieneImagen
                  ? const Icon(Icons.image, color: Colors.white70, size: 20)
                  : Icon(
                      _iconoDe(campana.icono),
                      color: Colors.white,
                      size: 24,
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          campana.titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (!campana.activo) ...[
                        const SizedBox(width: 8),
                        _Chip(
                          texto: 'INACTIVA',
                          color: AppColors.textSecondary,
                        ),
                      ] else if (!vigente) ...[
                        const SizedBox(width: 8),
                        _Chip(texto: 'FUERA DE FECHA', color: AppColors.warning),
                      ] else ...[
                        const SizedBox(width: 8),
                        _Chip(texto: 'EN EL HOME', color: AppColors.success),
                      ],
                    ],
                  ),
                  if (campana.subtitulo != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      campana.subtitulo!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        campana.esDeEntidad
                            ? Icons.business_outlined
                            : Icons.storefront_outlined,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          campana.destino,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _resumen(campana),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            if (puedeEscribir) ...[
              Switch(
                value: campana.activo,
                activeTrackColor: AppColors.primary,
                onChanged: (_) => onAlternar(),
              ),
              PopupMenuButton<String>(
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
          ],
        ),
      ),
    );
  }

  static String _resumen(Campana c) {
    String f(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    final partes = <String>['Prioridad ${c.prioridad}'];
    if (c.desde != null && c.hasta != null) {
      partes.add('${f(c.desde!)} → ${f(c.hasta!)}');
    } else if (c.hasta != null) {
      partes.add('Hasta ${f(c.hasta!)}');
    } else if (c.desde != null) {
      partes.add('Desde ${f(c.desde!)}');
    } else {
      partes.add('Sin fecha límite');
    }
    return partes.join(' · ');
  }

  static Color? _parseColor(String? hex) {
    if (hex == null || hex.trim().isEmpty) return null;
    var v = hex.trim().replaceFirst('#', '');
    if (v.length == 6) v = 'FF$v';
    final n = int.tryParse(v, radix: 16);
    return n == null ? null : Color(n);
  }

  static IconData _iconoDe(String? nombre) => switch (nombre) {
    'spa' => Icons.spa_outlined,
    'storefront' => Icons.storefront_outlined,
    'star' => Icons.star_rounded,
    'local_offer' => Icons.local_offer_outlined,
    'directions_bus' => Icons.directions_bus_filled_outlined,
    'restaurant' => Icons.restaurant_outlined,
    'pets' => Icons.pets_outlined,
    'health' => Icons.medical_services_outlined,
    _ => Icons.campaign_outlined,
  };
}

class _Chip extends StatelessWidget {
  final String texto;
  final Color color;
  const _Chip({required this.texto, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

/// Alta/edición de una campaña.
class _CampanaDialog extends StatefulWidget {
  final Campana? campana;
  final List<({int id, String etiqueta})> destinos;

  const _CampanaDialog({required this.destinos, this.campana});

  @override
  State<_CampanaDialog> createState() => _CampanaDialogState();
}

class _CampanaDialogState extends State<_CampanaDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titulo;
  late final TextEditingController _subtitulo;
  late final TextEditingController _descripcion;
  late final TextEditingController _prioridad;
  late final TextEditingController _imageUrl;

  int? _idLocalServicio;
  String _icono = 'campaign';
  Color _colorInicio = AppColors.primary;
  Color _colorFin = AppColors.primaryLight;
  DateTime? _desde;
  DateTime? _hasta;
  bool _activo = true;
  bool _guardando = false;

  bool get _esEdicion => widget.campana != null;

  static const _iconosDisponibles = <String, IconData>{
    'campaign': Icons.campaign_outlined,
    'spa': Icons.spa_outlined,
    'storefront': Icons.storefront_outlined,
    'star': Icons.star_rounded,
    'local_offer': Icons.local_offer_outlined,
    'directions_bus': Icons.directions_bus_filled_outlined,
    'restaurant': Icons.restaurant_outlined,
    'pets': Icons.pets_outlined,
    'health': Icons.medical_services_outlined,
  };

  static const _paleta = <Color>[
    Color(0xFF2E7D32),
    Color(0xFF1976D2),
    Color(0xFF6D547D),
    Color(0xFF275B68),
    Color(0xFF8C5B72),
    Color(0xFF324B78),
    Color(0xFF8A7355),
    Color(0xFF2D7573),
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.campana;
    _titulo = TextEditingController(text: c?.titulo ?? '');
    _subtitulo = TextEditingController(text: c?.subtitulo ?? '');
    _descripcion = TextEditingController(text: c?.descripcion ?? '');
    _prioridad = TextEditingController(text: (c?.prioridad ?? 0).toString());
    _imageUrl = TextEditingController(text: c?.imageUrl ?? '');
    _idLocalServicio = c?.idLocalServicio;
    _icono = c?.icono ?? 'campaign';
    _colorInicio = _parse(c?.colorInicio) ?? AppColors.primary;
    _colorFin = _parse(c?.colorFin) ?? AppColors.primaryLight;
    _desde = c?.desde;
    _hasta = c?.hasta;
    _activo = c?.activo ?? true;
  }

  @override
  void dispose() {
    _titulo.dispose();
    _subtitulo.dispose();
    _descripcion.dispose();
    _prioridad.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  static Color? _parse(String? hex) {
    if (hex == null || hex.trim().isEmpty) return null;
    var v = hex.trim().replaceFirst('#', '');
    if (v.length == 6) v = 'FF$v';
    final n = int.tryParse(v, radix: 16);
    return n == null ? null : Color(n);
  }

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Future<void> _elegirFecha({required bool esDesde}) async {
    final inicial = (esDesde ? _desde : _hasta) ?? DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      helpText: esDesde ? 'Inicio de la campaña' : 'Fin de la campaña',
    );
    if (fecha == null || !mounted) return;
    setState(() {
      if (esDesde) {
        _desde = fecha;
      } else {
        // Fin al final del día: el servidor compara con `< hasta`, así que
        // guardar las 00:00 cortaría la campaña un día antes.
        _hasta = DateTime(fecha.year, fecha.month, fecha.day, 23, 59, 59);
      }
    });
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final uuid = AuthService.currentSuperAdmin?.uuid;
    if (uuid == null) return;

    setState(() => _guardando = true);
    try {
      await CampanaService.guardar(
        uuidUsuario: uuid,
        id: widget.campana?.id,
        titulo: _titulo.text.trim(),
        // El alcance es servicio o entidad, nunca ambos (lo exige el CHECK y el
        // RPC). Aquí el destino elegido es siempre un servicio; una campaña de
        // entidad se reserva para el panel de entidades si hace falta.
        idLocalServicio: _idLocalServicio,
        subtitulo: _subtitulo.text.trim(),
        descripcion: _descripcion.text.trim(),
        colorInicio: _hex(_colorInicio),
        colorFin: _hex(_colorFin),
        icono: _icono,
        imageUrl: _imageUrl.text.trim(),
        desde: _desde,
        hasta: _hasta,
        prioridad: int.tryParse(_prioridad.text.trim()) ?? 0,
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
            backgroundColor: AppColors.error,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 700),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _esEdicion ? 'Editar campaña' : 'Nueva campaña',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _titulo,
                        decoration: const InputDecoration(
                          labelText: 'Título',
                          hintText: 'Ej: Luna Studio',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'El título es obligatorio'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _subtitulo,
                        decoration: const InputDecoration(
                          labelText: 'Subtítulo',
                          hintText: 'Ej: Tu momento empieza aquí',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        initialValue: _idLocalServicio,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Servicio a destacar',
                          border: OutlineInputBorder(),
                        ),
                        items: widget.destinos
                            .map(
                              (d) => DropdownMenuItem(
                                value: d.id,
                                child: Text(
                                  d.etiqueta,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _idLocalServicio = v),
                        validator: (v) =>
                            v == null ? 'Elige un servicio' : null,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Una campaña de entidad (varios locales) se gestiona '
                        'desde el panel de la entidad.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Aspecto en el Home',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: LinearGradient(
                                colors: [_colorInicio, _colorFin],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Icon(
                              _iconosDisponibles[_icono] ??
                                  Icons.campaign_outlined,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Colores del degradado',
                                  style: TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    for (final c in _paleta)
                                      GestureDetector(
                                        onTap: () => setState(() {
                                          _colorInicio = c;
                                          _colorFin = _aclarar(c);
                                        }),
                                        child: Container(
                                          width: 26,
                                          height: 26,
                                          decoration: BoxDecoration(
                                            color: c,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: _colorInicio == c
                                                  ? Colors.black
                                                  : Colors.transparent,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final e in _iconosDisponibles.entries)
                            ChoiceChip(
                              selected: _icono == e.key,
                              onSelected: (_) =>
                                  setState(() => _icono = e.key),
                              avatar: Icon(e.value, size: 18),
                              label: const SizedBox.shrink(),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _imageUrl,
                        decoration: const InputDecoration(
                          labelText: 'URL de imagen (opcional)',
                          helperText:
                              'Si la dejas vacía se usa el degradado elegido.',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
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
                          const SizedBox(width: 12),
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
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _prioridad,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Prioridad',
                          helperText:
                              'Mayor número = aparece antes en la rotación.',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return null;
                          return int.tryParse(t) == null
                              ? 'Debe ser un número'
                              : null;
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _activo,
                        activeTrackColor: AppColors.primary,
                        onChanged: (v) => setState(() => _activo = v),
                        title: const Text('Activa'),
                        subtitle: const Text(
                          'Solo si está activa y dentro de fechas se ve en el Home.',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _guardando ? null : _guardar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: _guardando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_esEdicion ? 'Guardar' : 'Crear campaña'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _aclarar(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + 0.22).clamp(0.0, 1.0)).toColor();
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
      icon: const Icon(Icons.event_outlined, size: 18),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            etiqueta,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(texto, style: const TextStyle(fontSize: 12.5)),
              if (onLimpiar != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onLimpiar,
                  child: const Icon(Icons.close, size: 14),
                ),
              ],
            ],
          ),
        ],
      ),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}