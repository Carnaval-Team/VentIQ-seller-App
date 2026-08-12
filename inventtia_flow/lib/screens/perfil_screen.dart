import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/entidad_provider.dart';
import '../services/auth_service.dart';
import '../widgets/notificaciones_bell.dart';
import '../services/update_service.dart';
import 'perfil_setup_screen.dart';
import 'admin/entidad_detail_screen.dart';
import 'admin/gestion_locales_screen.dart';
import 'admin/gestion_servicios_screen.dart';

class PerfilScreen extends StatelessWidget {
  const PerfilScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro que deseas cerrar sesión?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Cerrar Sesión'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      final auth = context.read<AuthProvider>();
      final entidad = context.read<EntidadProvider>();
      // Navegar primero antes de que signOut dispare notifyListeners
      // y potencialmente invalide el contexto
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      entidad.limpiar();
      await auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final entidadProv = context.watch<EntidadProvider>();
    final perfil = auth.perfil;
    final user = auth.user;

    final inicial = perfil != null
        ? perfil.nombre[0].toUpperCase()
        : (user?.email?[0].toUpperCase() ?? 'U');

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Column(
        children: [
          // ── Hero con avatar integrado ───────────────────────────
          _buildHero(
            inicial: inicial,
            nombre: perfil?.nombreCompleto ?? 'Sin nombre',
            email: user?.email ?? '',
          ),

          // ── Contenido desplazable ───────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Datos del perfil ─────────────────────────────
                  const _SectionLabel('DATOS PERSONALES'),
                  const SizedBox(height: 10),
                  _SoftCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _InfoRow(
                            icon: Icons.person_outlined,
                            label: 'Nombre',
                            value: perfil?.nombre ?? '-'),
                        const _SoftDivider(),
                        _InfoRow(
                            icon: Icons.person_outlined,
                            label: 'Apellidos',
                            value: perfil?.apellidos ?? '-'),
                        const _SoftDivider(),
                        _InfoRow(
                            icon: Icons.badge_outlined,
                            label: 'CI',
                            value: perfil?.ci ?? '-'),
                        const _SoftDivider(),
                        _InfoRow(
                            icon: Icons.phone_outlined,
                            label: 'Teléfono',
                            value: perfil?.telefono ?? '-'),
                        const _SoftDivider(),
                        _InfoRow(
                            icon: Icons.email_outlined,
                            label: 'Correo',
                            value: user?.email ?? '-'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // ── Sección Entidad ──────────────────────────────
                  if (entidadProv.isAdmin)
                    _EntidadAdminSection(provider: entidadProv)
                  else
                    _EntidadRegisterBanner(ownerUuid: user?.id ?? ''),
                  const SizedBox(height: 22),

                  // ── Acciones generales ───────────────────────────
                  const _SectionLabel('CUENTA'),
                  const SizedBox(height: 10),
                  _SoftCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _ActionTile(
                          icon: Icons.edit_outlined,
                          title: 'Editar Perfil',
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const PerfilSetupScreen())),
                        ),
                        const _SoftDivider(indent: 56),
                        _ActionTile(
                          icon: Icons.notifications_outlined,
                          title: 'Notificaciones',
                          onTap: () => Navigator.pushNamed(
                              context, '/notificaciones'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // ── Versión de la app ────────────────────────────
                  const _AppVersionSection(),
                  const SizedBox(height: 22),

                  // ── Cerrar sesión ────────────────────────────────
                  OutlinedButton.icon(
                    onPressed: () => _signOut(context),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Cerrar Sesión'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: const BorderSide(color: AppTheme.error),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Cabecera "hero" con el avatar del usuario embebido sobre el degradado.
  Widget _buildHero({
    required String inicial,
    required String nombre,
    required String email,
  }) {
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
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    'MI PERFIL',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  const NotificacionesBell(color: Colors.white),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  // Avatar circular con anillo translúcido.
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.45),
                          width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 34,
                      backgroundColor: Colors.white,
                      child: Text(
                        inicial,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombre,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.email_outlined,
                                size: 13,
                                color: Colors.white.withValues(alpha: 0.75)),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                email,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Etiqueta de sección (eyebrow) ──────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: AppTheme.textSecondary.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

// ── Tarjeta blanca con sombra suave (estilo home) ──────────────
class _SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _SoftCard({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
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
      child: child,
    );
  }
}

class _SoftDivider extends StatelessWidget {
  final double indent;
  const _SoftDivider({this.indent = 0});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 20, thickness: 1, color: AppTheme.border, indent: indent);
  }
}

// ── ListTile de acción con flecha ──────────────────────────────
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _ActionTile(
      {required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
              ),
              const Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Banner para usuarios sin entidad ──────────────────────────
class _EntidadRegisterBanner extends StatelessWidget {
  final String ownerUuid;
  const _EntidadRegisterBanner({required this.ownerUuid});

  void _registrar(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _NuevaEntidadSheet(ownerUuid: ownerUuid),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.08),
            AppTheme.accent.withValues(alpha: 0.06)
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.business_outlined,
                    color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('¿Tienes una organización?',
                    style:
                        TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Registra tu entidad para gestionar locales, servicios y turnos desde la app.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _registrar(context),
              icon: const Icon(Icons.add_business, size: 18),
              label: const Text('Registrar Entidad'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sección para admins: selector + accesos rápidos ───────────
class _EntidadAdminSection extends StatelessWidget {
  final EntidadProvider provider;
  const _EntidadAdminSection({required this.provider});

  @override
  Widget build(BuildContext context) {
    final seleccionada = provider.entidadSeleccionada;
    final myUuid = AuthService.currentUserId ?? '';

    // Si no hay UUID, mostrar mensaje de error
    if (myUuid.isEmpty) {
      return const Center(
        child: Text('No se pudo obtener el usuario autenticado'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cabecera con selector
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _SectionLabel('MIS ENTIDADES'),
              TextButton.icon(
                onPressed: () => _nuevaEntidad(context, myUuid),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Nueva', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Chips de selección de entidad
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: provider.misEntidades.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final e = provider.misEntidades[i];
              final isSelected = seleccionada?.id == e.id;
              return ChoiceChip(
                label: Text(e.denominacion,
                    style: TextStyle(
                        fontSize: 13,
                        color: isSelected
                            ? Colors.white
                            : AppTheme.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.normal)),
                selected: isSelected,
                selectedColor: AppTheme.primary,
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: BorderSide(
                      color: isSelected
                          ? AppTheme.primary
                          : AppTheme.border),
                ),
                showCheckmark: false,
                onSelected: (_) => provider.seleccionarEntidad(e),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              );
            },
          ),
        ),
        const SizedBox(height: 12),

        // Card de la entidad seleccionada con accesos rápidos
        if (seleccionada != null)
          _SoftCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  contentPadding:
                      const EdgeInsets.fromLTRB(14, 6, 8, 6),
                  leading: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.primary.withValues(alpha: 0.14),
                          AppTheme.accent.withValues(alpha: 0.14),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(seleccionada.denominacion[0].toUpperCase(),
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 18)),
                  ),
                  title: Text(seleccionada.denominacion,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  subtitle: seleccionada.direccion != null
                      ? Text(seleccionada.direccion!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12))
                      : null,
                  trailing: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              EntidadDetailScreen(entidad: seleccionada)),
                    ),
                    child: const Text('Detalle'),
                  ),
                ),
                const _SoftDivider(indent: 14),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      _QuickAction(
                        icon: Icons.store_outlined,
                        label: 'Locales',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => GestionLocalesScreen(
                                  entidad: seleccionada)),
                        ),
                      ),
                      _QuickAction(
                        icon: Icons.miscellaneous_services_outlined,
                        label: 'Servicios',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => GestionServiciosScreen(
                                  entidad: seleccionada)),
                        ),
                      ),
                      _QuickAction(
                        icon: Icons.people_alt_outlined,
                        label: 'Admins',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => EntidadDetailScreen(
                                  entidad: seleccionada)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _nuevaEntidad(BuildContext context, String ownerUuid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _NuevaEntidadSheet(ownerUuid: ownerUuid),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 21, color: AppTheme.primary),
              ),
              const SizedBox(height: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Formulario nueva entidad (compartido) ──────────────────────
class _NuevaEntidadSheet extends StatefulWidget {
  final String ownerUuid;
  const _NuevaEntidadSheet({required this.ownerUuid});

  @override
  State<_NuevaEntidadSheet> createState() => _NuevaEntidadSheetState();
}

class _NuevaEntidadSheetState extends State<_NuevaEntidadSheet> {
  final _formKey = GlobalKey<FormState>();
  final _denomCtrl = TextEditingController();
  final _dirCtrl = TextEditingController();
  final _telCtrl = TextEditingController();

  @override
  void dispose() {
    _denomCtrl.dispose();
    _dirCtrl.dispose();
    _telCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<EntidadProvider>();
    final result = await provider.crearEntidad(
      denominacion: _denomCtrl.text.trim(),
      direccion: _dirCtrl.text.trim().isEmpty ? null : _dirCtrl.text.trim(),
      telefono: _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
      ownerUuid: widget.ownerUuid,
    );
    if (!mounted) return;
    if (result != null) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Error al crear la entidad'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EntidadProvider>();
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Nueva Entidad',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Serás el propietario (owner) de esta entidad.',
                style:
                    TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            const SizedBox(height: 20),
            TextFormField(
              controller: _denomCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Denominación *',
                  prefixIcon: Icon(Icons.business)),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dirCtrl,
              decoration: const InputDecoration(
                  labelText: 'Dirección',
                  prefixIcon: Icon(Icons.location_on_outlined)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Teléfono de contacto',
                  prefixIcon: Icon(Icons.phone_outlined)),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: provider.isLoading ? null : _submit,
              child: provider.isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Crear Entidad',
                      style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sección versión de la app ──────────────────────────────────
class _AppVersionSection extends StatefulWidget {
  const _AppVersionSection();

  @override
  State<_AppVersionSection> createState() => _AppVersionSectionState();
}

class _AppVersionSectionState extends State<_AppVersionSection> {
  String _version = '...';
  int _build = 0;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await UpdateService.getCurrentVersionInfo();
      if (mounted) {
        setState(() {
          _version = info['current_version'] ?? '1.0.0';
          _build = info['build'] ?? 1;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkUpdates() async {
    setState(() => _checking = true);
    try {
      final updateInfo = await UpdateService.checkForUpdates();
      if (!mounted) return;
      setState(() => _checking = false);
      if (updateInfo['hay_actualizacion'] == true) {
        _showUpdateDialog(updateInfo);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La aplicación está actualizada'),
            backgroundColor: AppTheme.primary,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al verificar: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _showUpdateDialog(Map<String, dynamic> updateInfo) {
    final bool isObligatory = updateInfo['obligatoria'] ?? false;
    final String newVersion = updateInfo['version_disponible'] ?? '';
    showDialog(
      context: context,
      barrierDismissible: !isObligatory,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isObligatory ? Icons.warning_amber_rounded : Icons.system_update,
              color: isObligatory ? Colors.orange : AppTheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isObligatory
                    ? 'Actualización obligatoria'
                    : 'Nueva versión disponible',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                maxLines: 2,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _VersionRow(
                label: 'Versión disponible',
                value: newVersion,
                highlight: true),
            const SizedBox(height: 6),
            _VersionRow(label: 'Versión actual', value: _version),
            const SizedBox(height: 16),
            Text(
              isObligatory
                  ? 'Esta actualización es obligatoria para continuar usando la aplicación.'
                  : 'Se recomienda actualizar para obtener las últimas mejoras.',
              style: TextStyle(
                color: isObligatory
                    ? Colors.orange.shade800
                    : AppTheme.textSecondary,
                fontSize: 13,
                fontWeight:
                    isObligatory ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          if (!isObligatory)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Más tarde'),
            ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Descargar'),
            onPressed: () async {
              final url = Uri.parse(UpdateService.downloadUrl);
              bool ok = false;
              try {
                ok = await launchUrl(url,
                    mode: LaunchMode.externalApplication);
              } catch (_) {}
              if (!ok) {
                try {
                  ok = await launchUrl(url);
                } catch (_) {}
              }
              if (ok && mounted) Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isObligatory ? Colors.orange : AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.info_outline, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Versión de la app',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 2),
                Text(
                  'v$_version (build $_build)',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
              ],
            ),
          ),
          _checking
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.primary),
                )
              : TextButton(
                  onPressed: _checkUpdates,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    foregroundColor: AppTheme.primary,
                  ),
                  child:
                      const Text('Verificar', style: TextStyle(fontSize: 13)),
                ),
        ],
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _VersionRow(
      {required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label: ',
            style:
                const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        Flexible(
          child: Text(value,
              style: TextStyle(
                fontSize: highlight ? 15 : 13,
                fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
                color: highlight ? AppTheme.primary : AppTheme.textPrimary,
              )),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppTheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
