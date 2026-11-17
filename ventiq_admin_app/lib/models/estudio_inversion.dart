/// Estudio histórico de cuánto de cada inversión de un producto se recuperó.
///
/// La meta está en USD, que es como se guarda el costo de la recepción. Lo
/// recaudado de una venta en CUP se divide por la tasa de esa fecha. Una venta
/// en USD entra directo. El stock en cero suma variantes y ubicaciones: si
/// llegó a cero entre dos recepciones, la segunda abre otra inversión.
library;

const double _existenciaCero = 0.000001;

/// Último estado completado, el mismo criterio que el reporte de ventas.
bool operacionCompletada(int? estado) => estado == 2;

/// Unidades base de una cantidad ya expresada con [factor] relativo a la base.
///
/// [factor] es `factor_rel` (la base vale 1). [esBase] conserva el atajo de
/// no multiplicar: la base resuelta ya trae factor 1, así que el servicio
/// pasa siempre el `factor_rel` y deja [esBase] en false.
double? aUnidadesBase({
  required double cantidad,
  required bool esBase,
  required double? factor,
}) {
  if (esBase) return cantidad;
  if (factor == null || factor <= 0) return null;
  return cantidad * factor;
}

/// Fila de `app_dat_producto_presentacion`.
///
/// La recepción y el inventario guardan [idFila] en la columna
/// `id_presentacion`, no el id del catálogo.
class FilaPresentacion {
  final int idFila;
  final int idCatalogo;
  final double cantidad;
  final bool marcadaBase;

  const FilaPresentacion({
    required this.idFila,
    required this.idCatalogo,
    required this.cantidad,
    required this.marcadaBase,
  });
}

class FactorPresentacion {
  final int idFila;
  final int idCatalogo;
  final double factorRel;
  final bool esBase;

  const FactorPresentacion({
    required this.idFila,
    required this.idCatalogo,
    required this.factorRel,
    required this.esBase,
  });
}

class TablaPresentaciones {
  final List<FactorPresentacion> factores;

  const TablaPresentaciones(this.factores);

  /// [idGuardado] null es la base. Si no es el id de la fila, se prueba el
  /// id de catálogo.
  FactorPresentacion? buscar(int? idGuardado) {
    if (factores.isEmpty) return null;
    if (idGuardado == null) {
      for (final factor in factores) {
        if (factor.esBase) return factor;
      }
      return null;
    }
    for (final factor in factores) {
      if (factor.idFila == idGuardado) return factor;
    }
    for (final factor in factores) {
      if (factor.idCatalogo == idGuardado) return factor;
    }
    return null;
  }
}

/// Misma cascada que `fn_presentaciones_producto`: la base es la fila
/// `es_base` y, si ninguna lo está, la de menor cantidad. `factor_rel` es
/// `cantidad / cantidad de esa base`, porque la base no siempre tiene
/// cantidad 1.
TablaPresentaciones tablaPresentaciones(List<FilaPresentacion> filas) {
  if (filas.isEmpty) return const TablaPresentaciones([]);
  final ordenadas = filas.toList()
    ..sort((a, b) {
      if (a.marcadaBase != b.marcadaBase) return a.marcadaBase ? -1 : 1;
      final porCantidad = a.cantidad.compareTo(b.cantidad);
      if (porCantidad != 0) return porCantidad;
      return a.idFila.compareTo(b.idFila);
    });
  final base = ordenadas.first;
  if (base.cantidad <= 0) return const TablaPresentaciones([]);
  return TablaPresentaciones([
    for (final fila in filas)
      FactorPresentacion(
        idFila: fila.idFila,
        idCatalogo: fila.idCatalogo,
        factorRel: fila.cantidad / base.cantidad,
        esBase: fila.idFila == base.idFila,
      ),
  ]);
}

