import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_app/services/admin_inventory_service.dart';
import 'package:ventiq_app/services/offline_database_service.dart';

class _Queue extends Fake implements OfflineDatabaseService {
  final List<Map<String, dynamic>> pending;
  final synced = <String>[];
  final errors = <String, String>{};

  _Queue(this.pending);

  @override
  Future<List<Map<String, dynamic>>> getPendingAdminOps() async => pending;

  @override
  Future<void> markAdminOpSynced(String clientUuid) async {
    synced.add(clientUuid);
  }

  @override
  Future<void> markAdminOpError(String clientUuid, String error) async {
    errors[clientUuid] = error;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const uuid = '00000000-0000-4000-8000-000000000001';

  for (final flags in [false, true]) {
    final type =
        flags ? AdminOpType.vendorUpdateFlags : AdminOpType.vendorAssignTpv;
    final rpc =
        flags
            ? 'fn_admin_caja_vendor_flags_offline'
            : 'fn_admin_caja_vendor_assign_tpv_offline';

    for (final outcome in [
      'denied',
      'missing',
      'invalid',
      'wrong_vendor',
      'missing_idempotent',
      'empty',
      'success',
      'replay',
    ]) {
      test(
        '$type $outcome no degrada a escritura directa ni pierde UUID',
        () async {
          final payload = <String, dynamic>{
            'id_vendedor': 7,
            if (flags)
              'permitir_customizar_precio_venta': true
            else
              'id_tpv': 9,
          };
          final queue = _Queue([
            {
              'client_uuid': uuid,
              'op_type': type,
              'payload': {...payload},
            },
          ]);
          final requests = <http.Request>[];
          final client = SupabaseClient(
            'https://example.supabase.co',
            'test-key',
            httpClient: MockClient((request) async {
              requests.add(request);
              final isRpc = request.url.path.endsWith('/rpc/$rpc');
              final status =
                  !isRpc
                      ? 200
                      : outcome == 'denied'
                      ? 403
                      : outcome == 'missing'
                      ? 404
                      : 200;
              final Object? response =
                  !isRpc
                      ? <Object>[]
                      : outcome == 'denied'
                      ? {'code': '42501', 'message': 'Sin permiso'}
                      : outcome == 'missing'
                      ? {'code': 'PGRST202', 'message': 'RPC no disponible'}
                      : outcome == 'empty'
                      ? null
                      : {
                        'success': outcome != 'invalid',
                        if (outcome != 'missing_idempotent')
                          'idempotent': outcome == 'replay',
                        'id_vendedor': outcome == 'wrong_vendor' ? 8 : 7,
                      };
              return http.Response(
                jsonEncode(response),
                status,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }),
          );
          addTearDown(client.dispose);
          final service = AdminInventoryService.forTesting(
            client: client,
            database: queue,
          );
          final success = outcome == 'success' || outcome == 'replay';

          expect(await service.syncPendingOps(), success ? 1 : 0);
          expect(requests, hasLength(1));
          expect(requests.single.method, 'POST');
          expect(requests.single.url.path, '/rest/v1/rpc/$rpc');
          expect(jsonDecode(requests.single.body), {
            'p_client_uuid': uuid,
            'p_id_vendedor': 7,
            if (flags)
              'p_permitir_customizar_precio_venta': true
            else
              'p_id_tpv': 9,
          });
          expect(queue.synced, success ? [uuid] : isEmpty);
          expect(queue.errors.keys, success ? isEmpty : [uuid]);
          expect(queue.pending.single['client_uuid'], uuid);
          expect(queue.pending.single['payload'], payload);
        },
      );
    }
  }
}
