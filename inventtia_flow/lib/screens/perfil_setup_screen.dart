import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../services/perfil_service.dart';

class PerfilSetupScreen extends StatefulWidget {
  const PerfilSetupScreen({super.key});

  @override
  State<PerfilSetupScreen> createState() => _PerfilSetupScreenState();
}

class _PerfilSetupScreenState extends State<PerfilSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _apellidosCtrl = TextEditingController();
  final _ciCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  bool _ciDuplicado = false;
  bool _checkingCi = false;

  @override
  void initState() {
    super.initState();
    final perfil = context.read<AuthProvider>().perfil;
    if (perfil != null) {
      _nombreCtrl.text = perfil.nombre;
      _apellidosCtrl.text = perfil.apellidos;
      _ciCtrl.text = perfil.ci;
      _telefonoCtrl.text = perfil.telefono ?? '';
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _apellidosCtrl.dispose();
    _ciCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkCiDuplicado(String ci) async {
    if (ci.length != 11) return;
    final uuid = AuthService.currentUserId;
    setState(() => _checkingCi = true);
    try {
      final existe = await PerfilService.existeCi(ci, excludeUuid: uuid);
      if (mounted) {
        setState(() {
          _ciDuplicado = existe;
          _checkingCi = false;
        });
        _formKey.currentState?.validate();
      }
    } catch (e) {
      // Si el schema no está expuesto u otro error de red, no bloqueamos
      // la UI — la validación server-side en _submit lo detectará
      if (mounted) setState(() => _checkingCi = false);
    }
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final isEdit = auth.hasPerfil;

    final ci = _ciCtrl.text.trim();

    if (!isEdit) {
      // Solo validar CI duplicado en modo creación
      if (_ciDuplicado) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este carnet de identidad ya está registrado por otro usuario.'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }
      if (!_formKey.currentState!.validate()) return;

      // Doble verificación server-side antes de guardar
      final uuid = await AuthService.getCurrentUserId();
      if (uuid == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo obtener el usuario autenticado'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        return;
      }
      setState(() => _checkingCi = true);
      bool existe = false;
      try {
        existe = await PerfilService.existeCi(ci, excludeUuid: uuid);
      } catch (_) {}
      setState(() => _checkingCi = false);
      if (!mounted) return;
      if (existe) {
        setState(() => _ciDuplicado = true);
        _formKey.currentState?.validate();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este carnet de identidad ya está registrado por otro usuario.'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }
    } else {
      if (!_formKey.currentState!.validate()) return;
    }
    final ok = await auth.savePerfil(
      nombre: _nombreCtrl.text.trim(),
      apellidos: _apellidosCtrl.text.trim(),
      ci: ci,
      telefono: _telefonoCtrl.text.trim().isEmpty
          ? null
          : _telefonoCtrl.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Error al guardar el perfil'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isEdit = auth.hasPerfil;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(isEdit ? 'Editar Perfil' : 'Completa tu Perfil'),
        automaticallyImplyLeading: isEdit,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isEdit) ...[
                const SizedBox(height: 16),
                const Text(
                  'Completa tu perfil',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Estos datos son necesarios para usar la app',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 24),
              ],
              // Avatar placeholder
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: AppTheme.primary.withOpacity(0.1),
                      child: const Icon(Icons.person,
                          size: 48, color: AppTheme.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nombreCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        prefixIcon: Icon(Icons.person_outlined),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _apellidosCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Apellidos',
                        prefixIcon: Icon(Icons.person_outlined),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 16),
                    if (isEdit)
                      // En edición: CI de solo lectura
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Carnet de Identidad',
                          prefixIcon: const Icon(Icons.badge_outlined),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: const OutlineInputBorder(),
                          suffixIcon: Tooltip(
                            message: 'El CI no puede modificarse',
                            child: Icon(Icons.lock_outline,
                                size: 18,
                                color: AppTheme.textSecondary.withOpacity(0.5)),
                          ),
                        ),
                        child: Text(
                          _ciCtrl.text,
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 15),
                        ),
                      )
                    else
                      TextFormField(
                        controller: _ciCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 11,
                        onChanged: (v) {
                          if (_ciDuplicado) setState(() => _ciDuplicado = false);
                          if (v.trim().length == 11) _checkCiDuplicado(v.trim());
                        },
                        decoration: InputDecoration(
                          labelText: 'Carnet de Identidad (11 dígitos)',
                          prefixIcon: const Icon(Icons.badge_outlined),
                          counterText: '',
                          suffixIcon: _checkingCi
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : _ciDuplicado
                                  ? const Icon(Icons.error, color: AppTheme.error)
                                  : _ciCtrl.text.length == 11
                                      ? const Icon(Icons.check_circle,
                                          color: AppTheme.success)
                                      : null,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Requerido';
                          if (v.trim().length != 11) return 'Debe tener 11 dígitos';
                          if (!RegExp(r'^\d+$').hasMatch(v.trim()))
                            return 'Solo números';
                          if (_ciDuplicado)
                            return 'Este CI ya está registrado por otro usuario';
                          return null;
                        },
                      ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _telefonoCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono (opcional)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: auth.isLoading ? null : _submit,
                        child: auth.isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                isEdit ? 'Guardar Cambios' : 'Continuar',
                                style: const TextStyle(fontSize: 16),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
