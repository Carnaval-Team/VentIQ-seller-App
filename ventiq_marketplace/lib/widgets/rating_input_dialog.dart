import 'package:flutter/material.dart';
// import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../config/app_theme.dart';

class RatingInputDialog extends StatefulWidget {
  final String title;
  final String? initialComment;
  final double initialRating;
  final Function(double rating, String? comment) onSubmit;

  const RatingInputDialog({
    Key? key,
    required this.title,
    required this.onSubmit,
    this.initialComment,
    this.initialRating = 0.0,
  }) : super(key: key);

  @override
  State<RatingInputDialog> createState() => _RatingInputDialogState();
}

class _RatingInputDialogState extends State<RatingInputDialog> {
  late double _rating;
  late TextEditingController _commentController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
    _commentController = TextEditingController(text: widget.initialComment);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_rating < 1.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona una calificación')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    // Simular un pequeño delay o simplemente llamar al callback
    // El callback es responsable de la lógica asíncrona (llamar al servicio)
    // Pero aquí cerramos el diálogo después de llamar

    try {
      await widget.onSubmit(_rating, _commentController.text.trim());
      if (mounted) {
        Navigator.of(context).pop(true); // Retorna true si se envió
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar calificación: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si no está el paquete flutter_rating_bar, usaremos una implementación alternativa simple
    // o asumimos que se agregará al pubspec.
    // Para asegurar que funcione sin paquetes externos si no están, haré una fila de estrellas manual.
    // Pero lo ideal es usar flutter_rating_bar. Verificaremos el pubspec luego.
    // Por ahora uso una implementación custom simple para evitar dependencias no instaladas.

    return AlertDialog(
      title: Text(
        widget.title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),
            _buildStarRating(),
            const SizedBox(height: 20),
            TextField(
              controller: _commentController,
              decoration: InputDecoration(
                labelText: 'Comentario (Opcional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                hintText: 'Cuéntanos tu experiencia...',
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Enviar', style: TextStyle(color: Colors.white)),
        ),
      ],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildStarRating() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return IconButton(
          onPressed: () {
            setState(() {
              _rating = index + 1.0;
            });
          },
          icon: Icon(
            index < _rating ? Icons.star : Icons.star_border,
            color: Colors.amber,
            size: 40,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        );
      }),
    );
  }
}
