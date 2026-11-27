import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/supplier_payment_model.dart';
import 'inventtia_payment_service.dart';
import 'supplier_payment_service.dart';

class CobroLicencia {
  final int suscripcionId;
  final int? tiendaId;
  final String tienda;
  final String plan;
  final double planUsd;
  final double cupTeorico;
  double recibidoUsd;
  double recibidoCup;
  String transaccion;
  final int? agenteId;
  final String? agenteNombre;
  final DateTime periodo;

  /// Nombres de las tiendas secundarias agrupadas bajo esta principal.
  final List<String> secundarias = [];

  /// Nombre de la principal cuando esta fila es una secundaria sin cobro
  /// propio de la principal en el período.
  String? secundariaDe;

  CobroLicencia({
    required this.suscripcionId,
    this.tiendaId,
    required this.tienda,
    required this.plan,
    required this.planUsd,
    required this.cupTeorico,
    required this.recibidoUsd,
    required this.recibidoCup,
    required this.transaccion,
    required this.agenteId,
    required this.agenteNombre,
    required this.periodo,
  });

  double get agente20 => recibidoCup * 0.20;
  double get quedaInventtia => recibidoCup - agente20;
}

class PersonaReparto {
  final int id;
  final String nombre;
  final String? tarjeta;
  final bool esSocio;

  /// Id del agente Carnaval (`inventtia_agentes`) cuya comisión 1%
  /// alimenta `agenteCarnaval`; null si la persona no cobra por esa vía.
  final int? agenteCarnavalId;
  double parteIgual = 0;
  double despliegue20 = 0;
  double carnavalGlobal = 0;
  double agenteCarnaval = 0;

  PersonaReparto({
    required this.id,
    required this.nombre,
    required this.tarjeta,
    required this.esSocio,
    this.agenteCarnavalId,
  });

  double get total =>
      parteIgual + despliegue20 + carnavalGlobal + agenteCarnaval;
}

class RepartoInventtia {
  final List<CobroLicencia> cobros;
  final List<PersonaReparto> personas;
  final double pagoProveedoresCup;
  final double comisionCarnavalCup;
  final int socios;
  final List<SupplierPaymentSummary> proveedores;
  final bool usoRenovaciones;
  final String? aviso;

  RepartoInventtia({
    required this.cobros,
    required this.personas,
    required this.pagoProveedoresCup,
    required this.comisionCarnavalCup,
    required this.socios,
    required this.proveedores,
    required this.usoRenovaciones,
    this.aviso,
  });
}

class _TiendasPrueba {
  final Set<int> ids;
  final Set<int> carnaval;
  const _TiendasPrueba(this.ids, this.carnaval);
}

class InventtiaRepartoService {
  static final _supabase = Supabase.instance.client;
  static const double _pct = 0.01;

