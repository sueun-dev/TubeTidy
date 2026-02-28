import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_summary/models/video.dart';
import 'package:youtube_summary/state/transcript_queue_controller.dart';

Video _video(String id) {
  return Video(
    id: id,
    youtubeId: id,
    channelId: 'channel-$id',
    title: 'Video $id',
    publishedAt: DateTime(2026, 1, 1),
    thumbnailUrl: '',
  );
}

void main() {
  test('enqueue prevents duplicate ids', () {
    final controller = TranscriptQueueController();

    final first = controller.enqueue(_video('v1'));
    final second = controller.enqueue(_video('v1'));

    expect(first, isTrue);
    expect(second, isFalse);
    expect(controller.containsVideoId('v1'), isTrue);
  });

  test('reset clears queue and advances generation', () async {
    final controller = TranscriptQueueController();
    controller.enqueue(_video('v1'));
    final before = controller.generation;

    controller.reset();
    final after = controller.generation;

    expect(after, before + 1);
    expect(controller.containsVideoId('v1'), isFalse);

    final processed = <String>[];
    await controller.processQueue(
      runTask: (video) async {
        processed.add(video.id);
      },
      onError: (_, __) {},
    );
    expect(processed, isEmpty);
  });

  test('processQueue runs all tasks and reports task errors', () async {
    final controller = TranscriptQueueController();
    controller.enqueue(_video('v1'));
    controller.enqueue(_video('v2'));
    controller.enqueue(_video('v3'));

    final processed = <String>[];
    final failed = <String>[];

    await controller.processQueue(
      runTask: (video) async {
        processed.add(video.id);
        if (video.id == 'v2') {
          throw StateError('boom');
        }
      },
      onError: (video, error) {
        failed.add(video.id);
      },
    );

    expect(processed, ['v1', 'v2', 'v3']);
    expect(failed, ['v2']);
  });

  test('processed video can be enqueued again', () async {
    final controller = TranscriptQueueController();
    controller.enqueue(_video('v1'));

    await controller.processQueue(
      runTask: (_) async {},
      onError: (_, __) {},
    );

    final secondEnqueue = controller.enqueue(_video('v1'));
    expect(secondEnqueue, isTrue);
  });

  test('concurrent processQueue call schedules restart safely', () async {
    final controller = TranscriptQueueController();
    controller.enqueue(_video('v1'));

    final startedFirst = Completer<void>();
    final releaseFirst = Completer<void>();
    final processed = <String>[];

    Future<void> runTask(Video video) async {
      processed.add(video.id);
      if (video.id == 'v1') {
        if (!startedFirst.isCompleted) {
          startedFirst.complete();
        }
        await releaseFirst.future;
      }
    }

    final firstRun = controller.processQueue(
      runTask: runTask,
      onError: (_, __) {},
    );

    await startedFirst.future;
    controller.enqueue(_video('v2'));

    await controller.processQueue(
      runTask: runTask,
      onError: (_, __) {},
    );

    releaseFirst.complete();
    await firstRun;
    await Future<void>.delayed(Duration.zero);

    expect(processed, containsAllInOrder(['v1', 'v2']));
  });
}
