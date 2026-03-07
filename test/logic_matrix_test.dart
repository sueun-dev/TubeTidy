import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_summary/models/channel.dart';
import 'package:youtube_summary/services/app_services.dart';
import 'package:youtube_summary/services/youtube_api.dart';
import 'package:youtube_summary/state/channel_sync_controller.dart';
import 'package:youtube_summary/state/selection_policy.dart';

class _NoopSelectionService implements SelectionServiceApi {
  @override
  Future<Set<String>?> fetchSelection(String userId) async => <String>{};

  @override
  Future<bool> saveSelection({
    required String userId,
    required List<Channel> channels,
    required Set<String> selectedIds,
  }) async {
    return true;
  }
}

List<String> _idsFromMask(List<String> source, int mask) {
  final ids = <String>[];
  for (var index = 0; index < source.length; index += 1) {
    if ((mask & (1 << index)) != 0) {
      ids.add(source[index]);
    }
  }
  return ids;
}

List<Channel> _channelsFromIds(List<String> ids) {
  return ids
      .map(
        (id) => Channel(
          id: id,
          youtubeChannelId: id,
          title: id,
          thumbnailUrl: '',
        ),
      )
      .toList();
}

Set<String> _expectedNormalizedSelection({
  required List<String> availableIds,
  required List<String> selectedIds,
  required int channelLimit,
}) {
  if (availableIds.isEmpty || channelLimit <= 0 || selectedIds.isEmpty) {
    return <String>{};
  }
  final available = availableIds.toSet();
  final filtered = <String>{};
  for (final selectedId in selectedIds) {
    if (!available.contains(selectedId)) continue;
    filtered.add(selectedId);
    if (filtered.length >= channelLimit) {
      break;
    }
  }
  return filtered;
}

Set<String> _expectedFilteredSelection({
  required List<String> availableIds,
  required List<String> selectedIds,
  required int channelLimit,
}) {
  final available = availableIds.toSet();
  if (channelLimit <= 0) {
    return selectedIds.where(available.contains).toSet();
  }
  final filtered = <String>{};
  for (final selectedId in selectedIds) {
    if (!available.contains(selectedId)) continue;
    filtered.add(selectedId);
    if (filtered.length >= channelLimit) {
      break;
    }
  }
  return filtered;
}

void main() {
  test('channel sync selection matrices cover more than 500 logical cases', () {
    const availablePool = ['c1', 'c2', 'c3', 'c4'];
    const selectedPool = ['c1', 'c2', 'c3', 'c4', 'cx'];
    final controller = ChannelSyncController(
      selectionService: _NoopSelectionService(),
      youtubeApiFactory: (_) => YouTubeApi(authHeaders: const {}),
    );

    var caseCount = 0;
    for (var availableMask = 0;
        availableMask < (1 << availablePool.length);
        availableMask += 1) {
      final availableIds = _idsFromMask(availablePool, availableMask);
      final channels = _channelsFromIds(availableIds);
      for (var selectedMask = 0;
          selectedMask < (1 << selectedPool.length);
          selectedMask += 1) {
        final selectedIds = _idsFromMask(selectedPool, selectedMask);
        final selectedSet = selectedIds.toSet();
        for (var channelLimit = 0; channelLimit <= 5; channelLimit += 1) {
          caseCount += 2;

          expect(
            controller.normalizeSelection(
              channels: channels,
              selectedChannelIds: selectedSet,
              channelLimit: channelLimit,
            ),
            _expectedNormalizedSelection(
              availableIds: availableIds,
              selectedIds: selectedIds,
              channelLimit: channelLimit,
            ),
            reason:
                'normalizeSelection failed for available=$availableIds selected=$selectedIds limit=$channelLimit',
          );

          expect(
            controller.filterServerSelection(
              selected: selectedSet,
              channels: channels,
              channelLimit: channelLimit,
            ),
            _expectedFilteredSelection(
              availableIds: availableIds,
              selectedIds: selectedIds,
              channelLimit: channelLimit,
            ),
            reason:
                'filterServerSelection failed for available=$availableIds selected=$selectedIds limit=$channelLimit',
          );
        }
      }
    }

    expect(caseCount, greaterThanOrEqualTo(500));
  });

  test('pending swap validation matrix covers all state combinations', () {
    const addedIds = <String?>[null, 'c2', 'c9'];
    const removedIds = <String?>[null, 'c1', 'c9'];

    var caseCount = 0;
    for (final selectionCompleted in [false, true]) {
      for (final selectionChangePending in [false, true]) {
        for (final dailySwapAddedId in addedIds) {
          for (final dailySwapRemovedId in removedIds) {
            caseCount += 1;
            final result = SelectionPolicy.validatePendingSwap(
              selectionCompleted: selectionCompleted,
              selectionChangePending: selectionChangePending,
              dailySwapAddedId: dailySwapAddedId,
              dailySwapRemovedId: dailySwapRemovedId,
            );
            final expectedValid = !selectionCompleted ||
                !selectionChangePending ||
                (dailySwapAddedId != null && dailySwapRemovedId != null);
            expect(
              result.isValid,
              expectedValid,
              reason:
                  'validatePendingSwap failed for completed=$selectionCompleted pending=$selectionChangePending added=$dailySwapAddedId removed=$dailySwapRemovedId',
            );
            if (expectedValid) {
              expect(result.toastMessage, isNull);
            } else {
              expect(result.toastMessage, contains('1개 교체'));
            }
          }
        }
      }
    }

    expect(caseCount, 36);
  });
}
