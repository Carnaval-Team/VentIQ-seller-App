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
      type: json['type'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
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
      version: json['version'] ?? '',
      date: json['date'] ?? '',
      title: json['title'] ?? '',
      changes: (json['changes'] as List<dynamic>?)
          ?.map((change) => ChangelogEntry.fromJson(change))
          .toList() ?? [],
    );
  }
}

class ChangelogData {
  final List<Changelog> changelogs;

  ChangelogData({required this.changelogs});

  factory ChangelogData.fromJson(Map<String, dynamic> json) {
    return ChangelogData(
      changelogs: (json['changelogs'] as List<dynamic>?)
          ?.map((changelog) => Changelog.fromJson(changelog))
          .toList() ?? [],
    );
  }
}
