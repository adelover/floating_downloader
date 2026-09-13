import 'dart:io';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

class MediaInfo {
  final String title;
  final String thumbnailUrl;
  final String platform;
  final List<MediaStreamOption> options;

  MediaInfo({
    required this.title,
    required this.thumbnailUrl,
    required this.platform,
    required this.options,
  });
}

class MediaStreamOption {
  final String qualityLabel;
  final String container;
  final dynamic streamData;

  MediaStreamOption({
    required this.qualityLabel,
    required this.container,
    required this.streamData,
  });
}

class DownloadService {
  final Dio _dio = Dio();
  final yt.YoutubeExplode _ytExplode = yt.YoutubeExplode();

  Future<MediaInfo> analyzeUrl(String inputUrl) async {
    final uri = Uri.parse(inputUrl.trim());
    final host = uri.host.toLowerCase();

    if (host.contains('youtube.com') || host.contains('youtu.be')) {
      return await _analyzeYoutube(inputUrl);
    } else if (host.contains('instagram.com')) {
      return MediaInfo(
        title: "محتوای اینستاگرام",
        thumbnailUrl: "https://cdn-icons-png.flaticon.com/512/174/174855.png",
        platform: "Instagram",
        options: [
          MediaStreamOption(qualityLabel: "کیفیت اصلی ویدیو", container: "mp4", streamData: inputUrl),
        ],
      );
    } else if (host.contains('soundcloud.com')) {
      return MediaInfo(
        title: "تراک صوتی ساندکلود",
        thumbnailUrl: "https://cdn-icons-png.flaticon.com/512/145/145809.png",
        platform: "SoundCloud",
        options: [
          MediaStreamOption(qualityLabel: "کیفیت اصلی MP3", container: "mp3", streamData: inputUrl),
        ],
      );
    } else if (host.contains('spotify.com')) {
      return MediaInfo(
        title: "موزیک اسپاتیفای",
        thumbnailUrl: "https://cdn-icons-png.flaticon.com/512/174/174872.png",
        platform: "Spotify",
        options: [
          MediaStreamOption(qualityLabel: "استخراج فایل صوتی", container: "mp3", streamData: inputUrl),
        ],
      );
    } else {
      throw Exception("لینک پشتیبانی نمی‌شود یا نامعتبر است.");
    }
  }

  Future<MediaInfo> _analyzeYoutube(String url) async {
    final video = await _ytExplode.videos.get(url);
    final manifest = await _ytExplode.videos.streamsClient.getManifest(video.id);

    List<MediaStreamOption> options = [];

    for (var stream in manifest.muxed) {
      options.add(MediaStreamOption(
        qualityLabel: "${stream.qualityLabel} (${(stream.size.totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB)",
        container: stream.container.name,
        streamData: stream,
      ));
    }

    final audioStream = manifest.audioOnly.withHighestBitrate();
    options.add(MediaStreamOption(
      qualityLabel: "فقط صوت - MP3 (${audioStream.bitrate.kiloBitsPerSecond} kbps)",
      container: "mp3",
      streamData: audioStream,
    ));

    return MediaInfo(
      title: video.title,
      thumbnailUrl: video.thumbnails.highResUrl,
      platform: "YouTube",
      options: options,
    );
  }

  Future<void> downloadFile({
    required MediaStreamOption option,
    required String title,
    required Function(int count, int total) onProgress,
  }) async {
    await Permission.storage.request();
    await Permission.photos.request();

    final tempDir = await getTemporaryDirectory();
    final cleanTitle = title.replaceAll(RegExp(r'[^\w\s]+'), '_');
    final filePath = '${tempDir.path}/$cleanTitle.${option.container}';

    if (option.streamData is yt.StreamInfo) {
      final streamInfo = option.streamData as yt.StreamInfo;
      final stream = _ytExplode.videos.streamsClient.get(streamInfo);
      final file = File(filePath);
      final fileStream = file.openWrite();

      int downloaded = 0;
      final total = streamInfo.size.totalBytes;

      await for (final data in stream) {
        downloaded += data.length;
        fileStream.add(data);
        onProgress(downloaded, total);
      }
      await fileStream.flush();
      await fileStream.close();
    } else if (option.streamData is String) {
      await _dio.download(
        option.streamData,
        filePath,
        onReceiveProgress: onProgress,
      );
    }

    if (option.container == 'mp4') {
      await Gal.putVideo(filePath);
    } else {
      await Gal.putImage(filePath);
    }
  }

  void dispose() {
    _ytExplode.close();
  }
}
