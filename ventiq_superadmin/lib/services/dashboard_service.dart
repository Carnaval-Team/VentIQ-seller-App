import '../models/dashboard_data.dart';

class DashboardService {
  // Simulación de datos del dashboard - En producción conectar con Supabase
  Future<DashboardData> getDashboardData() async {
    try {
      // Simular delay de red
      await Future.delayed(const Duration(seconds: 1));
      
      // En producción, hacer consulta a la base de datos
      return DashboardData.mock();
    } catch (e) {
      throw Exception('Error al cargar datos del dashboard: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> getGlobalStats() async {
    try {
      await Future.delayed(const Duration(milliseconds: 800));
      
      return {
        'total_tiendas': 156,
        'tiendas_activas': 142,
        'tiendas_inactivas': 14,
        'nuevas_tiendas_mes': 12,
        'total_usuarios': 1247,
        'usuarios_activos_mes': 892,
        'total_productos': 125000,
        'productos_agregados_mes': 2500,
        'ventas_totales_mes': 1250000.00,
        'ingresos_licencias_mes': 45000.00,
        'crecimiento_tiendas': 8.5, // porcentaje
        'crecimiento_ventas': 12.3, // porcentaje
        'satisfaccion_cliente': 4.7, // de 5
      };
    } catch (e) {
      throw Exception('Error al cargar estadísticas globales: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getTopTiendas({int limit = 10}) async {
    try {
      await Future.delayed(const Duration(milliseconds: 600));
      
      return [
        {
          'id': 3,
          'nombre': 'Farmacia San Miguel',
          'ventas_mes': 78000.00,
          'crecimiento': 15.2,
          'ubicacion': 'La Vega, RD',
        },
        {
          'id': 1,
          'nombre': 'Supermercado Central',
          'ventas_mes': 45000.00,
          'crecimiento': 8.7,
          'ubicacion': 'Santo Domingo, RD',
        },
        {
          'id': 5,
          'nombre': 'Autoservicio Norte',
          'ventas_mes': 32000.00,
          'crecimiento': 22.1,
          'ubicacion': 'Santiago, RD',
        },
        {
          'id': 2,
          'nombre': 'Minimarket La Esquina',
          'ventas_mes': 12000.00,
          'crecimiento': 5.4,
          'ubicacion': 'Santiago, RD',
        },
        {
          'id': 4,
          'nombre': 'Colmado Don Juan',
          'ventas_mes': 5000.00,
          'crecimiento': -2.1,
          'ubicacion': 'San Pedro de Macorís, RD',
        },
      ];
    } catch (e) {
      throw Exception('Error al cargar top tiendas: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getLicenciasProximasVencer({int dias = 30}) async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      
      return [
        {
          'tienda_id': 2,
          'tienda_nombre': 'Minimarket La Esquina',
          'dias_restantes': 15,
          'tipo_licencia': 'gratuita',
          'fecha_vencimiento': DateTime.now().add(const Duration(days: 15)),
        },
        {
          'tienda_id': 7,
          'tienda_nombre': 'Panadería El Buen Pan',
          'dias_restantes': 8,
          'tipo_licencia': 'premium',
          'fecha_vencimiento': DateTime.now().add(const Duration(days: 8)),
        },
        {
          'tienda_id': 12,
          'tienda_nombre': 'Ferretería Los Hermanos',
          'dias_restantes': 25,
          'tipo_licencia': 'enterprise',
          'fecha_vencimiento': DateTime.now().add(const Duration(days: 25)),
        },
      ];
    } catch (e) {
      throw Exception('Error al cargar licencias próximas a vencer: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> getActivitySummary() async {
    try {
      await Future.delayed(const Duration(milliseconds: 400));
      
      return {
        'nuevos_registros_hoy': 5,
        'ventas_hoy': 25847.50,
        'usuarios_conectados': 234,
        'alertas_sistema': 3,
        'tickets_soporte': 12,
        'actualizaciones_pendientes': 2,
      };
    } catch (e) {
      throw Exception('Error al cargar resumen de actividad: ${e.toString()}');
    }
  }
}
