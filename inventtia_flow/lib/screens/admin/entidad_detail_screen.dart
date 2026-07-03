import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/entidad.dart';
import '../../models/perfil.dart';
import '../../models/servicio.dart';
import '../../providers/auth_provider.dart';
import '../../providers/entidad_provider.dart';
import '../../services/catalogo_service.dart';
import '../../services/auth_service.dart';
import '../../services/entidad_service.dart';
import '../../services/perfil_service.dart';
import 'gestion_locales_screen.dart';
import 'gestion_servicios_screen.dart';

class EntidadDetailScreen extends StatefulWidget {
  final Entidad entidad;
  const EntidadDetailScreen({super.key, required this.entidad});

  @override
  State<EntidadDetailScreen> createState() => _EntidadDetailScreenState();
}

class _EntidadDetailScreenState extends State<EntidadDetailScreen> {
  late Entidad _entidad;
  List<EntidadAdmin> _admins = [];
  List<EntidadVendedor> _vendedores = [];
  List<Local> _locales = [];
  List<Servicio> _servicios = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _entidad = widget.entidad;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        EntidadService.getAdmins(_entidad.id),
        CatalogoService.getLocalesByEntidad(_entidad.id),
        CatalogoService.getServiciosByEntidad(_entidad.id),
        EntidadService.getVendedores(_entidad.id),
      ]);
      _admins = results[0] as List<EntidadAdmin>;
      _locales = results[1] as List<Local>;
      _servicios = results[2] as List<Servicio>;
      _vendedores = results[3] as List<EntidadVendedor>;
    } catch (e) {
      print('[flow] EntidadDetailScreen _cargar ERROR: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  bool get _isOwner =>
      _entidad.isOwner(context.read<AuthProvider>().user?.id ?? '');

  void _editarEntidad() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditEntidadSheet(entidad: _entidad),
    ).then((_) async {
      final provider = context.read<EntidadProvider>();
      final updated = provider.misEntidades.firstWhere(
        (e) => e.id == _entidad.id,
        orElse: () => _entidad,
      );
      setState(() => _entidad = updated);
    });
  }

  Future<void> _agregarVendedor() async {
    final uuid = await _showAgregarUsuarioDialog('Agregar Vendedor');
    if (uuid != null) await _vincularMiembro(uuid, rol: 'vendedor');
  }

  Future<void> _agregarAdmin() async {
    final uuid = await _showAgregarUsuarioDialog('Agregar Administrador');
    if (uuid != null) await _vincularMiembro(uuid, rol: 'admin');
  }

  Future<void> _vincularMiembro(String uuid, {required String rol}) async {
    try {
      final perfil = await PerfilService.getPerfil(uuid);
      final myUuid = context.read<AuthProvider>().user!.id;
      if (rol == 'vendedor') {
        await EntidadService.addVendedor(
          idEntidad: _entidad.id,
          uuidUsuario: uuid,
          asignadoPor: myUuid,
        );
      } else {
        await EntidadService.addAdmin(
          idEntidad: _entidad.id,
          uuidUsuario: uuid,
          asignadoPor: myUuid,
        );
      }
      await _cargar();
      if (!mounted) return;
      final nombre = perfil?.nombreCompleto ?? uuid;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$nombre agregado como ${rol == 'vendedor' ? 'vendedor' : 'administrador'}'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      print('[flow] _vincularMiembro ERROR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al agregar ${rol == 'vendedor' ? 'vendedor' : 'administrador'}: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _quitarVendedor(EntidadVendedor vendedor) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar Vendedor'),
        content: const Text('¿Estás seguro de quitar a este vendedor?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await EntidadService.removeVendedor(vendedor.id);
      await _cargar();
    }
  }

  Future<String?> _showAgregarUsuarioDialog(String title) async {
    return showDialog<String?>(
      context: context,
      builder: (ctx) => _AgregarUsuarioDialog(title: title),
    );
  }

  Future<void> _quitarAdmin(EntidadAdmin admin) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar Administrador'),
        content:
            const Text('¿Estás seguro de quitar a este administrador?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await EntidadService.removeAdmin(admin.id);
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_entidad.denominacion),
        actions: [
          if (_isOwner)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: _editarEntidad,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Info de la entidad
                  _InfoCard(entidad: _entidad),
                  const SizedBox(height: 16),

                  // Gestión rápida
                  _SectionTitle('Gestión'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.store_outlined,
                          label: 'Locales',
                          count: _locales.length,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GestionLocalesScreen(
                                  entidad: _entidad),
                            ),
                          ).then((_) => _cargar()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.miscellaneous_services_outlined,
                          label: 'Servicios',
                          count: _servicios.length,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GestionServiciosScreen(
                                  entidad: _entidad),
                            ),
                          ).then((_) => _cargar()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Administradores
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SectionTitle('Administradores'),
                      if (_isOwner)
                        TextButton.icon(
                          onPressed: _agregarAdmin,
                          icon: const Icon(Icons.person_add_outlined,
                              size: 18),
                          label: const Text('Agregar'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Owner siempre aparece primero
                  _AdminTile(
                    label: 'Owner (tú)',
                    uuid: _entidad.ownerUuid,
                    isOwner: true,
                    canRemove: false,
                    onRemove: null,
                  ),
                  ..._admins.map((a) => _AdminTile(
                        label: 'Admin',
                        uuid: a.uuidUsuario,
                        email: a.email,
                        isOwner: false,
                        canRemove: _isOwner,
                        onRemove: () => _quitarAdmin(a),
                      )),
                  if (_admins.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Sin administradores adicionales',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Vendedores
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SectionTitle('Trabajadores'),
                      if (_isOwner)
                        TextButton.icon(
                          onPressed: _agregarVendedor,
                          icon: const Icon(Icons.person_add_outlined,
                              size: 18),
                          label: const Text('Agregar'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._vendedores.map((v) => _AdminTile(
                        label: 'Vendedor',
                        uuid: v.uuidUsuario,
                        email: v.email,
                        isOwner: false,
                        roleColor: const Color(0xFF34C759),
                        canRemove: _isOwner,
                        onRemove: () => _quitarVendedor(v),
                      )),
                  if (_vendedores.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Sin vendedores asignados',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Entidad entidad;
  const _InfoCard({required this.entidad});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.primary.withOpacity(0.1),
                  child: Text(
                    entidad.denominacion[0].toUpperCase(),
                    style: const TextStyle(
                        fontSize: 20,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entidad.denominacion,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (entidad.direccion != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(entidad.direccion!,
                        style: const TextStyle(
                            color: AppTheme.textSecondary)),
                  ),
                ],
              ),
            ],
            if (entidad.telefono != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.phone_outlined,
                      size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text(entidad.telefono!,
                      style: const TextStyle(
                          color: AppTheme.textSecondary)),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.timer_outlined,
                    size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text(
                  entidad.permiteCancelacionCliente
                      ? 'Cancelación permitida hasta ${entidad.horasAnticipacionCancelacion} horas antes'
                      : 'Cancelación por cliente deshabilitada',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary),
      );
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppTheme.primary, size: 28),
            const SizedBox(height: 8),
            Text(
              '$count',
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary),
            ),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final String label;
  final String uuid;
  final bool isOwner;
  final String? email;
  final Color? roleColor;
  final bool canRemove;
  final VoidCallback? onRemove;

  const _AdminTile({
    required this.label,
    required this.uuid,
    required this.isOwner,
    this.email,
    this.roleColor,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final color = isOwner
        ? AppTheme.primary
        : (roleColor ?? AppTheme.textSecondary);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.15),
        child: Icon(
          isOwner ? Icons.star : Icons.person_outline,
          color: color,
          size: 20,
        ),
      ),
      title: Text(
        isOwner ? 'Propietario' : label,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        email ?? '${uuid.substring(0, 8)}...',
        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
      ),
      trailing: canRemove
          ? IconButton(
              icon: const Icon(Icons.remove_circle_outline,
                  color: AppTheme.error),
              onPressed: onRemove,
            )
          : null,
    );
  }
}

class _AgregarUsuarioDialog extends StatefulWidget {
  final String title;
  const _AgregarUsuarioDialog({required this.title});

  @override
  State<_AgregarUsuarioDialog> createState() => _AgregarUsuarioDialogState();
}

class _AgregarUsuarioDialogState extends State<_AgregarUsuarioDialog> {
  int _tab = 0;
  bool _loading = false;
  String? _error;

  // Vincular existente
  final _emailBuscarCtrl = TextEditingController();
  Perfil? _encontrado;
  String? _uuidEncontrado;

  // Crear nuevo
  final _emailCrearCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _apellidosCtrl = TextEditingController();
  final _ciCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Future<void> _buscar() async {
    setState(() {
      _loading = true;
      _error = null;
      _encontrado = null;
      _uuidEncontrado = null;
    });
    try {
      final email = _emailBuscarCtrl.text.trim();
      final uuid = await PerfilService.getUuidByEmail(email);
      if (uuid == null) {
        setState(() => _error = 'No se encontró un usuario registrado con ese correo');
      } else {
        _uuidEncontrado = uuid;
        // Intentar obtener el perfil, pero permitir vincular igual si no existe.
        final perfil = await PerfilService.getPerfil(uuid);
        setState(() => _encontrado = perfil);
      }
    } catch (e) {
      setState(() => _error = 'Error al buscar: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _crear() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uuid = await AuthService.createUserFromAdmin(
        email: _emailCrearCtrl.text.trim(),
        password: _passCtrl.text,
        nombre: _nombreCtrl.text.trim(),
        apellidos: _apellidosCtrl.text.trim(),
        ci: _ciCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim().isEmpty
            ? null
            : _telefonoCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, uuid);
    } catch (e) {
      setState(() => _error = 'Error al crear usuario: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Vincular existente'),
                    selected: _tab == 0,
                    onSelected: (_) => setState(() => _tab = 0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Crear nuevo'),
                    selected: _tab == 1,
                    onSelected: (_) => setState(() => _tab = 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_tab == 0) ...[
              TextField(
                controller: _emailBuscarCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Correo del usuario',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _buscar,
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Buscar'),
                ),
              ),
              if (_uuidEncontrado != null) ...[
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(_encontrado?.nombreCompleto ?? _emailBuscarCtrl.text.trim()),
                  subtitle: _encontrado != null
                      ? Text(_emailBuscarCtrl.text.trim())
                      : const Text('Usuario sin perfil completo', style: TextStyle(fontStyle: FontStyle.italic)),
                ),
              ],
            ] else ...[
              Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _emailCrearCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) {
                        final email = v?.trim() ?? '';
                        if (!email.contains('@')) return 'Correo inválido';
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Contraseña temporal',
                        prefixIcon: Icon(Icons.lock_outlined),
                      ),
                      validator: (v) =>
                          (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _nombreCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _apellidosCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Apellidos',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _ciCtrl,
                      decoration: const InputDecoration(
                        labelText: 'CI',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _telefonoCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono (opcional)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: AppTheme.error, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        if (_tab == 0)
          ElevatedButton(
            onPressed: _uuidEncontrado == null || _loading
                ? null
                : () => Navigator.pop(context, _uuidEncontrado),
            child: _loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Vincular'),
          )
        else
          ElevatedButton(
            onPressed: _loading ? null : _crear,
            child: _loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Crear y vincular'),
          ),
      ],
    );
  }
}

class _EditEntidadSheet extends StatefulWidget {
  final Entidad entidad;
  const _EditEntidadSheet({required this.entidad});

  @override
  State<_EditEntidadSheet> createState() => _EditEntidadSheetState();
}

class _EditEntidadSheetState extends State<_EditEntidadSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _denomCtrl;
  late final TextEditingController _dirCtrl;
  late final TextEditingController _telCtrl;
  late final TextEditingController _horasCancelCtrl;

  @override
  void initState() {
    super.initState();
    _denomCtrl = TextEditingController(text: widget.entidad.denominacion);
    _dirCtrl = TextEditingController(text: widget.entidad.direccion ?? '');
    _telCtrl = TextEditingController(text: widget.entidad.telefono ?? '');
    _horasCancelCtrl = TextEditingController(
      text: widget.entidad.horasAnticipacionCancelacion.toString(),
    );
  }

  @override
  void dispose() {
    _denomCtrl.dispose();
    _dirCtrl.dispose();
    _telCtrl.dispose();
    _horasCancelCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final horas = int.tryParse(_horasCancelCtrl.text.trim()) ?? 0;
    final provider = context.read<EntidadProvider>();
    final ok = await provider.actualizarEntidad(
      id: widget.entidad.id,
      denominacion: _denomCtrl.text.trim(),
      direccion: _dirCtrl.text.trim().isEmpty ? null : _dirCtrl.text.trim(),
      telefono: _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
      horasAnticipacionCancelacion: horas,
    );
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
            const Text('Editar Entidad',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            const SizedBox(height: 12),
            TextFormField(
              controller: _horasCancelCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Horas de anticipación para cancelar',
                prefixIcon: Icon(Icons.timer_outlined),
                helperText: '0 = el cliente no puede cancelar',
              ),
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                if (n == null || n < 0) return 'Valor inválido';
                return null;
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: provider.isLoading ? null : _submit,
              child: provider.isLoading
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Guardar cambios',
                      style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
