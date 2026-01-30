import 'plan.dart';

enum PaymentStatus {
  pending,
  active,
  canceled,
  failed,
}

enum PaymentPeriod {
  monthly,
  lifetime,
}

class Payment {
  Payment({
    required this.id,
    required this.userId,
    required this.plan,
    required this.status,
    required this.period,
    required this.providerId,
    required this.amount,
  });

  final String id;
  final String userId;
  final Plan plan;
  final PaymentStatus status;
  final PaymentPeriod period;
  final String providerId;
  final double amount;
}
