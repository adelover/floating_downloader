import 'package:flutter_test/flutter_test.dart';
import 'package:floating_downloader/main.dart';

void main() {
  group('DownloadService helpers', () {
    test('sanitizes invalid Android file characters', () {
      expect(
        DownloadService.sanitizeFileName('a:/b?c*'),
        'a__b_c_',
      );
    });

    test('detects HLS links', () {
      expect(
        DownloadService.isHls('https://cdn.example.com/master.m3u8?token=1'),
        isTrue,
      );
    });

    test('detects direct media links', () {
      expect(
        DownloadService.looksLikeMedia('https://cdn.example.com/video.mp4?x=1'),
        isTrue,
      );
    });

    test('maps common extensions to MIME types', () {
      expect(DownloadService.mimeFromExtension('.mp4'), 'video/mp4');
      expect(DownloadService.mimeFromExtension('.mp3'), 'audio/mpeg');
      expect(
        DownloadService.mimeFromExtension('.unknown'),
        'application/octet-stream',
      );
    });
  });
}
