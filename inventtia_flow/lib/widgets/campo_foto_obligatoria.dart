import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_theme.dart';
import '../utils/foto_obligatoria.dart';
import 'net_image.dart';
import 'preview_imagen.dart';

/// Selector de la **foto obligatoria** de un local o de un servicio.
///
/// POR QUE EXISTE
///   El mismo bloque estaba duplicado en los dos formularios del panel (local y
///   servicio) y ninguno validaba nada: se podía guardar un local o un servicio
///   sin foto. Ahora hay un único sitio que sabe pintar el campo **y** que la
///   foto es obligatoria, así que la regla se cumple igual en crear y en editar
///   y no puede divergir entre los dos formularios.
///
/// Es un `FormField`, no un widget suelto, para que el error salga con el resto
/// de campos inválidos al pulsar Guardar (y desaparezca en cuanto se elige la
/// foto, sin tener que volver a intentarlo).
///
/// TEMPORAL: para levantar la obligación basta con quitar el `validator`.
class CampoFotoObligatoria extends StatefulWidget {
  const CampoFotoObligatoria({
    super.key,
    required this.queEs,
    required this.fotoGuardada,
    required this.archivo,
    required this.placeholder,
    required this.onElegir,
    this.alto = 140,
  });

  /// `'local'` o `'servicio'`: sale en la etiqueta y en el mensaje de error.
  final String queEs;

  /// URL ya guardada en la base de datos (`null` en un alta).
  final String? fotoGuardada;

  /// Archivo recién elegido, todavía sin subir.
  final XFile? archivo;

  /// Qué pintar cuando aún no hay foto.
  final Widget placeholder;

  final VoidCallback onElegir;
  final double alto;

  @override
  State<CampoFotoObligatoria> createState() => _CampoFotoObligatoriaState();
}

class _CampoFotoObligatoriaState extends State<CampoFotoObligatoria> {
  final _clave = GlobalKey<FormFieldState<bool>>();

  bool get _tiene => tieneFoto(
    fotoGuardada: widget.fotoGuardada,
    archivoElegido: widget.archivo != null,
  );

  @override
  void didUpdateWidget(covariant CampoFotoObligatoria anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.archivo != widget.archivo ||
        anterior.fotoGuardada != widget.fotoGuardada) {
      // El campo se revalida **después** del frame: elegir la foto tiene que
      // quitar el error en el acto, no en el siguiente intento de guardar.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _clave.currentState?.didChange(_tiene);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormField<bool>(
      key: _clave,
      initialValue: _tiene,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (_) => errorFotoObligatoria(
        queEs: widget.queEs,
        fotoGuardada: widget.fotoGuardada,
        archivoElegido: widget.archivo != null,
      ),
      builder: (estado) {
        final error = estado.errorText;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Foto del ${widget.queEs} *',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: widget.onElegir,
              child: Container(
                height: widget.alto,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: error != null
                        ? AppTheme.error
                        : (_tiene
                              ? Colors.grey.shade300
                              : AppTheme.warning.withValues(alpha: 0.7)),
                    width: error != null ? 1.6 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: _contenido(),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton.icon(
                onPressed: widget.onElegir,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                label: Text(_tiene ? 'Cambiar imagen' : 'Agregar imagen'),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 15,
                      color: AppTheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        error,
                        style: const TextStyle(
                          color: AppTheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (!_tiene)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Obligatoria: es la imagen que verá el cliente.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSecondary.withValues(alpha: 0.95),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _contenido() {
    final archivo = widget.archivo;
    if (archivo != null) {
      return PreviewImagen(
        file: archivo,
        fit: BoxFit.cover,
        width: double.infinity,
      );
    }
    final url = widget.fotoGuardada?.trim();
    if (url != null && url.isNotEmpty) {
      // `NetImage` aplica el `?v=` de la última sustitución, así que después de
      // cambiar la foto se ve la nueva y no la que quedó en caché.
      return NetImage(
        url: url,
        fit: BoxFit.cover,
        width: double.infinity,
        placeholder: () => const Center(child: CircularProgressIndicator()),
        errorWidget: () => widget.placeholder,
      );
    }
    return widget.placeholder;
  }
}
