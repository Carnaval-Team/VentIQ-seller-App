import 'package:flutter/material.dart';

import '../money/venta_v1_envio.dart';
import '../theme/ventiq_home_theme.dart';

/// Netos ya fijados. Cambiar el cobro vuelve al detalle.
class CheckoutV1Grupos extends StatelessWidget {
  final List<GrupoCobro> grupos;
  final VoidCallback onCambiar;

  const CheckoutV1Grupos({
    super.key,
    required this.grupos,
    required this.onCambiar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Cobro por moneda', style: VentiqHomeTheme.tituloSeccion),
        const SizedBox(height: 8),
        if (grupos.isEmpty)
          const Text('No hay un cobro nativo para esta orden.')
        else
          for (final grupo in grupos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '${grupo.moneda} · medio ${grupo.medio ?? '-'} · ${grupo.neto} '
                '(equivalente ${grupo.cup} CUP)',
              ),
            ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onCambiar,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Cambiar en el detalle'),
        ),
      ],
    );
  }
}
