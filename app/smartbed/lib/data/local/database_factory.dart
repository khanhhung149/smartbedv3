import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Trỏ sqflite vào engine đúng với nền tảng đang chạy.
///
/// Phải chạy xong trước khi mở database đầu tiên. Android/iOS đã có plugin gốc
/// nên **không** đụng vào `databaseFactory` ở đó — gán đè sẽ hỏng đường chuẩn.
Future<void> initDatabaseFactory() async {
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
    return;
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return;
    default:
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
  }
}
