import 'package:flutter_test/flutter_test.dart';
import 'package:floating_downloader/models/download_task.dart';
import 'package:floating_downloader/services/download_service.dart';
import 'package:floating_downloader/services/link_parser.dart';

void main() {
  group('DownloadService helpers', () {
    test('extracts unique links from pasted text', () {
      expect(
        LinkParser.extractHttpLinks(
          'See https://example.com/a.mp4 and https://example.com/a.mp4, '
          'then https://example.com/b.mp3.',
        ),
        ['https://example.com/a.mp4', 'https://example.com/b.mp3'],
      );
    });
    test('sanitizes invalid Android file characters', () {
      expect(
        DownloadService.sanitizeFileName('a:/b?c*'),
        'a__b_c_',
      );
    });

    test('removes control characters, trailing dots, and device names', () {
      expect(DownloadService.sanitizeFileName('  con.  '), '_con');
      expect(DownloadService.sanitizeFileName('a\u0000b...'), 'a_b');
      expect(DownloadService.sanitizeFileName('../video.mp4'), '.._video.mp4');
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

  test('download task exposes retry only for recoverable states', () {
    final task = DownloadTask(id: '1', url: 'https://example.com', name: 'x');
    expect(task.canRetry, isFalse);
    task.status = DownloadTaskStatus.failed;
    expect(task.canRetry, isTrue);
    task.status = DownloadTaskStatus.cancelled;
    expect(task.canRetry, isTrue);
  });
}
