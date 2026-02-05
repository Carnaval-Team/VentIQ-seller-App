import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/payment_method.dart';
import 'user_preferences_service.dart';

class PaymentMethodService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _userPreferencesService =
      UserPreferencesService();

  /// Obtiene métodos de pago con soporte de cache offline
  static Future<List<PaymentMethod>> getPaymentMethodsWithCache({
    required bool isOfflineModeEnabled,
    bool onlyEfectivo = false,
  }) async {
    if (isOfflineModeEnabled) {
      final cachedMethods = await _loadCachedMethods();
      if (cachedMethods.isNotEmpty) {
        final filtered = _filterMethods(cachedMethods, onlyEfectivo);
        print(
          '🔌 Modo offline - Métodos de pago desde cache: ${filtered.length}',
        );
        return filtered;
      }
      print('⚠️ Modo offline sin métodos de pago en cache');
      return [];
    }

    final onlineMethods = await getActivePaymentMethods();
    if (onlineMethods.isNotEmpty) {
      await _userPreferencesService.mergeOfflineData({
        'payment_methods': onlineMethods.map((pm) => pm.toJson()).toList(),
      });
      print('💾 Métodos de pago actualizados en cache offline');
      return _filterMethods(onlineMethods, onlyEfectivo);
    }

    final cachedMethods = await _loadCachedMethods();
    if (cachedMethods.isNotEmpty) {
      print('⚠️ Sin métodos de pago en línea - usando cache offline');
      return _filterMethods(cachedMethods, onlyEfectivo);
    }

    print('⚠️ No hay métodos de pago disponibles');
    return [];
  }

  static Future<List<PaymentMethod>> _loadCachedMethods() async {
    final cached = await _userPreferencesService.getPaymentMethodsOffline();
    if (cached.isEmpty) return [];
    return cached.map((data) => PaymentMethod.fromJson(data)).toList();
  }

  static List<PaymentMethod> _filterMethods(
    List<PaymentMethod> methods,
    bool onlyEfectivo,
  ) {
    if (!onlyEfectivo) return methods;
    return methods.where((method) => method.esEfectivo).toList();
  }

  /// Obtiene todos los medios de pago activos
  static Future<List<PaymentMethod>> getActivePaymentMethods({
    bool only_efectivo = false,
  }) async {
    try {
      print('🔍 Fetching active payment methods...');
      List<Map<String, dynamic>> response;
      if (!only_efectivo) {
        response = await _supabase
            .from('app_nom_medio_pago')
            .select('*')
            .eq('es_activo', true)
            .order('denominacion', ascending: true);
      } else {
        print('solo efectivo');
        response = await _supabase
            .from('app_nom_medio_pago')
            .select('*')
            .eq('es_activo', true)
            .eq('id', 1)
            .order('denominacion', ascending: true);
      }
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
