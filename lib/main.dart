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

const _bg = Color(0xFF090B12);
const _surface = Color(0xFF121722);
const _surface2 = Color(0xFF181E2B);
const _primary = Color(0xFF7C5CFF);
const _cyan = Color(0xFF38D9FF);
const _success = Color(0xFF36D399);
const _danger = Color(0xFFFF5D73);
const _muted = Color(0xFF8D96A8);

const _storageChannel = MethodChannel('com.example.floating_downloader/storage');

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Directionality(
    textDirection: TextDirection.rtl,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FloatingUI(),
    ),
  ));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DownloaderApp());
}

class DownloaderApp extends StatelessWidget {
  const DownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _bg,
      fontFamily: 'sans',
      colorScheme: const ColorScheme.dark(
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
          borderSide: const BorderSide(color: _primary, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(
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
        indicatorColor: _primary.withValues(alpha: .18),
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? Colors.white
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
        child: child ?? const SizedBox.shrink(),
      ),
      home: const MainScreen(),
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

  const DownloadItem({
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

class DownloadService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 30),
      sendTimeout: const Duration(seconds: 30),
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

  static Future<DownloadItem> download({
    required String url,
    String? preferredName,
    Map<String, String>? headers,
    void Function(double progress)? onProgress,
  }) async {
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
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/131 Mobile Safari/537.36',
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

      final savedUri = await _saveToDownloads(
        sourcePath: tempPath,
        fileName: fileName,
        mimeType: mimeType,
      );
      final bytes = await file.length();
      await file.delete().catchError((error) => file);

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
      await File(tempPath).delete().catchError((error) => File(tempPath));
      rethrow;
    }
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int index = 0;

  final pages = const [
    HomeTab(),
    BrowserTab(),
    HistoryTab(),
    SettingsTab(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DownloadStore.instance.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard_rounded),
            label: 'خانه',
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

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final urlController = TextEditingController();
  bool overlayActive = false;
  bool downloading = false;

  @override
  void initState() {
    super.initState();
    _refreshOverlay();
  }

  @override
  void dispose() {
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
      await Future<void>.delayed(const Duration(milliseconds: 350));
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
    setState(() => downloading = true);
    try {
      final item = await DownloadService.download(url: url);
      if (mounted) {
        _message('✓ ${item.name} در Downloads ذخیره شد.');
        urlController.clear();
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
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
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
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
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
            padding: const EdgeInsets.symmetric(horizontal: 20),
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
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
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
                  accent: const Color(0xFF2AABEE),
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
      MaterialPageRoute(builder: (_) => const BrowserTab(fullscreen: true)),
    );
  }

  void _openDownloads(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoryTab(fullscreen: true)),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget trailing;

  const _Header({
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
            gradient: const LinearGradient(
              colors: [_primary, _cyan],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
          ),
          child: const Icon(Icons.download_rounded, color: Colors.white),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
        trailing,
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onPaste;
  final VoidCallback onDownload;

  const _HeroCard({
    required this.controller,
    required this.loading,
    required this.onPaste,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [
            _surface2,
            _primary.withValues(alpha: .10),
            _surface,
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: .08),
            blurRadius: 30,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt_rounded, color: _cyan),
              SizedBox(width: 8),
              Text(
                'دانلود مستقیم',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'لینک مستقیم فایل را وارد کنید. فایل پس از دانلود واقعی داخل Downloads ذخیره می‌شود.',
            style: TextStyle(color: _muted, height: 1.5, fontSize: 12),
          ),
          const SizedBox(height: 16),
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
                icon: const Icon(Icons.content_paste_rounded),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
This Flutter source code implements a comprehensive media downloader featuring an in-app browser, system-level file saving, and a persistent floating overlay window[span_1](start_span)[span_1](end_span). Building on your background in developing media extraction tools, this mobile architecture provides a robust, user-friendly frontend while smartly routing the official `@gard_config` Telegram community directly into the app's ecosystem[span_2](start_span)[span_2](end_span).

**Core Architecture & Features**
*   **Smart Media Detection:** The `BrowserTab` uses `InAppWebView` to intercept network requests, automatically identifying downloadable media resources while users browse[span_3](start_span)[span_3](end_span).
*   **Floating UI:** Leverages `flutter_overlay_window` to render a globally accessible download widget over other Android applications, allowing quick URL pasting and downloading without opening the main app[span_4](start_span)[span_4](end_span).
*   **Native Storage Integration:** Bypasses legacy storage constraints by using a custom `MethodChannel` (`com.example.floating_downloader/storage`) to write files directly to Android's `MediaStore` Downloads directory[span_5](start_span)[span_5](end_span).
*   **State Management:** Utilizes a custom singleton `ChangeNotifier` (`DownloadStore`) backed by `SharedPreferences` to persist completed downloads across app restarts[span_6](start_span)[span_6](end_span).

**Dependency Breakdown**

| Module | Package | Implementation Purpose |
| :--- | :--- | :--- |
| **Networking** | `dio` | Manages HTTP requests, stream chunking, and precise download progress tracking[span_7](start_span)[span_7](end_span). |
| **Web View** | `flutter_inappwebview` | Renders external sites and intercepts asset URLs via `shouldInterceptRequest` and `onLoadResource`[span_8](start_span)[span_8](end_span). |
| **Persistence** | `shared_preferences` | Serializes the `DownloadItem` history objects into JSON strings for local storage[span_9](start_span)[span_9](end_span). |
| **System Overlay** | `flutter_overlay_window` | Manages the permissions and rendering lifecycle for the `FloatingUI` widget[span_10](start_span)[span_10](end_span). |

**Refinement Opportunities**
*   **HLS Stream Processing:** The current `DownloadService` explicitly throws an exception for `.m3u8` HLS streams[span_11](start_span)[span_11](end_span). Integrating `ffmpeg_kit_flutter` could allow you to download and multiplex these segmented streams into standard MP4s directly on the device.
*   **Isolate Spawning:** For extremely large files, `Dio` downloads running on the main UI isolate might cause slight frame drops. Moving the heavy I/O operations of the `DownloadService` into a separate Dart Isolate would keep the 60fps/120fps UI perfectly smooth during heavy network activity.
*   **Channel Error Handling:** Ensure the native Kotlin/Java side of your `saveToDownloads` method channel gracefully handles Android 11+ Scoped Storage edge cases, as uncaught native exceptions during `MediaStore` operations can crash the Flutter engine[span_12](start_span)[span_12](end_span).
