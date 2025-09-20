import 'dart:convert';

// ============================================================================
// MODELOS PARA UNIDADES DE MEDIDA
// ============================================================================

class UnidadMedida {
  final int id;
  final String denominacion;
  final String abreviatura;
  final int tipoUnidad; // 1=Peso, 2=Volumen, 3=Longitud, 4=Unidad
  final bool esBase;
  final double? factorBase;
  final String? descripcion;
  final DateTime createdAt;

  UnidadMedida({
    required this.id,
    required this.denominacion,
    required this.abreviatura,
    required this.tipoUnidad,
    this.esBase = false,
    this.factorBase,
    this.descripcion,
    required this.createdAt,
  });

  factory UnidadMedida.fromJson(Map<String, dynamic> json) {
    return UnidadMedida(
      id: json['id'] as int,
      denominacion: json['denominacion'] as String,
      abreviatura: json['abreviatura'] as String,
      tipoUnidad: json['tipo_unidad'] as int,
      esBase: json['es_base'] as bool? ?? false,
      factorBase: (json['factor_base'] as num?)?.toDouble(),
      descripcion: json['descripcion'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'abreviatura': abreviatura,
      'tipo_unidad': tipoUnidad,
      'es_base': esBase,
      'factor_base': factorBase,
      'descripcion': descripcion,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get tipoUnidadTexto {
    switch (tipoUnidad) {
      case 1: return 'Peso';
      case 2: return 'Volumen';
      case 3: return 'Longitud';
      case 4: return 'Unidad';
      default: return 'Desconocido';
    }
  }
}

class ConversionUnidad {
  final int id;
  final int idUnidadOrigen;
  final int idUnidadDestino;
  final double factorConversion;
  final bool esAproximada;
  final String? observaciones;
  final DateTime createdAt;
  final UnidadMedida? unidadOrigen;
  final UnidadMedida? unidadDestino;

  ConversionUnidad({
    required this.id,
    required this.idUnidadOrigen,
    required this.idUnidadDestino,
    required this.factorConversion,
    this.esAproximada = false,
    this.observaciones,
    required this.createdAt,
    this.unidadOrigen,
    this.unidadDestino,
  });

  factory ConversionUnidad.fromJson(Map<String, dynamic> json) {
    // Manejo seguro de valores null para evitar errores de type cast
    int? parseIntSafely(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is num) return value.toInt();
      return null;
    }

    double? parseDoubleSafely(dynamic value) {
      if (value == null) return null;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value);
      if (value is num) return value.toDouble();
      return null;
    }

    UnidadMedida? parseUnidadMedida(dynamic data) {
      if (data == null) return null;
      if (data is! Map<String, dynamic>) return null;
      
      try {
        return UnidadMedida(
          id: parseIntSafely(data['id']) ?? 0,
          denominacion: data['denominacion']?.toString() ?? '',
          abreviatura: data['abreviatura']?.toString() ?? '',
          tipoUnidad: parseIntSafely(data['tipo_unidad']) ?? 1,
          esBase: data['es_base'] as bool? ?? false,
          factorBase: parseDoubleSafely(data['factor_base']),
          descripcion: data['descripcion']?.toString(),
          createdAt: DateTime.tryParse(data['created_at']?.toString() ?? '') ?? DateTime.now(),
        );
      } catch (e) {
        print('❌ Error parseando UnidadMedida: $e');
        return null;
      }
    }

    try {
      return ConversionUnidad(
        id: parseIntSafely(json['id']) ?? 0,
        idUnidadOrigen: parseIntSafely(json['id_unidad_origen']) ?? 0,
        idUnidadDestino: parseIntSafely(json['id_unidad_destino']) ?? 0,
        factorConversion: parseDoubleSafely(json['factor_conversion']) ?? 1.0,
        esAproximada: json['es_aproximada'] as bool? ?? false,
        observaciones: json['observaciones']?.toString(),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
        unidadOrigen: parseUnidadMedida(json['unidad_origen']),
        unidadDestino: parseUnidadMedida(json['unidad_destino']),
      );
    } catch (e) {
      print('❌ Error parseando ConversionUnidad: $e');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_unidad_origen': idUnidadOrigen,
      'id_unidad_destino': idUnidadDestino,
      'factor_conversion': factorConversion,
      'es_aproximada': esAproximada,
      'observaciones': observaciones,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class ProductoUnidad {
  final int? id;
  final int idProducto;
  final int idUnidadMedida;
  final double factorProducto;
  final bool esUnidadCompra;
  final bool esUnidadVenta;
  final bool esUnidadInventario;
  final String? observaciones;
  final DateTime? createdAt;
  final UnidadMedida? unidadMedida;

  ProductoUnidad({
    this.id,
    required this.idProducto,
    required this.idUnidadMedida,
    this.factorProducto = 1.0,
    this.esUnidadCompra = false,
    this.esUnidadVenta = false,
    this.esUnidadInventario = false,
    this.observaciones,
    this.createdAt,
    this.unidadMedida,
  });

  factory ProductoUnidad.fromJson(Map<String, dynamic> json) {
    return ProductoUnidad(
      id: json['id'] as int?,
      idProducto: json['id_producto'] as int,
      idUnidadMedida: json['id_unidad_medida'] as int,
      factorProducto: (json['factor_producto'] as num?)?.toDouble() ?? 1.0,
      esUnidadCompra: json['es_unidad_compra'] as bool? ?? false,
      esUnidadVenta: json['es_unidad_venta'] as bool? ?? false,
      esUnidadInventario: json['es_unidad_inventario'] as bool? ?? false,
      observaciones: json['observaciones'] as String?,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String)
          : null,
      unidadMedida: json['unidad_medida'] != null 
          ? UnidadMedida.fromJson(json['unidad_medida'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_producto': idProducto,
      'id_unidad_medida': idUnidadMedida,
      'factor_producto': factorProducto,
      'es_unidad_compra': esUnidadCompra,
      'es_unidad_venta': esUnidadVenta,
      'es_unidad_inventario': esUnidadInventario,
      'observaciones': observaciones,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}

// ============================================================================
// MODELOS PARA PLATOS ELABORADOS
// ============================================================================

class PlatoElaborado {
  final int id;
  final String nombre;
  final String? descripcion;
  final int? idCategoria;
  final double precioVenta;
  final int? tiempoPreparacion;
  final bool esActivo;
  final String? imagen;
  final String? instruccionesPreparacion;
  final DateTime createdAt;
  final CategoriaPlato? categoria;
  final List<Receta> recetas;

  PlatoElaborado({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.idCategoria,
    required this.precioVenta,
    this.tiempoPreparacion,
    this.esActivo = true,
    this.imagen,
    this.instruccionesPreparacion,
    required this.createdAt,
    this.categoria,
    this.recetas = const [],
  });

  factory PlatoElaborado.fromJson(Map<String, dynamic> json) {
    // Funciones de parsing seguro
    int? parseIntSafely(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is num) return value.toInt();
      return null;
    }

    double? parseDoubleSafely(dynamic value) {
      if (value == null) return null;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value);
      if (value is num) return value.toDouble();
      return null;
    }

    try {
      return PlatoElaborado(
        id: parseIntSafely(json['id']) ?? 0,
        nombre: json['nombre']?.toString() ?? '',
        descripcion: json['descripcion']?.toString(),
        idCategoria: parseIntSafely(json['id_categoria']),
        precioVenta: parseDoubleSafely(json['precio_venta']) ?? 0.0,
        tiempoPreparacion: parseIntSafely(json['tiempo_preparacion']),
        esActivo: json['es_activo'] as bool? ?? true,
        imagen: json['imagen']?.toString(),
        instruccionesPreparacion: json['instrucciones_preparacion']?.toString(),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
        categoria: json['categoria'] != null 
            ? CategoriaPlato.fromJson(json['categoria'] as Map<String, dynamic>)
            : null,
        recetas: json['recetas'] != null 
            ? (json['recetas'] as List).map((r) => Receta.fromJson(r as Map<String, dynamic>)).toList()
            : [],
      );
    } catch (e) {
      print('❌ Error parseando PlatoElaborado: $e');
      print('❌ JSON recibido: $json');
      rethrow;
    }
  }

  double get costoEstimado {
    return recetas.fold(0.0, (sum, receta) => sum + (receta.costoEstimado ?? 0));
  }

  double get margenEstimado {
    final costo = costoEstimado;
    if (costo == 0) return 0;
    return ((precioVenta - costo) / precioVenta) * 100;
  }
}

class CategoriaPlato {
  final int id;
  final String nombre;
  final String? descripcion;
  final int ordenMenu;
  final bool esActivo;
  final String? imagen;
  final DateTime? createdAt;

  CategoriaPlato({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.ordenMenu = 1,
    this.esActivo = true,
    this.imagen,
    this.createdAt,
  });

  factory CategoriaPlato.fromJson(Map<String, dynamic> json) {
    // Funciones de parsing seguro
    int? parseIntSafely(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is num) return value.toInt();
      return null;
    }

    try {
      return CategoriaPlato(
        id: parseIntSafely(json['id']) ?? 0, // Usar 0 como valor por defecto si no existe
        nombre: json['nombre']?.toString() ?? '',
        descripcion: json['descripcion']?.toString(),
        ordenMenu: parseIntSafely(json['orden_menu']) ?? 1,
        esActivo: json['es_activo'] as bool? ?? true,
        imagen: json['imagen']?.toString(),
        createdAt: json['created_at'] != null 
            ? DateTime.tryParse(json['created_at'].toString())
            : null,
      );
    } catch (e) {
      print('❌ Error parseando CategoriaPlato: $e');
      print('❌ JSON recibido: $json');
      // Crear una categoría básica en caso de error total
      return CategoriaPlato(
        id: 0,
        nombre: json['nombre']?.toString() ?? 'Sin categoría',
        descripcion: json['descripcion']?.toString(),
      );
    }
  }
}

class Receta {
  final int id;
  final int idPlato;
  final int idProductoInventario;
  final double cantidadRequerida;
  final String? um;
  final String? observaciones;
  final int orden;
  final DateTime createdAt;
  final ProductoInventario? producto;
  final double? costoEstimado;

  Receta({
    required this.id,
    required this.idPlato,
    required this.idProductoInventario,
    required this.cantidadRequerida,
    this.um,
    this.observaciones,
    this.orden = 1,
    required this.createdAt,
    this.producto,
    this.costoEstimado,
  });

  factory Receta.fromJson(Map<String, dynamic> json) {
    return Receta(
      id: json['id'] as int,
      idPlato: json['id_plato'] as int,
      idProductoInventario: json['id_producto_inventario'] as int,
      cantidadRequerida: (json['cantidad_requerida'] as num).toDouble(),
      um: json['um'] as String?,
      observaciones: json['observaciones'] as String?,
      orden: json['orden'] as int? ?? 1,
      createdAt: DateTime.parse(json['created_at'] as String),
      producto: json['producto'] != null 
          ? ProductoInventario.fromJson(json['producto'] as Map<String, dynamic>)
          : null,
    );
  }
}

class ProductoInventario {
  final int id;
  final String denominacion;
  final String sku;
  final String? um;

  ProductoInventario({
    required this.id,
    required this.denominacion,
    required this.sku,
    this.um,
  });

  factory ProductoInventario.fromJson(Map<String, dynamic> json) {
    return ProductoInventario(
      id: json['id'] as int,
      denominacion: json['denominacion'] as String,
      sku: json['sku'] as String,
      um: json['um'] as String?,
    );
  }
}

// ============================================================================
// MODELOS PARA DISPONIBILIDAD
// ============================================================================

class DisponibilidadPlato {
  final bool disponible;
  final List<IngredienteFaltante> ingredientesFaltantes;
  final double costoTotal;
  final int cantidadSolicitada;
  final String? error;

  DisponibilidadPlato({
    required this.disponible,
    this.ingredientesFaltantes = const [],
    this.costoTotal = 0,
    this.cantidadSolicitada = 1,
    this.error,
  });

  factory DisponibilidadPlato.fromJson(Map<String, dynamic> json) {
    return DisponibilidadPlato(
      disponible: json['disponible'] as bool,
      ingredientesFaltantes: json['ingredientes_faltantes'] != null 
          ? (json['ingredientes_faltantes'] as List)
              .map((i) => IngredienteFaltante.fromJson(i as Map<String, dynamic>))
              .toList()
          : [],
      costoTotal: (json['costo_total'] as num?)?.toDouble() ?? 0,
      cantidadSolicitada: json['cantidad_solicitada'] as int? ?? 1,
      error: json['error'] as String?,
    );
  }
}

class IngredienteFaltante {
  final int productoId;
  final String producto;
  final String sku;
  final double necesario;
  final String? unidadReceta;
  final double disponible;
  final double faltante;
  final double costoUnitario;

  IngredienteFaltante({
    required this.productoId,
    required this.producto,
    required this.sku,
    required this.necesario,
    this.unidadReceta,
    required this.disponible,
    required this.faltante,
    this.costoUnitario = 0,
  });

  factory IngredienteFaltante.fromJson(Map<String, dynamic> json) {
    return IngredienteFaltante(
      productoId: json['producto_id'] as int,
      producto: json['producto'] as String,
      sku: json['sku'] as String,
      necesario: (json['necesario'] as num).toDouble(),
      unidadReceta: json['unidad_receta'] as String?,
      disponible: (json['disponible'] as num).toDouble(),
      faltante: (json['faltante'] as num).toDouble(),
      costoUnitario: (json['costo_unitario'] as num?)?.toDouble() ?? 0,
    );
  }
}

// ============================================================================
// MODELOS PARA COSTOS DE PRODUCCIÓN
// ============================================================================

class CostoProduccion {
  final int? id;
  final int idPlato;
  final DateTime fechaCalculo;
  final double costoIngredientes;
  final double costoManoObra;
  final double costoIndirecto;
  final double margenDeseado;
  final String? calculadoPor;
  final String? observaciones;
  final DateTime? createdAt;

  CostoProduccion({
    this.id,
    required this.idPlato,
    required this.fechaCalculo,
    required this.costoIngredientes,
    this.costoManoObra = 0,
    this.costoIndirecto = 0,
    this.margenDeseado = 30.0,
    this.calculadoPor,
    this.observaciones,
    this.createdAt,
  });

  factory CostoProduccion.fromJson(Map<String, dynamic> json) {
    return CostoProduccion(
      id: json['id'] as int?,
      idPlato: json['id_plato'] as int,
      fechaCalculo: DateTime.parse(json['fecha_calculo'] as String),
      costoIngredientes: (json['costo_ingredientes'] as num).toDouble(),
      costoManoObra: (json['costo_mano_obra'] as num?)?.toDouble() ?? 0,
      costoIndirecto: (json['costo_indirecto'] as num?)?.toDouble() ?? 0,
      margenDeseado: (json['margen_deseado'] as num?)?.toDouble() ?? 30.0,
      calculadoPor: json['calculado_por'] as String?,
      observaciones: json['observaciones'] as String?,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  double get costoTotal => costoIngredientes + costoManoObra + costoIndirecto;
  double get precioSugerido => costoTotal * (1 + margenDeseado / 100);
}

// ============================================================================
// MODELOS PARA DESCUENTOS DE INVENTARIO
// ============================================================================

class ResultadoDescuento {
  final bool success;
  final List<DescuentoDetalle> descuentos;
  final int? operacionId;
  final String? plato;
  final int? cantidadPlatos;
  final String? error;
  final String? warning;

  ResultadoDescuento({
    required this.success,
    this.descuentos = const [],
    this.operacionId,
    this.plato,
    this.cantidadPlatos,
    this.error,
    this.warning,
  });

  factory ResultadoDescuento.fromJson(Map<String, dynamic> json) {
    return ResultadoDescuento(
      success: json['success'] as bool,
      descuentos: json['descuentos'] != null 
          ? (json['descuentos'] as List)
              .map((d) => DescuentoDetalle.fromJson(d as Map<String, dynamic>))
              .toList()
          : [],
      operacionId: json['operacion_id'] as int?,
      plato: json['plato'] as String?,
      cantidadPlatos: json['cantidad_platos'] as int?,
      error: json['error'] as String?,
      warning: json['warning'] as String?,
    );
  }
}

class DescuentoDetalle {
  final String producto;
  final String sku;
  final double cantidadDescontada;
  final int ubicacionId;
  final double precioCosto;
  final double importe;

  DescuentoDetalle({
    required this.producto,
    required this.sku,
    required this.cantidadDescontada,
    required this.ubicacionId,
    required this.precioCosto,
    required this.importe,
  });

  factory DescuentoDetalle.fromJson(Map<String, dynamic> json) {
    return DescuentoDetalle(
      producto: json['producto'] as String,
      sku: json['sku'] as String,
      cantidadDescontada: (json['cantidad_descontada'] as num).toDouble(),
      ubicacionId: json['ubicacion_id'] as int,
      precioCosto: (json['precio_costo'] as num).toDouble(),
      importe: (json['importe'] as num).toDouble(),
    );
  }
}

class DescuentoInventario {
  final int id;
  final int idVentaPlato;
  final int idProductoInventario;
  final double cantidadDescontada;
  final int idUnidadMedida;
  final int idUbicacion;
  final double? precioCosto;
  final DateTime fechaDescuento;
  final String procesadoPor;
  final String? observaciones;
  final VentaPlato? ventaPlato;
  final ProductoInventario? producto;
  final UbicacionAlmacen? ubicacion;

  DescuentoInventario({
    required this.id,
    required this.idVentaPlato,
    required this.idProductoInventario,
    required this.cantidadDescontada,
    required this.idUnidadMedida,
    required this.idUbicacion,
    this.precioCosto,
    required this.fechaDescuento,
    required this.procesadoPor,
    this.observaciones,
    this.ventaPlato,
    this.producto,
    this.ubicacion,
  });

  factory DescuentoInventario.fromJson(Map<String, dynamic> json) {
    return DescuentoInventario(
      id: json['id'] as int,
      idVentaPlato: json['id_venta_plato'] as int,
      idProductoInventario: json['id_producto_inventario'] as int,
      cantidadDescontada: (json['cantidad_descontada'] as num).toDouble(),
      idUnidadMedida: json['id_unidad_medida'] as int,
      idUbicacion: json['id_ubicacion'] as int,
      precioCosto: (json['precio_costo'] as num?)?.toDouble(),
      fechaDescuento: DateTime.parse(json['fecha_descuento'] as String),
      procesadoPor: json['procesado_por'] as String,
      observaciones: json['observaciones'] as String?,
      ventaPlato: json['venta_plato'] != null 
          ? VentaPlato.fromJson(json['venta_plato'] as Map<String, dynamic>)
          : null,
      producto: json['producto'] != null 
          ? ProductoInventario.fromJson(json['producto'] as Map<String, dynamic>)
          : null,
      ubicacion: json['ubicacion'] != null 
          ? UbicacionAlmacen.fromJson(json['ubicacion'] as Map<String, dynamic>)
          : null,
    );
  }
}

class VentaPlato {
  final int cantidad;
  final PlatoElaborado? plato;

  VentaPlato({
    required this.cantidad,
    this.plato,
  });

  factory VentaPlato.fromJson(Map<String, dynamic> json) {
    return VentaPlato(
      cantidad: json['cantidad'] as int,
      plato: json['plato'] != null 
          ? PlatoElaborado.fromJson(json['plato'] as Map<String, dynamic>)
          : null,
    );
  }
}

class UbicacionAlmacen {
  final String skuCodigo;

  UbicacionAlmacen({
    required this.skuCodigo,
  });

  factory UbicacionAlmacen.fromJson(Map<String, dynamic> json) {
    return UbicacionAlmacen(
      skuCodigo: json['sku_codigo'] as String,
    );
  }
}

// ============================================================================
// MODELOS PARA DESPERDICIOS
// ============================================================================

class Desperdicio {
  final int id;
  final int idProductoInventario;
  final int? idPlato;
  final double cantidadDesperdiciada;
  final int idUnidadMedida;
  final String motivoDesperdicio;
  final double? costoDesperdicio;
  final DateTime fechaDesperdicio;
  final String registradoPor;
  final String? observaciones;
  final DateTime createdAt;
  final ProductoInventario? producto;
  final PlatoElaborado? plato;
  final UnidadMedida? unidad;

  Desperdicio({
    required this.id,
    required this.idProductoInventario,
    this.idPlato,
    required this.cantidadDesperdiciada,
    required this.idUnidadMedida,
    required this.motivoDesperdicio,
    this.costoDesperdicio,
    required this.fechaDesperdicio,
    required this.registradoPor,
    this.observaciones,
    required this.createdAt,
    this.producto,
    this.plato,
    this.unidad,
  });

  factory Desperdicio.fromJson(Map<String, dynamic> json) {
    return Desperdicio(
      id: json['id'] as int,
      idProductoInventario: json['id_producto_inventario'] as int,
      idPlato: json['id_plato'] as int?,
      cantidadDesperdiciada: (json['cantidad_desperdiciada'] as num).toDouble(),
      idUnidadMedida: json['id_unidad_medida'] as int,
      motivoDesperdicio: json['motivo_desperdicio'] as String,
      costoDesperdicio: (json['costo_desperdicio'] as num?)?.toDouble(),
      fechaDesperdicio: DateTime.parse(json['fecha_desperdicio'] as String),
      registradoPor: json['registrado_por'] as String,
      observaciones: json['observaciones'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      producto: json['producto'] != null 
          ? ProductoInventario.fromJson(json['producto'] as Map<String, dynamic>)
          : null,
      plato: json['plato'] != null 
          ? PlatoElaborado.fromJson(json['plato'] as Map<String, dynamic>)
          : null,
      unidad: json['unidad'] != null 
          ? UnidadMedida.fromJson(json['unidad'] as Map<String, dynamic>)
          : null,
    );
  }
}

// ============================================================================
// MODELOS PARA ESTADOS DE PREPARACIÓN
// ============================================================================

class EstadoPreparacion {
  final int id;
  final int idVentaPlato;
  final int estado; // 1=Pendiente, 2=En preparación, 3=Listo, 4=Entregado
  final int? tiempoEstimado;
  final int? tiempoReal;
  final String? asignadoA;
  final String? observacionesCocina;
  final DateTime fechaCambioEstado;
  final String cambiadoPor;
  final VentaPlato? ventaPlato;

  EstadoPreparacion({
    required this.id,
    required this.idVentaPlato,
    required this.estado,
    this.tiempoEstimado,
    this.tiempoReal,
    this.asignadoA,
    this.observacionesCocina,
    required this.fechaCambioEstado,
    required this.cambiadoPor,
    this.ventaPlato,
  });

  factory EstadoPreparacion.fromJson(Map<String, dynamic> json) {
    return EstadoPreparacion(
      id: json['id'] as int,
      idVentaPlato: json['id_venta_plato'] as int,
      estado: json['estado'] as int,
      tiempoEstimado: json['tiempo_estimado'] as int?,
      tiempoReal: json['tiempo_real'] as int?,
      asignadoA: json['asignado_a'] as String?,
      observacionesCocina: json['observaciones_cocina'] as String?,
      fechaCambioEstado: DateTime.parse(json['fecha_cambio_estado'] as String),
      cambiadoPor: json['cambiado_por'] as String,
      ventaPlato: json['venta_plato'] != null 
          ? VentaPlato.fromJson(json['venta_plato'] as Map<String, dynamic>)
          : null,
    );
  }

  String get estadoTexto {
    switch (estado) {
      case 1: return 'Pendiente';
      case 2: return 'En preparación';
      case 3: return 'Listo';
      case 4: return 'Entregado';
      default: return 'Desconocido';
    }
  }

  bool get estaRetrasado {
    if (tiempoEstimado == null || tiempoReal == null) return false;
    return tiempoReal! > tiempoEstimado!;
  }
}
