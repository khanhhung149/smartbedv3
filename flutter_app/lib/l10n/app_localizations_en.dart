// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Sleep Tech';

  @override
  String get signIn => 'Sign in';

  @override
  String get signUp => 'Sign up';

  @override
  String get logIn => 'Log in';

  @override
  String get logOut => 'Log out';

  @override
  String get createAccount => 'Create account';

  @override
  String get getStarted => 'Get started';

  @override
  String get continueCta => 'Continue';

  @override
  String get save => 'Save';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get cancel => 'Cancel';

  @override
  String get retry => 'Retry';

  @override
  String get accept => 'Accept';

  @override
  String get decline => 'Decline';

  @override
  String get send => 'Send';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get createYourAccount => 'Create your account';

  @override
  String get newHereSignUp => 'New here? Sign up';

  @override
  String get alreadyHaveAccount => 'Already have an account? ';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get forgotPasswordTitle => 'Forgot password';

  @override
  String get forgotPasswordSubtitle =>
      'Enter your email and we\'ll send a reset code';

  @override
  String get sendResetCode => 'Send reset code';

  @override
  String get backToSignIn => 'Back to sign in';

  @override
  String get emailAddress => 'Email address';

  @override
  String get password => 'Password';

  @override
  String get currentPassword => 'Current password';

  @override
  String get newPassword => 'New password';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get passwordChanged => 'Password changed successfully.';

  @override
  String get checkYourEmail => 'Check your email';

  @override
  String verifyEmailSubtitle(String email) {
    return 'We sent a 6-digit code to\n$email';
  }

  @override
  String get verify => 'Verify';

  @override
  String get resendCode => 'Resend code';

  @override
  String resendIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get resetPassword => 'Reset password';

  @override
  String resetPasswordSubtitle(String email) {
    return 'Enter the code sent to $email';
  }

  @override
  String get enterValidEmail => 'Enter a valid email address.';

  @override
  String get passwordTooShort => 'Password must be at least 8 characters.';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match.';

  @override
  String get enterSixDigitCode => 'Enter the 6-digit code.';

  @override
  String get settings => 'Settings';

  @override
  String get account => 'Account';

  @override
  String get notifications => 'Notifications';

  @override
  String get appearance => 'Appearance';

  @override
  String get deviceConnection => 'Device Connection';

  @override
  String get about => 'About';

  @override
  String get changePassword => 'Change password';

  @override
  String get enablePushNotifications => 'Enable push notifications';

  @override
  String get quietHours => 'Quiet hours';

  @override
  String get quietHoursValue => '10pm — 7am';

  @override
  String get appVersion => 'App version';

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get supportEmail => 'Support Email';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get advanced => 'Advanced';

  @override
  String get savedWifiCredentials => 'Saved WiFi credentials';

  @override
  String get invalidUrlFormat => 'Invalid URL format';

  @override
  String get language => 'Language';

  @override
  String get devices => 'Devices';

  @override
  String get deviceDetails => 'Device Details';

  @override
  String get noDevicesPaired => 'No devices paired yet.';

  @override
  String get addDevice => 'Add device';

  @override
  String get noDeviceSelected => 'No device selected.';

  @override
  String get deviceIdCopied => 'Device ID copied';

  @override
  String failedToLoadDevice(String error) {
    return 'Failed to load device: $error';
  }

  @override
  String pairedOn(String date) {
    return 'Paired $date';
  }

  @override
  String activeAgo(String time) {
    return 'Active $time';
  }

  @override
  String get online => 'Online';

  @override
  String get offline => 'Offline';

  @override
  String get deviceNameHint => 'Device name';

  @override
  String get noDevice => 'No device';

  @override
  String get setupSleepPad => 'Setup Sleep Tech';

  @override
  String get sleepPadReady => 'Sleep Tech is ready';

  @override
  String get monitorSleepTagline => 'Monitor sleep,\nwithout wearables';

  @override
  String get giveWifi => 'Give your Sleep Tech WiFi';

  @override
  String get wifiDescription =>
      'Your Sleep Tech will use this network to send data to the cloud.';

  @override
  String get networkName => 'Network Name (SSID)';

  @override
  String get saveAndGoHome => 'Save and go home';

  @override
  String get pairingWithDevice => 'Pairing with your device...';

  @override
  String get pairingDuration => 'This usually takes 10–30 seconds';

  @override
  String get sharingTitle => 'Share peace of mind';

  @override
  String get sharingSubtitle =>
      'Invite family members by email. They see the same sleep data in real time.';

  @override
  String get sendInvite => 'Send invite';

  @override
  String get pendingInvites => 'PENDING INVITES';

  @override
  String get noDevicesShared => 'No devices shared with you.';

  @override
  String inviteFrom(String email) {
    return 'Invite from $email';
  }

  @override
  String get alerts => 'Alerts';

  @override
  String get alertDetail => 'Alert Detail';

  @override
  String get knowIfSomethingOff => 'Know if something\'s off';

  @override
  String get alertsSubtitle =>
      'Set personalized thresholds. Get a notification the moment something changes.';

  @override
  String get activeNotificationsEnabled => 'Active notifications enabled';

  @override
  String get sleepHistory => 'Sleep History';

  @override
  String get couldNotLoadHistory => 'Could not load history';

  @override
  String get notEnoughData => 'Not enough data yet';

  @override
  String get sleepDataWillAppear =>
      'Sleep data will appear here once your device has been monitoring.';

  @override
  String get noDevicePaired => 'No device paired';

  @override
  String get iAlreadyHaveAccount => 'I already have an account';

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(int minutes) {
    return '$minutes min ago';
  }

  @override
  String hoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String get networkNameRequired => 'Network name is required';

  @override
  String get somethingWentWrong => 'Something went wrong. Try again.';

  @override
  String get inviteFamily => 'Invite family';

  @override
  String get inviteFamilyDescription =>
      'They\'ll get an email invite. When they accept, they\'ll see the same realtime data and alerts you do.';

  @override
  String get addDeviceToGetStarted => 'Add a Sleep Tech device to get started.';

  @override
  String reconnectingTo(String deviceName) {
    return 'Reconnecting to $deviceName…';
  }

  @override
  String get heartRate => 'Heart Rate';

  @override
  String get respiration => 'Respiration';

  @override
  String get temperature => 'Temperature';

  @override
  String get movement => 'Movement';

  @override
  String get snores => 'Snores';

  @override
  String get sData => 'S-Data';

  @override
  String get pData => 'P-Data';

  @override
  String get nearbyDevices => 'NEARBY DEVICES';

  @override
  String get searchingForDevices => 'Searching for nearby devices...';

  @override
  String get bluetoothPermissionNeeded => 'Bluetooth permission needed';

  @override
  String get bluetoothPermissionDescription =>
      'Sleep Tech needs Bluetooth to find your device. Grant permission to continue.';

  @override
  String get openSettings => 'Open settings';

  @override
  String get strongSignal => 'Strong signal';

  @override
  String get moderateSignal => 'Moderate signal';

  @override
  String get weakSignal => 'Weak signal';
}
