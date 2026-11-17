import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/estudio_inversion.dart';
import 'user_preferences_service.dart';

/// Lee la historia completa de un producto en la tienda activa y la entrega
/// al cálculo puro. No recorta por el rango de fechas de Tiempo real.
class EstudioInversionService {
  EstudioInversionService({SupabaseClient? client, UserPreferencesService? preferencias})
    : _supabase = client ?? Supabase.instance.client,
      _preferencias = preferencias ?? UserPreferencesService();

  final SupabaseClient _supabase;
  final UserPreferencesService _preferencias;

  static const int _pagina = 1000;
  static const int _lote = 200;

  Future<EstudioInversion> cargar(int idProducto) async {
    final idTienda = await _preferencias.getIdTienda();
    if (idTienda == null) {
      throw StateError('No hay tienda seleccionada');
    }

    final idsUbicacion = await _idsUbicacion(idTienda);
    final idVenta = await _idTipoVenta();
    final factores = await _tabla(idProducto);
    final precios = await _precios(idProducto);
    final recepciones = await _recepciones(idProducto, idTienda, factores);
    final ventas = await _ventas(idProducto, idTienda, idVenta, factores, precios);
    final existencia = await _existencia(idProducto, factores, idsUbicacion);

    final precio = await _precioActual(idProducto);
    return estudiarInversion(
      recepciones: recepciones,
      ventas: ventas,
      existencia: existencia,
    ).conPrecioActual(usd: precio.usd, cup: precio.cup);
  }

  /// Productos de la tienda cuyo saldo actual, en unidades base, es positivo.
  Future<List<ProductoConExistencia>> listarConExistencia() async {
    final idTienda = await _preferencias.getIdTienda();
    if (idTienda == null) {
      throw StateError('No hay tienda seleccionada');
    }
    final idsUbicacion = await _idsUbicacion(idTienda);
    if (idsUbicacion.isEmpty) return const [];

    final movimientos = await _porLotes<Map<String, dynamic>>(idsUbicacion, (lote) {
      return _paginaDonde(
        () => _supabase
            .from('app_dat_inventario_productos')
            .select('id, id_producto, id_ubicacion, id_variante, id_presentacion, cantidad_final, created_at')
            .inFilter('id_ubicacion', lote)
            .order('id'),
      );
    });

    final porProducto = <int, List<Map<String, dynamic>>>{};
    for (final movimiento in movimientos) {
      final id = (movimiento['id_producto'] as num?)?.toInt();
      if (id == null) continue;
      (porProducto[id] ??= []).add(movimiento);
    }
    if (porProducto.isEmpty) return const [];

    final ids = porProducto.keys.toList();
    final factores = await _tablas(ids);
    final nombres = await _nombres(ids, idTienda);
    final precios = await _preciosVigentes(ids);
    final idVenta = await _idTipoVenta();
    final recepciones = await _recepcionesDe(ids, idTienda, factores);
    final referencias = await _preciosDe(ids);
    final ventas = await _ventasDe(ids, idTienda, idVenta, factores, referencias);

    final lista = <ProductoConExistencia>[];
    for (final id in ids) {
      final nombre = nombres[id];
      if (nombre == null) continue;
      final tabla = factores[id] ?? const TablaPresentaciones([]);
      final stock = _saldoActual(porProducto[id]!, tabla);
      if (stock <= 1e-6) continue;
      final precio = precios[id];
      final estudio = estudiarInversion(
        recepciones: recepciones[id] ?? const [],
        ventas: ventas[id] ?? const [],
        existencia: _serie(porProducto[id]!, tabla),
      );
      final resumen = estudio.resumenDelListado;
      lista.add(
        ProductoConExistencia(
          idProducto: id,
          nombre: nombre,
          existenciasBase: stock,
          precioUsd: precio?.usd,
          precioCup: precio?.cup,
          costoUnitarioUsd: resumen?.costoUnitarioUsd,
          cumplimiento: resumen?.cumplimiento,
        ),
      );
    }
    lista.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    return lista;
  }

  Future<List<int>> _idsUbicacion(int idTienda) async {
    final almacenes = await _supabase.from('app_dat_almacen').select('id').eq('id_tienda', idTienda);
    final idsAlmacen = [for (final fila in almacenes) (fila['id'] as num).toInt()];
    if (idsAlmacen.isEmpty) return const [];
    final ubicaciones = await _porLotes(
      idsAlmacen,
      (lote) => _supabase.from('app_dat_layout_almacen').select('id').inFilter('id_almacen', lote),
    );
    return [for (final fila in ubicaciones) (fila['id'] as num).toInt()];
  }

