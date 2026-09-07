---
phase: 3
title: "Nghiệm thu: bơm giả rồi board thật"
status: completed
priority: P1
dependencies: [2]
---

# Phase 03: Nghiệm thu

## Overview

Chứng minh đường dây chạy: trước bằng `mosquitto_pub` (kiểm backend độc lập với board), sau bằng
voice-node thật (kiểm cả model lẫn đường truyền).

## Requirements

**Chức năng**

- Bơm payload giả → đúng một dòng trong `room_snore_events`.
- Board thật giả tiếng ngáy → serial in publish OK **và** DB có dòng tương ứng.
- Không rò sang bảng của pad.

**Phi chức năng**

- Mọi lệnh nghiệm thu ghi lại được, chạy lại được.

## Architecture

Hai lớp tách bạch, vì chúng hỏng theo hai kiểu khác nhau:

| Lớp | Kiểm cái gì | Hỏng thì lỗi ở đâu |
|---|---|---|
| `mosquitto_pub` | Subscribe, parse, ghi DB | Backend |
| Board thật | Model, publish, đường MQTT | Firmware hoặc mạng |

Bơm giả trước. Nếu bỏ qua lớp này rồi board không ra dòng nào, không biết lỗi ở model hay ở backend.

### Broker nào

voice-node nói với **`home-mqtt`, cổng 1883, có xác thực** (`allow_anonymous false`) — không phải
broker của sleep-pad ở cổng 1884. Dùng đúng credential trong `cloud/presence-ac/.env`.

### Lệnh bơm giả

```bash
cd /mnt/d/smartbedv3/cloud/presence-ac && set -a && . ./.env && set +a
docker exec home-mqtt mosquitto_pub -h localhost -p 1883 \
  -u "$MQTT_USER" -P "$MQTT_PASS" \
  -t 'home/room/snore_event' \
  -m '{"ts":123456,"confidence":0.873,"duration_ms":3000}'
```

Kiểm:

```sql
SELECT t, device_ms, confidence, duration_ms, source
FROM room_snore_events ORDER BY t DESC LIMIT 5;
```

## Related Code Files

- Create: `plans/260821-1023-noi-voice-node-snore-event-vao-backend/reports/` — báo cáo nghiệm thu
- Modify: `docs/runbook-dem-do-8-tieng.md` — thêm mục kiểm ngáy nếu runbook đó còn dùng

## Implementation Steps

1. Bơm payload hợp lệ, xác nhận đúng một dòng, `confidence = 0.873`, `device_ms = 123456`.
2. Bơm payload rác (`-m 'not json'`) → log cảnh báo, **không** thêm dòng, backend còn sống.
3. Bơm payload thiếu `duration_ms` → dòng có `duration_ms = 0`, không lỗi.
4. Ghi lại `SELECT count(*) FROM min_data WHERE snore_count > 0` **trước và sau** — phải bằng nhau.
5. Bật voice-node, mở serial, giả tiếng ngáy 30–60 giây. Đối chiếu từng sự kiện serial với từng dòng DB.
6. Để phòng yên tĩnh 10 phút, đếm sự kiện — đây là phép đo báo nhầm đầu tiên.
7. Reset board, kiểm `device_ms` tụt về gần 0 trong khi `t` vẫn tăng.
8. Tắt Postgres, bơm payload, xác nhận backend không chết và presence/AC vẫn chạy.
9. Viết báo cáo nghiệm thu, ghi cả số sự kiện lúc yên tĩnh.

## Success Criteria

- [ ] Payload hợp lệ → đúng một dòng, giá trị khớp từng trường.
- [ ] Payload rác → 0 dòng, log cảnh báo, backend sống.
- [ ] Payload thiếu trường → `duration_ms = 0`, không lỗi.
- [ ] `min_data.snore_count` không đổi trước/sau — không rò sang bảng pad.
- [ ] Board thật: mỗi `[snore] publish … -> OK` trên serial ứng đúng một dòng DB.
- [ ] 10 phút yên tĩnh: số sự kiện được **ghi lại**, dù bằng 0 hay không.
- [ ] Board reset: `device_ms` tụt, `t` vẫn tăng đều.
- [ ] Postgres tắt: backend sống, `/api/state` trả 200.
- [ ] Báo cáo nghiệm thu ghi rõ số sự kiện lúc yên tĩnh **là phép đo báo nhầm đầu tiên và chưa đủ để
      kết luận** — một mẫu 10 phút không thay được một đêm có nhãn (R2).

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| Nghiệm thu "xanh" che mất việc model chưa đánh giá thực địa (R2) | Bắt buộc ghi mục cảnh báo trong báo cáo. Phòng yên tĩnh 10 phút **không phải** bằng chứng model tốt |
| Nhầm broker (1883 vs 1884) | Ghi rõ trong lệnh. Hai broker khác chính sách xác thực — nhầm là `not authorised` |
| Giả tiếng ngáy bằng loa điện thoại | Không áp dụng ở đây: mic **nghe được** loa. Khác pad áp điện. Nhưng nên ghi rõ đã dùng cách nào, vì loa và ngáy thật cho phổ khác nhau |
| Board đang bận stream wakeword lúc thử | Snore chạy task riêng core 0, có mutex với wakeword. Nếu thấy bỏ sót, kiểm log tranh chấp trước khi đổ cho model |
