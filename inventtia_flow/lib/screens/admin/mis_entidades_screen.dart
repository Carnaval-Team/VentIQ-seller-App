import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/entidad.dart';
import '../../providers/auth_provider.dart';
import '../../providers/entidad_provider.dart';
import '../../services/auth_service.dart';
import 'entidad_detail_screen.dart';

class MisEntidadesScreen extends StatefulWidget {
  const MisEntidadesScreen({super.key});

  @override
  State<MisEntidadesScreen> createState() => _MisEntidadesScreenState();
}

class _MisEntidadesScreenState extends State<MisEntidadesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    final uuid = AuthService.currentUserId;
    if (uuid != null) {
      await context.read<EntidadProvider>().cargarMisEntidades(uuid);
    }
  }

  void _nuevaEntidad() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _EntidadFormSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EntidadProvider>();
    final myUuid = AuthService.currentUserId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Entidades'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargar,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevaEntidad,
        icon: const Icon(Icons.add),
        label: const Text('Nueva Entidad'),
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.misEntidades.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.business_outlined,
                          size: 72, color: AppTheme.primary.withOpacity(0.3)),
                      const SizedBox(height: 16),
                      const Text(
                        'Aún no tienes entidades',
                        style: TextStyle(
                            fontSize: 16, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Crea una para gestionar tus locales y servicios',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: provider.misEntidades.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final e = provider.misEntidades[i];
                      final isOwner = e.isOwner(myUuid);
                      return _EntidadTile(
                        entidad: e,
                        isOwner: isOwner,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EntidadDetailScreen(entidad: e),
                          ),
                        ).then((_) => _cargar()),
                      );
                    },
                  ),
                ),
    );
  }
}

class _EntidadTile extends StatelessWidget {
  final Entidad entidad;
  final bool isOwner;
  final VoidCallback onTap;

  const _EntidadTile({
    required this.entidad,
    required this.isOwner,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withOpacity(0.1),
          child: Text(
            entidad.denominacion[0].toUpperCase(),
            style: const TextStyle(
                color: AppTheme.primary, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(entidad.denominacion,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOwner)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Owner',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600)),
              )
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Admin',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w600)),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _EntidadFormSheet extends StatefulWidget {
  final Entidad? entidad;
  const _EntidadFormSheet({this.entidad});

  @override
  State<_EntidadFormSheet> createState() => _EntidadFormSheetState();
}

class _EntidadFormSheetState extends State<_EntidadFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _denomCtrl;
  late final TextEditingController _dirCtrl;
  late final TextEditingController _telCtrl;

  @override
  void initState() {
    super.initState();
    _denomCtrl =
        TextEditingController(text: widget.entidad?.denominacion ?? '');
    _dirCtrl = TextEditingController(text: widget.entidad?.direccion ?? '');
    _telCtrl = TextEditingController(text: widget.entidad?.telefono ?? '');
  }

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
    final uuid = context.read<AuthProvider>().user!.id;

    bool ok;
    if (widget.entidad == null) {
      final result = await provider.crearEntidad(
        denominacion: _denomCtrl.text.trim(),
        direccion: _dirCtrl.text.trim().isEmpty ? null : _dirCtrl.text.trim(),
        telefono: _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        ownerUuid: uuid,
      );
      ok = result != null;
    } else {
      ok = await provider.actualizarEntidad(
        id: widget.entidad!.id,
        denominacion: _denomCtrl.text.trim(),
        direccion: _dirCtrl.text.trim().isEmpty ? null : _dirCtrl.text.trim(),
        telefono: _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
      );
    }

    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Error al guardar'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.entidad != null;
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
            Text(
              isEdit ? 'Editar Entidad' : 'Nueva Entidad',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _denomCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Denominación *',
                prefixIcon: Icon(Icons.business),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dirCtrl,
              decoration: const InputDecoration(
                labelText: 'Dirección',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono de contacto',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: provider.isLoading ? null : _submit,
              child: provider.isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : Text(isEdit ? 'Guardar cambios' : 'Crear Entidad',
                      style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
