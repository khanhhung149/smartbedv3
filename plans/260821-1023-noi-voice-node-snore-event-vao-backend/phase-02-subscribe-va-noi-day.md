---
phase: 2
title: "Subscribe topic và nối dây ở main.go"
status: completed
priority: P1
dependencies: [1]
---

# Phase 02: Subscribe `home/room/snore_event` và nối dây

## Overview

Thêm topic vào `mqttclient`, parse payload, gọi handler; nối handler đó ở `main.go` để ghi qua gói
`internal/snore` của pha 01.

## Requirements

**Chức năng**

- Subscribe `home/room/snore_event` QoS 1, đăng ký trong `OnConnect` để tự re-subscribe sau reconnect.
- Payload sai định dạng → log cảnh báo, bỏ qua, **không** làm chết client.
- Handler nil → không subscribe (đúng mẫu `OnSample`/`OnACCmd` hiện có).

**Phi chức năng**

- Postgres hỏng **không** chặn khởi động; presence/AC/voice chạy tiếp, chỉ mất ghi ngáy.
- Ghi lỗi nuốt thành log, đúng mẫu `record()` trong `main.go`.

## Architecture

### Kiểu payload

`events` là nơi các kiểu payload MQTT đang sống (`events.Motion`, `events.Presence`, `events.Sample`).
Thêm vào đó cho nhất quán:

```go
// SnoreEvent — voice-node báo một đợt ngáy đã xác nhận (3 cửa sổ 1s liên tiếp trên ngưỡng model).
//
// TS là millis() uptime của board, KHÔNG phải epoch: voice-node chưa NTP sync
// (firmware/voice-node/src/main.cpp:1037). Backend tự đóng dấu giờ; TS chỉ dùng để
// xếp thứ tự và để nhận ra board reset (giá trị tụt).
type SnoreEvent struct {
    TS         uint64  `json:"ts"`
    Confidence float64 `json:"confidence"`
    DurationMS uint32  `json:"duration_ms"`
}
```

### Đăng ký subscribe

Theo đúng mẫu đã có trong `internal/mqttclient/client.go`:

```go
const topicSnore = "home/room/snore_event"

// trong Handlers:
//   OnSnore func(events.SnoreEvent)

if h.OnSnore != nil {
    c.Subscribe(topicSnore, 1, func(_ mqtt.Client, msg mqtt.Message) {
        var s events.SnoreEvent
        if err := json.Unmarshal(msg.Payload(), &s); err != nil {
            slog.Warn("payload snore sai", "err", err, "raw", string(msg.Payload()))
            return
        }
        h.OnSnore(s)
    })
}
```

Bọc trong `if h.OnSnore != nil` giống `OnSample`: Postgres hỏng thì `main.go` để handler nil, và
backend không subscribe một topic mà nó không ghi được.

### Nối ở `main.go`

Cùng chỗ đã mở `sessions.NewPGStore`, dùng lại pool:

```go
var recordSnore func(events.SnoreEvent)
if pg != nil {
    if ss, err := snore.Open(pg.DB()); err != nil {
        slog.Warn("không mở được bảng ngáy, bỏ qua ghi ngáy", "err", err)
    } else {
        recordSnore = func(s events.SnoreEvent) {
            ms := int64(s.TS)
            ev := snore.Event{
                T: time.Now().UTC(), DeviceMS: &ms,
                Confidence: s.Confidence, DurationMS: int(s.DurationMS),
                Source: "voice-node",
            }
            if err := ss.Append(context.Background(), ev); err != nil {
                slog.Warn("ghi ngáy lỗi", "err", err)   // nuốt lỗi, không chặn MQTT
            }
        }
    }
}
```

`recordSnore` để nil khi Postgres hỏng → `OnSnore` nil → không subscribe. Không có nhánh nào làm
chết luồng MQTT.

## Related Code Files

- Modify: `cloud/presence-ac/internal/events/events.go` — thêm `SnoreEvent`
- Modify: `cloud/presence-ac/internal/mqttclient/client.go` — `topicSnore`, `Handlers.OnSnore`, subscribe
- Modify: `cloud/presence-ac/cmd/server/main.go` — mở `snore.Store`, dựng `recordSnore`, truyền vào `Handlers`
- Create: `cloud/presence-ac/internal/events/events_snore_test.go` — test unmarshal
- Reference: `firmware/voice-node/src/main.cpp:1035-1044` — nơi payload được dựng

## Implementation Steps

1. Thêm `SnoreEvent` vào `internal/events/events.go` kèm comment về `millis()` (quyết định 5).
2. Thêm `topicSnore` và trường `OnSnore` vào `Handlers`; subscribe trong `OnConnect`, bọc `!= nil`.
3. Ở `main.go`, sau khối `sessions.NewPGStore`, mở `snore.Store` và dựng `recordSnore`.
4. Truyền `OnSnore: recordSnore` vào `mqttclient.New(...)`.
5. Test unmarshal: payload thật từ firmware, payload thiếu trường, payload rác, payload `confidence`
   ngoài `[0,1]`.

## Success Criteria

- [ ] `go build ./...`, `go vet ./...` sạch; `go test ./... -count=1` xanh.
- [ ] Test unmarshal payload thật `{"ts":123456,"confidence":0.873,"duration_ms":3000}` → đúng ba trường.
- [ ] Test payload rác (`not json`) → trả lỗi, hàm gọi không panic.
- [ ] Test payload thiếu `duration_ms` → `DurationMS = 0`, không lỗi (JSON cho phép thiếu trường).
- [ ] Postgres tắt lúc khởi động → backend vẫn lên, log cảnh báo, `/api/state` và `/api/ws` chạy bình thường.
- [ ] `mosquitto_sub -t 'home/room/snore_event'` và backend cùng nhận được một publish thử.

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| Ghi DB chậm chặn callback MQTT (R4) | `Append()` có timeout 3s từ pha 01; lỗi nuốt thành log |
| Postgres hỏng làm chết cả backend | `recordSnore` nil → không subscribe. Đúng mẫu `sl`/`sS` đang dùng cho `/api/samples` và `/api/sessions*` |
| `confidence` ngoài `[0,1]` do model đổi | Không chặn ở tầng này — lưu nguyên giá trị. Chặn ở đây sẽ giấu mất việc model đổi hành vi |
| Subscribe mất sau reconnect | Đăng ký trong `OnConnect`, đúng lý do chú thích sẵn ở `client.go:51` |
