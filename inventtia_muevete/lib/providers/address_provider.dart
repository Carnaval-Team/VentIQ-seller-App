import 'package:flutter/material.dart';
import '../models/saved_address_model.dart';
import '../services/saved_address_service.dart';

class AddressProvider extends ChangeNotifier {
  final SavedAddressService _service = SavedAddressService();

  List<SavedAddressModel> _addresses = [];
  bool _isLoading = false;
  String? _error;

  List<SavedAddressModel> get addresses => _addresses;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadAddresses(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _addresses = await _service.getAddresses(userId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addAddress({
    required String userId,
    required String label,
    required String icon,
    required String direccion,
    required double latitud,
    required double longitud,
  }) async {
    try {
      final newAddr = await _service.createAddress(
        userId: userId,
        label: label,
        icon: icon,
        direccion: direccion,
        latitud: latitud,
        longitud: longitud,
      );
      _addresses.add(newAddr);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteAddress(int id) async {
    try {
      await _service.deleteAddress(id);
      _addresses.removeWhere((a) => a.id == id);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateAddress(int id, {
    String? label,
    String? icon,
    String? direccion,
    double? latitud,
    double? longitud,
  }) async {
    try {
      await _service.updateAddress(
        id,
        label: label,
        icon: icon,
        direccion: direccion,
        latitud: latitud,
        longitud: longitud,
      );
      final idx = _addresses.indexWhere((a) => a.id == id);
      if (idx != -1) {
        _addresses[idx] = _addresses[idx].copyWith(
          label: label,
          icon: icon,
          direccion: direccion,
          latitud: latitud,
          longitud: longitud,
        );
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
}
