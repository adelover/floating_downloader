import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// رنگ‌های حالت تاریک و روشن. همه‌ی ویجت‌های برنامه با همون اسم‌های قبلی
/// (_bg، _surface, _primary و…) کار می‌کنن؛ فقط این‌ها الان به تنظیمات
/// تم واکنش نشون می‌دن به‌جای اینکه یک رنگ ثابت باشن.
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

Color get _bg =>
    ThemeStore.isDark.value ? Color(0xFF090B12) : Color(0xFFF3F4FA);
Color get _surface =>
    ThemeStore.isDark.value ? Color(0xFF121722) : Color(0xFFFFFFFF);
Color get _surface2 =>
    ThemeStore.isDark.value ? Color(0xFF181E2B) : Color(0xFFEEF0F8);
Color get _primary => Color(0xFF7C5CFF);
Color get _cyan => Color(0xFF2AABEE);
Color get _success =>
    ThemeStore.isDark.value ? Color(0xFF36D399) : Color(0xFF13A76F);
Color get _danger =>
    ThemeStore.isDark.value ? Color(0xFFFF5D73) : Color(0xFFE3324B);
Color get _muted =>
    ThemeStore.isDark.value ? Color(0xFF8D96A8) : Color(0xFF6B7280);
Color get _bubbleOut =>
    ThemeStore.isDark.value ? Color(0xFF2B3547) : Color(0xFFE1F3FF);

final _storageChannel = MethodChannel('com.example.floating_downloader/storage');

@pragma('vm:entry-point')
Future<void> overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DownloadGateService.load();
  runApp(Directionality(
    textDirection: TextDirection.rtl,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FloatingUI(),
    ),
  ));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsStore.load();
  await ThemeStore.load();
  await DownloadGateService.load();
  await SharedLinkBus.init();
  runApp(DownloaderApp());
}

class DownloaderApp extends StatelessWidget {
  DownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeStore.isDark,
      builder: (context, isDark, _) {
        final base = ThemeData(
          brightness: isDark ? Brightness.dark : Brightness.light,
          scaffoldBackgroundColor: _bg,
          fontFamily: 'sans',
          colorScheme: isDark
              ? ColorScheme.dark(
                  primary: _primary,
                  secondary: _cyan,
                  surface: _surface,
                  error: _danger,
                )
              : ColorScheme.light(
                  primary: _primary,
                  secondary: _cyan,
                  surface: _surface,
                  error: _danger,
                ),
          splashFactory: InkSparkle.splashFactory,
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: _surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: _primary, width: 1.2),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 17,
            ),
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor: _surface2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: _surface,
            indicatorColor: _primary.withOpacity(.18),
            height: 72,
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                color: states.contains(WidgetState.selected)
                    ? _primary
                    : _muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            iconTheme: WidgetStateProperty.resolveWith(
              (states) => IconThemeData(
                color: states.contains(WidgetState.selected) ? _cyan : _muted,
              ),
            ),
          ),
        );

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Floating Downloader',
          theme: base,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? SizedBox.shrink(),
          ),
          home: KeyedSubtree(
            key: ValueKey(isDark),
            child: MainScreen(),
          ),
        );
      },
    );
  }
}

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

class SettingsStore {
  static final ValueNotifier<bool> wifiOnly = ValueNotifier<bool>(false);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    wifiOnly.value = prefs.getBool('wifi_only') ?? false;
  }

  static Future<void> setWifiOnly(bool value) async {
    wifiOnly.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wifi_only', value);
  }
}

/// وقتی کاربر از اپ دیگری (مثل مرورگر یا تلگرام) یک لینک را با «اشتراک‌گذاری»
/// به این برنامه می‌فرستد، سمت نیتیو آن را از طریق MethodChannel به اینجا
/// می‌فرستد و این کلاس آن را به رابط کاربری اعلام می‌کند.
class SharedLinkBus {
  static final ValueNotifier<String?> pending = ValueNotifier<String?>(null);