  Future<Map<int, TablaPresentaciones>> _tablas(List<int> ids) async {
    final filas = await _porLotes<Map<String, dynamic>>(ids, (lote) async {
      final respuesta = await _supabase
          .from('app_dat_producto_presentacion')
          .select('id, id_producto, id_presentacion, es_base, cantidad')
          .inFilter('id_producto', lote);
      return List<Map<String, dynamic>>.from(respuesta);
    });
    final porProducto = <int, List<FilaPresentacion>>{};
    for (final fila in filas) {
      final id = (fila['id_producto'] as num).toInt();
      (porProducto[id] ??= []).add(
        FilaPresentacion(
          idFila: (fila['id'] as num).toInt(),
          idCatalogo: (fila['id_presentacion'] as num).toInt(),
          cantidad: _numero(fila['cantidad']) ?? 0,
          marcadaBase: fila['es_base'] == true,
        ),
      );
    }
    return {for (final entrada in porProducto.entries) entrada.key: tablaPresentaciones(entrada.value)};
  }

  Future<Map<int, String>> _nombres(List<int> ids, int idTienda) async {
    final filas = await _porLotes<Map<String, dynamic>>(ids, (lote) async {
      final respuesta = await _supabase
          .from('app_dat_producto')
          .select('id, denominacion')
          .eq('id_tienda', idTienda)
          .inFilter('id', lote);
      return List<Map<String, dynamic>>.from(respuesta);
    });
    return {
      for (final fila in filas) (fila['id'] as num).toInt(): (fila['denominacion'] ?? 'Producto').toString(),
    };
  }

  Future<Map<int, ({double? usd, double? cup})>> _preciosVigentes(List<int> ids) async {
    final filas = await _porLotes<Map<String, dynamic>>(ids, (lote) async {
      final respuesta = await _supabase
          .from('app_v_precio_venta_base_vigente')
          .select('id, id_producto, precio_venta_cup, precio_venta_usd')
          .inFilter('id_producto', lote);
      return List<Map<String, dynamic>>.from(respuesta);
    });
    final mejor = <int, Map<String, dynamic>>{};
    for (final fila in filas) {
      final id = (fila['id_producto'] as num).toInt();
      final actual = mejor[id];
      if (actual == null || (fila['id'] as num) > (actual['id'] as num)) {
        mejor[id] = fila;
      }
    }
    return {
      for (final entrada in mejor.entries)
        entrada.key: (
          usd: _precioPositivo(entrada.value['precio_venta_usd']),
          cup: _precioPositivo(entrada.value['precio_venta_cup']),
        ),
    };
  }

  double _saldoActual(List<Map<String, dynamic>> movimientos, TablaPresentaciones factores) {
    final ordenados = movimientos.toList()
      ..sort((a, b) {
        final porFecha = a['created_at'].toString().compareTo(b['created_at'].toString());
        if (porFecha != 0) return porFecha;
        return (a['id'] as num).compareTo(b['id'] as num);
      });
    final saldo = <String, double>{};
    for (final movimiento in ordenados) {
      final unidades = _unidades(
        (movimiento['id_presentacion'] as num?)?.toInt(),
        _numero(movimiento['cantidad_final']) ?? 0,
        factores,
      );
      if (unidades == null) continue;
      final ubicacion = (movimiento['id_ubicacion'] as num?)?.toInt();
      if (ubicacion == null) continue;
      final variante = (movimiento['id_variante'] as num?)?.toInt() ?? 0;
      saldo['$ubicacion|$variante'] = unidades;
    }
    final total = saldo.values.fold<double>(0, (suma, valor) => suma + valor);
    return total > 0 ? total : 0;
  }

