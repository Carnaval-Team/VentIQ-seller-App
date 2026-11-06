import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_app/services/session_refresh_service.dart';
import 'package:ventiq_app/services/server_time_service.dart';
import 'package:ventiq_app/services/reauthentication_service.dart';
import 'package:ventiq_app/services/user_preferences_service.dart';
import 'package:ventiq_app/utils/session_expiry.dart';

Map<String, dynamic> sessionData(DateTime expiresAt) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {
    'access_token':
        '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': 'test-user', 'exp': expiresAt.millisecondsSinceEpoch ~/ 1000})}.test-signature',
    'refresh_token': 'test-refresh-token',
    'token_type': 'bearer',
    'user': {
      'id': 'test-user',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'no acepta el resultado de refresh después de cerrar sesión manualmente',
    () async {
      final entered = Completer<void>();
      final response = Completer<http.Response>();
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/token')) {
            entered.complete();
            return response.future;
          }
          return http.Response('{}', 200, request: request);
        }),
      );
      await client.auth.setInitialSession(
        jsonEncode(sessionData(DateTime.now().add(const Duration(minutes: 1)))),
      );
      final service = SessionRefreshService.forTesting(client: client);
      service.start();
      final pending = service.ensureFreshSession();
      await entered.future;
      await client.auth.signOut();
      response.complete(
        http.Response(
          jsonEncode(sessionData(DateTime.now().add(const Duration(hours: 1)))),
          200,
        ),
      );
      expect(await pending, isFalse);
      expect(client.auth.currentSession, isNull);
      service.stop();
      await client.dispose();
    },
  );

  test('no conserva una sesión cuyo refresh token fue revocado', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (request) async => http.Response(
          '{"msg":"refresh token revoked","code":"refresh_token_not_found"}',
          400,
        ),
      ),
    );
    await client.auth.setInitialSession(
      jsonEncode(sessionData(DateTime.now().add(const Duration(minutes: 1)))),
    );
    final service = SessionRefreshService.forTesting(client: client);
    service.start();
    expect(
      await service.ensureFreshSession(allowReauthentication: false),
      isFalse,
    );
    expect(client.auth.currentSession, isNull);
    service.stop();
    await client.dispose();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerTimeService().syncFromHeaders({
      'date': HttpDate.format(DateTime.now()),
    });
  });

  tearDown(() async {
    await ServerTimeService().syncFromHeaders({
      'date': HttpDate.format(DateTime.now()),
    });
  });

  test(
    'la petición RPC no renueva un token vigente con reloj adelantado una hora',
    () async {
      final serverNow = DateTime.now().subtract(const Duration(hours: 1));
      await ServerTimeService().syncFromHeaders({
        'date': HttpDate.format(serverNow),
      });
      var refreshRequests = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/token')) refreshRequests++;
          return http.Response(
            '{}',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await client.auth.setInitialSession(
        jsonEncode(sessionData(serverNow.add(const Duration(minutes: 30)))),
      );
      final service = SessionRefreshService.forTesting(client: client);
      service.start();
      final token = client.auth.currentSession!.accessToken;
      expect(await service.ensureFreshSession(), isTrue);
      await client.rpc('test_detail');
      expect(refreshRequests, 0);
      expect(client.auth.currentSession!.accessToken, token);
      service.stop();
      await client.dispose();
    },
  );

  test(
    'un cierre manual durante un refresh no se revierte ante un 429',
    () async {
      final entered = Completer<void>();
      final response = Completer<http.Response>();
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/token')) {
            entered.complete();
            return response.future;
          }
          return http.Response('{}', 200);
        }),
      );
      await client.auth.setInitialSession(
        jsonEncode(sessionData(DateTime.now().add(const Duration(minutes: 1)))),
      );
      final service = SessionRefreshService.forTesting(client: client);
      service.start();
      final pending = service.ensureFreshSession();
      await entered.future;
      await client.auth.signOut();
      await Future<void>.delayed(Duration.zero);
      response.complete(http.Response('{"message":"rate limited"}', 429));
      expect(await pending, isFalse);
      expect(client.auth.currentSession, isNull);
      service.stop();
      await client.dispose();
    },
  );

  test('no recupera un JWT realmente vencido después de un 429', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (request) async => http.Response('{"message":"rate limited"}', 429),
      ),
    );
    await client.auth.setInitialSession(
      jsonEncode(
        sessionData(DateTime.now().subtract(const Duration(minutes: 1))),
      ),
    );
    final service = SessionRefreshService.forTesting(client: client);
    service.start();
    expect(await service.ensureFreshSession(), isFalse);
    expect(client.auth.currentSession, isNull);
    service.stop();
    await client.dispose();
  });

  test(
    'un error temporal de perfil conserva sesión y datos locales, con límite de dos horas',
    () async {
      var logins = 0;
      var logouts = 0;
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        anonKey: 'test-key',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
          localStorage: EmptyLocalStorage(),
        ),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/token')) {
            logins++;
            return http.Response(
              jsonEncode(
                sessionData(DateTime.now().add(const Duration(hours: 1))),
              ),
              200,
            );
          }
          if (request.url.path.endsWith('/logout')) logouts++;
          return http.Response(
            '{"message":"temporary profile failure","code":"503"}',
            503,
            request: request,
          );
        }),
      );
      final prefs = UserPreferencesService();
      await prefs.saveCredentials('test@example.com', 'test-password');
      await prefs.saveUserData(
        userId: 'test-user',
        email: 'test@example.com',
        accessToken: 'local-cache',
      );
      final service = ReauthenticationService();
      final first = service.reauthenticateUser();
      final second = service.reauthenticateUser();
      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(logins, 1);
      expect(logouts, 0);
      expect(Supabase.instance.client.auth.currentSession, isNotNull);
      expect(await prefs.getUserId(), 'test-user');
      expect(await service.reauthenticateUser(), isFalse);
      expect(logins, 1);
      await Supabase.instance.dispose();
    },
  );

  test('corrige solo el vencimiento local del SDK sin modificar el JWT', () {
    final deviceNow = DateTime.now().toUtc();
    final serverNow = deviceNow.subtract(const Duration(hours: 1));
    final expiry = serverNow.add(const Duration(minutes: 30));
    final session = Session.fromJson(sessionData(expiry))!;
    final token = session.accessToken;
    expect(session.isExpired, isTrue);

    alignSessionExpiryToDeviceClock(session, serverNow, deviceNow: deviceNow);

    expect(session.isExpired, isFalse);
    expect(session.accessToken, token);
    expect(
      sessionTokenExpiresAt(session)!.millisecondsSinceEpoch ~/ 1000,
      expiry.millisecondsSinceEpoch ~/ 1000,
    );
    alignSessionExpiryToDeviceClock(session, serverNow, deviceNow: deviceNow);
    expect(
      session.expiresAt,
      deviceNow.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000,
    );
  });

  test('no transforma un JWT realmente vencido en uno vigente', () {
    final deviceNow = DateTime.now().toUtc();
    final serverNow = deviceNow.subtract(const Duration(hours: 1));
    final session =
        Session.fromJson(
          sessionData(serverNow.subtract(const Duration(minutes: 5))),
        )!;
    alignSessionExpiryToDeviceClock(session, serverNow, deviceNow: deviceNow);
    expect(session.isExpired, isTrue);
  });

  test(
    'las llamadas concurrentes esperan el mismo resultado de refresh',
    () async {
      final entered = Completer<void>();
      final response = Completer<http.Response>();
      var requests = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) {
          requests++;
          entered.complete();
          return response.future;
        }),
      );
      await client.auth.setInitialSession(
        jsonEncode(sessionData(DateTime.now().add(const Duration(minutes: 1)))),
      );
      final service = SessionRefreshService.forTesting(client: client);
      final first = service.ensureFreshSession();
      await entered.future;
      var secondFinished = false;
      final second = service.ensureFreshSession().then((value) {
        secondFinished = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      expect(secondFinished, isFalse);
      response.complete(
        http.Response(
          jsonEncode({
            'message': 'rate limited',
            'code': 'over_request_rate_limit',
          }),
          429,
        ),
      );
      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(requests, 1);
      expect(client.auth.currentSession, isNotNull);
      service.stop();
      await client.dispose();
    },
  );

  test(
    'un 429 no dispara login con contraseña y conserva un JWT vigente',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'message': 'rate limited',
              'code': 'over_request_rate_limit',
            }),
            429,
          );
        }),
      );
      await client.auth.setInitialSession(
        jsonEncode(sessionData(DateTime.now().add(const Duration(minutes: 1)))),
      );
      final service = SessionRefreshService.forTesting(client: client);
      service.start();
      expect(await service.ensureFreshSession(), isFalse);
      expect(client.auth.currentSession, isNotNull);
      expect(requests, hasLength(1));
      expect(
        requests.single.url.queryParameters['grant_type'],
        'refresh_token',
      );
      expect(await service.ensureFreshSession(), isFalse);
      expect(requests, hasLength(1));
      service.stop();
      await client.dispose();
    },
  );
}
