import 'package:flutter/material.dart';
import '../models/variant.dart';
import '../models/product.dart';
import '../services/variant_service.dart';
import '../config/app_colors.dart';

class VariantsTabView extends StatefulWidget {
  const VariantsTabView({super.key});

  @override
  State<VariantsTabView> createState() => _VariantsTabViewState();
}

class _VariantsTabViewState extends State<VariantsTabView> {
  List<Variant> _variants = [];
  bool _isLoading = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Map<int, List<Map<String, dynamic>>> _variantSubcategoriesCache = {};

  @override
  void initState() {
    super.initState();
    _loadVariants();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadVariants() async {
    setState(() => _isLoading = true);
    
    try {
      final variants = await VariantService.getVariants();
      setState(() {
        _variants = variants;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar variantes: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<Variant> get _filteredVariants {
    if (_searchQuery.isEmpty) return _variants;
    
    return _variants.where((variant) {
      return variant.denominacion.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             (variant.descripcion?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
    }).toList();
  }

  Future<void> _showCreateVariantDialog() async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear Nueva Variante'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre de la variante',
                hintText: 'Ej: Color, Talla, Material',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                hintText: 'Descripción opcional',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('El nombre es requerido')),
                );
                return;
              }
              
              try {
                final variant = await VariantService.createVariant({
                  'denominacion': nameController.text.trim(),
                  'label': nameController.text.trim().toLowerCase().replaceAll(' ', '_'),
                  'descripcion': descriptionController.text.trim(),
                });
                
                if (variant != null) {
                  Navigator.pop(context, true);
                } else {
                  throw Exception('No se pudo crear la variante');
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    
    if (result == true) {
      _loadVariants();
    }
  }

  Future<void> _showEditVariantDialog(Variant variant) async {
    final TextEditingController nameController = TextEditingController(text: variant.denominacion);
    final TextEditingController descriptionController = TextEditingController(text: variant.descripcion);
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Variante'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre de la variante',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Descripción',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('El nombre es requerido')),
                );
                return;
              }
              
              try {
                final success = await VariantService.updateVariant(
                  variant.id.toString(),
                  {
                    'denominacion': nameController.text.trim(),
                    'descripcion': descriptionController.text.trim(),
                  },
                );
                
                if (success) {
                  Navigator.pop(context, true);
                } else {
                  throw Exception('No se pudo actualizar la variante');
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    
    if (result == true) {
      _loadVariants();
    }
  }

  Future<void> _deleteVariant(Variant variant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Variante'),
        content: Text('¿Estás seguro de que deseas eliminar "${variant.denominacion}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await VariantService.deleteVariant(variant.id);
        if (success) {
          _loadVariants();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Variante eliminada exitosamente')),
            );
          }
        } else {
          throw Exception('No se pudo eliminar la variante');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar: $e')),
          );
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> _getVariantSubcategories(int variantId) async {
    if (_variantSubcategoriesCache.containsKey(variantId)) {
      return _variantSubcategoriesCache[variantId]!;
    }
    
    try {
      final subcategories = await VariantService.getSubcategoriesByVariant(variantId);
      _variantSubcategoriesCache[variantId] = subcategories;
      return subcategories;
    } catch (e) {
      print('Error loading subcategories for variant $variantId: $e');
      return [];
    }
  }

  void _refreshVariantSubcategories(int variantId) {
    _variantSubcategoriesCache.remove(variantId);
  }

  Future<void> _showSubcategoriesDialog(Variant variant) async {
    final subcategories = await _getVariantSubcategories(variant.id);
    
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => _SubcategoriesDialog(
          variant: variant,
          subcategories: subcategories,
          onSubcategoriesChanged: () => _refreshVariantSubcategories(variant.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Search and Add Button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Buscar variantes...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              icon: const Icon(Icons.clear),
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _showCreateVariantDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva Variante'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: AppColors.primary),
                        SizedBox(height: 16),
                        Text('Cargando variantes...'),
                      ],
                    ),
                  )
                : _filteredVariants.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.tune, size: 64, color: AppColors.textSecondary),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty 
                                  ? 'No hay variantes configuradas'
                                  : 'No se encontraron variantes',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Las variantes te permiten organizar productos por características como color, talla, etc.'
                                  : 'Intenta con otros términos de búsqueda',
                              style: const TextStyle(color: AppColors.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                            if (_searchQuery.isEmpty) ...[
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: _showCreateVariantDialog,
                                icon: const Icon(Icons.add),
                                label: const Text('Crear Primera Variante'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadVariants,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredVariants.length,
                          itemBuilder: (context, index) {
                            final variant = _filteredVariants[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.primary.withOpacity(0.1),
                                  child: const Icon(Icons.tune, color: AppColors.primary),
                                ),
                                title: Text(
                                  variant.denominacion,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (variant.descripcion?.isNotEmpty == true) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        variant.descripcion!,
                                        style: const TextStyle(color: AppColors.textSecondary),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    FutureBuilder<List<Map<String, dynamic>>>(
                                      future: _getVariantSubcategories(variant.id),
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState == ConnectionState.waiting) {
                                          return const Text(
                                            'Cargando subcategorías...',
                                            style: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                            ),
                                          );
                                        }
                                        
                                        final subcategories = snapshot.data ?? [];
                                        return Text(
                                          '${subcategories.length} subcategoría${subcategories.length != 1 ? 's' : ''} configurada${subcategories.length != 1 ? 's' : ''}',
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'subcategories':
                                        _showSubcategoriesDialog(variant);
                                        break;
                                      case 'edit':
                                        _showEditVariantDialog(variant);
                                        break;
                                      case 'delete':
                                        _deleteVariant(variant);
                                        break;
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'subcategories',
                                      child: ListTile(
                                        leading: Icon(Icons.category),
                                        title: Text('Gestionar Subcategorías'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: ListTile(
                                        leading: Icon(Icons.edit),
                                        title: Text('Editar'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: ListTile(
                                        leading: Icon(Icons.delete, color: Colors.red),
                                        title: Text('Eliminar', style: TextStyle(color: Colors.red)),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () => _showSubcategoriesDialog(variant),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _SubcategoriesDialog extends StatefulWidget {
  final Variant variant;
  final List<Map<String, dynamic>> subcategories;
  final VoidCallback? onSubcategoriesChanged;

  const _SubcategoriesDialog({
    required this.variant,
    required this.subcategories,
    this.onSubcategoriesChanged,
  });

  @override
  State<_SubcategoriesDialog> createState() => _SubcategoriesDialogState();
}

class _SubcategoriesDialogState extends State<_SubcategoriesDialog> {
  List<Map<String, dynamic>> _currentSubcategories = [];
  bool _isLoading = false;
  Map<int, int> _productCounts = {}; // Cache for product counts per subcategory
  Map<int, List<Product>> _subcategoryProducts = {}; // Cache for products per subcategory
  Map<int, bool> _expandedSubcategories = {}; // Track which subcategories are expanded

  @override
  void initState() {
    super.initState();
    _currentSubcategories = List.from(widget.subcategories);
    _loadProductCounts();
  }

  void _loadProductCounts() async {
    for (final subcategory in _currentSubcategories) {
      final subcategoryId = subcategory['id'] as int;
      try {
        final count = await VariantService.getProductCountByVariantAndSubcategory(
          widget.variant.id, 
          subcategoryId
        );
        if (mounted) {
          setState(() {
            _productCounts[subcategoryId] = count;
          });
        }
      } catch (e) {
        print('Error loading product count for subcategory $subcategoryId: $e');
      }
    }
  }

  Future<void> _loadProductsForSubcategory(int subcategoryId) async {
    if (_subcategoryProducts.containsKey(subcategoryId)) return; // Already loaded

    try {
      final products = await VariantService.getProductsByVariantAndSubcategory(
        widget.variant.id, 
        subcategoryId
      );
      if (mounted) {
        setState(() {
          _subcategoryProducts[subcategoryId] = products;
        });
      }
    } catch (e) {
      print('Error loading products for subcategory $subcategoryId: $e');
    }
  }

  void _toggleSubcategoryExpansion(int subcategoryId) async {
    final isExpanded = _expandedSubcategories[subcategoryId] ?? false;
    
    if (!isExpanded) {
      // Load products when expanding
      await _loadProductsForSubcategory(subcategoryId);
    }
    
    setState(() {
      _expandedSubcategories[subcategoryId] = !isExpanded;
    });
  }

  Future<void> _showAddSubcategoryDialog() async {
    // First, let user select a category
    final categories = await VariantService.getCategories();
    
    if (categories.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay categorías disponibles')),
        );
      }
      return;
    }

    // Show category selection dialog
    final selectedCategory = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleccionar Categoría'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.category),
                  title: Text(category['denominacion'] ?? ''),
                  subtitle: Text(category['descripcion'] ?? ''),
                  onTap: () => Navigator.of(context).pop(category),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (selectedCategory == null) return;

    // Debug: Print selected category info
    print('DEBUG: Selected category: ${selectedCategory['denominacion']} (ID: ${selectedCategory['id']})');

    // Now get subcategories for the selected category
    final categorySubcategories = await VariantService.getSubcategoriesByCategory(
      selectedCategory['id'], 
      categoryName: selectedCategory['denominacion']
    );
    
    // Debug: Print fetched subcategories
    print('DEBUG: Fetched ${categorySubcategories.length} subcategories for category ${selectedCategory['id']}');
    for (var sub in categorySubcategories) {
      print('DEBUG: Subcategory: ${sub['denominacion']} (ID: ${sub['id']})');
    }
    
    // Filter out subcategories already assigned to this variant
    final availableSubcategories = categorySubcategories.where((sub) {
      return !_currentSubcategories.any((current) => current['id'] == sub['id']);
    }).toList();

    // Debug: Print filtering results
    print('DEBUG: Current variant subcategories: ${_currentSubcategories.length}');
    print('DEBUG: Available subcategories after filtering: ${availableSubcategories.length}');

    if (availableSubcategories.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No hay subcategorías disponibles en ${selectedCategory['denominacion']}')),
        );
      }
      return;
    }

    // Show subcategory selection dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Subcategorías - ${selectedCategory['denominacion']}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: availableSubcategories.length,
            itemBuilder: (context, index) {
              final subcategory = availableSubcategories[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.subdirectory_arrow_right),
                  title: Text(subcategory['denominacion'] ?? ''),
                  subtitle: Text('${subcategory['categoria_nombre']} > ${subcategory['denominacion']}'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    
                    // Add subcategory to variant
                    final success = await VariantService.createVariantSubcategoryRelation(
                      widget.variant.id,
                      subcategory['id'],
                    );
                    
                    if (success) {
                      setState(() {
                        _currentSubcategories.add(subcategory);
                      });
                      
                      // Refresh parent cache
                      if (widget.onSubcategoriesChanged != null) {
                        widget.onSubcategoriesChanged!();
                      }
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Subcategoría "${subcategory['denominacion']}" agregada exitosamente')),
                        );
                      }
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Error al agregar subcategoría')),
                        );
                      }
                    }
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _addSubcategoryRelation(Map<String, dynamic> subcategory) async {
    setState(() => _isLoading = true);
    
    try {
      final success = await VariantService.createVariantSubcategoryRelation(
        widget.variant.id,
        subcategory['id'],
      );
      
      if (success) {
        setState(() {
          _currentSubcategories.add({
            ...subcategory,
            'hierarchy': '${subcategory['categoria_nombre']} > ${subcategory['denominacion']}',
          });
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Subcategoría agregada exitosamente')),
          );
        }
        
        widget.onSubcategoriesChanged?.call();
      } else {
        throw Exception('No se pudo crear la relación');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al agregar subcategoría: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _removeSubcategoryRelation(Map<String, dynamic> subcategory) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Relación'),
        content: Text(
          '¿Estás seguro de que deseas eliminar la relación con "${subcategory['denominacion']}"?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    
    try {
      final subcategoryId = subcategory['id'] ?? 0;
      
      // Use the new service method with proper validation
      await VariantService.removeVariantSubcategoryRelation(
        widget.variant.id, 
        subcategoryId
      );
      
      // Only remove from UI if deletion was successful
      setState(() {
        _currentSubcategories.removeWhere((item) => item['id'] == subcategoryId);
        // Also clear any cached product data for this subcategory
        _productCounts.remove(subcategoryId);
        _subcategoryProducts.remove(subcategoryId);
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Relación eliminada exitosamente')),
        );
      }
      
      widget.onSubcategoriesChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text('Subcategorías de ${widget.variant.denominacion}'),
          ),
          IconButton(
            onPressed: _isLoading ? null : _showAddSubcategoryDialog,
            icon: const Icon(Icons.add, color: Colors.green),
            tooltip: 'Agregar subcategoría',
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text('Procesando...'),
                  ],
                ),
              )
            : _currentSubcategories.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.category_outlined, size: 64, color: AppColors.textSecondary),
                        const SizedBox(height: 16),
                        const Text('No hay subcategorías configuradas'),
                        const SizedBox(height: 8),
                        const Text(
                          'Esta variante no tiene subcategorías asignadas',
                          style: TextStyle(color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _showAddSubcategoryDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar Subcategoría'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _currentSubcategories.length,
                    itemBuilder: (context, index) {
                      final subcategory = _currentSubcategories[index];
                      final subcategoryId = subcategory['id'] ?? 0;
                      final isExpanded = _expandedSubcategories[subcategoryId] ?? false;
                      final productCount = _productCounts[subcategoryId] ?? 0;
                      final products = _subcategoryProducts[subcategoryId] ?? [];
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          children: [
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.orange.withOpacity(0.1),
                                child: const Icon(Icons.category, color: Colors.orange),
                              ),
                              title: Text(
                                subcategory['denominacion'] ?? subcategory['subcategoria_nombre'] ?? 'Sin nombre',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Categoría: ${subcategory['categoria_nombre'] ?? subcategory['denominacion_categoria'] ?? 'Sin categoría'}',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (subcategory['hierarchy'] != null)
                                    Text(
                                      subcategory['hierarchy'],
                                      style: const TextStyle(
                                        color: Colors.orange,
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.blue.withOpacity(0.3),
                                          ),
                                        ),
                                        child: Text(
                                          '$productCount productos',
                                          style: const TextStyle(
                                            color: Colors.blue,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      if (productCount > 0) ...[
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: () => _toggleSubcategoryExpansion(subcategoryId),
                                          child: Text(
                                            isExpanded ? 'Ocultar' : 'Ver productos',
                                            style: TextStyle(
                                              color: Colors.orange,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              decoration: TextDecoration.underline,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (productCount > 0)
                                    IconButton(
                                      onPressed: () => _toggleSubcategoryExpansion(subcategoryId),
                                      icon: Icon(
                                        isExpanded ? Icons.expand_less : Icons.expand_more,
                                        color: Colors.orange,
                                      ),
                                      tooltip: isExpanded ? 'Ocultar productos' : 'Ver productos',
                                    ),
                                  IconButton(
                                    onPressed: () => _removeSubcategoryRelation(subcategory),
                                    icon: const Icon(Icons.remove_circle, color: Colors.red),
                                    tooltip: 'Eliminar relación',
                                  ),
                                ],
                              ),
                            ),
                            if (isExpanded && productCount > 0)
                              Container(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Divider(),
                                    Text(
                                      'Productos afectados ($productCount):',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (products.isEmpty)
                                      const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(16.0),
                                          child: CircularProgressIndicator(
                                            color: Colors.orange,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    else
                                      ListView.separated(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        itemCount: products.length,
                                        separatorBuilder: (context, index) => const SizedBox(height: 4),
                                        itemBuilder: (context, productIndex) {
                                          final product = products[productIndex];
                                          return Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.withOpacity(0.05),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.grey.withOpacity(0.2),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                CircleAvatar(
                                                  radius: 16,
                                                  backgroundColor: AppColors.primary.withOpacity(0.1),
                                                  child: const Icon(
                                                    Icons.inventory,
                                                    color: AppColors.primary,
                                                    size: 16,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        product.denominacion,
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Row(
                                                        children: [
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                            decoration: BoxDecoration(
                                                              color: AppColors.primary.withOpacity(0.1),
                                                              borderRadius: BorderRadius.circular(8),
                                                            ),
                                                            child: Text(
                                                              product.sku,
                                                              style: const TextStyle(
                                                                color: AppColors.primary,
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.w500,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(width: 8),
                                                          Text(
                                                            '\$${product.precioVenta.toStringAsFixed(2)}',
                                                            style: const TextStyle(
                                                              color: AppColors.textSecondary,
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.w500,
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
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
