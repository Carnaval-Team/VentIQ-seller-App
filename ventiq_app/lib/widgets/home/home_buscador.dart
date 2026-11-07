import 'package:flutter/material.dart';

import '../../theme/ventiq_home_theme.dart';

/// Buscador del Home: card blanca con el campo dentro, siempre visible.
///
/// Es un widget con API pública y no un método privado de la pantalla, porque
/// el Home viejo tenía **dos copias** de esto (una en la versión móvil y otra
/// en la web) con diferencias accidentales —entre ellas que la web no validaba
/// stock al tocar un resultado—. Una sola implementación evita que vuelvan a
/// separarse.
///
/// Usa `ValueListenableBuilder` sobre el controlador para decidir si muestra el
/// botón de limpiar, así no obliga a la pantalla a reconstruirse en cada tecla.
class HomeBuscador extends StatelessWidget {
  const HomeBuscador({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onLimpiar,
    this.onAbrirFiltros,
    this.filtrosActivos = 0,
    this.hint = 'Buscar producto, categoría o SKU…',
    this.focusNode,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onLimpiar;

  /// `null` = sin botón de filtros.
  final VoidCallback? onAbrirFiltros;

  /// Cuántos filtros hay puestos. Con 0 el icono va limpio.
  final int filtrosActivos;

  final String hint;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: VentiqHomeTheme.card,
        borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusBlock),
        border: Border.all(color: VentiqHomeTheme.border),
        boxShadow: VentiqHomeTheme.shadowBuscador,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: VentiqHomeTheme.surface,
          borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusField),
          border: Border.all(color: VentiqHomeTheme.border),
        ),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (BuildContext context, TextEditingValue valor, _) {
            final bool hayTexto = valor.text.trim().isNotEmpty;

            return TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              textAlignVertical: TextAlignVertical.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: VentiqHomeTheme.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: VentiqHomeTheme.textSecondary,
                  fontSize: 12.5,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: VentiqHomeTheme.primary,
                  size: 21,
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (hayTexto)
                      IconButton(
                        tooltip: 'Limpiar',
                        onPressed: onLimpiar,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: VentiqHomeTheme.textSecondary,
                          size: 19,
                        ),
                      ),
                    if (onAbrirFiltros != null)
                      IconButton(
                        tooltip: 'Filtros avanzados',
                        onPressed: onAbrirFiltros,
                        icon: filtrosActivos > 0
                            ? Badge.count(
                                count: filtrosActivos,
                                backgroundColor: VentiqHomeTheme.accent,
                                child: const Icon(
                                  Icons.tune_rounded,
                                  color: VentiqHomeTheme.primary,
                                  size: 20,
                                ),
                              )
                            : const Icon(
                                Icons.tune_rounded,
                                color: VentiqHomeTheme.primary,
                                size: 20,
                              ),
                      ),
                  ],
                ),
                filled: true,
                fillColor: Colors.transparent,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            );
          },
        ),
      ),
    );
  }
}
