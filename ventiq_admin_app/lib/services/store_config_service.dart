import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class StoreConfigService {
  static final _supabase = Supabase.instance.client;

  /// Obtiene la configuración de la tienda
  /// Si no existe, la crea con valores por defecto
  static Future<Map<String, dynamic>> getStoreConfig(int storeId) async {
    try {
      print('🔧 Obteniendo configuración para tienda ID: $storeId');

      // Intentar obtener configuración existente
      final response =
          await _supabase
              .from('app_dat_configuracion_tienda')
              .select('*')
              .eq('id_tienda', storeId)
              .maybeSingle();

      if (response != null) {
        print('✅ Configuración encontrada para tienda $storeId');
        return response;
      } else {
        print(
          '⚠️ No existe configuración para tienda $storeId, creando con valores por defecto...',
        );

        // Crear configuración con valores por defecto
        final newConfig =
            await _supabase
                .from('app_dat_configuracion_tienda')
                .insert({
                  'id_tienda': storeId,
                  'need_master_password_to_cancel': false,
                  'need_all_orders_completed_to_continue': false,
                  'metodo_redondeo_precio_venta': 'NO_REDONDEAR',
                  'guardar_impresora_por_defecto': false,
                  'tickets_a_imprimir': ['cliente', 'almacen'],
                  'copias_por_ticket': {'cliente': 1, 'almacen': 1},
                  'autocompletar_cantidad_real_conteo': false,
                })
                .select()
                .single();

        print(
          '✅ Configuración creada para tienda $storeId con valores por defecto',
        );
        return newConfig;
      }
    } catch (e) {
      print('❌ Error al obtener/crear configuración de tienda: $e');
      rethrow;
    }
  }

  /// Actualiza la configuración de la tienda
  static Future<Map<String, dynamic>> updateStoreConfig(
    int storeId, {
    bool? needMasterPasswordToCancel,
    bool? needAllOrdersCompletedToContinue,
    String? masterPassword,
    bool? manejaInventario,
    bool? mostrarDebeHaberEnConteoInventario,
    bool? permiteVenderAunSinDisponibilidad,
    bool? noSolicitarCliente,
    bool? allowDiscountOnVendedor,
    bool? permitirImprimirPendientes,
    String? metodoRedondeoPrecioVenta,
    Map<String, dynamic>? tpvTrabajadorEncargadoCarnaval,
    bool? allowSellerMakeOrderModifications,
    bool? precioVentaRegidoPorUsd,
    bool? cambiarFechaCreacionOperacionAlCierre,
    bool? solicitarImagenOperacion,
    bool? permitirModoOfflineCompleto,
    int? diasMaxSinValidarLicencia,
    bool? guardarImpresoraPorDefecto,
    List<String>? ticketsAImprimir,
    Map<String, int>? copiasPorTicket,
    bool? autocompletarCantidadRealConteo,
    bool? modoRestaurante,
    bool? cocinaActiva,
  }) async {
    try {
      print('🔧 Actualizando configuración para tienda ID: $storeId');

      final updateData = <String, dynamic>{};

      if (needMasterPasswordToCancel != null) {
        updateData['need_master_password_to_cancel'] =
            needMasterPasswordToCancel;
        print(
          '  - need_master_password_to_cancel: $needMasterPasswordToCancel',
        );
      }

      if (needAllOrdersCompletedToContinue != null) {
        updateData['need_all_orders_completed_to_continue'] =
            needAllOrdersCompletedToContinue;
        print(
          '  - need_all_orders_completed_to_continue: $needAllOrdersCompletedToContinue',
        );
      }

      if (masterPassword != null) {
        // Encriptar la contraseña usando SHA-256
        final bytes = utf8.encode(masterPassword);
        final digest = sha256.convert(bytes);
        updateData['master_password'] = digest.toString();
        print('  - master_password: [ENCRIPTADA]');
      }

      if (manejaInventario != null) {
        updateData['maneja_inventario'] = manejaInventario;
        print('  - maneja_inventario: $manejaInventario');
      }

      if (mostrarDebeHaberEnConteoInventario != null) {
        updateData['mostrar_debe_haber_en_conteo_inventario'] =
            mostrarDebeHaberEnConteoInventario;
        print(
          '  - mostrar_debe_haber_en_conteo_inventario: $mostrarDebeHaberEnConteoInventario',
        );
      }

      if (permiteVenderAunSinDisponibilidad != null) {
        updateData['permite_vender_aun_sin_disponibilidad'] =
            permiteVenderAunSinDisponibilidad;
        print(
          '  - permite_vender_aun_sin_disponibilidad: $permiteVenderAunSinDisponibilidad',
        );
      }

      if (noSolicitarCliente != null) {
        updateData['no_solicitar_cliente'] = noSolicitarCliente;
        print('  - no_solicitar_cliente: $noSolicitarCliente');
      }

      if (allowDiscountOnVendedor != null) {
        updateData['allow_discount_on_vendedor'] = allowDiscountOnVendedor;
        print('  - allow_discount_on_vendedor: $allowDiscountOnVendedor');
      }

      if (permitirImprimirPendientes != null) {
        updateData['permitir_imprimir_pendientes'] = permitirImprimirPendientes;
        print('  - permitir_imprimir_pendientes: $permitirImprimirPendientes');
      }

      if (metodoRedondeoPrecioVenta != null) {
        updateData['metodo_redondeo_precio_venta'] = metodoRedondeoPrecioVenta;
        print('  - metodo_redondeo_precio_venta: $metodoRedondeoPrecioVenta');
      }

      if (tpvTrabajadorEncargadoCarnaval != null) {
        updateData['tpv_trabajador_encargado_carnaval'] =
            tpvTrabajadorEncargadoCarnaval;
        print(
          '  - tpv_trabajador_encargado_carnaval: $tpvTrabajadorEncargadoCarnaval',
        );
      }

      if (allowSellerMakeOrderModifications != null) {
        updateData['allow_seller_make_order_modifications'] =
            allowSellerMakeOrderModifications;
        print(
          '  - allow_seller_make_order_modifications: $allowSellerMakeOrderModifications',
        );
      }

      if (precioVentaRegidoPorUsd != null) {
        updateData['precio_venta_regido_por_usd'] = precioVentaRegidoPorUsd;
        print('  - precio_venta_regido_por_usd: $precioVentaRegidoPorUsd');
      }

      if (cambiarFechaCreacionOperacionAlCierre != null) {
        updateData['cambiar_fecha_creacion_operacion_al_cierre'] =
            cambiarFechaCreacionOperacionAlCierre;
        print(
          '  - cambiar_fecha_creacion_operacion_al_cierre: $cambiarFechaCreacionOperacionAlCierre',
        );
      }

      if (solicitarImagenOperacion != null) {
        updateData['solicitar_imagen_operacion'] = solicitarImagenOperacion;
        print('  - solicitar_imagen_operacion: $solicitarImagenOperacion');
      }

      if (permitirModoOfflineCompleto != null) {
        updateData['permitir_modo_offline_completo'] =
            permitirModoOfflineCompleto;
        print(
          '  - permitir_modo_offline_completo: $permitirModoOfflineCompleto',
        );
      }

      if (diasMaxSinValidarLicencia != null) {
        updateData['dias_max_sin_validar_licencia'] =
            diasMaxSinValidarLicencia;
        print(
          '  - dias_max_sin_validar_licencia: $diasMaxSinValidarLicencia',
        );
      }

      if (guardarImpresoraPorDefecto != null) {
        updateData['guardar_impresora_por_defecto'] =
            guardarImpresoraPorDefecto;
        print('  - guardar_impresora_por_defecto: $guardarImpresoraPorDefecto');
      }

      if (ticketsAImprimir != null) {
        updateData['tickets_a_imprimir'] = ticketsAImprimir;
        print('  - tickets_a_imprimir: $ticketsAImprimir');
      }

      if (copiasPorTicket != null) {
        updateData['copias_por_ticket'] = copiasPorTicket;
        print('  - copias_por_ticket: $copiasPorTicket');
      }

      if (autocompletarCantidadRealConteo != null) {
        updateData['autocompletar_cantidad_real_conteo'] =
            autocompletarCantidadRealConteo;
        print(
          '  - autocompletar_cantidad_real_conteo: $autocompletarCantidadRealConteo',
        );
      }

      if (modoRestaurante != null) {
        updateData['modo_restaurante'] = modoRestaurante;
        print('  - modo_restaurante: $modoRestaurante');
      }

      if (cocinaActiva != null) {
        updateData['cocina_activa'] = cocinaActiva;
        print('  - cocina_activa: $cocinaActiva');
      }

      if (updateData.isEmpty) {
        throw Exception('No hay datos para actualizar');
      }

      final response =
          await _supabase
              .from('app_dat_configuracion_tienda')
              .update(updateData)
              .eq('id_tienda', storeId)
              .select()
              .single();

      print('✅ Configuración actualizada exitosamente para tienda $storeId');
      return response;
    } catch (e) {
      print('❌ Error al actualizar configuración de tienda: $e');
      rethrow;
    }
  }

  /// Obtiene solo el valor de need_master_password_to_cancel
  static Future<bool> getNeedMasterPasswordToCancel(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['need_master_password_to_cancel'] ?? false;
    } catch (e) {
      print('❌ Error al obtener need_master_password_to_cancel: $e');
      return false; // Valor por defecto en caso de error
    }
  }

  /// Obtiene solo el valor de need_all_orders_completed_to_continue
  static Future<bool> getNeedAllOrdersCompletedToContinue(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['need_all_orders_completed_to_continue'] ?? false;
    } catch (e) {
      print('❌ Error al obtener need_all_orders_completed_to_continue: $e');
      return false; // Valor por defecto en caso de error
    }
  }

  /// Actualiza solo need_master_password_to_cancel
  static Future<void> updateNeedMasterPasswordToCancel(
    int storeId,
    bool value,
  ) async {
    await updateStoreConfig(storeId, needMasterPasswordToCancel: value);
  }

  /// Actualiza solo need_all_orders_completed_to_continue
  static Future<void> updateNeedAllOrdersCompletedToContinue(
    int storeId,
    bool value,
  ) async {
    await updateStoreConfig(storeId, needAllOrdersCompletedToContinue: value);
  }

  /// Actualiza solo master_password
  static Future<void> updateMasterPassword(int storeId, String password) async {
    await updateStoreConfig(storeId, masterPassword: password);
  }

  /// Obtiene el master_password (encriptado)
  static Future<String?> getMasterPassword(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['master_password'];
    } catch (e) {
      print('❌ Error al obtener master_password: $e');
      return null;
    }
  }

  /// Verifica si existe un master_password configurado
  static Future<bool> hasMasterPassword(int storeId) async {
    try {
      final masterPassword = await getMasterPassword(storeId);
      return masterPassword != null && masterPassword.isNotEmpty;
    } catch (e) {
      print('❌ Error al verificar master_password: $e');
      return false;
    }
  }

  /// Obtiene solo el valor de maneja_inventario
  static Future<bool> getManejaInventario(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['maneja_inventario'] ?? false;
    } catch (e) {
      print('❌ Error al obtener maneja_inventario: $e');
      return false; // Valor por defecto en caso de error
    }
  }

  /// Actualiza solo maneja_inventario
  static Future<void> updateManejaInventario(int storeId, bool value) async {
    await updateStoreConfig(storeId, manejaInventario: value);
  }

  /// Obtiene si se muestra "debe haber" en el conteo de inventario
  static Future<bool> getMostrarDebeHaberEnConteoInventario(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['mostrar_debe_haber_en_conteo_inventario'] ?? false;
    } catch (e) {
      print('❌ Error al obtener mostrar_debe_haber_en_conteo_inventario: $e');
      return false;
    }
  }

  /// Actualiza mostrar_debe_haber_en_conteo_inventario
  static Future<void> updateMostrarDebeHaberEnConteoInventario(
    int storeId,
    bool value,
  ) async {
    await updateStoreConfig(
      storeId,
      mostrarDebeHaberEnConteoInventario: value,
    );
  }

  /// Obtiene solo el valor de permite_vender_aun_sin_disponibilidad
  static Future<bool> getPermiteVenderAunSinDisponibilidad(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['permite_vender_aun_sin_disponibilidad'] ?? false;
    } catch (e) {
      print('❌ Error al obtener permite_vender_aun_sin_disponibilidad: $e');
      return false; // Valor por defecto en caso de error
    }
  }

  /// Actualiza solo permite_vender_aun_sin_disponibilidad
  static Future<void> updatePermiteVenderAunSinDisponibilidad(
    int storeId,
    bool value,
  ) async {
    await updateStoreConfig(storeId, permiteVenderAunSinDisponibilidad: value);
  }

  /// Obtiene solo el valor de no_solicitar_cliente
  static Future<bool> getNoSolicitarCliente(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['no_solicitar_cliente'] ?? false;
    } catch (e) {
      print('❌ Error al obtener no_solicitar_cliente: $e');
      return false; // Valor por defecto en caso de error
    }
  }

  /// Actualiza solo no_solicitar_cliente
  static Future<void> updateNoSolicitarCliente(int storeId, bool value) async {
    await updateStoreConfig(storeId, noSolicitarCliente: value);
  }

  static Future<bool> getAllowDiscountOnVendedor(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['allow_discount_on_vendedor'] ?? false;
    } catch (e) {
      print('❌ Error al obtener allow_discount_on_vendedor: $e');
      return false;
    }
  }

  static Future<void> updateAllowDiscountOnVendedor(
    int storeId,
    bool value,
  ) async {
    await updateStoreConfig(storeId, allowDiscountOnVendedor: value);
  }

  /// Obtiene solo el valor de permitir_imprimir_pendientes
  static Future<bool> getAllowPrintPending(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['permitir_imprimir_pendientes'] ?? false;
    } catch (e) {
      print('❌ Error al obtener permitir_imprimir_pendientes: $e');
      return false;
    }
  }

  /// Actualiza permitir_imprimir_pendientes
  static Future<void> updateAllowPrintPending(int storeId, bool value) async {
    await updateStoreConfig(storeId, permitirImprimirPendientes: value);
  }

  /// Obtiene solo el valor de allow_seller_make_order_modifications
  static Future<bool> getAllowSellerMakeOrderModifications(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['allow_seller_make_order_modifications'] ?? false;
    } catch (e) {
      print('❌ Error al obtener allow_seller_make_order_modifications: $e');
      return false;
    }
  }

  /// Actualiza allow_seller_make_order_modifications
  static Future<void> updateAllowSellerMakeOrderModifications(
    int storeId,
    bool value,
  ) async {
    await updateStoreConfig(storeId, allowSellerMakeOrderModifications: value);
  }

  /// Obtiene el método de redondeo configurado
  static Future<String> getMetodoRedondeoPrecioVenta(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['metodo_redondeo_precio_venta'] ?? 'NO_REDONDEAR';
    } catch (e) {
      print('❌ Error al obtener metodo_redondeo_precio_venta: $e');
      return 'NO_REDONDEAR';
    }
  }

  /// Actualiza el método de redondeo configurado
  static Future<void> updateMetodoRedondeoPrecioVenta(
    int storeId,
    String value,
  ) async {
    await updateStoreConfig(storeId, metodoRedondeoPrecioVenta: value);
  }

  /// Obtiene solo el valor de tpv_trabajador_encargado_carnaval
  static Future<Map<String, dynamic>?> getTpvTrabajadorEncargadoCarnaval(
    int storeId,
  ) async {
    try {
      final config = await getStoreConfig(storeId);
      final value = config['tpv_trabajador_encargado_carnaval'];
      if (value == null) return null;
      if (value is String) return jsonDecode(value);
      return value as Map<String, dynamic>;
    } catch (e) {
      print('❌ Error al obtener tpv_trabajador_encargado_carnaval: $e');
      return null;
    }
  }

  /// Actualiza solo tpv_trabajador_encargado_carnaval
  static Future<void> updateTpvTrabajadorEncargadoCarnaval(
    int storeId,
    Map<String, dynamic>? value,
  ) async {
    await updateStoreConfig(storeId, tpvTrabajadorEncargadoCarnaval: value);
  }

  static Future<void> updateCambiarFechaCreacionOperacionAlCierre(
    int storeId,
    bool value,
  ) async {
    await updateStoreConfig(
      storeId,
      cambiarFechaCreacionOperacionAlCierre: value,
    );
  }

  static Future<void> updateSolicitarImagenOperacion(
    int storeId,
    bool value,
  ) async {
    await updateStoreConfig(storeId, solicitarImagenOperacion: value);
  }

  /// Obtiene el valor de precio_venta_regido_por_usd
  static Future<bool> getPrecioVentaRegidoPorUsd(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['precio_venta_regido_por_usd'] ?? false;
    } catch (e) {
      print('❌ Error al obtener precio_venta_regido_por_usd: $e');
      return false;
    }
  }

  /// Actualiza precio_venta_regido_por_usd
  static Future<void> updatePrecioVentaRegidoPorUsd(
    int storeId,
    bool value,
  ) async {
    await updateStoreConfig(storeId, precioVentaRegidoPorUsd: value);
  }

  /// Obtiene el valor de permitir_modo_offline_completo
  static Future<bool> getPermitirModoOfflineCompleto(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['permitir_modo_offline_completo'] ?? false;
    } catch (e) {
      print('❌ Error al obtener permitir_modo_offline_completo: $e');
      return false;
    }
  }

  /// Actualiza permitir_modo_offline_completo
  static Future<void> updatePermitirModoOfflineCompleto(
    int storeId,
    bool value,
  ) async {
    await updateStoreConfig(storeId, permitirModoOfflineCompleto: value);
  }

  /// Obtiene el valor de dias_max_sin_validar_licencia
  static Future<int> getDiasMaxSinValidarLicencia(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['dias_max_sin_validar_licencia'] ?? 7;
    } catch (e) {
      print('❌ Error al obtener dias_max_sin_validar_licencia: $e');
      return 7;
    }
  }

  /// Actualiza dias_max_sin_validar_licencia
  static Future<void> updateDiasMaxSinValidarLicencia(
    int storeId,
    int value,
  ) async {
    await updateStoreConfig(storeId, diasMaxSinValidarLicencia: value);
  }

  /// Obtiene el valor de guardar_impresora_por_defecto
  static Future<bool> getGuardarImpresoraPorDefecto(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['guardar_impresora_por_defecto'] ?? false;
    } catch (e) {
      print('❌ Error al obtener guardar_impresora_por_defecto: $e');
      return false;
    }
  }

  /// Actualiza guardar_impresora_por_defecto
  static Future<void> updateGuardarImpresoraPorDefecto(
    int storeId,
    bool value,
  ) async {
    await updateStoreConfig(storeId, guardarImpresoraPorDefecto: value);
  }

  /// Obtiene la lista de tickets a imprimir
  static Future<List<String>> getTicketsAImprimir(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      final raw = config['tickets_a_imprimir'];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return ['cliente', 'almacen'];
    } catch (e) {
      print('❌ Error al obtener tickets_a_imprimir: $e');
      return ['cliente', 'almacen'];
    }
  }

  /// Actualiza tickets_a_imprimir
  static Future<void> updateTicketsAImprimir(
    int storeId,
    List<String> value,
  ) async {
    await updateStoreConfig(storeId, ticketsAImprimir: value);
  }

  /// Obtiene el mapa de copias por ticket
  static Future<Map<String, int>> getCopiasPorTicket(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      final raw = config['copias_por_ticket'];
      if (raw is Map) {
        return raw.map(
          (key, value) => MapEntry(key.toString(), (value as num).toInt()),
        );
      }
      return {'cliente': 1, 'almacen': 1};
    } catch (e) {
      print('❌ Error al obtener copias_por_ticket: $e');
      return {'cliente': 1, 'almacen': 1};
    }
  }

  /// Actualiza copias_por_ticket
  static Future<void> updateCopiasPorTicket(
    int storeId,
    Map<String, int> value,
  ) async {
    await updateStoreConfig(storeId, copiasPorTicket: value);
  }

  /// Obtiene el valor de autocompletar_cantidad_real_conteo
  static Future<bool> getAutocompletarCantidadRealConteo(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['autocompletar_cantidad_real_conteo'] ?? false;
    } catch (e) {
      print('❌ Error al obtener autocompletar_cantidad_real_conteo: $e');
      return false;
    }
  }

  /// Actualiza autocompletar_cantidad_real_conteo
  static Future<void> updateAutocompletarCantidadRealConteo(
    int storeId,
    bool value,
  ) async {
    await updateStoreConfig(
      storeId,
      autocompletarCantidadRealConteo: value,
    );
  }

  // ==================== RESTAURANTE / COCINA ====================

  static Future<bool> getModoRestaurante(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['modo_restaurante'] ?? false;
    } catch (e) {
      print('❌ Error al obtener modo_restaurante: $e');
      return false;
    }
  }

  /// Actualiza modo_restaurante.
  ///
  /// Al DESACTIVAR se apaga también `cocina_activa`: el módulo de cocina vive
  /// de las cuentas de mesa, así que dejarlo encendido sin mesas produciría
  /// comandas que nadie puede abrir.
  static Future<void> updateModoRestaurante(int storeId, bool value) async {
    await updateStoreConfig(
      storeId,
      modoRestaurante: value,
      cocinaActiva: value ? null : false,
    );
  }

  static Future<bool> getCocinaActiva(int storeId) async {
    try {
      final config = await getStoreConfig(storeId);
      return config['cocina_activa'] ?? false;
    } catch (e) {
      print('❌ Error al obtener cocina_activa: $e');
      return false;
    }
  }

  /// Actualiza cocina_activa.
  ///
  /// Al ACTIVAR se enciende también `modo_restaurante` si faltaba: sin mesas no
  /// hay de dónde salgan las comandas.
  static Future<void> updateCocinaActiva(int storeId, bool value) async {
    await updateStoreConfig(
      storeId,
      cocinaActiva: value,
      modoRestaurante: value ? true : null,
    );
  }
}
