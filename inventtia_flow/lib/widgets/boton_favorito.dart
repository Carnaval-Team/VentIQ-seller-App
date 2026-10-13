import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/favoritos_provider.dart';
import '../screens/favoritos_screen.dart';

/// Corazón de favoritos reutilizable (Home, catálogo y detalle de servicio).
///
/// Se **auto-oculta** cuando no hay nada que guardar:
///   - `flow.favorito` todavía no existe (migración `25_favoritos.sql` sin
///     aplicar) → [FavoritosProvider.disponible] es `false`;
///   - no hay sesión iniciada.
///
/// Así el mismo binario funciona antes y después de aplicar la migración, sin
/// banderas que voltear a mano ni un botón que siempre falla.
///
/// El estado se lee con `context.select`, de modo que solo se repinta este
/// botón al alternar un favorito, no la pantalla entera.
class BotonFavorito extends StatelessWidget {
  /// `local_servicio.id`.
  final int idLocalServicio;

  /// Título del servicio, para el mensaje de confirmación.
  final String titulo;

  /// Si no se pasa, lo resuelve el provider (`FavoritosProvider.estaGuardado`).
  final bool? saved;

  /// Tamaño del botón.
  final double size;

  /// `true` para el corazón sobre fondo claro (Home): círculo blanco.
  /// `false` para el header oscuro del detalle: fondo translúcido.
  final bool sobreClaro;

  const BotonFavorito({
    super.key,
    required this.idLocalServicio,
    required this.titulo,
    this.saved,
    this.size = 30,
    this.sobreClaro = true,
  });

  @override
  Widget build(BuildContext context) {
    final disponible = context.select<FavoritosProvider, bool>(
      (p) => p.disponible,
    );
    final haySesion = context.select<AuthProvider, bool>((p) => p.isLoggedIn);
    if (!disponible || !haySesion) return const SizedBox.shrink();

    final guardado =
        saved ??
        context.select<FavoritosProvider, bool>(
          (p) => p.estaGuardado(idLocalServicio),
        );

    return IconButton(
      onPressed: () => alternarFavorito(
        context,
        idLocalServicio: idLocalServicio,
        titulo: titulo,
      ),
      tooltip: guardado ? 'Quitar de favoritos' : 'Guardar en favoritos',
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      style: IconButton.styleFrom(
        backgroundColor: sobreClaro
            ? Colors.white.withValues(alpha: 0.90)
            : Colors.white.withValues(alpha: 0.18),
      ),
      icon: Icon(
        guardado ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        size: size * 0.58,
        color: guardado
            ? AppTheme.error
            : (sobreClaro ? AppTheme.primary : Colors.white),
      ),
    );
  }
}

/// Alterna un favorito y avisa del resultado.
///
/// Centraliza el aviso para que las tres pantallas se comporten igual: mismo
/// texto, misma acción "Ver favoritos" y mismo manejo del error.
///
/// Devuelve el estado resultante (`true` = quedó guardado), o `null` si no se
/// pudo (sin sesión o migración sin aplicar).
Future<bool?> alternarFavorito(
  BuildContext context, {
  required int idLocalServicio,
  required String titulo,
}) async {
  final favoritos = context.read<FavoritosProvider>();
  final messenger = ScaffoldMessenger.of(context);
  try {
    final guardado = await favoritos.alternar(idLocalServicio);
    if (guardado == null) return null;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            guardado
                ? '$titulo guardado en favoritos.'
                : '$titulo quitado de favoritos.',
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          action: guardado
              ? SnackBarAction(
                  label: 'Ver',
                  textColor: AppTheme.accent,
                  onPressed: () => abrirFavoritos(context),
                )
              : null,
        ),
      );
    return guardado;
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('No pudimos actualizar tus favoritos.'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
          backgroundColor: AppTheme.error,
        ),
      );
    return null;
  }
}

/// Abre la pantalla de favoritos.
///
/// El import de la pantalla convive con un ciclo (`favoritos_screen` importa el
/// detalle, que importa este archivo), que en Dart es legal y no impide el
/// tree-shaking.
void abrirFavoritos(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const FavoritosScreen()),
  );
}
