import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';

/// Shared filter chrome used by shipper, carrier and dispatcher boards.
class FilterPanelContainer extends StatelessWidget {
  final bool isDark;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const FilterPanelContainer({
    super.key,
    required this.isDark,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 12),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : const Color(0xFFF4F6FA),
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppTheme.darkBorder : Colors.grey.shade200,
          ),
        ),
      ),
      child: child,
    );
  }
}

class FilterToolbar extends StatelessWidget {
  final bool isDark;
  final String summary;
  final bool expanded;
  final bool hasActiveFilters;
  final VoidCallback onToggle;
  final VoidCallback? onClear;

  const FilterToolbar({
    super.key,
    required this.isDark,
    required this.summary,
    required this.expanded,
    required this.hasActiveFilters,
    required this.onToggle,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? AppTheme.darkCard : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              summary,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
          ),
          if (hasActiveFilters && onClear != null)
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear, size: 14),
              label: const Text('Limpiar', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.error,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
          Material(
            color: hasActiveFilters
                ? AppTheme.primaryColor.withValues(alpha: 0.12)
                : (isDark ? Colors.white10 : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(10),
            child: IconButton(
              onPressed: onToggle,
              tooltip: 'Filtros',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                expanded ? Icons.filter_list_off_rounded : Icons.tune_rounded,
                color: hasActiveFilters
                    ? AppTheme.primaryColor
                    : (isDark ? Colors.white54 : Colors.grey[600]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SharedFilterField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool isDark;
  final VoidCallback onChanged;
  final IconData? icon;

  const SharedFilterField({
    super.key,
    required this.controller,
    required this.label,
    required this.isDark,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      style: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        color: isDark ? Colors.white : const Color(0xFF1A1D27),
      ),
      decoration: _sharedDecoration(
        isDark: isDark,
        label: label,
        icon: icon ?? Icons.search,
      ),
    );
  }
}

class SharedFilterDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final bool isDark;
  final ValueChanged<T?> onChanged;
  final IconData? icon;

  const SharedFilterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.isDark,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      items: items,
      onChanged: onChanged,
      hint: Text(
        'Todos',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          color: isDark ? Colors.white38 : Colors.grey[400],
        ),
      ),
      dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        color: isDark ? Colors.white : const Color(0xFF1A1D27),
      ),
      decoration: _sharedDecoration(
        isDark: isDark,
        label: label,
        icon: icon ?? Icons.filter_alt_outlined,
      ),
    );
  }
}

class SharedFilterChip extends StatelessWidget {
  final String label;
  final bool? value;
  final ValueChanged<bool?> onChanged;
  final bool isDark;

  const SharedFilterChip({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == true;
    return FilterChip(
      label: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected
              ? AppTheme.primaryColor
              : (isDark ? Colors.white70 : Colors.grey[700]),
        ),
      ),
      selected: selected,
      onSelected: (v) => onChanged(v ? true : null),
      selectedColor: AppTheme.primaryColor.withValues(alpha: 0.15),
      backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
      checkmarkColor: AppTheme.primaryColor,
      side: BorderSide(
        color: selected
            ? AppTheme.primaryColor.withValues(alpha: 0.45)
            : (isDark ? AppTheme.darkBorder : Colors.grey.shade300),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      visualDensity: VisualDensity.compact,
    );
  }
}

InputDecoration _sharedDecoration({
  required bool isDark,
  required String label,
  required IconData icon,
}) {
  return InputDecoration(
    labelText: label,
    isDense: true,
    filled: true,
    fillColor: isDark ? AppTheme.darkCard : Colors.white,
    prefixIcon: Icon(icon, size: 18),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: isDark ? AppTheme.darkBorder : Colors.grey.shade300,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.4),
    ),
  );
}