  Future<Map<int, List<RecepcionInversion>>> _recepcionesDe(
    List<int> ids,
    int idTienda,
    Map<int, TablaPresentaciones> factores,
  ) async {
    if (ids.isEmpty) return const {};
    final lineas = await _porLotes<Map<String, dynamic>>(ids, (lote) {
      return _paginaDonde(
        () => _supabase
            .from('app_dat_recepcion_productos')
            .select(
              'id_producto, id_operacion, id_presentacion, cantidad, precio_unitario, costo_real, bonificacion_cantidad, created_at',
            )
            .inFilter('id_producto', lote)
            .order('created_at'),
      );
    });
    final completadas = await _operacionesCompletadas(
      lineas.map((linea) => (linea['id_operacion'] as num?)?.toInt()).whereType<int>(),
      idTienda,
    );
    final porProducto = <int, List<RecepcionInversion>>{};
    for (final linea in lineas) {
      final idOperacion = (linea['id_operacion'] as num?)?.toInt();
      if (!completadas.contains(idOperacion)) continue;
      final id = (linea['id_producto'] as num?)?.toInt();
      if (id == null) continue;
      (porProducto[id] ??= []).add(_recepcion(linea, factores[id] ?? const TablaPresentaciones([])));
    }
    return porProducto;
  }

  Future<Map<int, List<PrecioReferencia>>> _preciosDe(List<int> ids) async {
    if (ids.isEmpty) return const {};
    final filas = await _porLotes<Map<String, dynamic>>(ids, (lote) {
      return _paginaDonde(
        () => _supabase
            .from('app_dat_precio_venta')
            .select('id, id_producto, id_variante, precio_venta_cup, precio_venta_usd, fecha_desde, fecha_hasta')
            .inFilter('id_producto', lote)
            .order('id'),
      );
    });
    final porProducto = <int, List<PrecioReferencia>>{};
    for (final fila in filas) {
      final id = (fila['id_producto'] as num?)?.toInt();
      if (id == null) continue;
      (porProducto[id] ??= []).add(
        PrecioReferencia(
          id: (fila['id'] as num).toInt(),
          idVariante: (fila['id_variante'] as num?)?.toInt(),
          desde: DateTime.parse(fila['fecha_desde'].toString()),
          hasta: fila['fecha_hasta'] == null ? null : DateTime.parse(fila['fecha_hasta'].toString()),
          precioCup: _numero(fila['precio_venta_cup']) ?? 0,
          precioUsd: _numero(fila['precio_venta_usd']) ?? 0,
        ),
      );
    }
    return porProducto;
  }

  Future<Map<int, List<VentaInversion>>> _ventasDe(
    List<int> ids,
    int idTienda,
    int? idVenta,
    Map<int, TablaPresentaciones> factores,
    Map<int, List<PrecioReferencia>> precios,
  ) async {
    if (ids.isEmpty || idVenta == null) return const {};
    final lineas = await _porLotes<Map<String, dynamic>>(ids, (lote) {
      return _paginaDonde(
        () => _supabase
            .from('app_dat_extraccion_productos')
            .select(
              'id_producto, id_operacion, id_presentacion, id_variante, cantidad, precio_unitario, importe, moneda_venta, precio_unitario_neto_nativo, created_at',
            )
            .inFilter('id_producto', lote)
            .order('created_at'),
      );
    });
    final completadas = await _operacionesCompletadas(
      lineas.map((linea) => (linea['id_operacion'] as num?)?.toInt()).whereType<int>(),
      idTienda,
      idTipo: idVenta,
    );
    final porProducto = <int, List<VentaInversion>>{};
    for (final linea in lineas) {
      final idOperacion = (linea['id_operacion'] as num?)?.toInt();
      if (!completadas.contains(idOperacion)) continue;
      final id = (linea['id_producto'] as num?)?.toInt();
      if (id == null) continue;
      (porProducto[id] ??= []).add(
        _venta(linea, factores[id] ?? const TablaPresentaciones([]), precios[id] ?? const []),
      );
    }
    return porProducto;
  }

