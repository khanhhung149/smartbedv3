// Default entry point — delegates to the dev flavor entry point.
// Keeps existing IDE run configurations working without changes.
// For production builds use: flutter build apk -t lib/main/main_prod.dart
import 'main/main_dev.dart' as entry;

void main() => entry.main();