/// [costoReal] es el costo de una unidad de la presentación (precio neto más
/// adicionales), no el total de la línea. La meta es la cantidad pagada por
/// ese unitario. Si `costo_real` vino en 0, se usa el precio unitario.
double metaDeRecepcion({
  required double costoReal,
  required double cantidadPagada,
  required double precioUnitarioUsd,
}) {
  final unitario = costoReal > 0 ? costoReal : precioUnitarioUsd;
  return cantidadPagada * unitario;
}

/// CUP por 1 USD a partir del par de precios de referencia de esa fecha.
double? tasaUsdDesdeReferencia({required double? precioCup, required double? precioUsd}) {
  if (precioCup == null || precioUsd == null) return null;
  if (precioCup <= 0 || precioUsd <= 0) return null;
  return precioCup / precioUsd;
}

class PrecioReferencia {
  final int id;
  final int? idVariante;
  final DateTime desde;
  final DateTime? hasta;
  final double precioCup;
  final double precioUsd;

  const PrecioReferencia({
    required this.id,
    required this.idVariante,
    required this.desde,
    required this.hasta,
    required this.precioCup,
    required this.precioUsd,
  });
}

/// Fila de `app_dat_precio_venta` vigente en [fecha]. Mayor id. Si la venta
/// trae variante, prefiere esa variante; si no hay, usa el precio base.
PrecioReferencia? precioReferenciaEnFecha(
  List<PrecioReferencia> filas,
  DateTime fecha, {
  int? idVariante,
}) {
  final dia = DateTime(fecha.year, fecha.month, fecha.day);
  final cubren = filas.where((fila) {
    final desde = DateTime(fila.desde.year, fila.desde.month, fila.desde.day);
    final hasta = fila.hasta == null
        ? null
        : DateTime(fila.hasta!.year, fila.hasta!.month, fila.hasta!.day);
    if (dia.isBefore(desde)) return false;
    if (hasta != null && dia.isAfter(hasta)) return false;
    return true;
  }).toList();
  if (cubren.isEmpty) return null;

  final variante = idVariante != null && idVariante != 0 ? idVariante : null;
  final especificas = variante == null
      ? const <PrecioReferencia>[]
      : cubren.where((fila) => fila.idVariante == variante).toList();
  final candidatas = especificas.isNotEmpty
      ? especificas
      : cubren.where((fila) => fila.idVariante == null || fila.idVariante == 0).toList();
  final usable = candidatas.isEmpty ? cubren : candidatas;
  usable.sort((a, b) => a.id.compareTo(b.id));
  return usable.last;
}

class RecepcionInversion {
  final DateTime fecha;
  final double unidadesBase;
  final double costoUnitarioUsd;
  final double totalUsd;

  /// False cuando no se pudo pasar la cantidad a unidades base.
  final bool cuentaParaStock;

  const RecepcionInversion({
    required this.fecha,
    required this.unidadesBase,
    required this.costoUnitarioUsd,
    required this.totalUsd,
    this.cuentaParaStock = true,
  });
}

class VentaInversion {
  final DateTime fecha;
  final double unidadesBase;
  final String moneda;
  final double importeNativo;

  /// CUP por 1 USD en la fecha de la venta. No se usa cuando [moneda] es USD.
  final double? tasaUsd;

  const VentaInversion({
    required this.fecha,
    required this.unidadesBase,
    required this.moneda,
    required this.importeNativo,
    this.tasaUsd,
  });

  bool get esUsd => moneda.trim().toUpperCase() == 'USD';

  /// Equivalente USD de lo cobrado. Null si falta la tasa de una venta que no
  /// está en USD: no es cero.
  double? get equivalenteUsd {
    if (esUsd) return importeNativo;
    final tasa = tasaUsd;
    if (tasa == null || tasa <= 0) return null;
    return importeNativo / tasa;
  }
}

/// Entrada o salida que no es una recepción ni una venta (devolución, ajuste).
class AjusteStock {
  final DateTime fecha;
  final double deltaUnidadesBase;

  const AjusteStock({required this.fecha, required this.deltaUnidadesBase});
}

