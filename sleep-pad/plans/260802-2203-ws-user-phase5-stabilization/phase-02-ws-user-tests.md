---
phase: 2
title: "Test /ws/user (4 case)"
status: pending
priority: P1
dependencies: [1]
---

# Phase 2: Test `/ws/user`

## Overview

4 case theo spec Phase 5 của plan gốc: auth reject, combined frame khi pad publish,
watch snapshot fields populated, ping heartbeat.

Đối tượng test: `backend/app/data/router.py` — `websocket_user` (~110 LOC),
`_build_combined`, `_merge_pad_frame`, `_pad_online`, `_watch_payload`.

## Requirements

**Functional**
- Thiếu token → close 1008 "missing token"
- Token sai → close 1008 "invalid token"
- Token hợp lệ → nhận frame khởi tạo `{"type":"combined", ...}` ngay khi connect
- Publish vào `realtime:{device_id}` → nhận frame có `pad.hr`/`pad.rr` đúng
- `pad.online` = true sau khi có frame
- Publish vào `watch_update:{user_id}` → push snapshot watch ngay
- Ping heartbeat có bắn

**Non-functional**
- Toàn bộ test (trừ ping) chạy < 5s

## Architecture

### WS test client

Dùng `starlette.testclient.TestClient.websocket_connect` (sync, chạy app trong thread
riêng có event loop riêng). Publish vào Redis từ thân test bằng client redis đồng bộ
hoặc qua portal — cả hai đều hoạt động vì WS handler chạy ở loop khác.

```python
with TestClient(test_app) as c:
    with c.websocket_connect(f"/ws/user?token={jwt}") as ws:
        first = ws.receive_json()          # frame khởi tạo
        redis_sync.publish(f"realtime:{pad_id}", json.dumps({...}))
        frame = ws.receive_json()
```

### Auth reject — kiểm gì

`websocket_user` gọi `websocket.close(code=1008)` **trước** `accept()`. Starlette
TestClient raise `WebSocketDisconnect` khi vào context manager. Bắt exception và
assert `exc.code == 1008`.

### Frame khởi tạo luôn có

`router.py:262` gửi `_build_combined(...)` ngay sau `accept()` trước khi vào loop.
Mọi test phải đọc frame này trước rồi mới publish — nếu không sẽ assert nhầm vào nó.

### Ping heartbeat — điểm quyết định

Ping chỉ bắn khi `pubsub.get_message(timeout=30)` trả `None`, tức **30 giây không có
message** (`router.py:265-283`). Ba lựa chọn:

| Cách | Ưu | Nhược |
|---|---|---|
| **(a) Test chờ thật, đánh dấu `@pytest.mark.slow`** | Không đụng code production — đúng ràng buộc "đừng sửa gì cả" | 1 test tốn 30s; loại khỏi lần chạy mặc định bằng `-m "not slow"` |
| (b) Tách timeout thành hằng số module rồi monkeypatch | Test nhanh | Sửa code production, trái ràng buộc user |
| (c) Bỏ test ping | Nhanh nhất | Thiếu 1 mục Phase 5 |

**Khuyến nghị (a).** Ràng buộc user rõ ràng. Nếu 30s không chấp nhận được thì hỏi user
trước khi chuyển sang (b) — đó là sửa code, phải có phê duyệt.

## Related Code Files

**Create**
- `backend/tests/test_ws_user.py`

**Read only**
- `backend/app/data/router.py:100-330`
- `backend/app/redis_client.py` (`online_key`)
- `backend/app/auth/service.py` (`decode_access_token` — để ký JWT test đúng định dạng)

**Không sửa** file backend nào.

## Implementation Steps

1. `test_ws_user_missing_token_closes_1008` — connect không có `?token=`
2. `test_ws_user_invalid_token_closes_1008` — token rác
3. `test_ws_user_initial_frame` — token hợp lệ, user có 1 pad → frame đầu có
   `type == "combined"`, `pad.device_id` đúng, `pad.online` false (chưa có key Redis)
4. `test_ws_user_pad_frame_merges` — publish `realtime:{pad_id}` với
   `{"device_id":..., "heart_rate":72, "resp_rate":15}` → frame kế có `pad.hr == 72`,
   `pad.rr == 15`, `pad.online` true, có `hr_at`/`rr_at`
5. `test_ws_user_watch_snapshot_present` — seed `watch_data` rồi connect → frame đầu
   có `watch.spo2`/`watch.steps`/`watch.systolic` đúng
6. `test_ws_user_watch_update_pushes` — publish `watch_update:{user_id}` → nhận frame
   mới với snapshot watch đã cập nhật
7. `test_ws_user_ping_heartbeat` với `@pytest.mark.slow` — không publish gì, chờ >30s,
   assert nhận `{"type":"ping"}`
8. Đăng ký marker `slow` trong `pytest.ini`; chạy mặc định `-m "not slow"`

## Success Criteria

- [ ] 6 test nhanh pass, tổng < 5s
- [ ] Test `slow` pass khi chạy `pytest -m slow`
- [ ] Không sửa dòng nào trong `backend/app/`
- [ ] Test độc lập thứ tự (chạy `-p no:randomly` và ngẫu nhiên đều xanh)

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| Race: publish trước khi handler subscribe xong | Luôn đọc frame khởi tạo trước — nó chứng minh handler đã qua `pubsub.subscribe` |
| TestClient WS + async pubsub deadlock | `receive_json()` có timeout; nếu treo, chuyển sang `httpx-ws` với `ASGITransport` |
| `_merge_pad_frame` giữ giá trị cũ giữa các test | Mỗi test một WS connection mới → `pad` dict mới |
| JWT test không khớp thuật toán | Ký bằng đúng `jwt_secret` + `jwt_algorithm` từ `get_settings()` |
