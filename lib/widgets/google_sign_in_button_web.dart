import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi_web;

Widget buildGoogleSignInButton({required bool disabled}) {
  return AbsorbPointer(
    absorbing: disabled,
    child: gsi_web.renderButton(),
  );
}
