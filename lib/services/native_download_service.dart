import 'native_bridge.dart';

/// Optional Android WorkManager backend. The existing Dart queue remains the
/// default; this API is for callers that need downloads to survive UI
/// backgrounding and expose native notification progress.
class NativeDownloadService {
  static Future<String> enqueue({
    required String url,
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async {
    final id = await storageChannel.invokeMethod<String>(
      'enqueueNativeDownload',
      {'url': url, 'fileName': fileName, 'mimeType': mimeType},
    );
    if (id == null || id.isEmpty) {
      throw StateError('Android did not return a native download id.');
    }
    return id;
  }

  static Future<void> pause(String id) =>
      storageChannel.invokeMethod('pauseNativeDownload', {'id': id});

  static Future<void> resume(String id) =>
      storageChannel.invokeMethod('resumeNativeDownload', {'id': id});

  static Future<void> cancel(String id) =>
      storageChannel.invokeMethod('cancelNativeDownload', {'id': id});

  static Future<NativeDownloadStatus> status(String id) async {
    final raw = await storageChannel.invokeMethod<Map<Object?, Object?>>(
      'getNativeDownloadStatus',
      {'id': id},
    );
    final data = raw == null
        ? const <Object?, Object?>{}
        : Map<Object?, Object?>.from(raw);
    return NativeDownloadStatus(
      id: id,
      state: data['state']?.toString() ?? 'queued',
      progress: (data['progress'] as num?)?.toDouble() ?? 0,
      value: data['value']?.toString(),
    );
  }
}

class NativeDownloadStatus {
  const NativeDownloadStatus({
    required this.id,
    required this.state,
    required this.progress,
    this.value,
  });

  final String id;
  final String state;
  final double progress;
  final String? value;
}
