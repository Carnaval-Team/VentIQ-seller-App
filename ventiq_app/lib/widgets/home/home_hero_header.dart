import 'package:flutter/material.dart';

import '../../theme/ventiq_home_theme.dart';

/// Cabecera del Home: banda degradada + saludo + acciones + estado de conexión,
/// y debajo el buscador **flotando sobre la costura** con el lienzo claro.
///
/// Es el port de `HomeHeroHeader` de `inventtia_flow`
/// (`widgets/home_hero_header.dart`), con dos diferencias deliberadas:
///
///  * **el buscador es un hijo fijo, no algo que se abre**. En `inventtia_flow`
///    el buscador viaja con el scroll y se abre con un icono; aquí el requisito
///    es que esté siempre visible entre la barra y el lienzo blanco, así que
///    [buscador] se pinta siempre y no hay estado que lo esconda;
///  * **el estado de conexión va abajo a la derecha**, debajo de las acciones,
///    y no pegado al saludo. Con el chip «Online» en la misma fila, el saludo
///    quedaba comprimido entre dos bloques y el conjunto se leía centrado; así
///    el nombre del vendedor ocupa la izquierda de verdad y la derecha queda
///    ordenada en dos pisos (acciones arriba, conexión abajo).
///
/// El truco del "flote": la banda degradada termina, y debajo hay una franja
/// del mismo color que el final del degradado ([VentiqHomeTheme.heroBand]).
/// El buscador se pinta en un `Stack` encima de esa franja, así que la tapa
/// salvo los 16 px de gutter de cada lado y parece estar suspendido sobre el
/// corte, en vez de pegado debajo.
class HomeHeroHeader extends StatelessWidget {
  const HomeHeroHeader({
    super.key,
    required this.saludo,
    this.subtitulo,
    this.acciones = const <Widget>[],
    this.estadoConexion,
    this.buscador,
  });

  /// Texto grande de la cabecera, alineado a la izquierda.
  /// Ej. `'Hola, César 👋'`.
  final String saludo;

  final String? subtitulo;

  /// Acciones de la esquina superior derecha (campana, escáner...).
  final List<Widget> acciones;

  /// Estado de conexión (online/offline). Se pinta debajo de [acciones], en la
  /// esquina inferior derecha de la banda.
  final Widget? estadoConexion;

  /// El buscador. Se pinta siempre, sin condiciones: es el requisito.
  final Widget? buscador;

  @override
  Widget build(BuildContext context) {
    final Widget? sub = subtitulo == null
        ? null
        : Text(
            subtitulo!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 13,
            ),
          );

    final bool hayColumnaDerecha = acciones.isNotEmpty || estadoConexion != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ── Banda degradada: termina justo debajo de la fila del saludo ──
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: VentiqHomeTheme.heroGradient,
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // El nombre lo escribe la persona y puede ser largo.
                        // `FittedBox` lo encoge lo justo para caber en una
                        // línea, en vez de partirlo en dos y empujar el
                        // buscador hacia abajo.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            saludo,
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                        if (sub != null) ...<Widget>[
                          const SizedBox(height: 4),
                          sub,
                        ],
                      ],
                    ),
                  ),
                  if (hayColumnaDerecha) ...<Widget>[
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (acciones.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: acciones,
                          ),
                        if (estadoConexion != null) ...<Widget>[
                          if (acciones.isNotEmpty) const SizedBox(height: 6),
                          estadoConexion!,
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // ── Franja de solape + buscador encima ──
        if (buscador != null)
          Stack(
            children: <Widget>[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: VentiqHomeTheme.searchOverlap,
                child: const ColoredBox(color: VentiqHomeTheme.heroBand),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  VentiqHomeTheme.sectionPadding,
                  0,
                  VentiqHomeTheme.sectionPadding,
                  18,
                ),
                child: buscador,
              ),
            ],
          ),
      ],
    );
  }
}