  static Future<RepartoInventtia> cargar({
    required DateTime desde,
    required DateTime hasta,
    required DateTime licenciaMes,
  }) async {
    final tasa = (await InventtiaPaymentService.getExchangeRates()).valorUsd;
    final personasRows = await _personas();
    final suscripciones = await _suscripciones();
    final mesLicencia = DateTime(licenciaMes.year, licenciaMes.month, 1);
    final renovaciones = await _renovacionesEnRango(mesLicencia, mesLicencia);
    final ajustes = await _ajustes();
    final agents = await InventtiaPaymentService.getAgents(onlyActive: true);
    final proveedores = await SupplierPaymentService.getSupplierPayments(desde, hasta);
    final prueba = await _tiendasPrueba();

    final porTienda = <int, Map<String, dynamic>>{};
    for (final s in suscripciones) {
      final idTienda = (s['id_tienda'] as num?)?.toInt();
      if (idTienda != null && !prueba.ids.contains(idTienda)) {
        // Si la tienda tiene varias suscripciones activas gana la de id
        // mayor (la más reciente): las duplicadas viejas no cuentan dos veces.
        final previa = porTienda[idTienda];
        final idActual = (s['id'] as num?)?.toInt() ?? 0;
        final idPrevia = (previa?['id'] as num?)?.toInt() ?? 0;
        if (previa == null || idActual > idPrevia) {
          porTienda[idTienda] = s;
        }
      }
    }

    final cobros = <CobroLicencia>[];
    final usoRenovaciones = renovaciones.isNotEmpty;
    final renovacionesUnicas = _unaRenovacionPorTiendaMes(renovaciones, porTienda);
    if (usoRenovaciones) {
      for (final r in renovacionesUnicas) {
        final idTienda = (r['id_tienda'] as num?)?.toInt();
        final sus = idTienda == null ? null : porTienda[idTienda];
        if (sus == null) continue;
        // Resumen de un mes en el que la licencia ya estaba vencida:
        // dato inconsistente, no se cobra (limpiar con el script SQL).
        final vencimiento = DateTime.tryParse(
          sus['fecha_fin']?.toString() ?? '',
        );
        if (vencimiento != null && vencimiento.isBefore(mesLicencia)) {
          continue;
        }
        final usd = (r['total_pagado'] as num?)?.toDouble() ?? 0;
        cobros.add(_cobro(
          sus: sus,
          planUsd: usd,
          tasa: tasa,
          periodo: DateTime((r['id_anno'] as num).toInt(), (r['id_mes'] as num).toInt(), 1),
          ajustes: ajustes,
        ));
      }
    } else {
      final periodo = mesLicencia;
      final vistas = <int>{};
      for (final sus in suscripciones) {
        final idTienda = (sus['id_tienda'] as num?)?.toInt();
        if (idTienda == null || prueba.ids.contains(idTienda)) continue;
        // Un cobro por tienda: la suscripción elegida en porTienda.
        if (porTienda[idTienda]?['id'] != sus['id']) continue;
        if (!vistas.add(idTienda)) continue;
        // Solo se cobran licencias vigentes en el mes consultado:
        // vencida antes del mes = no entra al reparto (revocarla la saca del todo).
        final vencimiento = DateTime.tryParse(
          sus['fecha_fin']?.toString() ?? '',
        );
        if (vencimiento != null && vencimiento.isBefore(mesLicencia)) {
          continue;
        }
        final plan = sus['app_suscripciones_plan'];
        final usd = plan is Map ? (plan['precio_mensual'] as num?)?.toDouble() ?? 0 : 0.0;
        if (usd <= 0) continue;
        cobros.add(_cobro(
          sus: sus,
          planUsd: usd,
          tasa: tasa,
          periodo: periodo,
          ajustes: ajustes,
        ));
      }
    }

    final grupos = await _gruposMultitienda();
    final cobrosAgrupados = agruparCobros(
      cobros,
      grupos.$1,
      grupos.$2,
    )
      // Fuera las filas con pago 0 (planes gratuitos o renovaciones basura
      // sin monto): el reparto es solo sobre lo que realmente se cobra.
      ..removeWhere(
        (c) => c.planUsd <= 0 && c.recibidoUsd <= 0 && c.recibidoCup <= 0,
      )
      ..sort((a, b) => a.tienda.toLowerCase().compareTo(b.tienda.toLowerCase()));

    final personas = personasRows.map((row) {
      return PersonaReparto(
        id: (row['id'] as num).toInt(),
        nombre: '${row['nombre'] ?? ''} ${row['apellidos'] ?? ''}'.trim(),
        tarjeta: row['tarjeta']?.toString(),
        esSocio: row['es_socio'] == true && row['estado'] == 1,
        agenteCarnavalId: (row['id_agente_carnaval'] as num?)?.toInt(),
      );
    }).toList();

    final porId = {for (final p in personas) p.id: p};
    final socios = personas.where((p) => p.esSocio).length;
    final neto = cobrosAgrupados.fold<double>(0, (s, c) => s + c.quedaInventtia);
    final parte = socios > 0 ? neto / socios : 0.0;

    final proveedoresPago = proveedores
        .where((p) => !prueba.carnaval.contains(p.id))
        .toList();
    final pagoPorProveedor = <int, double>{
      for (final p in proveedoresPago) p.id: p.totalCup - p.excluidoCup,
    };
    final pagoProveedores = pagoPorProveedor.values.fold<double>(0, (s, v) => s + v);
    final comision = pagoProveedores * _pct;
    final parteCarnaval = socios > 0 ? comision / socios : 0.0;

    for (final p in personas) {
      if (p.esSocio) {
        p.parteIgual = parte;
        p.carnavalGlobal = parteCarnaval;
      }
    }
    for (final c in cobrosAgrupados) {
      final agente = c.agenteId == null ? null : porId[c.agenteId!];
      if (agente != null) agente.despliegue20 += c.agente20;
    }

    final storesByAgent = <int, List<int>>{};
    for (final agent in agents) {
      storesByAgent[agent.id] = agent.proveedorIds;
    }
    for (final row in personasRows) {
      final carnavalId = (row['id_agente_carnaval'] as num?)?.toInt();
      final persona = porId[(row['id'] as num).toInt()];
      if (carnavalId == null || persona == null) continue;
      final tiendas = storesByAgent[carnavalId] ?? const <int>[];
      var base = 0.0;
      for (final id in tiendas) {
        base += pagoPorProveedor[id] ?? 0;
      }
      persona.agenteCarnaval = base * _pct;
    }

    final visibles = personas.where((p) => p.esSocio || p.total > 0.005).toList()
      ..sort((a, b) {
        if (a.esSocio != b.esSocio) return a.esSocio ? -1 : 1;
        return b.total.compareTo(a.total);
      });

    return RepartoInventtia(
      cobros: cobrosAgrupados,
      personas: visibles,
      pagoProveedoresCup: pagoProveedores,
      comisionCarnavalCup: comision,
      socios: socios,
      proveedores: proveedoresPago,
      usoRenovaciones: usoRenovaciones,
      aviso: socios == 0
          ? 'No hay socios marcados. En Agentes activa "Socio" en Odeimys, Cesar y Yoelvis.'
          : null,
    );
  }

