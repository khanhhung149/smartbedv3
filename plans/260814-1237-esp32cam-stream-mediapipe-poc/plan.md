---
status: completed
created: 2026-08-14
blocks: [260713-1019-smartbed-v3-mvp]
---

# Plan — ESP32-CAM MJPEG stream + MediaPipe Pose Landmarker PoC

- **Ngày lập:** 2026-08-14
- **Trạng thái:** completed 2026-08-14
- **Nguồn:** `plans/reports/brainstorm-260814-1237-esp32cam-mjpeg-stream-mediapipe-pose-poc-report.md`
- **Loại:** Amendment — **thay thế hoàn toàn** `plans/260813-0934-esp32cam-vl53l0x-camera-node/` (plan đó bị xoá ở Phase 1)
- **Rủi ro tổng:** thấp về an toàn (không actuator, không chuyển động), trung bình về lãng phí công (viết lại từ đầu code đã verify trên phần cứng thật)

## Bối cảnh

Node `firmware/esp32cam-node/` hiện tại: chụp OV2640 → ghi microSD → muốn xem phải rút thẻ. Vòng lặp phản hồi quá chậm để nghiệm thu ý tưởng *quan sát tư thế ngủ bằng vision*. Đổi sang **HTTP MJPEG stream**, OpenCV đọc trực tiếp, chạy **MediaPipe Pose Landmarker** trên laptop.

Hưng chọn **xoá sạch viết lại** thay vì refactor tại chỗ, sau khi đã được trình bày rằng refactor rẻ hơn. Ghi nhận là quyết định của Hưng, không đảo ngược.

## Quyết định đã khoá

| # | Quyết định |
|---|---|
| 1 | Xoá sạch `firmware/esp32cam-node/`, viết mới `firmware/esp32cam-stream/` (tên mới, tránh lẫn lịch sử) |
| 2 | **Giữ nguyên `firmware/camera-node/`** — đó là placeholder Phase 05 (camera Jetson), thiết bị hoàn toàn khác |
| 3 | **Bỏ hẳn VL53L0X** → GPIO4 tự do → hazard **H-26 (đèn flash nhấp nháy) biến mất**, xoá khỏi hazard-analysis |
| 4 | **Giữ H-25**, viết lại cho ngữ cảnh stream (mạnh hơn bản cũ: không ghi frame ra đĩa ở bất kỳ đâu) |
| 5 | Stream: MJPEG `multipart/x-mixed-replace`, **VGA 640×480, JPEG quality ~12** |
| 6 | WiFi: `include/config.h` gitignored + `config.h.example` commit |
| 7 | MediaPipe: **Tasks API** (`vision.PoseLandmarker`), model **`pose_landmarker_full.task`** |
| 8 | Model `.task`: gitignore + script download, không commit binary |
| 9 | PoC chạy **laptop x86_64**, không đụng Jetson vòng này. Đặt ở **`scripts/pose-poc/`**, KHÔNG ở `edge/vision/` (validate session 1) |
| 10 | Rủi ro MediaPipe/Jetson aarch64: **ghi vào docs**, sửa `edge/README.md`, không verify vòng này |
| 11 | Ghim `platform = espressif32@55.3.311` (bài học duy nhất giữ lại từ node cũ) |

## Phases

| # | Tên | Ra được gì | Phụ thuộc | Trạng thái |
|---|---|---|---|---|
| [1](phase-01-xoa-firmware-va-tai-lieu-cu.md) | Xoá firmware + tài liệu cũ | Repo sạch dấu vết node cũ, không còn link chết, BOM MVP khớp thực tế | — | **completed** 14/08 |
| [2](phase-02-firmware-esp32cam-stream.md) | Firmware `esp32cam-stream` | Board stream MJPEG VGA, xem được trên trình duyệt | Phase 1 | **completed** 14/08 |
| [3](phase-03-poc-mediapipe-pose.md) | PoC MediaPipe Pose | `scripts/pose-poc/pose_poc.py` vẽ 33 landmark từ stream | Phase 2 | **completed** 14/08 |
| [4](phase-04-nghiem-thu-va-ghi-rui-ro.md) | Nghiệm thu + ghi rủi ro | DoD đóng, rủi ro Jetson/ánh sáng yếu vào docs | Phase 3 | **completed** 14/08 |

## Phụ thuộc chéo

