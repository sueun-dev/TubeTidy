import 'package:flutter/widgets.dart';

import 'google_sign_in_button_stub.dart'
    if (dart.library.html) 'google_sign_in_button_web.dart';

class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, this.disabled = false});

  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return buildGoogleSignInButton(disabled: disabled);
  }
}
