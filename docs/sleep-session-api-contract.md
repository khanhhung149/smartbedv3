# Hợp đồng API — phiên ngủ

**Phiên bản:** 1 · **Cập nhật:** 2026-08-19
**Backend:** `sleep_pad_AI/backend/app/sessions/` (FastAPI) · **Client:** `smartbedv3/app/`

> **Luật:** sửa endpoint là sửa file này **trong cùng commit**. Hai repo không có CI chung;
> file này là thứ duy nhất giữ chúng không trôi khỏi nhau.

## Backend này là cầu tạm

Đích kiến trúc vẫn là cloud K8s ở `smartbedv3/cloud/` theo `phase-06` của plan
`260713-1019-smartbed-v3-mvp` — quyết định đó **không** bị đảo ngược.

FastAPI `sleep_pad_AI` được dùng ở vòng này vì nó **đang chạy thật và đã có dữ liệu**,
trong khi cả 8 phase của plan MVP chưa bắt đầu và smartbedv3 chưa sinh ra bản ghi nào.
Khi cloud K8s lên, app đổi `baseUrl` và giữ nguyên shape response nếu hợp đồng này được tôn trọng.

## Xác thực

Mọi endpoint cần `Authorization: Bearer <JWT>`.

Token lấy bằng `POST /auth/login` (`{email, password}` → `{access_token}`), hạn 30 ngày
(`jwt_expire_days`). Vòng này app **không có UI đăng nhập** — token nạp qua
`--dart-define=DEV_TOKEN=...` hoặc màn hình cài đặt.

| Mã | Nghĩa | App phải làm gì |
|---|---|---|
| `401` | Thiếu / sai / hết hạn token | Hiện "Dev token hết hạn — lấy token mới" + nút mở cài đặt. **Không** im lặng, không retry vô hạn |
| `404` | Device hoặc phiên không thuộc user | Coi như không tồn tại. Backend cố tình **không** trả `403` |
| `422` | Tham số sai (vd `bucket` ngoài whitelist) | Lỗi lập trình, không phải lỗi người dùng |

## `GET /sessions`

Danh sách phiên của một thiết bị, mới nhất trước.

| Query | Bắt buộc | Mặc định | Ghi chú |
|---|---|---|---|
| `device_id` | có | — | |
| `from` | không | — | ISO 8601, lọc theo `started_at` |
| `to` | không | — | ISO 8601, nửa khoảng mở |
| `limit` | không | `30` | 1–200 |

```json
[
  {
    "id": "586e0011-36cf-4b07-bc3d-bef3693f7740",
    "device_id": "TEST000001",
    "started_at": "2026-08-18T15:00:00Z",
    "ended_at": "2026-08-18T22:59:59Z",
    "duration_s": 28799,
    "hr_avg": 62.1875,
    "hr_min": 52,
    "hr_max": 70,
    "rr_avg": 15.001041412353516,
    "movement_total": 717,
    "snore_total": 96,
    "resp_disorder_total": 7,
    "sit_up_count": 3,
    "wake_count": 4
  }
]
```

**`null` và `0` là hai chuyện khác nhau.** `null` = không đủ dữ liệu hợp lệ để tính.
`hr_avg = 0` không bao giờ là giá trị hợp lệ. App hiện `null` thành `—`, **không** thành `0`.

`ended_at = null` nghĩa là phiên **đang diễn ra** — người vẫn trên giường ở lần dựng gần nhất.
Khi đó `duration_s` cũng `null`.

## `GET /sessions/{id}`

Cùng shape, một object (không phải mảng). `404` khi phiên không tồn tại **hoặc** không thuộc user —
cùng một mã cho cả hai, để người gọi không dò được id của người khác.

## `GET /sessions/{id}/timeline`

Endpoint **duy nhất** màn hình chi tiết cần.

| Query | Mặc định | Giá trị hợp lệ |
|---|---|---|
| `bucket` | `1m` | `1m`, `5m` — whitelist phía server. Giá trị khác → `422` |

```json
{
  "session_id": "586e0011-36cf-4b07-bc3d-bef3693f7740",
  "bucket": "1m",
  "points": [
    {
      "t": "2026-08-18T15:00:00Z",
      "hr": 61.0,
      "rr": 14.899999618530273,
      "movement": 2,
      "snore": 0,
      "resp_disorder": 0,
      "bed_state": "on_bed",
      "events": [2, 4]
    }
  ]
}
```

**Bucket rỗng thì vắng mặt, không phải `null`.** Một đêm 8 tiếng ở `bucket=1m` trả 480 point;
đoạn mất dữ liệu 40 phút trả 440. App phải vẽ **khoảng trống** ở đó — nối liền là bịa dữ liệu
(`docs/system-architecture.md` §6 cấm).

**`bed_state`** suy từ luật `hr > 0 OR rr > 0`, **không** từ `status`.
Không tồn tại mã status nào nghĩa là "đang nằm trên giường".

**`events`** là mã sự kiện thô của giao thức Legact (tr.4 §2.4.1), đã lọc trùng và sắp xếp:

| Mã | Nghĩa | Mã | Nghĩa |
|---|---|---|---|
| `1` | rời giường | `5` | tỉnh |
| `2` | cử động | `6` | vật nặng |
| `3` | ngồi dậy | `7` | ngáy |
| `4` | ngủ | `8` | thở yếu |

## Quy tắc mở rộng

Mỗi point và mỗi phiên là một **object**. Thêm `presence`, `temp`, `ac_on` sau này là
**thêm khoá** — client cũ bỏ qua khoá lạ và không vỡ. App lưu JSON nguyên bản trong cache
sqflite chính vì lý do này.

Đổi tên hoặc xoá khoá là **breaking change**: tăng phiên bản ở đầu file và ghi rõ.

## Cảnh báo về ý nghĩa dữ liệu

Luật `on_bed := hr > 0 OR rr > 0` là **suy luận**, chưa được kiểm chứng. Giao thức Legact
nói `0` cũng có nghĩa "không tính được", nên cảm biến nhiễu trông giống giường trống.
Ngưỡng nằm trong `Settings` (`session_open_seconds`, `session_close_seconds`,
`session_max_minutes`) để chỉnh sau một đêm đo thật.

Đây là thiết bị **wellness**. Mọi chỉ số hiện trên app phải gắn nhãn
**"tham khảo, không dùng chẩn đoán"**.
