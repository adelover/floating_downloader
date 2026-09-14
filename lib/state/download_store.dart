import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/download_service.dart';

class DownloadItem {
  final String id;
  final String name;
  final String url;
  final String savedUri;
  final String date;
  final int bytes;
  final String mimeType;

  DownloadItem({
    required this.id,
    required this.name,
    required this.url,
    required this.savedUri,
    required this.date,
    required this.bytes,
    required this.mimeType,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'savedUri': savedUri,
        'date': date,
        'bytes': bytes,
        'mimeType': mimeType,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
        id: '${json['id'] ?? DateTime.now().microsecondsSinceEpoch}',
        name: '${json['name'] ?? 'فایل دانلود شده'}',
        url: '${json['url'] ?? ''}',
        savedUri: '${json['savedUri'] ?? ''}',
        date: '${json['date'] ?? ''}',
        bytes: int.tryParse('${json['bytes'] ?? 0}') ?? 0,
        mimeType: '${json['mimeType'] ?? 'application/octet-stream'}',
      );
}

class DownloadStore extends ChangeNotifier {
  DownloadStore._();
  static final instance = DownloadStore._();

  final List<DownloadItem> completed = [];
  final Map<String, double> active = {};
  final Map<String, String> activeNames = {};

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('downloads') ?? [];
    completed
      ..clear()
      ..addAll(raw.map((e) {
        try {
          return DownloadItem.fromJson(jsonDecode(e) as Map<String, dynamic>);
        } catch (_) {
          return null;
        }
      }).whereType<DownloadItem>());
    notifyListeners();
  }

  Future<void> add(DownloadItem item) async {
    completed.insert(0, item);
    if (completed.length > 100) {
      completed.removeRange(100, completed.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'downloads',
      completed.map((e) => jsonEncode(e.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<void> clear() async {
    completed.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('downloads');
    notifyListeners();
  }

  Future<void> remove(String id, String savedUri) async {
    await DownloadService.deleteFile(savedUri);
    completed.removeWhere((e) => e.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'downloads',
      completed.map((e) => jsonEncode(e.toJson())).toList(),
    );
    notifyListeners();
  }

  void start(String id, String name) {
    active[id] = 0;
    activeNames[id] = name;
    notifyListeners();
  }

  void progress(String id, double value) {
    if (!active.containsKey(id)) return;
    active[id] = value.clamp(0, 1);
    notifyListeners();
  }

  void finish(String id) {
    active.remove(id);
    activeNames.remove(id);
    notifyListeners();
  }

  void fail(String id) {
    active.remove(id);
    activeNames.remove(id);
    notifyListeners();
  }
}