class ExistenciaProducto {
  final DateTime fecha;
  final double unidadesBase;

  const ExistenciaProducto({required this.fecha, required this.unidadesBase});

  bool get agotado => unidadesBase <= _existenciaCero;
}

class TramoInversion {
  final DateTime inicio;
  final DateTime? fin;
  final List<RecepcionInversion> recepciones;
  final List<VentaInversion> ventas;

  const TramoInversion({
    required this.inicio,
    required this.fin,
    required this.recepciones,
    required this.ventas,
  });

  bool get enCurso => fin == null;

  double get meta => recepciones.fold<double>(0, (suma, r) => suma + r.totalUsd);

  double get unidadesVendidas =>
      ventas.fold<double>(0, (suma, v) => suma + v.unidadesBase);

  bool get incompleto => ventas.any((venta) => venta.equivalenteUsd == null);

  /// Suma solo las ventas que sí se pudieron pasar a USD.
  double get recaudado => ventas.fold<double>(
    0,
    (suma, venta) => suma + (venta.equivalenteUsd ?? 0),
  );

  /// Null si la meta es 0 o si alguna venta del tramo no tiene tasa.
  double? get cumplimiento {
    if (incompleto || meta <= 0) return null;
    return recaudado / meta;
  }
}

/// Stock que queda valorado al precio de venta vigente, sumado a lo recaudado.
class PrediccionInversion {
  final double existenciasBase;
  final double? precioActualUsd;
  final double? valorExistenciasUsd;
  final double? proyectadoUsd;
  final double? gananciaUsd;
  final double? porcentajeGanancia;
  final bool sinPrecio;
  final bool incompleta;

  const PrediccionInversion._({
    this.existenciasBase = 0,
    this.precioActualUsd,
    this.valorExistenciasUsd,
    this.proyectadoUsd,
    this.gananciaUsd,
    this.porcentajeGanancia,
    this.sinPrecio = false,
  }) : incompleta = false;

  bool get esGanancia => (gananciaUsd ?? 0) > 0;

  const PrediccionInversion.incompleta()
    : existenciasBase = 0,
      precioActualUsd = null,
      valorExistenciasUsd = null,
      proyectadoUsd = null,
      gananciaUsd = null,
      porcentajeGanancia = null,
      sinPrecio = false,
      incompleta = true;
}

/// [tasaUsdACup] es cuántos CUP vale 1 USD. El precio teórico se escribe en
/// cualquiera de las dos monedas y la otra sale de esta tasa.
double? usdDesdeCup({required double cup, required double tasaUsdACup}) {
  if (tasaUsdACup <= 0) return null;
  return cup / tasaUsdACup;
}

double? cupDesdeUsd({required double usd, required double tasaUsdACup}) {
  if (tasaUsdACup <= 0) return null;
  return usd * tasaUsdACup;
}

double? parsearPrecioTeorico(String texto) {
  final limpio = texto.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (limpio.isEmpty || limpio == '.') return null;
  return double.tryParse(limpio);
}

/// [existenciasBase] es el saldo actual del producto en unidades base.
/// Se valora con el precio de venta USD vigente, o con el precio teórico
/// ya pasado a USD. [porcentajeGanancia] es
/// (recaudado + valor del stock − meta) / meta. Puede ser negativo.
PrediccionInversion predecirInversion({
  required double meta,
  required double recaudado,
  required bool incompleto,
  required double existenciasBase,
  required double? precioActualUsd,
}) {
  if (incompleto || meta <= 0) return const PrediccionInversion.incompleta();
  final stock = existenciasBase > 0 ? existenciasBase : 0.0;
  final precio = precioActualUsd != null && precioActualUsd > 0 ? precioActualUsd : null;
  if (precio == null && stock > 0) {
    return PrediccionInversion._(existenciasBase: stock, sinPrecio: true);
  }
  final valor = stock * (precio ?? 0);
  final proyectado = recaudado + valor;
  final ganancia = proyectado - meta;
  return PrediccionInversion._(
    existenciasBase: stock,
    precioActualUsd: precio,
    valorExistenciasUsd: valor,
    proyectadoUsd: proyectado,
    gananciaUsd: ganancia,
    porcentajeGanancia: ganancia / meta,
  );
}

