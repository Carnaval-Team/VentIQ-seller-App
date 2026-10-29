import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_admin_app/models/wapi_agotado_config.dart';
import 'package:ventiq_admin_app/models/wapi_agotado_log.dart';
import 'package:ventiq_admin_app/models/wapi_programacion.dart';
import 'package:ventiq_admin_app/services/wapi_notification_service.dart';
import 'package:ventiq_admin_app/utils/wapi_errores.dart';

/// Pruebas de la lógica pura de la feature "solo disponibles" + avisos de
/// agotado: parseo/escritura de modelos y el aviso de migración pendiente.
/// Nada aquí toca Supabase ni Flutter widgets.
void main() {
  group('WapiProgramacion.soloDisponibles', () {
    test('lee la columna cuando viene en la fila', () {
      final p = WapiProgramacion.fromJson({
        'id': 7,
        'id_tienda': 1,
        'id_sesion': 2,
        'hora_envio': '09:30:00',
        'activa': true,
        'solo_disponibles': true,
      });
      expect(p.soloDisponibles, isTrue);
      expect(p.horaEnvio, const TimeOfDay(hour: 9, minute: 30));
    });

    test('por defecto false si el backend todavía no tiene la columna', () {
      final p = WapiProgramacion.fromJson({
        'id': 7,
        'id_tienda': 1,
        'id_sesion': 2,
        'hora_envio': '09:30:00',
      });
      expect(p.soloDisponibles, isFalse);
    });

    test('toDbMap escribe solo_disponibles y la hora HH:mm:ss', () {
      final p = WapiProgramacion(
        id: 7,
        idTienda: 1,
        idSesion: 2,
        nombre: 'Difusión diaria',
        horaEnvio: const TimeOfDay(hour: 8, minute: 5),
        timezone: 'America/Havana',
        activa: true,
        delayMinSeconds: 5,
        delayMaxSeconds: 12,
        soloDisponibles: true,
      );
      final map = p.toDbMap();
      expect(map['solo_disponibles'], isTrue);
      expect(map['hora_envio'], '08:05:00');
      expect(map['id_tienda'], 1);
      // `nombre` no se persiste desde el cliente: no debe pisar el del backend.
      expect(map.containsKey('nombre'), isFalse);
    });

    test(
      'toDbMap manda solo_disponibles=false (si no, no se podría apagar)',
      () {
        final p = WapiProgramacion(
          id: 7,
          idTienda: 1,
          idSesion: 2,
          nombre: 'Difusión diaria',
          horaEnvio: const TimeOfDay(hour: 8, minute: 5),
          timezone: 'America/Havana',
          activa: true,
          delayMinSeconds: 5,
          delayMaxSeconds: 12,
        );
        final map = p.toDbMap();
        expect(map.containsKey('solo_disponibles'), isTrue);
        expect(map['solo_disponibles'], isFalse);
      },
    );
  });

  group('WapiAgotadoPlantilla', () {
    test('reemplaza los placeholders conocidos', () {
      final texto = WapiAgotadoPlantilla.render(
        'Hola: {producto} a {precio} ({tienda})',
        const {
          '{producto}': 'Café',
          '{precio}': '10.00',
          '{tienda}': 'Mi tienda',
        },
      );
      expect(texto, 'Hola: Café a 10.00 (Mi tienda)');
    });

    test('deja intactos los tokens desconocidos o sin valor', () {
      final texto = WapiAgotadoPlantilla.render(
        '{producto} / {produto} / {stock}',
        const {'{producto}': 'Café'},
      );
      expect(texto, 'Café / {produto} / {stock}');
    });

    test(
      'tokensDesconocidos detecta typos sin duplicar ni ordenar al azar',
      () {
        expect(
          WapiAgotadoPlantilla.tokensDesconocidos(
            '{producto} {produto} {precio2} {produto}',
          ),
          ['{precio2}', '{produto}'],
        );
        expect(
          WapiAgotadoPlantilla.tokensDesconocidos('{producto} {stock}'),
          isEmpty,
        );
      },
    );

    test('la plantilla por defecto sólo usa placeholders conocidos', () {
      expect(
        WapiAgotadoPlantilla.tokensDesconocidos(
          WapiAgotadoConfig.plantillaDefault,
        ),
        isEmpty,
      );
    });
  });

  group('WapiAgotadoConfig', () {
    test('fromJson tolera columnas ausentes y aplica defaults', () {
      final c = WapiAgotadoConfig.fromJson(
        {'id': 3, 'id_tienda': 9, 'activo': true},
        destinatarioIds: const [4, 5],
      );
      expect(c.id, 3);
      expect(c.activo, isTrue);
      expect(c.plantilla, WapiAgotadoConfig.plantillaDefault);
      expect(c.delayMinSeconds, 5);
      expect(c.cooldownMinutos, 60);
      expect(c.destinatarioIds, [4, 5]);
      expect(c.operativa, isTrue);
    });

    test('sin destinatarios no está operativa aunque esté activa', () {
      final c = WapiAgotadoConfig.fromJson({
        'id': 3,
        'id_tienda': 9,
        'activo': true,
      });
      expect(c.tieneDestinatarios, isFalse);
      expect(c.operativa, isFalse);
    });

    test('toDbMap incluye sólo las columnas del contrato', () {
      const c = WapiAgotadoConfig(
        id: 3,
        idTienda: 9,
        idSesion: 2,
        activo: true,
        plantilla: 'hola {producto}',
        delayMinSeconds: 6,
        delayMaxSeconds: 11,
        cooldownMinutos: 30,
      );
      final map = c.toDbMap();
      expect(map['id_tienda'], 9);
      expect(map['id_sesion'], 2);
      expect(map['activo'], isTrue);
      expect(map['plantilla'], 'hola {producto}');
      expect(map['delay_min_seconds'], 6);
      expect(map['delay_max_seconds'], 11);
      expect(map['cooldown_minutos'], 30);
      expect(map.containsKey('id'), isFalse);
    });

    test('copyWith conserva la tienda y cambia sólo lo pedido', () {
      const c = WapiAgotadoConfig(
        id: 3,
        idTienda: 9,
        plantilla: 'x',
        activo: false,
      );
      final pausada = c.copyWith(activo: true);
      expect(pausada.idTienda, 9);
      expect(pausada.activo, isTrue);
      expect(pausada.plantilla, 'x');
    });
  });

  group('WapiAgotadoLog', () {
    test('parsea estado y error del historial', () {
      final log = WapiAgotadoLog.fromJson({
        'id': 1,
        'id_tienda': 9,
        'id_producto': 44,
        'chat_id': '1203@g.us',
        'estado': 'fallido',
        'error_code': 'HTTP_500',
        'error_message': 'boom',
        'created_at': '2026-01-02T03:04:05Z',
      });
      expect(log.estado, WapiAgotadoEstado.fallido);
      expect(log.estado.label, 'Fallido');
      expect(log.idProducto, 44);
      expect(log.createdAt, isNotNull);
    });

    test('estado desconocido cae a pendiente', () {
      final log = WapiAgotadoLog.fromJson({'id': 1, 'id_tienda': 9});
      expect(log.estado, WapiAgotadoEstado.pendiente);
    });

    test('parsea "omitido" (el backend lo usa si no pudo ni intentarlo)', () {
      final log = WapiAgotadoLog.fromJson({
        'id': 2,
        'id_tienda': 9,
        'estado': 'omitido',
        'error_code': 'NO_VAULT',
      });
      expect(log.estado, WapiAgotadoEstado.omitido);
      expect(log.estado.label, 'Omitido');
      expect(log.estado.apiValue, 'omitido');
    });
  });

  group('esEsquemaFaltante', () {
    test('detecta 42P01 (tabla inexistente)', () {
      final e = PostgrestException(
        message: 'relation "app_wapi_agotado_config" does not exist',
        code: '42P01',
      );
      expect(esEsquemaFaltante(e), isTrue);
    });

    test('detecta 42703 de la columna concreta', () {
      final e = PostgrestException(
        message: 'column "solo_disponibles" does not exist',
        code: '42703',
      );
      expect(esEsquemaFaltante(e, columna: 'solo_disponibles'), isTrue);
      expect(esEsquemaFaltante(e, columna: 'otra_columna'), isFalse);
    });

    test(
      'detecta PGRST204 (columna ausente del schema cache de PostgREST)',
      () {
        // Es el error que devuelve Supabase cuando la app se actualiza antes de
        // aplicar la migración de `solo_disponibles`.
        final e = PostgrestException(
          message:
              "Could not find the 'solo_disponibles' column of "
              "'app_wapi_programacion' in the schema cache",
          code: 'PGRST204',
        );
        expect(esEsquemaFaltante(e, columna: 'solo_disponibles'), isTrue);
        expect(esEsquemaFaltante(e, columna: 'otra_columna'), isFalse);
      },
    );

    test('detecta PGRST205 (tabla ausente del schema cache de PostgREST)', () {
      final e = PostgrestException(
        message:
            "Could not find the table 'public.app_wapi_agotado_config' "
            "in the schema cache",
        code: 'PGRST205',
      );
      expect(esEsquemaFaltante(e), isTrue);
    });

    test('no confunde un error normal con una migración pendiente', () {
      final e = PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
      );
      expect(esEsquemaFaltante(e), isFalse);
      expect(esEsquemaFaltante(Exception('timeout de red')), isFalse);
    });
  });

  group('diagnóstico de los errores nuevos del filtro por stock', () {
    test('SKIPPED_AGOTADO se explica y no invita a reintentar', () {
      final d = diagnosticarError(
        codigo: 'SKIPPED_AGOTADO',
        mensaje: 'Producto sin stock: no se envía con solo_disponibles',
      );
      expect(d.tipo, WapiDiagTipo.definitivo);
      expect(d.reintentable, isFalse);
      expect(d.queHacer, contains('solo disponibles'));
    });

    test('PRODUCTO_NO_ENCONTRADO no se confunde con un fallo transitorio', () {
      final d = diagnosticarError(
        codigo: 'PRODUCTO_NO_ENCONTRADO',
        mensaje: 'No se pudo resolver el producto 44',
      );
      expect(d.tipo, WapiDiagTipo.definitivo);
      expect(d.reintentable, isFalse);
      expect(d.titulo, contains('producto'));
    });
  });
}
