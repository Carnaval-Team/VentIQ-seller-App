import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/auth_service.dart';
import '../services/resena_service.dart';

/// Fila de estrellas de solo lectura.
///
/// Cuando no hay valoración ([promedio] nulo o 0) muestra estrellas vacías y un
/// texto neutro: **nunca** inventa un 4.8 para rellenar, que es exactamente lo
/// que hacía el Home antes.
class Estrellas extends StatelessWidget {
  final double? promedio;
  final double size;
  final bool mostrarValorJunto;

  const Estrellas({
    super.key,
    required this.promedio,
    this.size = 15,
    this.mostrarValorJunto = false,
  });

  @override
  Widget build(BuildContext context) {
    final valor = promedio ?? 0;
    // Redondeo a media estrella para que 4.3 no se pinte como 4.5.
    final medios = (valor * 2).round();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            medios >= i * 2
                ? Icons.star_rounded
                : (medios >= i * 2 - 1
                      ? Icons.star_half_rounded
                      : Icons.star_border_rounded),
            size: size,
            color: valor > 0
                ? AppTheme.warning
                : AppTheme.textSecondary.withValues(alpha: 0.45),
          ),
        if (mostrarValorJunto) ...[
          const SizedBox(width: 5),
          Text(
            valor > 0 ? valor.toStringAsFixed(1) : 'Sin valoraciones',
            style: TextStyle(
              fontSize: size * 0.72,
              fontWeight: FontWeight.w800,
              color: valor > 0 ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Selector de 1 a 5 estrellas para el formulario de reseña.
class SelectorEstrellas extends StatelessWidget {
  final int valor;
  final ValueChanged<int> onChanged;
  final double size;

  const SelectorEstrellas({
    super.key,
    required this.valor,
    required this.onChanged,
    this.size = 40,
  });

  static const _etiquetas = <int, String>{
    1: 'Muy malo',
    2: 'Malo',
    3: 'Normal',
    4: 'Bueno',
    5: 'Excelente',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                onPressed: () => onChanged(i),
                tooltip: _etiquetas[i],
                icon: Icon(
                  i <= valor ? Icons.star_rounded : Icons.star_border_rounded,
                  size: size,
                  color: i <= valor
                      ? AppTheme.warning
                      : AppTheme.textSecondary.withValues(alpha: 0.5),
                ),
              ),
          ],
        ),
        Text(
          _etiquetas[valor] ?? 'Toca para valorar',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valor > 0 ? AppTheme.textPrimary : AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Resumen con promedio, total y barras de distribución por estrellas.
class ResumenValoraciones extends StatelessWidget {
  final ResumenResenas resumen;

  const ResumenValoraciones({super.key, required this.resumen});

  @override
  Widget build(BuildContext context) {
    if (!resumen.hayDatos) return const SizedBox.shrink();
    final maximo = resumen.distribucion.values.fold<int>(0, (a, b) => a > b ? a : b);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          children: [
            Text(
              resumen.promedio.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                height: 1.0,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Estrellas(promedio: resumen.promedio, size: 14),
            const SizedBox(height: 4),
            Text(
              resumen.total == 1 ? '1 reseña' : '${resumen.total} reseñas',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            children: [
              for (var i = 5; i >= 1; i--)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 10,
                        child: Text(
                          '$i',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: maximo == 0
                                ? 0
                                : (resumen.distribucion[i] ?? 0) / maximo,
                            minHeight: 7,
                            backgroundColor: AppTheme.border,
                            color: AppTheme.warning,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 22,
                        child: Text(
                          '${resumen.distribucion[i] ?? 0}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Una reseña en la lista.
class TarjetaResena extends StatelessWidget {
  final Resena resena;
  final VoidCallback? onEditar;
  final VoidCallback? onEliminar;

  const TarjetaResena({
    super.key,
    required this.resena,
    this.onEditar,
    this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: resena.esMia
              ? AppTheme.primary.withValues(alpha: 0.35)
              : AppTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                child: Text(
                  resena.autor.trim().isEmpty
                      ? '?'
                      : resena.autor.trim()[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            resena.autor,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (resena.esMia) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'TUYA',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Estrellas(promedio: resena.puntuacion.toDouble(), size: 13),
                        if (resena.createdAt != null) ...[
                          const SizedBox(width: 7),
                          Text(
                            _fechaCorta(resena.createdAt!),
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (onEditar != null || onEliminar != null)
                PopupMenuButton<String>(
                  tooltip: 'Opciones',
                  onSelected: (v) {
                    if (v == 'editar') onEditar?.call();
                    if (v == 'eliminar') onEliminar?.call();
                  },
                  itemBuilder: (_) => [
                    if (onEditar != null)
                      const PopupMenuItem(
                        value: 'editar',
                        child: Text('Editar mi reseña'),
                      ),
                    if (onEliminar != null)
                      const PopupMenuItem(
                        value: 'eliminar',
                        child: Text('Eliminar'),
                      ),
                  ],
                ),
            ],
          ),
          if (resena.tieneComentario) ...[
            const SizedBox(height: 9),
            Text(
              resena.comentario!,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _fechaCorta(DateTime fecha) {
    final d = fecha.day.toString().padLeft(2, '0');
    final m = fecha.month.toString().padLeft(2, '0');
    return '$d/$m/${fecha.year}';
  }
}

/// Abre el formulario de reseña. Devuelve `true` si se publicó algo.
///
/// [idAgenda] viene del RPC (`agenda_resenable`): es una reserva completada
/// propia sin reseñar, así que guardar no puede fallar por permisos.
Future<bool> mostrarEscribirResena(
  BuildContext context, {
  required int idAgenda,
  required String nombreServicio,
  Resena? existente,
}) async {
  final guardado = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _EscribirResenaSheet(
      idAgenda: idAgenda,
      nombreServicio: nombreServicio,
      existente: existente,
    ),
  );
  return guardado == true;
}

class _EscribirResenaSheet extends StatefulWidget {
  final int idAgenda;
  final String nombreServicio;
  final Resena? existente;

  const _EscribirResenaSheet({
    required this.idAgenda,
    required this.nombreServicio,
    this.existente,
  });

  @override
  State<_EscribirResenaSheet> createState() => _EscribirResenaSheetState();
}

class _EscribirResenaSheetState extends State<_EscribirResenaSheet> {
  late final TextEditingController _comentario;
  late int _puntuacion;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _puntuacion = widget.existente?.puntuacion ?? 0;
    _comentario = TextEditingController(
      text: widget.existente?.comentario ?? '',
    );
  }

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_puntuacion < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elige de 1 a 5 estrellas.')),
      );
      return;
    }
    final uuid = AuthService.currentUserId;
    if (uuid == null) return;

    setState(() => _enviando = true);
    try {
      await ResenaService.publicar(
        uuidUsuario: uuid,
        idAgenda: widget.idAgenda,
        puntuacion: _puntuacion,
        comentario: _comentario.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('$e'.replaceFirst('Exception: ', '')),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    final esEdicion = widget.existente != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + insets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            esEdicion ? 'Editar tu reseña' : '¿Cómo te fue?',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            widget.nombreServicio,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tu reseña es de una reserva que ya te atendieron.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
          ),
          const SizedBox(height: 14),
          SelectorEstrellas(
            valor: _puntuacion,
            onChanged: (v) => setState(() => _puntuacion = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _comentario,
            maxLines: 4,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Cuéntanos más (opcional)',
              hintText: '¿Qué te gustó? ¿Qué se puede mejorar?',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _enviando ? null : _enviar,
              child: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(esEdicion ? 'Guardar cambios' : 'Publicar reseña'),
            ),
          ),
        ],
      ),
    );
  }
}