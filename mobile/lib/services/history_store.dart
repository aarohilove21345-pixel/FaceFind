import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scan_result.dart';

class HistoryEntry {
  final String id;
  final DateTime time;
  final List<MatchResult> matches;

  const HistoryEntry({
    required this.id,
    required this.time,
    required this.matches,
  });
}

/// Keeps the last scans on the phone only. Nothing is sent anywhere.
class HistoryStore {
  static const String _key = 'scan_history_v1';
  static const int _max = 20;

  /// Bumped whenever the saved history changes, so screens can refresh.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<List<HistoryEntry>> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_key);
      if (raw == null) return [];
      final dynamic list = jsonDecode(raw);
      if (list is! List) return [];
      final List<HistoryEntry> out = [];
      for (final dynamic e in list) {
        if (e is! Map<String, dynamic>) continue;
        final List<MatchResult> matches = [];
        final dynamic rawMatches = e['matches'];
        if (rawMatches is List) {
          for (final dynamic m in rawMatches) {
            if (m is Map<String, dynamic>) {
              matches.add(MatchResult(
                platform: m['platform'] as String?,
                title: m['title'] as String?,
                profileUrl: m['url'] as String?,
                previewUrl: m['preview'] as String?,
              ));
            }
          }
        }
        out.add(HistoryEntry(
          id: '${e['id']}',
          time: DateTime.tryParse('${e['time']}') ?? DateTime.now(),
          matches: matches,
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(ScanState scan) async {
    try {
      final List<HistoryEntry> entries = await load();
      entries.insert(
        0,
        HistoryEntry(id: scan.id, time: DateTime.now(), matches: scan.matches),
      );
      await _save(entries.take(_max).toList());
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      changes.value++;
    } catch (_) {}
  }

  static Future<void> _save(List<HistoryEntry> entries) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> data = entries
        .map((e) => <String, dynamic>{
              'id': e.id,
              'time': e.time.toIso8601String(),
              'matches': e.matches
                  .map((m) => <String, dynamic>{
                        'platform': m.platform,
                        'title': m.title,
                        'url': m.profileUrl,
                        'preview': m.previewUrl,
                      })
                  .toList(),
            })
        .toList();
    await prefs.setString(_key, jsonEncode(data));
    changes.value++;
  }
}