  static Future<void> init() async {
    _storageChannel.setMethodCallHandler((call) async {
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
          await _storageChannel.invokeMethod<String>('getSharedText');
      if (initial != null && initial.trim().isNotEmpty) {
        pending.value = initial.trim();
      }
    } catch (_) {}
  }
}

class DownloadService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: Duration(seconds: 20),
      receiveTimeout: Duration(minutes: 30),
      sendTimeout: Duration(seconds: 30),
      followRedirects: true,
      maxRedirects: 8,
      validateStatus: (status) => status != null && status >= 200 && status < 400,
    ),
  );

  static Future<String> _cacheDirectory() async {
    final path = await _storageChannel.invokeMethod<String>('getCacheDirectory');
    if (path == null || path.isEmpty) {
      throw Exception('مسیر موقت برنامه پیدا نشد.');
    }
    return path;
  }

  static Future<String> _saveToDownloads({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) async {
    final result = await _storageChannel.invokeMethod<String>(
      'saveToDownloads',
      {
        'sourcePath': sourcePath,
        'fileName': fileName,
        'mimeType': mimeType,
      },
    );
    if (result == null || result.isEmpty) {
      throw Exception('ذخیره فایل در Downloads ناموفق بود.');
    }
    return result;
  }

  static String sanitizeFileName(String value) {
    var name = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    name = name.replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) name = 'Floating_Download';
    if (name.length > 90) name = name.substring(0, 90);
    return name;
  }

  static String extensionFromUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    final match = RegExp(r'\.([a-z0-9]{2,5})$').firstMatch(path);
    return match == null ? '' : '.${match.group(1)}';
  }

  static String mimeFromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case '.mp4':
        return 'video/mp4';
      case '.webm':
        return 'video/webm';
      case '.mkv':
        return 'video/x-matroska';
      case '.mov':
        return 'video/quicktime';
      case '.mp3':
        return 'audio/mpeg';
      case '.m4a':
        return 'audio/mp4';
      case '.wav':
        return 'audio/wav';
      case '.pdf':
        return 'application/pdf';
      case '.zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  static String fileNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final last = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : '';
    final decoded = Uri.decodeComponent(last);
    if (decoded.isNotEmpty && decoded.contains('.')) {
      return sanitizeFileName(decoded);
    }
    final ext = extensionFromUrl(url);
    return 'Floating_${DateTime.now().millisecondsSinceEpoch}$ext';
  }

  static bool isHls(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') || lower.contains('application/vnd.apple.mpegurl');
  }

  static bool looksLikeMedia(String url) {
    final lower = url.toLowerCase();
    return RegExp(r'\.(mp4|webm|mkv|mov|mp3|m4a|wav)(\?|#|$)').hasMatch(lower) ||
        lower.contains('videoplayback') ||
        lower.contains('mime=video') ||
        lower.contains('mime=audio') ||
        isHls(lower);
  }

  /// بررسی چند بایت اول فایل (Magic Number) برای انواع پرکاربرد رسانه.
  /// اگر نوع فایل ناشناخته بود یا شناسه نداشت (مثلاً zip/pdf/غیره)، به‌جای
  /// رد کردن، به‌صورت محافظه‌کارانه قبول می‌شود؛ فقط جلوی «ویدیو/صدا/عکس جعلی
  /// که در واقع HTML یا متن است» گرفته می‌شود.
  static Future<bool> _looksLikeValidFile(File file, String mimeType) async {
    final raf = await file.open();
    try {
      final header = await raf.read(16);
      if (header.length < 4) return true;
      bool startsWithAscii(String s) {
        final bytes = s.codeUnits;
        if (header.length < bytes.length) return false;
        for (var i = 0; i < bytes.length; i++) {
          if (header[i] != bytes[i]) return false;
        }
        return true;
      }

      final looksLikeHtmlOrText = startsWithAscii('<htm') ||
          startsWithAscii('<!DO') ||
          startsWithAscii('<HTM') ||
          startsWithAscii('<?xm') ||
          startsWithAscii('{') ||
          startsWithAscii('[');

      // برای video/audio/image فقط بررسی می‌کنیم که فایل با یک صفحه
      // HTML/JSON/متنی شروع نشده باشد (رایج‌ترین حالت دانلود فیک).
      // امضای دقیق هر فرمت رسانه چک نمی‌شود چون فرمت‌های واقعی معتبر
      // زیادند و هدف فقط رد کردن پاسخ‌های غیر-رسانه‌ای است.
      if (looksLikeHtmlOrText) return false;
      return true;
    } finally {
      await raf.close();
    }
  }

  static Future<bool> isWifiConnected() async {
    try {
      return await _storageChannel.invokeMethod<bool>('isWifiConnected') ??
          true;
    } catch (_) {
      return true;
    }
  }

  static Future<String?> openFile(String uri, String mimeType) async {
    try {
      return await _storageChannel.invokeMethod<String>(
        'openFile',
        {'uri': uri, 'mimeType': mimeType},
      );
    } catch (e) {
      return e.toString();
    }
  }

  static Future<void> shareFile(String uri, String mimeType) async {
    try {
      await _storageChannel.invokeMethod('shareFile', {
        'uri': uri,
        'mimeType': mimeType,
      });
    } catch (_) {}
  }

  static Future<void> deleteFile(String uri) async {
    try {
      await _storageChannel.invokeMethod('deleteFile', {'uri': uri});
    } catch (_) {}
  }

  static Future<DownloadItem> download({
    required String url,
    String? preferredName,
    Map<String, String>? headers,
    void Function(double progress)? onProgress,
  }) async {
    if (SettingsStore.wifiOnly.value) {
      final wifi = await isWifiConnected();
      if (!wifi) {
        throw Exception(
          'طبق تنظیمات شما، دانلود فقط با Wi-Fi انجام می‌شود. به Wi-Fi وصل شوید یا این گزینه را در تنظیمات خاموش کنید.',
        );
      }
    }
    final cleanUrl = url.trim();
    final parsed = Uri.tryParse(cleanUrl);
    if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
      throw Exception('لینک وارد شده معتبر نیست.');
    }
    if (parsed.scheme != 'http' && parsed.scheme != 'https') {
      throw Exception('فقط لینک‌های HTTP/HTTPS پشتیبانی می‌شوند.');
    }
    if (isHls(cleanUrl)) {
      throw Exception(
        'این لینک HLS است. فایل .m3u8 مستقیماً MP4 نیست و برای تبدیل به MP4 به پردازش جداگانه نیاز دارد.',
      );
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final baseName = sanitizeFileName(
      preferredName?.trim().isNotEmpty == true
          ? preferredName!.trim()
          : fileNameFromUrl(cleanUrl),
    );
    final ext = extensionFromUrl(cleanUrl);
    final fileName = baseName.toLowerCase().endsWith(ext.toLowerCase()) ||
            ext.isEmpty
        ? baseName
        : '$baseName$ext';
    final mimeType = mimeFromExtension(extensionFromUrl(fileName));
    final cacheDir = await _cacheDirectory();
    final tempPath = '$cacheDir${Platform.pathSeparator}$id.part';

    DownloadStore.instance.start(id, fileName);

    try {
      final response = await _dio.download(
        cleanUrl,
        tempPath,
        options: Options(
          headers: {
            'Accept': '*/*',
            'User-Agent': _browserUserAgent,
            ...?headers,
          },
        ),
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final value = received / total;
            DownloadStore.instance.progress(id, value);
            onProgress?.call(value);
          }
        },
      );

      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 400) {
        throw Exception('سرور کد HTTP $status برگرداند.');
      }

      final file = File(tempPath);
      if (!await file.exists() || await file.length() == 0) {
        throw Exception('فایل دانلودشده خالی یا ناقص است.');
      }

      // اعتبارسنجی واقعی بودن فایل: خیلی از سرورها به‌جای فایل رسانه‌ای،
      // یک صفحه HTML خطا/لاگین با کد 200 برمی‌گردانند. بدون این بررسی،
      // آن صفحه به اشتباه به‌عنوان "دانلود موفق" ذخیره می‌شد ولی در واقع
      // فایل واقعی نبود (همان دانلود فیک).
      final expectsMedia = mimeType.startsWith('video/') ||
          mimeType.startsWith('audio/') ||
          mimeType.startsWith('image/');
      final responseContentType =
          (response.headers.value('content-type') ?? '').toLowerCase();
      if (expectsMedia &&
          (responseContentType.contains('text/html') ||
              responseContentType.contains('text/plain') ||
              responseContentType.contains('application/json'))) {
        throw Exception(
          'سرور به‌جای فایل رسانه‌ای یک صفحه متنی/HTML برگرداند (معمولاً یعنی لینک نیاز به ورود، Referer یا کوکی معتبر دارد).',
        );
      }
      if (!await _looksLikeValidFile(file, mimeType)) {
        throw Exception(
          'فایل دریافتی با نوع «$mimeType» مطابقت ندارد و احتمالاً واقعی نیست. لینک مستقیم فایل را بررسی کنید.',
        );
      }

      final savedUri = await _saveToDownloads(
        sourcePath: tempPath,
        fileName: fileName,
        mimeType: mimeType,
      );
      final bytes = await file.length();
      await file.delete().catchError((_) {});

      final item = DownloadItem(
        id: id,
        name: fileName,
        url: cleanUrl,
        savedUri: savedUri,
        date: DateTime.now().toIso8601String(),
        bytes: bytes,
        mimeType: mimeType,
      );
      await DownloadStore.instance.add(item);
      DownloadStore.instance.finish(id);
      return item;
    } catch (error) {
      DownloadStore.instance.fail(id);
      await File(tempPath).delete().catchError((_) {});
      rethrow;
    }
  }
}

class MainScreen extends StatefulWidget {
  MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int index = 0;

  late final pages = [
    HomeTab(key: HomeTab.globalKey),
    PlatformsTab(),
    BrowserTab(),
    HistoryTab(),
    SettingsTab(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DownloadStore.instance.load();
    SharedLinkBus.pending.addListener(_onSharedLink);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSharedLink());
  }

  void _onSharedLink() {
    final link = SharedLinkBus.pending.value;
    if (link == null || link.isEmpty) return;
    SharedLinkBus.pending.value = null;
    setState(() => index = 0);
    HomeTab.globalKey.currentState?.receiveSharedLink(link);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SharedLinkBus.pending.removeListener(_onSharedLink);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      DownloadStore.instance.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard_rounded),
            label: 'خانه',
          ),
          NavigationDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps_rounded),
            label: 'پلتفرم‌ها',
          ),
          NavigationDestination(
            icon: Icon(Icons.travel_explore_outlined),
            selectedIcon: Icon(Icons.travel_explore_rounded),
            label: 'مرورگر',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download_rounded),
            label: 'دانلودها',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'تنظیمات',
          ),
        ],
      ),
    );
  }
}

/// یک فرمت/کیفیت قابل‌دانلود از یک رسانه (مثلاً «۷۲۰p» یا «۱۲۸kbps»).
class MediaFormat {
  final String label;
  final String url;
  final String mimeType;
  final String ext;

  const MediaFormat({
    required this.label,
    required this.url,
    required this.mimeType,
    required this.ext,
  });
}

/// نتیجه‌ی استخراج یک لینک از یک پلتفرم: عنوان، صاحب محتوا، کاور، و
/// فرمت‌های قابل‌دانلود (اگر پلتفرم اجازه بده).
class MediaInfo {
  final String title;
  final String? author;
  final String? thumbnailUrl;
  final List<MediaFormat> formats;
  final String sourceUrl;
  final String referer;

  const MediaInfo({
    required this.title,
    this.author,
    this.thumbnailUrl,
    required this.formats,
    required this.sourceUrl,
    required this.referer,
  });
}

class PlatformExtractorException implements Exception {
  final String message;
  const PlatformExtractorException(this.message);
  @override
  String toString() => message;
}

/// استخراج‌کننده‌ی مخصوص هر پلتفرم. هر متد کاملاً مستقل از بقیه است تا
/// تغییر/خرابی یک سایت روی بقیه اثر نذاره.
class PlatformExtractor {
  static final Dio _http = Dio(
    BaseOptions(
      connectTimeout: Duration(seconds: 15),
      receiveTimeout: Duration(seconds: 20),
      headers: {
        'User-Agent': _browserUserAgent,
        'Accept': 'text/html,application/json,*/*',
      },
      validateStatus: (s) => s != null && s < 500,
    ),
  );

  static String? _metaTag(String html, String property) {
    final re = RegExp(
      '<meta[^>]+property=["\']$property["\'][^>]+content=["\']([^"\']*)["\']',
      caseSensitive: false,
    );
    var m = re.firstMatch(html);
    if (m == null) {
      // بعضی صفحات ترتیب content/property را برعکس می‌نویسند.
      final re2 = RegExp(
        '<meta[^>]+content=["\']([^"\']*)["\'][^>]+property=["\']$property["\']',
        caseSensitive: false,
      );
      m = re2.firstMatch(html);
    }
    if (m == null) return null;
    return m
        .group(1)
        ?.replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'");
  }

