---
phase: 2
title: "Test qua đêm thật, đối chiếu báo cáo"
status: pending
priority: P1
dependencies: [1]
---

# Phase 2: Test qua đêm thật

## Overview
Chạy toàn bộ pipeline (radar + sleep-pad + voice-node + presence-ac backend đã sửa ở Phase 1) qua ít nhất 1 đêm ngủ thật, sáng hôm sau gọi API morning-report và đối chiếu bằng cảm nhận thực tế (không cần thiết bị đối chứng y tế — đây là sanity check, không phải validation lâm sàng).

## Requirements
- Functional: người dùng ngủ như bình thường ≥1 đêm với đủ 3 node cắm điện, sáng hôm sau gọi API lấy report.
- Non-functional: không được có gap dữ liệu do node rớt kết nối/reboot — nếu có, phải thấy rõ trong log (không được để log im lặng như vụ Postgres mất kết nối 19 tiếng trước đó).

## Related Code Files
- Không sửa code trong phase này trừ khi phát hiện bug khi test — nếu có, quay lại Phase 1/2 sửa rồi build lại trước khi test tiếp.

## Implementation Steps
1. Trước khi ngủ: xác nhận cả 2 docker stack (`presence-ac`, `sleeppad`) đang chạy (`docker compose ps`), 3 node (radar, sleep-pad, voice) đã kết nối MQTT (kiểm tra qua `mosquitto_sub` nhanh hoặc log).
2. Ghi lại giờ đi ngủ, số lần rời giường thực tế (nếu nhớ được), có ngáy hay không — để đối chiếu tay.
3. Sáng dậy: gọi `GET /sessions/{device_id}/morning-report?from=<giờ ngủ, UTC>&to=<giờ thức, UTC>` (nhớ đổi giờ local Bangkok UTC+7 sang UTC trước khi gọi, tránh nhầm như vụ "05:21:28 là mấy giờ" đã gặp trong session).
4. Đối chiếu: tổng thời gian on-bed có gần đúng giờ ngủ thực tế không (sai số chấp nhận vài chục phút, không cần chính xác giây); số off-bed transitions có khớp trí nhớ không; số snore_count có khớp không (đối chiếu thêm với `home/room/snore_event` MQTT log nếu cần).
5. Nếu số liệu sai lệch lớn (>50% hoặc thiếu hẳn 1 nguồn dữ liệu) → quay lại Phase 1 tìm nguyên nhân (network unreachable kiểu Postgres trước đó là ví dụ đã gặp — kiểm tra log của presence-ac trước khi kết luận là bug logic).

## Success Criteria
- [ ] Morning report trả về số liệu hợp lý (không phải toàn số 0 hoặc null do lỗi kết nối).
- [ ] Người dùng xác nhận bằng lời: số liệu "nghe hợp lý" so với đêm ngủ thật (không cần khớp tuyệt đối).
- [ ] Không phát hiện gap dữ liệu im lặng nào trong log của cả 2 backend suốt đêm test.

## Risk Assessment
- Risk: lặp lại lỗi "Postgres mất kết nối, không retry, im lặng" đã gặp — mitigation: kiểm tra log NGAY sau khi thức dậy trước khi tin vào con số API trả về, không chỉ tin API.
- Risk: 1 đêm test không đủ nếu có sự cố phần cứng (giống vụ GPIO33 hỏng) — nếu đêm đầu fail vì phần cứng, không tính là fail của Phase 2 logic, thử lại đêm sau sau khi fix phần cứng.
