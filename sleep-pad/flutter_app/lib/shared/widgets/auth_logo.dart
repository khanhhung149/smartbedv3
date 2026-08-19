import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Shared auth logo used by login/register/forgot-password screens.
class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key, this.width = 208});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/branding/icon_logo_title.svg',
      width: width,
      fit: BoxFit.contain,
    );
  }
}
