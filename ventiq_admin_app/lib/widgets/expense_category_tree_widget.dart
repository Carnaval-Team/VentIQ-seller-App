import 'package:flutter/material.dart';

class ExpenseCategoryTreeWidget extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final Set<String> selectedIds;
  final Function(Set<String>) onSelectionChanged;
  final String? title;

  const ExpenseCategoryTreeWidget({
    super.key,
    required this.categories,
    required this.selectedIds,
    required this.onSelectionChanged,
    this.title,
  });

  @override
  State<ExpenseCategoryTreeWidget> createState() => _ExpenseCategoryTreeWidgetState();
}

class _ExpenseCategoryTreeWidgetState extends State<ExpenseCategoryTreeWidget> {
  final Set<String> _expandedCategories = <String>{};
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.selectedIds);
  }

  @override
  void didUpdateWidget(ExpenseCategoryTreeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIds != widget.selectedIds) {
      _selectedIds = Set<String>.from(widget.selectedIds);
    }
  }

  void _toggleSelection(String id, Map<String, dynamic> item) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        
        // Si es una categoría, deseleccionar todas sus subcategorías
        if (item['type'] == 'category') {
          final children = item['children'] as List<Map<String, dynamic>>? ?? [];
          for (final child in children) {
            _selectedIds.remove(child['id']);
          }
        }
      } else {
        _selectedIds.add(id);
        
        // Si es una subcategoría, verificar si todas las subcategorías están seleccionadas
        // para seleccionar automáticamente la categoría padre
        if (item['type'] == 'subcategory') {
          final categoryId = 'cat_${item['category_id']}';
          final category = widget.categories.firstWhere(
            (cat) => cat['id'] == categoryId,
            orElse: () => <String, dynamic>{},
          );
          
          if (category.isNotEmpty) {
            final children = category['children'] as List<Map<String, dynamic>>? ?? [];
            final allChildrenSelected = children.every((child) => 
              _selectedIds.contains(child['id']) || child['id'] == id);
            
            if (allChildrenSelected) {
              _selectedIds.add(categoryId);
            }
          }
        }
        
        // Si es una categoría, seleccionar todas sus subcategorías
        if (item['type'] == 'category') {
          final children = item['children'] as List<Map<String, dynamic>>? ?? [];
          for (final child in children) {
            _selectedIds.add(child['id']);
          }
        }
      }
    });
    
    widget.onSelectionChanged(_selectedIds);
  }

  void _toggleExpansion(String categoryId) {
    setState(() {
      if (_expandedCategories.contains(categoryId)) {
        _expandedCategories.remove(categoryId);
      } else {
        _expandedCategories.add(categoryId);
      }
    });
  }

  bool _isCategoryPartiallySelected(Map<String, dynamic> category) {
    final children = category['children'] as List<Map<String, dynamic>>? ?? [];
    if (children.isEmpty) return false;
    
    final selectedChildren = children.where((child) => _selectedIds.contains(child['id'])).length;
    return selectedChildren > 0 && selectedChildren < children.length;
  }

  bool _isCategoryFullySelected(Map<String, dynamic> category) {
    final children = category['children'] as List<Map<String, dynamic>>? ?? [];
    if (children.isEmpty) return _selectedIds.contains(category['id']);
    
    return children.every((child) => _selectedIds.contains(child['id']));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.title != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Text(
                widget.title!,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: widget.categories.length,
              itemBuilder: (context, index) {
                final category = widget.categories[index];
                return _buildCategoryItem(category);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryItem(Map<String, dynamic> category) {
    final categoryId = category['id'] as String;
    final children = category['children'] as List<Map<String, dynamic>>? ?? [];
    final isExpanded = _expandedCategories.contains(categoryId);
    final isPartiallySelected = _isCategoryPartiallySelected(category);
    final isFullySelected = _isCategoryFullySelected(category);

    return Column(
      children: [
        InkWell(
          onTap: () => _toggleSelection(categoryId, category),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                if (children.isNotEmpty)
                  GestureDetector(
                    onTap: () => _toggleExpansion(categoryId),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        isExpanded ? Icons.expand_more : Icons.chevron_right,
                        size: 20,
                        color: Colors.grey[600],
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 28),
                
                Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isFullySelected || isPartiallySelected 
                          ? Theme.of(context).primaryColor 
                          : Colors.grey[400]!,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(3),
                    color: isFullySelected 
                        ? Theme.of(context).primaryColor 
                        : Colors.transparent,
                  ),
                  child: isFullySelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : isPartiallySelected
                          ? Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            )
                          : null,
                ),
                
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category['name'] ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isFullySelected || isPartiallySelected 
                              ? Theme.of(context).primaryColor 
                              : Colors.black87,
                        ),
                      ),
                      if (category['description'] != null && 
                          category['description'].toString().isNotEmpty)
                        Text(
                          category['description'],
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                
                if (children.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${children.length}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        
        if (isExpanded && children.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(left: 32),
            child: Column(
              children: children.map((child) => _buildSubcategoryItem(child)).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildSubcategoryItem(Map<String, dynamic> subcategory) {
    final subcategoryId = subcategory['id'] as String;
    final isSelected = _selectedIds.contains(subcategoryId);

    return InkWell(
      onTap: () => _toggleSelection(subcategoryId, subcategory),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected 
                      ? Theme.of(context).primaryColor 
                      : Colors.grey[400]!,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(3),
                color: isSelected 
                    ? Theme.of(context).primaryColor 
                    : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subcategory['name'] ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: isSelected 
                          ? Theme.of(context).primaryColor 
                          : Colors.black87,
                    ),
                  ),
                  if (subcategory['description'] != null && 
                      subcategory['description'].toString().isNotEmpty)
                    Text(
                      subcategory['description'],
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
