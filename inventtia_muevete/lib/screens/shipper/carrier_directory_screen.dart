import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_theme.dart';
import '../../providers/theme_provider.dart';
import 'package:provider/provider.dart';

class CarrierDirectoryScreen extends StatefulWidget {
  /// Set to true when embedded inside a TabBarView to suppress the
  /// inner Scaffold / AppBar (which would nest inside the parent Scaffold).
  final bool embedded;

  const CarrierDirectoryScreen({super.key, this.embedded = false});

  @override
  State<CarrierDirectoryScreen> createState() => _CarrierDirectoryScreenState();
}

class _CarrierDirectoryScreenState extends State<CarrierDirectoryScreen> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _carriers = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String? _error;

  // Filters
  final _searchCtrl = TextEditingController();
  String? _filterPais;
  String? _filterProvincia;
  String? _filterCategoria;
  bool? _filterKyc;   // null = all, true = verified, false = not verified
  bool? _filterActivo; // null = all

  // Distinct values for dropdown filters
  List<String> _paises = [];
  List<String> _categorias = [];

  @override
  void initState() {
    super.initState();
    _loadCarriers();
    _searchCtrl.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_applyFilters);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCarriers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Load carrier_carga drivers with their carrocerias
      final data = await _supabase
          .schema('muevete')
          .from('drivers')
          .select(
            'id, uuid, name, email, telefono, estado, kyc, image, categoria, '
            'mc_number, dot_number, pais, province, municipality, '
            'carrocerias(id, marca, modelo, matricula)',
          )
          .eq('tipo_usuario', 'carrier_carga')
          .order('name', ascending: true);

      final list = List<Map<String, dynamic>>.from(data as List);

      // Build distinct filter values
      final paises = <String>{};
      final provincias = <String>{};
      final categorias = <String>{};

      for (final c in list) {
        if (c['pais'] != null && (c['pais'] as String).isNotEmpty) {
          paises.add(c['pais'] as String);
        }
        if (c['province'] != null && (c['province'] as String).isNotEmpty) {
          provincias.add(c['province'] as String);
        }
        if (c['categoria'] != null && (c['categoria'] as String).isNotEmpty) {
          categorias.add(c['categoria'] as String);
        }
      }

      if (mounted) {
        setState(() {
          _carriers = list;
          _paises = paises.toList()..sort();
          _categorias = categorias.toList()..sort();
          _loading = false;
        });
        _applyFilters();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _applyFilters() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = _carriers.where((c) {
        // Name search
        final name = (c['name'] as String? ?? '').toLowerCase();
        if (query.isNotEmpty && !name.contains(query)) return false;

        // País
        if (_filterPais != null && c['pais'] != _filterPais) return false;

        // Provincia
        if (_filterProvincia != null && c['province'] != _filterProvincia) {
          return false;
        }

        // Categoría (vehicle type)
        if (_filterCategoria != null && c['categoria'] != _filterCategoria) {
          return false;
        }

        // KYC
        if (_filterKyc != null && c['kyc'] != _filterKyc) return false;

        // Activo
        if (_filterActivo != null && c['estado'] != _filterActivo) {
          return false;
        }

        return true;
      }).toList();
    });
  }

  List<String> _buildProvinciaList() {
    final source = _filterPais != null
        ? _carriers.where((c) => c['pais'] == _filterPais)
        : _carriers.cast<Map<String, dynamic>>();
    final set = source
        .map((c) => c['province'] as String?)
        .where((p) => p != null && p.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    set.sort();
    return set;
  }

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() {
      _filterPais = null;
      _filterProvincia = null;
      _filterCategoria = null;
      _filterKyc = null;
      _filterActivo = null;
    });
    _applyFilters();
  }

  bool get _hasActiveFilters =>
      _searchCtrl.text.isNotEmpty ||
      _filterPais != null ||
      _filterProvincia != null ||
      _filterCategoria != null ||
      _filterKyc != null ||
      _filterActivo != null;

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary = isDark ? Colors.white54 : Colors.grey[600]!;

    final body = Column(
      children: [
          // ── Search + filter bar ───────────────────────────────────────────
          Container(
            color: isDark ? AppTheme.darkCard : Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                // Action row (shown in embedded mode since there is no AppBar)
                if (widget.embedded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text(
                          'Directorio de Transportistas',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: textPrimary,
                          ),
                        ),
                        const Spacer(),
                        if (_hasActiveFilters)
                          TextButton.icon(
                            icon: const Icon(Icons.filter_alt_off, size: 16),
                            label: Text('Limpiar',
                                style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                            onPressed: _clearFilters,
                            style: TextButton.styleFrom(
                                foregroundColor: AppTheme.primaryColor,
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact),
                          ),
                        IconButton(
                          icon: Icon(Icons.refresh, color: textSecondary, size: 20),
                          onPressed: _loadCarriers,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                // Search field
                _SearchBar(
                  controller: _searchCtrl,
                  isDark: isDark,
                  hint: 'Buscar por nombre…',
                ),
                const SizedBox(height: 10),
                // Filter chips row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterDropdown<String>(
                        label: 'País',
                        value: _filterPais,
                        items: _paises,
                        isDark: isDark,
                        onChanged: (v) {
                          setState(() {
                            _filterPais = v;
                            // reset provincia when country changes
                            _filterProvincia = null;
                          });
                          _applyFilters();
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterDropdown<String>(
                        label: 'Provincia',
                        value: _filterProvincia,
                        items: _buildProvinciaList(),
                        isDark: isDark,
                        onChanged: (v) {
                          setState(() => _filterProvincia = v);
                          _applyFilters();
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterDropdown<String>(
                        label: 'Categoría',
                        value: _filterCategoria,
                        items: _categorias,
                        isDark: isDark,
                        onChanged: (v) {
                          setState(() => _filterCategoria = v);
                          _applyFilters();
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterToggle(
                        label: 'KYC',
                        value: _filterKyc,
                        trueLabel: 'Verificado',
                        falseLabel: 'Sin verificar',
                        isDark: isDark,
                        onChanged: (v) {
                          setState(() => _filterKyc = v);
                          _applyFilters();
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterToggle(
                        label: 'Estado',
                        value: _filterActivo,
                        trueLabel: 'Activo',
                        falseLabel: 'Inactivo',
                        isDark: isDark,
                        onChanged: (v) {
                          setState(() => _filterActivo = v);
                          _applyFilters();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Results count
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Text(
                  _loading
                      ? 'Cargando…'
                      : '${_filtered.length} transportista${_filtered.length == 1 ? '' : 's'}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorState(error: _error!, onRetry: _loadCarriers)
                    : _filtered.isEmpty
                        ? _EmptyState(hasFilters: _hasActiveFilters)
                        : RefreshIndicator(
                            onRefresh: _loadCarriers,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) => _CarrierCard(
                                carrier: _filtered[i],
                                isDark: isDark,
                                textPrimary: textPrimary,
                                textSecondary: textSecondary,
                              ),
                            ),
                          ),
          ),
        ],
    );

    if (widget.embedded) {
      return body;
    }
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        elevation: 0,
        title: Text(
          'Directorio de Transportistas',
          style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700, fontSize: 17, color: textPrimary),
        ),
        iconTheme: IconThemeData(color: textPrimary),
        actions: [
          if (_hasActiveFilters)
            TextButton.icon(
              icon: const Icon(Icons.filter_alt_off, size: 18),
              label: Text('Limpiar',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13)),
              onPressed: _clearFilters,
              style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor),
            ),
          IconButton(
            icon: Icon(Icons.refresh, color: textPrimary),
            onPressed: _loadCarriers,
          ),
        ],
      ),
      body: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carrier card
// ─────────────────────────────────────────────────────────────────────────────

class _CarrierCard extends StatefulWidget {
  final Map<String, dynamic> carrier;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;

  const _CarrierCard({
    required this.carrier,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  State<_CarrierCard> createState() => _CarrierCardState();
}

class _CarrierCardState extends State<_CarrierCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.carrier;
    final isDark = widget.isDark;
    final name = c['name'] as String? ?? 'Transportista';
    final kyc = c['kyc'] as bool? ?? false;
    final activo = c['estado'] as bool? ?? false;
    final pais = c['pais'] as String?;
    final province = c['province'] as String?;
    final municipality = c['municipality'] as String?;
    final categoria = c['categoria'] as String?;
    final mcNumber = c['mc_number'] as String?;
    final dotNumber = c['dot_number'] as String?;
    final telefono = c['telefono'] as String?;
    final email = c['email'] as String?;
    final imageUrl = c['image'] as String?;
    final carrocerias = List<Map<String, dynamic>>.from(
        (c['carrocerias'] as List? ?? []));

    final locationParts = [
      if (municipality != null && municipality.isNotEmpty) municipality,
      if (province != null && province.isNotEmpty) province,
      if (pais != null && pais.isNotEmpty) pais,
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : Colors.grey[200]!,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        children: [
          // Header row
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                    backgroundImage:
                        imageUrl != null ? NetworkImage(imageUrl) : null,
                    child: imageUrl == null
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryColor,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),

                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: widget.textPrimary,
                                ),
                              ),
                            ),
                            if (kyc)
                              Tooltip(
                                message: 'KYC Verificado',
                                child: Icon(Icons.verified,
                                    color: AppTheme.primaryColor, size: 18),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (locationParts.isNotEmpty)
                          Row(
                            children: [
                              Icon(Icons.place_outlined,
                                  size: 13, color: widget.textSecondary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  locationParts.join(', '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: widget.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 6),
                        // Badges row
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _Badge(
                              label: activo ? 'Activo' : 'Inactivo',
                              color: activo ? AppTheme.success : Colors.grey,
                            ),
                            if (categoria != null && categoria.isNotEmpty)
                              _Badge(
                                label: categoria,
                                color: AppTheme.primaryColor,
                              ),
                            if (carrocerias.isNotEmpty)
                              _Badge(
                                label:
                                    '${carrocerias.length} vehículo${carrocerias.length == 1 ? '' : 's'}',
                                color: Colors.indigo,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Expand arrow
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: widget.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // Expanded details
          if (_expanded) ...[
            Divider(
              height: 1,
              color: isDark ? AppTheme.darkBorder : Colors.grey[200],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Contact info
                  if (telefono != null && telefono.isNotEmpty)
                    _DetailRow(
                      icon: Icons.phone_outlined,
                      label: 'Teléfono',
                      value: telefono,
                      isDark: isDark,
                      textPrimary: widget.textPrimary,
                      textSecondary: widget.textSecondary,
                    ),
                  if (email != null && email.isNotEmpty)
                    _DetailRow(
                      icon: Icons.email_outlined,
                      label: 'Email',
                      value: email,
                      isDark: isDark,
                      textPrimary: widget.textPrimary,
                      textSecondary: widget.textSecondary,
                    ),
                  if (mcNumber != null && mcNumber.isNotEmpty)
                    _DetailRow(
                      icon: Icons.tag_outlined,
                      label: 'MC #',
                      value: mcNumber,
                      isDark: isDark,
                      textPrimary: widget.textPrimary,
                      textSecondary: widget.textSecondary,
                    ),
                  if (dotNumber != null && dotNumber.isNotEmpty)
                    _DetailRow(
                      icon: Icons.numbers_outlined,
                      label: 'DOT #',
                      value: dotNumber,
                      isDark: isDark,
                      textPrimary: widget.textPrimary,
                      textSecondary: widget.textSecondary,
                    ),

                  // Vehicles
                  if (carrocerias.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Vehículos',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: widget.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...carrocerias.map((v) {
                      final marca = v['marca'] as String? ?? '';
                      final modelo = v['modelo'] as String? ?? '';
                      final matricula = v['matricula'] as String? ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(Icons.local_shipping_outlined,
                                size: 16,
                                color: AppTheme.primaryColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                [
                                  if (marca.isNotEmpty) marca,
                                  if (modelo.isNotEmpty) modelo,
                                  if (matricula.isNotEmpty) '· $matricula',
                                ].join(' '),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: widget.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  final String hint;

  const _SearchBar(
      {required this.controller, required this.isDark, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkBg : Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? AppTheme.darkBorder : Colors.grey[300]!),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(Icons.search,
              size: 18,
              color: isDark ? Colors.white38 : Colors.grey[500]),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: isDark ? Colors.white38 : Colors.grey[500],
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              icon: Icon(Icons.clear,
                  size: 16,
                  color: isDark ? Colors.white38 : Colors.grey[400]),
              onPressed: controller.clear,
            ),
        ],
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final bool isDark;
  final ValueChanged<T?> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final active = value != null;
    return GestureDetector(
      onTap: items.isEmpty ? null : () => _showPicker(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.primaryColor.withValues(alpha: 0.15)
              : (isDark ? AppTheme.darkBg : Colors.grey[100]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? AppTheme.primaryColor
                : (isDark ? AppTheme.darkBorder : Colors.grey[300]!),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              active ? value.toString() : label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active
                    ? AppTheme.primaryColor
                    : (isDark ? Colors.white54 : Colors.grey[600]),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              active ? Icons.close : Icons.arrow_drop_down,
              size: 16,
              color: active
                  ? AppTheme.primaryColor
                  : (isDark ? Colors.white38 : Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    if (value != null) {
      onChanged(null);
      return;
    }
    showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PickerSheet<T>(
        label: label,
        items: items,
        isDark: isDark,
        onSelect: (v) {
          Navigator.pop(context);
          onChanged(v);
        },
      ),
    );
  }
}

class _FilterToggle extends StatelessWidget {
  final String label;
  final bool? value; // null=all, true=trueLabel, false=falseLabel
  final String trueLabel;
  final String falseLabel;
  final bool isDark;
  final ValueChanged<bool?> onChanged;

  const _FilterToggle({
    required this.label,
    required this.value,
    required this.trueLabel,
    required this.falseLabel,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    void cycle() {
      if (value == null) {
        onChanged(true);
      } else if (value == true) {
        onChanged(false);
      } else {
        onChanged(null);
      }
    }

    final active = value != null;
    final displayLabel =
        value == null ? label : (value! ? trueLabel : falseLabel);

    return GestureDetector(
      onTap: cycle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.primaryColor.withValues(alpha: 0.15)
              : (isDark ? AppTheme.darkBg : Colors.grey[100]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? AppTheme.primaryColor
                : (isDark ? AppTheme.darkBorder : Colors.grey[300]!),
          ),
        ),
        child: Text(
          displayLabel,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active
                ? AppTheme.primaryColor
                : (isDark ? Colors.white54 : Colors.grey[600]),
          ),
        ),
      ),
    );
  }
}

class _PickerSheet<T> extends StatelessWidget {
  final String label;
  final List<T> items;
  final bool isDark;
  final ValueChanged<T> onSelect;

  const _PickerSheet({
    required this.label,
    required this.items,
    required this.isDark,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Filtrar por $label',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: isDark ? AppTheme.darkBorder : Colors.grey[200],
              ),
              itemBuilder: (_, i) {
                return ListTile(
                  title: Text(
                    items[i].toString(),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  onTap: () => onSelect(items[i]),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: textSecondary),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: textSecondary),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: textPrimary,
                  fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppTheme.error, size: 48),
            const SizedBox(height: 12),
            Text(error,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(fontSize: 13)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasFilters;

  const _EmptyState({required this.hasFilters});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_shipping_outlined,
                size: 56, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              hasFilters
                  ? 'No hay transportistas con esos filtros'
                  : 'No hay transportistas registrados',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
