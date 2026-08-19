---
phase: 5
title: "App — màn hình danh sách phiên ngủ"
status: completed
priority: P2
dependencies: [4]
repo: smartbedv3
---

# Phase 05: App — màn hình danh sách phiên ngủ

## Overview
Màn hình chính: mỗi đêm một thẻ, đọc hiểu được. Cộng màn hình cài đặt tối thiểu để đổi base URL / device / token mà không phải build lại.

## Requirements
- Functional: danh sách phiên mới nhất trước, kéo để làm mới, banner khi dữ liệu là bản cache.
- Functional: màn hình cài đặt sửa được `baseUrl`, `deviceId`, `devToken` lúc chạy (ghi vào `shared_preferences`, đè lên `--dart-define`).
- Non-functional: **"đọc hiểu được, không phải biểu đồ kỹ thuật khô khan"** — tiêu chí nghiệm thu của `phase-06` plan MVP.
- Non-functional: mọi chỉ số gắn nhãn *"tham khảo, không dùng chẩn đoán"* (R7).
- Non-functional: không vỡ ở 360dp và 800dp.

## Architecture

```
lib/features/sessions/
  sessions_screen.dart
  sessions_providers.dart      # riverpod: AsyncValue<SessionsResult>
  widgets/
    session_card.dart
    stale_data_banner.dart
    empty_state.dart
    disclaimer_footer.dart
lib/features/settings/
  settings_screen.dart
```

**Thẻ một đêm** — thứ tự ưu tiên đọc, không phải thứ tự cột trong DB:
```
Đêm 18/08 → 19/08
23:41 – 06:52          7 giờ 11 phút
─────────────────────────────────────
Nhịp tim TB   62      Nhịp thở TB  15.2
Trở mình      34      Ngáy          12
Rối loạn hô hấp        6
```
Số 0 và `null` là hai chuyện khác nhau: `null` hiện `—`, **không** hiện `0`. Bịa số ra để biểu đồ liền mạch là điều `docs/system-architecture.md` §6 cấm thẳng.

**Responsive:** `< 600dp` một cột; `>= 600dp` lưới 2 cột. Dùng `breakpoints.dart` của Phase 04, không rải `MediaQuery` khắp nơi.

**Nhãn wellness:** một `disclaimer_footer.dart` dùng chung, đặt cuối danh sách và cuối màn hình chi tiết. Một chỗ, không copy chuỗi.

## Related Code Files
- Create: `smartbedv3/app/lib/features/sessions/**`
- Create: `smartbedv3/app/lib/features/settings/settings_screen.dart`
- Modify: `smartbedv3/app/lib/core/app_router.dart` — route `/` và `/settings`
- Modify: `smartbedv3/app/lib/core/app_config.dart` — đọc `shared_preferences` đè lên `--dart-define`
- Modify: `smartbedv3/app/pubspec.yaml` — thêm `shared_preferences`

## Implementation Steps
1. `sessions_providers.dart`: `FutureProvider` gọi `SessionRepository`, expose `isStale`
2. `session_card.dart`: layout thẻ như trên; format giờ bằng `intl`, locale `vi`
3. `sessions_screen.dart`: `RefreshIndicator` + `ListView`/`GridView` theo breakpoint; 3 trạng thái: loading / rỗng / có dữ liệu
4. `stale_data_banner.dart`: hiện khi `isStale`, ghi rõ thời điểm cache
5. `disclaimer_footer.dart`
6. `settings_screen.dart`: 3 ô nhập + nút Lưu → ghi `shared_preferences` → invalidate provider
7. Xử lý `DevTokenExpiredException`: hiện thông báo có nút "Mở cài đặt"
8. `test/`: widget test 4 trạng thái (loading, rỗng, có dữ liệu, stale)
9. `flutter analyze && flutter test`

## Success Criteria
- [ ] Seed 3 đêm → app hiện 3 thẻ, mới nhất trên cùng
- [ ] Kéo để làm mới gọi lại API và cập nhật thẻ
- [ ] Tắt mạng → vẫn thấy 3 thẻ + banner "dữ liệu ngoại tuyến, cập nhật lúc HH:mm"
- [ ] Trường `null` hiện `—`, **không** hiện `0`
- [ ] Token sai → thông báo rõ + nút mở cài đặt, **không** màn hình trắng
- [ ] Không vỡ ở **360dp** và **800dp** (đo bằng emulator resize hoặc `flutter run -d chrome` rồi kéo)
- [ ] Nhãn "tham khảo, không dùng chẩn đoán" hiện trên màn hình
- [ ] `flutter analyze` sạch, widget test xanh

## Risk Assessment
- **Trôi thành biểu đồ kỹ thuật:** tiêu chí của plan MVP là *đọc hiểu được*. Nếu thẻ chỉ là bảng số thô thì pha này chưa đạt, dù test có xanh.
- **`0` vs `null`:** `hr_avg` null (không đủ dữ liệu) khác `hr_avg = 0` (không bao giờ hợp lệ). Nhầm hai cái này là báo cáo sai cho người dùng.
- **Rải `MediaQuery`:** sẽ thành nợ khi làm tablet ở pha sau. Giữ ở `breakpoints.dart`.
