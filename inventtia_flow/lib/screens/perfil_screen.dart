import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/entidad.dart';
import '../providers/auth_provider.dart';
import '../providers/entidad_provider.dart';
import '../widgets/notificaciones_bell.dart';
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
      context.read<EntidadProvider>().limpiar();
      await context.read<AuthProvider>().signOut();
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final entidadProv = context.watch<EntidadProvider>();
    final perfil = auth.perfil;
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12, left: 4),
            child: NotificacionesBell(color: Colors.white),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Avatar y nombre ──────────────────────────────
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundColor: AppTheme.primary.withOpacity(0.1),
                    child: Text(
                      perfil != null
                          ? perfil.nombre[0].toUpperCase()
                          : (user?.email?[0].toUpperCase() ?? 'U'),
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    perfil?.nombreCompleto ?? 'Sin nombre',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.email ?? '',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Datos del perfil ─────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Datos Personales',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary)),
                    const SizedBox(height: 16),
                    _InfoRow(icon: Icons.person_outlined, label: 'Nombre', value: perfil?.nombre ?? '-'),
                    const Divider(height: 20),
                    _InfoRow(icon: Icons.person_outlined, label: 'Apellidos', value: perfil?.apellidos ?? '-'),
                    const Divider(height: 20),
                    _InfoRow(icon: Icons.badge_outlined, label: 'CI', value: perfil?.ci ?? '-'),
                    const Divider(height: 20),
                    _InfoRow(icon: Icons.phone_outlined, label: 'Teléfono', value: perfil?.telefono ?? '-'),
                    const Divider(height: 20),
                    _InfoRow(icon: Icons.email_outlined, label: 'Correo', value: user?.email ?? '-'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Sección Entidad ───────────────────────────────
            if (entidadProv.isAdmin)
              _EntidadAdminSection(provider: entidadProv)
            else
              _EntidadRegisterBanner(ownerUuid: user?.id ?? ''),
            const SizedBox(height: 16),

            // ── Acciones generales ───────────────────────────
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.edit_outlined, color: AppTheme.primary),
                    title: const Text('Editar Perfil'),
                    trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PerfilSetupScreen())),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined, color: AppTheme.primary),
                    title: const Text('Notificaciones'),
                    trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                    onTap: () => Navigator.pushNamed(context, '/notificaciones'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Cerrar sesión ────────────────────────────────
            OutlinedButton.icon(
              onPressed: () => _signOut(context),
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar Sesión'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                side: const BorderSide(color: AppTheme.error),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
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
          colors: [AppTheme.primary.withOpacity(0.08), AppTheme.accent.withOpacity(0.06)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.business_outlined, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('¿Tienes una organización?',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
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
    final myUuid = context.read<AuthProvider>().user?.id ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cabecera con selector
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Mis Entidades',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary)),
            TextButton.icon(
              onPressed: () => _nuevaEntidad(context, myUuid),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nueva', style: TextStyle(fontSize: 13)),
            ),
          ],
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
                        color: isSelected ? Colors.white : AppTheme.textPrimary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                selected: isSelected,
                selectedColor: AppTheme.primary,
                backgroundColor: Colors.grey.shade100,
                onSelected: (_) => provider.seleccionarEntidad(e),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              );
            },
          ),
        ),
        const SizedBox(height: 12),

        // Card de la entidad seleccionada con accesos rápidos
        if (seleccionada != null)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppTheme.primary.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                // Info + botón detalle
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primary.withOpacity(0.1),
                    child: Text(seleccionada.denominacion[0].toUpperCase(),
                        style: const TextStyle(
                            color: AppTheme.primary, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(seleccionada.denominacion,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
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
                    child: const Text('Ver detalle'),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                // Accesos rápidos
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      _QuickAction(
                        icon: Icons.store_outlined,
                        label: 'Locales',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  GestionLocalesScreen(entidad: seleccionada)),
                        ),
                      ),
                      _QuickAction(
                        icon: Icons.miscellaneous_services_outlined,
                        label: 'Servicios',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  GestionServiciosScreen(entidad: seleccionada)),
                        ),
                      ),
                      _QuickAction(
                        icon: Icons.people_alt_outlined,
                        label: 'Admins',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  EntidadDetailScreen(entidad: seleccionada)),
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
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Icon(icon, size: 22, color: AppTheme.primary),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
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
        left: 24, right: 24, top: 24,
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
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
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
                      height: 20, width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Crear Entidad', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
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
        Icon(icon, size: 18, color: AppTheme.textSecondary),
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
                      fontSize: 14, color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}
