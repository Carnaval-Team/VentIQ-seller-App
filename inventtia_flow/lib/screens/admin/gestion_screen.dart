import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/entidad.dart';
import '../../providers/auth_provider.dart';
import '../../providers/entidad_provider.dart';
import 'entidad_detail_screen.dart';
import 'gestion_locales_screen.dart';
import 'gestion_servicios_screen.dart';
import 'mis_entidades_screen.dart';
import 'planificacion_screen.dart';
import 'reservas_screen.dart';

class GestionScreen extends StatelessWidget {
  const GestionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final entidadProv = context.watch<EntidadProvider>();
    final myUuid = context.read<AuthProvider>().user?.id ?? '';
    final seleccionada = entidadProv.entidadSeleccionada;

    if (entidadProv.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!entidadProv.isAdmin || seleccionada == null) {
      return const Scaffold(
        body: Center(
          child: Text('Sin entidades disponibles',
              style: TextStyle(color: AppTheme.textSecondary)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: _EntidadSelector(
          entidades: entidadProv.misEntidades,
          seleccionada: seleccionada,
          onChanged: entidadProv.seleccionarEntidad,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_business_outlined),
            tooltip: 'Nueva entidad',
            onPressed: () => _nuevaEntidad(context, myUuid),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configurar entidad',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => EntidadDetailScreen(entidad: seleccionada)),
            ),
          ),
        ],
      ),
      body: _GestionBody(entidad: seleccionada, myUuid: myUuid),
    );
  }

  void _nuevaEntidad(BuildContext context, String ownerUuid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _NuevaEntidadInlineSheet(ownerUuid: ownerUuid),
    );
  }
}

// ── Selector de entidad en la AppBar ──────────────────────────
class _EntidadSelector extends StatelessWidget {
  final List<Entidad> entidades;
  final Entidad seleccionada;
  final ValueChanged<Entidad> onChanged;

  const _EntidadSelector({
    required this.entidades,
    required this.seleccionada,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (entidades.length == 1) {
      return Text(
        seleccionada.denominacion,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      );
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: seleccionada.id,
        icon: const Icon(Icons.expand_more, color: AppTheme.textPrimary),
        style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary),
        onChanged: (id) {
          if (id == null) return;
          final e = entidades.firstWhere((e) => e.id == id);
          onChanged(e);
        },
        items: entidades
            .map((e) => DropdownMenuItem(
                  value: e.id,
                  child: Text(e.denominacion,
                      overflow: TextOverflow.ellipsis),
                ))
            .toList(),
      ),
    );
  }
}

// ── Cuerpo principal de gestión ───────────────────────────────
class _GestionBody extends StatelessWidget {
  final Entidad entidad;
  final String myUuid;

  const _GestionBody({required this.entidad, required this.myUuid});

  @override
  Widget build(BuildContext context) {
    final isOwner = entidad.isOwner(myUuid);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info de la entidad
          _EntidadInfoCard(entidad: entidad, isOwner: isOwner),
          const SizedBox(height: 24),

          const Text('Gestión',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.8)),
          const SizedBox(height: 12),

          // Grid de módulos — columnas adaptativas según ancho disponible
          LayoutBuilder(
            builder: (context, constraints) {
              // 1 col < 300px | 2 col < 500px | 3 col < 750px | 4 col+
              final w = constraints.maxWidth;
              final cols = w < 300 ? 1 : w < 500 ? 2 : w < 750 ? 3 : 4;
              final modulos = [
                _ModuloCard(
                  icon: Icons.store_outlined,
                  title: 'Locales',
                  subtitle: 'Puntos de atención',
                  color: const Color(0xFF4F7FFA),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => GestionLocalesScreen(entidad: entidad))),
                ),
                _ModuloCard(
                  icon: Icons.miscellaneous_services_outlined,
                  title: 'Servicios',
                  subtitle: 'Catálogo de servicios',
                  color: const Color(0xFF7C5CFC),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => GestionServiciosScreen(entidad: entidad))),
                ),
                _ModuloCard(
                  icon: Icons.account_tree_outlined,
                  title: 'Planificación',
                  subtitle: 'Servicios por local',
                  color: const Color(0xFF34C759),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => PlanificacionScreen(entidad: entidad))),
                ),
                _ModuloCard(
                  icon: Icons.confirmation_number_outlined,
                  title: 'Reservas',
                  subtitle: 'Consultar y exportar',
                  color: const Color(0xFF5856D6),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ReservasScreen(entidad: entidad))),
                ),
                _ModuloCard(
                  icon: Icons.people_alt_outlined,
                  title: 'Admins',
                  subtitle: 'Gestionar accesos',
                  color: const Color(0xFFFF9500),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => EntidadDetailScreen(entidad: entidad))),
                ),
              ];
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.4,
                ),
                itemCount: modulos.length,
                itemBuilder: (_, i) => modulos[i],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EntidadInfoCard extends StatelessWidget {
  final Entidad entidad;
  final bool isOwner;

  const _EntidadInfoCard({required this.entidad, required this.isOwner});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppTheme.primary.withOpacity(0.1),
            child: Text(
              entidad.denominacion[0].toUpperCase(),
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entidad.denominacion,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                if (entidad.direccion != null)
                  Text(entidad.direccion!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                if (entidad.telefono != null)
                  Text(entidad.telefono!,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isOwner
                  ? AppTheme.primary.withOpacity(0.1)
                  : AppTheme.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isOwner ? 'Owner' : 'Admin',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isOwner ? AppTheme.primary : AppTheme.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuloCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModuloCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sheet inline nueva entidad (desde GestionScreen) ─────────
class _NuevaEntidadInlineSheet extends StatefulWidget {
  final String ownerUuid;
  const _NuevaEntidadInlineSheet({required this.ownerUuid});

  @override
  State<_NuevaEntidadInlineSheet> createState() =>
      _NuevaEntidadInlineSheetState();
}

class _NuevaEntidadInlineSheetState
    extends State<_NuevaEntidadInlineSheet> {
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
      direccion:
          _dirCtrl.text.trim().isEmpty ? null : _dirCtrl.text.trim(),
      telefono:
          _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
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
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Serás el propietario (owner) de esta entidad.',
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
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
