enum DownloadTaskStatus { queued, downloading, paused, failed, completed, cancelled }

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.url,
    required this.name,
    this.status = DownloadTaskStatus.queued,
    this.progress = 0,
    this.attempts = 0,
    this.error,
  });

  final String id;
  final String url;
  final String name;
  DownloadTaskStatus status;
  double progress;
  int attempts;
  String? error;

  bool get canRetry =>
      status == DownloadTaskStatus.failed ||
      status == DownloadTaskStatus.cancelled;
}
