import 'package:flutter/cupertino.dart';

import '../models/channel.dart';
import '../theme.dart';

class ChannelTile extends StatelessWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    required this.isSelected,
    required this.onChanged,
    required this.isDisabled,
  });

  final Channel channel;
  final bool isSelected;
  final bool isDisabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tile = CupertinoListTile.notched(
      leading: ClipOval(
        child: Image.network(
          channel.thumbnailUrl,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 36,
            height: 36,
            color: AppColors.elevatedCard,
            alignment: Alignment.center,
            child: const Icon(CupertinoIcons.person, color: AppColors.textSecondary, size: 18),
          ),
        ),
      ),
      title: Text(
        channel.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        isSelected ? '선택됨' : '요약 준비 중',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing: Semantics(
        label: '${channel.title} 채널 선택',
        toggled: isSelected,
        child: CupertinoSwitch(
          value: isSelected,
          onChanged: isDisabled ? null : onChanged,
          activeTrackColor: AppColors.brand,
        ),
      ),
    );

    if (!isDisabled || isSelected) {
      return tile;
    }

    return Opacity(opacity: 0.5, child: tile);
  }
}
