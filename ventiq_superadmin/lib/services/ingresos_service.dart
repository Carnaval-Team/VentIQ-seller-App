import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IngresosService {
  static final _supabase = Supabase.instance.client;

  /// Obtiene la tasa de cambio USD a CUP actual
  static Future<double> getUsdToCupRate() async {
    try {
      final rates = await _supabase
          .from('tasas_conversion')
          .select('tasa')
          .eq('moneda_origen', 'USD')
          .order('fecha_actualizacion', ascending: false)
          .limit(1)
          .maybeSingle();

      if (rates != null) {
        return (rates['tasa'] as num?)?.toDouble() ?? 440.0;
      }
      return 440.0; // Fallback
    } catch (e) {
      debugPrint('Error obteniendo tasa USD→CUP: $e');
      return 440.0;
    }
  }

  /// Calcula la distribución de ganancias con agentes individuales
  /// Retorna un mapa con los montos en CUP para cada beneficiario
  /// licencias: lista de licencias con sus datos (incluye agente_nombre)
  /// tasaCambio: tasa de cambio USD a CUP
  static Map<String, dynamic> calcularDistribucionConAgentes(
    List<Map<String, dynamic>> licencias,
    double tasaCambio,
  ) {
    // Convertir todos los precios a CUP
    double montoPagoCupTotal = 0.0;
    for (var lic in licencias) {
      final precioUsd = lic['precio_usd'] as double? ?? 0.0;
      montoPagoCupTotal += precioUsd * tasaCambio;
    }

    // 500 CUP por CATALOGO de cada licencia (se reparte a partes iguales entre 4)
    const double catalogoPorLicencia = 500.0;
    final double catalogoTotal = catalogoPorLicencia * licencias.length;
    final double catalogoPorPersona = catalogoTotal / 4; // Repartido entre Odeimy, Cesar, Jandro, Yoelvis

    // Resto después de descontar CATALOGO
    final double resto = montoPagoCupTotal - catalogoTotal;

    // Del resto:
    // - 45% para Odeimys
    // - 5% para agentes (distribuido según cada tienda)
    // - 50% a partes iguales (Cesar, Jandro, Yoelvis)

    final double odeimysDelResto = resto * 0.45;
    final double agenteDelRestoTotal = resto * 0.05;
    final double restoPorRepartir = resto * 0.50;
    final double cesarDelResto = restoPorRepartir / 3;
    final double jandroDelResto = restoPorRepartir / 3;
    final double yoelvisDelResto = restoPorRepartir / 3;

    // Calcular comisión de agentes por tienda
    final Map<String, double> comisionPorAgente = {};
    for (var lic in licencias) {
      final agenteNombre = lic['agente_nombre'] as String?;
      if (agenteNombre != null && agenteNombre.isNotEmpty) {
        final precioUsd = lic['precio_usd'] as double? ?? 0.0;
        final precioCup = precioUsd * tasaCambio;
        final comisionAgente = precioCup * 0.05; // 5% de este plan
        comisionPorAgente[agenteNombre] =
            (comisionPorAgente[agenteNombre] ?? 0.0) + comisionAgente;
      }
    }

    return {
      'monto_total_cup': montoPagoCupTotal,
      'catalogo_total': catalogoTotal,
      'catalogo_por_persona': catalogoPorPersona,
      'odeimys_catalogo': catalogoPorPersona,
      'yoelvis_catalogo': catalogoPorPersona,
      'cesar_catalogo': catalogoPorPersona,
      'jandro_catalogo': catalogoPorPersona,
      'odeimys_resto': odeimysDelResto,
      'agente_total': agenteDelRestoTotal,
      'agentes_por_nombre': comisionPorAgente,
      'cesar_resto': cesarDelResto,
      'jandro_resto': jandroDelResto,
      'yoelvis_resto': yoelvisDelResto,
      'odeimys_total': catalogoPorPersona + odeimysDelResto,
      'yoelvis_total': catalogoPorPersona + yoelvisDelResto,
      'cesar_total': catalogoPorPersona + cesarDelResto,
      'jandro_total': catalogoPorPersona + jandroDelResto,
    };
  }

  /// Calcula la distribución de ganancias (método antiguo, mantener para compatibilidad)
  /// Retorna un mapa con los montos en CUP para cada beneficiario
  /// montoPagoCup: monto total en CUP de todas las licencias
  /// cantidadLicencias: cantidad de licencias activas
  static Map<String, double> calcularDistribucion(
    double montoPagoCup,
    int cantidadLicencias,
  ) {
    // 500 CUP por CATALOGO de cada licencia (se reparte a partes iguales entre 4)
    const double catalogoPorLicencia = 500.0;
    final double catalogoTotal = catalogoPorLicencia * cantidadLicencias;
    final double catalogoPorPersona = catalogoTotal / 4; // Repartido entre 4

    // Resto después de descontar CATALOGO
    final double resto = montoPagoCup - catalogoTotal;

    // Del resto:
    // - 45% para Odeimys
    // - 5% para agente
    // - 50% a partes iguales (Cesar, Jandro, Yoelvis)

    final double odeimysDelResto = resto * 0.45;
    final double agenteDelResto = resto * 0.05;
    final double restoPorRepartir = resto * 0.50;
    final double cesarDelResto = restoPorRepartir / 3;
    final double jandroDelResto = restoPorRepartir / 3;
    final double yoelvisDelResto = restoPorRepartir / 3;

    return {
      'catalogo_total': catalogoTotal,
      'catalogo_por_persona': catalogoPorPersona,
      'odeimys_catalogo': catalogoPorPersona,
      'yoelvis_catalogo': catalogoPorPersona,
      'cesar_catalogo': catalogoPorPersona,
      'jandro_catalogo': catalogoPorPersona,
      'odeimys_resto': odeimysDelResto,
      'agente': agenteDelResto,
      'cesar_resto': cesarDelResto,
      'jandro_resto': jandroDelResto,
      'yoelvis_resto': yoelvisDelResto,
      'odeimys_total': catalogoPorPersona + odeimysDelResto,
      'yoelvis_total': catalogoPorPersona + yoelvisDelResto,
      'cesar_total': catalogoPorPersona + cesarDelResto,
      'jandro_total': catalogoPorPersona + jandroDelResto,
    };
  }

  /// Obtiene las licencias activas con sus precios (excluyendo planes gratuitos y vencidos)
  static Future<List<Map<String, dynamic>>> getLicenciasActivasConPrecio() async {
    try {
      final response = await _supabase
          .from('app_suscripciones')
          .select('''
            id,
            id_tienda,
            id_plan,
            id_agente,
            fecha_fin,
            app_dat_tienda!inner(denominacion),
            app_suscripciones_plan!inner(denominacion, precio_mensual),
            app_dat_agente(nombre, apellidos)
          ''')
          .eq('estado', 1)
          .gt('app_suscripciones_plan.precio_mensual', 0)
          .order('fecha_fin', ascending: true);

      final licencias = <Map<String, dynamic>>[];
      final ahora = DateTime.now();

      for (var lic in response) {
        final tienda = lic['app_dat_tienda'];
        final plan = lic['app_suscripciones_plan'];
        final agente = lic['app_dat_agente'];
        final precioUsd = (plan?['precio_mensual'] as num?)?.toDouble() ?? 0.0;
        final fechaFin = lic['fecha_fin'] as String?;

        // Filtro: solo planes pagos y no vencidos
        if (precioUsd > 0 && fechaFin != null) {
          final fechaVencimiento = DateTime.tryParse(fechaFin);
          if (fechaVencimiento != null && fechaVencimiento.isAfter(ahora)) {
            licencias.add({
              'id': lic['id'],
              'tienda_nombre': tienda?['denominacion'] ?? 'Sin tienda',
              'plan_nombre': plan?['denominacion'] ?? 'Sin plan',
              'precio_usd': precioUsd,
              'agente_nombre': agente != null
                  ? '${agente['nombre']} ${agente['apellidos']}'
                  : null,
              'fecha_fin': fechaFin,
            });
          }
        }
      }

      return licencias;
    } catch (e) {
      debugPrint('Error obteniendo licencias activas: $e');
      return [];
    }
  }
}
