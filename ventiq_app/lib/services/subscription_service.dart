import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/subscription.dart';
import '../models/subscription_plan.dart';

class SubscriptionService {
  final _supabase = Supabase.instance.client;

  /// Obtiene la suscripción más reciente de una tienda (activa o vencida)
  Future<Subscription?> getCurrentSubscription(int idTienda) async {
    try {
      print('🔍 Obteniendo suscripción actual para tienda: $idTienda');
      
      final response = await _supabase
          .from('app_suscripciones')
          .select('''
            *,
            app_suscripciones_plan (
              id,
              denominacion,
              descripcion,
              precio_mensual,
              duracion_trial_dias,
              limite_tiendas,
              limite_usuarios,
              funciones_habilitadas,
              es_activo
            )
          ''')
          .eq('id_tienda', idTienda)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        print('⚠️ No se encontró suscripción para la tienda $idTienda');
        return null;
      }

      print('✅ Suscripción encontrada para tienda $idTienda');
      return Subscription.fromJson(response);
    } catch (e) {
      print('❌ Error obteniendo suscripción actual: $e');
      return null;
    }
  }

  /// Obtiene la suscripción activa de una tienda
  Future<Subscription?> getActiveSubscription(int idTienda) async {
    try {
      print('🔍 Obteniendo suscripción activa para tienda: $idTienda');
      
      final response = await _supabase
          .from('app_suscripciones')
          .select('''
            *,
            app_suscripciones_plan (
              id,
              denominacion,
              descripcion,
              precio_mensual,
              duracion_trial_dias,
              limite_tiendas,
              limite_usuarios,
              funciones_habilitadas,
              es_activo
            )
          ''')
          .eq('id_tienda', idTienda)
          .eq('estado', 1) // Solo suscripciones activas
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        print('⚠️ No se encontró suscripción activa para la tienda $idTienda');
        return null;
      }

      if (response is! Map<String, dynamic>) {
        print('❌ Respuesta inesperada del servidor: ${response.runtimeType}');
        return null;
      }

      try {
        final subscription = Subscription.fromJson(response);
        print('✅ Suscripción activa encontrada: ${subscription.planDenominacion}');
        return subscription;
      } catch (e) {
        print('❌ Error procesando datos de suscripción: $e');
        print('   Datos recibidos: $response');
        return null;
      }
    } catch (e) {
      print('❌ Error obteniendo suscripción activa: $e');
      print('   Tipo de error: ${e.runtimeType}');
      return null;
    }
  }

  /// Obtiene todas las suscripciones de una tienda (historial completo)
  Future<List<Subscription>> getSubscriptionHistory(int idTienda) async {
    try {
      print('🔍 Obteniendo historial de suscripciones para tienda: $idTienda');
      
      final response = await _supabase
          .from('app_suscripciones')
          .select('''
            *,
            app_suscripciones_plan (
              id,
              denominacion,
              descripcion,
              precio_mensual,
              duracion_trial_dias,
              limite_tiendas,
              limite_usuarios,
              funciones_habilitadas,
              es_activo
            )
          ''')
          .eq('id_tienda', idTienda)
          .order('created_at', ascending: false);

      if (response is! List) {
        print('❌ Respuesta inesperada del servidor: ${response.runtimeType}');
        return [];
      }

      final subscriptions = <Subscription>[];
      for (int i = 0; i < response.length; i++) {
        try {
          final item = response[i];
          if (item is Map<String, dynamic>) {
            print('🔍 Procesando suscripción $i: ${item['id']}');
            
            // Log específico para funciones_habilitadas
            if (item['app_suscripciones_plan'] != null) {
              final plan = item['app_suscripciones_plan'];
              if (plan['funciones_habilitadas'] != null) {
                print('   Funciones habilitadas tipo: ${plan['funciones_habilitadas'].runtimeType}');
                print('   Funciones habilitadas valor: ${plan['funciones_habilitadas']}');
              }
            }
            
            subscriptions.add(Subscription.fromJson(item));
            print('✅ Suscripción $i procesada correctamente');
          } else {
            print('⚠️ Item $i no es un Map<String, dynamic>: ${item.runtimeType}');
          }
        } catch (e, stackTrace) {
          print('❌ Error procesando suscripción $i: $e');
          print('   Datos: ${response[i]}');
          print('   Stack trace: $stackTrace');
        }
      }

      print('✅ Encontradas ${subscriptions.length} suscripciones en el historial');
      return subscriptions;
    } catch (e) {
      print('❌ Error obteniendo historial de suscripciones: $e');
      print('   Tipo de error: ${e.runtimeType}');
      return [];
    }
  }

  /// Obtiene todos los planes de suscripción disponibles
  Future<List<SubscriptionPlan>> getAvailablePlans() async {
    try {
      print('🔍 Obteniendo planes de suscripción disponibles');
      
      final response = await _supabase
          .from('app_suscripciones_plan')
          .select('*')
          .eq('es_activo', true)
          .order('id', ascending: true);

      final plans = (response as List)
          .map((item) => SubscriptionPlan.fromJson(item))
          .toList();

      print('✅ Encontrados ${plans.length} planes disponibles');
      return plans;
    } catch (e) {
      print('❌ Error obteniendo planes de suscripción: $e');
      return [];
    }
  }

  /// Verifica si una tienda tiene una función habilitada en su plan
  Future<bool> hasFeatureEnabled(int idTienda, String feature) async {
    try {
      final subscription = await getActiveSubscription(idTienda);
      if (subscription == null) return false;

      final funciones = subscription.planFuncionesHabilitadas;
      if (funciones == null) return false;

      return funciones[feature] == true;
    } catch (e) {
      print('❌ Error verificando función habilitada: $e');
      return false;
    }
  }

  /// Obtiene las funciones habilitadas para una tienda
  Future<Map<String, bool>> getEnabledFeatures(int idTienda) async {
    try {
      final subscription = await getActiveSubscription(idTienda);
      if (subscription == null) return {};

      final funciones = subscription.planFuncionesHabilitadas;
      if (funciones == null) return {};

      return Map<String, bool>.from(funciones);
    } catch (e) {
      print('❌ Error obteniendo funciones habilitadas: $e');
      return {};
    }
  }

  /// Verifica si la suscripción está próxima a vencer (3 días o menos)
  Future<Map<String, dynamic>?> checkSubscriptionExpiration(int idTienda) async {
    try {
      final subscription = await getCurrentSubscription(idTienda);
      if (subscription == null) return null;

      final diasRestantes = subscription.diasRestantes;
      
      // Si tiene fecha fin y quedan 3 días o menos (pero no está vencida)
      if (subscription.fechaFin != null && diasRestantes >= 0 && diasRestantes <= 3) {
        return {
          'diasRestantes': diasRestantes,
          'fechaFin': subscription.fechaFin,
          'planNombre': subscription.planDenominacion ?? 'Plan desconocido',
          'estado': subscription.estadoText,
        };
      }

      return null;
    } catch (e) {
      print('❌ Error verificando expiración de suscripción: $e');
      return null;
    }
  }
}
