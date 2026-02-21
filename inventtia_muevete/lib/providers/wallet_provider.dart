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

  Future<bool> addFunds(String uuid, double amount) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _walletService.addFunds(uuid, amount);
      _balance += amount;
      await loadTransactions(uuid);
      _error = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
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
