---
phase: 6
title: "App — chi tiết phiên + biểu đồ timeline"
status: completed
priority: P2
dependencies: [5]
repo: smartbedv3
---

# Phase 06: App — chi tiết phiên + biểu đồ timeline

## Overview
Bấm vào một đêm → xem diễn biến cả đêm trên một trục thời gian: nhịp tim, nhịp thở, cử động, ngáy, và dải trên/rời giường.

## Requirements
- Functional: gọi `/sessions/{id}/timeline`, cache, vẽ.
- Functional: đọc offline được nếu timeline đã tải trước đó.
- Non-functional: một trục thời gian dùng chung cho mọi chuỗi — đây là toàn bộ lý do plan này tồn tại.
- Non-functional: biểu đồ cuộn ngang được trong khung của nó, **không** làm trang cuộn ngang.

## Architecture

```
lib/features/session_detail/
  session_detail_screen.dart
  session_detail_providers.dart
  widgets/
    summary_header.dart      # tóm tắt phiên, dùng lại thành phần của session_card
    timeline_chart.dart      # fl_chart, trục X chung
    bed_state_band.dart      # dải on_bed / off_bed
    event_markers.dart       # ngồi dậy · tỉnh · ngáy · thở yếu
```

**Bố cục dọc, mọi tầng chung trục X:**
```
┌ Nhịp tim (bpm) ─────────────────────┐
├ Nhịp thở (brpm) ────────────────────┤
├ Cử động / ngáy (cột) ───────────────┤
└ Dải trên giường ▓▓▓░░▓▓▓▓▓▓ ────────┘
   23:41                        06:52
```

**Chỗ để mở rộng:** danh sách tầng là dữ liệu, không phải code cứng. Thêm presence/nhiệt độ sau này = thêm một phần tử, không sửa `timeline_chart.dart`.

**Khoảng trống dữ liệu vẽ là khoảng trống**, không nối thẳng qua. Nối liền một gap 40 phút là bịa dữ liệu — `docs/system-architecture.md` §6 cấm.

**Hiệu năng:** một đêm 8 tiếng ở `bucket=1m` là ~480 điểm mỗi chuỗi. `fl_chart` chịu được. Nếu người dùng chọn khoảng dài hơn thì dùng `bucket=5m` — đừng tự giảm mẫu ở client.

## Related Code Files
- Create: `smartbedv3/app/lib/features/session_detail/**`
- Modify: `smartbedv3/app/lib/core/app_router.dart` — route `/session/:id`
- Modify: `smartbedv3/app/lib/data/session_repository.dart` — thêm `timeline(sessionId)` cache-trước
- Modify: `smartbedv3/app/lib/features/sessions/widgets/session_card.dart` — bấm để điều hướng

## Implementation Steps
1. `session_repository.timeline()` theo đúng luồng cache-trước của Phase 04
2. `summary_header.dart`: dùng lại phần chỉ số của `session_card`, không viết lại (DRY)
3. `timeline_chart.dart`: nhận `List<ChartLayer>`, mỗi layer có nhãn/đơn vị/kiểu vẽ. Trục X tính một lần, truyền xuống
4. `bed_state_band.dart`, `event_markers.dart`
5. Bọc biểu đồ trong khung `overflow` riêng — trang không được cuộn ngang
6. Trạng thái rỗng: phiên chưa có timeline → thông báo, không phải biểu đồ trắng
7. `test/`: golden test hoặc widget test cho 3 trạng thái (có dữ liệu, có gap, rỗng)
8. `flutter analyze && flutter test`

## Success Criteria
- [ ] Bấm một đêm → mở chi tiết, mọi chuỗi thẳng hàng trên cùng trục X
- [ ] Seed có `--gap-minutes` → chỗ gap là **khoảng trống**, không phải đường nối
- [ ] Dải trên/rời giường khớp `bed_state` của API
- [ ] Sự kiện ngáy / ngồi dậy hiện đúng vị trí thời gian
- [ ] Tắt mạng sau khi đã xem một lần → vẫn mở lại được phiên đó
- [ ] Trang **không** cuộn ngang ở 360dp; biểu đồ cuộn trong khung của nó
- [ ] Nhãn "tham khảo, không dùng chẩn đoán" hiện trên màn hình
- [ ] `flutter analyze` sạch, test xanh

## Risk Assessment
- **Lệch trục giữa các tầng:** nếu mỗi tầng tự tính trục X thì sẽ lệch vài pixel và mọi kết luận đọc từ biểu đồ đều sai. Tính một lần, truyền xuống.
- **Nối liền qua gap:** trông đẹp hơn, nhưng là bịa dữ liệu. Vi phạm quy tắc của repo.
- **Tự giảm mẫu ở client:** làm mất đỉnh (ngáy, trở mình). Đổi `bucket` phía server thay vì lọc ở Dart.
