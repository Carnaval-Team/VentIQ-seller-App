import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../services/muevete_service.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_drawer.dart';

/// Verificación KYC de Muevete.
///
/// Revisa dos colas distintas:
///  * **Clientes** → `muevete.users` (un cliente sin aprobar no puede publicar
///    viajes, ver migración 048).
///  * **Choferes** → `muevete.drivers`.
///
/// Todas las acciones pasan por la RPC `muevete.fn_kyc_revisar`, que es la
/// única vía que escribe `kyc_estado` en ambas tablas.
class MueveteKycScreen extends StatefulWidget {
  const MueveteKycScreen({super.key});
  @override
  State<MueveteKycScreen> createState() => _MueveteKycScreenState();
}

class _MueveteKycScreenState extends State<MueveteKycScreen> {
  List<Map<String, dynamic>> _clientes = [];
  List<Map<String, dynamic>> _choferes = [];
  bool _isLoading = true;
  String? _error;
  int _tab = 0; // 0 = clientes · 1 = choferes

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  int get _totalPendientes => _clientes.length + _choferes.length;

  /// Lista de la pestaña activa.
  List<Map<String, dynamic>> get _visibles => _tab == 0 ? _clientes : _choferes;

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Cada cola se carga por separado: si una falla, la otra sigue sirviendo.
    final errores = <String>[];
    var clientes = <Map<String, dynamic>>[];
    var choferes = <Map<String, dynamic>>[];

    try {
      clientes = await MueveteService.getPendingKycClients();
    } catch (e) {
      debugPrint('[MueveteKycScreen] clientes: $e');
      errores.add('los clientes');
    }

    try {
      choferes = await MueveteService.getPendingKycDrivers();
    } catch (e) {
      debugPrint('[MueveteKycScreen] conductores: $e');
      errores.add('los conductores');
    }

