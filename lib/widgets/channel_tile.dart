import 'package:flutter/cupertino.dart';

import '../localization/app_strings.dart';
import '../models/channel.dart';
import '../theme.dart';

class ChannelTile extends StatelessWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    required this.isSelected,
    required this.onChanged,
    required this.isDisabled,
    required this.strings,
  });

  final Channel channel;
  final bool isSelected;
  final bool isDisabled;
  final ValueChanged<bool>? onChanged;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isDisabled && !isSelected ? 0.5 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: LiquidColors.separatorLight,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            ClipOval(
              child: Image.network(
                channel.thumbnailUrl,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 44,
                  height: 44,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: LiquidColors.glassDark,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        CupertinoIcons.person_fill,
                        color: LiquidColors.textTertiary,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Title & subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.title,
                    style: LiquidTextStyles.headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isSelected ? strings.selected : strings.selectable,
                    style: LiquidTextStyles.caption1.copyWith(
                      color: isSelected
                          ? LiquidColors.brand
                          : LiquidColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Switch
            Semantics(
              label: strings.channelSelectSemantics(channel.title),
              toggled: isSelected,
              child: CupertinoSwitch(
                key: ValueKey('channel-switch-${channel.id}'),
                value: isSelected,
                onChanged: isDisabled ? null : onChanged,
                activeTrackColor: LiquidColors.brand,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
