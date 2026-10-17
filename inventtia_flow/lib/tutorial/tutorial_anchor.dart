import 'package:flutter/material.dart';

import 'tutorial_registry.dart';

/// Marca un widget como objetivo del tutorial.
///
/// No cambia el layout (envuelve con un `KeyedSubtree`) ni intercepta gestos:
/// su único trabajo es registrar la `GlobalKey` para que el overlay sepa dónde
/// está el elemento que hay que resaltar, y la ruta que lo contiene para poder
/// distinguir "visible" de "tapado por una hoja modal".
class TutorialAnchor extends StatefulWidget {
  /// Debe coincidir con `TutorialPaso.id`.
  final String id;

  final Widget child;

  const TutorialAnchor({super.key, required this.id, required this.child});

  @override
  State<TutorialAnchor> createState() => _TutorialAnchorState();
}

class _TutorialAnchorState extends State<TutorialAnchor> {
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    _registrar();
  }

  @override
  void didUpdateWidget(TutorialAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _desregistrar(oldWidget.id);
      _registrar();
    }
  }

  void _registrar() {
    // Un frame después: así el `RenderBox` ya tiene layout y el rectángulo es
    // válido la primera vez que el overlay lo consulta. Además, el registro
    // avisa al controlador, que puede pedir un `setState` al overlay: eso no se
    // puede hacer dentro de la fase de build (`dispose`/`didUpdateWidget`
    // corren ahí), así que todo el alta/baja va diferido a post-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      TutorialRegistry.instance.registrar(widget.id, _key);
    });
  }

  void _desregistrar(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TutorialRegistry.instance.desregistrar(id, _key);
    });
  }

  @override
  void dispose() {
    _desregistrar(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Depende del estado de la ruta: si se apila una hoja modal encima, este
    // widget se reconstruye y `isCurrent` queda actualizado en el registro.
    TutorialRegistry.instance.registrarRuta(
      widget.id,
      ModalRoute.of(context),
    );
    return KeyedSubtree(key: _key, child: widget.child);
  }
}