enum PlanTier {
  free,
  starter,
  growth,
  unlimited,
  lifetime,
}

class Plan {
  const Plan({required this.tier});

  final PlanTier tier;

  String get displayName {
    switch (tier) {
      case PlanTier.free:
        return 'Free';
      case PlanTier.starter:
        return 'Plus';
      case PlanTier.growth:
        return 'Pro';
      case PlanTier.unlimited:
        return 'Unlimited';
      case PlanTier.lifetime:
        return 'Unlimited';
    }
  }

  String get priceLabel {
    switch (tier) {
      case PlanTier.free:
        return '무료';
      case PlanTier.starter:
        return '\$0.99/월';
      case PlanTier.growth:
        return '\$1.99/월';
      case PlanTier.unlimited:
        return '\$2.99/월';
      case PlanTier.lifetime:
        return '\$19.99 (평생)';
    }
  }

  int? get channelLimit {
    switch (tier) {
      case PlanTier.free:
        return 3;
      case PlanTier.starter:
        return 10;
      case PlanTier.growth:
        return 50;
      case PlanTier.unlimited:
      case PlanTier.lifetime:
        return null;
    }
  }

  String get limitLabel {
    final limit = channelLimit;
    if (limit == null) {
      return '무제한 채널';
    }
    return '$limit 채널';
  }

  bool get isUnlimited => channelLimit == null;
}
