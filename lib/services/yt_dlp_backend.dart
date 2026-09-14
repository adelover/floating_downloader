import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../state/app_settings.dart';
import 'download_service.dart';

class YtDlpBackendService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 60),
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (status) => status != null && status >= 200 && status < 500,
      headers: const {
        'Accept': 'application/json',
      },
    ),
  );

  static String get baseUrl {
    var value = SettingsStore.ytDlpBackendUrl.value.trim();
    if (value.endsWith('/')) value = value.substring(0, value.length - 1);
    return value;
  }

  static bool get isConfigured => baseUrl.isNotEmpty;

  static Uri _endpoint(String path) {
    if (!isConfigured) {
      throw const YtDlpBackendException(
        'سرویس yt-dlp تنظیم نشده است. آدرس Backend را در تنظیمات برنامه وارد کنید.',
      );
    }
    return Uri.parse('$baseUrl$path');
  }

  static Future<Map<String, dynamic>> getInfo(String url, {String? proxy}) async {
    try {
      final response = await _dio.postUri(
        _endpoint('/api/info'),
        data: {
          'url': url,
          'proxy': (proxy ?? SettingsStore.ytDlpProxy.value).trim(),
        },
        options: Options(responseType: ResponseType.json),
      );
      if ((response.statusCode ?? 500) >= 400) {
        throw YtDlpBackendException(_extractError(response.data));
      }
      final data = response.data;
      if (data is! Map) {
        throw const YtDlpBackendException('پاسخ Backend برای اطلاعات رسانه معتبر نیست.');
      }
      return Map<String, dynamic>.from(data);
    } on DioException catch (e) {
      throw YtDlpBackendException(
        'ارتباط با Backend ناموفق بود: ${e.message ?? 'خطای شبکه'}',
      );
    } on YtDlpBackendException {
      rethrow;
    } catch (e) {
      throw YtDlpBackendException(e.toString());
    }
  }

  /// Downloads the selected yt-dlp format to the Android Downloads folder.
  /// The response is streamed to the app cache, so large files are not kept
  /// entirely in RAM.
  static Future<void> download({
    required String url,
    required String formatId,
    required String preferredName,
    String? proxy,
    void Function(double progress)? onProgress,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    DownloadService.startExternal(id, preferredName);

    String? tempPath;
    try {
      final response = await _dio.postUri<ResponseBody>(
        _endpoint('/api/download'),
        data: {
          'url': url,
          'proxy': (proxy ?? SettingsStore.ytDlpProxy.value).trim(),
          'format_id': formatId,
        },
        options: Options(responseType: ResponseType.stream),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final value = received / total;
            DownloadService.progressExternal(id, value);
            onProgress?.call(value);
          }
        },
      );

      final status = response.statusCode ?? 500;
      if (status >= 400) {
        final body = await _readErrorBody(response.data);
        throw YtDlpBackendException(body);
      }

      final stream = response.data;
      if (stream == null) {
        throw const YtDlpBackendException('Backend فایل دانلودی برنگرداند.');
      }

      final cacheDir = await DownloadService.cacheDirectory();
      final safeId = id.replaceAll(RegExp(r'[^0-9]'), '');
      tempPath = '$cacheDir${Platform.pathSeparator}yt_backend_$safeId.part';
      final file = File(tempPath);
      await file.parent.create(recursive: true);

      final sink = file.openWrite();
      try {
        await stream.stream.pipe(sink);
      } finally {
        await sink.close();
      }

      if (!await file.exists() || await file.length() == 0) {
        throw const YtDlpBackendException('فایل دریافتی از Backend خالی است.');
      }

      final contentDisposition =
          response.headers.value('content-disposition') ?? '';
      final filename = _filenameFromDisposition(contentDisposition) ??
          DownloadService.sanitizeFileName(
            preferredName.trim().isEmpty ? 'Floating_Download' : preferredName,
          );

      final mime = response.headers.value('content-type')?.split(';').first.trim();
      final fallbackMime = DownloadService.mimeFromExtension(
        DownloadService.extensionFromUrl(filename),
      );
      await DownloadService.importExternalFile(
        id: id,
        url: url,
        sourcePath: tempPath,
        fileName: filename,
        mimeType: (mime == null ||
                mime.isEmpty ||
                mime == 'application/octet-stream')
            ? (fallbackMime == 'application/octet-stream'
                ? (formatId == 'bestaudio/best' ? 'audio/mpeg' : 'video/mp4')
                : fallbackMime)
            : mime,
      );
      tempPath = null;
      DownloadService.finishExternal(id);
    } catch (e) {
      DownloadService.failExternal(id);
      if (tempPath != null) {
        await File(tempPath).delete().catchError((_) {});
      }
      if (e is YtDlpBackendException) rethrow;
      if (e is DioException) {
        throw YtDlpBackendException(
          'دانلود از Backend ناموفق بود: ${e.message ?? 'خطای شبکه'}',
        );
      }
      rethrow;
    }
  }

  static String _extractError(Object? data) {
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    if (data is String && data.trim().isNotEmpty) return data.trim();
    return 'Backend خطای نامشخص برگرداند.';
  }

  static Future<String> _readErrorBody(ResponseBody? body) async {
    if (body == null) return 'Backend فایل را با خطا برگرداند.';
    try {
      final bytes = <int>[];
      await for (final chunk in body.stream) {
        bytes.addAll(chunk);
        if (bytes.length > 256 * 1024) break;
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      try {
        return _extractError(jsonDecode(text));
      } catch (_) {
        return text.isEmpty ? 'Backend فایل را با خطا برگرداند.' : text;
      }
    } catch (_) {
      return 'Backend فایل را با خطا برگرداند.';
    }
  }

  static String? _filenameFromDisposition(String header) {
    final match = RegExp(
      r"filename\*=UTF-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(header);
    if (match != null) {
      try {
        return DownloadService.sanitizeFileName(
          Uri.decodeComponent(match.group(1)!),
        );
      } catch (_) {}
    }
    final quoted = RegExp(r'filename="?([^";]+)"?', caseSensitive: false)
        .firstMatch(header);
    if (quoted != null) {
      return DownloadService.sanitizeFileName(quoted.group(1)!.trim());
    }
    return null;
  }
}

class YtDlpBackendException implements Exception {
  final String message;
  const YtDlpBackendException(this.message);
  @override
  String toString() => message;
}
