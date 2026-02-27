import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_theme.dart';
import '../../models/transport_request_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/transport_provider.dart';

class RequestHistoryScreen extends StatefulWidget {
  const RequestHistoryScreen({super.key});

  @override
  State<RequestHistoryScreen> createState() => _RequestHistoryScreenState();
}

class _RequestHistoryScreenState extends State<RequestHistoryScreen> {
  List<TransportRequestModel> _requests = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final uuid = context.read<AuthProvider>().user?.id;
      if (uuid == null) return;

      final data = await Supabase.instance.client
          .schema('muevete')
          .from('solicitudes_transporte')
          .select()
          .eq('user_id', uuid)
          .order('created_at', ascending: false)
          .limit(50);

      setState(() {
        _requests = (data as List)
            .map((e) => TransportRequestModel.fromJson(e))
            .toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        title: Text(
          'Mis Solicitudes',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        iconTheme:
            IconThemeData(color: isDark ? Colors.white : Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: AppTheme.error)))
              : _requests.isEmpty
                  ? _EmptyHistory(isDark: isDark)
                  : RefreshIndicator(
                      onRefresh: _loadHistory,
                      color: AppTheme.primaryColor,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _requests.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) => _RequestTile(
                          request: _requests[i],
                          isDark: isDark,
                          onResume: _requests[i].estado ==
                                  EstadoSolicitud.pendiente
                              ? () => _resumeRequest(_requests[i])
                              : null,
                          onCancel: (_requests[i].estado ==
                                      EstadoSolicitud.pendiente ||
                                  _requests[i].estado ==
                                      EstadoSolicitud.expirada)
                              ? () => _cancelRequest(_requests[i])
                              : null,
                        ),
                      ),
                    ),
    );
  }

  Future<void> _resumeRequest(TransportRequestModel request) async {
    final transportProvider = context.read<TransportProvider>();
    final nav = Navigator.of(context);
    await transportProvider.restoreActiveRequest(request);
    if (mounted) nav.pushNamed('/client/driver-offers');
  }

  Future<void> _cancelRequest(TransportRequestModel request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar solicitud'),
        content: const Text('¿Estás seguro de que deseas cancelar esta solicitud?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .schema('muevete')
          .from('solicitudes_transporte')
          .update({'estado': 'cancelada'})
          .eq('id', request.id!);
      await _loadHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }
}

class _RequestTile extends StatelessWidget {
  final TransportRequestModel request;
  final bool isDark;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;

  const _RequestTile({
    required this.request,
    required this.isDark,
    this.onResume,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final estado = request.estado ?? EstadoSolicitud.expirada;
    final color = _estadoColor(estado);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: vehicle type + status badge
          Row(
            children: [
              Icon(
                _vehicleIcon(request.tipoVehiculo),
                color: AppTheme.primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _capitalize(request.tipoVehiculo ?? 'Transporte'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _estadoLabel(estado),  // estado is non-null after ?? above
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Route
          _RouteRow(
            icon: Icons.radio_button_checked,
            iconColor: AppTheme.success,
            text: request.direccionOrigen ?? 'Origen',
            isDark: isDark,
          ),
          const SizedBox(height: 4),
          _RouteRow(
            icon: Icons.location_on,
            iconColor: AppTheme.error,
            text: request.direccionDestino ?? 'Destino',
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          // Meta row: distance + price + date
          Row(
            children: [
              if (request.distanciaKm != null)
                _MetaChip(
                  label: '${request.distanciaKm!.toStringAsFixed(1)} km',
                  isDark: isDark,
                ),
              if (request.precioOferta != null) ...[
                const SizedBox(width: 8),
                _MetaChip(
                  label:
                      '\$${request.precioOferta!.toStringAsFixed(2)}',
                  isDark: isDark,
                ),
              ],
              const Spacer(),
              Text(
                _formatDate(request.createdAt),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.grey[500],
                ),
              ),
            ],
          ),
          if (onResume != null || onCancel != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (onResume != null)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onResume,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Continuar búsqueda',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                if (onResume != null && onCancel != null)
                  const SizedBox(width: 8),
                if (onCancel != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.error,
                        side: const BorderSide(color: AppTheme.error),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Cancelar',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _estadoColor(EstadoSolicitud estado) {
    switch (estado) {
      case EstadoSolicitud.pendiente:
        return AppTheme.warning;
      case EstadoSolicitud.aceptada:
        return AppTheme.success;
      case EstadoSolicitud.cancelada:
        return AppTheme.error;
      case EstadoSolicitud.expirada:
        return Colors.grey;
    }
  }

  String _estadoLabel(EstadoSolicitud estado) {
    switch (estado) {
      case EstadoSolicitud.pendiente:
        return 'Pendiente';
      case EstadoSolicitud.aceptada:
        return 'Aceptada';
      case EstadoSolicitud.cancelada:
        return 'Cancelada';
      case EstadoSolicitud.expirada:
        return 'Expirada';
    }
  }

  IconData _vehicleIcon(String? tipo) {
    switch (tipo?.toLowerCase()) {
      case 'moto':
        return Icons.two_wheeler;
      case 'microbus':
        return Icons.airport_shuttle;
      default:
        return Icons.directions_car;
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final bool isDark;

  const _RouteRow({
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.grey[700],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final bool isDark;

  const _MetaChip({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkBorder : Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white54 : Colors.grey[700],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  final bool isDark;
  const _EmptyHistory({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 64,
              color: isDark ? Colors.white24 : Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'Sin solicitudes aún',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}
