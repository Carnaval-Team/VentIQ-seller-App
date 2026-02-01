import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/ai_product_models.dart';
import '../services/ai_product_generation_service.dart';

class AiProductGeneratorSheet extends StatefulWidget {
  final VoidCallback? onProductsCreated;

  const AiProductGeneratorSheet({super.key, this.onProductsCreated});

  @override
  State<AiProductGeneratorSheet> createState() =>
      _AiProductGeneratorSheetState();
}

class _AiProductGeneratorSheetState extends State<AiProductGeneratorSheet> {
  final TextEditingController _promptController = TextEditingController();
  final AiProductGenerationService _generationService =
      AiProductGenerationService();

  ProductAiReferenceData? _referenceData;
  List<AiProductDraft> _drafts = [];
  bool _isLoadingReferences = true;
  bool _isGenerating = false;
  bool _isCreating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadReferenceData();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _loadReferenceData() async {
    setState(() {
      _isLoadingReferences = true;
      _errorMessage = null;
    });

    try {
      final data = await _generationService.loadReferenceData();
      if (!mounted) return;
      setState(() {
        _referenceData = data;
      });
    } catch (e, st) {
      print('$st');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error cargando datos base: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingReferences = false;
      });
    }
  }

  Future<void> _generatePreview() async {
    FocusScope.of(context).unfocus();

    final prompt = _promptController.text.trim();
    final validationError = _generationService.validatePrompt(prompt);
    if (validationError != null) {
      setState(() {
        _errorMessage = validationError;
        _drafts = [];
      });
      return;
    }

    final referenceData = _referenceData;
    if (referenceData == null) {
      setState(() {
        _errorMessage = 'No se cargaron las referencias necesarias.';
      });
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _drafts = [];
    });

    try {
      final drafts = await _generationService.generateDrafts(
        prompt: prompt,
        referenceData: referenceData,
      );
      if (!mounted) return;
      setState(() {
        _drafts = drafts;
      });
    } catch (e, st) {
      print('$st');

      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
      });
    }
  }

  Future<void> _createProducts() async {
    if (_drafts.isEmpty) {
      setState(() {
        _errorMessage = 'Genera productos antes de continuar.';
      });
      return;
    }

    final invalid = _drafts.where((draft) => !draft.isValid).toList();
    if (invalid.isNotEmpty) {
      setState(() {
        _errorMessage =
            'Completa los campos faltantes antes de generar en Supabase.';
      });
      return;
    }

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      final result = await _generationService.createProducts(_drafts);
      if (!mounted) return;

      if (result.createdCount == 0 && result.hasErrors) {
        setState(() {
          _errorMessage = result.errors.first;
          _isCreating = false;
        });
        return;
      }

      widget.onProductsCreated?.call();
      Navigator.pop(context, result);
    } catch (e, st) {
      print('$st');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error creando productos: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
      });
    }
  }

  void _removeDraft(String localId) {
    setState(() {
      _drafts = _drafts.where((draft) => draft.localId != localId).toList();
    });
  }

  Future<void> _editDraft(AiProductDraft draft) async {
    final referenceData = _referenceData;
    if (referenceData == null) return;

    final updated = await showModalBottomSheet<AiProductDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) =>
              _AiProductDraftEditor(draft: draft, referenceData: referenceData),
    );

    if (updated == null) {
      return;
    }

    setState(() {
      _drafts =
          _drafts
              .map((item) => item.localId == updated.localId ? updated : item)
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.98,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.auto_awesome, color: AppColors.primary),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Generar productos con IA',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Introduce el prompt para crear tus productos. La IA usara los IDs reales de categorias, subcategorias, presentaciones y unidades.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _promptController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Prompt de productos',
                        hintText:
                            'Ej: 6 productos para una cafeteria con cafe, dulces y bebidas frias',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            _isGenerating || _isLoadingReferences
                                ? null
                                : _generatePreview,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        icon:
                            _isGenerating
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Icon(Icons.preview),
                        label: Text(
                          _isGenerating
                              ? 'Generando vista previa...'
                              : 'Generar vista previa',
                        ),
                      ),
                    ),
                    if (_isLoadingReferences) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: const [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Cargando categorias, subcategorias y presentaciones...',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      _buildErrorBanner(_errorMessage!),
                    ],
                    const SizedBox(height: 20),
                    _buildPreviewSection(),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isCreating ? null : _createProducts,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                        ),
                        icon:
                            _isCreating
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Icon(Icons.cloud_upload),
                        label: Text(
                          _isCreating
                              ? 'Generando en Supabase...'
                              : 'Generar en Supabase',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPreviewSection() {
    if (_drafts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'La vista previa aparecera aqui una vez que generes productos.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vista previa',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ..._drafts.map(_buildDraftCard).toList(),
      ],
    );
  }

  Widget _buildDraftCard(AiProductDraft draft) {
    final referenceData = _referenceData;
    final missingFields = draft.getMissingFields();
    final categoryName =
        referenceData
            ?.findCategoryById(draft.categoryId)?['denominacion']
            ?.toString() ??
        'Sin categoria';
    final presentationName =
        referenceData
            ?.findPresentationById(draft.basePresentationId)?['denominacion']
            ?.toString() ??
        'Sin presentacion';
    final unitName =
        referenceData
            ?.findUnitById(draft.unidadMedidaId)?['abreviatura']
            ?.toString() ??
        (draft.unidadMedidaAbreviatura ?? 'Sin UM');
    final supplierName =
        referenceData
            ?.findSupplierById(draft.supplierId)?['denominacion']
            ?.toString();

    final subcategoryNames =
        referenceData == null
            ? <String>[]
            : draft.subcategoryIds
                .map(
                  (id) =>
                      referenceData.subcategories
                          .firstWhere(
                            (subcat) => subcat['id'] == id,
                            orElse: () => {},
                          )['denominacion']
                          ?.toString(),
                )
                .whereType<String>()
                .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              missingFields.isEmpty
                  ? Colors.grey.shade200
                  : Colors.orange.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  draft.denominacion,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (missingFields.isNotEmpty)
                const Icon(Icons.error_outline, color: Colors.orange, size: 18),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildInfoChip('SKU', draft.sku ?? 'Sin SKU'),
              _buildInfoChip(
                'Precio',
                draft.precioVenta != null
                    ? '\$${draft.precioVenta!.toStringAsFixed(2)}'
                    : 'Sin precio',
              ),
              _buildInfoChip(
                'Costo USD',
                draft.precioCostoUsd != null
                    ? '\$${draft.precioCostoUsd!.toStringAsFixed(2)}'
                    : 'Sin costo',
              ),
              _buildInfoChip('Categoria', categoryName),
              _buildInfoChip('Presentacion', presentationName),
              _buildInfoChip('UM', unitName),
              if (supplierName != null)
                _buildInfoChip('Proveedor', supplierName),
            ],
          ),
          if (subcategoryNames.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Subcategorias: ${subcategoryNames.join(', ')}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (missingFields.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Faltan: ${missingFields.join(', ')}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _editDraft(draft),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Editar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _removeDraft(draft.localId),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Quitar'),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _AiProductDraftEditor extends StatefulWidget {
  final AiProductDraft draft;
  final ProductAiReferenceData referenceData;

  const _AiProductDraftEditor({
    required this.draft,
    required this.referenceData,
  });

  @override
  State<_AiProductDraftEditor> createState() => _AiProductDraftEditorState();
}

class _AiProductDraftEditorState extends State<_AiProductDraftEditor> {
  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _priceController;
  late final TextEditingController _costUsdController;
  late final TextEditingController _cantidadPresentacionController;
  late final TextEditingController _cantidadUmController;

  int? _selectedCategoryId;
  List<int> _selectedSubcategoryIds = [];
  int? _selectedPresentationId;
  int? _selectedUnidadId;
  String? _selectedUnidadAbreviatura;
  int? _selectedSupplierId;

  bool _esVendible = true;
  bool _esComprable = true;
  bool _esInventariable = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.draft.denominacion);
    _skuController = TextEditingController(text: widget.draft.sku ?? '');
    _priceController = TextEditingController(
      text: widget.draft.precioVenta?.toStringAsFixed(2) ?? '',
    );
    _costUsdController = TextEditingController(
      text: widget.draft.precioCostoUsd?.toStringAsFixed(2) ?? '',
    );
    _cantidadPresentacionController = TextEditingController(
      text: widget.draft.cantidadPresentacion?.toString() ?? '1',
    );
    _cantidadUmController = TextEditingController(
      text: widget.draft.cantidadUm?.toString() ?? '1',
    );

    _selectedCategoryId = widget.draft.categoryId;
    _selectedSubcategoryIds = [...widget.draft.subcategoryIds];
    _selectedPresentationId = widget.draft.basePresentationId;
    _selectedUnidadId = widget.draft.unidadMedidaId;
    _selectedUnidadAbreviatura = widget.draft.unidadMedidaAbreviatura;
    _selectedSupplierId = widget.draft.supplierId;

    _esVendible = widget.draft.esVendible;
    _esComprable = widget.draft.esComprable;
    _esInventariable = widget.draft.esInventariable;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _priceController.dispose();
    _costUsdController.dispose();
    _cantidadPresentacionController.dispose();
    _cantidadUmController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _availableSubcategories {
    final categoryId = _selectedCategoryId;
    if (categoryId == null) return [];
    return widget.referenceData.subcategoriesForCategory(categoryId);
  }

  List<Map<String, dynamic>> get _availableUnits {
    final unitsMap = <String, Map<String, dynamic>>{};
    for (final unit in widget.referenceData.units) {
      final key = (unit['abreviatura'] ?? '').toString();
      if (key.isNotEmpty) {
        unitsMap[key] = unit;
      }
    }
    return unitsMap.values.toList();
  }

  void _saveDraft() {
    final precio = double.tryParse(
      _priceController.text.trim().replaceAll(',', '.'),
    );
    final costoUsd = double.tryParse(
      _costUsdController.text.trim().replaceAll(',', '.'),
    );
    final cantidadPresentacion = double.tryParse(
      _cantidadPresentacionController.text.trim().replaceAll(',', '.'),
    );
    final cantidadUm = double.tryParse(
      _cantidadUmController.text.trim().replaceAll(',', '.'),
    );

    final updated = widget.draft.copyWith(
      denominacion: _nameController.text.trim(),
      sku: _skuController.text.trim(),
      precioVenta: precio,
      precioCostoUsd: costoUsd,
      categoryId: _selectedCategoryId,
      subcategoryIds: _selectedSubcategoryIds,
      basePresentationId: _selectedPresentationId,
      cantidadPresentacion: cantidadPresentacion,
      unidadMedidaId: _selectedUnidadId,
      unidadMedidaAbreviatura: _selectedUnidadAbreviatura,
      cantidadUm: cantidadUm,
      supplierId: _selectedSupplierId,
      esVendible: _esVendible,
      esComprable: _esComprable,
      esInventariable: _esInventariable,
    );

    Navigator.pop(context, updated);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    const Text(
                      'Editar producto',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del producto',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _skuController,
                            decoration: const InputDecoration(
                              labelText: 'SKU',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _priceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Precio venta',
                              prefixText: '\$ ',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _costUsdController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Costo USD',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      value: _selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'Categoria',
                        border: OutlineInputBorder(),
                      ),
                      items:
                          widget.referenceData.categories.map((category) {
                            return DropdownMenuItem<int?>(
                              value: category['id'],
                              child: Text(category['denominacion'] ?? ''),
                            );
                          }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCategoryId = value;
                          _selectedSubcategoryIds = [];
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_selectedCategoryId == null)
                      const Text(
                        'Selecciona una categoria para ver subcategorias.',
                        style: TextStyle(color: AppColors.textSecondary),
                      )
                    else if (_availableSubcategories.isEmpty)
                      const Text(
                        'No hay subcategorias para esta categoria.',
                        style: TextStyle(color: AppColors.textSecondary),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            _availableSubcategories.map((subcat) {
                              final id = subcat['id'] as int?;
                              final isSelected =
                                  id != null &&
                                  _selectedSubcategoryIds.contains(id);
                              return FilterChip(
                                label: Text(subcat['denominacion'] ?? ''),
                                selected: isSelected,
                                onSelected: (selected) {
                                  if (id == null) return;
                                  setState(() {
                                    if (selected) {
                                      _selectedSubcategoryIds.add(id);
                                    } else {
                                      _selectedSubcategoryIds.remove(id);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int?>(
                            value: _selectedPresentationId,
                            decoration: const InputDecoration(
                              labelText: 'Presentacion base',
                              border: OutlineInputBorder(),
                            ),
                            items:
                                widget.referenceData.presentations.map((item) {
                                  return DropdownMenuItem<int?>(
                                    value: item['id'],
                                    child: Text(item['denominacion'] ?? ''),
                                  );
                                }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedPresentationId = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _cantidadPresentacionController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Cantidad',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int?>(
                            value: _selectedUnidadId,
                            decoration: const InputDecoration(
                              labelText: 'Unidad de medida',
                              border: OutlineInputBorder(),
                            ),
                            items:
                                _availableUnits.map((item) {
                                  return DropdownMenuItem<int?>(
                                    value: item['id'],
                                    child: Text(
                                      '${item['denominacion']} (${item['abreviatura']})',
                                    ),
                                  );
                                }).toList(),
                            onChanged: (value) {
                              final selected = _availableUnits.firstWhere(
                                (unit) => unit['id'] == value,
                                orElse: () => <String, dynamic>{},
                              );
                              setState(() {
                                _selectedUnidadId = value;
                                _selectedUnidadAbreviatura =
                                    selected['abreviatura']?.toString();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _cantidadUmController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Cantidad UM',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      value: _selectedSupplierId,
                      decoration: const InputDecoration(
                        labelText: 'Proveedor',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Sin proveedor'),
                        ),
                        ...widget.referenceData.suppliers.map((supplier) {
                          return DropdownMenuItem<int?>(
                            value: supplier['id'],
                            child: Text(supplier['denominacion'] ?? ''),
                          );
                        }).toList(),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedSupplierId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Es vendible'),
                      value: _esVendible,
                      onChanged: (value) {
                        setState(() {
                          _esVendible = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Es comprable'),
                      value: _esComprable,
                      onChanged: (value) {
                        setState(() {
                          _esComprable = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Es inventariable'),
                      value: _esInventariable,
                      onChanged: (value) {
                        setState(() {
                          _esInventariable = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saveDraft,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Guardar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
