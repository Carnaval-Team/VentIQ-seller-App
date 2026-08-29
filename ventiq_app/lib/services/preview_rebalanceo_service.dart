import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_preferences_service.dart';

/// Resultado de la consulta previa al descuento: ¿alcanza el saldo de esta
/// presentación, o hay que abrir/armar empaques para servir la venta?
///
/// FASE 4.1 del plan. Espeja el JSON de `fn_preview_rebalanceo`
/// (`presentaciones_inventario/10_preview_rebalanceo.sql`), que es **solo
/// lectura**: no escribe, no reserva y no bloquea.
class PreviewRebalanceo {
  /// `'ninguna'` | `'abrir'` | `'empaquetar'` | `'imposible'`.
  final String estrategia;

  /// `false` → se puede agregar sin preguntar nada.
  final bool necesitaConversion;

  /// Texto ya armado por el SQL, con el plural correcto:
  /// «Faltan 1 Bulto. ¿Armar 1 Bulto con 10 Bolsas?».
  ///
  /// Viene del servidor a propósito: el plural de las presentaciones lo sabe
  /// `fn_plural_presentacion`, que maneja las irregularidades del nomenclador.
  /// Duplicar esa lógica en Dart es pedir que se desincronice.
  final String? mensajeUsuario;

  /// Cuánto se puede servir como máximo. Se muestra cuando `estrategia` es
  /// `'imposible'`.
  final double maximoConvertible;

  /// Saldo de la presentación pedida, sin contar conversiones.
  final double saldoPropio;

  /// Nombre de la presentación pedida ("Bulto").
  final String? presentacionNombre;

  const PreviewRebalanceo({
    required this.estrategia,
    required this.necesitaConversion,
    this.mensajeUsuario,
    this.maximoConvertible = 0,
    this.saldoPropio = 0,
    this.presentacionNombre,
  });

  bool get esImposible => estrategia == 'imposible';

  /// Hay que preguntar al cajero: la venta requiere romper o armar un empaque.
  bool get requierePreguntar =>
      necesitaConversion && !esImposible && (mensajeUsuario?.isNotEmpty ?? false);

  factory PreviewRebalanceo.fromJson(Map<String, dynamic> json) {
    return PreviewRebalanceo(
      estrategia: json['estrategia'] as String? ?? 'ninguna',
      necesitaConversion: json['necesita_conversion'] as bool? ?? false,
      mensajeUsuario: json['mensaje_usuario'] as String?,
      maximoConvertible:
          (json['maximo_convertible'] as num?)?.toDouble() ?? 0,
      saldoPropio: (json['saldo_propio'] as num?)?.toDouble() ?? 0,
      presentacionNombre: json['presentacion_nombre'] as String?,
    );
  }

  /// Resultado neutro: se usa cuando la consulta falla o no aplica, para que la
  /// venta siga su curso como antes de Fase 4.1.
  static const PreviewRebalanceo sinConversion = PreviewRebalanceo(
    estrategia: 'ninguna',
    necesitaConversion: false,
  );
}

/// Pregunta antes de abrir o armar un empaque en el TPV.
///
/// ── Por qué existe (decisión 14 del plan) ──────────────────────────────────
/// El rebalanceo automático vive en el SQL y funciona sin preguntar. Pero abrir
/// una caja es una decisión FÍSICA del cajero: rompe un empaque que ya no se
/// puede rearmar y cambia lo que el cliente siguiente ve en el estante. La
/// industria nunca lo hace en silencio — SAP pide HU02 Repack, NetSuite un
/// Assembly Unbuild, Odoo un Unpack explícito, y D365 directamente bloquea con
/// `Restrict to sales unit`.
///
/// ── Lo que NO es ───────────────────────────────────────────────────────────
/// **No es una reserva.** Entre la consulta y la venta otra caja puede mover el
/// saldo, así que la escritura real vuelve a calcular y puede fallar aunque esto
/// haya dicho que sí. El error de la venta se sigue manejando igual que siempre;
/// este diálogo no lo evita.
class PreviewRebalanceoService {
  PreviewRebalanceoService._();

  static final _supabase = Supabase.instance.client;

  /// Clave de la preferencia "no volver a preguntar", **por TPV**.
  ///
  /// Por TPV y no global a propósito: un mostrador de bar que fracciona todo el
  /// día la apaga, y el almacén de al lado la deja encendida. Son turnos y
  /// criterios distintos sobre el mismo producto.
  static String _claveNoPreguntar(int idTpv) =>
      'preview_rebalanceo_no_preguntar_tpv_$idTpv';