  // ---------------------------------------------------------------------
  // یوتیوب — فقط متادیتا (بدون دانلود فایل، طبق محدودیت‌های یوتیوب)
  // ---------------------------------------------------------------------
  static Future<MediaInfo> youtubeMeta(String url) async {
    final resp = await _http.get(
      'https://www.youtube.com/oembed',
      queryParameters: {'url': url, 'format': 'json'},
    );
    if (resp.statusCode != 200 || resp.data is! Map) {
      throw PlatformExtractorException(
        'اطلاعات این ویدیوی یوتیوب پیدا نشد. لینک را بررسی کنید (باید عمومی باشد).',
      );
    }
    final data = resp.data as Map;
    return MediaInfo(
      title: (data['title'] ?? 'ویدیوی یوتیوب').toString(),
      author: data['author_name']?.toString(),
      thumbnailUrl: data['thumbnail_url']?.toString(),
      formats: const [],
      sourceUrl: url,
      referer: url,
    );
  }

  // ---------------------------------------------------------------------
  // اسپاتیفای — فقط متادیتا (فایل صوتی رمزگذاری‌شده و غیرقابل‌استخراج است)
  // ---------------------------------------------------------------------
  static Future<MediaInfo> spotifyMeta(String url) async {
    final resp = await _http.get(
      'https://open.spotify.com/oembed',
      queryParameters: {'url': url},
    );
    if (resp.statusCode != 200 || resp.data is! Map) {
      throw PlatformExtractorException(
        'اطلاعات این آیتم اسپاتیفای پیدا نشد. لینک را بررسی کنید.',
      );
    }
    final data = resp.data as Map;
    return MediaInfo(
      title: (data['title'] ?? 'آیتم اسپاتیفای').toString(),
      author: data['provider_name']?.toString(),
      thumbnailUrl: data['thumbnail_url']?.toString(),
      formats: const [],
      sourceUrl: url,
      referer: url,
    );
  }

  // ---------------------------------------------------------------------
  // اینستاگرام — از تگ‌های og:video / og:image صفحه‌ی عمومی پست
  // ---------------------------------------------------------------------
  static Future<MediaInfo> instagram(String url) async {
    final resp = await _http.get(url);
    if (resp.statusCode != 200 || resp.data is! String) {
      throw PlatformExtractorException(
        'صفحه‌ی اینستاگرام بارگذاری نشد. ممکن است پست خصوصی باشد یا لینک اشتباه باشد.',
      );
    }
    final html = resp.data as String;
    final title = _metaTag(html, 'og:title') ?? 'پست اینستاگرام';
    final videoUrl = _metaTag(html, 'og:video');
    final imageUrl = _metaTag(html, 'og:image');

    if (videoUrl == null && imageUrl == null) {
      throw PlatformExtractorException(
        'رسانه‌ای در این پست پیدا نشد. اگر پست خصوصی یا استوری است، اینستاگرام اجازه‌ی دسترسی عمومی نمی‌دهد.',
      );
    }

    final formats = <MediaFormat>[
      if (videoUrl != null)
        MediaFormat(
          label: 'ویدیو (کیفیت اصلی)',
          url: videoUrl,
          mimeType: 'video/mp4',
          ext: '.mp4',
        ),
      if (imageUrl != null)
        MediaFormat(
          label: videoUrl != null ? 'کاور/تصویر' : 'تصویر (کیفیت اصلی)',
          url: imageUrl,
          mimeType: 'image/jpeg',
          ext: '.jpg',
        ),
    ];

    return MediaInfo(
      title: title,
      author: null,
      thumbnailUrl: imageUrl,
      formats: formats,
      sourceUrl: url,
      referer: 'https://www.instagram.com/',
    );
  }

  // ---------------------------------------------------------------------
  // تیک‌تاک — ابتدا از JSON داخل صفحه، در صورت شکست از og:video
  // ---------------------------------------------------------------------
  static Future<MediaInfo> tiktok(String url) async {
    final resp = await _http.get(url);
    if (resp.statusCode != 200 || resp.data is! String) {
      throw PlatformExtractorException('صفحه‌ی تیک‌تاک بارگذاری نشد.');
    }
    final html = resp.data as String;

    String? videoUrl;
    String? coverUrl;
    String? title;
    String? author;

    try {
      final scriptMatch = RegExp(
        r'<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.*?)</script>',
        dotAll: true,
      ).firstMatch(html);
      if (scriptMatch != null) {
        final jsonStr = scriptMatch.group(1)!;
        final data = jsonDecode(jsonStr) as Map;
        final scope = data['__DEFAULT_SCOPE__'] as Map?;
        final detail = scope?['webapp.video-detail'] as Map?;
        final itemStruct = detail?['itemInfo']?['itemStruct'] as Map?;
        if (itemStruct != null) {
          final video = itemStruct['video'] as Map?;
          title = itemStruct['desc']?.toString();
          author = itemStruct['author']?['uniqueId']?.toString();
          coverUrl = video?['cover']?.toString() ?? video?['originCover']?.toString();
          final playAddr = video?['playAddr']?.toString();
          final downloadAddr = video?['downloadAddr']?.toString();
          videoUrl = (downloadAddr != null && downloadAddr.isNotEmpty)
              ? downloadAddr
              : playAddr;
        }
      }
    } catch (_) {
      // به روش پشتیبان زیر می‌رویم
    }

    videoUrl ??= _metaTag(html, 'og:video') ?? _metaTag(html, 'og:video:url');
    coverUrl ??= _metaTag(html, 'og:image');
    title ??= _metaTag(html, 'og:title') ?? 'ویدیوی تیک‌تاک';

    if (videoUrl == null || videoUrl.isEmpty) {
      throw PlatformExtractorException(
        'لینک ویدیوی واقعی پیدا نشد. تیک‌تاک مدام ساختار صفحه‌اش را تغییر می‌دهد — این لاگ را برای بررسی بفرستید.',
      );
    }

    return MediaInfo(
      title: title,
      author: author,
      thumbnailUrl: coverUrl,
      formats: [
        MediaFormat(
          label: 'ویدیو (بدون واترمارک در صورت وجود)',
          url: videoUrl,
          mimeType: 'video/mp4',
          ext: '.mp4',
        ),
      ],
      sourceUrl: url,
      referer: 'https://www.tiktok.com/',
    );
  }

  // ---------------------------------------------------------------------
  // ساندکلاود — گرفتن client_id عمومی از باندل جاوااسکریپت، سپس resolve
  // ---------------------------------------------------------------------
  static String? _cachedSoundCloudClientId;

  static Future<String> _soundCloudClientId() async {
    if (_cachedSoundCloudClientId != null) return _cachedSoundCloudClientId!;
    final home = await _http.get('https://soundcloud.com');
    if (home.statusCode != 200 || home.data is! String) {
      throw PlatformExtractorException('اتصال به SoundCloud ممکن نشد.');
    }
    final html = home.data as String;
    final scriptUrls = RegExp(r'src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)"')
        .allMatches(html)
        .map((m) => m.group(1)!)
        .toList();

    for (final scriptUrl in scriptUrls.reversed) {
      try {
        final js = await _http.get(scriptUrl);
        if (js.statusCode != 200 || js.data is! String) continue;
        final jsText = js.data as String;
        final m = RegExp(r'client_id\s*[:=]\s*"([a-zA-Z0-9]{16,})"').firstMatch(jsText);
        if (m != null) {
          _cachedSoundCloudClientId = m.group(1);
          return _cachedSoundCloudClientId!;
        }
      } catch (_) {
        continue;
      }
    }
    throw PlatformExtractorException(
      'پیدا کردن شناسه‌ی دسترسی SoundCloud ممکن نشد. ممکن است ساختار سایت تغییر کرده باشد.',
    );
  }

