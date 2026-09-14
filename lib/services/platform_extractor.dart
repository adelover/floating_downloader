import 'dart:convert';

import 'package:dio/dio.dart';

import 'native_bridge.dart';

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
        'User-Agent': browserUserAgent,
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
