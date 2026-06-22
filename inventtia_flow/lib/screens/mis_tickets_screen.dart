import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/agenda.dart';
import '../providers/auth_provider.dart';
import '../services/agenda_service.dart';

class MisTicketsScreen extends StatefulWidget {
  const MisTicketsScreen({super.key});

  @override
  State<MisTicketsScreen> createState() => _MisTicketsScreenState();
}

class _MisTicketsScreenState extends State<MisTicketsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Agenda> _tickets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final uuid = context.read<AuthProvider>().user?.id ?? '';
      final tickets = await AgendaService.getMisTickets(uuid);
      setState(() {
        _tickets = tickets;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  List<Agenda> _filtrados(String estado) {
    return _tickets
        .where((t) => t.estado?.nombre == estado)
        .toList();
  }

  Future<void> _cancelar(Agenda ticket) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar Ticket'),
        content: const Text('¿Deseas cancelar este ticket?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Cancelar Ticket'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await AgendaService.cancelarTicket(ticket.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Mis Tickets'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Reservados'),
            Tab(text: 'Completados'),
            Tab(text: 'Cancelados'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildLista(_filtrados('reservado'), canCancel: true),
                _buildLista(_filtrados('completado')),
                _buildLista(_filtrados('cancelado')),
              ],
            ),
    );
  }

  Widget _buildLista(List<Agenda> lista, {bool canCancel = false}) {
    if (lista.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.confirmation_number_outlined,
                size: 64,
                color: AppTheme.textSecondary.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text('No hay tickets',
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
        itemBuilder: (_, i) => _TicketCard(
          ticket: lista[i],
          onCancelar: canCancel ? () => _cancelar(lista[i]) : null,
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final Agenda ticket;
  final VoidCallback? onCancelar;

  const _TicketCard({required this.ticket, this.onCancelar});

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
            if (onCancelar != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: onCancelar,
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Cancelar', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: const BorderSide(color: AppTheme.error),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
