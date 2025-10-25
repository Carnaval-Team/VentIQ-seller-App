import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/hr_models.dart';

/// Servicio para gestionar datos de Recursos Humanos (turnos, horas trabajadas, salarios)
class HRService {
  static final _supabase = Supabase.instance.client;

  /// Obtiene los turnos con sus trabajadores en un rango de fechas
  /// Incluye información de horas trabajadas y salarios calculados
  static Future<List<ShiftWithWorkers>> getShiftsWithWorkers({
    required int idTienda,
    required DateTime fechaDesde,
    required DateTime fechaHasta,
  }) async {
    try {
      // Ajustar fechas para incluir todo el día
      final fechaDesdeStart = DateTime(
        fechaDesde.year,
        fechaDesde.month,
        fechaDesde.day,
        0, 0, 0, 0, 0, // 00:00:00.000
      );
      final fechaHastaEnd = DateTime(
        fechaHasta.year,
        fechaHasta.month,
        fechaHasta.day,
        23, 59, 59, 999, 999, // 23:59:59.999
      );

      print('🔍 Obteniendo turnos con trabajadores...');
      print('  - Tienda: $idTienda');
      print('  - Desde: ${fechaDesdeStart.toIso8601String()}');
      print('  - Hasta: ${fechaHastaEnd.toIso8601String()}');

      // Obtener turnos en el rango de fechas
      final turnosResponse = await _supabase
          .from('app_dat_caja_turno')
          .select('''
            id,
            fecha_apertura,
            fecha_cierre,
            efectivo_inicial,
            efectivo_real,
            diferencia,
            estado,
            id_tpv,
            id_vendedor,
            app_dat_tpv!inner(
              denominacion,
              id_tienda
            ),
            app_dat_vendedor!inner(
              id_trabajador,
              app_dat_trabajadores(
                nombres,
                apellidos
              )
            ),
            app_nom_estado_operacion(
              denominacion
            )
          ''')
          .eq('app_dat_tpv.id_tienda', idTienda)
          .gte('fecha_apertura', fechaDesdeStart.toIso8601String())
          .lte('fecha_apertura', fechaHastaEnd.toIso8601String())
          .order('fecha_apertura', ascending: false);

      print('✅ Turnos obtenidos: ${turnosResponse.length}');

      // Obtener IDs de turnos para buscar trabajadores
      final turnoIds = (turnosResponse as List<dynamic>)
          .map((t) => t['id'] as int)
          .toList();

      if (turnoIds.isEmpty) {
        print('ℹ️ No hay turnos en el rango de fechas especificado');
        return [];
      }

      // Obtener trabajadores de todos los turnos
      final trabajadoresResponse = await _supabase
          .from('app_dat_turno_trabajadores')
          .select('''
            id,
            id_turno,
            id_trabajador,
            hora_entrada,
            hora_salida,
            horas_trabajadas,
            observaciones,
            app_dat_trabajadores(
              nombres,
              apellidos,
              salario_horas,
              id_roll,
              seg_roll(
                denominacion
              )
            )
          ''')
          .inFilter('id_turno', turnoIds)
          .order('hora_entrada', ascending: true);

      print('✅ Trabajadores obtenidos: ${trabajadoresResponse.length}');

      // Agrupar trabajadores por turno
      final trabajadoresPorTurno = <int, List<ShiftWorkerHours>>{};
      for (final trabajadorData in trabajadoresResponse as List<dynamic>) {
        final idTurno = trabajadorData['id_turno'] as int;
        final trabajadorInfo = trabajadorData['app_dat_trabajadores'] as Map<String, dynamic>?;
        final rolInfo = trabajadorInfo?['seg_roll'] as Map<String, dynamic>?;

        // 💰 Calcular salario total: horas_trabajadas * salario_hora
        final horasTrabajadas = (trabajadorData['horas_trabajadas'] as num?)?.toDouble();
        final salarioHora = (trabajadorInfo?['salario_horas'] as num?)?.toDouble() ?? 0.0;
        final salarioTotal = horasTrabajadas != null ? horasTrabajadas * salarioHora : 0.0;

        final worker = ShiftWorkerHours(
          id: trabajadorData['id'] as int,
          idTurno: idTurno,
          idTrabajador: trabajadorData['id_trabajador'] as int,
          trabajadorNombre: trabajadorInfo != null
              ? '${trabajadorInfo['nombres']} ${trabajadorInfo['apellidos']}'
              : 'Desconocido',
          rolNombre: rolInfo?['denominacion'] as String? ?? 'N/A',
          horaEntrada: DateTime.parse(trabajadorData['hora_entrada'] as String),
          horaSalida: trabajadorData['hora_salida'] != null
              ? DateTime.parse(trabajadorData['hora_salida'] as String)
              : null,
          horasTrabajadas: horasTrabajadas,
          salarioHora: salarioHora,
          salarioTotal: salarioTotal, // ✅ CORREGIDO: Calcular correctamente
          observaciones: trabajadorData['observaciones'] as String?,
        );

        if (!trabajadoresPorTurno.containsKey(idTurno)) {
          trabajadoresPorTurno[idTurno] = [];
        }
        trabajadoresPorTurno[idTurno]!.add(worker);
      }

      // Construir lista de turnos con trabajadores
      final shifts = <ShiftWithWorkers>[];
      for (final turnoData in turnosResponse) {
        final turnoId = turnoData['id'] as int;
        final tpvData = turnoData['app_dat_tpv'] as Map<String, dynamic>?;
        final vendedorData = turnoData['app_dat_vendedor'] as Map<String, dynamic>?;
        final trabajadorData = vendedorData?['app_dat_trabajadores'] as Map<String, dynamic>?;
        final estadoData = turnoData['app_nom_estado_operacion'] as Map<String, dynamic>?;

        final shift = ShiftWithWorkers(
          turnoId: turnoId,
          fechaApertura: DateTime.parse(turnoData['fecha_apertura'] as String),
          fechaCierre: turnoData['fecha_cierre'] != null
              ? DateTime.parse(turnoData['fecha_cierre'] as String)
              : null,
          estadoNombre: estadoData?['denominacion'] as String? ?? 'Desconocido',
          tpvDenominacion: tpvData?['denominacion'] as String? ?? 'N/A',
          vendedorNombre: trabajadorData != null
              ? '${trabajadorData['nombres']} ${trabajadorData['apellidos']}'
              : 'N/A',
          efectivoInicial: (turnoData['efectivo_inicial'] as num?)?.toDouble() ?? 0.0,
          efectivoReal: (turnoData['efectivo_real'] as num?)?.toDouble(),
          diferencia: (turnoData['diferencia'] as num?)?.toDouble(),
          trabajadores: trabajadoresPorTurno[turnoId] ?? [],
        );

        shifts.add(shift);
      }

      print('✅ Turnos procesados con trabajadores: ${shifts.length}');
      return shifts;
    } catch (e) {
      print('❌ Error obteniendo turnos con trabajadores: $e');
      rethrow;
    }
  }

