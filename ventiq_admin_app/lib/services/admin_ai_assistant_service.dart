import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config/gemini_config.dart';
import 'permissions_service.dart';

/// Response model for admin AI assistant
class AdminAiAssistantResponse {
  final String message;
  final String? suggestedRoute;
  final bool isNavigable;

  const AdminAiAssistantResponse({
    required this.message,
    this.suggestedRoute,
    this.isNavigable = false,
  });

  factory AdminAiAssistantResponse.fromJson(Map<String, dynamic> json) {
    return AdminAiAssistantResponse(
      message: (json['message'] ?? '').toString(),
      suggestedRoute: json['suggested_route']?.toString(),
      isNavigable: json['is_navigable'] == true,
    );
  }
}

/// Service for the admin AI assistant that helps users navigate the app
class AdminAiAssistantService {
  static final AdminAiAssistantService _instance =
      AdminAiAssistantService._internal();
  factory AdminAiAssistantService() => _instance;
  AdminAiAssistantService._internal();

  final PermissionsService _permissionsService = PermissionsService();

  // Cache for knowledge base
  Map<String, dynamic>? _cachedKnowledge;
  DateTime? _lastKnowledgeLoad;
  static const Duration _knowledgeCacheTtl = Duration(hours: 1);

  /// Load knowledge base from assets
  Future<Map<String, dynamic>> loadKnowledge({bool forceRefresh = false}) async {
    // Return cached knowledge if still valid
    if (!forceRefresh &&
        _cachedKnowledge != null &&
        _lastKnowledgeLoad != null) {
      final elapsed = DateTime.now().difference(_lastKnowledgeLoad!);
      if (elapsed < _knowledgeCacheTtl) {
        return _cachedKnowledge!;
      }
    }

    try {
      final jsonString =
          await rootBundle.loadString('assets/ai_assistant_knowledge.json');
      final knowledge = jsonDecode(jsonString) as Map<String, dynamic>;

      _cachedKnowledge = knowledge;
      _lastKnowledgeLoad = DateTime.now();

      return knowledge;
    } catch (e) {
      print('Error loading AI assistant knowledge: $e');
      // Return empty knowledge on error
      return {
        'version': '1.0.0',
        'welcome_messages': {},
        'modules': {},
        'faqs': [],
        'glossary': {},
        'role_descriptions': {},
        'suggested_questions': {},
      };
    }
  }

  /// Get role name string from UserRole enum
  String _getRoleKey(UserRole role) {
    switch (role) {
      case UserRole.gerente:
        return 'gerente';
      case UserRole.supervisor:
        return 'supervisor';
      case UserRole.auditor:
        return 'auditor';
      case UserRole.almacenero:
        return 'almacenero';
      case UserRole.vendedor:
        return 'vendedor';
      case UserRole.none:
        return 'gerente'; // Default to gerente for generic help
    }
  }

  /// Get welcome message based on user role
  Future<String> getWelcomeMessage() async {
    final knowledge = await loadKnowledge();
    final userRole = await _permissionsService.getUserRole();
    final roleKey = _getRoleKey(userRole);

    final welcomeMessages =
        knowledge['welcome_messages'] as Map<String, dynamic>? ?? {};

    return welcomeMessages[roleKey]?.toString() ??
        'Hola! Soy tu asistente de VentIQ Admin. En que puedo ayudarte hoy?';
  }

  /// Get suggested questions based on user role
  Future<List<String>> getSuggestedQuestions() async {
    final knowledge = await loadKnowledge();
    final userRole = await _permissionsService.getUserRole();
    final roleKey = _getRoleKey(userRole);

    final suggestedQuestions =
        knowledge['suggested_questions'] as Map<String, dynamic>? ?? {};

    final questions = suggestedQuestions[roleKey];
    if (questions is List) {
      return questions.map((q) => q.toString()).toList();
    }

    // Default questions if none configured
    return [
      'Como creo un producto?',
      'Como veo el inventario?',
      'Como funciona este sistema?',
      'Que puedo hacer aqui?',
    ];
  }

