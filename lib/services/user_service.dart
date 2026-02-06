import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend_api.dart';

class UserProfile {
  const UserProfile({required this.userId, this.email, required this.planTier});

  final String userId;
  final String? email;
  final String planTier;
}

class UserService {
  static const Duration _timeout = Duration(seconds: 15);

  static Future<UserProfile?> upsertUser({
    required String userId,
    required String? email,
    required String planTier,
  }) async {
    if (userId.isEmpty) return null;
    final uri = BackendApi.uri('/user/upsert');
    try {
      final response = await http
          .post(
            uri,
            headers: BackendApi.headers(),
            body: jsonEncode({
              'user_id': userId,
              'email': email,
              'plan_tier': planTier,
            }),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final plan = data['plan_tier'] as String? ?? planTier;
      final mail = data['email'] as String?;
      return UserProfile(userId: userId, email: mail, planTier: plan);
    } catch (_) {
      return null;
    }
  }

  static Future<UserProfile?> fetchUser(String userId) async {
    if (userId.isEmpty) return null;
    final uri = BackendApi.uri('/user', queryParameters: {'user_id': userId});
    try {
      final response =
          await http.get(uri, headers: BackendApi.headers()).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return UserProfile(
        userId: userId,
        email: data['email'] as String?,
        planTier: data['plan_tier'] as String? ?? 'free',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> updatePlan(String userId, String planTier) async {
    if (userId.isEmpty) return false;
    final uri = BackendApi.uri('/user/plan');
    try {
      final response = await http
          .post(
            uri,
            headers: BackendApi.headers(),
            body: jsonEncode({'user_id': userId, 'plan_tier': planTier}),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
