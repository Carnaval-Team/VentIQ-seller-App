import 'package:flutter/foundation.dart';

import '../models/sales.dart';
import '../models/sales_analyst_models.dart';
import 'sales_analyst_service.dart';
import 'sales_service.dart';

class SalesAnalystContextSnapshot {
  final DateTime startDate;
  final DateTime endDate;
  final double totalSales;
  final int totalProductsSold;
  final List<ProductSalesReport> productSalesReports;
  final List<SalesVendorReport> vendorReports;
  final List<SupplierSalesReport> supplierReports;
  final String selectedTpv;
  final int? selectedWarehouseId;
  final String? selectedWarehouseName;
  final List<ProductAnalysis> productAnalysis;

  const SalesAnalystContextSnapshot({
    required this.startDate,
    required this.endDate,
    required this.totalSales,
    required this.totalProductsSold,
    required this.productSalesReports,
    required this.vendorReports,
    required this.supplierReports,
    required this.selectedTpv,
    required this.productAnalysis,
    this.selectedWarehouseId,
    this.selectedWarehouseName,
  });

  bool get hasAnyData {
    return productSalesReports.isNotEmpty ||
        vendorReports.isNotEmpty ||
        supplierReports.isNotEmpty ||
        productAnalysis.isNotEmpty;
  }
}

class SalesAnalystController extends ChangeNotifier {
  final SalesAnalystService _service;
  final List<SalesAnalystMessage> _messages = [];
  bool _isLoading = false;

  SalesAnalystController({SalesAnalystService? service})
    : _service = service ?? SalesAnalystService() {
    _messages.add(SalesAnalystMessage.assistant(text: _service.initialMessage));
  }

  List<SalesAnalystMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;

  void resetConversation() {
    _messages
      ..clear()
      ..add(SalesAnalystMessage.assistant(text: _service.initialMessage));
    _isLoading = false;
    notifyListeners();
  }

  Future<void> sendQuestion({
    required String question,
    required SalesAnalystContextSnapshot context,
  }) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      _addAssistantMessage(
        'Escribe una pregunta sobre tus ventas.',
        isError: true,
      );
      return;
    }

    if (!context.hasAnyData) {
      _addAssistantMessage(
        'No hay datos de ventas en el período seleccionado. Ajusta el rango e intenta de nuevo.',
        isError: true,
      );
      return;
    }

    if (_isLoading) {
      return;
    }

    final validation = _service.validateQuestion(trimmed);
    if (validation != null) {
      _addAssistantMessage(validation, isError: true);
      return;
    }

    _messages.add(SalesAnalystMessage.user(trimmed));
    _setLoading(true);

    try {
      final contextPayload = _service.buildContext(
        startDate: context.startDate,
        endDate: context.endDate,
        totalSales: context.totalSales,
        totalProductsSold: context.totalProductsSold,
        productSalesReports: context.productSalesReports,
        vendorReports: context.vendorReports,
        supplierReports: context.supplierReports,
        selectedTpv: context.selectedTpv,
        selectedWarehouseId: context.selectedWarehouseId,
        selectedWarehouseName: context.selectedWarehouseName,
        productAnalysis: context.productAnalysis,
      );

      final response = await _service.analyze(
        question: trimmed,
        context: contextPayload,
      );

      final summary =
          response.summary.isNotEmpty ? response.summary : response.title;

      _messages.add(
        SalesAnalystMessage.assistant(text: summary, response: response),
      );
    } catch (e) {
      _messages.add(SalesAnalystMessage.error(_normalizeError(e)));
    } finally {
      _setLoading(false);
    }
  }

  void _addAssistantMessage(String text, {bool isError = false}) {
    _messages.add(SalesAnalystMessage.assistant(text: text, isError: isError));
    notifyListeners();
  }

  void _setLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    notifyListeners();
  }

  String _normalizeError(Object error) {
    return error.toString().replaceFirst('Exception: ', '').trim();
  }
}
