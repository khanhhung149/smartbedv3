---
date: 2026-08-21
phase: 3
scope: backend-mqtt-fake-payload
status: partial
---

# Phase 03 backend MQTT giả

## Môi trường

- Backend: `home-backend`, image `presence-ac-backend`, port `8080`.
- Broker đúng cho voice-node: `home-mqtt`, port `1883`.
- Postgres: `sleeppad-postgres`, database `sleeptech`.
- Backend log lúc khởi động:
  - mở SQLite history OK.
  - mở Postgres sleep sessions OK.
  - MQTT connected OK.

## Mốc trước

```sql
SELECT count(*) FROM min_data WHERE snore_count > 0;
-- 157

SELECT count(*) FROM room_snore_events;
-- 0
```

## Payload hợp lệ

```bash
docker exec home-mqtt mosquitto_pub -h localhost -p 1883 \
  -u "$MQTT_USER" -P "$MQTT_PASS" \
  -t 'home/room/snore_event' -q 1 \
  -m '{"ts":123456,"confidence":0.873,"duration_ms":3000}'
```

Kết quả:

```sql
SELECT t, device_ms, confidence, duration_ms, source
FROM room_snore_events ORDER BY t DESC LIMIT 5;

-- 2026-08-21 06:12:56.085934+00 | 123456 | 0.873 | 3000 | voice-node
```

Đạt: backend tự đóng dấu `t`; `device_ms`, `confidence`, `duration_ms`, `source` khớp payload/contract.

## Payload rác

```bash
docker exec home-mqtt mosquitto_pub -h localhost -p 1883 \
  -u "$MQTT_USER" -P "$MQTT_PASS" \
  -t 'home/room/snore_event' -q 1 \
  -m 'not json'
```

Kết quả log:

```text
WARN payload snore sai err="invalid character 'o' in literal null (expecting 'u')" raw="not json"
```

Đạt: log cảnh báo, không chèn dòng.

## Payload thiếu duration_ms

```bash
docker exec home-mqtt mosquitto_pub -h localhost -p 1883 \
  -u "$MQTT_USER" -P "$MQTT_PASS" \
  -t 'home/room/snore_event' -q 1 \
  -m '{"ts":789,"confidence":0.5}'
```

Kết quả:

```sql
SELECT device_ms, confidence, duration_ms, source
FROM room_snore_events ORDER BY t DESC LIMIT 5;

-- 789    | 0.5   | 0    | voice-node
-- 123456 | 0.873 | 3000 | voice-node
```

Đạt: thiếu `duration_ms` được JSON decode thành 0, không lỗi.

## Không rò sang bảng pad

```sql
SELECT count(*) FROM min_data WHERE snore_count > 0;
-- 157
```

Đạt: không đổi so với mốc trước.

## Backend còn sống

Trong compose network:

```bash
docker exec home-asr python -c "import urllib.request; r=urllib.request.urlopen('http://backend:8080/api/state', timeout=3); print(r.status)"
-- 200
```

## Chưa làm

- Board thật: đối chiếu serial `[snore] publish ... -> OK` với dòng DB.
- 10 phút phòng yên tĩnh: ghi số event, đây chỉ là phép đo báo nhầm ban đầu.
- Reset board: kiểm `device_ms` tụt trong khi `t` vẫn tăng.
- Tắt Postgres: xác nhận backend vẫn chạy và presence/AC/voice không ảnh hưởng.