    if (!mounted) return;
    setState(() {
      _clientes = clientes;
      _choferes = choferes;
      _isLoading = false;
      _error = errores.isEmpty
          ? null
          : 'No se pudieron cargar ${errores.join(' ni ')}. Revisa la conexión.';
      // Si la pestaña activa quedó vacía y la otra tiene trabajo, se cambia
      // sola para no dejar al revisor mirando una lista sin nada.
      if (_visibles.isEmpty &&
          (_tab == 0 ? _choferes : _clientes).isNotEmpty) {
        _tab = _tab == 0 ? 1 : 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(
      MediaQuery.of(context).size.width,
    );
    final pendientes = _visibles;
    final pad = isDesktop ? 32.0 : 16.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            surfaceTintColor: Colors.black,
            elevation: 0.5,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: _totalPendientes > 0
                        ? LinearGradient(colors: [
                            AppColors.error,
                            AppColors.error.withValues(alpha: 0.7),
                          ])
                        : LinearGradient(colors: [
                            AppColors.success,
                            AppColors.success.withValues(alpha: 0.7),
                          ]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verificación KYC',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '$_totalPendientes pendientes',
                      style: TextStyle(
                        fontSize: 12,
                        color: _totalPendientes > 0
                            ? AppColors.error
                            : AppColors.success,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: _loadData,
                icon: Icon(
                  Icons.refresh_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
              child: Column(
                children: [
                  _buildTabs(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _buildErrorBanner(_error!),
                  ],
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 16, pad, pad),
            sliver: _isLoading
                ? const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : pendientes.isEmpty
                    ? SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(),
                      )
                    : SliverGrid(
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: isDesktop ? 460 : 620,
                          mainAxisExtent: isDesktop ? 500 : 470,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _buildCard(
                            pendientes[i],
                            esCliente: _tab == 0,
                          ),
                          childCount: pendientes.length,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ─── Pestañas ────────────────────────────────────────────────────────

  Widget _buildTabs() {
    Widget tab({
      required int index,
      required String label,
      required IconData icon,
      required Color color,
    }) {
      final activo = _tab == index;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = index),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: activo ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: activo
                    ? color.withValues(alpha: 0.35)
                    : Colors.transparent,
              ),
              boxShadow: activo
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: activo ? color : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: activo ? FontWeight.w700 : FontWeight.w600,
                      color: activo ? color : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          tab(
            index: 0,
            label: 'Clientes (${_clientes.length})',
            icon: Icons.person_rounded,
            color: AppColors.secondary,
          ),
          const SizedBox(width: 6),
          tab(
            index: 1,
            label: 'Choferes (${_choferes.length})',
            icon: Icons.directions_car_rounded,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String mensaje) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
          TextButton(
            onPressed: _loadData,
            child: const Text(
              'Reintentar',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Estados vacíos ──────────────────────────────────────────────────

  Widget _buildEmptyState() {
    // "Todo verificado" sólo cuando no queda nada en ninguna de las dos colas.
    if (_totalPendientes == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_rounded,
                size: 48,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Todo verificado',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No hay clientes ni conductores pendientes de revisión',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    final esClientes = _tab == 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(
                esClientes
                    ? Icons.person_search_rounded
                    : Icons.no_crash_rounded,
                size: 42,
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              esClientes
                  ? 'No hay clientes pendientes'
                  : 'No hay conductores pendientes',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              esClientes
                  ? 'Los clientes con CI y ambas fotos del documento aparecen aquí'
                  : 'Los conductores con el KYC sin revisar aparecen aquí',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Tarjeta (cliente y chofer comparten estética) ───────────────────

  Widget _buildCard(Map<String, dynamic> d, {required bool esCliente}) {
    final nombre = _texto(d['name'], 'Sin nombre');
    final email = _texto(d['email'], '—');
    // users usa `phone`; drivers usa `telefono`.
    final telefono = _texto(esCliente ? d['phone'] : d['telefono'], '—');
    final ci = _texto(d['ci'], '—');
    final tipoDoc = _texto(d['tipo_documento'], '—');
    final estado = _texto(d['kyc_estado'], 'pendiente');
    final docF = d['doc_frente_url'] as String?;
    final docD = d['doc_dorso_url'] as String?;
    final veh = esCliente ? null : d['vehiculos'] as Map<String, dynamic>?;
    final accent = esCliente ? AppColors.secondary : AppColors.error;
    final initial = nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.surfaceVariant),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _chip(
                            label: esCliente ? 'Cliente' : 'Chofer',
                            color: accent,
                            icon: esCliente
                                ? Icons.person_rounded
                                : Icons.directions_car_rounded,
                          ),
                          _estadoChip(estado),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Info
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow(Icons.phone_rounded, telefono),
                  if (esCliente)
                    _infoRow(Icons.assignment_ind_rounded, 'CI: $ci'),
                  _infoRow(Icons.badge_rounded, 'Doc: $tipoDoc'),
                  if (esCliente) ...[
                    _infoRow(Icons.place_rounded, _ubicacion(d)),
                    _infoRow(Icons.home_rounded, _texto(d['direccion'], '—')),
                  ],
                  if (!esCliente && veh != null)
                    _infoRow(
                      Icons.directions_car_rounded,
                      '${veh['marca'] ?? ''} ${veh['modelo'] ?? ''} · ${veh['chapa'] ?? ''}',
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'DOCUMENTOS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _docThumb('Frente', docF)),
                      const SizedBox(width: 10),
                      Expanded(child: _docThumb('Dorso', docD)),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          // Actions
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.surfaceVariant),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _rechazar(d, esCliente: esCliente),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(
                        color: AppColors.error.withValues(alpha: 0.4),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Rechazar',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _aprobar(d, esCliente: esCliente),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Aprobar',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _estadoChip(String estado) {
    final enRevision = estado == 'en_revision';
    final color = enRevision ? AppColors.info : AppColors.warning;
    final label = enRevision
        ? 'En revisión'
        : (estado == 'pendiente' ? 'Pendiente' : estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.textHint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _texto(dynamic valor, String fallback) {
    if (valor == null) return fallback;
    final s = valor.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  String _ubicacion(Map<String, dynamic> d) {
    final partes = <String>[];
    for (final clave in ['province', 'municipality', 'poblado']) {
      final v = _texto(d[clave], '');
      if (v.isNotEmpty) partes.add(v);
    }
    return partes.isEmpty ? '—' : partes.join(' · ');
  }

  Widget _docThumb(String label, String? url) {
    return GestureDetector(
      onTap: url != null && url.isNotEmpty ? () => _showDocFull(label, url) : null,
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 80,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: AppColors.surfaceVariant,
              border: Border.all(color: AppColors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: url != null && url.isNotEmpty
                ? Stack(
                    children: [
                      Image.network(
                        url,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(
                            Icons.broken_image_rounded,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.fullscreen_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Text(
                      'Sin doc.',
                      style: TextStyle(fontSize: 11, color: AppColors.textHint),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showDocFull(String label, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      'Documento — $label',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Center(child: Text('Error cargando imagen')),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Acciones (siempre por RPC) ──────────────────────────────────────

  Future<void> _aprobar(
    Map<String, dynamic> d, {
    required bool esCliente,
  }) async {
    final nombre = _texto(d['name'], 'Sin nombre');
    final uuid = d['uuid'] as String?;
    if (uuid == null || uuid.isEmpty) {
      _snack('No se pudo identificar a $nombre (falta el uuid)', AppColors.error);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          esCliente ? 'Aprobar cliente' : 'Aprobar conductor',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          esCliente
              ? '¿Confirmas la verificación de $nombre?\nEl cliente podrá publicar viajes.'
              : '¿Confirmas la verificación de $nombre?\nEl conductor podrá operar con el badge "Verificado".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await MueveteService.revisarKyc(
        rol: esCliente ? 'cliente' : 'chofer',
        uuid: uuid,
        decision: 'aprobado',
      );
      await _loadData();
      _snack('$nombre verificado', AppColors.success);
    } catch (e) {
      _snack(_mensajeError(e), AppColors.error);
    }
  }

  Future<void> _rechazar(
    Map<String, dynamic> d, {
    required bool esCliente,
  }) async {
    final nombre = _texto(d['name'], 'Sin nombre');
    final uuid = d['uuid'] as String?;
    if (uuid == null || uuid.isEmpty) {
      _snack('No se pudo identificar a $nombre (falta el uuid)', AppColors.error);
      return;
    }

    final ctrl = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          esCliente ? 'Rechazar cliente' : 'Rechazar conductor',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Por qué se rechaza a $nombre?',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Documentos ilegibles, datos incorrectos...',
                hintStyle: TextStyle(color: AppColors.textHint, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.error, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'El motivo es obligatorio: el usuario lo verá en la app.',
              style: TextStyle(fontSize: 11, color: AppColors.textHint),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (!mounted) return;
    if (motivo == null) return; // canceló
    if (motivo.isEmpty) {
      _snack('Escribe el motivo del rechazo', AppColors.warning);
      return;
    }

    try {
      await MueveteService.revisarKyc(
        rol: esCliente ? 'cliente' : 'chofer',
        uuid: uuid,
        decision: 'rechazado',
        motivo: motivo,
      );
      await _loadData();
      _snack('$nombre rechazado', AppColors.error);
    } catch (e) {
      _snack(_mensajeError(e), AppColors.error);
    }
  }

  void _snack(String mensaje, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _mensajeError(Object e) {
    const prefijo = 'Exception: ';
    final texto = e.toString();
    return texto.startsWith(prefijo) ? texto.substring(prefijo.length) : texto;
  }
}