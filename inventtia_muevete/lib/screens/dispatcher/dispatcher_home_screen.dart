import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/carga_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/dispatcher_service.dart';
import '../../services/document_upload_service.dart';
import '../carrier/carrier_home_screen.dart';
import '../common/unified_profile_screen.dart';

class DispatcherHomeScreen extends StatefulWidget {
  const DispatcherHomeScreen({super.key});

  @override
  State<DispatcherHomeScreen> createState() =>
      _DispatcherHomeScreenState();
}

class _DispatcherHomeScreenState extends State<DispatcherHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  List<Map<String, dynamic>> _flota = [];
  bool _loadingFlota = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Future.wait([
      _loadFlota(),
      context.read<CargaProvider>().loadCargasDisponibles(),
    ]);
  }

  Future<void> _loadFlota() async {
    setState(() => _loadingFlota = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final dispatcherDriverId =
          authProvider.driverProfile?['id'] as int?;
      debugPrint('[FlotaDebug] dispatcherDriverId=$dispatcherDriverId');
      if (dispatcherDriverId == null) return;
      final data = await Supabase.instance.client
          .schema('muevete')
          .from('drivers')
          .select(
              'id, name, email, telefono, estado, licencia, carnet, circulacion, '
              'lic_conduccion_frente_url, lic_conduccion_dorso_url, '
              'lic_circulacion_frente_url, lic_circulacion_dorso_url, '
              'lic_operativa_frente_url, lic_operativa_dorso_url, '
              'carrocerias(id, tipo_carroceria, marca, modelo, matricula, capacidad_ton, longitud_m, seguro_vigente)')
          .eq('dispatcher_id', dispatcherDriverId);
      debugPrint('[FlotaDebug] rows=${data.length}');
      if (data.isNotEmpty) {
        debugPrint('[FlotaDebug] first row keys=${data.first.keys.toList()}');
        debugPrint('[FlotaDebug] first row vehiculos=${data.first['vehiculos']}');
        debugPrint('[FlotaDebug] first row=${data.first}');
      }
      if (mounted) {
        setState(() {
          _flota = data.map<Map<String, dynamic>>((row) {
            // vehiculos can come as a List (one-to-many) or Map (one-to-one)
            final veh = row['vehiculos'];
            Map<String, dynamic>? vehiculoMap;
            if (veh is List && veh.isNotEmpty) {
              vehiculoMap = Map<String, dynamic>.from(veh.first as Map);
            } else if (veh is Map) {
              vehiculoMap = Map<String, dynamic>.from(veh);
            }
            // Keep carrocerias as a List<Map> for the detail modal
            final carrs = row['carrocerias'];
            List<Map<String, dynamic>> carroceriasList = [];
            if (carrs is List) {
              carroceriasList = carrs
                  .map((c) => Map<String, dynamic>.from(c as Map))
                  .toList();
            }
            return {
              ...Map<String, dynamic>.from(row),
              'vehiculos': vehiculoMap,
              'carrocerias': carroceriasList,
            };
          }).toList();
        });
      }
    } catch (e, st) {
      debugPrint('[FlotaDebug] ERROR: $e\n$st');
    } finally {
      if (mounted) setState(() => _loadingFlota = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final auth = context.watch<AuthProvider>();
    final name =
        (auth.driverProfile?['name'] as String?) ?? 'Dispatcher';
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        elevation: 0,
        title: Text(
          'Hola, $name',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.person_outline, color: textPrimary),
            tooltip: 'Mi Perfil',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const UnifiedProfileScreen(),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh_outlined, color: textPrimary),
            onPressed: _load,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: Icon(Icons.logout, color: textPrimary),
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/landing');
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor:
              isDark ? Colors.white54 : Colors.grey[500],
          indicatorColor: AppTheme.primaryColor,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.search_outlined), text: 'Cargas'),
            Tab(icon: Icon(Icons.groups_outlined), text: 'Mi Flota'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          const CargasDisponiblesTab(),
          _FlotaTab(
            flota: _flota,
            loading: _loadingFlota,
            onRefresh: _loadFlota,
            onEdit: (driver) => _showEditDriverDialog(context, driver),
            onDelete: (driver) => _deleteDriver(context, driver),
          ),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabs,
        builder: (context, child) {
          return _tabs.index == 1
              ? FloatingActionButton.extended(
                  onPressed: () => _showAddDriverDialog(context),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Agregar Chofer'),
                  backgroundColor: AppTheme.primaryColor,
                )
              : const SizedBox.shrink();
        },
      ),
    );
  }

  /// Shows dialog to add a new driver to the fleet
  Future<void> _showAddDriverDialog(BuildContext context) async {
    final isDark = context.read<ThemeProvider>().isDark;
    final formKey = GlobalKey<FormState>();
    final nombreCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final telefonoCtrl = TextEditingController();
    final marcaCtrl = TextEditingController();
    final modeloCtrl = TextEditingController();
    final matriculaCtrl = TextEditingController();
    final capacidadCtrl = TextEditingController();
    final longitudCtrl = TextEditingController();
    final docService = DocumentUploadService();
    final dispatcherService = DispatcherService();

    String? licCondFrenteUrl;
    String? licCondDorsoUrl;
    String? licCircFrenteUrl;
    String? licCircDorsoUrl;
    String? licOpFrenteUrl;
    String? licOpDorsoUrl;
    String? tipoCarroceria;
    bool seguroVigente = false;

    bool uploadingLicCondFrente = false;
    bool uploadingLicCondDorso = false;
    bool uploadingLicCircFrente = false;
    bool uploadingLicCircDorso = false;
    bool uploadingLicOpFrente = false;
    bool uploadingLicOpDorso = false;

    // Load equipment types from DB
    List<Map<String, dynamic>> tiposEquipo = [];
    try {
      final rows = await Supabase.instance.client
          .schema('muevete')
          .from('app_nom_tipo_equipo')
          .select('id, nombre, abreviacion')
          .eq('activo', true)
          .order('nombre');
      tiposEquipo = List<Map<String, dynamic>>.from(rows);
    } catch (_) {}

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final bg = isDark ? AppTheme.darkCard : Colors.white;
          return Dialog(
            backgroundColor: bg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Row(
                      children: [
                        Text(
                          'Agregar Chofer',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.close),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Form(
                        key: formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                  TextFormField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo *',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) =>
                        v?.trim().isEmpty ?? true ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email *',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (v) {
                      if (v?.trim().isEmpty ?? true) return 'Requerido';
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                          .hasMatch(v!)) {
                        return 'Email inválido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: telefonoCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono *',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (v) =>
                        v?.trim().isEmpty ?? true ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Vehículo',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: tipoCarroceria,
                    dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de equipo',
                      prefixIcon: Icon(Icons.local_shipping_outlined),
                    ),
                    items: tiposEquipo.isEmpty
                        ? ['flatbed', 'dry_van', 'reefer', 'lowboy', 'tanker',
                           'step_deck', 'hotshot', 'curtainsider', 'caja']
                            .map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t.toUpperCase()),
                                ))
                            .toList()
                        : tiposEquipo
                            .map((t) => DropdownMenuItem(
                                  value: t['abreviacion'] as String,
                                  child: Text(t['nombre'] as String),
                                ))
                            .toList(),
                    onChanged: (v) => setS(() => tipoCarroceria = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: marcaCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Marca',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: modeloCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Modelo',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: matriculaCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Matrícula / Chapa',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: capacidadCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Capacidad (ton)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: longitudCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Longitud (m)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Seguro de carga vigente',
                      style: TextStyle(fontSize: 13),
                    ),
                    value: seguroVigente,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (v) => setS(() => seguroVigente = v),
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Licencias',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildLicensePhotoRow(
                    'Lic. Conducción - Frente',
                    licCondFrenteUrl,
                    uploadingLicCondFrente,
                    () async {
                      final source = await _showImageSourcePicker(ctx, isDark);
                      if (source == null) return;
                      setS(() => uploadingLicCondFrente = true);
                      final url = await docService.pickCompressAndUpload(
                        uuid: 'disp_${DateTime.now().millisecondsSinceEpoch}',
                        filename: 'lic_cond_frente.jpg',
                        source: source,
                      );
                      setS(() {
                        licCondFrenteUrl = url;
                        uploadingLicCondFrente = false;
                      });
                    },
                    isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildLicensePhotoRow(
                    'Lic. Conducción - Dorso',
                    licCondDorsoUrl,
                    uploadingLicCondDorso,
                    () async {
                      final source = await _showImageSourcePicker(ctx, isDark);
                      if (source == null) return;
                      setS(() => uploadingLicCondDorso = true);
                      final url = await docService.pickCompressAndUpload(
                        uuid: 'disp_${DateTime.now().millisecondsSinceEpoch}',
                        filename: 'lic_cond_dorso.jpg',
                        source: source,
                      );
                      setS(() {
                        licCondDorsoUrl = url;
                        uploadingLicCondDorso = false;
                      });
                    },
                    isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildLicensePhotoRow(
                    'Lic. Circulación - Frente',
                    licCircFrenteUrl,
                    uploadingLicCircFrente,
                    () async {
                      final source = await _showImageSourcePicker(ctx, isDark);
                      if (source == null) return;
                      setS(() => uploadingLicCircFrente = true);
                      final url = await docService.pickCompressAndUpload(
                        uuid: 'disp_${DateTime.now().millisecondsSinceEpoch}',
                        filename: 'lic_circ_frente.jpg',
                        source: source,
                      );
                      setS(() {
                        licCircFrenteUrl = url;
                        uploadingLicCircFrente = false;
                      });
                    },
                    isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildLicensePhotoRow(
                    'Lic. Circulación - Dorso',
                    licCircDorsoUrl,
                    uploadingLicCircDorso,
                    () async {
                      final source = await _showImageSourcePicker(ctx, isDark);
                      if (source == null) return;
                      setS(() => uploadingLicCircDorso = true);
                      final url = await docService.pickCompressAndUpload(
                        uuid: 'disp_${DateTime.now().millisecondsSinceEpoch}',
                        filename: 'lic_circ_dorso.jpg',
                        source: source,
                      );
                      setS(() {
                        licCircDorsoUrl = url;
                        uploadingLicCircDorso = false;
                      });
                    },
                    isDark,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Lic. Operativa (opcional)',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildLicensePhotoRow(
                    'Lic. Operativa - Frente',
                    licOpFrenteUrl,
                    uploadingLicOpFrente,
                    () async {
                      final source = await _showImageSourcePicker(ctx, isDark);
                      if (source == null) return;
                      setS(() => uploadingLicOpFrente = true);
                      final url = await docService.pickCompressAndUpload(
                        uuid: 'disp_${DateTime.now().millisecondsSinceEpoch}',
                        filename: 'lic_op_frente.jpg',
                        source: source,
                      );
                      setS(() {
                        licOpFrenteUrl = url;
                        uploadingLicOpFrente = false;
                      });
                    },
                    isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildLicensePhotoRow(
                    'Lic. Operativa - Dorso',
                    licOpDorsoUrl,
                    uploadingLicOpDorso,
                    () async {
                      final source = await _showImageSourcePicker(ctx, isDark);
                      if (source == null) return;
                      setS(() => uploadingLicOpDorso = true);
                      final url = await docService.pickCompressAndUpload(
                        uuid: 'disp_${DateTime.now().millisecondsSinceEpoch}',
                        filename: 'lic_op_dorso.jpg',
                        source: source,
                      );
                      setS(() {
                        licOpDorsoUrl = url;
                        uploadingLicOpDorso = false;
                      });
                    },
                    isDark,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        Navigator.pop(ctx, true);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Agregar Chofer'),
                    ),
                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );


    if (result == true) {
      try {
        final authProvider = context.read<AuthProvider>();
        final dispatcherDriverId = authProvider.driverProfile?['id'] as int?;
        final dispatcherUuid = authProvider.user?.id;

        if (dispatcherDriverId == null || dispatcherUuid == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: No se pudo obtener el ID del dispatcher')),
          );
          return;
        }

        await dispatcherService.invitarTransportista(
          dispatcherUuid: dispatcherUuid,
          dispatcherDriverId: dispatcherDriverId,
          transportista: {
            'name': nombreCtrl.text.trim(),
            'email': emailCtrl.text.trim(),
            'telefono': telefonoCtrl.text.trim(),
            'tipo_carroceria': tipoCarroceria,
            'marca': marcaCtrl.text.trim(),
            'modelo': modeloCtrl.text.trim(),
            'matricula': matriculaCtrl.text.trim(),
            'capacidad_ton': double.tryParse(capacidadCtrl.text.trim()),
            if (longitudCtrl.text.trim().isNotEmpty)
              'longitud_m': double.tryParse(longitudCtrl.text.trim()),
            'seguro_vigente': seguroVigente,
            'lic_conduccion_frente_url': licCondFrenteUrl,
            'lic_conduccion_dorso_url': licCondDorsoUrl,
            'lic_circulacion_frente_url': licCircFrenteUrl,
            'lic_circulacion_dorso_url': licCircDorsoUrl,
            'lic_operativa_frente_url': licOpFrenteUrl,
            'lic_operativa_dorso_url': licOpDorsoUrl,
          },
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chofer agregado exitosamente'),
            backgroundColor: AppTheme.success,
          ),
        );
        _loadFlota();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al agregar chofer: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }

    nombreCtrl.dispose();
    emailCtrl.dispose();
    telefonoCtrl.dispose();
    marcaCtrl.dispose();
    modeloCtrl.dispose();
    matriculaCtrl.dispose();
    capacidadCtrl.dispose();
    longitudCtrl.dispose();
  }

  Future<ImageSource?> _showImageSourcePicker(BuildContext context, bool isDark) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      builder: (modalCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Cámara'),
              onTap: () => Navigator.pop(modalCtx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Galería'),
              onTap: () => Navigator.pop(modalCtx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLicensePhotoRow(
    String label,
    String? url,
    bool uploading,
    VoidCallback onTap,
    bool isDark,
  ) {
    final hasPhoto = url != null && url.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: hasPhoto
              ? Border.all(color: AppTheme.success)
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: hasPhoto
                    ? AppTheme.success.withValues(alpha: 0.15)
                    : AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                image: hasPhoto
                    ? DecorationImage(
                        image: NetworkImage(url),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: !hasPhoto
                  ? Icon(
                      uploading ? Icons.hourglass_top : Icons.add_a_photo_outlined,
                      size: 18,
                      color: uploading ? Colors.orange : AppTheme.primaryColor,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasPhoto ? 'Foto agregada' : 'Toca para subir',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: hasPhoto ? AppTheme.success : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (hasPhoto)
              const Icon(Icons.check_circle, color: AppTheme.success, size: 18),
          ],
        ),
      ),
    );
  }

  /// Shows dialog to edit an existing driver
  Future<void> _showEditDriverDialog(
      BuildContext context, Map<String, dynamic> driver) async {
    final isDark = context.read<ThemeProvider>().isDark;
    final formKey = GlobalKey<FormState>();
    final nombreCtrl = TextEditingController(
        text: driver['name'] as String? ?? '');
    final emailCtrl = TextEditingController(
        text: driver['email'] as String? ?? '');
    final telefonoCtrl = TextEditingController(
        text: driver['telefono'] as String? ?? '');
    final licenciaCtrl = TextEditingController(
        text: driver['licencia'] as String? ?? '');
    final carnetCtrl = TextEditingController(
        text: driver['carnet'] as String? ?? '');
    final categoriaCtrl = TextEditingController(
        text: driver['categoria'] as String? ?? '');

    final docService = DocumentUploadService();
    final dispatcherService = DispatcherService();
    final driverId = driver['id'] as int;

    // Load carroceria data if available
    final carroceriasList = driver['carrocerias'];
    Map<String, dynamic>? carroceria;
    if (carroceriasList is List && carroceriasList.isNotEmpty) {
      carroceria = Map<String, dynamic>.from(carroceriasList.first as Map);
    }

    final marcaCtrl = TextEditingController(text: carroceria?['marca'] as String? ?? '');
    final modeloCtrl = TextEditingController(text: carroceria?['modelo'] as String? ?? '');
    final matriculaCtrl = TextEditingController(text: carroceria?['matricula'] as String? ?? '');
    final capacidadCtrl = TextEditingController(
        text: carroceria?['capacidad_ton']?.toString() ?? '');
    final longitudCtrl = TextEditingController(
        text: carroceria?['longitud_m']?.toString() ?? '');
    String? tipoCarroceria = carroceria?['tipo_carroceria'] as String?;
    bool seguroVigente = carroceria?['seguro_vigente'] as bool? ?? false;
    final carroceriaId = carroceria?['id'] as int?;

    List<Map<String, dynamic>> tiposEquipo = [];
    try {
      final rows = await Supabase.instance.client
          .schema('muevete')
          .from('app_nom_tipo_equipo')
          .select('id, nombre, abreviacion')
          .eq('activo', true)
          .order('nombre');
      tiposEquipo = List<Map<String, dynamic>>.from(rows);
    } catch (_) {}

    String? licCondFrenteUrl = driver['lic_conduccion_frente_url'] as String?;
    String? licCondDorsoUrl = driver['lic_conduccion_dorso_url'] as String?;
    String? licCircFrenteUrl = driver['lic_circulacion_frente_url'] as String?;
    String? licCircDorsoUrl = driver['lic_circulacion_dorso_url'] as String?;
    String? licOpFrenteUrl = driver['lic_operativa_frente_url'] as String?;
    String? licOpDorsoUrl = driver['lic_operativa_dorso_url'] as String?;

    bool uploadingLicCondFrente = false;
    bool uploadingLicCondDorso = false;
    bool uploadingLicCircFrente = false;
    bool uploadingLicCircDorso = false;
    bool uploadingLicOpFrente = false;
    bool uploadingLicOpDorso = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final bg = isDark ? AppTheme.darkCard : Colors.white;
          return Dialog(
            backgroundColor: bg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Row(
                      children: [
                        Text(
                          'Editar Chofer',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.close),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Form(
                        key: formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                  TextFormField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo *',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) =>
                        v?.trim().isEmpty ?? true ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email *',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (v) {
                      if (v?.trim().isEmpty ?? true) return 'Requerido';
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                          .hasMatch(v!)) {
                        return 'Email inválido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: telefonoCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono *',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (v) =>
                        v?.trim().isEmpty ?? true ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Vehículo',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: tipoCarroceria,
                    dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de equipo',
                      prefixIcon: Icon(Icons.local_shipping_outlined),
                    ),
                    items: tiposEquipo.isEmpty
                        ? ['flatbed', 'dry_van', 'reefer', 'lowboy', 'tanker',
                           'step_deck', 'hotshot', 'curtainsider', 'caja']
                            .map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t.toUpperCase()),
                                ))
                            .toList()
                        : tiposEquipo
                            .map((t) => DropdownMenuItem(
                                  value: t['abreviacion'] as String,
                                  child: Text(t['nombre'] as String),
                                ))
                            .toList(),
                    onChanged: (v) => setS(() => tipoCarroceria = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: marcaCtrl,
                          decoration: const InputDecoration(labelText: 'Marca'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: modeloCtrl,
                          decoration: const InputDecoration(labelText: 'Modelo'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: matriculaCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Matrícula / Chapa',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: capacidadCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Capacidad (ton)'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: longitudCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Longitud (m)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Seguro vigente', style: TextStyle(fontSize: 13)),
                    value: seguroVigente,
                    activeColor: AppTheme.primaryColor,
                    onChanged: (v) => setS(() => seguroVigente = v),
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Licencias',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: licenciaCtrl,
                          decoration: const InputDecoration(
                            labelText: 'N° Licencia',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: categoriaCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Categoría',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: carnetCtrl,
                    decoration: const InputDecoration(
                      labelText: 'N° Carnet',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Fotos de Licencias',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildLicensePhotoRow(
                    'Lic. Conducción - Frente',
                    licCondFrenteUrl,
                    uploadingLicCondFrente,
                    () async {
                      final source = await _showImageSourcePicker(ctx, isDark);
                      if (source == null) return;
                      setS(() => uploadingLicCondFrente = true);
                      final url = await docService.pickCompressAndUpload(
                        uuid: 'disp_${DateTime.now().millisecondsSinceEpoch}',
                        filename: 'lic_cond_frente.jpg',
                        source: source,
                      );
                      setS(() {
                        licCondFrenteUrl = url;
                        uploadingLicCondFrente = false;
                      });
                    },
                    isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildLicensePhotoRow(
                    'Lic. Conducción - Dorso',
                    licCondDorsoUrl,
                    uploadingLicCondDorso,
                    () async {
                      final source = await _showImageSourcePicker(ctx, isDark);
                      if (source == null) return;
                      setS(() => uploadingLicCondDorso = true);
                      final url = await docService.pickCompressAndUpload(
                        uuid: 'disp_${DateTime.now().millisecondsSinceEpoch}',
                        filename: 'lic_cond_dorso.jpg',
                        source: source,
                      );
                      setS(() {
                        licCondDorsoUrl = url;
                        uploadingLicCondDorso = false;
                      });
                    },
                    isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildLicensePhotoRow(
                    'Lic. Circulación - Frente',
                    licCircFrenteUrl,
                    uploadingLicCircFrente,
                    () async {
                      final source = await _showImageSourcePicker(ctx, isDark);
                      if (source == null) return;
                      setS(() => uploadingLicCircFrente = true);
                      final url = await docService.pickCompressAndUpload(
                        uuid: 'disp_${DateTime.now().millisecondsSinceEpoch}',
                        filename: 'lic_circ_frente.jpg',
                        source: source,
                      );
                      setS(() {
                        licCircFrenteUrl = url;
                        uploadingLicCircFrente = false;
                      });
                    },
                    isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildLicensePhotoRow(
                    'Lic. Circulación - Dorso',
                    licCircDorsoUrl,
                    uploadingLicCircDorso,
                    () async {
                      final source = await _showImageSourcePicker(ctx, isDark);
                      if (source == null) return;
                      setS(() => uploadingLicCircDorso = true);
                      final url = await docService.pickCompressAndUpload(
                        uuid: 'disp_${DateTime.now().millisecondsSinceEpoch}',
                        filename: 'lic_circ_dorso.jpg',
                        source: source,
                      );
                      setS(() {
                        licCircDorsoUrl = url;
                        uploadingLicCircDorso = false;
                      });
                    },
                    isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildLicensePhotoRow(
                    'Lic. Operativa - Frente (opcional)',
                    licOpFrenteUrl,
                    uploadingLicOpFrente,
                    () async {
                      final source = await _showImageSourcePicker(ctx, isDark);
                      if (source == null) return;
                      setS(() => uploadingLicOpFrente = true);
                      final url = await docService.pickCompressAndUpload(
                        uuid: 'disp_${DateTime.now().millisecondsSinceEpoch}',
                        filename: 'lic_op_frente.jpg',
                        source: source,
                      );
                      setS(() {
                        licOpFrenteUrl = url;
                        uploadingLicOpFrente = false;
                      });
                    },
                    isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildLicensePhotoRow(
                    'Lic. Operativa - Dorso (opcional)',
                    licOpDorsoUrl,
                    uploadingLicOpDorso,
                    () async {
                      final source = await _showImageSourcePicker(ctx, isDark);
                      if (source == null) return;
                      setS(() => uploadingLicOpDorso = true);
                      final url = await docService.pickCompressAndUpload(
                        uuid: 'disp_${DateTime.now().millisecondsSinceEpoch}',
                        filename: 'lic_op_dorso.jpg',
                        source: source,
                      );
                      setS(() {
                        licOpDorsoUrl = url;
                        uploadingLicOpDorso = false;
                      });
                    },
                    isDark,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        Navigator.pop(ctx, true);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Guardar Cambios'),
                    ),
                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (result == true) {
      try {
        await dispatcherService.actualizarTransportista(
          driverId: driverId,
          driverData: {
            'name': nombreCtrl.text.trim(),
            'email': emailCtrl.text.trim(),
            'telefono': telefonoCtrl.text.trim(),
            'licencia': licenciaCtrl.text.trim(),
            'carnet': carnetCtrl.text.trim(),
            'categoria': categoriaCtrl.text.trim(),
            'lic_conduccion_frente_url': licCondFrenteUrl,
            'lic_conduccion_dorso_url': licCondDorsoUrl,
            'lic_circulacion_frente_url': licCircFrenteUrl,
            'lic_circulacion_dorso_url': licCircDorsoUrl,
            'lic_operativa_frente_url': licOpFrenteUrl,
            'lic_operativa_dorso_url': licOpDorsoUrl,
          },
          carroceriaId: carroceriaId,
          carroceriaData: {
            'tipo_carroceria': tipoCarroceria ?? 'otro',
            if (marcaCtrl.text.trim().isNotEmpty) 'marca': marcaCtrl.text.trim(),
            if (modeloCtrl.text.trim().isNotEmpty) 'modelo': modeloCtrl.text.trim(),
            if (matriculaCtrl.text.trim().isNotEmpty) 'matricula': matriculaCtrl.text.trim(),
            if (capacidadCtrl.text.trim().isNotEmpty)
              'capacidad_ton': double.tryParse(capacidadCtrl.text.trim()),
            if (longitudCtrl.text.trim().isNotEmpty)
              'longitud_m': double.tryParse(longitudCtrl.text.trim()),
            'seguro_vigente': seguroVigente,
          },
          dispatcherDriverId: context.read<AuthProvider>().driverProfile?['id'] as int?,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chofer actualizado exitosamente'),
            backgroundColor: AppTheme.success,
          ),
        );
        _loadFlota();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar chofer: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }

    nombreCtrl.dispose();
    emailCtrl.dispose();
    telefonoCtrl.dispose();
    licenciaCtrl.dispose();
    carnetCtrl.dispose();
    categoriaCtrl.dispose();
    marcaCtrl.dispose();
    modeloCtrl.dispose();
    matriculaCtrl.dispose();
    capacidadCtrl.dispose();
    longitudCtrl.dispose();
  }

  /// Deletes a driver from the fleet
  Future<void> _deleteDriver(
      BuildContext context, Map<String, dynamic> driver) async {
    final driverId = driver['id'] as int?;
    if (driverId == null) return;

    try {
      final dispatcherService = DispatcherService();
      await dispatcherService.eliminarTransportista(driverId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chofer eliminado exitosamente'),
          backgroundColor: AppTheme.success,
        ),
      );
      _loadFlota();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar chofer: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }
}

class _FlotaTab extends StatelessWidget {
  final List<Map<String, dynamic>> flota;
  final bool loading;
  final VoidCallback onRefresh;
  final Function(Map<String, dynamic>)? onEdit;
  final Function(Map<String, dynamic>)? onDelete;
  const _FlotaTab({
    required this.flota,
    required this.loading,
    required this.onRefresh,
    this.onEdit,
    this.onDelete,
  });

  void _showDriverDetail(
      BuildContext context, Map<String, dynamic> driver, bool isDark) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary = isDark ? Colors.white60 : Colors.grey[600]!;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;

    final vehiculo = driver['vehiculos'] as Map<String, dynamic>?;
    // carrocerias comes as a List from the join
    final carroceriasList = driver['carrocerias'];
    Map<String, dynamic>? carroceria;
    if (carroceriasList is List && carroceriasList.isNotEmpty) {
      carroceria = Map<String, dynamic>.from(carroceriasList.first as Map);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor:
                        AppTheme.primaryColor.withValues(alpha: 0.15),
                    child: Text(
                      (driver['name'] as String? ?? 'T')[0].toUpperCase(),
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driver['name'] as String? ?? 'Transportista',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (driver['telefono'] != null)
                          Row(
                            children: [
                              Icon(Icons.phone_outlined, size: 13, color: textSecondary),
                              const SizedBox(width: 4),
                              Text(
                                driver['telefono'] as String,
                                style: TextStyle(fontSize: 13, color: textSecondary),
                              ),
                            ],
                          ),
                        if (driver['email'] != null) ...[  
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.email_outlined, size: 13, color: textSecondary),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  driver['email'] as String,
                                  style: TextStyle(fontSize: 13, color: textSecondary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Status
              _DetailSection(
                title: 'Estado',
                isDark: isDark,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: (driver['estado'] == true
                                ? Colors.green
                                : Colors.grey)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        driver['estado'] == true ? 'Activo' : 'Inactivo',
                        style: TextStyle(
                          color: driver['estado'] == true
                              ? Colors.green[700]
                              : Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Licenses
              if (driver['licencia'] != null ||
                  driver['carnet'] != null ||
                  driver['circulacion'] != null) ...[
                const SizedBox(height: 16),
                _DetailSection(
                  title: 'Licencias y Documentos',
                  isDark: isDark,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (driver['licencia'] != null)
                        _DetailRow('Licencia', driver['licencia'] as String),
                      if (driver['carnet'] != null)
                        _DetailRow('Carnet', driver['carnet'] as String),
                      if (driver['circulacion'] != null)
                        _DetailRow('Circulación', driver['circulacion'] as String),
                    ],
                  ),
                ),
              ],

              // License Photos
              if (driver['lic_conduccion_frente_url'] != null ||
                  driver['lic_conduccion_dorso_url'] != null ||
                  driver['lic_circulacion_frente_url'] != null ||
                  driver['lic_circulacion_dorso_url'] != null ||
                  driver['lic_operativa_frente_url'] != null ||
                  driver['lic_operativa_dorso_url'] != null) ...[
                const SizedBox(height: 16),
                _DetailSection(
                  title: 'Fotos de Licencias',
                  isDark: isDark,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (driver['lic_conduccion_frente_url'] != null)
                        _LicensePhoto(ctx,
                            'Lic. Conducción Frente',
                            driver['lic_conduccion_frente_url'] as String),
                      if (driver['lic_conduccion_dorso_url'] != null)
                        _LicensePhoto(ctx,
                            'Lic. Conducción Dorso',
                            driver['lic_conduccion_dorso_url'] as String),
                      if (driver['lic_circulacion_frente_url'] != null)
                        _LicensePhoto(ctx,
                            'Lic. Circulación Frente',
                            driver['lic_circulacion_frente_url'] as String),
                      if (driver['lic_circulacion_dorso_url'] != null)
                        _LicensePhoto(ctx,
                            'Lic. Circulación Dorso',
                            driver['lic_circulacion_dorso_url'] as String),
                      if (driver['lic_operativa_frente_url'] != null)
                        _LicensePhoto(ctx,
                            'Lic. Operativa Frente',
                            driver['lic_operativa_frente_url'] as String),
                      if (driver['lic_operativa_dorso_url'] != null)
                        _LicensePhoto(ctx,
                            'Lic. Operativa Dorso',
                            driver['lic_operativa_dorso_url'] as String),
                    ],
                  ),
                ),
              ],

              // Carrocería / vehicle body info
              if (carroceria != null) ...[
                const SizedBox(height: 16),
                _DetailSection(
                  title: 'Carrocería',
                  isDark: isDark,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (carroceria!['tipo_carroceria'] != null)
                        _DetailRow('Tipo', carroceria!['tipo_carroceria'] as String),
                      if (carroceria['marca'] != null)
                        _DetailRow('Marca', carroceria!['marca'] as String),
                      if (carroceria['modelo'] != null)
                        _DetailRow('Modelo', carroceria!['modelo'] as String),
                      if (carroceria['matricula'] != null)
                        _DetailRow('Matrícula', carroceria!['matricula'] as String),
                      if (carroceria['capacidad_ton'] != null)
                        _DetailRow('Capacidad', '${carroceria!['capacidad_ton']} ton'),
                      if (carroceria['longitud_m'] != null)
                        _DetailRow('Longitud', '${carroceria!['longitud_m']} m'),
                      _DetailRow(
                        'Seguro',
                        carroceria['seguro_vigente'] == true ? 'Vigente ✓' : 'No vigente',
                      ),
                    ],
                  ),
                ),
              ],

              // Vehicle
              if (vehiculo != null) ...[
                const SizedBox(height: 16),
                _DetailSection(
                  title: 'Vehículo Asignado',
                  isDark: isDark,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (vehiculo!['image'] != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            vehiculo['image'] as String,
                            height: 120,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              height: 120,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.local_shipping_outlined,
                                size: 40,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          height: 120,
                          decoration: BoxDecoration(
                            color:
                                AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.local_shipping_outlined,
                              size: 40,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (vehiculo!['marca'] != null || vehiculo['modelo'] != null)
                        Text(
                          [
                            if (vehiculo['marca'] != null) vehiculo!['marca'],
                            if (vehiculo['modelo'] != null) vehiculo!['modelo'],
                          ].where((e) => e != null).join(' '),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            color: textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      const SizedBox(height: 6),
                      if (vehiculo['chapa'] != null)
                        _DetailRow('Matrícula', vehiculo!['chapa'] as String),
                      if (vehiculo['capacidad_ton'] != null)
                        _DetailRow('Capacidad', '${vehiculo!['capacidad_ton']} ton'),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onEdit != null
                          ? () {
                              Navigator.pop(context);
                              onEdit!(driver);
                            }
                          : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(color: AppTheme.primaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onDelete != null
                          ? () {
                              Navigator.pop(context);
                              _confirmDelete(context, driver, onDelete!);
                            }
                          : null,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Eliminar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _LicensePhoto(BuildContext ctx, String label, String url) {
    return GestureDetector(
      onTap: () => _showFullscreenImage(ctx, label, url),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  width: 140,
                  height: 90,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 140,
                    height: 90,
                    color: Colors.grey[300],
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.zoom_in, color: Colors.white, size: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  void _showFullscreenImage(BuildContext context, String label, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.white, size: 60),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              right: 56,
              child: Text(
                label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary =
        isDark ? Colors.white60 : Colors.grey[600]!;

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (flota.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.groups_outlined,
                  size: 64, color: AppTheme.primaryColor),
              const SizedBox(height: 16),
              Text(
                'Sin transportistas en la flota',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Los transportistas vinculados a tu empresa aparecerán aquí.',
                style:
                    TextStyle(fontSize: 13, color: textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: flota.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final driver = flota[i];
          final nombre =
              driver['name'] as String? ?? 'Transportista';
          final phone =
              driver['telefono'] as String? ?? '';
          final activo = driver['estado'] == true;
          final vehiculo = driver['vehiculos'] as Map<String, dynamic>?;

          return InkWell(
            onTap: () => _showDriverDetail(context, driver, isDark),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isDark
                        ? AppTheme.darkBorder
                        : Colors.grey[200]!),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Vehicle or Driver Avatar
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      image: vehiculo?['image'] != null
                          ? DecorationImage(
                              image: NetworkImage(
                                  vehiculo!['image'] as String),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: vehiculo?['image'] == null
                        ? Icon(
                            Icons.local_shipping_outlined,
                            color: AppTheme.primaryColor,
                            size: 22,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nombre,
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: textPrimary)),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(phone,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: textSecondary)),
                        ],
                        // Vehicle info if available
                        if (vehiculo != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (vehiculo!['marca'] != null)
                                vehiculo!['marca'],
                              if (vehiculo['chapa'] != null)
                                vehiculo!['chapa'],
                            ].where((e) => e != null).join(' · '),
                            style: TextStyle(
                              fontSize: 11,
                              color: textSecondary,
                            ),
                          ),
                        ],
                        // License indicators
                        if (driver['licencia'] != null ||
                            driver['carnet'] != null) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            children: [
                              if (driver['lic_conduccion_frente_url'] != null ||
                                  driver['lic_operativa_frente_url'] != null)
                                Icon(Icons.verified,
                                    size: 14, color: Colors.green[600]),
                              if (driver['licencia'] != null)
                                _Badge('Lic: ${driver['licencia']}', isDark),
                              if (driver['categoria'] != null)
                                _Badge('Cat: ${driver['categoria']}', isDark),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (activo ? Colors.green : Colors.grey)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: (activo ? Colors.green : Colors.grey)
                                  .withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          activo ? 'Activo' : 'Inactivo',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: activo ? Colors.green : Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Action buttons
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit_outlined,
                                size: 18, color: AppTheme.primaryColor),
                            onPressed: onEdit != null
                                ? () => onEdit!(driver)
                                : null,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            tooltip: 'Editar',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: Colors.redAccent),
                            onPressed: onDelete != null
                                ? () => _confirmDelete(context, driver, onDelete!)
                                : null,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            tooltip: 'Eliminar',
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, Map<String, dynamic> driver,
      Function(Map<String, dynamic>) onDelete) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = driver['name'] as String? ?? 'este chofer';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        title: Text(
          'Eliminar Chofer',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar a "$name" de tu flota? Esta acción no se puede deshacer.',
          style: GoogleFonts.plusJakartaSans(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete(driver);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

// Helper widgets for driver detail view
class _DetailSection extends StatelessWidget {
  final String title;
  final Widget child;
  final bool isDark;

  const _DetailSection({
    required this.title,
    required this.child,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final bool isDark;

  const _Badge(this.text, this.isDark);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: AppTheme.primaryColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
