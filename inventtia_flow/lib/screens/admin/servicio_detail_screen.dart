import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/campo_adicional.dart';
import '../../models/config_precio.dart';
import '../../models/servicio.dart';
import '../../services/catalogo_service.dart';
import '../../widgets/net_image.dart';
import 'config_recursos_screen.dart';
import 'gestion_servicios_screen.dart';

class ServicioDetailScreen extends StatefulWidget {
  final Servicio servicio;
  final int idEntidad;

  const ServicioDetailScreen({
    super.key,
    required this.servicio,
    required this.idEntidad,
  });

  @override
  State<ServicioDetailScreen> createState() => _ServicioDetailScreenState();
}

class _ServicioDetailScreenState extends State<ServicioDetailScreen> {
  bool _cargando = true;
  List<LocalServicio> _items = [];
  String? _error;
  String? _tipoActividadNombre;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final [locales, tipos] = await Future.wait([
        CatalogoService.getLocalServicios(idServicio: widget.servicio.id),
        CatalogoService.getTiposActividadServicio(),
      ]);
      final nombre = () {
        final id = widget.servicio.idTipoActividad;
        if (id == null) return null;
        for (final t in tipos as List<Map<String, dynamic>>) {
          if ((t['id'] as num?)?.toInt() == id) {
            return t['nombre']?.toString();
          }
        }
        return null;
      }();
      if (mounted) {
        setState(() {
          _items = locales as List<LocalServicio>;
          _tipoActividadNombre = nombre;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(widget.servicio.nombre),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar servicio',
            onPressed: _editarServicio,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppTheme.error),
            tooltip: 'Eliminar servicio',
            onPressed: _eliminarServicio,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Future<void> _editarServicio() async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ServicioFormSheet(
        idEntidad: widget.idEntidad,
        servicio: widget.servicio,
      ),
    );
    if (res == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _eliminarServicio() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar servicio'),
        content: Text(
          '¿Eliminar "${widget.servicio.nombre}"?\n\n'
          'Se desvinculará de todos los locales.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CatalogoService.deleteServicio(widget.servicio.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  Widget _buildBody() {
    if (_cargando && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(child: Text('Error: $_error'));
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'Este servicio aún no está vinculado a ningún local.\n'
          'Vincúlalo en Planificación para ver sus recursos y turnos.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInfoSection(),
          const SizedBox(height: 24),
          ..._items.map((ls) => _buildLocalCard(ls)),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.servicio.foto != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: NetImage(
              url: widget.servicio.foto!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: 180,
              errorWidget: () => _fotoPlaceholder(),
            ),
          ),
        if (widget.servicio.foto != null) const SizedBox(height: 16),
        Text(
          widget.servicio.nombre,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (widget.servicio.descripcion != null)
          Text(
            widget.servicio.descripcion!,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        const SizedBox(height: 16),
        _buildInfoRow(
          'Actividad',
          _tipoActividadNombre ?? widget.servicio.tipoActividad ?? '—',
        ),
        _buildInfoRow(
          'Reserva para terceros',
          widget.servicio.permiteTercero ? 'Sí' : 'No',
        ),
        _buildInfoRow(
          'Moneda por defecto',
          MonedasApp.etiqueta(widget.servicio.configPrecio.monedaDefault),
        ),
        _buildInfoRow(
          'Monedas disponibles',
          widget.servicio.configPrecio.monedas
              .map(MonedasApp.etiqueta)
              .join(', '),
        ),
        if (widget.servicio.configPrecio.preciosBase.isNotEmpty)
          _buildInfoRow(
            'Precios base',
            widget.servicio.configPrecio.preciosBase.entries
                .map((e) =>
                    '${_fmtPrecio(e.value)} ${MonedasApp.simbolo(e.key)}')
                .join(' · '),
          ),
        if (widget.servicio.configPrecio.aplicaPrecioIdaVueltaTodos)
          _buildInfoRow(
            'Ida y vuelta',
            'Precio combinado aplica siempre',
          ),
        if (widget.servicio.configPrecio.reglas.isNotEmpty)
          ..._buildReglasPrecio(widget.servicio.configPrecio),
        if (widget.servicio.camposAdicionales.isNotEmpty)
          _buildCamposAdicionales(widget.servicio.camposAdicionales),
      ],
    );
  }

  String _fmtPrecio(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  List<Widget> _buildReglasPrecio(ConfigPrecio cfg) {
    return [
      const SizedBox(height: 8),
      const Text(
        'Reglas de precio',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
        ),
      ),
      const SizedBox(height: 4),
      ...cfg.reglas.expand((r) {
        return r.preciosOpcion.entries.map((op) {
          final precios = op.value.entries
              .map((e) =>
                  '${_fmtPrecio(e.value)} ${MonedasApp.simbolo(e.key)}')
              .join(' · ');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    r.siClave,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    '${op.key}: $precios',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          );
        });
      }),
    ];
  }

  Widget _buildCamposAdicionales(List<CampoAdicional> campos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text(
          'Datos adicionales',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        ...campos.map((c) => _campoCard(campo: c)),
      ],
    );
  }

  Widget _campoCard({required CampoAdicional campo}) {
    final icon = switch (campo.tipo) {
      TipoCampo.texto => Icons.text_fields_outlined,
      TipoCampo.numero => Icons.numbers_outlined,
      TipoCampo.select => Icons.list_alt_outlined,
      TipoCampo.booleano => Icons.toggle_on_outlined,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    campo.etiqueta,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _campoBadge(campo.tipo.etiqueta),
                      if (campo.requerido) _campoBadge('Requerido'),
                      if (campo.contabilizar) _campoBadge('Contabiliza'),
                      if (campo.min != null) _campoBadge('Mín: ${campo.min}'),
                      if (campo.max != null) _campoBadge('Máx: ${campo.max}'),
                    ],
                  ),
                  if (campo.opciones.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Opciones',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: campo.opciones
                          .map((o) => Chip(
                                label: Text(o),
                                visualDensity: VisualDensity.compact,
                                backgroundColor:
                                    AppTheme.primary.withValues(alpha: 0.08),
                              ))
                          .toList(),
                    ),
                  ],
                  if (campo.valorDefault != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Valor por defecto: ${campo.valorDefault}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campoBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fotoPlaceholder() {
    return Container(
      height: 180,
      color: AppTheme.surface,
      child: const Icon(
        Icons.miscellaneous_services_outlined,
        size: 64,
        color: AppTheme.primary,
      ),
    );
  }

  Widget _buildLocalCard(LocalServicio ls) {
    final local = ls.local;
    final localNombre = local?.nombre ?? 'Local #${ls.idLocal}';
    final title = localNombre == widget.servicio.nombre
        ? 'Recursos y turnos'
        : 'Recursos y turnos · $localNombre';
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            if (local?.ubicacion.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                local!.ubicacion,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ConfigRecursosPanel(
              localServicio: ls,
              showHeader: false,
              onUpdated: () => _cargar(),
            ),
          ],
        ),
      ),
    );
  }
}
