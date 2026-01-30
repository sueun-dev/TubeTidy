import 'plan.dart';

class User {
  User({
    required this.id,
    required this.email,
    required this.plan,
    required this.createdAt,
  });

  final String id;
  final String email;
  final Plan plan;
  final DateTime createdAt;
}
