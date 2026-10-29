import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/campo_adicional.dart';
import '../../models/config_precio.dart';
import '../../models/servicio.dart';
import '../../services/catalogo_service.dart';
import '../../widgets/net_image.dart';
import 'gestion_servicios_screen.dart';
import 'local_servicio_admin_screen.dart';
import 'planificacion_sheets.dart';

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

  /// Copia viva del servicio.
  ///
  /// Antes el build leía `widget.servicio` en todas partes, así que al guardar
  /// desde el formulario la pantalla seguía mostrando los datos viejos: había
  /// que salir a la lista y volver a entrar (punto 5). Ahora el formulario
  /// devuelve la fila actualizada y se sustituye aquí.
  late Servicio _servicio;

  @override
  void initState() {
    super.initState();
    _servicio = widget.servicio;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final [locales, tipos] = await Future.wait([
        // Se listan también los pares desactivados: el detalle del admin debe
        // decir en qué locales está el servicio aunque esté oculto al cliente
        // (punto 4), y cada fila avisa de su estado.
        CatalogoService.getLocalServicios(
          idServicio: _servicio.id,
          incluirInactivos: true,
        ),
        CatalogoService.getTiposActividadServicio(),
      ]);
      final nombre = () {
        final id = _servicio.idTipoActividad;
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
        title: Text(_servicio.nombre),
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
    // El formulario devuelve el `Servicio` recargado de la BD, no un bool: así
    // el detalle se repinta al instante y sin volver a pedir nada (punto 5).
    final actualizado = await showModalBottomSheet<Servicio>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          ServicioFormSheet(idEntidad: widget.idEntidad, servicio: _servicio),
    );
    if (actualizado != null && mounted) {
      setState(() => _servicio = actualizado);
      // El nombre de la actividad se resuelve contra el catálogo, así que se
      // recalcula por si el admin la cambió.
      await _cargar();
    }
  }

  Future<void> _eliminarServicio() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar servicio'),
        content: Text(
          '¿Eliminar "${_servicio.nombre}"?\n\n'
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
      await CatalogoService.deleteServicio(_servicio.id);
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
    return RefreshIndicator(
      onRefresh: _cargar,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _buildInfoSection(),
              const SizedBox(height: 24),
              const Text(
                'SE OFRECE EN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              if (_items.isEmpty)
                const Text(
                  'Todavía no se ofrece en ningún local. Añádelo desde '
                  '«Locales y servicios», dentro del local donde lo atiendes.',
                  style: TextStyle(color: AppTheme.textSecondary),
                )
              else
                Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < _items.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 16, endIndent: 16),
                        _buildLocalTile(_items[i]),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Punto 4: dejar claro que un servicio inactivo no se ve en ningún lado.
        if (!_servicio.activo) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.warning.withValues(alpha: 0.35),
              ),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.visibility_off_outlined,
                  size: 18,
                  color: AppTheme.warning,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Servicio inactivo: no se muestra en ningún local ni se '
                    'puede reservar. Actívalo desde Editar.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_servicio.foto != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: NetImage(
              url: _servicio.foto!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: 180,
              errorWidget: () => _fotoPlaceholder(),
            ),
          ),
        if (_servicio.foto != null) const SizedBox(height: 16),
        Text(
          _servicio.nombre,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_servicio.descripcion != null)
          Text(
            _servicio.descripcion!,
            style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
        const SizedBox(height: 16),
        _buildInfoRow(
          'Actividad',
          _tipoActividadNombre ?? _servicio.tipoActividad ?? '—',
        ),
        _buildInfoRow('Estado', _servicio.activo ? 'Activo' : 'Inactivo'),
        _buildInfoRow(
          'Reserva para terceros',
          _servicio.permiteTercero ? 'Sí' : 'No',
        ),
        // [67] El cobro por adelantado es por servicio (la cuenta que cobra es de
        // la entidad). Se muestra aquí para no tener que abrir el formulario.
        _buildInfoRow(
          'Pago por adelantado',
          _servicio.cobroAdelantado ? 'Sí' : 'No',
        ),
        _buildInfoRow(
          'Moneda por defecto',
          MonedasApp.etiqueta(_servicio.configPrecio.monedaDefault),
        ),
        _buildInfoRow(
          'Monedas disponibles',
          _servicio.configPrecio.monedas.map(MonedasApp.etiqueta).join(', '),
        ),
        if (_servicio.configPrecio.preciosBase.isNotEmpty)
          _buildInfoRow(
            'Precios base',
            _servicio.configPrecio.preciosBase.entries
                .map(
                  (e) => '${_fmtPrecio(e.value)} ${MonedasApp.simbolo(e.key)}',
                )
                .join(' · '),
          ),
        if (_servicio.configPrecio.aplicaPrecioIdaVueltaTodos)
          _buildInfoRow('Ida y vuelta', 'Precio combinado aplica siempre'),
        if (_servicio.configPrecio.reglas.isNotEmpty)
          ..._buildReglasPrecio(_servicio.configPrecio),
        if (_servicio.camposAdicionales.isNotEmpty)
          _buildCamposAdicionales(_servicio.camposAdicionales),
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
      // D6: el orden de las reglas decide el precio (gana la primera que
      // coincide con un dato del cliente). Se dice aquí en vez de dejarlo
      // silencioso: cambiar el orden cambia importes ya guardados.
      const Text(
        'Si dos reglas coinciden, se aplica la primera.',
        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
      ),
      const SizedBox(height: 4),
      ...cfg.reglas.expand((r) {
        return r.preciosOpcion.entries.map((op) {
          final precios = op.value.entries
              .map((e) => '${_fmtPrecio(e.value)} ${MonedasApp.simbolo(e.key)}')
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
                          .map(
                            (o) => Chip(
                              label: Text(o),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: AppTheme.primary.withValues(
                                alpha: 0.08,
                              ),
                            ),
                          )
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
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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

  /// Un local donde se ofrece el servicio. Los recursos, turnos, calendario y
  /// promociones de ese local se gestionan en `LocalServicioAdminScreen`; aquí
  /// solo se lista y se lleva hasta allí.
  Widget _buildLocalTile(LocalServicio ls) {
    final local = ls.local;
    return ListTile(
      leading: const Icon(Icons.store_outlined, color: AppTheme.primary),
      title: Text(local?.nombre ?? 'Local #${ls.idLocal}'),
      subtitle: local?.ubicacion.isNotEmpty == true
          ? Text(local!.ubicacion)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChipEstado(
            texto: ls.activoEfectivo ? 'Publicado' : 'Oculto',
            color: ls.activoEfectivo ? AppTheme.success : AppTheme.warning,
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LocalServicioAdminScreen(
              localServicio: ls.copyWith(servicio: _servicio),
              entidadId: widget.idEntidad,
            ),
          ),
        );
        await _cargar();
      },
    );
  }
}
