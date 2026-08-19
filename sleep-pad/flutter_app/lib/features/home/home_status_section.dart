import 'package:flutter/material.dart';
import '../../shared/widgets/status_badge.dart';

// Status hero section — connection dot + sleep status label.
// Receives pre-resolved connection state and latest data from HomeContent.
class HomeStatusSection extends StatelessWidget {
  const HomeStatusSection({
    super.key,
    required this.statusCode,
    required this.connection,
    this.wsUrl,
  });

  final int? statusCode;
  final DeviceLinkState connection;
  final String? wsUrl;

  @override
  Widget build(BuildContext context) {
    return StatusHero(
      statusCode: statusCode,
      connection: connection,
      wsUrl: wsUrl,
    );
  }
}