  List<ExistenciaProducto>? _serie(
    List<Map<String, dynamic>> movimientos,
    TablaPresentaciones factores,
  ) {
    if (movimientos.isEmpty) return null;
    final ordenados = movimientos.toList()
      ..sort((a, b) {
        final porFecha = a['created_at'].toString().compareTo(b['created_at'].toString());
        if (porFecha != 0) return porFecha;
        return (a['id'] as num).compareTo(b['id'] as num);
      });
    final saldo = <String, double>{};
    final serie = <ExistenciaProducto>[];
    for (final movimiento in ordenados) {
      final unidades = _unidades(
        (movimiento['id_presentacion'] as num?)?.toInt(),
        _numero(movimiento['cantidad_final']) ?? 0,
        factores,
      );
      if (unidades == null) return null;
      final ubicacion = (movimiento['id_ubicacion'] as num?)?.toInt();
      if (ubicacion == null) continue;
      final variante = (movimiento['id_variante'] as num?)?.toInt() ?? 0;
      saldo['$ubicacion|$variante'] = unidades;
      serie.add(
        ExistenciaProducto(
          fecha: DateTime.parse(movimiento['created_at'].toString()).toLocal(),
          unidadesBase: saldo.values.fold<double>(0, (suma, valor) => suma + valor),
        ),
      );
    }
    return serie.isEmpty ? null : serie;
  }

  Future<int?> _idTipoVenta() async {
    final filas = await _supabase.from('app_nom_tipo_operacion').select('id, denominacion');
    for (final fila in filas) {
      final nombre = (fila['denominacion'] ?? '').toString().trim().toLowerCase();
      if (nombre == 'venta') return (fila['id'] as num).toInt();
    }
    return null;
  }

  Future<TablaPresentaciones> _tabla(int idProducto) async {
    final filas = await _supabase
        .from('app_dat_producto_presentacion')
        .select('id, id_presentacion, es_base, cantidad')
        .eq('id_producto', idProducto);
    return tablaPresentaciones([
      for (final fila in filas)
        FilaPresentacion(
          idFila: (fila['id'] as num).toInt(),
          idCatalogo: (fila['id_presentacion'] as num).toInt(),
          cantidad: _numero(fila['cantidad']) ?? 0,
          marcadaBase: fila['es_base'] == true,
        ),
    ]);
  }

  Future<({double? usd, double? cup})> _precioActual(int idProducto) async {
    final filas = await _supabase
        .from('app_v_precio_venta_base_vigente')
        .select('precio_venta_cup, precio_venta_usd')
        .eq('id_producto', idProducto)
        .order('id', ascending: false)
        .limit(1);
    if (filas.isEmpty) return (usd: null, cup: null);
    final fila = filas.first;
    return (usd: _precioPositivo(fila['precio_venta_usd']), cup: _precioPositivo(fila['precio_venta_cup']));
  }

  Future<List<PrecioReferencia>> _precios(int idProducto) async {
    final filas = await _paginaDonde(
      () => _supabase
          .from('app_dat_precio_venta')
          .select('id, id_variante, precio_venta_cup, precio_venta_usd, fecha_desde, fecha_hasta')
          .eq('id_producto', idProducto)
          .order('id'),
    );
    return [
      for (final fila in filas)
        PrecioReferencia(
          id: (fila['id'] as num).toInt(),
          idVariante: (fila['id_variante'] as num?)?.toInt(),
          desde: DateTime.parse(fila['fecha_desde'].toString()),
          hasta: fila['fecha_hasta'] == null ? null : DateTime.parse(fila['fecha_hasta'].toString()),
          precioCup: _numero(fila['precio_venta_cup']) ?? 0,
          precioUsd: _numero(fila['precio_venta_usd']) ?? 0,
        ),
    ];
  }

  Future<List<RecepcionInversion>> _recepciones(
    int idProducto,
    int idTienda,
    TablaPresentaciones factores,
  ) async {
    final lineas = await _paginaDonde(
      () => _supabase
          .from('app_dat_recepcion_productos')
          .select(
            'id_operacion, id_presentacion, cantidad, precio_unitario, costo_real, bonificacion_cantidad, created_at',
          )
          .eq('id_producto', idProducto)
          .order('created_at'),
    );
    final completadas = await _operacionesCompletadas(
      lineas.map((linea) => (linea['id_operacion'] as num?)?.toInt()).whereType<int>(),
      idTienda,
    );

    return [
      for (final linea in lineas)
        if (completadas.contains((linea['id_operacion'] as num?)?.toInt()))
          _recepcion(linea, factores),
    ];
  }

