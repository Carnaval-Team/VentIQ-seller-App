import 'package:flutter/material.dart';
import '../config/app_colors.dart';

class ConversionInfoWidget extends StatelessWidget {
  final List<Map<String, dynamic>> conversions;
  final bool showDetails;

  const ConversionInfoWidget({
    Key? key,
    required this.conversions,
    this.showDetails = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Validación más robusta
    if (conversions.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final hasConversions = conversions.any((c) => 
      c != null && 
      c is Map<String, dynamic> && 
      c['conversion_applied'] == true
    );
    
    if (!hasConversions) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.transform,
                color: Colors.orange.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Conversiones Aplicadas',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (showDetails) ...[
            const SizedBox(height: 8),
            ...conversions
                .where((c) => 
                  c != null && 
                  c is Map<String, dynamic> && 
                  c['conversion_applied'] == true
                )
                .map((conversion) => _buildConversionItem(conversion)),
          ],
        ],
      ),
    );
  }

  Widget _buildConversionItem(Map<String, dynamic> conversion) {
  // Validaciones adicionales para evitar errores
  final cantidadOriginal = conversion['cantidad_original']?.toString() ?? '0';
  final cantidad = conversion['cantidad']?.toString() ?? '0';
  
  // Obtener información de presentaciones
  final presentacionOriginal = conversion['presentacion_original_info'];
  final presentacionFinal = conversion['presentation_info'];
  
  String presentacionOriginalText = 'presentación';
  String presentacionFinalText = 'presentación base';
  
  if (presentacionOriginal != null && presentacionOriginal['denominacion'] != null) {
    presentacionOriginalText = presentacionOriginal['denominacion'];
  }
  
  if (presentacionFinal != null && presentacionFinal['denominacion'] != null) {
    presentacionFinalText = presentacionFinal['denominacion'];
  }
  
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        const SizedBox(width: 28), // Alineación con el icono
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.black87, fontSize: 12),
              children: [
                TextSpan(
                  text: '$cantidadOriginal $presentacionOriginalText',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' → '),
                TextSpan(
                  text: '$cantidad $presentacionFinalText',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
}