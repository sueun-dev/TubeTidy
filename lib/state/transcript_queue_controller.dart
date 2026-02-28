import 'dart:async';
import 'dart:collection';

import '../models/video.dart';

typedef TranscriptTaskRunner = Future<void> Function(Video video);
typedef TranscriptErrorHandler = void Function(Video video, Object error);

class TranscriptQueueController {
  Queue<Video> _queue = Queue<Video>();
  final Set<String> _queuedIds = <String>{};
  bool _isProcessing = false;
  bool _pendingRestart = false;
  int _generation = 0;

  int get generation => _generation;

  void reset() {
    _generation += 1;
    _queue = Queue<Video>();
    _queuedIds.clear();
    _pendingRestart = false;
  }

  bool containsVideoId(String videoId) {
    return _queuedIds.contains(videoId);
  }

  bool enqueue(Video video) {
    if (!_queuedIds.add(video.id)) {
      return false;
    }
    _queue.addLast(video);
    return true;
  }

  Future<void> processQueue({
    required TranscriptTaskRunner runTask,
    required TranscriptErrorHandler onError,
  }) async {
    if (_isProcessing) {
      _pendingRestart = true;
      return;
    }
    _isProcessing = true;
    final generation = _generation;

    while (_queue.isNotEmpty && generation == _generation) {
      final video = _queue.removeFirst();
      _queuedIds.remove(video.id);
      try {
        await runTask(video);
      } catch (error) {
        onError(video, error);
      }
    }

    _isProcessing = false;
    if (_pendingRestart) {
      _pendingRestart = false;
      unawaited(processQueue(
        runTask: runTask,
        onError: onError,
      ));
    }
  }
}
