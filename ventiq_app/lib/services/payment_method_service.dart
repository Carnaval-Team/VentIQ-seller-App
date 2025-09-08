import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/payment_method.dart';

class PaymentMethodService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene todos los medios de pago activos
  static Future<List<PaymentMethod>> getActivePaymentMethods() async {
    try {
      print('🔍 Fetching active payment methods...');

      final response = await _supabase
          .from('app_nom_medio_pago')
          .select('*')
          .eq('es_activo', true)
          .order('denominacion', ascending: true);

      print('📊 Payment methods response: $response');

      if (response.isNotEmpty) {
        final paymentMethods =
            response
                .map<PaymentMethod>((item) => PaymentMethod.fromJson(item))
                .toList();

        print('✅ Found ${paymentMethods.length} active payment methods');
        return paymentMethods;
      }

      print('⚠️ No active payment methods found');
      return [];
    } catch (e) {
      print('❌ Error fetching payment methods: $e');
      return [];
    }
  }

  /// Obtiene un medio de pago específico por ID
  static Future<PaymentMethod?> getPaymentMethodById(int id) async {
    try {
      print('🔍 Fetching payment method with ID: $id');

      final response =
          await _supabase
              .from('app_nom_medio_pago')
              .select('*')
              .eq('id', id)
              .eq('es_activo', true)
              .single();

      print('📊 Payment method response: $response');

      if (response != null) {
        final paymentMethod = PaymentMethod.fromJson(response);
        print('✅ Found payment method: ${paymentMethod.denominacion}');
        return paymentMethod;
      }

      return null;
    } catch (e) {
      print('❌ Error fetching payment method by ID: $e');
      return null;
    }
  }

  /// Valida si un medio de pago existe y está activo
  static Future<bool> isValidPaymentMethod(int id) async {
    try {
      final paymentMethod = await getPaymentMethodById(id);
      return paymentMethod != null && paymentMethod.esActivo;
    } catch (e) {
      print('❌ Error validating payment method: $e');
      return false;
    }
  }
}