  /// Consulta si la cantidad pedida necesita abrir o armar empaques.
  ///
  /// Devuelve [PreviewRebalanceo.sinConversion] ante cualquier fallo (offline,
  /// RPC caída, datos incompletos): la venta no se bloquea porque la consulta no
  /// haya podido hacerse. El servidor sigue siendo la autoridad.
  static Future<PreviewRebalanceo> consultar({
    required int idProducto,
    required int idUbicacion,
    required int idPresentacion,
    required double cantidad,
    int? idVariante,
    int? idOpcionVariante,
  }) async {
    try {
      final res = await _supabase.rpc(
        'fn_preview_rebalanceo',
        params: {
          'p_id_producto': idProducto,
          'p_id_ubicacion': idUbicacion,
          'p_id_presentacion': idPresentacion,
          'p_cantidad': cantidad,
          'p_id_variante': idVariante,
          'p_id_opcion_variante': idOpcionVariante,
        },
      );

      if (res is Map) {
        return PreviewRebalanceo.fromJson(Map<String, dynamic>.from(res));
      }
      return PreviewRebalanceo.sinConversion;
    } catch (e) {
      // STABLE y solo lectura: si falla, no hay nada que revertir.
      debugPrint('⚠️ fn_preview_rebalanceo falló, se sigue sin preguntar: $e');
      return PreviewRebalanceo.sinConversion;
    }
  }

  static Future<bool> _noPreguntar() async {
    final idTpv = await UserPreferencesService().getIdTpv();
    if (idTpv == null) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_claveNoPreguntar(idTpv)) ?? false;
  }

  static Future<void> _guardarNoPreguntar() async {
    final idTpv = await UserPreferencesService().getIdTpv();
    // Sin TPV no se guarda nada: la preferencia es POR TPV y una clave global
    // silenciaria el aviso en todos los mostradores.
    if (idTpv == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_claveNoPreguntar(idTpv), true);
  }

  /// Consulta y, si hace falta, pregunta. `true` = seguir con la venta.
  ///
  /// Tres salidas:
  ///   · no necesita conversión → `true` sin molestar
  ///   · `estrategia = 'imposible'` → `false` y se avisa el máximo servible
  ///   · abrir/empaquetar → diálogo con el texto del SQL
  static Future<bool> confirmarSiHaceFalta(
    BuildContext context, {
    required int idProducto,
    required int idUbicacion,
    required int idPresentacion,
    required double cantidad,
    int? idVariante,
    int? idOpcionVariante,
  }) async {
    final preview = await consultar(
      idProducto: idProducto,
      idUbicacion: idUbicacion,
      idPresentacion: idPresentacion,
      cantidad: cantidad,
      idVariante: idVariante,
      idOpcionVariante: idOpcionVariante,
    );

    if (!context.mounted) return true;

    // No alcanza ni convirtiendo: esto NO se puede saltar con la preferencia.
    // "No volver a preguntar" silencia la confirmación de abrir empaques, no la
    // falta de stock.
    if (preview.esImposible) {
      await _avisarImposible(context, preview);
      return false;
    }

    if (!preview.requierePreguntar) return true;

    if (await _noPreguntar()) return true;
    if (!context.mounted) return true;

    return await _preguntar(context, preview) ?? false;
  }

  static Future<void> _avisarImposible(
    BuildContext context,
    PreviewRebalanceo preview,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text('No hay suficiente')),
          ],
        ),
        content: Text(
          preview.mensajeUsuario ??
              'No alcanza el stock disponible para esa cantidad.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  static Future<bool?> _preguntar(
    BuildContext context,
    PreviewRebalanceo preview,
  ) async {
    // El verbo del botón sigue la terminología acordada (decisión 15):
    // Unpack → Desempaquetar, Put in Pack → Poner en paquete.
    final abrir = preview.estrategia == 'abrir';
    final etiquetaAccion = abrir ? 'Desempaquetar' : 'Poner en paquete';
    var noPreguntarMas = false;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                abrir ? Icons.unfold_more : Icons.unfold_less,
                color: Colors.orange.shade800,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(abrir ? '¿Abrir un empaque?' : '¿Armar un empaque?'),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Texto del servidor: el plural correcto lo sabe el SQL.
              Text(preview.mensajeUsuario ?? ''),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(() => noPreguntarMas = !noPreguntarMas),
                child: Row(
                  children: [
                    Checkbox(
                      value: noPreguntarMas,
                      onChanged: (v) =>
                          setState(() => noPreguntarMas = v ?? false),
                    ),
                    const Expanded(
                      child: Text(
                        'No volver a preguntar en este TPV',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (noPreguntarMas) await _guardarNoPreguntar();
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              },
              child: Text(etiquetaAccion),
            ),
          ],
        ),
      ),
    );
  }
}