  static Future<MediaInfo> soundcloud(String url) async {
    final clientId = await _soundCloudClientId();
    final resolve = await _http.get(
      'https://api-v2.soundcloud.com/resolve',
      queryParameters: {'url': url, 'client_id': clientId},
    );
    if (resolve.statusCode != 200 || resolve.data is! Map) {
      throw PlatformExtractorException(
        'این لینک SoundCloud پیدا نشد یا خصوصی/حذف‌شده است.',
      );
    }
    final track = resolve.data as Map;
    final title = track['title']?.toString() ?? 'آهنگ SoundCloud';
    final author = track['user']?['username']?.toString();
    final artwork = (track['artwork_url'] ?? track['user']?['avatar_url'])
        ?.toString()
        .replaceAll('-large.', '-t500x500.');

    final transcodings = (track['media']?['transcodings'] as List?) ?? [];
    final progressive = transcodings.firstWhere(
      (t) => (t['format']?['protocol'] == 'progressive'),
      orElse: () => null,
    );

    if (progressive == null) {
      throw PlatformExtractorException(
        'این آهنگ فقط به‌صورت استریم HLS ارائه شده و امکان دانلود مستقیم آن نیست.',
      );
    }

    final streamInfo = await _http.get(
      progressive['url'].toString(),
      queryParameters: {'client_id': clientId},
    );
    final streamUrl = (streamInfo.data is Map) ? streamInfo.data['url']?.toString() : null;
    if (streamUrl == null || streamUrl.isEmpty) {
      throw PlatformExtractorException('گرفتن لینک نهایی فایل صوتی ناموفق بود.');
    }

    return MediaInfo(
      title: title,
      author: author,
      thumbnailUrl: artwork,
      formats: [
        MediaFormat(
          label: 'MP3 (کیفیت استاندارد)',
          url: streamUrl,
          mimeType: 'audio/mpeg',
          ext: '.mp3',
        ),
      ],
      sourceUrl: url,
      referer: 'https://soundcloud.com/',
    );
  }
}

/// این‌ها را با کانال و (اختیاری) توکن ربات خودتان جایگزین کنید.
class TelegramGateConfig {
  /// یوزرنیم کانال بدون @ — مثلاً برای t.me/gard_config بنویسید gard_config
  static const channelUsername = 'gard_config';
  static const channelDisplayName = 'کانال رسمی Floating Downloader';

  /// اختیاری: اگر این ربات را ادمین کانال کنید و توکنش را اینجا بگذارید،
  /// «تایید عضویت» واقعاً از API تلگرام استعلام می‌گیرد. اگر خالی بماند،
  /// دکمه‌ی تایید بعد از بازدید از کانال مستقیم ادامه می‌دهد (بدون استعلام).
  static const botToken = '';

  /// وقتی botToken پر است، این user_id عددی تلگرام کاربر برای استعلام
  /// getChatMember لازم است. چون این اپ به هویت تلگرام کاربر متصل نیست
  /// (نیاز به راه‌اندازی Telegram Login با دامنه‌ی واقعی دارد)، این مقدار
  /// باید جایی در برنامه از کاربر گرفته شود؛ در غیر این صورت استعلام واقعی
  /// انجام نمی‌شود و به‌صورت شفاف به همان حالت «بدون استعلام» برمی‌گردد.
  static int? telegramUserId;

  static bool get hasRealVerification => botToken.isNotEmpty && telegramUserId != null;
}

/// شمارش دانلودهای موفق و قفل‌کردن ادامه‌ی کار تا عضویت در کانال.
class DownloadGateService {
  static final ValueNotifier<int> successCount = ValueNotifier<int>(0);
  static final ValueNotifier<bool> verified = ValueNotifier<bool>(false);
  static const _threshold = 2;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    successCount.value = prefs.getInt('gate_success_count') ?? 0;
    verified.value = prefs.getBool('gate_verified') ?? false;
  }

  static bool get isLocked => successCount.value >= _threshold && !verified.value;

  /// بعد از هر دانلود موفق (از هر پلتفرمی) صدا زده می‌شود.
  static Future<void> registerSuccess() async {
    successCount.value += 1;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('gate_success_count', successCount.value);
  }

  /// بررسی واقعی عضویت از طریق Telegram Bot API (در صورت تنظیم‌بودن توکن).
  /// نتیجه را با پیام دقیق برمی‌گرداند تا هیچ‌چیز نمایشی/جعلی نباشد.
  static Future<({bool ok, String message})> checkMembership() async {
    if (!TelegramGateConfig.hasRealVerification) {
      return (
        ok: true,
        message: 'استعلام خودکار فعال نیست؛ بر اساس تایید شما ادامه داده شد.',
      );
    }
    try {
      final dio = Dio();
      final resp = await dio.get(
        'https://api.telegram.org/bot${TelegramGateConfig.botToken}/getChatMember',
        queryParameters: {
          'chat_id': '@${TelegramGateConfig.channelUsername}',
          'user_id': TelegramGateConfig.telegramUserId,
        },
      );
      final data = resp.data;
      if (data is Map && data['ok'] == true) {
        final status = data['result']?['status']?.toString() ?? '';
        final isMember = ['member', 'administrator', 'creator'].contains(status);
        return (
          ok: isMember,
          message: isMember
              ? 'عضویت شما تایید شد.'
              : 'شما هنوز عضو کانال نیستید. لطفاً ابتدا عضو شوید.',
        );
      }
      return (
        ok: false,
        message: data is Map ? (data['description']?.toString() ?? 'خطای نامشخص از تلگرام.') : 'خطای نامشخص از تلگرام.',
      );
    } catch (e) {
      return (ok: false, message: 'استعلام تلگرام ناموفق بود: ${e.toString()}');
    }
  }

  static Future<void> markVerified() async {
    verified.value = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gate_verified', true);
  }

  /// اگر قفل است، صفحه‌ی قفل را نشان می‌دهد و صبر می‌کند تا کاربر رد شود.
  /// خروجی true یعنی حالا اجازه‌ی ادامه‌ی کار دارد.
  static Future<bool> ensureUnlocked(BuildContext context) async {
    if (!isLocked) return true;
    final result = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => const TelegramGateScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
    );
    return result == true;
  }

  /// بعد از یک دانلود موفق: شمارنده را بالا می‌برد و اگر تازه به آستانه
  /// رسیده، بلافاصله صفحه‌ی قفل را نشان می‌دهد.
  static Future<void> registerSuccessAndMaybeGate(BuildContext context) async {
    final wasLocked = isLocked;
    await registerSuccess();
    if (!wasLocked && isLocked && context.mounted) {
      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (_, __, ___) => const TelegramGateScreen(),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: child,
          ),
        ),
      );
    }
  }
}

class TelegramGateScreen extends StatefulWidget {
  const TelegramGateScreen({super.key});

  @override
  State<TelegramGateScreen> createState() => _TelegramGateScreenState();
}

class _TelegramGateScreenState extends State<TelegramGateScreen> {
  bool checking = false;
  bool openedChannel = false;
  String? error;

  Future<void> _openChannel() async {
    setState(() => openedChannel = true);
    final deepLink = Uri.parse(
      'tg://resolve?domain=${TelegramGateConfig.channelUsername}',
    );
    final webLink = Uri.parse(
      'https://t.me/${TelegramGateConfig.channelUsername}',
    );
    try {
      final opened = await launchUrl(deepLink, mode: LaunchMode.externalApplication);
      if (!opened) {
        await launchUrl(webLink, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(webLink, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _confirm() async {
    if (!openedChannel) {
      setState(() => error = 'لطفاً ابتدا روی «عضویت در کانال» بزنید.');
      return;
    }
    setState(() {
      checking = true;
      error = null;
    });
    final result = await DownloadGateService.checkMembership();
    if (!mounted) return;
    if (result.ok) {
      await DownloadGateService.markVerified();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        checking = false;
        error = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [_primary, _cyan],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _cyan.withOpacity(.35),
                        blurRadius: 40,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(Icons.telegram, color: Colors.white, size: 56),
                ),
                SizedBox(height: 28),
                Text(
                  'برای ادامه‌ی دانلود، عضو کانال شوید',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 10),
                Text(
                  'با عضویت در ${TelegramGateConfig.channelDisplayName}، به آپدیت‌ها و ویژگی‌های جدید دسترسی پیدا می‌کنید و اجازه‌ی دانلودهای بعدی هم فعال می‌شود.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 13, height: 1.8),
                ),
                SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _openChannel,
                    style: FilledButton.styleFrom(
                      backgroundColor: _cyan,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: Icon(Icons.telegram, size: 22),
                    label: Text(
                      'عضویت در کانال',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: checking ? null : _confirm,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _primary, width: 1.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: checking
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _primary),
                          )
                        : Icon(Icons.check_circle_outline_rounded, color: _primary),
                    label: Text(
                      'تایید عضویت و ادامه',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _primary),
                    ),
                  ),
                ),
                if (error != null) ...[
                  SizedBox(height: 14),
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _danger, fontSize: 12),
                  ),
                ],
                SizedBox(height: 18),
                Text(
                  TelegramGateConfig.hasRealVerification
                      ? 'عضویت شما به‌صورت خودکار از تلگرام استعلام می‌شود.'
                      : 'در این نسخه، تایید بر پایه‌ی اعتماد به شماست؛ برای استعلام خودکار واقعی، توکن ربات را در تنظیمات پروژه فعال کنید.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeTab extends StatefulWidget {
  HomeTab({super.key});

  static final GlobalKey<_HomeTabState> globalKey =
      GlobalKey<_HomeTabState>();

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with WidgetsBindingObserver {
  final urlController = TextEditingController();
  bool overlayActive = false;
  bool downloading = false;
  String? clipboardSuggestion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshOverlay();
    _checkClipboard();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkClipboard();
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) return;
      final uri = Uri.tryParse(text);
      final isLink = uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.hasAuthority;
      if (!isLink || text == urlController.text) return;
      if (mounted) setState(() => clipboardSuggestion = text);
    } catch (_) {}
  }

