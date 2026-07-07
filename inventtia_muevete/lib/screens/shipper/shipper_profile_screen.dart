import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/plan_suscripcion_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Nomencladores universales
// ─────────────────────────────────────────────────────────────────────────────

const _tiposOrganizacion = <String, String>{
  'empresa_privada':  'Empresa Privada',
  'empresa_estatal':  'Empresa Estatal / Pública',
  'autonomo':         'Autónomo / Cuenta Propia',
  'cooperativa':      'Cooperativa',
  'ong':              'ONG / Fundación',
  'otro':             'Otro',
};

// Adaptive labels for fiscal-id and activity-code per country ISO code.
// Defaults apply when country is not in the map.
const _fiscalIdLabel = <String, String>{
  'CU': 'NIF',
  'ES': 'NIF / CIF',
  'US': 'EIN / TIN',
  'MX': 'RFC',
};

const _actividadLabel = <String, String>{
  'CU': 'Código CNAE',
  'ES': 'Código CNAE',
  'US': 'Código NAICS',
  'MX': 'Código SCIAN / CIIU',
};

String _labelFiscal(String? iso) =>
    _fiscalIdLabel[iso?.toUpperCase()] ?? 'Identificador Fiscal';

String _labelActividad(String? iso) =>
    _actividadLabel[iso?.toUpperCase()] ?? 'Código de Actividad Económica';

// ─────────────────────────────────────────────────────────────────────────────

class ShipperProfileScreen extends StatefulWidget {
  const ShipperProfileScreen({super.key});

  @override
  State<ShipperProfileScreen> createState() => _ShipperProfileScreenState();
}

