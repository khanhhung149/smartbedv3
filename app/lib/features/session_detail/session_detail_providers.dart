import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/sleep_session.dart';
import '../sessions/sessions_providers.dart';

/// Looks the session up in the list already loaded rather than refetching it.
///
/// The list comes from cache first, so this works offline for any night the
/// user has seen — which is the offline acceptance criterion.
final sessionByIdProvider =
    FutureProvider.family<SleepSession?, String>((ref, id) async {
  final result = await ref.watch(sessionsProvider.future);
  for (final s in result.items) {
    if (s.id == id) return s;
  }
  return null;
});
