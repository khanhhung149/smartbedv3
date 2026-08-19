import 'package:flutter/material.dart';

/// The wellness disclaimer, defined once.
///
/// This is a regulatory line, not decoration: the pad is a wellness device and
/// may not carry a diagnostic claim. Copying the string per screen is how one
/// copy eventually drifts, so every screen renders this widget instead.
const String kWellnessDisclaimer = 'Số liệu chỉ mang tính tham khảo, không dùng chẩn đoán';

class DisclaimerFooter extends StatelessWidget {
  const DisclaimerFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 16, color: Theme.of(context).hintColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              kWellnessDisclaimer,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).hintColor,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