**`blocks: [260713-1019-smartbed-v3-mvp]`** — plan này sửa `phase-00`, `phase-01`, `phase-03` của plan MVP (chúng đang trỏ vào plan `260813-0934-...` sắp bị xoá, và ghi BOM cũ có VL53L0X). Phải chạy Phase 1 của plan này **trước khi** Phase 01 MVP bắt đầu lắp cụm cảm biến.

**Không đụng `phase-05-camera-edge-ai.md`** của MVP — Phase 05 vẫn là chủ sở hữu MediaPipe Pose production trên Jetson. PoC ở plan này là **công cụ nghiệm thu**, không phải kéo Phase 05 về sớm.

## Tiêu chí chấp nhận (toàn plan)

- [x] `grep -rn "260813-0934"` toàn repo → **0 kết quả** (không còn trỏ tới plan đã xoá). Ba tên **`esp32cam-node`, `vl53l0x`, `MLX90614` cố ý giữ lại** ở một số chỗ dưới dạng **bản ghi lịch sử** — "node cũ ghi SD chỉ đạt 1.5 fps", "VL53L0X đã bị bỏ nên H-26 nghỉ hưu", "đã bỏ MLX90614, không bù lại". Xoá những câu đó đi là mất chính lý do vì sao thiết kế hiện tại như vậy. Tiêu chí gốc viết quá chặt so với ý định của nó
- [x] `./scripts/check-doc-links.sh` sạch — không còn link chết tới `plans/260813-0934-esp32cam-vl53l0x-camera-node/`
- [x] `edge/vision/` vẫn không tồn tại — `edge/` chỉ có `README.md` (ranh giới Phase 05 nguyên vẹn)
- [x] `docs/sensor-characterization.md` đã tạo, có mục node stream với **số đo thật** và mục "Not measured yet" liệt kê rõ cái gì chưa đo
- [x] `pio run -t upload` thành công (COM8 → `/dev/ttyUSB0` qua usbipd), hash verified, serial in `192.168.1.119`
- [x] Hưng mở `http://192.168.1.119/` trên Chrome, thấy video chuyển động mượt (ảnh chụp màn hình 14/08 14:35)
- [x] `cv2.VideoCapture("http://<ip>:81/stream")` đọc frame VGA liên tục **5.5 phút**: 7509 frame, 22.8 fps, 0 lần đọc hỏng, không treo
- [x] `pose_poc.py` vẽ **33 landmark lên người thật**, phòng đủ sáng: phát hiện **343/347 frame = 99%**. Khung hình lúc test chỉ có đầu và vai nên landmark hiện ra ở vùng mặt; **chưa test khung toàn thân từ trên giường**
- [x] `hazard-analysis.md`: H-25 viết lại cho stream, H-26 chuyển sang mục "Retired hazards" kèm lý do + điều kiện quay lại
- [x] `edge/README.md` không còn khẳng định GPU; thay bằng cảnh báo delegate chưa xác định + trỏ sang mục rủi ro §6.1.1

## Ngoài scope

Jetson / `edge/vision/` production, ghi DB, posture request tới mech-handler, hoạt động ban đêm, auth cho HTTP stream, so sánh lite/full/heavy.

## Rủi ro toàn plan

| Rủi ro | Mức | Xử lý |
|---|---|---|
| Ban đêm ảnh gần đen → landmark rác (OV2640 không IR) | Cao, có bằng chứng công bố | Chấp nhận. PoC chỉ nghiệm thu ban ngày. Ghi vào docs |
| MediaPipe trên Jetson aarch64: không wheel chính thức, GPU delegate không nhanh hơn CPU | Cao, chặn Phase 05 | Phase 4 ghi risk. Verify ở vòng sau |
| Mất bản ghi bring-up cũ khi xoá plan | Trung bình | Chấp nhận theo quyết định Hưng. Giữ lại 2 bài học: ghim platform version, PSRAM bắt buộc |
| Viết lại từ đầu lặp bug cũ | Trung bình | Phase 2 checklist mang theo bài học đã biết |

## Validation Log

### Session 1 — 2026-08-14

