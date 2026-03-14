import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../services/muevete_service.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_drawer.dart';

class MueveteDashboardScreen extends StatefulWidget {
  const MueveteDashboardScreen({super.key});

  @override
  State<MueveteDashboardScreen> createState() =>
      _MueveteDashboardScreenState();
}

class _MueveteDashboardScreenState extends State<MueveteDashboardScreen> {
  Map<String, int> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final stats = await MueveteService.getStats();
      if (mounted) setState(() { _stats = stats; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(w);
    final pad = isDesktop ? 32.0 : 16.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                _buildAppBar(isDesktop),
                SliverPadding(
                  padding: EdgeInsets.all(pad),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildKpiRow(isDesktop),
                      const SizedBox(height: 28),
                      _buildSectionTitle('Operaciones en Tiempo Real'),
                      const SizedBox(height: 14),
                      _buildLiveCards(isDesktop),
                      const SizedBox(height: 28),
                      _buildSectionTitle('Accesos Rápidos'),
                      const SizedBox(height: 14),
                      _buildQuickActions(isDesktop),
                    ]),
                  ),
                ),
              ],
            ),
    );
  }

  // ── App Bar ─────────────────────────────────────────────────────────
  SliverAppBar _buildAppBar(bool isDesktop) {
    return SliverAppBar(
      floating: true,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0.5,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.directions_car, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Inventtia Muévete',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              Text('Panel de control',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _loadData,
          icon: Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
          tooltip: 'Actualizar datos',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ── KPI Row ─────────────────────────────────────────────────────────
  Widget _buildKpiRow(bool isDesktop) {
    final kpis = [
      _KpiData('Conductores', _stats['total_drivers'] ?? 0,
          '${_stats['drivers_online'] ?? 0} en línea', Icons.people_alt_rounded,
          AppColors.primary, AppColors.primaryLight),
      _KpiData('Viajes', _stats['total_trips'] ?? 0,
          '${_stats['trips_completed'] ?? 0} completados', Icons.route_rounded,
          AppColors.secondary, AppColors.secondaryLight),
      _KpiData('Solicitudes', _stats['total_requests'] ?? 0,
          '${_stats['requests_pending'] ?? 0} pendientes', Icons.taxi_alert_rounded,
          AppColors.warning, const Color(0xFFFFB74D)),
      _KpiData('Pasajeros', _stats['total_users'] ?? 0,
          'Registrados', Icons.person_rounded,
          AppColors.success, const Color(0xFF66BB6A)),
    ];

    if (isDesktop) {
      return Row(
        children: kpis.map((k) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _buildKpiCard(k),
          ),
        )).toList(),
      );
    }
    return Column(
      children: [
        Row(children: [
          Expanded(child: _buildKpiCard(kpis[0])),
          const SizedBox(width: 12),
          Expanded(child: _buildKpiCard(kpis[1])),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _buildKpiCard(kpis[2])),
          const SizedBox(width: 12),
          Expanded(child: _buildKpiCard(kpis[3])),
        ]),
      ],
    );
  }

  Widget _buildKpiCard(_KpiData kpi) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [kpi.c1, kpi.c2]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(kpi.icon, color: Colors.white, size: 22),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kpi.c1.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(kpi.subtitle,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: kpi.c1)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('${kpi.value}',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary, height: 1)),
          const SizedBox(height: 4),
          Text(kpi.title,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  // ── Live operation cards ────────────────────────────────────────────
  Widget _buildLiveCards(bool isDesktop) {
    final pending = _stats['pending_kyc'] ?? 0;
    final onlineNow = _stats['drivers_online'] ?? 0;
    final pendReq = _stats['requests_pending'] ?? 0;

    final cards = [
      _buildLiveCard(
        icon: Icons.verified_user_rounded,
        title: 'Verificaciones KYC',
        value: '$pending pendientes',
        color: pending > 0 ? AppColors.error : AppColors.success,
        route: '/muevete/kyc',
        urgent: pending > 0,
      ),
      _buildLiveCard(
        icon: Icons.gps_fixed_rounded,
        title: 'Conductores en línea',
        value: '$onlineNow activos ahora',
        color: AppColors.primary,
        route: '/muevete/mapa',
      ),
      _buildLiveCard(
        icon: Icons.pending_actions_rounded,
        title: 'Solicitudes pendientes',
        value: '$pendReq esperando conductor',
        color: AppColors.warning,
        route: '/muevete/solicitudes',
        urgent: pendReq > 5,
      ),
    ];

    if (isDesktop) {
      return Row(
        children: cards.map((c) => Expanded(
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: c),
        )).toList(),
      );
    }
    return Column(
      children: cards.map((c) => Padding(
        padding: const EdgeInsets.only(bottom: 12), child: c,
      )).toList(),
    );
  }

  Widget _buildLiveCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    required String route,
    bool urgent = false,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: () => Navigator.pushReplacementNamed(context, route),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: urgent ? color.withOpacity(0.3) : AppColors.divider,
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(value, style: TextStyle(fontSize: 12,
                        color: urgent ? color : AppColors.textSecondary,
                        fontWeight: urgent ? FontWeight.w600 : FontWeight.w400)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }

  // ── Quick Actions ──────────────────────────────────────────────────
  Widget _buildQuickActions(bool isDesktop) {
    final actions = [
      _QA('Mapa en Vivo', Icons.map_rounded, AppColors.success, '/muevete/mapa'),
      _QA('Conductores', Icons.people_alt_rounded, AppColors.primary, '/muevete/conductores'),
      _QA('Viajes', Icons.route_rounded, AppColors.secondary, '/muevete/viajes'),
      _QA('Solicitudes', Icons.taxi_alert_rounded, AppColors.warning, '/muevete/solicitudes'),
      _QA('Valoraciones', Icons.star_rounded, const Color(0xFFFF9800), '/muevete/valoraciones'),
      _QA('Billeteras', Icons.account_balance_wallet_rounded, AppColors.primaryDark, '/muevete/billeteras'),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: actions.map((a) => SizedBox(
        width: isDesktop ? 180 : (MediaQuery.of(context).size.width - 44) / 2,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => Navigator.pushReplacementNamed(context, a.route),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: a.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(a.icon, color: a.color, size: 26),
                  ),
                  const SizedBox(height: 10),
                  Text(a.title, textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
          ),
        ),
      )).toList(),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(text, style: TextStyle(fontSize: 17,
        fontWeight: FontWeight.w700, color: AppColors.textPrimary));
  }
}

class _KpiData {
  final String title;
  final int value;
  final String subtitle;
  final IconData icon;
  final Color c1, c2;
  const _KpiData(this.title, this.value, this.subtitle, this.icon, this.c1, this.c2);
}

class _QA {
  final String title;
  final IconData icon;
  final Color color;
  final String route;
  const _QA(this.title, this.icon, this.color, this.route);
}
