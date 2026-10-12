import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/resena_service.dart';
import 'resenas.dart';

/// Tarjeta de una reseña reciente en el carrusel del Home.
///
/// Orden de lectura, que es lo que se pidió: **arriba** quién la escribió (autor
/// abreviado) y sobre qué servicio, **debajo** el comentario, que es lo que se lee
/// de verdad, y la **nota en la esquina inferior derecha**. Antes las estrellas
/// iban las primeras y el autor al final, así que el ojo entraba por una nota sin
/// saber de quién era.
///
/// La nota va abajo a la derecha a propósito: en la cabecera se peleaba el ancho
/// con el nombre del autor (y salían elipsis en nombres largos como
/// "reserv@gmail.com R."), y aquí queda en una esquina libre, sin robar líneas al
/// comentario.
///
/// Solo muestra lo que el RPC entrega: estrellas reales, el comentario, el autor
/// abreviado y el servicio. Nada de "Verificada" ni insignias decorativas: la
/// reseña ya está verificada por construcción (viene de una reserva completada),
/// así que presumirlo en cada tarjeta sería ruido.
///
/// Vive en `lib/widgets/` y no dentro de la pantalla del Home porque así se puede
/// medir en un test: es una tarjeta de ancho y alto fijos (250×178 en el
/// carrusel) y el riesgo real es que la cabecera o la nota se salgan.
class TarjetaResenaReciente extends StatelessWidget {
  final Resena resena;
  final VoidCallback onTap;

  /// Clave de la fila de la nota (estrellas + número). Está para poder medir en
  /// un test que de verdad queda pegada a la esquina inferior derecha: los iconos
  /// y el texto no acaban a la misma altura exacta, la fila sí.
  static const Key claveNota = Key('tarjeta-resena-nota');

  const TarjetaResenaReciente({
    super.key,
    required this.resena,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: AppTheme.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D2B3A67),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Arriba: quién la escribió y de qué servicio.
            Row(
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    resena.autor.trim().isEmpty
                        ? '?'
                        : resena.autor.trim()[0].toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resena.autor,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (resena.servicio != null)
                        Text(
                          resena.servicio!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Debajo: el comentario. Se queda con el espacio que sobra, así que
            // la nota baja sola a la esquina aunque el texto sea de una línea.
            // 5 líneas es lo que cabe de verdad en los 178 de alto: cabecera
            // (~28) + huecos (14) + nota (15) dejan ~95 px, y 6 líneas a 17,5
            // pedirían 105 (la sexta saldría cortada a media altura).
            Expanded(
              child: Text(
                resena.comentario ?? '',
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Esquina inferior derecha: estrellas + nota. Ya sin competir con el
            // nombre, pueden ir a 13.
            Align(
              key: claveNota,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Estrellas(promedio: resena.puntuacion.toDouble(), size: 13),
                  const SizedBox(width: 4),
                  Text(
                    resena.puntuacion.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.warning,
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