class ResumenListaInversion {
  final double? costoUnitarioUsd;
  final double? cumplimiento;

  const ResumenListaInversion({this.costoUnitarioUsd, this.cumplimiento});
}

class EstudioInversion {
  final List<TramoInversion> tramos;
  final List<VentaInversion> ventasSinTramo;
  final bool datosIncompletos;
  final double? precioActualUsd;
  final double? precioActualCup;

  /// Saldo actual del producto, variantes y ubicaciones ya en unidades base.
  /// Solo el tramo en curso lo conserva: uno cerrado llegó a cero antes de
  /// la recepción siguiente.
  final double existenciasBase;

  const EstudioInversion({
    required this.tramos,
    this.ventasSinTramo = const [],
    this.datosIncompletos = false,
    this.precioActualUsd,
    this.precioActualCup,
    this.existenciasBase = 0,
  });

  List<TramoInversion> get delMasRecienteAlMasAntiguo =>
      tramos.reversed.toList(growable: false);

  double existenciasDe(TramoInversion tramo) => tramo.enCurso ? existenciasBase : 0;

  /// El tramo que el listado resume: el que sigue abierto, o el último si ya
  /// se agotó. El costo es la meta partida por las unidades base recibidas.
  ResumenListaInversion? get resumenDelListado {
    if (tramos.isEmpty) return null;
    TramoInversion? abierto;
    for (final tramo in tramos.reversed) {
      if (tramo.enCurso) {
        abierto = tramo;
        break;
      }
    }
    final tramo = abierto ?? tramos.last;
    final unidades = tramo.recepciones.fold<double>(
      0,
      (suma, recepcion) => suma + (recepcion.cuentaParaStock ? recepcion.unidadesBase : 0),
    );
    return ResumenListaInversion(
      costoUnitarioUsd: unidades > 0 && tramo.meta > 0 ? tramo.meta / unidades : null,
      cumplimiento: tramo.cumplimiento,
    );
  }

  EstudioInversion conPrecioActual({double? usd, double? cup}) {
    return EstudioInversion(
      tramos: tramos,
      ventasSinTramo: ventasSinTramo,
      datosIncompletos: datosIncompletos,
      precioActualUsd: usd,
      precioActualCup: cup,
      existenciasBase: existenciasBase,
    );
  }
}

/// Arma los tramos. [existencia] es la serie real de stock (variantes y
/// ubicaciones ya sumadas). Si no viene, se reconstruye con recepciones,
/// ventas y [ajustes].
EstudioInversion estudiarInversion({
  required List<RecepcionInversion> recepciones,
  required List<VentaInversion> ventas,
  List<AjusteStock> ajustes = const [],
  List<ExistenciaProducto>? existencia,
}) {
  final conStock = recepciones.where((r) => r.cuentaParaStock).toList()
    ..sort((a, b) => a.fecha.compareTo(b.fecha));
  final serie = (existencia ??
          _reconstruirExistencia(
            recepciones: conStock,
            ventas: ventas,
            ajustes: ajustes,
          ))
      .toList()
    ..sort((a, b) => a.fecha.compareTo(b.fecha));

  final tramos = _partirRecepciones(conStock, serie);
  final sinTramo = <VentaInversion>[];
  final ventasPorTramo = {for (final tramo in tramos) tramo: <VentaInversion>[]};

  final ventasOrdenadas = ventas.toList()
    ..sort((a, b) => a.fecha.compareTo(b.fecha));
  for (final venta in ventasOrdenadas) {
    final destino = _tramoDeVenta(tramos, venta.fecha);
    if (destino == null) {
      sinTramo.add(venta);
    } else {
      ventasPorTramo[destino]!.add(venta);
    }
  }

  final saldo = serie.isEmpty ? 0.0 : serie.last.unidadesBase;
  return EstudioInversion(
    datosIncompletos: recepciones.any((r) => !r.cuentaParaStock),
    ventasSinTramo: sinTramo,
    existenciasBase: saldo > 0 ? saldo : 0,
    tramos: [
      for (final tramo in tramos)
        TramoInversion(
          inicio: tramo.inicio,
          fin: tramo.fin,
          recepciones: tramo.recepciones,
          ventas: ventasPorTramo[tramo]!,
        ),
    ],
  );
}