  static Future<void> guardarAjuste(CobroLicencia cobro) async {
    final periodo =
        '${cobro.periodo.year.toString().padLeft(4, '0')}-${cobro.periodo.month.toString().padLeft(2, '0')}-01';
    await _supabase.from('app_dat_cobro_licencia').upsert({
      'id_suscripcion': cobro.suscripcionId,
      'periodo': periodo,
      'recibido_usd': cobro.recibidoUsd,
      'recibido_cup': cobro.recibidoCup,
      'transaccion': cobro.transaccion.trim().isEmpty ? null : cobro.transaccion.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'id_suscripcion,periodo');
  }

  static CobroLicencia _cobro({
    required Map<String, dynamic> sus,
    required double planUsd,
    required double tasa,
    required DateTime periodo,
    required Map<String, Map<String, dynamic>> ajustes,
  }) {
    final id = (sus['id'] as num).toInt();
    final key = '$id-${periodo.year}-${periodo.month}';
    final ajuste = ajustes[key];
    final teorico = planUsd * (tasa <= 0 ? 1 : tasa);
    final tienda = sus['app_dat_tienda'];
    final plan = sus['app_suscripciones_plan'];
    final agente = sus['app_dat_agente'];
    return CobroLicencia(
      suscripcionId: id,
      tiendaId: (sus['id_tienda'] as num?)?.toInt(),
      tienda: tienda is Map ? (tienda['denominacion']?.toString() ?? 'Tienda') : 'Tienda',
      plan: plan is Map ? (plan['denominacion']?.toString() ?? '') : '',
      planUsd: planUsd,
      cupTeorico: teorico,
      recibidoUsd: (ajuste?['recibido_usd'] as num?)?.toDouble() ?? planUsd,
      recibidoCup: (ajuste?['recibido_cup'] as num?)?.toDouble() ?? teorico,
      transaccion: ajuste?['transaccion']?.toString() ?? '',
      agenteId: (sus['id_agente'] as num?)?.toInt(),
      agenteNombre: agente is Map
          ? '${agente['nombre'] ?? ''} ${agente['apellidos'] ?? ''}'.trim()
          : null,
      periodo: periodo,
    );
  }

  static List<Map<String, dynamic>> _unaRenovacionPorTiendaMes(
    List<Map<String, dynamic>> renovaciones,
    Map<int, Map<String, dynamic>> porTienda,
  ) {
    final elegida = <String, Map<String, dynamic>>{};
    for (final row in renovaciones) {
      final idTienda = (row['id_tienda'] as num?)?.toInt();
      final anno = (row['id_anno'] as num?)?.toInt();
      final mes = (row['id_mes'] as num?)?.toInt();
      if (idTienda == null || anno == null || mes == null) continue;
      final key = '$idTienda-$anno-$mes';
      final previa = elegida[key];
      if (previa == null || _prefiereRenovacion(row, previa, porTienda[idTienda])) {
        elegida[key] = row;
      }
    }
    return elegida.values.toList();
  }

  /// Si en el mes hay dos planes, se queda el de la licencia actual.
  static bool _prefiereRenovacion(
    Map<String, dynamic> candidata,
    Map<String, dynamic> actual,
    Map<String, dynamic>? suscripcion,
  ) {
    final planLicencia = (suscripcion?['id_plan'] as num?)?.toInt();
    final planCandidata = (candidata['id_plan'] as num?)?.toInt();
    final planActual = (actual['id_plan'] as num?)?.toInt();
    final candidataVigente = planLicencia != null && planCandidata == planLicencia;
    final actualVigente = planLicencia != null && planActual == planLicencia;
    if (candidataVigente != actualVigente) return candidataVigente;
    final idCandidata = (candidata['id'] as num?)?.toInt() ?? 0;
    final idActual = (actual['id'] as num?)?.toInt() ?? 0;
    return idCandidata >= idActual;
  }

  /// Colapsa los cobros de tiendas secundarias dentro de su principal.
  /// Si la principal no tiene cobro en el período, la secundaria queda
  /// visible marcada con `secundariaDe`.
  static List<CobroLicencia> agruparCobros(
    List<CobroLicencia> cobros,
    Map<int, int> secundariaAPrincipal,
    Map<int, String> nombresTiendas,
  ) {
    final porTienda = <int, CobroLicencia>{
      for (final c in cobros)
        if (c.tiendaId != null) c.tiendaId!: c,
    };
    final resultado = <CobroLicencia>[];
    for (final c in cobros) {
      final principalId =
          c.tiendaId == null ? null : secundariaAPrincipal[c.tiendaId];
      if (principalId == null) {
        resultado.add(c);
        continue;
      }
      final principal = porTienda[principalId];
      if (principal != null && !identical(principal, c)) {
        // El grupo cobra como un solo cliente: solo cuenta la licencia
        // de la principal, la secundaria solo se anota (no suma).
        principal.secundarias.add(c.tienda);
      } else {
        c.secundariaDe = nombresTiendas[principalId];
        resultado.add(c);
      }
    }
    return resultado;
  }

  /// (secundariaId -> principalId, tiendaId -> nombre)
  static Future<(Map<int, int>, Map<int, String>)> _gruposMultitienda() async {
    try {
      final rows = await _supabase
          .from('app_dat_tienda')
          .select('id, denominacion, id_tienda_principal');
      final secAPrincipal = <int, int>{};
      final nombres = <int, String>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final id = (row['id'] as num?)?.toInt();
        if (id == null) continue;
        nombres[id] = row['denominacion']?.toString() ?? 'Tienda #$id';
        final principal = (row['id_tienda_principal'] as num?)?.toInt();
        if (principal != null && principal != id) {
          secAPrincipal[id] = principal;
        }
      }
      return (secAPrincipal, nombres);
    } catch (e) {
      debugPrint('Grupos multitienda no disponibles: $e');
      return (const <int, int>{}, const <int, String>{});
    }
  }

