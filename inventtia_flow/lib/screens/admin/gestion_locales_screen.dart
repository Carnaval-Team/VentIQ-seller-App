import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/entidad.dart';
import '../../models/servicio.dart';
import '../../services/catalogo_service.dart';
import '../../services/geonames_service.dart';

class GestionLocalesScreen extends StatefulWidget {
  final Entidad entidad;
  const GestionLocalesScreen({super.key, required this.entidad});

  @override
  State<GestionLocalesScreen> createState() => _GestionLocalesScreenState();
}

class _GestionLocalesScreenState extends State<GestionLocalesScreen> {
  List<Local> _locales = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      _locales = await CatalogoService.getLocalesByEntidad(widget.entidad.id);
    } catch (e) {
      print('[flow] GestionLocalesScreen _cargar ERROR: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _nuevoLocal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LocalFormSheet(idEntidad: widget.entidad.id),
    ).then((_) => _cargar());
  }

  void _editarLocal(Local local) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _LocalFormSheet(idEntidad: widget.entidad.id, local: local),
    ).then((_) => _cargar());
  }

  Future<void> _eliminarLocal(Local local) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Local'),
        content: Text(
            '¿Eliminar "${local.nombre}"? Se eliminarán sus servicios y colas asociados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await CatalogoService.deleteLocal(local.id);
        await _cargar();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Locales · ${widget.entidad.denominacion}'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevoLocal,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Local'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _locales.isEmpty
              ? const Center(
                  child: Text('Sin locales registrados',
                      style: TextStyle(color: AppTheme.textSecondary)),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _locales.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final l = _locales[i];
                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppTheme.surface,
                            child: Icon(Icons.store_outlined,
                                color: AppTheme.primary),
                          ),
                          title: Text(l.nombre,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: l.direccion != null
                              ? Text(l.direccion!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12))
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    size: 20, color: AppTheme.primary),
                                onPressed: () => _editarLocal(l),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 20, color: AppTheme.error),
                                onPressed: () => _eliminarLocal(l),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _LocalFormSheet extends StatefulWidget {
  final int idEntidad;
  final Local? local;
  const _LocalFormSheet({required this.idEntidad, this.local});

  @override
  State<_LocalFormSheet> createState() => _LocalFormSheetState();
}

