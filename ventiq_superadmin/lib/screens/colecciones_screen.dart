import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/coleccion.dart';
import '../services/auth_service.dart';
import '../services/catalogo_destinos_service.dart';
import '../services/coleccion_service.dart';
import '../widgets/app_drawer.dart';

/// Paletas sugeridas para la tarjeta del Home. Se ofrecen como atajos porque
/// escribir dos hexadecimales a mano es donde más se falla.
const List<({String nombre, String inicio, String fin})> _paletas = [
  (nombre: 'Novia', inicio: '#8C5B72', fin: '#C98CA4'),
  (nombre: 'Bienestar', inicio: '#1C7C7A', fin: '#64B6AC'),
  (nombre: 'Transporte', inicio: '#395B91', fin: '#6D9DD1'),
  (nombre: 'Ofertas', inicio: '#2C3654', fin: '#1FA8B8'),
  (nombre: 'Fiesta', inicio: '#7B2C6B', fin: '#D46A9F'),
  (nombre: 'Familia', inicio: '#1B5E20', fin: '#66BB6A'),
];

/// Colecciones temáticas del Home del cliente.
///
/// **No es lo mismo que una promoción.** Una promoción descuenta el precio y la
/// crea el admin de la entidad para sus servicios; una colección solo **agrupa**
/// servicios curados y cruza entidades, así que la cura el superadmin. Una
/// colección jamás cambia el importe que paga el cliente.
class ColeccionesScreen extends StatefulWidget {
  const ColeccionesScreen({super.key});

  @override
  State<ColeccionesScreen> createState() => _ColeccionesScreenState();
}

class _ColeccionesScreenState extends State<ColeccionesScreen> {
  List<Coleccion> _colecciones = const [];
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
      final colecciones = await ColeccionService.listar(
        uuidUsuario: AuthService.currentSuperAdmin?.uuid ?? '',
      );
      if (!mounted) return;
      setState(() {
        _colecciones = colecciones;
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
      return 'Falta aplicar la migración 30_colecciones.sql en Supabase.';
    }
    return t.replaceFirst('Exception: ', '');
  }

