import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dashboard_data.dart';

class DashboardService {
  final _supabase = Supabase.instance.client;
  
  Future<DashboardData> getDashboardData() async {
    try {
      debugPrint('📊 Obteniendo datos del dashboard...');
      
      // Obtener estadísticas generales (para uso futuro)
      // final stats = await StoreService.getSystemStats();
      
      // Total de tiendas
      final tiendasResponse = await _supabase
          .from('app_dat_tienda')
          .select('id, created_at');
      
      final totalTiendas = tiendasResponse.length;
      final tiendasActivas = totalTiendas; // Por ahora todas activas
      
      // Total de usuarios únicos
      final totalUsuarios = await _getTotalUsuarios();
      final usuariosActivos = totalUsuarios; // Por ahora todos activos
      
      // Ventas totales y del mes
      final ventasData = await _getVentasData();
      
      // Productos totales
      final productosResponse = await _supabase
          .from('app_dat_producto')
          .select('id')
          .count();
      
      final productosTotal = productosResponse.count;
      
      // Pedidos del día
      final pedidosDelDia = await _getPedidosDelDia();
      
      // Ventas por mes (últimos 12 meses)
      final ventasPorMes = await _getVentasPorMes();
      
      // Tiendas por plan
      final tiendasPorPlan = _getTiendasPorPlan(totalTiendas);
      
      // Top 5 tiendas por ventas
      final topTiendas = await _getTopTiendas();
      
      // Actividad reciente
      final actividadReciente = await _getActividadReciente();
      
      debugPrint('✅ Datos del dashboard obtenidos exitosamente');
      
      // Generar datos de gráficos
      final registroTiendasChart = _generateRegistroTiendasChart();
      final ventasChart = _generateVentasChart(ventasPorMes);
      
      return DashboardData(
        totalTiendas: totalTiendas,
        tiendasActivas: tiendasActivas,
        tiendasPendientesRenovacion: 0, // Por ahora 0, implementar después
        ventasGlobales: ventasData['total'] ?? 0.0,
        dineroTotalVendido: ventasData['total'] ?? 0.0,
        totalProductosRegistrados: productosTotal,
        registroTiendasChart: registroTiendasChart,
        ventasChart: ventasChart,
        totalUsuarios: totalUsuarios,
        usuariosActivos: usuariosActivos,
        ventasTotales: ventasData['total'] ?? 0.0,
        ventasDelMes: ventasData['mes'] ?? 0.0,
        productosTotal: productosTotal,
        pedidosDelDia: pedidosDelDia,
        ventasPorMes: ventasPorMes,
        tiendasPorPlan: tiendasPorPlan,
        topTiendas: topTiendas,
        actividadReciente: actividadReciente,
      );
    } catch (e) {
      debugPrint('❌ Error obteniendo datos del dashboard: $e');
      return DashboardData.mock();
    }
  }
  
  Future<int> _getTotalUsuarios() async {
    try {
      final gerentesResponse = await _supabase
          .from('app_dat_gerente')
          .select('uuid');
      
      final supervisoresResponse = await _supabase
          .from('app_dat_supervisor')
          .select('uuid');
      
      final vendedoresResponse = await _supabase
          .from('app_dat_vendedor')
          .select('uuid');
      
      final almacenerosResponse = await _supabase
          .from('app_dat_almacenero')
          .select('uuid');
      
      // Crear set de UUIDs únicos
      final uniqueUsers = <String>{};
      for (var gerente in gerentesResponse) {
        uniqueUsers.add(gerente['uuid']);
      }
      for (var supervisor in supervisoresResponse) {
        uniqueUsers.add(supervisor['uuid']);
      }
      for (var vendedor in vendedoresResponse) {
        uniqueUsers.add(vendedor['uuid']);
      }
      for (var almacenero in almacenerosResponse) {
        uniqueUsers.add(almacenero['uuid']);
      }
      
      return uniqueUsers.length;
    } catch (e) {
      debugPrint('Error obteniendo total de usuarios: $e');
      return 0;
    }
  }
  