  void _useClipboardSuggestion() {
    final link = clipboardSuggestion;
    if (link == null) return;
    setState(() {
      urlController.text = link;
      clipboardSuggestion = null;
    });
  }

  /// وقتی از اپ دیگری لینک به این برنامه اشتراک‌گذاری شود، از اینجا وارد
  /// می‌شود و دانلود به‌صورت خودکار شروع می‌شود.
  void receiveSharedLink(String link) {
    setState(() {
      urlController.text = link;
      clipboardSuggestion = null;
    });
    _download();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    urlController.dispose();
    super.dispose();
  }

  Future<void> _refreshOverlay() async {
    try {
      final active = await FlutterOverlayWindow.isActive();
      if (mounted) setState(() => overlayActive = active);
    } catch (_) {}
  }

  Future<void> _toggleOverlay() async {
    try {
      var allowed = await FlutterOverlayWindow.isPermissionGranted();
      if (!allowed) {
        allowed = await FlutterOverlayWindow.requestPermission() ?? false;
      }
      if (!allowed) {
        _message('اجازه نمایش روی برنامه‌های دیگر داده نشد.');
        return;
      }

      if (overlayActive) {
        await FlutterOverlayWindow.closeOverlay();
      } else {
        await FlutterOverlayWindow.showOverlay(
          alignment: OverlayAlignment.centerRight,
          width: 330,
          height: 180,
          flag: OverlayFlag.focusPointer,
          enableDrag: true,
        );
      }
      await Future<void>.delayed(Duration(milliseconds: 350));
      await _refreshOverlay();
    } catch (e) {
      _message('فعال‌سازی پنجره شناور ناموفق بود: $e');
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text?.trim().isNotEmpty == true) {
      urlController.text = data!.text!.trim();
      setState(() {});
    }
  }

