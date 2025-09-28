import 'package:flutter/material.dart';

class DashboardData {
  final int totalTiendas;
  final int tiendasActivas;
  final int tiendasPendientesRenovacion;
  final double ventasGlobales;
  final double dineroTotalVendido;
  final int totalProductosRegistrados;
  final List<ChartData> registroTiendasChart;
  final List<ChartData> ventasChart;

  DashboardData({
    required this.totalTiendas,
    required this.tiendasActivas,
    required this.tiendasPendientesRenovacion,
    required this.ventasGlobales,
    required this.dineroTotalVendido,
    required this.totalProductosRegistrados,
    required this.registroTiendasChart,
    required this.ventasChart,
  });

  factory DashboardData.mock() {
    return DashboardData(
      totalTiendas: 156,
      tiendasActivas: 142,
      tiendasPendientesRenovacion: 14,
      ventasGlobales: 25847.50,
      dineroTotalVendido: 1250000.00,
      totalProductosRegistrados: 12500,
      registroTiendasChart: [
        ChartData('Ene', 12),
        ChartData('Feb', 18),
        ChartData('Mar', 25),
        ChartData('Abr', 22),
        ChartData('May', 30),
        ChartData('Jun', 28),
        ChartData('Jul', 35),
        ChartData('Ago', 32),
        ChartData('Sep', 38),
        ChartData('Oct', 42),
        ChartData('Nov', 45),
        ChartData('Dic', 48),
      ],
      ventasChart: [
        ChartData('Ene', 85000),
        ChartData('Feb', 92000),
        ChartData('Mar', 108000),
        ChartData('Abr', 95000),
        ChartData('May', 125000),
        ChartData('Jun', 118000),
        ChartData('Jul', 142000),
        ChartData('Ago', 135000),
        ChartData('Sep', 158000),
        ChartData('Oct', 165000),
        ChartData('Nov', 172000),
        ChartData('Dic', 185000),
      ],
    );
  }
}

class ChartData {
  final String label;
  final double value;

  ChartData(this.label, this.value);
}

class KPIData {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String? trend;
  final bool isPositiveTrend;

  KPIData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.trend,
    this.isPositiveTrend = true,
  });
}
