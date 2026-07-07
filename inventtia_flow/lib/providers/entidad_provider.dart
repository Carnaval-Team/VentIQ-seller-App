import 'package:flutter/material.dart';
import '../models/entidad.dart';
import '../services/entidad_service.dart';

class EntidadProvider extends ChangeNotifier {
  List<Entidad> _misEntidades = [];
  List<Entidad> _misEntidadesComoVendedor = [];
  Entidad? _entidadSeleccionada;
  Entidad? _entidadVendedorSeleccionada;
  bool _isLoading = false;
  String? _error;

  List<Entidad> get misEntidades => _misEntidades;
  List<Entidad> get misEntidadesComoVendedor => _misEntidadesComoVendedor;
  Entidad? get entidadSeleccionada => _entidadSeleccionada;
  Entidad? get entidadVendedorSeleccionada => _entidadVendedorSeleccionada;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAdmin => _misEntidades.isNotEmpty;
  bool get isVendedor => _misEntidadesComoVendedor.isNotEmpty;

  void seleccionarEntidad(Entidad entidad) {
    _entidadSeleccionada = entidad;
    notifyListeners();
  }

  void seleccionarEntidadVendedor(Entidad entidad) {
    _entidadVendedorSeleccionada = entidad;
    notifyListeners();
  }

  Future<void> cargarMisEntidades(String uuidUsuario) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        EntidadService.getMisEntidades(uuidUsuario),
        EntidadService.getMisEntidadesComoVendedor(uuidUsuario),
      ]);
      _misEntidades = results[0];
      _misEntidadesComoVendedor = results[1];
      print('[flow] EntidadProvider → ${_misEntidades.length} entidades admin, ${_misEntidadesComoVendedor.length} como vendedor');
      // Autoseleccionar admin
      if (_misEntidades.isNotEmpty) {
        final stillExists = _entidadSeleccionada != null &&
            _misEntidades.any((e) => e.id == _entidadSeleccionada!.id);
        if (!stillExists) {
          _entidadSeleccionada = _misEntidades.first;
        } else {
          _entidadSeleccionada = _misEntidades
              .firstWhere((e) => e.id == _entidadSeleccionada!.id);
        }
      } else {
        _entidadSeleccionada = null;
      }
      // Autoseleccionar vendedor
      if (_misEntidadesComoVendedor.isNotEmpty) {
        final stillExists = _entidadVendedorSeleccionada != null &&
            _misEntidadesComoVendedor
                .any((e) => e.id == _entidadVendedorSeleccionada!.id);
        if (!stillExists) {
          _entidadVendedorSeleccionada = _misEntidadesComoVendedor.first;
        } else {
          _entidadVendedorSeleccionada = _misEntidadesComoVendedor
              .firstWhere((e) => e.id == _entidadVendedorSeleccionada!.id);
        }
      } else {
        _entidadVendedorSeleccionada = null;
      }
    } catch (e) {
      print('[flow] EntidadProvider ERROR: $e');
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<Entidad?> crearEntidad({
    required String denominacion,
    String? direccion,
    String? telefono,
    required String ownerUuid,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final entidad = await EntidadService.createEntidad(
        denominacion: denominacion,
        direccion: direccion,
        telefono: telefono,
        ownerUuid: ownerUuid,
      );
      _misEntidades.add(entidad);
      _misEntidades.sort((a, b) => a.denominacion.compareTo(b.denominacion));
      // Auto-selectar la nueva entidad creada
      _entidadSeleccionada = entidad;
      print('[flow] EntidadProvider → entidad creada id: ${entidad.id}');
      print('[flow] EntidadProvider → entidad seleccionada: ${entidad.denominacion}');
      _isLoading = false;
      notifyListeners();
      return entidad;
    } catch (e) {
      print('[flow] EntidadProvider crearEntidad ERROR: $e');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> actualizarEntidad({
    required int id,
    required String denominacion,
    String? direccion,
    String? telefono,
    int? horasAnticipacionCancelacion,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await EntidadService.updateEntidad(
        id: id,
        denominacion: denominacion,
        direccion: direccion,
        telefono: telefono,
        horasAnticipacionCancelacion: horasAnticipacionCancelacion,
      );
      final idx = _misEntidades.indexWhere((e) => e.id == id);
      if (idx != -1) _misEntidades[idx] = updated;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      print('[flow] EntidadProvider actualizarEntidad ERROR: $e');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void limpiar() {
    _misEntidades = [];
    _misEntidadesComoVendedor = [];
    _entidadSeleccionada = null;
    _entidadVendedorSeleccionada = null;
    _error = null;
    notifyListeners();
  }

  Future<void> recargarSiEsNecesario(String uuidUsuario) async {
    if (_misEntidades.isEmpty && !_isLoading) {
      await cargarMisEntidades(uuidUsuario);
    }
  }
}