  static Future<_TiendasPrueba> _tiendasPrueba() async {
    try {
      final rows = await _supabase
          .from('app_dat_tienda')
          .select('id, id_tienda_carnaval')
          .eq('es_prueba', true);
      final ids = <int>{};
      final carnaval = <int>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final id = (row['id'] as num?)?.toInt();
        if (id != null) ids.add(id);
        final carnavalId = (row['id_tienda_carnaval'] as num?)?.toInt();
        if (carnavalId != null) carnaval.add(carnavalId);
      }
      return _TiendasPrueba(ids, carnaval);
    } catch (e) {
      debugPrint('Tiendas de prueba no disponibles: $e');
      return _TiendasPrueba(const {}, const {});
    }
  }

  static Future<List<Map<String, dynamic>>> _personas() async {
    final rows = await _supabase
        .from('app_dat_agente')
        .select('id, nombre, apellidos, tarjeta, es_socio, id_agente_carnaval, estado');
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> _suscripciones() async {
    final rows = await _supabase.from('app_suscripciones').select('''
          id, id_tienda, id_plan, id_agente, estado, fecha_fin,
          app_dat_tienda(denominacion),
          app_suscripciones_plan(denominacion, precio_mensual),
          app_dat_agente(id, nombre, apellidos)
        ''').eq('estado', 1);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<List<Map<String, dynamic>>> _renovacionesEnRango(
    DateTime desde,
    DateTime hasta,
  ) async {
    try {
      final rows = await _supabase
          .from('app_suscripciones_renovaciones_resumen')
          .select('id, id_mes, id_anno, id_tienda, id_plan, total_pagado');
      final inicio = DateTime(desde.year, desde.month, 1);
      final fin = DateTime(hasta.year, hasta.month, 1);
      return List<Map<String, dynamic>>.from(rows).where((r) {
        final mes = DateTime((r['id_anno'] as num).toInt(), (r['id_mes'] as num).toInt(), 1);
        return !mes.isBefore(inicio) && !mes.isAfter(fin);
      }).toList();
    } catch (e) {
      debugPrint('Renovaciones no disponibles: $e');
      return [];
    }
  }

  static Future<Map<String, Map<String, dynamic>>> _ajustes() async {
    try {
      final rows = await _supabase
          .from('app_dat_cobro_licencia')
          .select('id_suscripcion, periodo, recibido_usd, recibido_cup, transaccion');
      final map = <String, Map<String, dynamic>>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final id = (row['id_suscripcion'] as num?)?.toInt();
        final periodo = DateTime.tryParse(row['periodo']?.toString() ?? '');
        if (id == null || periodo == null) continue;
        map['$id-${periodo.year}-${periodo.month}'] = row;
      }
      return map;
    } catch (e) {
      debugPrint('Ajustes de cobro no disponibles: $e');
      return {};
    }
  }
}
