import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/download_task.dart';
import '../services/download_service.dart';
import '../state/app_settings.dart';

/// Coordinates downloads without allowing an unbounded number of network
/// requests. Work continues when the Flutter UI is backgrounded.
class DownloadQueueController extends ChangeNotifier {
  DownloadQueueController._() {
    SettingsStore.maxConcurrent.addListener(_onConcurrencyChanged);
  }
  static final instance = DownloadQueueController._();

  final Map<String, DownloadTask> tasks = {};
  final Map<String, Future<void>> _running = {};
  final Map<String, _QueuedRequest> _requests = {};

  void _onConcurrencyChanged() {
    _pump();
  }

  Iterable<DownloadTask> get activeTasks => tasks.values.where((task) =>
      task.status == DownloadTaskStatus.downloading ||
      task.status == DownloadTaskStatus.queued ||
      task.status == DownloadTaskStatus.paused ||
      task.status == DownloadTaskStatus.failed);

  Future<DownloadItem> enqueue({
    required String url,
    String? preferredName,
    Map<String, String>? headers,
    void Function(double progress)? onProgress,
  }) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final task = DownloadTask(
      id: id,
      url: url,
      name: preferredName?.trim().isNotEmpty == true
          ? preferredName!.trim()
          : DownloadService.fileNameFromUrl(url),
    );
    final request = _QueuedRequest(
      task: task,
      preferredName: preferredName,
      headers: headers,
      onProgress: onProgress,
    );
    tasks[id] = task;
    _requests[id] = request;
    notifyListeners();
    _pump();
    return request.result.future;
  }

  void pause(String id) {
    final request = _requests[id];
    if (request == null) return;
    request.paused = true;
    if (tasks[id]?.status == DownloadTaskStatus.queued) {
      tasks[id]!.status = DownloadTaskStatus.paused;
      notifyListeners();
    } else {
      request.cancel?.call('paused');
    }
  }

  void resume(String id) {
    final request = _requests[id];
    final task = tasks[id];
    if (request == null || task == null || !request.paused) return;
    request.paused = false;
    if (task.status == DownloadTaskStatus.paused) {
      task.status = DownloadTaskStatus.queued;
      notifyListeners();
      _pump();
    }
  }

  void cancel(String id) {
    final request = _requests[id];
    final task = tasks[id];
    if (request == null || task == null) return;
    final wasNotRunning = task.status == DownloadTaskStatus.queued ||
        task.status == DownloadTaskStatus.paused;
    request.cancel?.call('cancelled');
    task.status = DownloadTaskStatus.cancelled;
    if (wasNotRunning) {
      request.result.completeError(StateError('Download cancelled'));
      _requests.remove(id);
      notifyListeners();
      _pump();
    }
  }

  void retry(String id) {
    final request = _requests[id];
    final task = tasks[id];
    if (request == null || task == null || !task.canRetry) return;
    task.status = DownloadTaskStatus.queued;
    task.error = null;
    request.paused = false;
    notifyListeners();
    _pump();
  }

  void _pump() {
    while (_running.length < SettingsStore.maxConcurrent.value) {
      _QueuedRequest? request;
      for (final candidate in _requests.values) {
        if (!candidate.paused &&
            candidate.task.status == DownloadTaskStatus.queued &&
            !_running.containsKey(candidate.task.id)) {
          request = candidate;
          break;
        }

        @override
        void dispose() {
          SettingsStore.maxConcurrent.removeListener(_onConcurrencyChanged);
          super.dispose();
        }
      }
      if (request == null) return;
      final future = _run(request);
      _running[request.task.id] = future;
      future.whenComplete(() {
        _running.remove(request.task.id);
        _pump();
      });
    }
  }

  Future<void> _run(_QueuedRequest request) async {
    final task = request.task;
    task.status = DownloadTaskStatus.downloading;
    task.attempts++;
    notifyListeners();
    try {
      final item = await DownloadService.downloadNow(
        id: task.id,
        url: request.url,
        preferredName: request.preferredName,
        headers: request.headers,
        onProgress: (value) {
          task.progress = value;
          request.onProgress?.call(value);
          notifyListeners();
        },
        registerStore: true,
        onCancel: (cancel) => request.cancel = cancel,
      );
      task.status = DownloadTaskStatus.completed;
      task.progress = 1;
      if (!request.result.isCompleted) request.result.complete(item);
    } catch (error) {
      if (request.paused) {
        task.status = DownloadTaskStatus.paused;
      } else if (task.status == DownloadTaskStatus.cancelled) {
        if (!request.result.isCompleted) {
          request.result.completeError(StateError('Download cancelled'));
        }
      } else if (task.status != DownloadTaskStatus.cancelled) {
        task.status = DownloadTaskStatus.failed;
        task.error = error.toString();
        if (!request.result.isCompleted) request.result.completeError(error);
      }
      notifyListeners();
    } finally {
      request.cancel = null;
      notifyListeners();
    }
  }
}

class _QueuedRequest {
  _QueuedRequest({
    required this.task,
    this.preferredName,
    this.headers,
    this.onProgress,
  });

  final DownloadTask task;
  final String? preferredName;
  final Map<String, String>? headers;
  final void Function(double progress)? onProgress;
  final Completer<DownloadItem> result = Completer<DownloadItem>();
  bool paused = false;
  String get url => task.url;
  void Function(String reason)? cancel;
}
