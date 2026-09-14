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

import 'services/download_service.dart';
import 'services/link_parser.dart';
import 'services/native_bridge.dart';
import 'services/platform_extractor.dart';
import 'services/yt_dlp_backend.dart';
import 'controllers/download_queue_controller.dart';
import 'models/download_task.dart';
import 'state/app_settings.dart';
import 'state/download_store.dart';

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
  bool analyzing = false;
  String? clipboardSuggestion;
  MediaInfo? analyzedInfo;
  _PlatformDef? analyzedPlatform;
  String? analyzeError;
  final Set<String> downloadingFormats = {};

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
      final links = LinkParser.extractHttpLinks(text);
      if (links.isEmpty || text == urlController.text) return;
      if (mounted) setState(() => clipboardSuggestion = links.join('\n'));
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

  /// تحلیل واقعی لینک: تشخیص پلتفرم، گرفتن عنوان/کاور/کیفیت‌های واقعی.
  /// این همان چیزی است که جلوی «دانلود فیک» صفحات یوتیوب/اینستاگرام و
  /// مشابه را می‌گیرد؛ هیچ داده‌ای نمایشی یا ساختگی نیست.
  Future<void> _analyzeLink(String url) async {
    setState(() {
      analyzing = true;
      analyzeError = null;
      analyzedInfo = null;
      analyzedPlatform = null;
    });
    try {
      final platform = detectPlatform(url);
      if (platform == null) {
        throw PlatformExtractorException(
          'این لینک متعلق به هیچ‌کدام از پلتفرم‌های پشتیبانی‌شده (یوتیوب، اینستاگرام، تیک‌تاک، ساندکلاود، اسپاتیفای) نیست.',
        );
      }
      final info = await platform.fetch(url);
      if (!mounted) return;
      setState(() {
        analyzedInfo = info;
        analyzedPlatform = platform;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => analyzeError = e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => analyzing = false);
    }
  }

  void _clearAnalysis() {
    setState(() {
      analyzedInfo = null;
      analyzedPlatform = null;
      analyzeError = null;
    });
  }

  Future<void> _downloadAnalyzedFormat(MediaFormat format) async {
    if (!await DownloadGateService.ensureUnlocked(context)) return;
    setState(() => downloadingFormats.add(format.url));
    try {
      if (format.backendFormatId != null) {
        await YtDlpBackendService.download(
          url: analyzedInfo!.sourceUrl,
          formatId: format.backendFormatId!,
          preferredName: analyzedInfo!.title,
        );
      } else {
        await DownloadService.download(
          url: format.url,
          preferredName: analyzedInfo?.title,
          headers: {'Referer': analyzedInfo?.referer ?? ''},
        );
      }
      if (mounted) {
        _message('✓ دانلود کامل شد و در Downloads ذخیره شد.');
        await DownloadGateService.registerSuccessAndMaybeGate(context);
      }
    } catch (e) {
      if (mounted) _message(_friendlyError(e));
    } finally {
      if (mounted) setState(() => downloadingFormats.remove(format.url));
    }
  }

  Future<void> _download() async {
    final links = LinkParser.extractHttpLinks(urlController.text);
    if (links.isEmpty) {
      _message('اول لینک فایل را وارد کنید.');
      return;
    }

    // اگر لینک متعلق به یکی از پلتفرم‌های پشتیبانی‌شده باشد، به‌جای دانلود
    // خام صفحه (که باعث فایل جعلی می‌شد)، تحلیل واقعی انجام می‌شود.
    if (links.length == 1 && detectPlatform(links.first) != null) {
      await _analyzeLink(links.first);
      return;
    }

    if (!await DownloadGateService.ensureUnlocked(context)) return;
    setState(() => downloading = true);
    try {
      var completed = 0;
      for (final url in links) {
        await DownloadService.download(url: url);
        completed++;
      }
      if (mounted) {
        _message('✓ $completed دانلود در Downloads ذخیره شد.');
        urlController.clear();
        await DownloadGateService.registerSuccessAndMaybeGate(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => analyzeError = _friendlyError(e));
        _message('دانلود ناموفق بود؛ دوباره تلاش کنید.');
      }
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
                loading: downloading || analyzing,
                onPaste: _paste,
                onDownload: _download,
              ),
            ),
          ),
          if (analyzeError != null)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              sliver: SliverToBoxAdapter(
                child: Container(
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
                        child: Text(
                          analyzeError!,
                          style: TextStyle(color: _danger, fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: downloading ? null : _download,
                        child: Text('تلاش دوباره'),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                        onPressed: _clearAnalysis,
                        icon: Icon(Icons.close_rounded, size: 16, color: _muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (analyzedInfo != null && analyzedPlatform != null)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              sliver: SliverToBoxAdapter(
                child: _AnalyzedMediaCard(
                  info: analyzedInfo!,
                  platform: analyzedPlatform!,
                  downloadingFormats: downloadingFormats,
                  onDownloadFormat: _downloadAnalyzedFormat,
                  onOpenOriginal: () => launchUrl(
                    Uri.parse(analyzedInfo!.sourceUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  onClose: _clearAnalysis,
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

class _AnalyzedMediaCard extends StatelessWidget {
  final MediaInfo info;
  final _PlatformDef platform;
  final Set<String> downloadingFormats;
  final void Function(MediaFormat format) onDownloadFormat;
  final VoidCallback onOpenOriginal;
  final VoidCallback onClose;

  const _AnalyzedMediaCard({
    required this.info,
    required this.platform,
    required this.downloadingFormats,
    required this.onDownloadFormat,
    required this.onOpenOriginal,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: platform.color.withOpacity(.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(platform.icon, color: platform.color, size: 16),
              SizedBox(width: 6),
              Text(
                platform.title,
                style: TextStyle(
                  color: platform.color,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                ),
              ),
              Spacer(),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, size: 17, color: _muted),
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: info.thumbnailUrl != null
                    ? Image.network(
                        info.thumbnailUrl!,
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 84,
                          height: 84,
                          color: _surface2,
                          child: Icon(platform.icon, color: platform.color),
                        ),
                      )
                    : Container(
                        width: 84,
                        height: 84,
                        color: _surface2,
                        child: Icon(platform.icon, color: platform.color),
                      ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    if (info.author != null) ...[
                      SizedBox(height: 6),
                      Text(
                        info.author!,
                        style: TextStyle(color: _muted, fontSize: 11.5),
                      ),
                    ],
                    if (info.duration != null &&
                        info.duration!.isNotEmpty &&
                        info.duration != 'نامشخص') ...[
                      SizedBox(height: 4),
                      Text(
                        'مدت: ${info.duration}',
                        style: TextStyle(color: _muted, fontSize: 10.5),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          if (!platform.downloadable) ...[
            Text(
              '${platform.title} اجازه‌ی دانلود مستقیم فایل را نمی‌دهد. می‌توانید آن را در اپ اصلی باز کنید.',
              style: TextStyle(color: _muted, fontSize: 11, height: 1.7),
            ),
            SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onOpenOriginal,
                icon: Icon(Icons.open_in_new_rounded, size: 18),
                label: Text('باز کردن در اپ ${platform.title}'),
              ),
            ),
          ] else
            ...info.formats.map((format) {
              final isDownloading = downloadingFormats.contains(format.url);
              return Container(
                margin: EdgeInsets.only(bottom: 8),
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _surface2,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    Icon(
                      format.mimeType.startsWith('audio/')
                          ? Icons.music_note_rounded
                          : format.mimeType.startsWith('image/')
                              ? Icons.image_rounded
                              : Icons.movie_rounded,
                      color: platform.color,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        format.label,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                    FilledButton(
                      onPressed: isDownloading ? null : () => onDownloadFormat(format),
                      style: FilledButton.styleFrom(backgroundColor: platform.color),
                      child: isDownloading
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(Icons.download_rounded, size: 17),
                    ),
                  ],
                ),
              );
            }),
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
                  userAgent: browserUserAgent,
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
  final List<String> hosts;
  final Future<MediaInfo> Function(String url) fetch;

  const _PlatformDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.hint,
    required this.downloadable,
    required this.hosts,
    required this.fetch,
  });
}

final List<_PlatformDef> _platformDefs = [
  _PlatformDef(
    id: 'instagram',
    title: 'اینستاگرام',
    subtitle: 'استخراج واقعی با yt-dlp',
    icon: Icons.camera_alt_rounded,
    color: Color(0xFFE1306C),
    hint: 'لینک پست یا ریلز اینستاگرام را بچسبانید',
    downloadable: true,
    hosts: ['instagram.com'],
    fetch: PlatformExtractor.ytDlp,
  ),
  _PlatformDef(
    id: 'tiktok',
    title: 'تیک‌تاک',
    subtitle: 'استخراج واقعی با yt-dlp',
    icon: Icons.music_video_rounded,
    color: Color(0xFF25F4EE),
    hint: 'لینک ویدیوی تیک‌تاک را بچسبانید',
    downloadable: true,
    hosts: ['tiktok.com'],
    fetch: PlatformExtractor.ytDlp,
  ),
  _PlatformDef(
    id: 'soundcloud',
    title: 'ساندکلاود',
    subtitle: 'استخراج واقعی با yt-dlp',
    icon: Icons.cloud_rounded,
    color: Color(0xFFFF7700),
    hint: 'لینک آهنگ SoundCloud را بچسبانید',
    downloadable: true,
    hosts: ['soundcloud.com', 'snd.sc'],
    fetch: PlatformExtractor.ytDlp,
  ),
  _PlatformDef(
    id: 'youtube',
    title: 'یوتیوب',
    subtitle: 'دانلود و استخراج کیفیت با yt-dlp',
    icon: Icons.smart_display_rounded,
    color: Color(0xFFFF0000),
    hint: 'لینک ویدیوی یوتیوب را بچسبانید',
    downloadable: true,
    hosts: ['youtube.com', 'youtu.be', 'm.youtube.com'],
    fetch: PlatformExtractor.ytDlp,
  ),
  _PlatformDef(
    id: 'spotify',
    title: 'اسپاتیفای',
    subtitle: 'فقط اطلاعات + باز کردن در اپ',
    icon: Icons.headphones_rounded,
    color: Color(0xFF1DB954),
    hint: 'لینک آهنگ/پلی‌لیست اسپاتیفای را بچسبانید',
    downloadable: false,
    hosts: ['open.spotify.com', 'spotify.com', 'spotify.link'],
    fetch: PlatformExtractor.spotifyMeta,
  ),
];

/// تشخیص خودکار اینکه یک لینک مال کدام پلتفرم است (بر اساس دامنه).
_PlatformDef? detectPlatform(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase();
  if (host == null || host.isEmpty) return null;
  for (final def in _platformDefs) {
    if (def.hosts.any((h) => host == h || host.endsWith('.$h'))) return def;
  }
  return null;
}

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
      if (format.backendFormatId != null) {
        await YtDlpBackendService.download(
          url: info!.sourceUrl,
          formatId: format.backendFormatId!,
          preferredName: info!.title,
        );
      } else {
        await DownloadService.download(
          url: format.url,
          preferredName: info?.title,
          headers: {'Referer': info?.referer ?? widget.def.hint},
        );
      }
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
  String category = 'all';

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
        animation: Listenable.merge(
          [DownloadStore.instance, DownloadQueueController.instance],
        ),
        builder: (context, _) {
          final store = DownloadStore.instance;
          final queue = DownloadQueueController.instance;
          final activeTasks = queue.activeTasks.toList();
          if (store.completed.isEmpty && store.active.isEmpty &&
              activeTasks.isEmpty) {
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
                      (e.name.toLowerCase().contains(query.trim().toLowerCase()) || e.url.toLowerCase().contains(query.trim().toLowerCase())))
                  .toList();
          final categorized = filtered.where((item) {
            if (category == 'all') return true;
            if (category == 'video') return item.mimeType.startsWith('video/');
            if (category == 'audio') return item.mimeType.startsWith('audio/');
            return !item.mimeType.startsWith('video/') &&
                !item.mimeType.startsWith('audio/');
          }).toList();

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
              if (store.completed.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: ['all', 'video', 'audio', 'other']
                      .map(
                        (value) => ChoiceChip(
                          label: Text(value),
                          selected: category == value,
                          onSelected: (_) =>
                              setState(() => category = value),
                        ),
                      )
                      .toList(),
                ),
              if (store.active.isNotEmpty || activeTasks.isNotEmpty) ...[
                _SectionTitle(title: 'در حال دانلود'),
                ...activeTasks.map(
                  (task) => _ActiveDownloadCard(
                    id: task.id,
                    name: task.name,
                    progress: task.progress,
                  ),
                ),
                ...store.active.entries
                    .where((entry) => !queue.tasks.containsKey(entry.key))
                    .map(
                  (entry) => _ActiveDownloadCard(
                    id: entry.key,
                    name: store.activeNames[entry.key] ?? 'فایل',
                    progress: entry.value,
                  ),
                ),
                SizedBox(height: 16),
              ],
              if (categorized.isNotEmpty) ...[
                _SectionTitle(title: 'تکمیل‌شده'),
                ...categorized.map((item) => _HistoryCard(item: item)),
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
  final String id;
  final String name;
  final double progress;

  _ActiveDownloadCard({
    required this.id,
    required this.name,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: DownloadQueueController.instance,
      builder: (context, _) {
        final task = DownloadQueueController.instance.tasks[id];
        final paused = task?.status == DownloadTaskStatus.paused;
        final failed = task?.status == DownloadTaskStatus.failed;
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
          IconButton(
            tooltip: failed ? 'تلاش دوباره' : (paused ? 'ادامه' : 'مکث'),
            icon: Icon(
              failed
                  ? Icons.refresh_rounded
                  : (paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
            ),
            onPressed: task == null
                ? null
                : () => failed
                    ? DownloadQueueController.instance.retry(id)
                    : paused
                        ? DownloadQueueController.instance.resume(id)
                        : DownloadQueueController.instance.pause(id),
          ),
          IconButton(
            tooltip: 'لغو',
            icon: Icon(Icons.close_rounded, color: _danger),
            onPressed: () => DownloadQueueController.instance.cancel(id),
          ),
          SizedBox(width: 4),
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
      },
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
  Future<void> _editYtDlpBackend(
    BuildContext context,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('آدرس Backend yt-dlp'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            hintText: 'http://192.168.1.10:8000',
            helperText: 'دستگاه و سرور باید روی یک شبکه یا اینترنت قابل‌دسترسی باشند.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) {
      await SettingsStore.setYtDlpBackendUrl(value);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value.trim().isEmpty
                  ? 'Backend غیرفعال شد.'
                  : 'آدرس Backend ذخیره شد.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _editYtDlpProxy(
    BuildContext context,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Proxy برای yt-dlp'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            hintText: 'http://user:pass@host:port',
            helperText: 'اختیاری — برای درخواست‌های yt-dlp استفاده می‌شود.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) {
      await SettingsStore.setYtDlpProxy(value);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Proxy ذخیره شد.')),
        );
      }
    }
  }

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
            subtitle: 'نسخه 3.6 • Android',
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
          ValueListenableBuilder<int>(
            valueListenable: SettingsStore.maxConcurrent,
            builder: (context, value, _) => _SettingTile(
              icon: Icons.speed_rounded,
              title: 'همزمانی دانلود ($value)',
              subtitle: 'تعداد دانلودهای همزمان (۱ تا ۴)',
              color: _cyan,
              onTap: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => SafeArea(
                  child: Slider(
                    min: 1,
                    max: 4,
                    divisions: 3,
                    value: value.toDouble(),
                    onChanged: (v) =>
                        SettingsStore.setMaxConcurrent(v.round()),
                  ),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: SettingsStore.keepHistory,
            builder: (context, value, _) => _SettingSwitchTile(
              icon: Icons.history_rounded,
              title: 'ذخیره تاریخچه دانلود',
              subtitle: 'ثبت فایل‌های جدید در تاریخچه برنامه',
              color: _success,
              value: value,
              onChanged: SettingsStore.setKeepHistory,
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
          _SectionTitle(title: 'Backend استخراج'),
          ValueListenableBuilder<String>(
            valueListenable: SettingsStore.ytDlpBackendUrl,
            builder: (context, value, _) => _SettingTile(
              icon: Icons.cloud_sync_rounded,
              title: 'سرویس yt-dlp',
              subtitle: value.isEmpty
                  ? 'تنظیم نشده — برای YouTube/TikTok/Instagram/SoundCloud لازم است'
                  : value,
              color: _cyan,
              onTap: () => _editYtDlpBackend(context, value),
            ),
          ),
          ValueListenableBuilder<String>(
            valueListenable: SettingsStore.ytDlpProxy,
            builder: (context, value, _) => _SettingTile(
              icon: Icons.vpn_lock_rounded,
              title: 'Proxy برای yt-dlp',
              subtitle: value.isEmpty ? 'بدون Proxy' : value,
              color: _primary,
              onTap: () => _editYtDlpProxy(context, value),
            ),
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
            subtitle: 'نسخه 3.6.0',
            color: _muted,
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Floating Downloader',
              applicationVersion: '3.6.0',
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