class _LocalFormSheetState extends State<_LocalFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _dirCtrl;
  late final TextEditingController _horarioCtrl;

  // GeoNames
  List<Map<String, dynamic>> _countries = [];
  List<Map<String, dynamic>> _states = [];
  Map<String, dynamic>? _selectedCountry;
  Map<String, dynamic>? _selectedState;
  bool _loadingCountries = false;
  bool _loadingStates = false;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.local?.nombre ?? '');
    _descCtrl = TextEditingController(text: widget.local?.descripcion ?? '');
    _dirCtrl = TextEditingController(text: widget.local?.direccion ?? '');
    _horarioCtrl =
        TextEditingController(text: widget.local?.horarioAtencion ?? '');
    _loadCountries();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    _dirCtrl.dispose();
    _horarioCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCountries() async {
    setState(() => _loadingCountries = true);
    try {
      final countries = await GeonamesService.getCountries();
      if (!mounted) return;
      setState(() {
        _countries = countries;
        _loadingCountries = false;
      });
      // Si el local ya tiene país, preseleccionar
      final existingPais = widget.local?.pais;
      if (existingPais != null && existingPais.isNotEmpty) {
        final match = countries.firstWhere(
          (c) => (c['countryName'] as String) == existingPais,
          orElse: () => <String, dynamic>{},
        );
        if (match.isNotEmpty) {
          setState(() => _selectedCountry = match);
          await _loadStates(match['countryCode'] as String,
              preselectedProvincia: widget.local?.provincia);
        }
      }
    } catch (e) {
      print('[flow] _loadCountries ERROR: $e');
      if (mounted) setState(() => _loadingCountries = false);
    }
  }

  Future<void> _loadStates(String countryCode,
      {String? preselectedProvincia}) async {
    setState(() {
      _loadingStates = true;
      _states = [];
      _selectedState = null;
    });
    try {
      final states = await GeonamesService.getStates(countryCode);
      if (!mounted) return;
      setState(() {
        _states = states;
        _loadingStates = false;
      });
      if (preselectedProvincia != null && preselectedProvincia.isNotEmpty) {
        final match = states.firstWhere(
          (s) => (s['name'] as String) == preselectedProvincia,
          orElse: () => <String, dynamic>{},
        );
        if (match.isNotEmpty) setState(() => _selectedState = match);
      }
    } catch (e) {
      print('[flow] _loadStates ERROR: $e');
      if (mounted) setState(() => _loadingStates = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    String? _v(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final paisNombre = _selectedCountry != null
        ? _selectedCountry!['countryName'] as String
        : null;
    final provinciaNombre =
        _selectedState != null ? _selectedState!['name'] as String : null;
    try {
      if (widget.local == null) {
        await CatalogoService.createLocal(
          nombre: _nombreCtrl.text.trim(),
          descripcion: _v(_descCtrl),
          direccion: _v(_dirCtrl),
          horarioAtencion: _v(_horarioCtrl),
          pais: paisNombre,
          provincia: provinciaNombre,
          idEntidad: widget.idEntidad,
        );
      } else {
        await CatalogoService.updateLocal(
          id: widget.local!.id,
          nombre: _nombreCtrl.text.trim(),
          descripcion: _v(_descCtrl),
          direccion: _v(_dirCtrl),
          horarioAtencion: _v(_horarioCtrl),
          pais: paisNombre,
          provincia: provinciaNombre,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.local == null ? 'Nuevo Local' : 'Editar Local',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // Nombre
              TextFormField(
                controller: _nombreCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  prefixIcon: Icon(Icons.store_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),

              // Descripción
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 12),

              // Dirección
              TextFormField(
                controller: _dirCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dirección',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 12),

              // Horario
              TextFormField(
                controller: _horarioCtrl,
                decoration: const InputDecoration(
                  labelText: 'Horario de atención',
                  prefixIcon: Icon(Icons.schedule),
                  hintText: 'Ej: Lun-Vie 8:00-17:00',
                ),
              ),
              const SizedBox(height: 12),

              // ── País (dropdown GeoNames) ──────────────────
              _GeoDropdown(
                label: 'País',
                icon: Icons.flag_outlined,
                loading: _loadingCountries,
                hint: _loadingCountries ? 'Cargando países...' : 'Seleccionar país',
                value: _selectedCountry,
                items: _countries,
                displayKey: 'countryName',
                onChanged: (country) {
                  setState(() {
                    _selectedCountry = country;
                    _selectedState = null;
                    _states = [];
                  });
                  if (country != null) {
                    _loadStates(country['countryCode'] as String);
                  }
                },
              ),
              const SizedBox(height: 12),

              // ── Estado/Provincia (dropdown GeoNames) ──────
              _GeoDropdown(
                label: 'Estado / Provincia',
                icon: Icons.map_outlined,
                loading: _loadingStates,
                hint: _selectedCountry == null
                    ? 'Selecciona un país primero'
                    : _loadingStates
                        ? 'Cargando estados...'
                        : _states.isEmpty
                            ? 'Sin estados disponibles'
                            : 'Seleccionar estado',
                value: _selectedState,
                items: _states,
                displayKey: 'name',
                enabled: _selectedCountry != null && !_loadingStates && _states.isNotEmpty,
                onChanged: (state) => setState(() => _selectedState = state),
              ),
              const SizedBox(height: 20),

              // Botón guardar
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        widget.local == null ? 'Crear Local' : 'Guardar',
                        style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dropdown genérico para GeoNames ──────────────────────────
class _GeoDropdown extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final String hint;
  final Map<String, dynamic>? value;
  final List<Map<String, dynamic>> items;
  final String displayKey;
  final bool enabled;
  final ValueChanged<Map<String, dynamic>?> onChanged;

  const _GeoDropdown({
    required this.label,
    required this.icon,
    required this.loading,
    required this.hint,
    required this.value,
    required this.items,
    required this.displayKey,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: loading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : Icon(icon),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      isEmpty: value == null,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Map<String, dynamic>>(
          value: value,
          hint: Text(hint,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 14)),
          isExpanded: true,
          isDense: true,
          onChanged: enabled && !loading ? onChanged : null,
          items: items
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(
                      item[displayKey] as String,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}