  RecepcionInversion _recepcion(Map<String, dynamic> linea, TablaPresentaciones factores) {
    final cantidad = _numero(linea['cantidad']) ?? 0;
    final bonificacion = _numero(linea['bonificacion_cantidad']) ?? 0;
    final presentacion = (linea['id_presentacion'] as num?)?.toInt();
    final unidades = _unidades(presentacion, cantidad + bonificacion, factores);
    final unitario = (_numero(linea['costo_real']) ?? 0) > 0
        ? _numero(linea['costo_real'])!
        : (_numero(linea['precio_unitario']) ?? 0);
    final total = metaDeRecepcion(
      costoReal: _numero(linea['costo_real']) ?? 0,
      cantidadPagada: cantidad,
      precioUnitarioUsd: _numero(linea['precio_unitario']) ?? 0,
    );
    final unitarioBase = unidades != null && unidades > 0 ? total / unidades : unitario;
    return RecepcionInversion(
      fecha: DateTime.parse(linea['created_at'].toString()).toLocal(),
      unidadesBase: unidades ?? 0,
      costoUnitarioUsd: unitarioBase,
      totalUsd: unidades == null ? 0 : total,
      cuentaParaStock: unidades != null,
    );
  }

  Future<List<VentaInversion>> _ventas(
    int idProducto,
    int idTienda,
    int? idVenta,
    TablaPresentaciones factores,
    List<PrecioReferencia> precios,
  ) async {
    if (idVenta == null) return const [];
    final lineas = await _paginaDonde(
      () => _supabase
          .from('app_dat_extraccion_productos')
          .select(
            'id_operacion, id_presentacion, id_variante, cantidad, precio_unitario, importe, moneda_venta, precio_unitario_neto_nativo, created_at',
          )
          .eq('id_producto', idProducto)
          .order('created_at'),
    );
    final ids = lineas.map((linea) => (linea['id_operacion'] as num?)?.toInt()).whereType<int>();
    final completadas = await _operacionesCompletadas(ids, idTienda, idTipo: idVenta);

    return [
      for (final linea in lineas)
        if (completadas.contains((linea['id_operacion'] as num?)?.toInt()))
          _venta(linea, factores, precios),
    ];
  }

  VentaInversion _venta(
    Map<String, dynamic> linea,
    TablaPresentaciones factores,
    List<PrecioReferencia> precios,
  ) {
    final fecha = DateTime.parse(linea['created_at'].toString()).toLocal();
    final cantidad = _numero(linea['cantidad']) ?? 0;
    final presentacion = (linea['id_presentacion'] as num?)?.toInt();
    final unidades = _unidades(presentacion, cantidad, factores) ?? 0;
    final moneda = (linea['moneda_venta'] ?? '').toString().trim().toUpperCase();
    final esUsd = moneda == 'USD';
    final neto = _numero(linea['precio_unitario_neto_nativo']);
    final unitario = _numero(linea['precio_unitario']) ?? 0;
    final importeLinea = _numero(linea['importe']);
    final importe = esUsd
        ? (neto ?? unitario) * cantidad
        : (importeLinea ?? (neto ?? unitario) * cantidad);
    double? tasa;
    if (!esUsd) {
      final referencia = precioReferenciaEnFecha(
        precios,
        fecha,
        idVariante: (linea['id_variante'] as num?)?.toInt(),
      );
      tasa = tasaUsdDesdeReferencia(
        precioCup: referencia?.precioCup,
        precioUsd: referencia?.precioUsd,
      );
    }
    return VentaInversion(
      fecha: fecha,
      unidadesBase: unidades,
      moneda: esUsd ? 'USD' : 'CUP',
      importeNativo: importe,
      tasaUsd: tasa,
    );
  }

  Future<List<ExistenciaProducto>?> _existencia(
    int idProducto,
    TablaPresentaciones factores,
    List<int> idsUbicacion,
  ) async {
    if (idsUbicacion.isEmpty) return null;

    final movimientos = await _porLotes(
      idsUbicacion,
      (lote) => _paginaDonde(
        () => _supabase
            .from('app_dat_inventario_productos')
            .select('id, id_ubicacion, id_variante, id_presentacion, cantidad_final, created_at')
            .eq('id_producto', idProducto)
            .inFilter('id_ubicacion', lote)
            .order('created_at'),
      ),
    );
    if (movimientos.isEmpty) return null;

    movimientos.sort((a, b) {
      final porFecha = a['created_at'].toString().compareTo(b['created_at'].toString());
      if (porFecha != 0) return porFecha;
      return (a['id'] as num).compareTo(b['id'] as num);
    });

    final saldo = <String, double>{};
    final serie = <ExistenciaProducto>[];
    for (final movimiento in movimientos) {
      final presentacion = (movimiento['id_presentacion'] as num?)?.toInt();
      final unidades = _unidades(presentacion, _numero(movimiento['cantidad_final']) ?? 0, factores);
      if (unidades == null) return null;
      final variante = (movimiento['id_variante'] as num?)?.toInt() ?? 0;
      final ubicacion = (movimiento['id_ubicacion'] as num).toInt();
      saldo['$ubicacion|$variante'] = unidades;
      serie.add(
        ExistenciaProducto(
          fecha: DateTime.parse(movimiento['created_at'].toString()).toLocal(),
          unidadesBase: saldo.values.fold<double>(0, (suma, valor) => suma + valor),
        ),
      );
    }
    return serie;
  }