  Future<void> _download() async {
    final url = urlController.text.trim();
    if (url.isEmpty) {
      _message('اول لینک فایل را وارد کنید.');
      return;
    }
    if (!await DownloadGateService.ensureUnlocked(context)) return;
    setState(() => downloading = true);
    try {
      final item = await DownloadService.download(url: url);
      if (mounted) {
        _message('✓ ${item.name} در Downloads ذخیره شد.');
        urlController.clear();
        await DownloadGateService.registerSuccessAndMaybeGate(context);
      }
    } catch (e) {
      if (mounted) _message(_friendlyError(e));
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _friendlyError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    return text.length > 220 ? '${text.substring(0, 220)}…' : text;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
            sliver: SliverToBoxAdapter(
              child: _Header(
                title: 'Floating Downloader',
                subtitle: 'سریع، تمیز و بدون مسیرهای جعلی',
                trailing: IconButton(
                  onPressed: _toggleOverlay,
                  tooltip: 'پنجره شناور',
                  icon: Icon(
                    overlayActive
                        ? Icons.bubble_chart_rounded
                        : Icons.bubble_chart_outlined,
                    color: overlayActive ? _cyan : _muted,
                  ),
                ),
              ),
            ),
          ),
          if (clipboardSuggestion != null)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _ClipboardBanner(
                  link: clipboardSuggestion!,
                  onUse: _useClipboardSuggestion,
                  onDismiss: () => setState(() => clipboardSuggestion = null),
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
            sliver: SliverToBoxAdapter(
              child: _HeroCard(
                controller: urlController,
                loading: downloading,
                onPaste: _paste,
                onDownload: _download,
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: AnimatedBuilder(
                animation: DownloadStore.instance,
                builder: (context, _) => _StatsRow(
                  active: DownloadStore.instance.active.length,
                  completed: DownloadStore.instance.completed.length,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 10),
            sliver: SliverToBoxAdapter(
              child: Text(
                'ابزارهای سریع',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 28),
            sliver: SliverGrid.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.45,
              children: [
                _QuickCard(
                  icon: Icons.travel_explore_rounded,
                  title: 'مرورگر هوشمند',
                  subtitle: 'پیدا کردن لینک‌های مستقیم رسانه',
                  accent: _cyan,
                  onTap: () => _openBrowser(context),
                ),
                _QuickCard(
                  icon: Icons.layers_rounded,
                  title: 'پنجره شناور',
                  subtitle: overlayActive ? 'فعال است' : 'فعال‌سازی روی سایر برنامه‌ها',
                  accent: _primary,
                  onTap: _toggleOverlay,
                ),
                _QuickCard(
                  icon: Icons.history_rounded,
                  title: 'دانلودهای من',
                  subtitle: 'تاریخچه فایل‌های ذخیره‌شده',
                  accent: _success,
                  onTap: () => _openDownloads(context),
                ),
                _QuickCard(
                  icon: Icons.telegram,
                  title: 'کانال رسمی',
                  subtitle: '@gard_config',
                  accent: Color(0xFF2AABEE),
                  onTap: () async {
                    await launchUrl(
                      Uri.parse('https://t.me/gard_config'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openBrowser(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BrowserTab(fullscreen: true)),
    );
  }

  void _openDownloads(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HistoryTab(fullscreen: true)),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget trailing;

  _Header({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: LinearGradient(
              colors: [_primary, _cyan],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
          ),
          child: Icon(Icons.download_rounded, color: Colors.white),
        ),
        SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
        trailing,
      ],
    );
  }
}

class _ClipboardBanner extends StatelessWidget {
  final String link;
  final VoidCallback onUse;
  final VoidCallback onDismiss;

  _ClipboardBanner({
    required this.link,
    required this.onUse,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _cyan.withOpacity(.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cyan.withOpacity(.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded, color: _cyan, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'لینکی در کلیپ‌بورد پیدا شد',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
                Text(
                  link,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onUse,
            child: Text('استفاده'),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(),
            onPressed: onDismiss,
            icon: Icon(Icons.close_rounded, size: 17, color: _muted),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onPaste;
  final VoidCallback onDownload;

  _HeroCard({
    required this.controller,
    required this.loading,
    required this.onPaste,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [
            _surface2,
            _primary.withOpacity(.10),
            _surface,
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        border: Border.all(color: Colors.white.withOpacity(.06)),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(.08),
            blurRadius: 30,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: _cyan),
              SizedBox(width: 8),
              Text(
                'دانلود مستقیم',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'لینک مستقیم فایل را وارد کنید. فایل پس از دانلود واقعی داخل Downloads ذخیره می‌شود.',
            style: TextStyle(color: _muted, height: 1.5, fontSize: 12),
          ),
          SizedBox(height: 16),
          TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            maxLines: 2,
            minLines: 1,
            decoration: InputDecoration(
              hintText: 'https://example.com/video.mp4',
              hintTextDirection: TextDirection.ltr,
              suffixIcon: IconButton(
                onPressed: onPaste,
                tooltip: 'چسباندن',
                icon: Icon(Icons.content_paste_rounded),
              ),
            ),
          ),
          SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: loading ? null : onDownload,
              icon: loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.download_rounded),
              label: Text(loading ? 'در حال دانلود…' : 'شروع دانلود'),
              style: FilledButton.styleFrom(
                minimumSize: Size.fromHeight(52),
                backgroundColor: _primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int active;
  final int completed;

  _StatsRow({required this.active, required this.completed});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.downloading_rounded,
            label: 'در حال دانلود',
            value: '$active',
            accent: _cyan,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.check_circle_rounded,
            label: 'تکمیل‌شده',
            value: '$completed',
            accent: _success,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withOpacity(.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: accent, size: 21),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  _QuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(21),
      child: InkWell(
        borderRadius: BorderRadius.circular(21),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: Colors.white.withOpacity(.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent, size: 25),
              Spacer(),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _muted, fontSize: 10, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BrowserTab extends StatefulWidget {
  final bool fullscreen;

  BrowserTab({super.key, this.fullscreen = false});

  @override
  State<BrowserTab> createState() => _BrowserTabState();
}

_browserUserAgent =
    'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/131 Mobile Safari/537.36';

class _DetectedMedia {
  final String url;
  final String referer;

  _DetectedMedia({required this.url, required this.referer});
}

class _BrowserTabState extends State<BrowserTab> {
  InAppWebViewController? webView;
  final addressController = TextEditingController(text: 'https://www.google.com');
  double progress = 0;
  bool loading = true;
  String currentPageUrl = 'https://www.google.com';
  final List<_DetectedMedia> detected = [];

  @override
  void dispose() {
    addressController.dispose();
    super.dispose();
  }

  void _addDetected(String url) {
    if (!DownloadService.looksLikeMedia(url)) return;
    if (DownloadService.isHls(url)) return;
    if (detected.any((e) => e.url == url)) return;
    if (!mounted) return;
    setState(() {
      detected.insert(0, _DetectedMedia(url: url, referer: currentPageUrl));
      if (detected.length > 20) detected.removeLast();
    });
  }

  Future<void> _navigate(String value) async {
    final input = value.trim();
    if (input.isEmpty) return;

    Uri uri;
    final parsed = Uri.tryParse(input);
    if (parsed != null && parsed.hasScheme) {
      uri = parsed;
    } else {
      uri = Uri.https('www.google.com', '/search', {'q': input});
    }
    addressController.text = uri.toString();
    await webView?.loadUrl(urlRequest: URLRequest(url: WebUri(uri.toString())));
  }

  Future<void> _downloadDetected(_DetectedMedia media) async {
    Navigator.of(context).maybePop();
    if (!await DownloadGateService.ensureUnlocked(context)) return;
    try {
      // بدون Referer/Cookieِ درست، بسیاری از سرورها به‌جای فایل، صفحه
      // خطا/لاگین برمی‌گردانند که باعث «دانلود فیک» می‌شد. اینجا همان
      // هدرهایی که مرورگر داخلی برای دیدن رسانه استفاده کرده، برای دانلود
      // هم فرستاده می‌شود.
      String cookieHeader = '';
      try {
        final cookies = await CookieManager.instance()
            .getCookies(url: WebUri(media.referer));
        cookieHeader = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      } catch (_) {}

      await DownloadService.download(
        url: media.url,
        headers: {
          'Referer': media.referer,
          if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ دانلود کامل شد و در Downloads ذخیره شد.')),
        );
        await DownloadGateService.registerSuccessAndMaybeGate(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  void _showDetected() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * .72,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 20),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                SizedBox(height: 18),
                Row(
                  children: [
                    Icon(Icons.radar_rounded, color: _cyan),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'رسانه‌های پیدا شده',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ),
                    Text(
                      '${detected.length}',
                      style: TextStyle(color: _muted),
                    ),
                  ],
                ),
                SizedBox(height: 14),
                Expanded(
                  child: ListView.separated(
                    itemCount: detected.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final media = detected[index];
                      final mime = DownloadService.mimeFromExtension(
                        DownloadService.extensionFromUrl(media.url),
                      );
                      return Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _surface2,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Color(0x1A38D9FF),
                              child: Icon(
                                mime.startsWith('audio/')
                                    ? Icons.music_note_rounded
                                    : Icons.movie_rounded,
                                color: _cyan,
                              ),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                media.url,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textDirection: TextDirection.ltr,
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                            SizedBox(width: 8),
                            IconButton(
                              onPressed: () => _downloadDetected(media),
                              icon: Icon(Icons.download_rounded),
                              color: _success,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              if (widget.fullscreen)
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.arrow_back_rounded),
                ),
              IconButton(
                onPressed: () => webView?.goBack(),
                icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              ),
              IconButton(
                onPressed: () => webView?.goForward(),
                icon: Icon(Icons.arrow_forward_ios_rounded, size: 18),
              ),
              Expanded(
                child: TextField(
                  controller: addressController,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: _navigate,
                  decoration: InputDecoration(
                    hintText: 'آدرس یا جستجو…',
                    prefixIcon: Icon(Icons.language_rounded, size: 20),
                    suffixIcon: IconButton(
                      onPressed: () => _navigate(addressController.text),
                      icon: Icon(Icons.arrow_upward_rounded),
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => webView?.reload(),
                icon: Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        if (progress < 1)
          LinearProgressIndicator(
            value: progress == 0 ? null : progress,
            minHeight: 2,
            color: _cyan,
            backgroundColor: Colors.transparent,
          ),
        Expanded(
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri('https://www.google.com'),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  useShouldInterceptRequest: true,
                  useOnLoadResource: true,
                  useOnDownloadStart: true,
                  thirdPartyCookiesEnabled: true,
                  transparentBackground: true,
                  userAgent: _browserUserAgent,
                ),
                onWebViewCreated: (controller) => webView = controller,
                onLoadStart: (controller, url) {
                  if (!mounted) return;
                  setState(() {
                    loading = true;
                    progress = 0;
                    if (url != null) {
                      addressController.text = url.toString();
                      currentPageUrl = url.toString();
                    }
                    detected.clear();
                  });
                },
                onLoadStop: (controller, url) {
                  if (!mounted) return;
                  setState(() => loading = false);
                },
                onProgressChanged: (controller, value) {
                  if (!mounted) return;
                  setState(() => progress = value / 100);
                },
                shouldInterceptRequest: (controller, request) async {
                  _addDetected(request.url.toString());
                  return null;
                },
                onLoadResource: (controller, resource) async {
                  _addDetected(resource.url.toString());
                },
                onDownloadStartRequest: (controller, request) async {
                  _addDetected(request.url.toString());
                },
              ),
              if (loading)
                Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: widget.fullscreen
          ? null
          : AppBar(
              title: Text(
                'مرورگر هوشمند',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              backgroundColor: Colors.transparent,
            ),
      body: body,
      floatingActionButton: detected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _showDetected,
              backgroundColor: _primary,
              icon: Icon(Icons.download_rounded),
              label: Text('${detected.length} رسانه'),
            ),
    );
  }
}

class _PlatformDef {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String hint;
  final bool downloadable;
  final Future<MediaInfo> Function(String url) fetch;

  const _PlatformDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.hint,
    required this.downloadable,
    required this.fetch,
  });
}

final List<_PlatformDef> _platformDefs = [
  _PlatformDef(
    id: 'instagram',
    title: 'اینستاگرام',
    subtitle: 'دانلود پست/ریلز عمومی',
    icon: Icons.camera_alt_rounded,
    color: Color(0xFFE1306C),
    hint: 'لینک پست یا ریلز اینستاگرام را بچسبانید',
    downloadable: true,
    fetch: PlatformExtractor.instagram,
  ),
  _PlatformDef(
    id: 'tiktok',
    title: 'تیک‌تاک',
    subtitle: 'دانلود ویدیوی عمومی',
    icon: Icons.music_video_rounded,
    color: Color(0xFF25F4EE),
    hint: 'لینک ویدیوی تیک‌تاک را بچسبانید',
    downloadable: true,
    fetch: PlatformExtractor.tiktok,
  ),
  _PlatformDef(
    id: 'soundcloud',
    title: 'ساندکلاود',
    subtitle: 'دانلود آهنگ عمومی',
    icon: Icons.cloud_rounded,
    color: Color(0xFFFF7700),
    hint: 'لینک آهنگ SoundCloud را بچسبانید',
    downloadable: true,
    fetch: PlatformExtractor.soundcloud,
  ),
  _PlatformDef(
    id: 'youtube',
    title: 'یوتیوب',
    subtitle: 'فقط اطلاعات + باز کردن در اپ',
    icon: Icons.smart_display_rounded,
    color: Color(0xFFFF0000),
    hint: 'لینک ویدیوی یوتیوب را بچسبانید',
    downloadable: false,
    fetch: PlatformExtractor.youtubeMeta,
  ),
  _PlatformDef(
    id: 'spotify',
    title: 'اسپاتیفای',
    subtitle: 'فقط اطلاعات + باز کردن در اپ',
    icon: Icons.headphones_rounded,
    color: Color(0xFF1DB954),
    hint: 'لینک آهنگ/پلی‌لیست اسپاتیفای را بچسبانید',
    downloadable: false,
    fetch: PlatformExtractor.spotifyMeta,
  ),
];

class PlatformsTab extends StatelessWidget {
  const PlatformsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('پلتفرم‌ها', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          Text(
            'هر پلتفرم کاملاً جدا کار می‌کند: لینک را بچسبانید تا عنوان، کاور و گزینه‌های دانلود مخصوص همان پلتفرم نشان داده شود.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.7),
          ),
          SizedBox(height: 16),
          ..._platformDefs.map(
            (p) => Card(
              color: _surface,
              elevation: 0,
              margin: EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PlatformDetailScreen(def: p)),
                ),
                leading: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: p.color.withOpacity(.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(p.icon, color: p.color),
                ),
                title: Text(p.title, style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(p.subtitle, style: TextStyle(color: _muted, fontSize: 11)),
                trailing: Icon(Icons.chevron_left_rounded, color: _muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PlatformDetailScreen extends StatefulWidget {
  final _PlatformDef def;
  const PlatformDetailScreen({super.key, required this.def});

  @override
  State<PlatformDetailScreen> createState() => _PlatformDetailScreenState();
}

class _PlatformDetailScreenState extends State<PlatformDetailScreen> {
  final linkController = TextEditingController();
  bool loading = false;
  String? error;
  MediaInfo? info;
  final Set<String> downloadingFormats = {};

  @override
  void dispose() {
    linkController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final link = linkController.text.trim();
    if (link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      setState(() => error = 'لینک معتبر نیست.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
      info = null;
    });
    try {
      final result = await widget.def.fetch(link);
      if (!mounted) return;
      setState(() => info = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _downloadFormat(MediaFormat format) async {
    if (!await DownloadGateService.ensureUnlocked(context)) return;
    setState(() => downloadingFormats.add(format.url));
    try {
      await DownloadService.download(
        url: format.url,
        preferredName: info?.title,
        headers: {'Referer': info?.referer ?? widget.def.hint},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ دانلود کامل شد و در Downloads ذخیره شد.')),
        );
        await DownloadGateService.registerSuccessAndMaybeGate(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => downloadingFormats.remove(format.url));
    }
  }

  Future<void> _openOriginal() async {
    final uri = Uri.tryParse(linkController.text.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.def;
    return Scaffold(
      appBar: AppBar(
        title: Text(def.title, style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 6, 16, 28),
        children: [
          Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: linkController,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(hintText: def.hint),
                ),
                SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: loading ? null : _fetch,
                    style: FilledButton.styleFrom(backgroundColor: def.color),
                    icon: loading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(Icons.search_rounded),
                    label: Text(loading ? 'در حال بررسی…' : 'بررسی لینک'),
                  ),
                ),
              ],
            ),
          ),
          if (error != null) ...[
            SizedBox(height: 14),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _danger.withOpacity(.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _danger.withOpacity(.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: _danger, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(error!, style: TextStyle(color: _danger, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
          if (info != null) ...[
            SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: info!.thumbnailUrl != null
                      ? Image.network(
                          info!.thumbnailUrl!,
                          width: 92,
                          height: 92,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 92,
                            height: 92,
                            color: _surface2,
                            child: Icon(def.icon, color: def.color),
                          ),
                        )
                      : Container(
                          width: 92,
                          height: 92,
                          color: _surface2,
                          child: Icon(def.icon, color: def.color),
                        ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info!.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      if (info!.author != null) ...[
                        SizedBox(height: 6),
                        Text(info!.author!, style: TextStyle(color: _muted, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 18),
            if (!def.downloadable) ...[
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: def.color.withOpacity(.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${def.title} اجازه‌ی دانلود مستقیم فایل توسط اپ‌های شخص‌ثالث را نمی‌دهد. می‌توانید همین‌جا آن را در اپ اصلی باز کنید.',
                  style: TextStyle(color: _muted, fontSize: 11.5, height: 1.7),
                ),
              ),
              SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openOriginal,
                  icon: Icon(Icons.open_in_new_rounded),
                  label: Text('باز کردن در اپ ${def.title}'),
                ),
              ),
            ] else
              ...info!.formats.map((format) {
                final isDownloading = downloadingFormats.contains(format.url);
                return Container(
                  margin: EdgeInsets.only(bottom: 8),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        format.mimeType.startsWith('audio/')
                            ? Icons.music_note_rounded
                            : format.mimeType.startsWith('image/')
                                ? Icons.image_rounded
                                : Icons.movie_rounded,
                        color: def.color,
                      ),
                      SizedBox(width: 10),
                      Expanded(child: Text(format.label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                      FilledButton(
                        onPressed: isDownloading ? null : () => _downloadFormat(format),
                        style: FilledButton.styleFrom(backgroundColor: def.color),
                        child: isDownloading
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(Icons.download_rounded, size: 18),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }
}

class HistoryTab extends StatefulWidget {
  final bool fullscreen;

  HistoryTab({super.key, this.fullscreen = false});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  final searchController = TextEditingController();
  String query = '';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.fullscreen
            ? IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(Icons.arrow_back_rounded),
              )
            : null,
        title: Text(
          'دانلودهای من',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.transparent,
        actions: [
          AnimatedBuilder(
            animation: DownloadStore.instance,
            builder: (_, __) => DownloadStore.instance.completed.isEmpty
                ? SizedBox.shrink()
                : IconButton(
                    tooltip: 'پاک کردن تاریخچه',
                    onPressed: () => _confirmClear(context),
                    icon: Icon(Icons.delete_sweep_rounded),
                  ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: DownloadStore.instance,
        builder: (context, _) {
          final store = DownloadStore.instance;
          if (store.completed.isEmpty && store.active.isEmpty) {
            return _EmptyState(
              icon: Icons.download_for_offline_rounded,
              title: 'هنوز دانلودی ندارید',
              subtitle: 'از صفحه خانه لینک مستقیم بدهید یا از مرورگر یک رسانه پیدا کنید.',
            );
          }

          final filtered = query.trim().isEmpty
              ? store.completed
              : store.completed
                  .where((e) =>
                      e.name.toLowerCase().contains(query.trim().toLowerCase()))
                  .toList();

          return ListView(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 24),
            children: [
              if (store.completed.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: searchController,
                    onChanged: (value) => setState(() => query = value),
                    decoration: InputDecoration(
                      hintText: 'جستجو در نام فایل…',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                      contentPadding: EdgeInsets.symmetric(horizontal: 14),
                    ),
                  ),
                ),
              if (store.active.isNotEmpty) ...[
                _SectionTitle(title: 'در حال دانلود'),
                ...store.active.entries.map(
                  (entry) => _ActiveDownloadCard(
                    name: store.activeNames[entry.key] ?? 'فایل',
                    progress: entry.value,
                  ),
                ),
                SizedBox(height: 16),
              ],
              if (filtered.isNotEmpty) ...[
                _SectionTitle(title: 'تکمیل‌شده'),
                ...filtered.map((item) => _HistoryCard(item: item)),
              ] else if (query.trim().isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text(
                    'نتیجه‌ای پیدا نشد.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('پاک کردن تاریخچه؟'),
        content: Text('فقط تاریخچه داخل برنامه حذف می‌شود؛ فایل‌های Downloads پاک نمی‌شوند.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('پاک کردن'),
          ),
        ],
      ),
    );
    if (yes == true) await DownloadStore.instance.clear();
  }
}

class _ActiveDownloadCard extends StatelessWidget {
  final String name;
  final double progress;

  _ActiveDownloadCard({
    required this.name,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Row(
        children: [
          _FileIcon(icon: Icons.downloading_rounded, color: _cyan),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress == 0 ? null : progress,
                    minHeight: 5,
                    color: _cyan,
                    backgroundColor: Colors.white10,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 10),
          Text(
            '${(progress * 100).round()}%',
            style: TextStyle(
              color: _cyan,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final DownloadItem item;

  _HistoryCard({required this.item});

  Future<void> _handleAction(BuildContext context, String action) async {
    switch (action) {
      case 'open':
        final error = await DownloadService.openFile(
          item.savedUri,
          item.mimeType,
        );
        if (error != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('باز کردن فایل ممکن نشد: $error')),
          );
        }
        break;
      case 'share':
        await DownloadService.shareFile(item.savedUri, item.mimeType);
        break;
      case 'delete':
        final yes = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('حذف فایل؟'),
            content: Text('«${item.name}» هم از حافظه گوشی و هم از تاریخچه حذف می‌شود.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('انصراف'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: _danger),
                child: Text('حذف'),
              ),
            ],
          ),
        );
        if (yes == true) {
          await DownloadStore.instance.remove(item.id, item.savedUri);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(item.date);
    final dateText = date == null
        ? 'تاریخ نامشخص'
        : '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

    return _CardShell(
      child: Row(
        children: [
          _FileIcon(
            icon: item.mimeType.startsWith('video/')
                ? Icons.movie_rounded
                : item.mimeType.startsWith('audio/')
                    ? Icons.music_note_rounded
                    : item.mimeType.startsWith('image/')
                        ? Icons.image_rounded
                        : Icons.insert_drive_file_rounded,
            color: _success,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 5),
                Text(
                  '${_formatBytes(item.bytes)} • $dateText',
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
                SizedBox(height: 2),
                Text(
                  'ذخیره شده در Downloads',
                  style: TextStyle(color: _success, fontSize: 10),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: _muted),
            color: _surface2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: (value) => _handleAction(context, value),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'open',
                child: Row(
                  children: [
                    Icon(Icons.open_in_new_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('باز کردن'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('اشتراک‌گذاری'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, size: 18, color: _danger),
                    SizedBox(width: 10),
                    Text('حذف', style: TextStyle(color: _danger)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FileIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  _FileIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
        color: color.withOpacity(.11),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;

  _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 9),
      padding: EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(.05)),
      ),
      child: child,
    );
  }
}

class SettingsTab extends StatefulWidget {
  SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'تنظیمات',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _SettingsHeader(
            icon: Icons.settings_suggest_rounded,
            title: 'Floating Downloader',
            subtitle: 'نسخه 3.3 • Android',
          ),
          SizedBox(height: 16),
          _SectionTitle(title: 'ظاهر برنامه'),
          ValueListenableBuilder<bool>(
            valueListenable: ThemeStore.isDark,
            builder: (context, isDark, _) => _SettingSwitchTile(
              icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              title: isDark ? 'تم تاریک' : 'تم روشن',
              subtitle: 'هر وقت خواستید عوضش کنید',
              color: _primary,
              value: isDark,
              onChanged: ThemeStore.setDark,
            ),
          ),
          SizedBox(height: 16),
          _SectionTitle(title: 'دانلود'),
          ValueListenableBuilder<bool>(
            valueListenable: SettingsStore.wifiOnly,
            builder: (context, value, _) => _SettingSwitchTile(
              icon: Icons.wifi_rounded,
              title: 'دانلود فقط با Wi-Fi',
              subtitle: 'برای جلوگیری از مصرف اینترنت موبایل',
              color: _primary,
              value: value,
              onChanged: SettingsStore.setWifiOnly,
            ),
          ),
          _SettingTile(
            icon: Icons.folder_open_rounded,
            title: 'محل ذخیره',
            subtitle: 'Downloads سیستم با MediaStore',
            color: _cyan,
          ),
          _SettingTile(
            icon: Icons.security_rounded,
            title: 'ذخیره‌سازی امن',
            subtitle: 'بدون دسترسی قدیمی به کل حافظه',
            color: _success,
          ),
          _SettingTile(
            icon: Icons.radar_rounded,
            title: 'تشخیص خودکار رسانه',
            subtitle: 'در مرورگر هوشمند فعال است و Referer/Cookie واقعی صفحه را هم برای دانلود ارسال می‌کند.',
            color: _primary,
          ),
          _SettingTile(
            icon: Icons.ios_share_rounded,
            title: 'اشتراک‌گذاری از اپ‌های دیگر',
            subtitle: 'یک لینک را در هر اپی (مرورگر، تلگرام و…) به Floating Downloader Share کنید.',
            color: _cyan,
          ),
          SizedBox(height: 16),
          _SectionTitle(title: 'پشتیبانی'),
          _SettingTile(
            icon: Icons.telegram,
            title: 'کانال رسمی',
            subtitle: '@gard_config',
            color: Color(0xFF2AABEE),
            onTap: () => launchUrl(
              Uri.parse('https://t.me/gard_config'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          _SettingTile(
            icon: Icons.info_outline_rounded,
            title: 'درباره برنامه',
            subtitle: 'نسخه 3.3.0',
            color: _muted,
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Floating Downloader',
              applicationVersion: '3.3.0',
              applicationIcon: Icon(Icons.download_rounded, color: _primary),
              children: [
                Text(
                  'دانلودر اندرویدی با دانلود واقعیِ اعتبارسنجی‌شده (بدون فایل جعلی)، MediaStore، مرورگر داخلی با ارسال Referer/Cookie، دریافت لینک با Share از سایر اپ‌ها، و پنجره شناور.',
                ),
              ],
            ),
          ),
          SizedBox(height: 18),
          Text(
            'نکته: لینک‌های DRM و استریم‌های HLS مثل .m3u8 عمداً به‌عنوان MP4 جعلی ذخیره نمی‌شوند. برای آن‌ها باید پردازش استریم جداگانه پیاده‌سازی شود.',
            style: TextStyle(color: _muted, fontSize: 10, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  _SettingsHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_primary, _cyan]),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          SizedBox(width: 13),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w900)),
              SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: _muted, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _surface,
      elevation: 0,
      margin: EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      child: ListTile(
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(.10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: _muted, fontSize: 10),
        ),
        trailing: onTap == null
            ? null
            : Icon(Icons.chevron_left_rounded, color: _muted),
      ),
    );
  }
}

class _SettingSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool value;
  final ValueChanged<bool> onChanged;

  _SettingSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _surface,
      elevation: 0,
      margin: EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeColor: color,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        secondary: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(.10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: _muted, fontSize: 10),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 6, 4, 9),
      child: Text(
        title,
        style: TextStyle(
          color: _muted,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(38),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: _primary.withOpacity(.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: _primary, size: 38),
            ),
            SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, height: 1.6, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class FloatingUI extends StatefulWidget {
  FloatingUI({super.key});

  @override
  State<FloatingUI> createState() => _FloatingUIState();
}

class _FloatingUIState extends State<FloatingUI> {
  final controller = TextEditingController();
  bool expanded = false;
  bool downloading = false;
  double progress = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text?.trim().isNotEmpty == true) {
      controller.text = data!.text!.trim();
      setState(() {});
    }
  }

  Future<void> _download() async {
    final url = controller.text.trim();
    if (url.isEmpty) return;
    if (DownloadGateService.isLocked) {
      final deepLink = Uri.parse('tg://resolve?domain=${TelegramGateConfig.channelUsername}');
      final webLink = Uri.parse('https://t.me/${TelegramGateConfig.channelUsername}');
      final opened = await launchUrl(deepLink, mode: LaunchMode.externalApplication);
      if (!opened) await launchUrl(webLink, mode: LaunchMode.externalApplication);
      return;
    }
    setState(() {
      downloading = true;
      progress = 0;
    });

    try {
      await DownloadService.download(
        url: url,
        onProgress: (value) {
          if (mounted) setState(() => progress = value);
        },
      );
      if (mounted) {
        setState(() {
          downloading = false;
          progress = 1;
        });
        await DownloadGateService.registerSuccess();
      }
    } catch (_) {
      if (mounted) setState(() => downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: () {
            if (!expanded) _paste();
            setState(() => expanded = !expanded);
          },
          child: AnimatedContainer(
            duration: Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: expanded ? 320 : 60,
            height: expanded ? 184 : 60,
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _surface.withOpacity(.97),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _primary.withOpacity(.75)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.45),
                  blurRadius: 20,
                ),
              ],
            ),
            child: expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.bolt_rounded, color: _cyan, size: 19),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'دانلود سریع',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints(),
                            onPressed: () => setState(() => expanded = false),
                            icon: Icon(Icons.close_rounded, size: 19),
                          ),
                        ],
                      ),
                      SizedBox(height: 7),
                      TextField(
                        controller: controller,
                        textDirection: TextDirection.ltr,
                        maxLines: 1,
                        decoration: InputDecoration(
                          hintText: 'لینک مستقیم فایل',
                          hintTextDirection: TextDirection.ltr,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      if (downloading)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: progress == 0 ? null : progress,
                            minHeight: 5,
                            color: _cyan,
                          ),
                        )
                      else
                        AnimatedBuilder(
                          animation: Listenable.merge([
                            DownloadGateService.successCount,
                            DownloadGateService.verified,
                          ]),
                          builder: (context, _) {
                            final locked = DownloadGateService.isLocked;
                            return SizedBox(
                              height: 40,
                              child: FilledButton.icon(
                                onPressed: _download,
                                style: locked
                                    ? FilledButton.styleFrom(backgroundColor: _cyan)
                                    : null,
                                icon: Icon(
                                  locked ? Icons.telegram : Icons.download_rounded,
                                  size: 18,
                                ),
                                label: Text(locked ? 'عضویت در کانال' : 'دانلود'),
                              ),
                            );
                          },
                        ),
                    ],
                  )
                : Icon(Icons.download_rounded, color: _cyan, size: 28),
          ),
        ),
      ),
    );
  }
}
