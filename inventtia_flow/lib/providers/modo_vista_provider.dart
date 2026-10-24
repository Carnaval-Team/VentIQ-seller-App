import 'package:flutter/foundation.dart';

/// Si un admin está viendo la app **como cliente**.
///
/// POR QUE EXISTE
///   El rol de una persona no es único: el dueño de una entidad también es
///   cliente de otros locales y necesita ver lo que ve un cliente (cómo queda el
///   Home, si su local aparece, cómo se reserva). Antes el shell decidía por el
///   rol y un admin quedaba encerrado en «Gestión».
///
/// SIN PERSISTENCIA, a propósito: el modo vive en memoria mientras dure la
/// sesión. Si se guardara, un admin que cerró la app en modo cliente volvería a
/// abrirla en la vista de cliente y podría pensar que perdió su panel. Al
/// reiniciar, siempre se entra como administrador.
///
/// Lo leen el shell (para elegir las pantallas y la barra) y las pantallas que
/// cambian de contenido según el rol (Perfil), por eso es un `ChangeNotifier` y
/// no un simple campo del `State`.
class ModoVistaProvider extends ChangeNotifier {
  bool _comoCliente = false;

  /// `true` = el admin pidió ver la app como la ve un cliente.
  bool get comoCliente => _comoCliente;

  void verComoCliente() {
    if (_comoCliente) return;
    _comoCliente = true;
    notifyListeners();
  }

  void verComoAdmin() {
    if (!_comoCliente) return;
    _comoCliente = false;
    notifyListeners();
  }

  void alternar() {
    _comoCliente = !_comoCliente;
    notifyListeners();
  }
}
