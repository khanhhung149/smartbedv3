import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_env.dart';

// AppEnv provider — intentionally throws if no override is set.
// Each entry point (main_dev.dart, main_prod.dart) MUST override this
// with the correct AppEnv subclass via ProviderScope.overrides.
final appEnvProvider = Provider<AppEnv>(
  (ref) => throw UnimplementedError(
    'appEnvProvider must be overridden in ProviderScope. '
    'Use main_dev.dart or main_prod.dart as the entry point.',
  ),
);
