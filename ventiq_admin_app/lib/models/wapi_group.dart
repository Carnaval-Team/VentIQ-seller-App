/// Grupo WhatsApp listado desde la API WAPI.
class WapiGroup {
  final String chatId; // ej. xxx-yyy@g.us
  final String name;
  final String? description;
  final int? participantsCount;

  WapiGroup({
    required this.chatId,
    required this.name,
    this.description,
    this.participantsCount,
  });

  factory WapiGroup.fromJson(Map<String, dynamic> j) {
    return WapiGroup(
      chatId: (j['chatId'] ?? j['id'] ?? '') as String,
      name: (j['name'] ?? '') as String,
      description: j['description'] as String?,
      participantsCount: (j['participantsCount'] as num?)?.toInt(),
    );
  }
}
