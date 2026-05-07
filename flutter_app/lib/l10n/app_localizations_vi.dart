// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get appName => 'Sleep Tech';

  @override
  String get signIn => 'Đăng nhập';

  @override
  String get signUp => 'Đăng ký';

  @override
  String get logIn => 'Đăng nhập';

  @override
  String get logOut => 'Đăng xuất';

  @override
  String get createAccount => 'Tạo tài khoản';

  @override
  String get getStarted => 'Bắt đầu';

  @override
  String get continueCta => 'Tiếp tục';

  @override
  String get save => 'Lưu';

  @override
  String get saveChanges => 'Lưu thay đổi';

  @override
  String get cancel => 'Hủy';

  @override
  String get retry => 'Thử lại';

  @override
  String get accept => 'Chấp nhận';

  @override
  String get decline => 'Từ chối';

  @override
  String get send => 'Gửi';

  @override
  String get welcomeBack => 'Chào mừng trở lại';

  @override
  String get createYourAccount => 'Tạo tài khoản của bạn';

  @override
  String get newHereSignUp => 'Chưa có tài khoản? Đăng ký';

  @override
  String get alreadyHaveAccount => 'Đã có tài khoản? ';

  @override
  String get forgotPassword => 'Quên mật khẩu?';

  @override
  String get forgotPasswordTitle => 'Quên mật khẩu';

  @override
  String get forgotPasswordSubtitle =>
      'Nhập email và chúng tôi sẽ gửi mã đặt lại';

  @override
  String get sendResetCode => 'Gửi mã đặt lại';

  @override
  String get backToSignIn => 'Quay lại đăng nhập';

  @override
  String get emailAddress => 'Địa chỉ email';

  @override
  String get password => 'Mật khẩu';

  @override
  String get currentPassword => 'Mật khẩu hiện tại';

  @override
  String get newPassword => 'Mật khẩu mới';

  @override
  String get confirmPassword => 'Xác nhận mật khẩu';

  @override
  String get passwordChanged => 'Đổi mật khẩu thành công.';

  @override
  String get checkYourEmail => 'Kiểm tra email của bạn';

  @override
  String verifyEmailSubtitle(String email) {
    return 'Chúng tôi đã gửi mã 6 chữ số đến\n$email';
  }

  @override
  String get verify => 'Xác minh';

  @override
  String get resendCode => 'Gửi lại mã';

  @override
  String resendIn(int seconds) {
    return 'Gửi lại sau ${seconds}s';
  }

  @override
  String get resetPassword => 'Đặt lại mật khẩu';

  @override
  String resetPasswordSubtitle(String email) {
    return 'Nhập mã đã gửi đến $email';
  }

  @override
  String get enterValidEmail => 'Nhập địa chỉ email hợp lệ.';

  @override
  String get passwordTooShort => 'Mật khẩu phải có ít nhất 8 ký tự.';

  @override
  String get passwordsDoNotMatch => 'Mật khẩu không khớp.';

  @override
  String get enterSixDigitCode => 'Nhập mã 6 chữ số.';

  @override
  String get settings => 'Cài đặt';

  @override
  String get account => 'Tài khoản';

  @override
  String get notifications => 'Thông báo';

  @override
  String get appearance => 'Giao diện';

  @override
  String get deviceConnection => 'Kết nối thiết bị';

  @override
  String get about => 'Về ứng dụng';

  @override
  String get changePassword => 'Đổi mật khẩu';

  @override
  String get enablePushNotifications => 'Bật thông báo đẩy';

  @override
  String get quietHours => 'Giờ yên tĩnh';

  @override
  String get quietHoursValue => '10pm — 7am';

  @override
  String get appVersion => 'Phiên bản ứng dụng';

  @override
  String get termsOfService => 'Điều khoản dịch vụ';

  @override
  String get privacyPolicy => 'Chính sách bảo mật';

  @override
  String get supportEmail => 'Email hỗ trợ';

  @override
  String get serverUrl => 'URL máy chủ';

  @override
  String get advanced => 'Nâng cao';

  @override
  String get savedWifiCredentials => 'Thông tin WiFi đã lưu';

  @override
  String get invalidUrlFormat => 'Định dạng URL không hợp lệ';

  @override
  String get language => 'Ngôn ngữ';

  @override
  String get devices => 'Thiết bị';

  @override
  String get deviceDetails => 'Chi tiết thiết bị';

  @override
  String get noDevicesPaired => 'Chưa có thiết bị nào được ghép.';

  @override
  String get addDevice => 'Thêm thiết bị';

  @override
  String get noDeviceSelected => 'Chưa chọn thiết bị.';

  @override
  String get deviceIdCopied => 'Đã sao chép ID thiết bị';

  @override
  String failedToLoadDevice(String error) {
    return 'Không thể tải thiết bị: $error';
  }

  @override
  String pairedOn(String date) {
    return 'Đã ghép $date';
  }

  @override
  String activeAgo(String time) {
    return 'Hoạt động $time';
  }

  @override
  String get online => 'Trực tuyến';

  @override
  String get offline => 'Ngoại tuyến';

  @override
  String get deviceNameHint => 'Tên thiết bị';

  @override
  String get noDevice => 'Không có thiết bị';

  @override
  String get setupSleepPad => 'Cài đặt Sleep Tech';

  @override
  String get sleepPadReady => 'Sleep Tech đã sẵn sàng';

  @override
  String get monitorSleepTagline =>
      'Theo dõi giấc ngủ,\nkhông cần đeo thiết bị';

  @override
  String get giveWifi => 'Kết nối WiFi cho Sleep Tech';

  @override
  String get wifiDescription =>
      'Sleep Tech sẽ dùng mạng này để gửi dữ liệu lên đám mây.';

  @override
  String get networkName => 'Tên mạng (SSID)';

  @override
  String get saveAndGoHome => 'Lưu và về trang chủ';

  @override
  String get pairingWithDevice => 'Đang ghép đôi thiết bị...';

  @override
  String get pairingDuration => 'Thường mất 10–30 giây';

  @override
  String get sharingTitle => 'Chia sẻ sự an tâm';

  @override
  String get sharingSubtitle =>
      'Mời thành viên gia đình qua email. Họ xem cùng dữ liệu giấc ngủ theo thời gian thực.';

  @override
  String get sendInvite => 'Gửi lời mời';

  @override
  String get pendingInvites => 'LỜI MỜI CHỜ XỬ LÝ';

  @override
  String get noDevicesShared => 'Chưa có thiết bị nào được chia sẻ với bạn.';

  @override
  String inviteFrom(String email) {
    return 'Lời mời từ $email';
  }

  @override
  String get alerts => 'Cảnh báo';

  @override
  String get alertDetail => 'Chi tiết cảnh báo';

  @override
  String get knowIfSomethingOff => 'Biết ngay khi có bất thường';

  @override
  String get alertsSubtitle =>
      'Đặt ngưỡng cá nhân. Nhận thông báo ngay khi có thay đổi.';

  @override
  String get activeNotificationsEnabled => 'Thông báo đang bật';

  @override
  String get sleepHistory => 'Lịch sử giấc ngủ';

  @override
  String get couldNotLoadHistory => 'Không thể tải lịch sử';

  @override
  String get notEnoughData => 'Chưa đủ dữ liệu';

  @override
  String get sleepDataWillAppear =>
      'Dữ liệu giấc ngủ sẽ xuất hiện sau khi thiết bị theo dõi.';

  @override
  String get noDevicePaired => 'Chưa có thiết bị được ghép nối';

  @override
  String get iAlreadyHaveAccount => 'Tôi đã có tài khoản';

  @override
  String get justNow => 'vừa xong';

  @override
  String minutesAgo(int minutes) {
    return '$minutes phút trước';
  }

  @override
  String hoursAgo(int hours) {
    return '${hours}h trước';
  }

  @override
  String get networkNameRequired => 'Tên mạng là bắt buộc';

  @override
  String get somethingWentWrong => 'Đã xảy ra lỗi. Vui lòng thử lại.';

  @override
  String get inviteFamily => 'Mời thành viên gia đình';

  @override
  String get inviteFamilyDescription =>
      'Họ sẽ nhận được lời mời qua email. Khi chấp nhận, họ sẽ thấy dữ liệu và cảnh báo theo thời gian thực giống bạn.';

  @override
  String get addDeviceToGetStarted => 'Thêm thiết bị Sleep Tech để bắt đầu.';

  @override
  String reconnectingTo(String deviceName) {
    return 'Đang kết nối lại với $deviceName…';
  }

  @override
  String get heartRate => 'Nhịp tim';

  @override
  String get respiration => 'Hô hấp';

  @override
  String get temperature => 'Nhiệt độ';

  @override
  String get movement => 'Cử động';

  @override
  String get snores => 'Tiếng ngáy';

  @override
  String get sData => 'S-Data';

  @override
  String get pData => 'P-Data';

  @override
  String get nearbyDevices => 'THIẾT BỊ GẦN ĐÂY';

  @override
  String get searchingForDevices => 'Đang tìm thiết bị lân cận...';

  @override
  String get bluetoothPermissionNeeded => 'Cần quyền Bluetooth';

  @override
  String get bluetoothPermissionDescription =>
      'Sleep Tech cần Bluetooth để tìm thiết bị của bạn. Cấp quyền để tiếp tục.';

  @override
  String get openSettings => 'Mở cài đặt';

  @override
  String get strongSignal => 'Tín hiệu mạnh';

  @override
  String get moderateSignal => 'Tín hiệu vừa';

  @override
  String get weakSignal => 'Tín hiệu yếu';

  @override
  String get only24GhzSupported =>
      'Thiết bị dùng WiFi 2.4GHz. Router 2 băng tần (cùng tên mạng) vẫn hoạt động bình thường. Nếu kết nối thất bại, hãy thử chọn mạng 2.4GHz riêng.';

  @override
  String get wifiConnectionFailed => 'Kết nối WiFi thất bại';

  @override
  String get serverUnreachable => 'Không thể kết nối máy chủ';

  @override
  String get changeWifi => 'Đổi WiFi';

  @override
  String get changeWifiDescription =>
      'Để đổi WiFi, giữ nút trên thiết bị Sleep Tech 5 giây cho đến khi đèn LED nhấp nháy xanh — thiết bị sẽ khởi động lại ở chế độ cài đặt.';

  @override
  String get changeWifiContinue => 'Tiếp tục cài đặt';
}
