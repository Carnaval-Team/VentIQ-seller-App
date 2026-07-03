import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/agenda.dart';
import '../providers/auth_provider.dart';
import '../services/agenda_service.dart';
import '../widgets/datos_adicionales_view.dart';
import '../widgets/notificaciones_bell.dart';

class MisTicketsScreen extends StatefulWidget {
  const MisTicketsScreen({super.key});

  @override
  State<MisTicketsScreen> createState() => MisTicketsScreenState();
}

class MisTicketsScreenState extends State<MisTicketsScreen> {
  List<Agenda> _tickets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void reload() => _load();

  Future<void> _cancelar(Agenda ticket) async {
    final uuid = context.read<AuthProvider>().user?.id ?? '';
    if (uuid.isEmpty) return;

    final entidad = ticket.entidad;
    final horas = entidad?.horasAnticipacionCancelacion ?? 0;

    // Si la entidad configuró horas de anticipación, validamos el plazo.
    // Si no hay configuración (0 o null), el cliente puede cancelar en cualquier momento.
    if (horas > 0) {
      final ahora = DateTime.now();
      final limite = ticket.fechaHoraReserva.subtract(Duration(hours: horas));
      if (ahora.isAfter(limite)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Solo puedes cancelar hasta $horas horas antes de la reserva'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancelar reserva'),
        content: const Text('¿Estás seguro de que quieres cancelar esta reserva?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar reserva'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await AgendaService.cancelarTicketCliente(
        uuidUsuario: uuid,
        idAgenda: ticket.id,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reserva cancelada'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final uuid = context.read<AuthProvider>().user?.id ?? '';
      // Solo reservas en estado 'reservado' (id = 1)
      final tickets = await AgendaService.getMisTickets(uuid, idEstado: 1);
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _isLoading = false;
      });
    } catch (e) {
      print('[flow] MisTicketsScreen _load ERROR: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Column(
        children: [
          _buildHero(),
          Expanded(
            child: _isLoading
                ? _buildLoading()
                : _tickets.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppTheme.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          itemCount: _tickets.length,
                          itemBuilder: (_, i) => _TicketCard(
                            ticket: _tickets[i],
                            miUuid:
                                context.read<AuthProvider>().user?.id ?? '',
                            onCancelar: _cancelar,
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // Cabecera "hero" alineada con el catálogo y Mis Listas.
  Widget _buildHero() {
    final n = _tickets.length;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryDark, AppTheme.primary],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33405F90),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TUS TURNOS',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Mis Reservas',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isLoading
                          ? 'Cargando tus reservas...'
                          : n == 0
                              ? 'No tienes reservas activas'
                              : n == 1
                                  ? 'Tienes 1 reserva activa'
                                  : 'Tienes $n reservas activas',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  _HeroIconButton(onTap: _load),
                  const SizedBox(width: 4),
                  const NotificacionesBell(color: Colors.white),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppTheme.primary),
          SizedBox(height: 16),
          Text('Cargando tus reservas...',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.12),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.primary.withValues(alpha: 0.10),
                        AppTheme.accent.withValues(alpha: 0.10),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.confirmation_number_rounded,
                      size: 46, color: AppTheme.primary.withValues(alpha: 0.55)),
                ),
                const SizedBox(height: 18),
                const Text('No hay reservas',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('Tus turnos reservados aparecerán aquí',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Botón circular translúcido para acciones dentro del hero.
class _HeroIconButton extends StatelessWidget {
  final VoidCallback onTap;
  const _HeroIconButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.refresh, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final Agenda ticket;
  final String miUuid;
  final ValueChanged<Agenda> onCancelar;

  const _TicketCard({
    required this.ticket,
    required this.miUuid,
    required this.onCancelar,
  });

  Color get _estadoColor {
    switch (ticket.estado?.nombre) {
      case 'reservado':
        return AppTheme.primary;
      case 'completado':
        return AppTheme.success;
      case 'cancelado':
        return AppTheme.error;
      default:
        return AppTheme.textSecondary;
    }
  }

  bool get _puedeCancelar {
    if (ticket.estado?.nombre != 'reservado') return false;
    final horas = ticket.entidad?.horasAnticipacionCancelacion ?? 0;
    if (horas <= 0) return true;
    final limite = ticket.fechaHoraReserva.subtract(Duration(hours: horas));
    return DateTime.now().isBefore(limite);
  }

  IconData get _estadoIcon {
    switch (ticket.estado?.nombre) {
      case 'reservado':
        return Icons.schedule_rounded;
      case 'completado':
        return Icons.check_circle_rounded;
      case 'cancelado':
        return Icons.cancel_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = ticket.localServicio?.local;
    final servicio = ticket.localServicio?.servicio;
    final cliente = ticket.cliente;
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final color = _estadoColor;
    final esTercero = ticket.esParaTercero(miUuid);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Franja de acento vertical, teñida según el estado.
            Container(width: 5, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Ícono de estado.
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(_estadoIcon, color: color, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                local?.nombre ?? 'Local',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: AppTheme.textPrimary,
                                  letterSpacing: -0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (servicio != null) ...[
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    const Icon(Icons.design_services_outlined,
                                        size: 12, color: AppTheme.accent),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        servicio.nombre,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: AppTheme.accent,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Chip de estado.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Border.all(color: color.withValues(alpha: 0.30)),
                          ),
                          child: Text(
                            ticket.estado?.nombre ?? '',
                            style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(height: 1, color: AppTheme.border),
                    const SizedBox(height: 12),
                    _InfoLinea(
                      icon: Icons.calendar_today_rounded,
                      texto:
                          'Reserva: ${fmt.format(ticket.fechaHoraReserva.toLocal())}',
                    ),
                    if (ticket.cantidad > 1) ...[
                      const SizedBox(height: 6),
                      _InfoLinea(
                        icon: Icons.confirmation_number_outlined,
                        texto: '${ticket.cantidad} turnos reservados',
                        color: AppTheme.accent,
                      ),
                    ],
                    if (esTercero) ...[
                      const SizedBox(height: 6),
                      _InfoLinea(
                        icon: Icons.group_outlined,
                        texto:
                            'Para: ${cliente?.nombreCompleto.isNotEmpty == true ? cliente!.nombreCompleto : 'otra persona'}',
                        color: AppTheme.accent,
                      ),
                    ],
                    if (ticket.fechaHoraAtencion != null) ...[
                      const SizedBox(height: 6),
                      _InfoLinea(
                        icon: Icons.done_all_rounded,
                        texto:
                            'Atendido: ${fmt.format(ticket.fechaHoraAtencion!.toLocal())}',
                        color: AppTheme.success,
                      ),
                    ],
                    if (ticket.datosAdicionales != null &&
                        ticket.datosAdicionales!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'INFORMACIÓN ADICIONAL',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: AppTheme.textSecondary
                                    .withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 6),
                            DatosAdicionalesView(
                              valores: ticket.datosAdicionales,
                              campos: servicio?.camposAdicionales ?? const [],
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (cliente != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DATOS DEL CLIENTE',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: AppTheme.textSecondary
                                    .withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (cliente.nombreCompleto.isNotEmpty)
                              _ClienteRow(Icons.person_outlined,
                                  cliente.nombreCompleto),
                            if (cliente.ci != null && cliente.ci!.isNotEmpty)
                              _ClienteRow(
                                  Icons.badge_outlined, 'CI: ${cliente.ci}'),
                            if (cliente.telefono != null &&
                                cliente.telefono!.isNotEmpty)
                              _ClienteRow(
                                  Icons.phone_outlined, cliente.telefono!),
                          ],
                        ),
                      ),
                    ],
                    if (_puedeCancelar) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => onCancelar(ticket),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: const Text('Cancelar reserva'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.error,
                            side: const BorderSide(color: AppTheme.error),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Línea de info con ícono + texto (fechas del ticket).
class _InfoLinea extends StatelessWidget {
  final IconData icon;
  final String texto;
  final Color? color;

  const _InfoLinea({required this.icon, required this.texto, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textSecondary;
    return Row(
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(fontSize: 12, color: c),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ClienteRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ClienteRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
