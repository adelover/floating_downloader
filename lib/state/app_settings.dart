import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/native_bridge.dart';

/// رنگ‌های حالت تاریک و روشن برنامه از این کلاس پیروی می‌کنند.
class ThemeStore {
  static final ValueNotifier<bool> isDark = ValueNotifier<bool>(true);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    isDark.value = prefs.getBool('dark_theme') ?? true;
  }

  static Future<void> setDark(bool value) async {
    isDark.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_theme', value);
  }

  static Future<void> toggle() => setDark(!isDark.value);
}

class SettingsStore {
  static final ValueNotifier<bool> wifiOnly = ValueNotifier<bool>(false);
  static final ValueNotifier<int> maxConcurrent = ValueNotifier<int>(2);
  static final ValueNotifier<bool> keepHistory = ValueNotifier<bool>(true);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    wifiOnly.value = prefs.getBool('wifi_only') ?? false;
    maxConcurrent.value =
        (prefs.getInt('max_concurrent') ?? 2).clamp(1, 4).toInt();
    keepHistory.value = prefs.getBool('keep_history') ?? true;
  }

  static Future<void> setWifiOnly(bool value) async {
    wifiOnly.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wifi_only', value);
  }

  static Future<void> setMaxConcurrent(int value) async {
    maxConcurrent.value = value.clamp(1, 4).toInt();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('max_concurrent', maxConcurrent.value);
  }

  static Future<void> setKeepHistory(bool value) async {
    keepHistory.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('keep_history', value);
  }
}

/// وقتی کاربر از اپ دیگری (مثل مرورگر یا تلگرام) یک لینک را با «اشتراک‌گذاری»
/// به این برنامه می‌فرستد، سمت نیتیو آن را از طریق MethodChannel به اینجا
/// می‌فرستد و این کلاس آن را به رابط کاربری اعلام می‌کند.
class SharedLinkBus {
  static final ValueNotifier<String?> pending = ValueNotifier<String?>(null);

  static Future<void> init() async {
    storageChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        final text = call.arguments as String?;
        if (text != null && text.trim().isNotEmpty) {
          pending.value = text.trim();
        }
      }
      return null;
    });
    try {
      final initial =
          await storageChannel.invokeMethod<String>('getSharedText');
      if (initial != null && initial.trim().isNotEmpty) {
        pending.value = initial.trim();
      }
    } catch (_) {}
  }
}