  double? _unidades(int? idPresentacion, double cantidad, TablaPresentaciones tabla) {
    if (tabla.factores.isEmpty) {
      return idPresentacion == null ? cantidad : null;
    }
    final factor = tabla.buscar(idPresentacion);
    if (factor == null) return null;
    return aUnidadesBase(cantidad: cantidad, esBase: false, factor: factor.factorRel);
  }

  Future<Set<int>> _operacionesCompletadas(
    Iterable<int> ids,
    int idTienda, {
    int? idTipo,
  }) async {
    final propios = await _porLotes<int>(ids.toSet().toList(), (lote) async {
      final filas = await _supabase
          .from('app_dat_operaciones')
          .select('id, id_tipo_operacion')
          .inFilter('id', lote)
          .eq('id_tienda', idTienda);
      return [
        for (final fila in filas)
          if (idTipo == null || (fila['id_tipo_operacion'] as num?)?.toInt() == idTipo)
            (fila['id'] as num).toInt(),
      ];
    });
    final deLaTienda = propios.toSet();
    if (deLaTienda.isEmpty) return deLaTienda;

    final estados = await _porLotes<Map<String, dynamic>>(deLaTienda.toList(), (lote) async {
      return _paginaDonde(
        () => _supabase
            .from('app_dat_estado_operacion')
            .select('id, id_operacion, estado')
            .inFilter('id_operacion', lote)
            .order('id'),
      );
    });
    final ultimo = <int, int>{};
    final ordenado = estados.toList()
      ..sort((a, b) => (a['id'] as num).compareTo(b['id'] as num));
    for (final fila in ordenado) {
      ultimo[(fila['id_operacion'] as num).toInt()] = (fila['estado'] as num).toInt();
    }
    return ultimo.entries.where((entrada) => operacionCompletada(entrada.value)).map((e) => e.key).toSet();
  }

  Future<List<Map<String, dynamic>>> _paginaDonde(
    PostgrestTransformBuilder<List<Map<String, dynamic>>> Function() consulta,
  ) async {
    final acumulado = <Map<String, dynamic>>[];
    var desde = 0;
    while (true) {
      final pagina = await consulta().range(desde, desde + _pagina - 1);
      acumulado.addAll(pagina);
      if (pagina.length < _pagina) return acumulado;
      desde += _pagina;
    }
  }

  Future<List<T>> _porLotes<T>(
    List<int> ids,
    Future<List<T>> Function(List<int> lote) cargar,
  ) async {
    final acumulado = <T>[];
    for (var i = 0; i < ids.length; i += _lote) {
      final fin = i + _lote > ids.length ? ids.length : i + _lote;
      acumulado.addAll(await cargar(ids.sublist(i, fin)));
    }
    return acumulado;
  }
}

double? _numero(dynamic valor) {
  if (valor == null) return null;
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor.toString());
}

double? _precioPositivo(dynamic valor) {
  final precio = _numero(valor);
  if (precio == null || precio <= 0) return null;
  return precio;
}

class ProductoConExistencia {
  final int idProducto;
  final String nombre;
  final double existenciasBase;
  final double? precioUsd;
  final double? precioCup;
  final double? costoUnitarioUsd;

  /// Recaudado / meta del tramo que resume el listado. Null si falta la tasa
  /// o no hay costo.
  final double? cumplimiento;

  const ProductoConExistencia({
    required this.idProducto,
    required this.nombre,
    required this.existenciasBase,
    this.precioUsd,
    this.precioCup,
    this.costoUnitarioUsd,
    this.cumplimiento,
  });
}
