import 'package:flutter/material.dart';
import '../models/wallet_transaction_model.dart';
import '../services/wallet_service.dart';

class WalletProvider extends ChangeNotifier {
  final WalletService _walletService = WalletService();

  double _balance = 0;
  List<WalletTransactionModel> _transactions = [];
  bool _isLoading = false;
  String? _error;

  double get balance => _balance;
  List<WalletTransactionModel> get transactions => _transactions;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadClientBalance(String uuid) async {
    _isLoading = true;
    notifyListeners();

    try {
      _balance = await _walletService.getClientBalance(uuid);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadDriverBalance(int driverId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _balance = await _walletService.getDriverBalance(driverId);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadTransactions(String uuid) async {
    try {
      final results = await _walletService.getTransactions(uuid);
      _transactions = results
          .map((e) => WalletTransactionModel.fromJson(e))
          .toList();
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Creates a pending recharge transaction. Returns the transaction ID
  /// or null if an error occurred. Balance is NOT updated.
  Future<int?> addFunds(String uuid, double amount) async {
    _isLoading = true;
    notifyListeners();

    try {
      final transactionId = await _walletService.addFunds(uuid, amount);
      await loadTransactions(uuid);
      _error = null;
      _isLoading = false;
      notifyListeners();
      return transactionId;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<void> loadDriverTransactions(int driverId) async {
    try {
      final results = await _walletService.getDriverTransactions(driverId);
      _transactions = results
          .map((e) => WalletTransactionModel.fromJson(e))
          .toList();
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Creates a pending recharge transaction for a driver. Returns the
  /// transaction ID or null if an error occurred. Balance is NOT updated.
  Future<int?> addDriverFunds(int driverId, double amount) async {
    _isLoading = true;
    notifyListeners();

    try {
      final transactionId =
          await _walletService.addDriverFunds(driverId, amount);
      await loadDriverTransactions(driverId);
      _error = null;
      _isLoading = false;
      notifyListeners();
      return transactionId;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Uploads verification evidence for a pending recharge.
  Future<bool> uploadVerificacion({
    required int transaccionId,
    String? imagenUrl,
    String? detalleTexto,
  }) async {
    try {
      await _walletService.uploadVerificacion(
        transaccionId: transaccionId,
        imagenUrl: imagenUrl,
        detalleTexto: detalleTexto,
      );
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Checks if a verification exists for the given transaction.
  Future<bool> hasVerificacion(int transaccionId) async {
    try {
      final result = await _walletService.getVerificacion(transaccionId);
      return result != null;
    } catch (_) {
      return false;
    }
  }

  bool hasSufficientBalance(double amount) {
    return _balance >= amount;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
