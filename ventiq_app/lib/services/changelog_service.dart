import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/changelog.dart';

class ChangelogService {
  static final ChangelogService _instance = ChangelogService._internal();
  factory ChangelogService() => _instance;
  ChangelogService._internal();

  Future<ChangelogData> loadChangelogs() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/changelog.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      return ChangelogData.fromJson(jsonData);
    } catch (e) {
      print('Error loading changelog: $e');
      return ChangelogData(changelogs: []);
    }
  }

  Future<Changelog?> getLatestChangelog() async {
    final changelogData = await loadChangelogs();
    if (changelogData.changelogs.isNotEmpty) {
      return changelogData.changelogs.first;
    }
    return null;
  }
}
