import 'package:flutter/foundation.dart';

@immutable
class SelectionPolicyInput {
  const SelectionPolicyInput({
    required this.channelId,
    required this.selectedChannelIds,
    required this.channelLimit,
    required this.selectionCompleted,
    required this.selectionChangePending,
    required this.dailySwapAddedId,
    required this.dailySwapRemovedId,
    required this.canChangeSelectionToday,
  });

  final String channelId;
  final Set<String> selectedChannelIds;
  final int channelLimit;
  final bool selectionCompleted;
  final bool selectionChangePending;
  final String? dailySwapAddedId;
  final String? dailySwapRemovedId;
  final bool canChangeSelectionToday;
}

@immutable
class SelectionPolicyOutcome {
  const SelectionPolicyOutcome({
    required this.changed,
    required this.selectedChannelIds,
    required this.selectionChangePending,
    required this.dailySwapAddedId,
    required this.dailySwapRemovedId,
    this.toastMessage,
  });

  final bool changed;
  final Set<String> selectedChannelIds;
  final bool selectionChangePending;
  final String? dailySwapAddedId;
  final String? dailySwapRemovedId;
  final String? toastMessage;

  factory SelectionPolicyOutcome.noChange(
    SelectionPolicyInput input, {
    String? toastMessage,
  }) {
    return SelectionPolicyOutcome(
      changed: false,
      selectedChannelIds: input.selectedChannelIds,
      selectionChangePending: input.selectionChangePending,
      dailySwapAddedId: input.dailySwapAddedId,
      dailySwapRemovedId: input.dailySwapRemovedId,
      toastMessage: toastMessage,
    );
  }
}

@immutable
class PendingSwapValidationResult {
  const PendingSwapValidationResult({
    required this.isValid,
    this.toastMessage,
  });

  final bool isValid;
  final String? toastMessage;
}

class SelectionPolicy {
  static SelectionPolicyOutcome toggle(SelectionPolicyInput input) {
    final selected = Set<String>.from(input.selectedChannelIds);
    final isSelected = selected.contains(input.channelId);
    final hasFreeSlots =
        input.channelLimit > 0 && selected.length < input.channelLimit;
    final swapCompleted =
        input.dailySwapAddedId != null && input.dailySwapRemovedId != null;

    if (input.selectionCompleted &&
        !isSelected &&
        !input.selectionChangePending &&
        hasFreeSlots) {
      selected.add(input.channelId);
      return SelectionPolicyOutcome(
        changed: true,
        selectedChannelIds: Set.unmodifiable(selected),
        selectionChangePending: input.selectionChangePending,
        dailySwapAddedId: input.dailySwapAddedId,
        dailySwapRemovedId: input.dailySwapRemovedId,
      );
    }

    if (input.selectionCompleted &&
        !input.selectionChangePending &&
        !input.canChangeSelectionToday) {
      return SelectionPolicyOutcome.noChange(
        input,
        toastMessage: '오늘은 채널 변경을 이미 1회 사용했습니다. 내일 다시 변경할 수 있어요.',
      );
    }

    if (input.selectionCompleted && swapCompleted) {
      return SelectionPolicyOutcome.noChange(
        input,
        toastMessage: '오늘은 1개 교체만 가능합니다. 변경을 저장하려면 완료를 눌러주세요.',
      );
    }

    if (isSelected) {
      if (input.selectionCompleted &&
          !_canRemoveChannel(
            channelId: input.channelId,
            selected: selected,
            selectionChangePending: input.selectionChangePending,
            dailySwapRemovedId: input.dailySwapRemovedId,
          )) {
        return SelectionPolicyOutcome.noChange(
          input,
          toastMessage: '오늘은 채널 1개만 교체할 수 있습니다. 추가/제거를 더 진행할 수 없어요.',
        );
      }
      selected.remove(input.channelId);
      return SelectionPolicyOutcome(
        changed: true,
        selectedChannelIds: Set.unmodifiable(selected),
        selectionChangePending:
            input.selectionCompleted ? true : input.selectionChangePending,
        dailySwapAddedId:
            input.selectionCompleted ? input.dailySwapAddedId : null,
        dailySwapRemovedId: input.selectionCompleted
            ? (input.dailySwapRemovedId ?? input.channelId)
            : null,
      );
    }

    final canSelectMore =
        input.channelLimit > 0 && selected.length < input.channelLimit;
    if (!canSelectMore) {
      return SelectionPolicyOutcome.noChange(
        input,
        toastMessage: '채널 한도가 가득 찼습니다. 다른 채널을 하나 해제한 뒤 추가해주세요.',
      );
    }

    if (input.selectionCompleted &&
        !_canAddChannel(
          channelId: input.channelId,
          selectionChangePending: input.selectionChangePending,
          dailySwapAddedId: input.dailySwapAddedId,
        )) {
      return SelectionPolicyOutcome.noChange(
        input,
        toastMessage: '오늘은 채널 1개만 교체할 수 있습니다. 추가/제거를 더 진행할 수 없어요.',
      );
    }

    selected.add(input.channelId);
    return SelectionPolicyOutcome(
      changed: true,
      selectedChannelIds: Set.unmodifiable(selected),
      selectionChangePending:
          input.selectionCompleted ? true : input.selectionChangePending,
      dailySwapAddedId: input.selectionCompleted
          ? (input.dailySwapAddedId ?? input.channelId)
          : null,
      dailySwapRemovedId:
          input.selectionCompleted ? input.dailySwapRemovedId : null,
    );
  }

  static PendingSwapValidationResult validatePendingSwap({
    required bool selectionCompleted,
    required bool selectionChangePending,
    required String? dailySwapAddedId,
    required String? dailySwapRemovedId,
  }) {
    if (!selectionCompleted || !selectionChangePending) {
      return const PendingSwapValidationResult(isValid: true);
    }
    if (dailySwapAddedId == null || dailySwapRemovedId == null) {
      return const PendingSwapValidationResult(
        isValid: false,
        toastMessage: '채널 변경은 1개 교체(제거 1 + 추가 1)로 완료됩니다.',
      );
    }
    return const PendingSwapValidationResult(isValid: true);
  }

  static bool _canAddChannel({
    required String channelId,
    required bool selectionChangePending,
    required String? dailySwapAddedId,
  }) {
    if (!selectionChangePending) return true;
    return dailySwapAddedId == null || dailySwapAddedId == channelId;
  }

  static bool _canRemoveChannel({
    required String channelId,
    required Set<String> selected,
    required bool selectionChangePending,
    required String? dailySwapRemovedId,
  }) {
    if (!selectionChangePending) {
      return selected.length > 1;
    }
    return dailySwapRemovedId == null || dailySwapRemovedId == channelId;
  }
}
