import 'package:flutter/foundation.dart';

import '../services/nomencladores_service.dart';

class NomencladoresProvider extends ChangeNotifier {
  final _service = NomencladoresService();

  List<NomTipoMercancia> _tiposMercancia = [];
  List<NomTipoEquipo> _tiposEquipo = [];
  List<NomEquipoManejo> _opcionesEquipoManejo = [];
  List<NomCommodity> _commodities = [];
  List<NomUnidadPeso> _unidadesPeso = [];

  bool _loading = false;
  bool _cargado = false;
  String? _error;

  List<NomTipoMercancia> get tiposMercancia => _tiposMercancia;
  List<NomTipoEquipo> get tiposEquipo => _tiposEquipo;
  List<NomEquipoManejo> get opcionesEquipoManejo => _opcionesEquipoManejo;
  List<NomCommodity> get commodities => _commodities;
  List<NomUnidadPeso> get unidadesPeso => _unidadesPeso;

  NomUnidadPeso? get unidadPesoKg {
    for (final u in _unidadesPeso) {
      if (u.codigo == 'KG') return u;
    }
    return _unidadesPeso.isNotEmpty ? _unidadesPeso.first : null;
  }

  NomUnidadPeso? unidadPesoPorId(int? id) {
    if (id == null) return null;
    for (final u in _unidadesPeso) {
      if (u.id == id) return u;
    }
    return null;
  }

  bool get loading => _loading;
  bool get cargado => _cargado;
  String? get error => _error;

  Future<void> cargar({bool forzar = false}) async {
    if (_cargado && !forzar) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _service.loadAll(
        onMercancia: (v) => _tiposMercancia = v,
        onEquipo: (v) => _tiposEquipo = v,
        onEquipoManejo: (v) => _opcionesEquipoManejo = v,
        onCommodity: (v) => _commodities = v,
        onUnidadPeso: (v) => _unidadesPeso = v,
      );
      _cargado = true;
    } catch (e) {
      _error = e.toString();
      debugPrint('[NomencladoresProvider] error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
