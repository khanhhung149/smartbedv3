import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Says the data is cached and when it was cached.
///
/// The timestamp is the point: "offline" alone leaves the reader unable to
/// judge whether last night's report is in front of them or last week's.
class StaleDataBanner extends StatelessWidget {
  const StaleDataBanner({super.key, this.cachedAt});

  final DateTime? cachedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = cachedAt == null
        ? ''
        : ', cập nhật lúc ${DateFormat('HH:mm dd/MM', 'vi').format(cachedAt!)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: theme.hintColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Dữ liệu ngoại tuyến$when',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