  /// Obtiene un resumen de horas y salarios por período
  static Future<HRSummary> getHRSummary({
    required int idTienda,
    required DateTime fechaDesde,
    required DateTime fechaHasta,
  }) async {
    try {
      print('📊 Calculando resumen de RR.HH...');

      final shifts = await getShiftsWithWorkers(
        idTienda: idTienda,
        fechaDesde: fechaDesde,
        fechaHasta: fechaHasta,
      );

      // Calcular totales
      int totalTrabajadores = 0;
      double totalHorasTrabajadas = 0.0;
      double totalSalarios = 0.0;
      final salariosPorRol = <String, double>{};
      final trabajadoresUnicos = <int>{};

      for (final shift in shifts) {
        for (final worker in shift.trabajadores) {
          trabajadoresUnicos.add(worker.idTrabajador);
          
          if (worker.horasTrabajadas != null) {
            totalHorasTrabajadas += worker.horasTrabajadas!;
            totalSalarios += worker.salarioTotal;

            // Acumular por rol
            final rol = worker.rolNombre;
            salariosPorRol[rol] = (salariosPorRol[rol] ?? 0.0) + worker.salarioTotal;
          }
        }
      }

      totalTrabajadores = trabajadoresUnicos.length;

      final summary = HRSummary(
        fechaDesde: fechaDesde,
        fechaHasta: fechaHasta,
        totalTurnos: shifts.length,
        totalTrabajadores: totalTrabajadores,
        totalHorasTrabajadas: totalHorasTrabajadas,
        totalSalarios: totalSalarios,
        salariosPorRol: salariosPorRol,
      );

      print('✅ Resumen calculado:');
      print('  - Total turnos: ${summary.totalTurnos}');
      print('  - Total trabajadores: ${summary.totalTrabajadores}');
      print('  - Total horas: ${summary.totalHorasTrabajadas.toStringAsFixed(2)}');
      print('  - Total salarios: ${summary.totalSalariosFormatted}');

      return summary;
    } catch (e) {
      print('❌ Error calculando resumen de RR.HH.: $e');
      rethrow;
    }
  }
}