  Future<void> _abrirFormulario({Coleccion? coleccion}) async {
    // El catálogo se carga bajo demanda: no hace falta para abrir la lista.
    if (_destinos.isEmpty) {
      try {
        _destinos = await CatalogoDestinosService.servicios();
      } catch (e) {
        if (mounted) _avisar('No se pudo leer el catálogo: $e', error: true);
        return;
      }
    }
    if (!mounted) return;

    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => _ColeccionDialog(
        coleccion: coleccion,
        destinos: _destinos,
      ),
    );
    if (guardado != true || !mounted) return;
    await _cargar();
    if (!mounted) return;
    _avisar(coleccion == null ? 'Colección creada.' : 'Colección actualizada.');
  }

  Future<void> _alternar(Coleccion c) async {
    try {
      await ColeccionService.alternar(
        uuidUsuario: AuthService.currentSuperAdmin?.uuid ?? '',
        id: c.id,
        activo: !c.activo,
      );
      await _cargar();
      if (mounted) {
        _avisar(c.activo ? 'Colección desactivada.' : 'Colección activada.');
      }
    } catch (e) {
      if (mounted) _avisar('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _eliminar(Coleccion c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar colección'),
        content: Text(
          '¿Eliminar «${c.titulo}»? Se quita del Home y se pierden sus '
          '${c.totalServicios} servicios asignados. No se puede deshacer.',
        ),
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
      await ColeccionService.eliminar(
        uuidUsuario: AuthService.currentSuperAdmin?.uuid ?? '',
        id: c.id,
      );
      await _cargar();
      if (mounted) _avisar('Colección eliminada.');
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
        title: const Text('Colecciones temáticas'),
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
              label: const Text('Nueva colección'),
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
                  if (_colecciones.isEmpty && _error == null)
                    const _VacioCard()
                  else
                    ..._colecciones.map(
                      (c) => _ColeccionCard(
                        coleccion: c,
                        puedeEscribir: puedeEscribir,
                        onEditar: () => _abrirFormulario(coleccion: c),
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
            Icon(Icons.collections_bookmark_outlined, color: AppColors.primary),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Una colección agrupa servicios curados de cualquier entidad '
                '("Pack Novia", "Self-care Sunday"). Las activas se muestran en '
                'el Home del cliente y al tocarlas filtran el catálogo. NO '
                'modifican el precio de la reserva: para descuentos usa las '
                'promociones del panel de la entidad.',
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
  const _ErrorCard({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.error.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error),
            const SizedBox(width: 12),
            Expanded(child: Text(mensaje)),
            TextButton(onPressed: onReintentar, child: const Text('Reintentar')),
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
    return Card(
      elevation: 0,
      color: AppColors.warning.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.warning.withValues(alpha: 0.30)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: AppColors.warning),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tu rol puede ver las colecciones pero no editarlas. Solo un '
                'superadmin con acceso total puede crearlas o cambiarlas.',
              ),
            ),
          ],
        ),
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
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.collections_bookmark_outlined,
              size: 42,
              color: AppColors.textHint,
            ),
            SizedBox(height: 12),
            Text(
              'Todavía no hay colecciones',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            SizedBox(height: 6),
            Text(
              'Hasta que no crees una con al menos un servicio, la sección '
              '"Colecciones destacadas" no aparece en el Home del cliente.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColeccionCard extends StatelessWidget {
  const _ColeccionCard({
    required this.coleccion,
    required this.puedeEscribir,
    required this.onEditar,
    required this.onAlternar,
    required this.onEliminar,
  });

  final Coleccion coleccion;
  final bool puedeEscribir;
  final VoidCallback onEditar;
  final VoidCallback onAlternar;
  final VoidCallback onEliminar;

  /// Acepta `#RRGGBB` o `RRGGBB`; `null` si no es válido.
  static Color? _parseColor(String? valor) {
    final v = valor?.trim().replaceFirst('#', '');
    if (v == null || v.length != 6) return null;
    final n = int.tryParse(v, radix: 16);
    return n == null ? null : Color(0xFF000000 | n);
  }

  @override
  Widget build(BuildContext context) {
    final inicio = _parseColor(coleccion.colorInicio) ?? AppColors.primary;
    final fin = _parseColor(coleccion.colorFin) ?? AppColors.primaryLight;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [inicio, fin],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                (coleccion.icono?.trim().isNotEmpty ?? false)
                    ? coleccion.icono!.trim()
                    : '✨',
                style: const TextStyle(fontSize: 22),
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
                          coleccion.titulo,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (!coleccion.activo) ...[
                        const SizedBox(width: 8),
                        const _Etiqueta(texto: 'APAGADA', color: AppColors.error),
                      ] else if (!coleccion.vigente) ...[
                        const SizedBox(width: 8),
                        const _Etiqueta(
                          texto: 'FUERA DE FECHA',
                          color: AppColors.warning,
                        ),
                      ],
                    ],
                  ),
                  if (coleccion.subtitulo != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      coleccion.subtitulo!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Etiqueta(
                        texto: coleccion.etiquetaServicios.toUpperCase(),
                        color: AppColors.primary,
                      ),
                      Text(
                        'orden ${coleccion.orden}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (coleccion.hasta != null)
                        Text(
                          'hasta ${_fecha(coleccion.hasta!)}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (puedeEscribir)
              Column(
                children: [
                  Switch(value: coleccion.activo, onChanged: (_) => onAlternar()),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: onEditar,
                        tooltip: 'Editar',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                      ),
                      IconButton(
                        onPressed: onEliminar,
                        tooltip: 'Eliminar',
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static String _fecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, required this.color});

  final String texto;
  final Color color;

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
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Alta y edición de una colección.
///
/// `servicios` se manda completo en cada guardado: el servidor **reemplaza** el
/// conjunto, no hace merge. Así quitar un servicio del formulario lo quita de la
/// colección de verdad.
class _ColeccionDialog extends StatefulWidget {
  const _ColeccionDialog({required this.destinos, this.coleccion});

  final List<({int id, String etiqueta})> destinos;
  final Coleccion? coleccion;

  @override
  State<_ColeccionDialog> createState() => _ColeccionDialogState();
}

class _ColeccionDialogState extends State<_ColeccionDialog> {
  late final TextEditingController _titulo;
  late final TextEditingController _subtitulo;
  late final TextEditingController _icono;
  late final TextEditingController _colorInicio;
  late final TextEditingController _colorFin;
  late final TextEditingController _orden;
  final TextEditingController _busqueda = TextEditingController();

  /// `Set` de Dart preserva el orden de inserción, así que el array que se manda
  /// al servidor refleja el orden en que se marcaron los servicios.
  final Set<int> _seleccionados = <int>{};

  late bool _activo;
  DateTime? _desde;
  DateTime? _hasta;
  bool _guardando = false;
  String? _errorLocal;

  bool get _esEdicion => widget.coleccion != null;

  @override
  void initState() {
    super.initState();
    final c = widget.coleccion;
    _titulo = TextEditingController(text: c?.titulo ?? '');
    _subtitulo = TextEditingController(text: c?.subtitulo ?? '');
    _icono = TextEditingController(text: c?.icono ?? '');
    _colorInicio = TextEditingController(text: c?.colorInicio ?? '');
    _colorFin = TextEditingController(text: c?.colorFin ?? '');
    _orden = TextEditingController(text: '${c?.orden ?? 0}');
    _activo = c?.activo ?? true;
    _desde = c?.desde;
    _hasta = c?.hasta;
    if (c != null) _seleccionados.addAll(c.servicios);
  }

  @override
  void dispose() {
    _titulo.dispose();
    _subtitulo.dispose();
    _icono.dispose();
    _colorInicio.dispose();
    _colorFin.dispose();
    _orden.dispose();
    _busqueda.dispose();
    super.dispose();
  }

  /// Normaliza `#RRGGBB` / `RRGGBB` a `#RRGGBB`. `null` si no es válido.
  static String? _limpiarHex(String valor) {
    final v = valor.trim().replaceFirst('#', '');
    if (v.length != 6) return null;
    if (int.tryParse(v, radix: 16) == null) return null;
    return '#${v.toUpperCase()}';
  }

  static String? _vacioANulo(String v) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  static String _sinAcentos(String v) {
    const con = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const sin = 'aaaaaeeeeiiiiooooouuuunc';
    final sb = StringBuffer();
    for (final ch in v.split('')) {
      final i = con.indexOf(ch);
      sb.write(i >= 0 ? sin[i] : ch);
    }
    return sb.toString();
  }

  Future<void> _elegirFecha({required bool esDesde}) async {
    final base = (esDesde ? _desde : _hasta) ?? DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (elegida == null) return;
    setState(() {
      if (esDesde) {
        _desde = elegida;
      } else {
        _hasta = elegida;
      }
    });
  }

  Future<void> _guardar() async {
    final titulo = _titulo.text.trim();
    if (titulo.isEmpty) {
      setState(() => _errorLocal = 'El título es obligatorio');
      return;
    }
    if (_seleccionados.isEmpty) {
      setState(() => _errorLocal =
          'Elige al menos un servicio: una colección vacía no se muestra en el Home');
      return;
    }

    final textoInicio = _colorInicio.text.trim();
    final textoFin = _colorFin.text.trim();
    final ci = _limpiarHex(textoInicio);
    final cf = _limpiarHex(textoFin);
    if (textoInicio.isNotEmpty && ci == null) {
      setState(() => _errorLocal = 'El color inicial debe ser #RRGGBB');
      return;
    }
    if (textoFin.isNotEmpty && cf == null) {
      setState(() => _errorLocal = 'El color final debe ser #RRGGBB');
      return;
    }
    if (_desde != null && _hasta != null && !_desde!.isBefore(_hasta!)) {
      setState(() => _errorLocal = 'La fecha de fin debe ser posterior al inicio');
      return;
    }

    setState(() {
      _guardando = true;
      _errorLocal = null;
    });
    try {
      await ColeccionService.guardar(
        uuidUsuario: AuthService.currentSuperAdmin?.uuid ?? '',
        id: widget.coleccion?.id,
        titulo: titulo,
        subtitulo: _vacioANulo(_subtitulo.text),
        icono: _vacioANulo(_icono.text),
        colorInicio: ci,
        colorFin: cf,
        orden: int.tryParse(_orden.text.trim()) ?? 0,
        activo: _activo,
        desde: _desde,
        hasta: _hasta,
        servicios: _seleccionados.toList(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _errorLocal = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados();

    return AlertDialog(
      title: Text(_esEdicion ? 'Editar colección' : 'Nueva colección'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titulo,
                decoration: const InputDecoration(
                  labelText: 'Título *',
                  hintText: 'Pack Novia',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subtitulo,
                decoration: const InputDecoration(
                  labelText: 'Subtítulo',
                  hintText: 'Todo para el gran día',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _icono,
                      maxLength: 4,
                      decoration: const InputDecoration(
                        labelText: 'Icono',
                        hintText: '💍',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _colorInicio,
                      decoration: const InputDecoration(
                        labelText: 'Color inicial',
                        hintText: '#8C5B72',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _colorFin,
                      decoration: const InputDecoration(
                        labelText: 'Color final',
                        hintText: '#C98CA4',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _paletas.map((p) {
                  return InkWell(
                    onTap: () => setState(() {
                      _colorInicio.text = p.inicio;
                      _colorFin.text = p.fin;
                    }),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _parseColor(p.inicio) ?? AppColors.primary,
                            _parseColor(p.fin) ?? AppColors.primaryLight,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        p.nombre,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _orden,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Orden',
                        helperText: 'menor = antes',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SwitchListTile(
                      value: _activo,
                      onChanged: (v) => setState(() => _activo = v),
                      title: const Text('Activa', style: TextStyle(fontSize: 14)),
                      subtitle: Text(
                        _activo
                            ? 'Se muestra en el Home'
                            : 'No se muestra en el Home',
                        style: const TextStyle(fontSize: 12),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _CampoFecha(
                      etiqueta: 'Vigente desde',
                      valor: _desde,
                      onElegir: () => _elegirFecha(esDesde: true),
                      onLimpiar: () => setState(() => _desde = null),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CampoFecha(
                      etiqueta: 'Vigente hasta',
                      valor: _hasta,
                      onElegir: () => _elegirFecha(esDesde: false),
                      onLimpiar: () => setState(() => _hasta = null),
                    ),
                  ),
                ],
              ),
              const Divider(height: 28),
              Row(
                children: [
                  Text(
                    'Servicios (${_seleccionados.length}) *',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  if (_seleccionados.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(_seleccionados.clear),
                      child: const Text('Quitar todos'),
                    ),
                ],
              ),
              TextField(
                controller: _busqueda,
                decoration: const InputDecoration(
                  hintText: 'Buscar servicio o local',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: filtrados.isEmpty
                    ? const Center(
                        child: Text(
                          'Sin resultados',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtrados.length,
                        itemBuilder: (_, i) {
                          final d = filtrados[i];
                          final marcado = _seleccionados.contains(d.id);
                          return CheckboxListTile(
                            value: marcado,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              d.etiqueta,
                              style: const TextStyle(fontSize: 13),
                            ),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _seleccionados.add(d.id);
                              } else {
                                _seleccionados.remove(d.id);
                              }
                            }),
                          );
                        },
                      ),
              ),
              if (_errorLocal != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorLocal!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _guardando ? null : _guardar,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_esEdicion ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }

  List<({int id, String etiqueta})> _filtrados() {
    final q = _sinAcentos(_busqueda.text.trim().toLowerCase());
    if (q.isEmpty) return widget.destinos;
    return widget.destinos
        .where((d) => _sinAcentos(d.etiqueta.toLowerCase()).contains(q))
        .toList();
  }

  static Color? _parseColor(String? valor) {
    final v = valor?.trim().replaceFirst('#', '');
    if (v == null || v.length != 6) return null;
    final n = int.tryParse(v, radix: 16);
    return n == null ? null : Color(0xFF000000 | n);
  }
}

class _CampoFecha extends StatelessWidget {
  const _CampoFecha({
    required this.etiqueta,
    required this.valor,
    required this.onElegir,
    required this.onLimpiar,
  });

  final String etiqueta;
  final DateTime? valor;
  final VoidCallback onElegir;
  final VoidCallback onLimpiar;

  @override
  Widget build(BuildContext context) {
    final v = valor;
    return InkWell(
      onTap: onElegir,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: etiqueta,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: v == null
              ? const Icon(Icons.calendar_today_outlined, size: 18)
              : IconButton(
                  tooltip: 'Quitar',
                  onPressed: onLimpiar,
                  icon: const Icon(Icons.close, size: 18),
                ),
        ),
        child: Text(
          v == null
              ? 'Sin límite'
              : '${v.day.toString().padLeft(2, '0')}/'
                    '${v.month.toString().padLeft(2, '0')}/${v.year}',
          style: TextStyle(
            color: v == null ? AppColors.textHint : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
