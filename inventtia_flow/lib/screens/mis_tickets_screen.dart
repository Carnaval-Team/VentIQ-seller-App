import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/agenda.dart';
import '../providers/auth_provider.dart';
import '../services/agenda_service.dart';
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
      appBar: AppBar(
        title: const Text('Mis Reservas'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          const Padding(
            padding: EdgeInsets.only(right: 12, left: 4),
            child: NotificacionesBell(color: Colors.white),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildLista(_tickets),
    );
  }

  Widget _buildLista(List<Agenda> lista) {
    if (lista.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.confirmation_number_outlined,
                size: 64,
                color: AppTheme.textSecondary.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text('No hay reservas',
                style:
                    TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: lista.length,
        itemBuilder: (_, i) => _TicketCard(ticket: lista[i]),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final Agenda ticket;

  const _TicketCard({required this.ticket});

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

  IconData get _estadoIcon {
    switch (ticket.estado?.nombre) {
      case 'reservado':
        return Icons.schedule;
      case 'completado':
        return Icons.check_circle;
      case 'cancelado':
        return Icons.cancel;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = ticket.localServicio?.local;
    final servicio = ticket.localServicio?.servicio;
    final cliente = ticket.cliente;
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _estadoColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child:
                      Icon(_estadoIcon, color: _estadoColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        local?.nombre ?? 'Local',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (servicio != null)
                        Text(servicio.nombre,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.accent)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _estadoColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _estadoColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    ticket.estado?.nombre ?? '',
                    style: TextStyle(
                        color: _estadoColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'Reserva: ${fmt.format(ticket.fechaHoraReserva.toLocal())}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
            if (ticket.fechaHoraAtencion != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.done_all,
                      size: 14, color: AppTheme.success),
                  const SizedBox(width: 6),
                  Text(
                    'Atendido: ${fmt.format(ticket.fechaHoraAtencion!.toLocal())}',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.success),
                  ),
                ],
              ),
            ],
            if (cliente != null) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              if (cliente.nombreCompleto.isNotEmpty)
                _ClienteRow(
                    Icons.person_outlined, cliente.nombreCompleto),
              if (cliente.ci != null && cliente.ci!.isNotEmpty)
                _ClienteRow(Icons.badge_outlined, 'CI: ${cliente.ci}'),
              if (cliente.telefono != null && cliente.telefono!.isNotEmpty)
                _ClienteRow(Icons.phone_outlined, cliente.telefono!),
            ],
          ],
        ),
      ),
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
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }
}