  /// Ask a question to the AI assistant
  Future<AdminAiAssistantResponse> askQuestion({
    required String question,
    required List<Map<String, String>> conversationHistory,
  }) async {
    final validationError = _validateQuestion(question);
    if (validationError != null) {
      throw Exception(validationError);
    }

    final config = await GeminiConfig.load();
    if (!config.hasApiKey) {
      throw Exception(
        'El asistente de IA no esta configurado. Contacta al administrador.',
      );
    }

    final knowledge = await loadKnowledge();
    final userRole = await _permissionsService.getUserRole();
    final roleKey = _getRoleKey(userRole);
    final roleName = _permissionsService.getRoleName(userRole);

    final prompt = _buildPrompt(
      question: question,
      conversationHistory: conversationHistory,
      knowledge: knowledge,
      roleKey: roleKey,
      roleName: roleName,
    );

    final requestBody = config.applyAuthToBody(
      config.isMuleRouter
          ? {
              'model': config.model,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'You are a helpful assistant for VentIQ Admin. Only answer in Spanish.',
                },
                {'role': 'user', 'content': prompt},
              ],
            }
          : {
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {
                'temperature': 0.3,
                'maxOutputTokens': 1200,
                'response_mime_type': 'application/json',
              },
            },
    );

    final uri = config.buildUri(endpoint: 'generateContent');
    final headers = config.buildHeaders();

    final response = await http
        .post(uri, headers: headers, body: jsonEncode(requestBody))
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(
        'Error al contactar el asistente (${response.statusCode})',
      );
    }

    final data = jsonDecode(response.body);
    final text = _extractResponseText(data);
    final jsonText = _extractJson(text);
    final parsed = jsonDecode(jsonText);

    if (parsed is! Map<String, dynamic>) {
      throw Exception('Respuesta del asistente invalida.');
    }

    return AdminAiAssistantResponse.fromJson(parsed);
  }

  String? _validateQuestion(String question) {
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      return 'Escribe una pregunta para que pueda ayudarte.';
    }
    if (trimmed.length < 3) {
      return 'La pregunta es muy corta. Se mas especifico.';
    }
    return null;
  }

  String _buildPrompt({
    required String question,
    required List<Map<String, String>> conversationHistory,
    required Map<String, dynamic> knowledge,
    required String roleKey,
    required String roleName,
  }) {
    // Convert knowledge to a more compact format for the prompt
    final modulesInfo = _summarizeModules(knowledge);
    final faqsInfo = _summarizeFaqs(knowledge, roleKey);
    final glossaryInfo = _summarizeGlossary(knowledge);
    final roleDescription = _getRoleDescription(knowledge, roleKey);

    final conversationJson =
        const JsonEncoder.withIndent('  ').convert(conversationHistory);

    return '''Eres el asistente de ayuda de VentIQ Admin, una aplicacion de gestion de inventarios y ventas.
Tu trabajo es ayudar al usuario a entender como usar la aplicacion y guiarlo paso a paso.

REGLAS IMPORTANTES:
1. Responde SIEMPRE en espanol de forma clara y amigable
2. Si el usuario pregunta como hacer algo, da pasos claros y concretos
3. Si hay una pantalla relacionada, indica la ruta para que el usuario pueda navegar
4. Adapta tu respuesta al rol del usuario (solo menciona funciones a las que tiene acceso)
5. Si no sabes algo o la pregunta no es sobre la app, indica que no puedes ayudar con eso
6. Se conciso pero completo

INFORMACION DEL USUARIO:
- Rol actual: $roleName
- Descripcion del rol: $roleDescription

MODULOS DISPONIBLES EN LA APP:
$modulesInfo

PREGUNTAS FRECUENTES:
$faqsInfo

GLOSARIO DE TERMINOS:
$glossaryInfo

HISTORIAL DE CONVERSACION:
$conversationJson

PREGUNTA DEL USUARIO:
"$question"

RESPONDE EN FORMATO JSON (sin markdown, sin texto adicional):
{
  "message": "tu respuesta clara y util en espanol",
  "suggested_route": "/ruta-si-aplica" o null,
  "is_navigable": true o false
}

Si la respuesta involucra ir a una pantalla especifica, incluye suggested_route y is_navigable=true.
Si es solo una explicacion general, suggested_route=null y is_navigable=false.
''';
  }

  String _summarizeModules(Map<String, dynamic> knowledge) {
    final modules = knowledge['modules'] as Map<String, dynamic>? ?? {};
    final buffer = StringBuffer();

    for (final entry in modules.entries) {
      final module = entry.value as Map<String, dynamic>;
      final name = module['name'] ?? entry.key;
      final description = module['description'] ?? '';
      final routes = module['routes'] as Map<String, dynamic>? ?? {};
      final features = module['features'] as List? ?? [];

      buffer.writeln('- $name: $description');
      buffer.writeln('  Rutas: ${routes.values.join(", ")}');

      if (features.isNotEmpty) {
        buffer.write('  Funciones: ');
        final featureNames =
            features.map((f) => (f as Map)['name'] ?? '').join(', ');
        buffer.writeln(featureNames);
      }
    }

    return buffer.toString();
  }

  String _summarizeFaqs(Map<String, dynamic> knowledge, String roleKey) {
    final faqs = knowledge['faqs'] as List? ?? [];
    final buffer = StringBuffer();

    for (final faq in faqs) {
      if (faq is Map<String, dynamic>) {
        final roles = faq['roles'] as List? ?? [];
        // Include FAQ if it applies to this role or has no role restriction
        if (roles.isEmpty || roles.contains(roleKey)) {
          buffer.writeln('Q: ${faq['question']}');
          buffer.writeln('A: ${faq['answer']}');
          if (faq['route'] != null) {
            buffer.writeln('Ruta: ${faq['route']}');
          }
          buffer.writeln();
        }
      }
    }

    return buffer.toString();
  }

  String _summarizeGlossary(Map<String, dynamic> knowledge) {
    final glossary = knowledge['glossary'] as Map<String, dynamic>? ?? {};
    final buffer = StringBuffer();

    for (final entry in glossary.entries) {
      final item = entry.value as Map<String, dynamic>;
      final term = item['term'] ?? entry.key;
      final definition = item['definition'] ?? '';
      buffer.writeln('- $term: $definition');
    }

    return buffer.toString();
  }

  String _getRoleDescription(Map<String, dynamic> knowledge, String roleKey) {
    final roleDescriptions =
        knowledge['role_descriptions'] as Map<String, dynamic>? ?? {};
    final roleInfo = roleDescriptions[roleKey] as Map<String, dynamic>?;

    if (roleInfo != null) {
      return roleInfo['description']?.toString() ?? 'Usuario del sistema';
    }

    return 'Usuario del sistema';
  }

  String _extractResponseText(dynamic data) {
    if (data is Map<String, dynamic>) {
      // OpenAI/MuleRouter format
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final message = choices.first['message'];
        if (message is Map<String, dynamic>) {
          final content = message['content'];
          if (content != null) {
            return content.toString();
          }
        }
      }

      // Gemini format
      final candidates = data['candidates'];
      if (candidates is List && candidates.isNotEmpty) {
        final content = candidates.first['content'];
        if (content is Map<String, dynamic>) {
          final parts = content['parts'];
          if (parts is List && parts.isNotEmpty) {
            final text = parts.first['text'];
            if (text != null) {
              return text.toString();
            }
          }
        }
      }
    }

    throw Exception('Respuesta del asistente vacia o invalida.');
  }

  String _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');

    if (start == -1 || end == -1 || end <= start) {
      throw Exception('El asistente no devolvio una respuesta valida.');
    }

    return text.substring(start, end + 1);
  }

  /// Clear the knowledge cache
  void clearCache() {
    _cachedKnowledge = null;
    _lastKnowledgeLoad = null;
  }
}
