import 'package:flutter/material.dart';

import '../models/mesa.dart';
import '../services/mesa_cuenta_service.dart';
import '../services/mesa_service.dart';
import 'tutorial_destino.dart';

/// Traduce el destino de un paso del tutorial en navegación real.
///
/// Se apoya en el `NavigatorState` que captura el punto de lanzamiento, así el
/// tutorial puede cruzar pantallas sin depender de un contexto que se desmonta.
class TutorialNavegacion {
  TutorialNavegacion._();

  static Future<void> ir(NavigatorState nav, TutorialDestino destino) async {
    switch (destino) {
      case TutorialDestino.home:
        nav.popUntil((Route<dynamic> r) => r.isFirst);
      case TutorialDestino.preorder:
        nav.popUntil((Route<dynamic> r) => r.isFirst);
        nav.pushNamed('/preorder');
      case TutorialDestino.mesas:
        nav.popUntil((Route<dynamic> r) => r.isFirst);
        nav.pushNamed('/mesas');
      case TutorialDestino.mesaDetalle:
        final int? idMesa = await _primeraMesaId();
        if (idMesa == null) return;
        nav.popUntil((Route<dynamic> r) => r.isFirst);
        nav.pushNamed('/mesa-detail', arguments: idMesa);
      case TutorialDestino.cuentaMesa:
        final int? idCuenta = await _primeraCuentaId();
        if (idCuenta != null) {
          nav.popUntil((Route<dynamic> r) => r.isFirst);
          nav.pushNamed('/cuenta-mesa', arguments: idCuenta);
          return;
        }
        // Sin cuentas abiertas, al menos deja Mesas a la vista.
        nav.popUntil((Route<dynamic> r) => r.isFirst);
        nav.pushNamed('/mesas');
    }
  }

  static Future<int?> _primeraMesaId() async {
    try {
      final List<Mesa> mesas = await MesaService().listMesasWithStats();
      if (mesas.isEmpty) return null;
      for (final Mesa mesa in mesas) {
        if (mesa.activa) return mesa.id;
      }
      return mesas.first.id;
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _primeraCuentaId() async {
    try {
      final List<Mesa> mesas = await MesaService().listMesasWithStats();
      for (final Mesa mesa in mesas) {
        if (!mesa.activa || !mesa.ocupada) continue;
        final cuentas = await MesaCuentaService().listarCuentasMesa(mesa.id);
        if (cuentas.isNotEmpty) return cuentas.first.id;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
