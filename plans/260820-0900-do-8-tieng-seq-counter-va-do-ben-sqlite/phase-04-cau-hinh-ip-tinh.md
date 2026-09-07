---
phase: 4
title: "Cấu hình IP cố định cho máy host"
status: completed
priority: P2
dependencies: []
---

# Phase 04: Cấu hình IP cố định cho máy host

## Overview
Khử ràng buộc "đổi máy host ⇒ flash lại node" bằng một địa chỉ LAN cố định, để sau này chuyển stack từ laptop sang Jetson không phải đụng firmware.

## Requirements

**Chức năng**
- `config.h.example` nói rõ `MQTT_HOST` phải trỏ tới địa chỉ đã reserve, không phải IP tạm.
- Có hướng dẫn đặt DHCP reservation và cách xác nhận đã đúng.
- Ghi rõ hệ quả của việc **không** làm: đổi máy host ⇒ flash lại từng node.

**Ràng buộc**
- `firmware/**/config.h` bị `.gitignore` (đúng — chứa mật khẩu WiFi). Phase này **không** sửa file thật; chỉ sửa file `.example` và tài liệu. Việc đặt trên router và sửa `config.h` là của người vận hành.

## Architecture

`firmware/radar-node/include/config.h.example` hiện có `MQTT_HOST "192.168.1.95"` không kèm giải thích. Địa chỉ này **compile vào firmware**. Hệ quả:

| Tình huống | Chi phí |
|---|---|
| Máy host giữ nguyên IP | 0 |
| IP đổi do DHCP cấp lại | flash lại từng node (hoặc OTA nếu còn tới được — mà tới không được vì broker đã đổi chỗ) |
| Chuyển laptop → Jetson, gán đúng IP cũ | 0 |
| Chuyển laptop → Jetson, IP khác | flash lại từng node |

Đây là lý do đặt reservation ngay bây giờ có giá trị: nó biến quyết định "laptop hay Jetson" thành đảo ngược được, không cần chốt hôm nay.

`config.h.example` cũng đã có sẵn ba dòng `WIFI_STATIC_IP` cho **board** — khác việc này. Chỗ cần cố định là **máy host**, không phải board.

## Related Code Files
- Modify: `firmware/radar-node/include/config.h.example` — comment cho `MQTT_HOST`
- Create hoặc Modify: `docs/` — mục "Địa chỉ máy host" trong runbook Phase 05 (không tạo file riêng, tránh tài liệu vụn)

## Implementation Steps

1. Sửa comment quanh `MQTT_HOST` trong `config.h.example`: nêu địa chỉ này compile vào firmware, phải là IP đã reserve trên router, và đổi nó là phải flash lại node.
2. Kiểm xem `firmware/sleep-pad-node*/` có file cấu hình tương đương không; có thì sửa cùng kiểu để hai đường ống nhất quán.
3. Viết mục "Địa chỉ máy host" cho runbook Phase 05:
   - Lấy MAC của máy host, đặt DHCP reservation trên router.
   - Xác nhận: `ip -4 addr` trên host, đối chiếu với `MQTT_HOST` trong từng `config.h`.
   - Kiểm từ phía node: log ESP-IDF phải hiện "MQTT: nối broker OK".
4. Không đụng `.gitignore`, không commit `config.h` thật.

## Success Criteria
- [ ] `config.h.example` nói rõ hệ quả của việc đổi `MQTT_HOST`
- [ ] Runbook có mục đặt và xác nhận reservation
- [ ] `git status` sạch phần `config.h` — không có credentials nào bị track
- [ ] Node sleep-pad cũng được phủ, không chỉ radar

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| Vô tình commit `config.h` thật | Chỉ sửa `.example`; kiểm `git status` trước khi commit |
| Router không cho đặt reservation | Phương án dự phòng: đặt IP tĩnh trên máy host, ngoài dải DHCP. Ghi cả hai cách vào runbook |
| Hai broker cùng máy, node trỏ nhầm broker | Runbook ghi rõ node nào trỏ cổng nào (1883 vs 1884) |