class _TramoAbierto {
  final DateTime inicio;
  final DateTime? fin;
  final List<RecepcionInversion> recepciones;

  _TramoAbierto({required this.inicio, required this.fin, required this.recepciones});
}

List<_TramoAbierto> _partirRecepciones(
  List<RecepcionInversion> recepciones,
  List<ExistenciaProducto> serie,
) {
  final tramos = <_TramoAbierto>[];
  for (final recepcion in recepciones) {
    final anterior = tramos.isEmpty ? null : tramos.last;
    final agoto = anterior != null &&
        serie.any(
          (punto) =>
              punto.fecha.isAfter(anterior.inicio) &&
              punto.fecha.isBefore(recepcion.fecha) &&
              punto.agotado,
        );
    if (anterior == null || agoto) {
      tramos.add(
        _TramoAbierto(inicio: recepcion.fecha, fin: null, recepciones: [recepcion]),
      );
    } else {
      anterior.recepciones.add(recepcion);
    }
  }

  return [
    for (var i = 0; i < tramos.length; i++)
      _TramoAbierto(
        inicio: tramos[i].inicio,
        fin: _primerAgotado(
          serie,
          desde: tramos[i].inicio,
          antesDe: i + 1 < tramos.length ? tramos[i + 1].inicio : null,
        ),
        recepciones: tramos[i].recepciones,
      ),
  ];
}

DateTime? _primerAgotado(
  List<ExistenciaProducto> serie, {
  required DateTime desde,
  required DateTime? antesDe,
}) {
  for (final punto in serie) {
    if (!punto.fecha.isAfter(desde)) continue;
    if (antesDe != null && !punto.fecha.isBefore(antesDe)) break;
    if (punto.agotado) return punto.fecha;
  }
  return null;
}

_TramoAbierto? _tramoDeVenta(List<_TramoAbierto> tramos, DateTime fecha) {
  for (final tramo in tramos) {
    final despuesDelInicio = !fecha.isBefore(tramo.inicio);
    final antesDelFin = tramo.fin == null || !fecha.isAfter(tramo.fin!);
    if (despuesDelInicio && antesDelFin) return tramo;
  }
  return null;
}

List<ExistenciaProducto> _reconstruirExistencia({
  required List<RecepcionInversion> recepciones,
  required List<VentaInversion> ventas,
  required List<AjusteStock> ajustes,
}) {
  final eventos = <_Delta>[
    for (final recepcion in recepciones)
      _Delta(recepcion.fecha, 3, recepcion.unidadesBase),
    for (final venta in ventas) _Delta(venta.fecha, 0, -venta.unidadesBase),
    for (final ajuste in ajustes)
      _Delta(ajuste.fecha, ajuste.deltaUnidadesBase < 0 ? 1 : 2, ajuste.deltaUnidadesBase),
  ]..sort((a, b) {
      final porFecha = a.fecha.compareTo(b.fecha);
      if (porFecha != 0) return porFecha;
      return a.orden.compareTo(b.orden);
    });

  var stock = 0.0;
  final serie = <ExistenciaProducto>[];
  for (final evento in eventos) {
    stock += evento.delta;
    serie.add(ExistenciaProducto(fecha: evento.fecha, unidadesBase: stock));
  }
  return serie;
}

class _Delta {
  final DateTime fecha;
  final int orden;
  final double delta;

  const _Delta(this.fecha, this.orden, this.delta);
}