  Future<Map<String, double>> _getVentasData() async {
    try {
      final ventasResponse = await _supabase
          .from('app_dat_operacion_venta')
          .select('importe_total, created_at');
      
      double ventasTotales = 0;
      double ventasDelMes = 0;
      final inicioMes = DateTime(DateTime.now().year, DateTime.now().month, 1);
      
      for (var venta in ventasResponse) {
        final importe = (venta['importe_total'] ?? 0).toDouble();
        ventasTotales += importe;
        
        final fechaVenta = DateTime.parse(venta['created_at']);
        if (fechaVenta.isAfter(inicioMes)) {
          ventasDelMes += importe;
        }
      }
      
      return {'total': ventasTotales, 'mes': ventasDelMes};
    } catch (e) {
      debugPrint('Error obteniendo datos de ventas: $e');
      return {'total': 0, 'mes': 0};
    }
  }
  
  Future<int> _getPedidosDelDia() async {
    try {
      final inicioDia = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      
      final pedidosHoyResponse = await _supabase
          .from('app_dat_operacion_venta')
          .select('id')
          .gte('created_at', inicioDia.toIso8601String())
          .count();
      
      return pedidosHoyResponse.count;
    } catch (e) {
      debugPrint('Error obteniendo pedidos del día: $e');
      return 0;
    }
  }
  
  Future<List<double>> _getVentasPorMes() async {
    final ventasPorMes = <double>[];
    final ahora = DateTime.now();
    
    for (int i = 11; i >= 0; i--) {
      final mes = DateTime(ahora.year, ahora.month - i, 1);
      final mesSiguiente = DateTime(ahora.year, ahora.month - i + 1, 1);
      
      try {
        final ventasMesResponse = await _supabase
            .from('app_dat_operacion_venta')
            .select('importe_total')
            .gte('created_at', mes.toIso8601String())
            .lt('created_at', mesSiguiente.toIso8601String());
        
        double totalMes = 0;
        for (var venta in ventasMesResponse) {
          totalMes += (venta['importe_total'] ?? 0).toDouble();
        }
        
        ventasPorMes.add(totalMes);
      } catch (e) {
        ventasPorMes.add(0);
      }
    }
    
    return ventasPorMes;
  }
  
  Map<String, int> _getTiendasPorPlan(int totalTiendas) {
    return {
      'Básico': (totalTiendas * 0.4).round(),
      'Profesional': (totalTiendas * 0.3).round(),
      'Empresarial': (totalTiendas * 0.2).round(),
      'Premium': (totalTiendas * 0.1).round(),
    };
  }
  
  Future<List<Map<String, dynamic>>> _getTopTiendas() async {
    // Por ahora retornar lista vacía, implementar cuando tengamos la estructura correcta
    return [];
  }
  
  Future<List<Map<String, dynamic>>> _getActividadReciente() async {
    final actividades = <Map<String, dynamic>>[];
    
    try {
      // Últimas tiendas creadas
      final tiendasRecientes = await _supabase
          .from('app_dat_tienda')
          .select('denominacion, created_at')
          .order('created_at', ascending: false)
          .limit(2);
      
      for (var tienda in tiendasRecientes) {
        actividades.add({
          'tipo': 'nueva_tienda',
          'descripcion': 'Nueva tienda: ${tienda['denominacion']}',
          'tiempo': _getTimeAgo(DateTime.parse(tienda['created_at'])),
        });
      }
    } catch (e) {
      debugPrint('Error obteniendo actividad reciente: $e');
    }
    
    return actividades;
  }
  
  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} horas';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} días';
    } else {
      return '${(difference.inDays / 7).round()} semanas';
    }
  }
  
  List<ChartData> _generateRegistroTiendasChart() {
    final meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    final List<ChartData> data = [];
    
    for (int i = 0; i < meses.length; i++) {
      // Por ahora datos simulados, después implementar con datos reales
      data.add(ChartData(meses[i], (10 + i * 3).toDouble()));
    }
    
    return data;
  }
  
  List<ChartData> _generateVentasChart(List<double> ventasPorMes) {
    final meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    final List<ChartData> data = [];
    
    for (int i = 0; i < meses.length && i < ventasPorMes.length; i++) {
      data.add(ChartData(meses[i], ventasPorMes[i]));
    }
    
    // Si no hay suficientes datos, llenar con ceros
    while (data.length < 12) {
      data.add(ChartData(meses[data.length], 0));
    }
    
    return data;
  }
}
