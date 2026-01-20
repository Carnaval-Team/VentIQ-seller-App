import 'dart:convert';

import 'package:http/http.dart' as http;

class WhapiService {
  static const String _baseUrl = 'https://gate.whapi.cloud';
  static const String _apiPrefix = '/';
  static const String _token = 'YPte4ulIx1BMjjlYP3msg3XkfKVvDcBv';

  final http.Client _client;

  WhapiService({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> get _headers => {
    'accept': 'application/json',
    'content-type': 'application/json',
    'authorization': 'Bearer $_token',
  };

  Uri _buildUri(String path, {Map<String, String>? query}) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$_baseUrl$_apiPrefix$normalizedPath');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  Future<String> acceptGroupInvite(String inviteCode) async {
    final uri = _buildUri('/groups');
    final response = await _client.put(
      uri,
      headers: _headers,
      body: jsonEncode({'invite_code': inviteCode}),
    );
    final data = _decodeBody(response);
    if (response.statusCode == 200) {
      final groupId = data['group_id']?.toString();
      if (groupId == null || groupId.isEmpty) {
        throw Exception('Respuesta sin group_id');
      }
      return groupId;
    }

    throw Exception(
      _extractErrorMessage(data) ??
          'Error registrando grupo (${response.statusCode})',
    );
  }

  Future<List<Map<String, dynamic>>> getGroups({
    int count = 100,
    int offset = 0,
  }) async {
    final uri = _buildUri(
      '/groups',
      query: {'count': '$count', 'offset': '$offset'},
    );
    final response = await _client.get(uri, headers: _headers);
    final data = _decodeBody(response);
    if (response.statusCode == 200) {
      final groups = data['groups'];
      if (groups is List) {
        return groups
            .whereType<Map>()
            .map((g) => Map<String, dynamic>.from(g))
            .toList();
      }
      return [];
    }

    throw Exception(
      _extractErrorMessage(data) ??
          'Error obteniendo grupos (${response.statusCode})',
    );
  }

  Future<void> sendImageMessage({
    required String to,
    required String caption,
    required String mediaUrl,
  }) async {
    final uri = _buildUri('/messages/image');
    final response = await _client.post(
      uri,
      headers: _headers,
      body: jsonEncode({'to': to, 'caption': caption, 'media': mediaUrl}),
    );
    final data = _decodeBody(response);
    if (response.statusCode == 200 && data['sent'] == true) return;

    throw Exception(
      _extractErrorMessage(data) ??
          'No se pudo enviar la imagen (${response.statusCode})',
    );
  }

  Future<void> sendTextMessage({
    required String to,
    required String body,
  }) async {
    final uri = _buildUri('/messages/text');
    final response = await _client.post(
      uri,
      headers: _headers,
      body: jsonEncode({'to': to, 'body': body}),
    );
    final data = _decodeBody(response);
    if (response.statusCode == 200) return;

    throw Exception(
      _extractErrorMessage(data) ??
          'No se pudo enviar el mensaje (${response.statusCode})',
    );
  }

  void dispose() => _client.close();

  Map<String, dynamic> _decodeBody(http.Response response) {
    if (response.body.isEmpty) return {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  String? _extractErrorMessage(dynamic data) {
    if (data is Map) {
      final error = data['error'];
      if (error is Map) {
        final message = error['message'];
        if (message != null && message.toString().isNotEmpty) {
          return message.toString();
        }
      }
      final message = data['message'];
      if (message != null && message.toString().isNotEmpty) {
        return message.toString();
      }
    }
    return null;
  }
}
