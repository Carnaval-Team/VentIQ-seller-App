import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/carga_provider.dart';
import '../../providers/theme_provider.dart';
import '../carrier/carrier_home_screen.dart';
import '../common/unified_profile_screen.dart';

class DispatcherHomeScreen extends StatefulWidget {
  const DispatcherHomeScreen({super.key});

  @override
  State<DispatcherHomeScreen> createState() =>
      _DispatcherHomeScreenState();
}

class _DispatcherHomeScreenState extends State<DispatcherHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  List<Map<String, dynamic>> _flota = [];
  bool _loadingFlota = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Future.wait([
      _loadFlota(),
      context.read<CargaProvider>().loadCargasDisponibles(),
    ]);
  }

  Future<void> _loadFlota() async {
    setState(() => _loadingFlota = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final dispatcherDriverId =
          authProvider.driverProfile?['id'] as int?;
      if (dispatcherDriverId == null) return;
      final data = await Supabase.instance.client
          .schema('muevete')
          .from('drivers')
          .select('id, name, telefono, estado')
          .eq('dispatcher_id', dispatcherDriverId);
      if (mounted) {
        setState(() => _flota = List<Map<String, dynamic>>.from(data));
      }
    } catch (_) {
      // Graceful: empty fleet on error
    } finally {
      if (mounted) setState(() => _loadingFlota = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final auth = context.watch<AuthProvider>();
    final name =
        (auth.driverProfile?['name'] as String?) ?? 'Dispatcher';
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        elevation: 0,
        title: Text(
          'Hola, $name',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.person_outline, color: textPrimary),
            tooltip: 'Mi Perfil',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const UnifiedProfileScreen(),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh_outlined, color: textPrimary),
            onPressed: _load,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: Icon(Icons.logout, color: textPrimary),
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/landing');
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor:
              isDark ? Colors.white54 : Colors.grey[500],
          indicatorColor: AppTheme.primaryColor,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.search_outlined), text: 'Cargas'),
            Tab(icon: Icon(Icons.groups_outlined), text: 'Mi Flota'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          const CargasDisponiblesTab(),
          _FlotaTab(
              flota: _flota,
              loading: _loadingFlota,
              onRefresh: _loadFlota),
        ],
      ),
    );
  }
}

class _FlotaTab extends StatelessWidget {
  final List<Map<String, dynamic>> flota;
  final bool loading;
  final VoidCallback onRefresh;
  const _FlotaTab(
      {required this.flota,
      required this.loading,
      required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary =
        isDark ? Colors.white60 : Colors.grey[600]!;

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (flota.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.groups_outlined,
                  size: 64, color: AppTheme.primaryColor),
              const SizedBox(height: 16),
              Text(
                'Sin transportistas en la flota',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Los transportistas vinculados a tu empresa aparecerán aquí.',
                style:
                    TextStyle(fontSize: 13, color: textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: flota.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final driver = flota[i];
          final nombre =
              driver['name'] as String? ?? 'Transportista';
          final phone =
              driver['telefono'] as String? ?? '';
          final activo = driver['estado'] == true;
          return Container(
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isDark
                      ? AppTheme.darkBorder
                      : Colors.grey[200]!),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.primaryColor
                      .withValues(alpha: 0.15),
                  child: Text(
                    nombre.isNotEmpty
                        ? nombre[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nombre,
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: textPrimary)),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(phone,
                            style: TextStyle(
                                fontSize: 12,
                                color: textSecondary)),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (activo ? Colors.green : Colors.grey)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color:
                            (activo ? Colors.green : Colors.grey)
                                .withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    activo ? 'Activo' : 'Inactivo',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color:
                            activo ? Colors.green : Colors.grey),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
