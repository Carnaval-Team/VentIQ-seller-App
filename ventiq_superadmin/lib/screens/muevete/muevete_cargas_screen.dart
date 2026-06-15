import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/muevete_service.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_drawer.dart';

class MueveteCargasScreen extends StatefulWidget {
  const MueveteCargasScreen({super.key});
  @override
  State<MueveteCargasScreen> createState() => _MueveteCargasScreenState();
}

class _MueveteCargasScreenState extends State<MueveteCargasScreen> {
  List<Map<String, dynamic>> _cargas = [];
  List<Map<String, dynamic>> _estados = [];
  bool _isLoading = true;
  String? _filtroEstado;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        MueveteService.getCargas(estado: _filtroEstado),
        MueveteService.getEstadosNomenclador(),
      ]);
      if (mounted) {
        setState(() {
          _cargas = results[0] as List<Map<String, dynamic>>;
          _estados = results[1] as List<Map<String, dynamic>>;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[MueveteCargasScreen] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _fmtDate(String? s) {
    if (s == null) return '—';
    final d = DateTime.tryParse(s)?.toLocal();
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _estadoLabel(String estado) {
    const labels = {
      'publicada': 'Publicada',
      'en_matching': 'En Matching',
      'ofertada': 'Ofertada',
      'aceptada': 'Aceptada',
      'tomada': 'Tomada',
      'en_transito': 'En Tránsito',
      'entregada': 'Entregada',
      'completada': 'Completada',
      'completada_carrier': 'Completada (Carrier)',
      'cancelada': 'Cancelada',
      'disputa': 'En Disputa',
    };
    return labels[estado] ?? estado;
  }

  Color _estadoColor(String estado) {
    const colors = {
      'publicada': Color(0xFF6366F1),
      'en_matching': Color(0xFF8B5CF6),
      'ofertada': Color(0xFF0EA5E9),
      'aceptada': Color(0xFF10B981),
      'tomada': Color(0xFF059669),
      'en_transito': Color(0xFFF59E0B),
      'entregada': Color(0xFF10B981),
      'completada': Color(0xFF047857),
      'completada_carrier': Color(0xFF065F46),
      'cancelada': Color(0xFFEF4444),
      'disputa': Color(0xFFDC2626),
    };
    return colors[estado] ?? const Color(0xFF94A3B8);
  }

  Future<void> _cancelarCarga(Map<String, dynamic> carga) async {
    final cargaId = carga['id'] as int;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar Carga'),
        content: Text('¿Seguro que deseas cancelar la carga #$cargaId?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final adminUuid = Supabase.instance.client.auth.currentUser?.id;
      await MueveteService.cambiarEstadoCarga(
        cargaId: cargaId,
        estadoCodigo: 'cancelada',
        usuarioUuid: adminUuid,
        motivo: 'Cancelada por el administrador',
      );
      _showSnack('Carga #$cargaId cancelada', true);
      _loadData();
    } catch (e) {
      _showSnack('Error: $e', false);
    }
  }

  Future<void> _cambiarEstado(Map<String, dynamic> carga) async {
    final cargaId = carga['id'] as int;
    final estadoActual = carga['estado'] as String? ?? '';

    final nuevoEstado = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? selected;
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text('Cambiar estado — Carga #$cargaId'),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Estado actual: ${_estadoLabel(estadoActual)}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selected,
                    decoration: const InputDecoration(
                      labelText: 'Nuevo estado',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _estados
                        .where((e) => e['codigo'] != estadoActual)
                        .map((e) => DropdownMenuItem<String>(
                              value: e['codigo'] as String,
                              child: Text(e['nombre'] as String? ?? e['codigo'] as String),
                            ))
                        .toList(),
                    onChanged: (v) => setLocal(() => selected = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: selected != null ? () => Navigator.pop(ctx, selected) : null,
                child: const Text('Aplicar'),
              ),
            ],
          );
        });
      },
    );

    if (nuevoEstado == null) return;

    try {
      final adminUuid = Supabase.instance.client.auth.currentUser?.id;
      await MueveteService.cambiarEstadoCarga(
        cargaId: cargaId,
        estadoCodigo: nuevoEstado,
        usuarioUuid: adminUuid,
        motivo: 'Cambio manual por administrador',
      );
      _showSnack('Estado de carga #$cargaId cambiado a "${_estadoLabel(nuevoEstado)}"', true);
      _loadData();
    } catch (e) {
      _showSnack('Error: $e', false);
    }
  }

  void _showDetalle(Map<String, dynamic> carga) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_shipping_outlined, color: Color(0xFF6366F1)),
                    const SizedBox(width: 12),
                    Text('Carga #${carga['id']}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    _estadoBadge(carga['estado'] as String? ?? ''),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              // Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailSection('Shipper', [
                        _detailRow('Nombre', carga['shipper_name'] as String? ?? '—'),
                        _detailRow('Email', carga['shipper_email'] as String? ?? '—'),
                        _detailRow('UUID', _truncUuid(carga['shipper_id'] as String?)),
                      ]),
                      if (carga['carrier_name'] != null) ...[
                        const SizedBox(height: 16),
                        _detailSection('Carrier', [
                          _detailRow('Nombre', carga['carrier_name'] as String? ?? '—'),
                          _detailRow('Email', carga['carrier_email'] as String? ?? '—'),
                          _detailRow('Driver ID', '${carga['carrier_driver_id'] ?? '—'}'),
                        ]),
                      ],
                      const SizedBox(height: 16),
                      _detailSection('Ruta', [
                        _detailRow('Origen', '${carga['ciudad_origen'] ?? ''} — ${carga['dir_origen'] ?? ''}'),
                        _detailRow('Destino', '${carga['ciudad_destino'] ?? ''} — ${carga['dir_destino'] ?? ''}'),
                        _detailRow('Distancia', carga['distancia_km'] != null ? '${(carga['distancia_km'] as num).toStringAsFixed(0)} km' : '—'),
                      ]),
                      const SizedBox(height: 16),
                      _detailSection('Mercancía', [
                        _detailRow('Tipo', _nestedField(carga, 'app_nom_tipo_mercancia', 'nombre')),
                        _detailRow('Descripción', carga['descripcion'] as String? ?? '—'),
                        _detailRow('Peso', carga['peso_kg'] != null ? '${carga['peso_kg']} kg' : '—'),
                        _detailRow('Volumen', carga['volumen_m3'] != null ? '${carga['volumen_m3']} m³' : '—'),
                        _detailRow('Dimensiones', _dimensiones(carga)),
                        _detailRow('Valor declarado', carga['valor_declarado'] != null ? '\$${carga['valor_declarado']}' : '—'),
                        _detailRow('Refrigeración', carga['requiere_refrigeracion'] == true ? 'Sí' : 'No'),
                        _detailRow('Seguro', carga['requiere_seguro'] == true ? 'Sí' : 'No'),
                      ]),
                      const SizedBox(height: 16),
                      _detailSection('Equipo / Tipo', [
                        _detailRow('Tipo carga', _nestedField(carga, 'app_nom_tipo_carga', 'abreviacion')),
                        _detailRow('Tipo equipo', _nestedField(carga, 'app_nom_tipo_equipo', 'nombre')),
                        _detailRow('LTL', carga['es_ltl'] == true ? 'Sí (${carga['ltl_espacio_ocupado'] ?? '—'}%)' : 'No'),
                      ]),
                      const SizedBox(height: 16),
                      _detailSection('Fechas y Precio', [
                        _detailRow('Recogida', _fmtDate(carga['fecha_recogida'] as String?)),
                        _detailRow('Entrega', _fmtDate(carga['fecha_entrega'] as String?)),
                        _detailRow('Precio', carga['precio_ofertado'] != null ? '\$${carga['precio_ofertado']} ${carga['moneda'] ?? 'USD'}' : '—'),
                        _detailRow('Precio final', carga['precio_final'] != null ? '\$${carga['precio_final']} ${carga['moneda'] ?? 'USD'}' : '—'),
                        _detailRow('Prioridad', (carga['prioridad'] as String? ?? 'normal').toUpperCase()),
                        _detailRow('Destacada', carga['destacada'] == true ? 'Sí' : 'No'),
                      ]),
                      const SizedBox(height: 16),
                      _detailSection('Contacto', [
                        _detailRow('Contacto origen', '${carga['contacto_origen_nombre'] ?? '—'} / ${carga['contacto_origen_tel'] ?? '—'}'),
                        _detailRow('Contacto destino', '${carga['contacto_destino_nombre'] ?? '—'} / ${carga['contacto_destino_tel'] ?? '—'}'),
                      ]),
                      if (carga['instrucciones'] != null && (carga['instrucciones'] as String).isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _detailSection('Instrucciones', [
                          Text(carga['instrucciones'] as String, style: const TextStyle(fontSize: 13)),
                        ]),
                      ],
                      const SizedBox(height: 16),
                      _detailRow('Creada', _fmtDate(carga['created_at'] as String?)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _nestedField(Map<String, dynamic> row, String relation, String field) {
    final nested = row[relation];
    if (nested is Map) return nested[field] as String? ?? '—';
    return '—';
  }

  String _dimensiones(Map<String, dynamic> c) {
    final l = c['longitud_m'];
    final a = c['ancho_m'];
    final h = c['alto_m'];
    if (l == null && a == null && h == null) return '—';
    return '${l ?? '?'} × ${a ?? '?'} × ${h ?? '?'} m';
  }

  Widget _detailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)))),
        ],
      ),
    );
  }

  void _showSnack(String msg, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFEF4444),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(MediaQuery.of(context).size.width);

    final total = _cargas.length;
    final activas = _cargas.where((c) => !['cancelada', 'entregada', 'completada'].contains(c['estado'])).length;
    final canceladas = _cargas.where((c) => c['estado'] == 'cancelada').length;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      body: CustomScrollView(slivers: [
        SliverAppBar(
          floating: true,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0.5,
          title: const Text('Gestión de Cargas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          actions: [
            IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B))),
            const SizedBox(width: 8),
          ],
        ),
        SliverPadding(
          padding: EdgeInsets.all(isDesktop ? 32 : 16),
          sliver: SliverList(delegate: SliverChildListDelegate([
            // Stats
            Row(children: [
              _statCard('Total', '$total', const Color(0xFF6366F1)),
              _statCard('Activas', '$activas', const Color(0xFFF59E0B)),
              _statCard('Canceladas', '$canceladas', const Color(0xFFEF4444)),
            ]),
            const SizedBox(height: 20),
            // Filter
            _buildFilter(isDesktop),
            const SizedBox(height: 16),
            _isLoading
                ? const Center(child: Padding(padding: EdgeInsets.all(60), child: CircularProgressIndicator()))
                : _buildTable(isDesktop),
          ])),
        ),
      ]),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(children: [
        Container(width: 4, height: 32, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
        ]),
      ]),
    ));
  }

  Widget _buildFilter(bool isDesktop) {
    final filters = <String, String>{
      'todos': 'Todos',
      'publicada': 'Publicada',
      'en_matching': 'En Matching',
      'ofertada': 'Ofertada',
      'aceptada': 'Aceptada',
      'tomada': 'Tomada',
      'en_transito': 'En Tránsito',
      'entregada': 'Entregada',
      'completada': 'Completada',
      'cancelada': 'Cancelada',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          const Icon(Icons.filter_list_rounded, size: 18, color: Color(0xFF94A3B8)),
          const SizedBox(width: 10),
          ...filters.entries.map((e) {
            final sel = (_filtroEstado == null && e.key == 'todos') || _filtroEstado == e.key;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(e.value),
                selected: sel,
                onSelected: (_) {
                  setState(() => _filtroEstado = e.key == 'todos' ? null : e.key);
                  _loadData();
                },
                selectedColor: const Color(0xFF6366F1),
                labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sel ? Colors.white : const Color(0xFF64748B)),
                backgroundColor: const Color(0xFFF1F5F9),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            );
          }),
          const SizedBox(width: 12),
          Text('${_cargas.length} cargas', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        ]),
      ),
    );
  }

  Widget _buildTable(bool isDesktop) {
    if (_cargas.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(60),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text('Sin cargas${_filtroEstado != null ? ' con estado "$_filtroEstado"' : ''}',
              style: TextStyle(color: Colors.grey[500])),
        ]),
      );
    }

    if (!isDesktop) return _buildMobileCards();

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 120),
          child: DataTable(
            headingRowColor: WidgetStateColor.resolveWith((_) => const Color(0xFFF8FAFC)),
            headingRowHeight: 48,
            dataRowMinHeight: 52,
            dataRowMaxHeight: 52,
            columnSpacing: 16,
            columns: const [
              DataColumn(label: Text('ID', style: _th)),
              DataColumn(label: Text('Estado', style: _th)),
              DataColumn(label: Text('Shipper', style: _th)),
              DataColumn(label: Text('Origen', style: _th)),
              DataColumn(label: Text('Destino', style: _th)),
              DataColumn(label: Text('Tipo', style: _th)),
              DataColumn(label: Text('Mercancía', style: _th)),
              DataColumn(label: Text('Precio', style: _th)),
              DataColumn(label: Text('Recogida', style: _th)),
              DataColumn(label: Text('Carrier', style: _th)),
              DataColumn(label: Text('Acciones', style: _th)),
            ],
            rows: _cargas.map((c) {
              return DataRow(
                cells: [
                  DataCell(
                    InkWell(
                      onTap: () => _showDetalle(c),
                      child: Text('#${c['id']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6366F1))),
                    ),
                  ),
                  DataCell(_estadoBadge(c['estado'] as String? ?? '')),
                  DataCell(Text(c['shipper_name'] as String? ?? _truncUuid(c['shipper_id'] as String?), style: const TextStyle(fontSize: 12, color: Color(0xFF334155)))),
                  DataCell(Text(c['ciudad_origen'] as String? ?? '—', style: const TextStyle(fontSize: 12, color: Color(0xFF334155)))),
                  DataCell(Text(c['ciudad_destino'] as String? ?? '—', style: const TextStyle(fontSize: 12, color: Color(0xFF334155)))),
                  DataCell(Text(_nestedField(c, 'app_nom_tipo_carga', 'abreviacion'), style: const TextStyle(fontSize: 12, color: Color(0xFF334155)))),
                  DataCell(Text(_nestedField(c, 'app_nom_tipo_mercancia', 'nombre'), style: const TextStyle(fontSize: 12, color: Color(0xFF334155)))),
                  DataCell(Text(
                    c['precio_ofertado'] != null ? '\$${(c['precio_ofertado'] as num).toStringAsFixed(0)}' : '—',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6366F1)),
                  )),
                  DataCell(Text(_fmtDate(c['fecha_recogida'] as String?), style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))),
                  DataCell(Text(c['carrier_name'] as String? ?? '—', style: const TextStyle(fontSize: 12, color: Color(0xFF334155)))),
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        tooltip: 'Ver detalle',
                        onPressed: () => _showDetalle(c),
                        color: const Color(0xFF6366F1),
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                        tooltip: 'Cambiar estado',
                        onPressed: () => _cambiarEstado(c),
                        color: const Color(0xFFF59E0B),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (c['estado'] != 'cancelada')
                        IconButton(
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          tooltip: 'Cancelar carga',
                          onPressed: () => _cancelarCarga(c),
                          color: const Color(0xFFEF4444),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  )),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileCards() {
    return Column(children: _cargas.map((c) {
      final estado = c['estado'] as String? ?? '';
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('#${c['id']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF6366F1))),
              const SizedBox(width: 8),
              _estadoBadge(estado),
              const Spacer(),
              Text(_fmtDate(c['fecha_recogida'] as String?), style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1))),
            ]),
            const SizedBox(height: 8),
            Text('${c['ciudad_origen'] ?? '—'} → ${c['ciudad_destino'] ?? '—'}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF334155))),
            const SizedBox(height: 4),
            Text('Shipper: ${c['shipper_name'] ?? '—'}', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
            if (c['carrier_name'] != null)
              Text('Carrier: ${c['carrier_name']}', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
            const SizedBox(height: 8),
            Row(children: [
              TextButton.icon(
                icon: const Icon(Icons.visibility_outlined, size: 14),
                label: const Text('Ver', style: TextStyle(fontSize: 11)),
                onPressed: () => _showDetalle(c),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF6366F1), visualDensity: VisualDensity.compact),
              ),
              TextButton.icon(
                icon: const Icon(Icons.swap_horiz_rounded, size: 14),
                label: const Text('Estado', style: TextStyle(fontSize: 11)),
                onPressed: () => _cambiarEstado(c),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFF59E0B), visualDensity: VisualDensity.compact),
              ),
              if (estado != 'cancelada')
                TextButton.icon(
                  icon: const Icon(Icons.cancel_outlined, size: 14),
                  label: const Text('Cancelar', style: TextStyle(fontSize: 11)),
                  onPressed: () => _cancelarCarga(c),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444), visualDensity: VisualDensity.compact),
                ),
            ]),
          ],
        ),
      );
    }).toList());
  }

  Widget _estadoBadge(String estado) {
    final color = _estadoColor(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(_estadoLabel(estado), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  String _truncUuid(String? u) {
    if (u == null || u.length < 8) return u ?? '—';
    return '${u.substring(0, 8)}...';
  }

  static const _th = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B), letterSpacing: 0.3);
}
