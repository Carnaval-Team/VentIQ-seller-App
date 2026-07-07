import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/plan_suscripcion_widget.dart';

class DispatcherProfileScreen extends StatefulWidget {
  const DispatcherProfileScreen({super.key});

  @override
  State<DispatcherProfileScreen> createState() =>
      _DispatcherProfileScreenState();
}

class _DispatcherProfileScreenState extends State<DispatcherProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _empresaCtrl;
  late TextEditingController _rutCtrl;
  late TextEditingController _direccionCtrl;
  late TextEditingController _paisCtrl;
  late TextEditingController _provinciaCtrl;
  late TextEditingController _municipioCtrl;

  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    final p = context.read<AuthProvider>().driverProfile;
    _nameCtrl = TextEditingController(text: p?['name'] as String? ?? '');
    _phoneCtrl = TextEditingController(text: p?['telefono'] as String? ?? '');
    _emailCtrl = TextEditingController(text: p?['email'] as String? ?? '');
    _empresaCtrl =
        TextEditingController(text: p?['empresa_nombre'] as String? ?? '');
    _rutCtrl = TextEditingController(text: p?['empresa_rut'] as String? ?? '');
    _direccionCtrl =
        TextEditingController(text: p?['empresa_direccion'] as String? ?? '');
    _paisCtrl = TextEditingController(text: p?['pais'] as String? ?? '');
    _provinciaCtrl =
        TextEditingController(text: p?['province'] as String? ?? '');
    _municipioCtrl =
        TextEditingController(text: p?['municipality'] as String? ?? '');
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _empresaCtrl.dispose();
    _rutCtrl.dispose();
    _direccionCtrl.dispose();
    _paisCtrl.dispose();
    _provinciaCtrl.dispose();
    _municipioCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    await context.read<AuthProvider>().updateProfile({
      'name': _nameCtrl.text.trim(),
      'telefono': _phoneCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'empresa_nombre': _empresaCtrl.text.trim(),
      'empresa_rut': _rutCtrl.text.trim(),
      'empresa_direccion': _direccionCtrl.text.trim(),
      'pais': _paisCtrl.text.trim(),
      'province': _provinciaCtrl.text.trim(),
      'municipality': _municipioCtrl.text.trim(),
    });
    if (mounted) {
      setState(() {
        _isSaving = false;
        _isEditing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Perfil actualizado',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _cancelEdit() {
    final p = context.read<AuthProvider>().driverProfile;
    _nameCtrl.text = p?['name'] as String? ?? '';
    _phoneCtrl.text = p?['telefono'] as String? ?? '';
    _emailCtrl.text = p?['email'] as String? ?? '';
    _empresaCtrl.text = p?['empresa_nombre'] as String? ?? '';
    _rutCtrl.text = p?['empresa_rut'] as String? ?? '';
    _direccionCtrl.text = p?['empresa_direccion'] as String? ?? '';
    _paisCtrl.text = p?['pais'] as String? ?? '';
    _provinciaCtrl.text = p?['province'] as String? ?? '';
    _municipioCtrl.text = p?['municipality'] as String? ?? '';
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        title: Text('Mi Perfil',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, color: textPrimary)),
        iconTheme: IconThemeData(color: textPrimary),
        actions: [
          if (!_isEditing)
            TextButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: Icon(Icons.edit_outlined,
                  size: 18, color: AppTheme.primaryColor),
              label: Text('Editar',
                  style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w600)),
            )
          else ...[
            TextButton(
              onPressed: _isSaving ? null : _cancelEdit,
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar'),
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: isDark ? Colors.white54 : Colors.grey[500],
          indicatorColor: AppTheme.primaryColor,
          tabs: const [
            Tab(icon: Icon(Icons.person_outline), text: 'Perfil'),
            Tab(icon: Icon(Icons.workspace_premium_outlined), text: 'Mi Plan'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildPerfilTab(isDark, textPrimary),
          _buildPlanTab(isDark, textPrimary),
        ],
      ),
    );
  }

  Widget _buildPerfilTab(bool isDark, Color textPrimary) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final border = isDark ? AppTheme.darkBorder : Colors.grey[200]!;

    Widget field(String label, TextEditingController ctrl,
        {TextInputType? keyboard}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: ctrl,
          readOnly: !_isEditing,
          keyboardType: keyboard,
          style: TextStyle(color: textPrimary),
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: cardColor,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Datos personales',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700, color: textPrimary)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Column(
                children: [
                  field('Nombre', _nameCtrl),
                  field('Teléfono', _phoneCtrl, keyboard: TextInputType.phone),
                  field('Email', _emailCtrl, keyboard: TextInputType.emailAddress),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Empresa dispatcher',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700, color: textPrimary)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Column(
                children: [
                  field('Nombre legal', _empresaCtrl),
                  field('RUT / ID fiscal', _rutCtrl),
                  field('Dirección', _direccionCtrl),
                  field('País', _paisCtrl),
                  field('Provincia', _provinciaCtrl),
                  field('Municipio', _municipioCtrl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanTab(bool isDark, Color textPrimary) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suscripción y facturación',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Gestiona tu plan y solicita cambios con evidencia de pago.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          const PlanSuscripcionTile(),
        ],
      ),
    );
  }
}
