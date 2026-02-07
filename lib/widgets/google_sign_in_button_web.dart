import 'package:flutter/cupertino.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi_web;

import '../app_config.dart';

final Future<void> _webSignInInitFuture = _ensureWebSignInInitialized();

Future<void> _ensureWebSignInInitialized() async {
  final googleSignIn = GoogleSignIn(
    scopes: const <String>[
      'email',
      'profile',
      'https://www.googleapis.com/auth/youtube.readonly',
    ],
    clientId: AppConfig.googleWebClientId.isNotEmpty
        ? AppConfig.googleWebClientId
        : null,
  );
  try {
    await googleSignIn.isSignedIn();
  } catch (_) {
    // Keep the button visible so the user can retry interactively.
  }
}

Widget buildGoogleSignInButton({required bool disabled}) {
  return FutureBuilder<void>(
    future: _webSignInInitFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const SizedBox(
          height: 44,
          child: Center(child: CupertinoActivityIndicator()),
        );
      }
      return AbsorbPointer(
        absorbing: disabled,
        child: gsi_web.renderButton(),
      );
    },
  );
}
