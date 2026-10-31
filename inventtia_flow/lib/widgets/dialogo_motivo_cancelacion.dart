import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../utils/motivo_cancelacion.dart';

/// Diálogo que pide el **motivo de la cancelación** antes de cancelar una
/// reserva (punto 2 del plan, §3.1).
///
/// Devuelve el motivo ya recortado (`String`), o `null` si la persona cierra o
/// pulsa «No».
///
/// * `obligatorio: true` (admin, vendedor y staff): «Sí, cancelar» está
///   **deshabilitado** hasta que el motivo sea válido ([validarMotivo]). El
///   servidor también lo exige; esto solo evita el viaje en balde.
/// * `obligatorio: false` (cliente): el campo es opcional y se puede confirmar
///   vacío — en ese caso devuelve `''`, que el llamador traduce a «sin motivo».
///   Si se escribe algo, tiene que ser válido igualmente: un «x» no ayuda a
///   nadie.
///
/// IMPORTANTE (plan §3.1): hay que abrir este diálogo **antes** de poner la
/// pantalla en estado de carga (`setState(_loading = true)`); si no, el
/// `showDialog` se queda esperando mientras la UI muestra el spinner y el
/// resultado se pierde.
Future<String?> dialogoMotivoCancelacion(
  BuildContext context, {
  required String titulo,
  required String detalle,
  bool obligatorio = true,
  String? motivoInicial,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _DialogoMotivoCancelacion(
      titulo: titulo,
      detalle: detalle,
      obligatorio: obligatorio,
      motivoInicial: motivoInicial,
    ),
  );
}

class _DialogoMotivoCancelacion extends StatefulWidget {
  final String titulo;
  final String detalle;
  final bool obligatorio;
  final String? motivoInicial;

  const _DialogoMotivoCancelacion({
    required this.titulo,
    required this.detalle,
    required this.obligatorio,
    this.motivoInicial,
  });

  @override
  State<_DialogoMotivoCancelacion> createState() =>
      _DialogoMotivoCancelacionState();
}

class _DialogoMotivoCancelacionState extends State<_DialogoMotivoCancelacion> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  /// La validación en vivo solo se muestra cuando la persona ya escribió algo
  /// (o intentó confirmar): un error rojo en un campo recién abierto es
  /// ruido, no ayuda.
  bool _tocado = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.motivoInicial ?? '');
    _focus = FocusNode();
    _controller.addListener(_alCambiar);
  }

  @override
  void dispose() {
    _controller.removeListener(_alCambiar);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _alCambiar() => setState(() {});

  String get _texto => _controller.text.trim();

  /// Un motivo vacío es válido solo cuando el motivo es opcional.
  bool get _esValido {
    if (!widget.obligatorio && _texto.isEmpty) return true;
    return validarMotivo(_texto) == null;
  }

  /// Error a pintar en el campo (o `null` para no pintar nada todavía).
  String? get _error {
    if (!_tocado) return null;
    if (!widget.obligatorio && _texto.isEmpty) return null;
    return validarMotivo(_texto);
  }

  void _confirmar() {
    if (!_esValido) {
      setState(() => _tocado = true);
      _focus.requestFocus();
      return;
    }
    Navigator.of(context).pop(_texto);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.event_busy_rounded, color: AppTheme.error, size: 22),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              widget.titulo,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.detalle,
              style: const TextStyle(fontSize: 13.5, height: 1.35),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              minLines: 2,
              maxLines: 3,
              maxLength: motivoCancelacionMaxLength,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.newline,
              onChanged: (_) {
                if (!_tocado) setState(() => _tocado = true);
              },
              onSubmitted: (_) => _confirmar(),
              decoration: InputDecoration(
                labelText: widget.obligatorio
                    ? 'Motivo (obligatorio)'
                    : 'Motivo (opcional)',
                hintText: 'Ej.: el cliente no pudo asistir',
                errorText: error,
                errorMaxLines: 3,
                helperText: widget.obligatorio
                    ? 'El cliente verá este motivo en su reserva.'
                    : 'Si lo dejas vacío, la reserva se cancela sin motivo.',
                helperMaxLines: 2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('No'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.error,
            foregroundColor: Colors.white,
          ),
          // Deshabilitado mientras falte el motivo obligatorio: el usuario ve
          // por qué (helper + error en vivo) en vez de un error del servidor.
          onPressed: _esValido ? _confirmar : null,
          child: const Text('Sí, cancelar'),
        ),
      ],
    );
  }
}