**Verification Results**
- Claims checked: 18 · Verified: 15 · Failed: 3 · Tier: Standard (4 phases)
- Verified: mọi đường dẫn xoá/sửa ở Phase 1 tồn tại thật; `system-architecture.md:199,206`, `phase-00:37`, `phase-03:22` đúng nội dung như plan mô tả; `edge/README.md:3` có câu "runs MediaPipe Pose on the GPU"; `firmware/camera-node/` tồn tại riêng biệt.
- **Failed 1** — Phase 2 ghi "thêm `.pio/` và `config.h` vào `.gitignore`". Thực tế `.gitignore:15` đã có `.pio/`, `.gitignore:27` đã có `firmware/**/config.h` (glob phủ node mới). → Bỏ bước thừa, thay bằng `git check-ignore -v` để verify.
- **Failed 2** — Phase 3 đặt PoC ở `edge/vision/poc/` nhưng `edge/vision/` **chưa tồn tại**; nó là module Phase 05 theo `edge/README.md`. Tạo nó = âm thầm khởi động Phase 05, mâu thuẫn với định vị PoC trong chính plan. → Dời sang `scripts/pose-poc/`.
- **Failed 3** — Phase 4 trỏ `docs/sensor-characterization.md` với câu mập mờ "nếu file tồn tại". File **không tồn tại** (`docs/` chỉ có `system-architecture.md`, `safety/`, `meetings/`). Plan cũ cũng có tiêu chí trỏ vào file này và chưa bao giờ đóng. → Phase 4 tạo mới file, ghi rõ là Create.

**Quyết định từ phỏng vấn**

| Câu hỏi | Quyết định | Ảnh hưởng |
|---|---|---|
| PoC đặt ở đâu | `scripts/pose-poc/` | Phase 3: đổi toàn bộ đường dẫn, thêm tiêu chí "`edge/vision/` vẫn không tồn tại" |
| `sensor-characterization.md` | Tạo file mới với 1 mục cho node | Phase 4: chuyển từ Modify sang Create, bỏ câu điều kiện mập mờ |
| Code `vl53l0x.*` dirty | Commit trước khi xoá | Phase 1: thêm bước 0, thêm tiêu chí commit bảo toàn đứng trước commit xoá |
| Gate H-25 | Giữ grep, không cần symbol-check | Phase 2: giữ nguyên |

**Phát hiện thêm:** repo có sẵn `scripts/check-doc-links.sh` → đưa vào Phase 1 làm gate kiểm link chết thay vì kiểm thủ công.

### Whole-Plan Consistency Sweep

Đã đọc lại `plan.md` + cả 4 phase file sau khi propagate.

- `edge/vision/poc/` không còn xuất hiện ở bất kỳ file nào ngoài phần giải thích lý do dời đi — đúng chủ đích.
- Định vị "PoC không phải Phase 05" giờ nhất quán giữa `plan.md`, phase-03 và phase-04; trước đó mâu thuẫn với đường dẫn.
- Tiêu chí `.gitignore` không còn trùng lặp giữa phase-02 và phase-03 (chỉ phase-03 thêm `*.task`).
- `docs/sensor-characterization.md` được ghi nhất quán là Create ở phase-04 và ở tiêu chí `plan.md`.
- **Kết quả: 0 mâu thuẫn chưa giải quyết.** Plan đủ điều kiện triển khai.

## Câu hỏi tồn đọng

Cả hai giờ đã có dữ liệu thật để quyết, nhưng **quyết định là của Hưng**, chưa chốt.

**1. Port lên Jetson, hay chuyển sang camera IR gắn thẳng Jetson (hướng C)?**

Dữ liệu nghiêng hẳn về **hướng C**. Lý do không phải hiệu năng — hiệu năng tốt bất ngờ: node đẩy 20–23 fps VGA và laptop suy luận kịp 22.8 fps, nghĩa là kiến trúc "camera rời + stream" hoàn toàn đủ nhanh. Vấn đề là **cái mà nó không bao giờ làm được**: OV2640 không có IR, mà sản phẩm này tồn tại để quan sát người *đang ngủ*, trong phòng *tối*. Port một pipeline chỉ chạy được ban ngày lên Jetson là bỏ công vào nhánh đã biết trước là cụt.

Cộng thêm: MediaPipe trên Orin còn chưa chắc cài được (§6.1.1), nên "port lên Jetson" hiện gánh **hai** rủi ro chưa giải chứ không phải một.

**2. Có lưu landmark ra JSONL không?**

Chưa cần, và nên cân nhắc kỹ trước khi thêm. Vòng này chỉ trả lời "pose có dùng được không", hiển thị live là đủ. Quan trọng hơn: **thêm đường ghi đĩa vào PoC là đụng thẳng H-25** — cả firmware lẫn script hiện không lưu gì cả, và đó là lý do hazard này gọn nhẹ như bây giờ. Nếu cần phân tích sau, phải viết lại H-25 trước khi viết code, không phải ngược lại.
