import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/payment_method.dart';

class PaymentMethodService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetches all active payment methods from app_nom_medio_pago table
  Future<List<PaymentMethod>> getPaymentMethods() async {
    try {
      print('PaymentMethodService: Fetching payment methods from app_nom_medio_pago');
      
      final response = await _supabase
          .from('app_nom_medio_pago')
          .select('*')
          .eq('es_activo', true)
          .order('denominacion');

      print('PaymentMethodService: Response received: ${response.length} payment methods');

      final List<PaymentMethod> paymentMethods = [];
      
      for (final item in response) {
        try {
          final paymentMethod = PaymentMethod.fromJson(item);
          paymentMethods.add(paymentMethod);
          print('PaymentMethodService: Added payment method: ${paymentMethod.denominacion} (ID: ${paymentMethod.id})');
        } catch (e) {
          print('PaymentMethodService: Error parsing payment method: $e');
          print('PaymentMethodService: Item data: $item');
        }
      }

      print('PaymentMethodService: Successfully loaded ${paymentMethods.length} payment methods');
      return paymentMethods;
      
    } catch (e) {
      print('PaymentMethodService: Error fetching payment methods: $e');
      
      // Return fallback payment methods in case of error
      return [
        PaymentMethod(
          id: 1,
          denominacion: 'Efectivo',
          descripcion: 'Pago en efectivo',
          esDigital: false,
          esEfectivo: true,
          esActivo: true,
        ),
        PaymentMethod(
          id: 2,
          denominacion: 'Transferencia',
          descripcion: 'Transferencia bancaria',
          esDigital: true,
          esEfectivo: false,
          esActivo: true,
        ),
      ];
    }
  }

  /// Gets a specific payment method by ID
  Future<PaymentMethod?> getPaymentMethodById(int id) async {
    try {
      final paymentMethods = await getPaymentMethods();
      return paymentMethods.firstWhere(
        (pm) => pm.id == id,
        orElse: () => throw Exception('Payment method not found'),
      );
    } catch (e) {
      print('PaymentMethodService: Error getting payment method by ID $id: $e');
      return null;
    }
  }
}
