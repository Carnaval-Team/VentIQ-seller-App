import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../services/carrito_bloqueos_service.dart';
import '../widgets/app_drawer.dart';

/// Panel de soporte: usuarios que incidieron en el anti-abuso del carrito.
/// Muestra quiénes eliminaron un producto más de dos veces, quiénes
/// reincidieron y quiénes están bloqueados, con opción de desbloquear.
class UsuariosBloqueadosScreen extends StatefulWidget {
  const UsuariosBloqueadosScreen({Key? key}) : super(key: key);

  @override
  State<UsuariosBloqueadosScreen> createState() =>
      _UsuariosBloqueadosScreenState();
}

enum _Filtro { todos, incidieron, reincidentes, bloqueados }

class _UsuariosBloqueadosScreenState extends State<UsuariosBloqueadosScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _incidencias = [];
  _Filtro _filtro = _Filtro.bloqueados;
  String _search = '';

  final DateFormat _fmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await CarritoBloqueosService.getIncidencias();
    if (!mounted) return;
    setState(() {
      _incidencias = data;
      _isLoading = false;
    });
  }

  bool _estaBloqueado(Map<String, dynamic> r) {
    final estado = r['estado_actual']?.toString() ?? '';
    return estado == 'bloqueado_temporal' || estado == 'bloqueado_permanente';
  }

  List<Map<String, dynamic>> get _filtradas {
    Iterable<Map<String, dynamic>> rows = _incidencias;

    switch (_filtro) {
      case _Filtro.incidieron:
        rows = rows.where((r) => r['incidio_mas_de_dos'] == true);
        break;
      case _Filtro.reincidentes:
        rows = rows.where((r) => r['reincidente'] == true);
        break;
      case _Filtro.bloqueados:
        rows = rows.where(_estaBloqueado);
        break;
      case _Filtro.todos:
        break;
    }

    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase();
      rows = rows.where((r) {
        final nombre = (r['usuario_nombre'] ?? '').toString().toLowerCase();
        final email = (r['usuario_email'] ?? '').toString().toLowerCase();
        final prod = (r['producto_nombre'] ?? '').toString().toLowerCase();
        return nombre.contains(q) || email.contains(q) || prod.contains(q);
      });
    }

    return rows.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Usuarios Bloqueados'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.surface,
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Buscar por usuario, email o producto...',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                _chip('Bloqueados', _Filtro.bloqueados),
                _chip('Reincidentes', _Filtro.reincidentes),
                _chip('Incidieron (>2)', _Filtro.incidieron),
                _chip('Todos', _Filtro.todos),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, _Filtro value) {
    final selected = _filtro == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
      onSelected: (_) => setState(() => _filtro = value),
    );
  }

  Widget _buildList() {
    final rows = _filtradas;
    if (rows.isEmpty) {
      return const Center(
        child: Text(
          'No hay registros para el filtro seleccionado',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _buildCard(rows[i]),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> r) {
    final estado = r['estado_actual']?.toString() ?? 'sin_bloqueo';
    final bloqueado = _estaBloqueado(r);
    final permanente = estado == 'bloqueado_permanente';

    final totalElim = r['total_eliminaciones'] ?? 0;
    final veces = r['veces_bloqueado'] ?? 0;
    final fin = r['bloqueo_fin'];

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (r['usuario_nombre'] ?? 'Sin nombre').toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        (r['usuario_email'] ?? '').toString(),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _estadoBadge(estado),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    (r['producto_nombre'] ?? '#${r['id_producto']}').toString(),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _metric('Eliminaciones', '$totalElim'),
                _metric('Últimas 2h', '${r['eliminaciones_ultimas_2h'] ?? 0}'),
                _metric('Veces bloqueado', '$veces'),
                if (r['incidio_mas_de_dos'] == true)
                  _tag('Incidió >2', AppColors.warning),
                if (r['reincidente'] == true)
                  _tag('Reincidente', AppColors.error),
              ],
            ),
            if (bloqueado && !permanente && fin != null) ...[
              const SizedBox(height: 8),
              Text(
                'Bloqueo temporal hasta: ${_fmtDate(fin)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (bloqueado) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: const Text('Desbloquear'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _confirmarDesbloqueo(r),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _estadoBadge(String estado) {
    late Color color;
    late String label;
    switch (estado) {
      case 'bloqueado_permanente':
        color = AppColors.error;
        label = 'Permanente';
        break;
      case 'bloqueado_temporal':
        color = AppColors.warning;
        label = 'Temporal';
        break;
      case 'bloqueo_expirado':
        color = AppColors.textSecondary;
        label = 'Expirado';
        break;
      default:
        color = AppColors.info;
        label = 'Sin bloqueo';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _fmtDate(dynamic value) {
    try {
      return _fmt.format(DateTime.parse(value.toString()).toLocal());
    } catch (_) {
      return value.toString();
    }
  }

  Future<void> _confirmarDesbloqueo(Map<String, dynamic> r) async {
    final nombre = (r['usuario_nombre'] ?? 'este usuario').toString();
    final producto =
        (r['producto_nombre'] ?? '#${r['id_producto']}').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desbloquear producto'),
        content: Text(
          '¿Desbloquear "$producto" para $nombre?\n\n'
          'Se eliminará el bloqueo y se limpiarán las eliminaciones recientes '
          'para que el patrón no se vuelva a disparar de inmediato. Se '
          'notificará al usuario.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desbloquear'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final userId = (r['user_id'] as num?)?.toInt();
    final idProducto = (r['id_producto'] as num?)?.toInt();
    if (userId == null || idProducto == null) return;

    final result = await CarritoBloqueosService.desbloquear(
      userId: userId,
      idProducto: idProducto,
    );

    if (!mounted) return;
    final success = result['desbloqueado'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Producto desbloqueado correctamente'
              : 'No se pudo desbloquear: ${result['error'] ?? 'sin bloqueo activo'}',
        ),
        backgroundColor: success ? AppColors.success : AppColors.error,
      ),
    );
    if (success) _load();
  }
}
