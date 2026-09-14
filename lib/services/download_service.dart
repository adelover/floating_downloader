import 'dart:io';

import 'package:dio/dio.dart';

import '../controllers/download_queue_controller.dart';
import '../state/app_settings.dart';
import '../state/download_store.dart';
import 'native_bridge.dart';

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
    final path = await storageChannel.invokeMethod<String>('getCacheDirectory');
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
    final result = await storageChannel.invokeMethod<String>(
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
    // MediaStore rejects path separators, control characters, and Windows
    // device names even on newer Android versions.
    var name = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    name = name.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '_');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    name = name.replaceAll(RegExp(r'[. ]+$'), '');
    if (name.isEmpty) name = 'Floating_Download';
    if (RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$',
            caseSensitive: false)
        .hasMatch(name)) {
      name = '_$name';
    }
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
    String decoded;
    try {
      decoded = Uri.decodeComponent(last);
    } catch (_) {
      decoded = last;
    }
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
      return await storageChannel.invokeMethod<bool>('isWifiConnected') ??
          true;
    } catch (_) {
      return true;
    }
  }

  static Future<String?> openFile(String uri, String mimeType) async {
    try {
      return await storageChannel.invokeMethod<String>(
        'openFile',
        {'uri': uri, 'mimeType': mimeType},
      );
    } catch (e) {
      return e.toString();
    }
  }

  static Future<void> shareFile(String uri, String mimeType) async {
    try {
      await storageChannel.invokeMethod('shareFile', {
        'uri': uri,
        'mimeType': mimeType,
      });
    } catch (_) {}
  }

  static Future<void> deleteFile(String uri) async {
    try {
      await storageChannel.invokeMethod('deleteFile', {'uri': uri});
    } catch (_) {}
  }

  static Future<DownloadItem> download({
    required String url,
    String? preferredName,
    Map<String, String>? headers,
    void Function(double progress)? onProgress,
  }) {
    return DownloadQueueController.instance.enqueue(
      url: url,
      preferredName: preferredName,
      headers: headers,
      onProgress: onProgress,
    );
  }

  /// Performs one queue entry. Callers should use [download], which applies
  /// concurrency limits and exposes pause/resume/cancel controls.
  static Future<DownloadItem> downloadNow({
    required String id,
    required String url,
    String? preferredName,
    Map<String, String>? headers,
    void Function(double progress)? onProgress,
    bool registerStore = true,
    void Function(void Function(String reason) cancel)? onCancel,
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

    if (registerStore) DownloadStore.instance.start(id, fileName);
    final cancelToken = CancelToken();
    onCancel?.call((reason) {
      cancelToken.cancel(reason);
    });

    try {
      final response = await _dio.download(
        cleanUrl,
        tempPath,
        options: Options(
          headers: {
            'Accept': '*/*',
            'User-Agent': browserUserAgent,
            ...?headers,
          },
        ),
        deleteOnError: true,
        cancelToken: cancelToken,
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
      if (SettingsStore.keepHistory.value) {
        await DownloadStore.instance.add(item);
      }
      if (registerStore) DownloadStore.instance.finish(id);
      return item;
    } catch (error) {
      if (registerStore) DownloadStore.instance.fail(id);
      await File(tempPath).delete().catchError((_) {});
      rethrow;
    }
  }
}
