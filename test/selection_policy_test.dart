import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_summary/state/selection_policy.dart';

void main() {
  test('allows adding channel when completed and free slot exists', () {
    final outcome = SelectionPolicy.toggle(
      const SelectionPolicyInput(
        channelId: 'c2',
        selectedChannelIds: {'c1'},
        channelLimit: 3,
        selectionCompleted: true,
        selectionChangePending: false,
        dailySwapAddedId: null,
        dailySwapRemovedId: null,
        canChangeSelectionToday: true,
      ),
    );

    expect(outcome.changed, isTrue);
    expect(outcome.selectedChannelIds, {'c1', 'c2'});
    expect(outcome.selectionChangePending, isFalse);
    expect(outcome.dailySwapAddedId, isNull);
    expect(outcome.dailySwapRemovedId, isNull);
  });

  test('blocks swap when daily change was already used', () {
    final outcome = SelectionPolicy.toggle(
      const SelectionPolicyInput(
        channelId: 'c2',
        selectedChannelIds: {'c1'},
        channelLimit: 1,
        selectionCompleted: true,
        selectionChangePending: false,
        dailySwapAddedId: null,
        dailySwapRemovedId: null,
        canChangeSelectionToday: false,
      ),
    );

    expect(outcome.changed, isFalse);
    expect(outcome.toastMessage, contains('오늘은 채널 변경을 이미 1회 사용했습니다'));
  });

  test('starts pending swap on remove from completed selection', () {
    final outcome = SelectionPolicy.toggle(
      const SelectionPolicyInput(
        channelId: 'c1',
        selectedChannelIds: {'c1', 'c2'},
        channelLimit: 3,
        selectionCompleted: true,
        selectionChangePending: false,
        dailySwapAddedId: null,
        dailySwapRemovedId: null,
        canChangeSelectionToday: true,
      ),
    );

    expect(outcome.changed, isTrue);
    expect(outcome.selectedChannelIds, {'c2'});
    expect(outcome.selectionChangePending, isTrue);
    expect(outcome.dailySwapRemovedId, 'c1');
    expect(outcome.dailySwapAddedId, isNull);
  });

  test('blocks removing last channel in completed selection', () {
    final outcome = SelectionPolicy.toggle(
      const SelectionPolicyInput(
        channelId: 'c1',
        selectedChannelIds: {'c1'},
        channelLimit: 3,
        selectionCompleted: true,
        selectionChangePending: false,
        dailySwapAddedId: null,
        dailySwapRemovedId: null,
        canChangeSelectionToday: true,
      ),
    );

    expect(outcome.changed, isFalse);
    expect(outcome.toastMessage, contains('오늘은 채널 1개만 교체할 수 있습니다'));
  });

  test('blocks additional toggle after swap is already completed', () {
    final outcome = SelectionPolicy.toggle(
      const SelectionPolicyInput(
        channelId: 'c3',
        selectedChannelIds: {'c2'},
        channelLimit: 3,
        selectionCompleted: true,
        selectionChangePending: true,
        dailySwapAddedId: 'c3',
        dailySwapRemovedId: 'c1',
        canChangeSelectionToday: true,
      ),
    );

    expect(outcome.changed, isFalse);
    expect(outcome.toastMessage, contains('오늘은 1개 교체만 가능합니다'));
  });

  test('validates pending swap requires both add/remove ids', () {
    final invalid = SelectionPolicy.validatePendingSwap(
      selectionCompleted: true,
      selectionChangePending: true,
      dailySwapAddedId: 'c2',
      dailySwapRemovedId: null,
    );
    final valid = SelectionPolicy.validatePendingSwap(
      selectionCompleted: true,
      selectionChangePending: true,
      dailySwapAddedId: 'c2',
      dailySwapRemovedId: 'c1',
    );

    expect(invalid.isValid, isFalse);
    expect(invalid.toastMessage, contains('1개 교체'));
    expect(valid.isValid, isTrue);
    expect(valid.toastMessage, isNull);
  });
}
