# app/ — Flutter client

Báo cáo giấc ngủ: mỗi đêm một thẻ, bấm vào xem diễn biến cả đêm trên một trục thời gian.

Thay cho màn 45" 4K LCD của spec 2023 — một tablet nhỏ làm cùng việc với chi phí BOM nhỏ hơn nhiều.
Chạy trên Android (điện thoại + tablet) và web.

## Dữ liệu đến từ đâu

Vòng này app đọc backend Go ở `../presence-ac/backend` (`:8080`, prefix `/api`) — **cầu tạm**,
không phải đích kiến trúc. Đích vẫn là cloud K8s ở `../cloud/` theo `phase-06` của plan
`260713-1019-smartbed-v3-mvp`.

Backend Go đọc thẳng TimescaleDB của `../sleep-pad` qua `POSTGRES_URL`, nên **vẫn cần stack
sleep-pad chạy** để có Postgres — nhưng FastAPI `:8000` thì không còn nằm trên đường đi của app.
Thiếu `POSTGRES_URL` hoặc Postgres chết thì `/api/sessions*` trả `503` còn radar/AC vẫn chạy bình
thường (log-and-continue, cố ý).

Hợp đồng API: [`../docs/sleep-session-api-contract.md`](../docs/sleep-session-api-contract.md).
**Sửa endpoint là sửa file đó trong cùng commit** — hai repo không có CI chung.

## Chạy

Cần hai thứ chạy: Postgres của `sleep-pad/` (nguồn dữ liệu) và backend Go (thứ app gọi).

```bash
cd ../sleep-pad/backend
docker compose -f docker-compose.yml -f docker-compose.dev.yml --env-file .env.dev up -d

cd ../../presence-ac/backend
docker compose up -d
```

`.env` và `.env.dev` không nằm trong repo (gitignore). Máy mới phải chép từ bản clone gốc hoặc
dựng từ `.env.example` trước khi chạy.

Backend Go phải khởi động **sau** khi Postgres nhận kết nối: nó ping một lần lúc start, ping hỏng
thì tắt hẳn `/api/sessions*` cho tới lần restart sau. Postgres chết giữa chừng rồi sống lại thì
`docker restart home-backend`.

Chạy app:

```bash
flutter run -d <device> \
  --dart-define=API_BASE_URL=http://10.0.2.2:8080/api \
  --dart-define=DEVICE_ID=TEST000001
```

### Địa chỉ backend — chỗ mất thời gian kinh điển

`API_BASE_URL` **phải kết thúc bằng `/api`** — client ghép đường dẫn trần (`/sessions`,
`/sessions/{id}/timeline`, xem `lib/core/api_client.dart`), còn router Go treo tất cả dưới `/api`.
Thiếu `/api` thì mọi lời gọi trả `404` dù backend khoẻ.

| Chạy ở đâu | `API_BASE_URL` |
|---|---|
| Emulator Android | `http://10.0.2.2:8080/api` — `10.0.2.2` là localhost của máy chủ nhìn từ emulator |
| Điện thoại thật trên cùng LAN | `http://<IP LAN của máy chủ>:8080/api`. Không phải IP nội bộ của WSL |
| Web (Chrome) | `http://localhost:8080/api`, **nhưng** backend phải cho phép origin đó và header `Authorization` trong CORS |

Không cần build lại để đổi: màn hình **Cài đặt** sửa được cả ba giá trị lúc chạy
(ghi vào `shared_preferences`, đè lên `--dart-define`).

## Token không bao giờ nằm trong repo

Backend Go hiện **không kiểm tra `Authorization`** — `/api` không có middleware auth, nó là
dịch vụ chỉ-LAN. `DEV_TOKEN` vì vậy là tuỳ chọn ở vòng này; client vẫn gắn header sẵn để khi
đích cloud `phase-06` bật auth thì không phải sửa đường gọi.

Khi token có mặt, nó là credential thật, hạn 30 ngày. Nó đi qua `--dart-define` hoặc màn hình
cài đặt — **không có file nào trong repo chứa token**. `.gitignore` chặn thêm `*.env` để phòng hờ.

Khi token hết hạn, app hiện "Dev token hết hạn" kèm nút mở cài đặt. Nó **không** im lặng
trả màn hình trống — đó là triệu chứng đắt nhất để chẩn đoán.

## Cấu trúc

```
lib/
  core/            api_client · app_config · app_router · app_theme · breakpoints
  data/
    models/        sleep_session · timeline_point
    local/         session_cache (sqflite, 2 bảng)
    session_repository.dart
  features/
    sessions/        danh sách đêm
    session_detail/  biểu đồ timeline
    settings/        đổi baseUrl / device / token lúc chạy
```

**Luồng dữ liệu:** đọc cache → trả ngay → gọi mạng → thành công thì ghi đè cache;
thất bại thì giữ cache và bật cờ `isStale`. Token hết hạn là ngoại lệ duy nhất **không**
núp sau cache — người dùng phải biết để đi lấy token mới.

Cache lưu **JSON nguyên bản** của server, không phải một cột mỗi trường. Đổi lấy một chút
dư thừa để server thêm cột (presence, nhiệt độ) mà app cũ không vỡ.

## Hai quy tắc không được vi phạm

**`null` khác `0`.** `null` = không đủ dữ liệu để tính, hiện `—`. `0` = thật sự bằng không.
Gộp hai cái là báo cáo sai cho người dùng.

**Khoảng trống vẽ là khoảng trống.** Đoạn mất dữ liệu không được nối liền.
`../docs/system-architecture.md` §6: *"Dropouts are marked, never invented"*.

## Test

```bash
flutter analyze
flutter test
```

Hai bài `live_*` nói chuyện với backend thật. Không truyền `--dart-define` thì
chúng **tự bỏ qua**, nên `flutter test` trần vẫn xanh trên máy không có backend:

```bash
flutter test test/live_backend_test.dart test/live_offline_test.dart \
  --dart-define=API_BASE_URL=http://localhost:8080/api \
  --dart-define=DEVICE_ID=TEST000001
```

`live_backend_test` chứng minh model đọc đúng payload thật.
`live_offline_test` chứng minh luồng ngoại tuyến bằng cache sqflite thật:
tải thật → trỏ sang cổng chết → vẫn đọc lại được, `isStale = true`.

## Thiết bị wellness

Mọi chỉ số gắn nhãn **"tham khảo, không dùng chẩn đoán"** (`kWellnessDisclaimer`,
định nghĩa **một chỗ** ở `features/sessions/widgets/disclaimer_footer.dart`).
Đây là ràng buộc pháp lý, không phải tuỳ chọn thiết kế.

Luật nhận biết trên giường (`hr > 0 OR rr > 0`) là **suy luận chưa kiểm chứng** —
giao thức nói `0` cũng có nghĩa "không tính được". Chưa có đêm ngủ thật nào xác nhận nó.