class _ShipperProfileScreenState extends State<ShipperProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _personalFormKey = GlobalKey<FormState>();
  final _entityFormKey = GlobalKey<FormState>();

  // Personal
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _ciCtrl;
  late TextEditingController _paisCtrl;
  late TextEditingController _provinciaCtrl;
  late TextEditingController _municipioCtrl;
  late TextEditingController _direccionCtrl;

  // Entidad (universal)
  String? _tipoOrg;
  late TextEditingController _nombreLegalCtrl;
  late TextEditingController _idFiscalCtrl;
  late TextEditingController _codActividadCtrl;
  late TextEditingController _paisEmpCtrl;
  late TextEditingController _regionEmpCtrl;
  late TextEditingController _ciudadEmpCtrl;
  late TextEditingController _direccionEmpCtrl;
  late TextEditingController _telefonoEmpCtrl;
  late TextEditingController _emailEmpCtrl;

  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final p = context.read<AuthProvider>().userProfile;
    _nameCtrl = TextEditingController(text: p?['name'] as String? ?? '');
    _phoneCtrl = TextEditingController(text: p?['phone'] as String? ?? '');
    _emailCtrl = TextEditingController(text: p?['email'] as String? ?? '');
    _ciCtrl = TextEditingController(text: p?['ci'] as String? ?? '');
    _paisCtrl = TextEditingController(text: p?['pais'] as String? ?? '');
    _provinciaCtrl =
        TextEditingController(text: p?['province'] as String? ?? '');
    _municipioCtrl =
        TextEditingController(text: p?['municipality'] as String? ?? '');
    _direccionCtrl =
        TextEditingController(text: p?['direccion'] as String? ?? '');

    _tipoOrg = p?['tipo_organizacion'] as String?;
    _nombreLegalCtrl =
        TextEditingController(text: p?['nombre_legal'] as String? ?? '');
    _idFiscalCtrl =
        TextEditingController(text: p?['id_fiscal'] as String? ?? '');
    _codActividadCtrl =
        TextEditingController(text: p?['cod_actividad'] as String? ?? '');
    _paisEmpCtrl =
        TextEditingController(text: p?['pais_empresa'] as String? ?? '');
    _regionEmpCtrl =
        TextEditingController(text: p?['region_empresa'] as String? ?? '');
    _ciudadEmpCtrl =
        TextEditingController(text: p?['ciudad_empresa'] as String? ?? '');
    _direccionEmpCtrl =
        TextEditingController(text: p?['direccion_empresa'] as String? ?? '');
    _telefonoEmpCtrl =
        TextEditingController(text: p?['telefono_empresa'] as String? ?? '');
    _emailEmpCtrl =
        TextEditingController(text: p?['email_empresa'] as String? ?? '');
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _ciCtrl.dispose();
    _paisCtrl.dispose();
    _provinciaCtrl.dispose();
    _municipioCtrl.dispose();
    _direccionCtrl.dispose();
    _nombreLegalCtrl.dispose();
    _idFiscalCtrl.dispose();
    _codActividadCtrl.dispose();
    _paisEmpCtrl.dispose();
    _regionEmpCtrl.dispose();
    _ciudadEmpCtrl.dispose();
    _direccionEmpCtrl.dispose();
    _telefonoEmpCtrl.dispose();
    _emailEmpCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final personalValid = _personalFormKey.currentState?.validate() ?? true;
    final entityValid = _entityFormKey.currentState?.validate() ?? true;
    if (!personalValid || !entityValid) return;

    setState(() => _isSaving = true);
    await context.read<AuthProvider>().updateProfile({
      'name': _nameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'ci': _ciCtrl.text.trim(),
      'pais': _paisCtrl.text.trim(),
      'province': _provinciaCtrl.text.trim(),
      'municipality': _municipioCtrl.text.trim(),
      'direccion': _direccionCtrl.text.trim(),
      if (_tipoOrg != null) 'tipo_organizacion': _tipoOrg,
      'nombre_legal': _nombreLegalCtrl.text.trim(),
      'id_fiscal': _idFiscalCtrl.text.trim(),
      'cod_actividad': _codActividadCtrl.text.trim(),
      'pais_empresa': _paisEmpCtrl.text.trim(),
      'region_empresa': _regionEmpCtrl.text.trim(),
      'ciudad_empresa': _ciudadEmpCtrl.text.trim(),
      'direccion_empresa': _direccionEmpCtrl.text.trim(),
      'telefono_empresa': _telefonoEmpCtrl.text.trim(),
      'email_empresa': _emailEmpCtrl.text.trim(),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  void _cancelEdit() {
    final p = context.read<AuthProvider>().userProfile;
    _nameCtrl.text = p?['name'] as String? ?? '';
    _phoneCtrl.text = p?['phone'] as String? ?? '';
    _ciCtrl.text = p?['ci'] as String? ?? '';
    _paisCtrl.text = p?['pais'] as String? ?? '';
    _provinciaCtrl.text = p?['province'] as String? ?? '';
    _municipioCtrl.text = p?['municipality'] as String? ?? '';
    _direccionCtrl.text = p?['direccion'] as String? ?? '';
    _tipoOrg = p?['tipo_organizacion'] as String?;
    _nombreLegalCtrl.text = p?['nombre_legal'] as String? ?? '';
    _idFiscalCtrl.text = p?['id_fiscal'] as String? ?? '';
    _codActividadCtrl.text = p?['cod_actividad'] as String? ?? '';
    _paisEmpCtrl.text = p?['pais_empresa'] as String? ?? '';
    _regionEmpCtrl.text = p?['region_empresa'] as String? ?? '';
    _ciudadEmpCtrl.text = p?['ciudad_empresa'] as String? ?? '';
    _direccionEmpCtrl.text = p?['direccion_empresa'] as String? ?? '';
    _telefonoEmpCtrl.text = p?['telefono_empresa'] as String? ?? '';
    _emailEmpCtrl.text = p?['email_empresa'] as String? ?? '';
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final profile = context.watch<AuthProvider>().userProfile;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;

    final nameDisplay =
        (profile?['name'] as String? ?? '').isNotEmpty
            ? profile!['name'] as String
            : 'Shipper';

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
              child: Text('Cancelar',
                  style: GoogleFonts.plusJakartaSans(
                      color: isDark ? Colors.white54 : Colors.grey,
                      fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.primaryColor))
                  : Text('Guardar',
                      style: GoogleFonts.plusJakartaSans(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w700)),
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: isDark ? Colors.white54 : Colors.grey[500],
          indicatorColor: AppTheme.primaryColor,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.person_outline), text: 'Personal'),
            Tab(icon: Icon(Icons.business_outlined), text: 'Empresa'),
            Tab(icon: Icon(Icons.workspace_premium_outlined), text: 'Mi Plan'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _PersonalTab(
            formKey: _personalFormKey,
            isDark: isDark,
            isEditing: _isEditing,
            nameCtrl: _nameCtrl,
            phoneCtrl: _phoneCtrl,
            emailCtrl: _emailCtrl,
            ciCtrl: _ciCtrl,
            paisCtrl: _paisCtrl,
            provinciaCtrl: _provinciaCtrl,
            municipioCtrl: _municipioCtrl,
            direccionCtrl: _direccionCtrl,
            nameDisplay: nameDisplay,
          ),
          _EntityTab(
            formKey: _entityFormKey,
            isDark: isDark,
            isEditing: _isEditing,
            tipoOrg: _tipoOrg,
            onTipoOrgChanged: (v) => setState(() => _tipoOrg = v),
            nombreLegalCtrl: _nombreLegalCtrl,
            idFiscalCtrl: _idFiscalCtrl,
            codActividadCtrl: _codActividadCtrl,
            paisEmpCtrl: _paisEmpCtrl,
            regionEmpCtrl: _regionEmpCtrl,
            ciudadEmpCtrl: _ciudadEmpCtrl,
            direccionEmpCtrl: _direccionEmpCtrl,
            telefonoEmpCtrl: _telefonoEmpCtrl,
            emailEmpCtrl: _emailEmpCtrl,
          ),
          const _PlanTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Personal
// ─────────────────────────────────────────────────────────────────────────────

class _PersonalTab extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final bool isDark;
  final bool isEditing;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController ciCtrl;
  final TextEditingController paisCtrl;
  final TextEditingController provinciaCtrl;
  final TextEditingController municipioCtrl;
  final TextEditingController direccionCtrl;
  final String nameDisplay;

  const _PersonalTab({
    required this.formKey,
    required this.isDark,
    required this.isEditing,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.emailCtrl,
    required this.ciCtrl,
    required this.paisCtrl,
    required this.provinciaCtrl,
    required this.municipioCtrl,
    required this.direccionCtrl,
    required this.nameDisplay,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Center(
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  border: Border.all(color: AppTheme.primaryColor, width: 3),
                ),
                child: Center(
                  child: Text(
                    nameDisplay.isNotEmpty
                        ? nameDisplay[0].toUpperCase()
                        : 'S',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _SectionHeader(label: 'Datos personales', isDark: isDark),
            const SizedBox(height: 12),
            _ProfileField(
              controller: nameCtrl,
              label: 'Nombre completo',
              icon: Icons.person_outline,
              isDark: isDark,
              enabled: isEditing,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: phoneCtrl,
              label: 'Teléfono',
              icon: Icons.phone_outlined,
              isDark: isDark,
              enabled: isEditing,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: emailCtrl,
              label: 'Correo electrónico',
              icon: Icons.email_outlined,
              isDark: isDark,
              enabled: false,
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: ciCtrl,
              label: 'Carné de identidad',
              icon: Icons.badge_outlined,
              isDark: isDark,
              enabled: isEditing,
            ),
            const SizedBox(height: 20),
            _SectionHeader(label: 'Ubicación personal', isDark: isDark),
            const SizedBox(height: 12),
            _ProfileField(
              controller: paisCtrl,
              label: 'País',
              icon: Icons.public_outlined,
              isDark: isDark,
              enabled: isEditing,
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: provinciaCtrl,
              label: 'Provincia',
              icon: Icons.location_city_outlined,
              isDark: isDark,
              enabled: isEditing,
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: municipioCtrl,
              label: 'Municipio',
              icon: Icons.map_outlined,
              isDark: isDark,
              enabled: isEditing,
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: direccionCtrl,
              label: 'Dirección',
              icon: Icons.home_outlined,
              isDark: isDark,
              enabled: isEditing,
              maxLines: 2,
            ),
            const SizedBox(height: 32),
            if (!isEditing)
              Center(
                child: Text(
                  'Toca "Editar" para modificar tus datos',
                  style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.grey[400],
                      fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Empresa / Entidad Económica
// ─────────────────────────────────────────────────────────────────────────────

class _EntityTab extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final bool isDark;
  final bool isEditing;
  final String? tipoOrg;
  final ValueChanged<String?> onTipoOrgChanged;
  final TextEditingController nombreLegalCtrl;
  final TextEditingController idFiscalCtrl;
  final TextEditingController codActividadCtrl;
  final TextEditingController paisEmpCtrl;
  final TextEditingController regionEmpCtrl;
  final TextEditingController ciudadEmpCtrl;
  final TextEditingController direccionEmpCtrl;
  final TextEditingController telefonoEmpCtrl;
  final TextEditingController emailEmpCtrl;

  const _EntityTab({
    required this.formKey,
    required this.isDark,
    required this.isEditing,
    required this.tipoOrg,
    required this.onTipoOrgChanged,
    required this.nombreLegalCtrl,
    required this.idFiscalCtrl,
    required this.codActividadCtrl,
    required this.paisEmpCtrl,
    required this.regionEmpCtrl,
    required this.ciudadEmpCtrl,
    required this.direccionEmpCtrl,
    required this.telefonoEmpCtrl,
    required this.emailEmpCtrl,
  });

  @override
  State<_EntityTab> createState() => _EntityTabState();
}

class _EntityTabState extends State<_EntityTab> {
  @override
  void initState() {
    super.initState();
    widget.paisEmpCtrl.addListener(_onPaisChanged);
  }

  @override
  void dispose() {
    widget.paisEmpCtrl.removeListener(_onPaisChanged);
    super.dispose();
  }

  void _onPaisChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final isEditing = widget.isEditing;
    final tipoOrg = widget.tipoOrg;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary = isDark ? Colors.white60 : Colors.grey[600]!;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;

    // Determine adaptive labels from the current pais_empresa value
    final paisIso = widget.paisEmpCtrl.text.trim();
    final fiscalLabel = _labelFiscal(paisIso.isNotEmpty ? paisIso : null);
    final actividadLabel = _labelActividad(paisIso.isNotEmpty ? paisIso : null);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: widget.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: AppTheme.primaryColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Completa los datos de la entidad. Los campos de identificación fiscal y actividad económica se adaptan al país seleccionado.',
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.grey[700]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── 1. Tipo de organización ──────────────────────────────────────
            _SectionHeader(label: '1. Tipo de organización', isDark: isDark),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isDark ? AppTheme.darkBorder : Colors.grey[300]!),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: tipoOrg,
                  isExpanded: true,
                  hint: Text('Seleccionar tipo de organización',
                      style: TextStyle(color: textSecondary, fontSize: 14)),
                  dropdownColor: cardColor,
                  style: TextStyle(color: textPrimary, fontSize: 14),
                  onChanged: isEditing ? widget.onTipoOrgChanged : null,
                  items: _tiposOrganizacion.entries.map((e) {
                    return DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value,
                          style: TextStyle(
                              color: textPrimary, fontSize: 14)),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── 2. Nombre legal ──────────────────────────────────────────────
            _ProfileField(
              controller: widget.nombreLegalCtrl,
              label: '2. Nombre legal de la empresa',
              icon: Icons.business_outlined,
              isDark: isDark,
              enabled: isEditing,
            ),
            const SizedBox(height: 12),

            // ── 5. País (before 3 & 4 so labels can adapt) ──────────────────
            _ProfileField(
              controller: widget.paisEmpCtrl,
              label: '5. País (ej: CU, US, ES, MX)',
              icon: Icons.public_outlined,
              isDark: isDark,
              enabled: isEditing,
            ),
            const SizedBox(height: 12),

            // ── 3. Identificador fiscal (label adapts to country) ────────────
            _ProfileField(
              controller: widget.idFiscalCtrl,
              label: '3. $fiscalLabel',
              icon: Icons.numbers_outlined,
              isDark: isDark,
              enabled: isEditing,
            ),
            const SizedBox(height: 12),

            // ── 4. Código de actividad económica (label adapts) ──────────────
            _ProfileField(
              controller: widget.codActividadCtrl,
              label: '4. $actividadLabel',
              icon: Icons.category_outlined,
              isDark: isDark,
              enabled: isEditing,
            ),
            const SizedBox(height: 16),

            // ── 6. Estado / Región / Provincia ───────────────────────────────
            _ProfileField(
              controller: widget.regionEmpCtrl,
              label: '6. Estado / Región / Provincia',
              icon: Icons.location_city_outlined,
              isDark: isDark,
              enabled: isEditing,
            ),
            const SizedBox(height: 12),

            // ── 7. Ciudad / Municipio ────────────────────────────────────────
            _ProfileField(
              controller: widget.ciudadEmpCtrl,
              label: '7. Ciudad / Municipio',
              icon: Icons.map_outlined,
              isDark: isDark,
              enabled: isEditing,
            ),
            const SizedBox(height: 12),

            // ── 8. Dirección completa ────────────────────────────────────────
            _ProfileField(
              controller: widget.direccionEmpCtrl,
              label: '8. Dirección completa',
              icon: Icons.pin_drop_outlined,
              isDark: isDark,
              enabled: isEditing,
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // ── 9 & 10. Contacto (opcionales) ────────────────────────────────
            _SectionHeader(
                label: 'Contacto (Opcional)', isDark: isDark),
            const SizedBox(height: 10),
            _ProfileField(
              controller: widget.telefonoEmpCtrl,
              label: '9. Teléfono',
              icon: Icons.phone_outlined,
              isDark: isDark,
              enabled: isEditing,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: widget.emailEmpCtrl,
              label: '10. Correo electrónico',
              icon: Icons.alternate_email_outlined,
              isDark: isDark,
              enabled: isEditing,
              keyboardType: TextInputType.emailAddress,
            ),

            // Hint for country-specific labels
            if (!isEditing && widget.paisEmpCtrl.text.trim().isNotEmpty) ...[  
              const SizedBox(height: 16),
              _CountryHintChip(paisIso: widget.paisEmpCtrl.text.trim(), isDark: isDark),
            ],

            const SizedBox(height: 32),
            if (!isEditing)
              Center(
                child: Text(
                  'Toca "Editar" para completar los datos de la empresa',
                  style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.grey[400],
                      fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Small chip that shows which fiscal-id / activity-code system applies
class _CountryHintChip extends StatelessWidget {
  final String paisIso;
  final bool isDark;
  const _CountryHintChip({required this.paisIso, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final fiscal = _labelFiscal(paisIso);
    final actividad = _labelActividad(paisIso);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? Colors.white12 : Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 15,
              color: isDark ? Colors.white38 : Colors.grey[500]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Para $paisIso: Fiscal → $fiscal  ·  Actividad → $actividad',
              style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final bool isDark;
  const _SectionHeader({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white70 : Colors.grey[700],
        letterSpacing: 0.4,
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isDark;
  final bool enabled;
  final int maxLines;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;

  const _ProfileField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.isDark,
    this.enabled = true,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final disabledColor = isDark ? Colors.white38 : Colors.grey[400]!;

    return TextFormField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(
          color: enabled ? textPrimary : disabledColor, fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon,
            size: 18,
            color: enabled ? AppTheme.primaryColor : disabledColor),
        filled: true,
        fillColor: enabled
            ? (isDark ? AppTheme.darkCard : Colors.white)
            : (isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.grey[50]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDark ? AppTheme.darkBorder : Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDark ? AppTheme.darkBorder : Colors.grey[300]!),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDark
                  ? Colors.white12
                  : Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: AppTheme.primaryColor, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Plan / Suscripción
// ─────────────────────────────────────────────────────────────────────────────

class _PlanTab extends StatelessWidget {
  const _PlanTab();

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suscripción y Facturación',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary(isDark),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'El ciclo de facturación cierra el día 2 de cada mes.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppTheme.textSecondary(isDark),
            ),
          ),
          const SizedBox(height: 16),
          const PlanSuscripcionTile(),
        ],
      ),
    );
  }
}
