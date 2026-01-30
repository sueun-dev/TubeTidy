class UserChannel {
  UserChannel({
    required this.id,
    required this.userId,
    required this.channelId,
    required this.isSelected,
    required this.syncedAt,
  });

  final String id;
  final String userId;
  final String channelId;
  final bool isSelected;
  final DateTime syncedAt;
}
