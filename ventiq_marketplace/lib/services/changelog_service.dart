import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/changelog.dart';

class ChangelogService {
  static final ChangelogService _instance = ChangelogService._internal();
  factory ChangelogService() => _instance;
  ChangelogService._internal();

  Future<ChangelogData> loadChangelogs() async {
    try {
      final jsonString = await rootBundle.loadString('assets/changelog.json');
      final jsonData = json.decode(jsonString);
      return ChangelogData.fromJson(Map<String, dynamic>.from(jsonData));
    } catch (_) {
      return ChangelogData(changelogs: []);
    }
  }

  Future<Changelog?> getLatestChangelog() async {
    final data = await loadChangelogs();
    if (data.changelogs.isEmpty) return null;
    return data.changelogs.first;
  }
}
