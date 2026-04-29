import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/oferta_carga_model.dart';

class OfertaCargaService {
  final _supabase = Supabase.instance.client;

  // ──────────────────────────────────────────────────────────────────────────
  // CARRIER: gestión de ofertas propias
  // ──────────────────────────────────────────────────────────────────────────

  Future<OfertaCargaModel?> hacerOferta(OfertaCargaModel oferta) async {
    try {
      debugPrint(
          '[OfertaCargaService] Enviando oferta carga=${oferta.cargaId}');
      final data = await _supabase
          .schema('muevete')
          .from('ofertas_carga')
          .insert(oferta.toInsertJson())
          .select()
          .single();
      // Mark the carga as 'ofertada' if it was still 'publicada'
      await _supabase
          .schema('muevete')
          .from('cargas')
          .update({'estado': 'ofertada', 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', oferta.cargaId)
          .eq('estado', 'publicada');
      debugPrint('[OfertaCargaService] Oferta enviada id=${data['id']}');
      return OfertaCargaModel.fromJson(data);
    } catch (e) {
      debugPrint('[OfertaCargaService] Error hacerOferta: $e');
      rethrow;
    }
  }

  Future<void> retirarOferta(int ofertaId) async {
    try {
      await _supabase
          .schema('muevete')
          .from('ofertas_carga')
          .update({'estado': 'retirada', 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', ofertaId);
      debugPrint('[OfertaCargaService] Oferta $ofertaId retirada');
    } catch (e) {
      debugPrint('[OfertaCargaService] Error retirarOferta: $e');
      rethrow;
    }
  }

  /// Obtiene todas las ofertas enviadas por un carrier.
  Future<List<OfertaCargaModel>> getOfertasCarrier(int driverId) async {
    try {
      final data = await _supabase
          .schema('muevete')
          .from('ofertas_carga')
          .select()
          .eq('driver_id', driverId)
          .order('created_at', ascending: false);
      return (data as List)
          .map((e) => OfertaCargaModel.fromJson(e))
          .toList();
    } catch (e) {
      debugPrint('[OfertaCargaService] Error getOfertasCarrier: $e');
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SHIPPER: gestión de ofertas recibidas por carga
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<OfertaCargaModel>> getOfertasCarga(int cargaId) async {
    try {
      debugPrint('[OfertaCargaService] Cargando ofertas carga=$cargaId');
      final data = await _supabase
          .schema('muevete')
          .from('ofertas_carga')
          .select()
          .eq('carga_id', cargaId)
          .inFilter('estado', ['pendiente', 'aceptada'])
          .order('precio', ascending: true);
      return (data as List)
          .map((e) => OfertaCargaModel.fromJson(e))
          .toList();
    } catch (e) {
      debugPrint('[OfertaCargaService] Error getOfertasCarga: $e');
      rethrow;
    }
  }

  Future<void> aceptarOferta(int ofertaId, int cargaId, int driverId) async {
    try {
      debugPrint('[OfertaCargaService] Aceptando oferta $ofertaId');
      // 1. Mark this offer as accepted
      await _supabase
          .schema('muevete')
          .from('ofertas_carga')
          .update({'estado': 'aceptada', 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', ofertaId);
      // 2. Reject all other pending offers for this carga
      await _supabase
          .schema('muevete')
          .from('ofertas_carga')
          .update({'estado': 'rechazada', 'updated_at': DateTime.now().toIso8601String()})
          .eq('carga_id', cargaId)
          .eq('estado', 'pendiente')
          .neq('id', ofertaId);
      // 3. Assign carrier to carga
      await _supabase.schema('muevete').from('cargas').update({
        'carrier_driver_id': driverId,
        'oferta_aceptada_id': ofertaId,
        'estado': 'aceptada',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', cargaId);
      debugPrint('[OfertaCargaService] Oferta $ofertaId aceptada OK');
    } catch (e) {
      debugPrint('[OfertaCargaService] Error aceptarOferta: $e');
      rethrow;
    }
  }

  Future<void> rechazarOferta(int ofertaId) async {
    try {
      await _supabase
          .schema('muevete')
          .from('ofertas_carga')
          .update({'estado': 'rechazada', 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', ofertaId);
      debugPrint('[OfertaCargaService] Oferta $ofertaId rechazada');
    } catch (e) {
      debugPrint('[OfertaCargaService] Error rechazarOferta: $e');
      rethrow;
    }
  }

  /// Returns whether the current carrier already sent an offer for a carga.
  Future<OfertaCargaModel?> getOfertaExistente(
      int cargaId, int driverId) async {
    try {
      final data = await _supabase
          .schema('muevete')
          .from('ofertas_carga')
          .select()
          .eq('carga_id', cargaId)
          .eq('driver_id', driverId)
          .maybeSingle();
      if (data == null) return null;
      return OfertaCargaModel.fromJson(data);
    } catch (e) {
      debugPrint('[OfertaCargaService] Error getOfertaExistente: $e');
      return null;
    }
  }
}
