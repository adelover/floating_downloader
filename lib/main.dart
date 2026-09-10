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
        indicatorColor: _primary.withOpacity(.18),
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
            child: FilledButton.icon(
              onPressed: loading ? null : onDownload,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(loading ? 'در حال دانلود…' : 'شروع دانلود'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
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

  const _StatsRow({required this.active, required this.completed});

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
        const SizedBox(width: 12),
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

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
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

  const _QuickCard({
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
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: Colors.white.withOpacity(.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent, size: 25),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 10, height: 1.35),
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

  const BrowserTab({super.key, this.fullscreen = false});

  @override
  State<BrowserTab> createState() => _BrowserTabState();
}

class _BrowserTabState extends State<BrowserTab> {
  InAppWebViewController? webView;
  final addressController = TextEditingController(text: 'https://www.google.com');
  double progress = 0;
  bool loading = true;
  final List<String> detected = [];

  @override
  void dispose() {
    addressController.dispose();
    super.dispose();
  }

  void _addDetected(String url) {
    if (!DownloadService.looksLikeMedia(url)) return;
    if (DownloadService.isHls(url)) return;
    if (detected.contains(url)) return;
    if (!mounted) return;
    setState(() {
      detected.insert(0, url);
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

  Future<void> _downloadDetected(String url) async {
    Navigator.of(context).maybePop();
    try {
      await DownloadService.download(url: url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ دانلود کامل شد و در Downloads ذخیره شد.')),
        );
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * .72,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
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
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(Icons.radar_rounded, color: _cyan),
                    const SizedBox(width: 9),
                    const Expanded(
                      child: Text(
                        'رسانه‌های پیدا شده',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ),
                    Text(
                      '${detected.length}',
                      style: const TextStyle(color: _muted),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView.separated(
                    itemCount: detected.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final url = detected[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _surface2,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Color(0x1A38D9FF),
                              child: Icon(Icons.movie_rounded, color: _cyan),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                url,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => _downloadDetected(url),
                              icon: const Icon(Icons.download_rounded),
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
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              if (widget.fullscreen)
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              IconButton(
                onPressed: () => webView?.goBack(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              ),
              IconButton(
                onPressed: () => webView?.goForward(),
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
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
                    prefixIcon: const Icon(Icons.language_rounded, size: 20),
                    suffixIcon: IconButton(
                      onPressed: () => _navigate(addressController.text),
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => webView?.reload(),
                icon: const Icon(Icons.refresh_rounded),
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
                ),
                onWebViewCreated: (controller) => webView = controller,
                onLoadStart: (controller, url) {
                  if (!mounted) return;
                  setState(() {
                    loading = true;
                    progress = 0;
                    if (url != null) addressController.text = url.toString();
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
                const Center(
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
              title: const Text(
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
              icon: const Icon(Icons.download_rounded),
              label: Text('${detected.length} رسانه'),
            ),
    );
  }
}

class HistoryTab extends StatelessWidget {
  final bool fullscreen;

  const HistoryTab({super.key, this.fullscreen = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: fullscreen
            ? IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : null,
        title: const Text(
          'دانلودهای من',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.transparent,
        actions: [
          AnimatedBuilder(
            animation: DownloadStore.instance,
            builder: (_, __) => DownloadStore.instance.completed.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'پاک کردن تاریخچه',
                    onPressed: () => _confirmClear(context),
                    icon: const Icon(Icons.delete_sweep_rounded),
                  ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: DownloadStore.instance,
        builder: (context, _) {
          final store = DownloadStore.instance;
          if (store.completed.isEmpty && store.active.isEmpty) {
            return const _EmptyState(
              icon: Icons.download_for_offline_rounded,
              title: 'هنوز دانلودی ندارید',
              subtitle: 'از صفحه خانه لینک مستقیم بدهید یا از مرورگر یک رسانه پیدا کنید.',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
            children: [
              if (store.active.isNotEmpty) ...[
                const _SectionTitle(title: 'در حال دانلود'),
                ...store.active.entries.map(
                  (entry) => _ActiveDownloadCard(
                    name: store.activeNames[entry.key] ?? 'فایل',
                    progress: entry.value,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (store.completed.isNotEmpty) ...[
                const _SectionTitle(title: 'تکمیل‌شده'),
                ...store.completed.map((item) => _HistoryCard(item: item)),
              ],
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
        title: const Text('پاک کردن تاریخچه؟'),
        content: const Text('فقط تاریخچه داخل برنامه حذف می‌شود؛ فایل‌های Downloads پاک نمی‌شوند.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('پاک کردن'),
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

  const _ActiveDownloadCard({
    required this.name,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Row(
        children: [
          const _FileIcon(icon: Icons.downloading_rounded, color: _cyan),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
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
          const SizedBox(width: 10),
          Text(
            '${(progress * 100).round()}%',
            style: const TextStyle(
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

  const _HistoryCard({required this.item});

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
                    : Icons.insert_drive_file_rounded,
            color: _success,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  '${_formatBytes(item.bytes)} • $dateText',
                  style: const TextStyle(color: _muted, fontSize: 10),
                ),
                const SizedBox(height: 2),
                const Text(
                  'ذخیره شده در Downloads',
                  style: TextStyle(color: _success, fontSize: 10),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: _success, size: 21),
        ],
      ),
    );
  }
}

class _FileIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _FileIcon({required this.icon, required this.color});

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

  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
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
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'تنظیمات',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _SettingsHeader(
            icon: Icons.settings_suggest_rounded,
            title: 'Floating Downloader',
            subtitle: 'نسخه 3.0 • Android',
          ),
          const SizedBox(height: 16),
          const _SectionTitle(title: 'دانلود'),
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
            subtitle: 'در مرورگر هوشمند فعال است و لینک‌های مستقیم را بررسی می‌کند.',
            color: _primary,
          ),
          const SizedBox(height: 16),
          const _SectionTitle(title: 'پشتیبانی'),
          _SettingTile(
            icon: Icons.telegram,
            title: 'کانال رسمی',
            subtitle: '@gard_config',
            color: const Color(0xFF2AABEE),
            onTap: () => launchUrl(
              Uri.parse('https://t.me/gard_config'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          _SettingTile(
            icon: Icons.info_outline_rounded,
            title: 'درباره برنامه',
            subtitle: 'نسخه 3.0.0',
            color: _muted,
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Floating Downloader',
              applicationVersion: '3.0.0',
              applicationIcon: const Icon(Icons.download_rounded, color: _primary),
              children: const [
                Text(
                  'دانلودر اندرویدی با دانلود واقعی، MediaStore، مرورگر داخلی و پنجره شناور.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
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

  const _SettingsHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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
              gradient: const LinearGradient(colors: [_primary, _cyan]),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 13),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: _muted, fontSize: 11)),
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

  const _SettingTile({
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
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(.10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: _muted, fontSize: 10),
        ),
        trailing: onTap == null
            ? null
            : const Icon(Icons.chevron_left_rounded, color: _muted),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 9),
      child: Text(
        title,
        style: const TextStyle(
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

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(38),
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
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, height: 1.6, fontSize: 11),
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
  const FloatingUI({super.key});

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
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: expanded ? 320 : 60,
            height: expanded ? 184 : 60,
            padding: const EdgeInsets.all(10),
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
                          const Icon(Icons.bolt_rounded, color: _cyan, size: 19),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'دانلود سریع',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => setState(() => expanded = false),
                            icon: const Icon(Icons.close_rounded, size: 19),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      TextField(
                        controller: controller,
                        textDirection: TextDirection.ltr,
                        maxLines: 1,
                        decoration: const InputDecoration(
                          hintText: 'لینک مستقیم فایل',
                          hintTextDirection: TextDirection.ltr,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
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
                        SizedBox(
                          height: 40,
                          child: FilledButton.icon(
                            onPressed: _download,
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('دانلود'),
                          ),
                        ),
                    ],
                  )
                : const Icon(Icons.download_rounded, color: _cyan, size: 28),
          ),
        ),
      ),
    );
  }
}
