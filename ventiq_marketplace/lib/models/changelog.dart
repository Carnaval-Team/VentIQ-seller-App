class ChangelogEntry {
  final String type;
  final String title;
  final String description;

  ChangelogEntry({
    required this.type,
    required this.title,
    required this.description,
  });

  factory ChangelogEntry.fromJson(Map<String, dynamic> json) {
    return ChangelogEntry(
      type: (json['type'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
    );
  }
}

class Changelog {
  final String version;
  final String date;
  final String title;
  final List<ChangelogEntry> changes;

  Changelog({
    required this.version,
    required this.date,
    required this.title,
    required this.changes,
  });

  factory Changelog.fromJson(Map<String, dynamic> json) {
    return Changelog(
      version: (json['version'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      changes:
          (json['changes'] as List<dynamic>?)
              ?.map(
                (e) => ChangelogEntry.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList() ??
          [],
    );
  }
}

class ChangelogData {
  final List<Changelog> changelogs;

  ChangelogData({required this.changelogs});

  factory ChangelogData.fromJson(Map<String, dynamic> json) {
    return ChangelogData(
      changelogs:
          (json['changelogs'] as List<dynamic>?)
              ?.map((e) => Changelog.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
    );
  }
}
