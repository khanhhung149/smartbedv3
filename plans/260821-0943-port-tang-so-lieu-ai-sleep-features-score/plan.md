---
type: plan
date: 2026-08-21 09:43
slug: port-tang-so-lieu-ai-sleep-features-score
status: abandoned
priority: P2
branch: master
mode: standard
brainstorm: plans/reports/brainstorm-260821-0943-port-tang-ai-sleep-tech-projection-phut-tu-sec-data-report.md
blockedBy: [260819-0909-smartbed-flutter-sleep-session-app]
blocks: []
---

# Đưa pad về chế độ giám sát của hãng, rồi port tầng số liệu `ai/`

Đổi firmware để pad phát **khung `0x86` mỗi phút** như hãng thiết kế, rồi port
`sleep_features.py` + `sleep_score.py` từ `github.com/Sleep-Tech-AI/sleep-pad-ai` **nguyên văn**.

**Nguồn:** [brainstorm 21/08](../reports/brainstorm-260821-0943-port-tang-ai-sleep-tech-projection-phut-tu-sec-data-report.md)

## Kế hoạch này đã đổi hình một lần

Bản đầu định tự dựng một **tầng chiếu** gộp `sec_data` theo giây thành dòng-theo-phút, vì tưởng pad
không phát khung phút được. Cửa validate bác bỏ hướng đó.

Tài liệu hãng (`数据传输协议英文版.xlsx`, mục 2.4) nói rõ:

> Frame type sent by the host computer `[0x04]`: Working mode setting.
> `[1byte data]` = **`0x20` Enter the host computer monitoring mode**

Trong chế độ `0x20`, thiết bị phát **cả hai**: `0x85` mỗi giây và `0x86` mỗi phút. Khung `0x86` mang
sẵn `[number of body movements]`, `[number of snoring]`, `[Number of respiratory disorders]` do chính
pad tính.

Firmware đang gửi ASCII `TAOSG`, gần như chắc chắn đẩy pad vào `0x30` = *data debugging mode* (lệnh
`[0x07]` liệt kê các chế độ) — đó là lý do ta nhận khối 66 byte chứa 25 mẫu áp điện thô.

**Đường khung `0x7D` trong firmware còn nguyên và đã nối đầu cuối:** `uart-parser.cpp:8` parse
header, `decode0x86()` ở dòng 101, `parser.onMinData = on_min_data` → `mqtt_publish_min` →
`subscriber._insert_min` → bảng `min_data`. Cả đường ống đang ngủ đông vì thiếu đúng một lệnh.

## Cái gì biến mất so với bản đầu

| Thứ | Bản đầu | Bản này |
|---|---|---|
| Tầng chiếu phút | tự viết ~150 dòng | **không cần** |
| Ánh xạ mã 0 → 4 | tự nghĩ | **không cần** — pad phát đúng thang |
| Mở rộng `OCCUPIED` | lệch upstream | **không cần** |
| Luật ưu tiên mã đại diện phút | tự nghĩ, không tài liệu hậu thuẫn | **không cần** — pad tự phán |
| `snore_count`, `resp_disorder` | suy từ mã giây | **số thật do pad đếm** |
| `sleep_features.py` | port + 2 chỗ lệch | **port nguyên văn** |

Ba rủi ro nặng nhất của bản đầu tan hết, vì chúng chỉ tồn tại do cố mô phỏng thứ thiết bị vốn làm sẵn.

## Quyết định đã khoá

| # | Quyết định | Lý do |
|---|---|---|
| 1 | Đưa pad vào chế độ `0x20` bằng khung `[0x04][0x20]` | Hướng của hãng. Xoá toàn bộ phần tự nghĩ |
| 2 | **Giữ đường TAOSG làm dự phòng** | Chờ khung `0x85` trong N giây; không thấy thì lùi về `TAOSG`. Cả hai đường đã có parser nên lùi về là an toàn |
| 3 | Gửi `[0x0B]` hiệu chỉnh đồng hồ ngay sau khi vào chế độ | Tài liệu: *"Calibrating the clock is very important… please calibrate the clock in the first step!"* Ở chế độ khung, mốc thời gian do thiết bị gắn |
| 4 | Port `sleep_features.py` và `sleep_score.py` **nguyên văn** | Không còn lý do gì để lệch |
| 5 | Chưa nối LLM | Hai file này là số học thuần, không phụ thuộc ngoài |
| 6 | Cửa sổ phiên lấy từ bảng `sleep_sessions` sẵn có | Không dùng `SESSION_GAP_HOURS` của upstream. Hai định nghĩa "một đêm" sẽ mâu thuẫn |
| 7 | Giữ `AND time >= devices.paired_at` | Ranh giới sở hữu. Đã xác minh cột tồn tại NOT NULL |
| 8 | **Giữ nguyên** thành phần hô hấp của `sleep_score` | Quyết định của Hưng. Rủi ro giảm mạnh ở bản này vì `rdi_proxy` sẽ là số thật do pad đếm |
| 9 | Chấp nhận `sleep_sessions.hr_avg` khác `SleepFeatures.hr_mean` | Hai định nghĩa khác nhau: "khi có người nằm" và "khi đang ngủ". Ghi rõ, không hợp nhất. Hưng: sau này sẽ chuyển sang Python thuần |
| 10 | Không thêm dependency | Hai file upstream chỉ dùng `dataclasses`, `datetime`, `statistics` |

## Các pha

| # | File | Nội dung | Ưu tiên | Phụ thuộc | Trạng thái |
|---|---|---|---|---|---|
| 01 | [phase-01-firmware-che-do-giam-sat.md](phase-01-firmware-che-do-giam-sat.md) | Firmware: dựng khung `0x7D`, vào chế độ `0x20`, hiệu chỉnh đồng hồ, tự lùi về TAOSG | P1 | — | **blocked — R1 đã xảy ra thật, xem phase-01** |
| 02 | [phase-02-port-sleep-features.md](phase-02-port-sleep-features.md) | Port `sleep_features.py` nguyên văn | P1 | 01 | completed (code đúng, chưa có `min_data` thật để chạy trên) |
| 03 | [phase-03-port-sleep-score.md](phase-03-port-sleep-score.md) | Port `sleep_score.py` nguyên văn | P2 | 02 | completed (cùng lý do trên) |
| 04 | [phase-04-nghiem-thu-du-lieu-that.md](phase-04-nghiem-thu-du-lieu-that.md) | Loader theo `sleep_sessions`, script nghiệm thu, sửa harness test | P1 | 03 | completed (27/27 test xanh, xác nhận thật 24/08); mục nghiệm thu trên `min_data` thật **chưa làm được** — pad không cho dữ liệu |

Pha 01 là pha rủi ro duy nhất và chặn tất cả — không có `min_data` thì ba pha sau không nghiệm thu được.
**Xác nhận 24/08:** rủi ro đó đã xảy ra thật. Pad không phản hồi khung `0x07`/`0x04` qua 3 lần bắt log
độc lập trên phần cứng thật. Xem `phase-01-firmware-che-do-giam-sat.md` để có bằng chứng đầy đủ.

## Mốc đối chiếu

Phiên đêm 21/08, `CNU10CDADC`, `2026-08-20 17:13:43Z` → `18:39:20Z` (5.136 giây, 87 phút).

Sau khi pad vào chế độ `0x20`, các số dưới đây dùng để **đối chiếu chéo** giữa số pad tự tính và số
suy từ `sec_data` — lệch nhiều là dấu hiệu hiểu sai giao thức:

| Đại lượng suy từ `sec_data` | Giá trị |
|---|---|
| Đợt cử động (mã 2) | 115 toàn cục / 110 trong phút có người |
| Mã 3, 5, 7, 8 | 0 |
| `hr_avg` / `rr_avg` (mọi giây có người) | 56,8 / 15,5 |
| `hr_min` / `hr_max` (theo giây) | 52 / 81 |

**Cảnh báo diễn giải:** các số này *không phải* kỳ vọng cho `SleepFeatures`. Upstream tính sinh hiệu
**chỉ trên phút thuộc `ASLEEP`**, nên `hr_mean` sẽ thấp hơn `sleep_sessions.hr_avg` một cách có hệ
thống. Đo thử trên dữ liệu 21/08: 55,2 so với 56,8, và `hr_max` 64 so với 81 (đỉnh 81 rơi vào phút
cử động — có người nhưng không phải đang ngủ). Cả hai đều đúng theo định nghĩa của mình (quyết định 9).

## Tiêu chí nghiệm thu

- [ ] Pad vào chế độ `0x20`: log firmware thấy khung `0x84` + nội dung `0x20` xác nhận.
- [ ] `min_data` nhận đúng **1 dòng/phút** cho `CNU10CDADC` trong ít nhất 10 phút liên tục.
- [ ] `sec_data` vẫn nhận ~1 dòng/giây — chuyển chế độ không làm mất đường cũ.
- [ ] Dòng `min_data` có `status` trong `{1,2,3,4,5,6}` và `movement`/`snore_count`/`resp_disorder`
      không NULL.
- [ ] Đối chiếu chéo: số đợt cử động pad báo trong `min_data.movement` cùng bậc độ lớn với số suy từ
      `sec_data.status = 2` trên cùng cửa sổ.
- [ ] `extract()` trả `SleepFeatures` khác `None` trên một phiên có `min_data`.
- [ ] `sleep_score` tái lập: chạy hai lần cùng phiên ra cùng điểm.
- [ ] `warnings` có mục "shorter than one hour" với phiên dưới 60 phút.
- [ ] `pytest` xanh toàn bộ (hiện 19 test) bằng **một lệnh**, không `docker cp` thủ công.

## Rủi ro

| # | Rủi ro | Mức | Giảm thiểu |
|---|---|---|---|
| R1 | LSM-800-T không hỗ trợ `[0x04][0x20]`, mất đường dữ liệu đang chạy | **Cao — ĐÃ XẢY RA, xác nhận 24/08** | Cơ chế lùi hoạt động đúng: không mất `sec_data`. Nhưng `min_data` là ngõ cụt trên phần cứng này — cần hướng khác (hỏi hãng về firmware pad, thử pad khác, hoặc dừng nhánh `0x20`) |
| R2 | Chế độ `0x20` không phát mã 7/8 nên `snore_total` vẫn 0 | Trung bình | Khung `0x86` có trường `number of snoring` riêng, độc lập với mã trạng thái — nên vẫn đếm được dù mã phút chỉ tới `0x06`. Vẫn cần bài thử ngáy để xác nhận |
| R3 | Đồng hồ pad lệch làm mốc `0x86` sai | Trung bình | Quyết định 3: gửi `[0x0B]` mỗi lần vào chế độ. Backend vẫn đóng dấu `received_at` để đối chiếu |
| R4 | Hai nguồn nhịp tim khác nhau gây nhầm lẫn | Thấp | Quyết định 9: ghi rõ hai định nghĩa. App chưa hiện `SleepFeatures` nên chưa xung đột thực tế |
| R5 | Port xong không ai tiêu thụ kết quả | Trung bình | Chấp nhận vòng này. Xem "Ngoài phạm vi" |

## Ngoài phạm vi

- `narrator.py`, `fact_guard.py`, `prompts.py`, `ai/router.py`, `ai/demo.py`.
- **Endpoint đọc.** Sau pha 04, `SleepFeatures`/`SleepScore` chỉ chạy được qua script nghiệm thu,
  **app không thấy gì**. Muốn app dùng cần thêm một vòng nữa.
- Gỡ bỏ đường TAOSG và `feedTaos()` — giữ làm dự phòng (quyết định 2).
- Đổi giao diện app để hiện điểm giấc ngủ.
- Hợp nhất `sleep_sessions.hr_avg` với `SleepFeatures.hr_mean`.

## Liên quan

- **Phụ thuộc:** [`260819-0909-smartbed-flutter-sleep-session-app`](../260819-0909-smartbed-flutter-sleep-session-app/plan.md)
  — đã giao `sleep_sessions`, `sessions/rules.py`, `sessions/service.py`.
- **Nguồn ngáy thứ hai, không chặn nhau:** [`260821-1023-noi-voice-node-snore-event-vao-backend`](../260821-1023-noi-voice-node-snore-event-vao-backend/plan.md)
  — lấy ngáy từ mic voice-node. Khác node, khác broker, khác bảng. Kế hoạch này trả lời "**người nằm
  trên pad** có ngáy không"; kế hoạch kia trả lời "**phòng này** có tiếng ngáy không". Lưu tách nguồn,
  không gộp số.
- **Không chặn nhau:** [`260820-0900-do-8-tieng-seq-counter-va-do-ben-sqlite`](../260820-0900-do-8-tieng-seq-counter-va-do-ben-sqlite/plan.md)
  — khác đường ống (radar/SQLite). Pha 06 của kế hoạch đó đang ghi `blocked — chờ board`, nhưng board
  đã nạp 21/08 và radar chạy 9,83 Hz với `seq` liền mạch; nên xem lại trạng thái.

## Câu chưa trả lời

- Pad có vào được chế độ `0x20` không? Chặn toàn bộ kế hoạch. Pha 01 trả lời.
- Pad có phát `number of snoring` khác 0 không? Cần bài thử ngáy: nằm lên pad tự phát tiếng ngáy bằng
  cổ họng 30–60 giây. **Không dùng loa điện thoại** — pad là cảm biến áp điện, nghe rung cơ học qua
  đệm chứ không nghe âm thanh trong không khí.
- Sau khi có `SleepScore`, app hiện ở đâu?

## Validation Log

### Session 1 — 2026-08-21

**Verification Results**
- Tier: Standard (4 pha) — Fact Checker + Contract Verifier
- Claims checked: 14 | Verified: 12 | Failed: 2
- Failures:
  - `plan.md` (bản đầu) kỳ vọng `hr_min = 52`, `hr_mean = 56,8`. Sai: đó là thống kê **theo giây**.
    Sau khi gộp phút, `hr_min` = 53, `hr_mean` = 57,5. Tính riêng trên phút `ASLEEP` thì còn 53 / 55,2.
  - `plan.md` (bản đầu) kỳ vọng `movement_total = 115`. Sai: `extract()` chỉ cộng qua phút thuộc
    `OCCUPIED`, nên là **110** — 5 đợt rơi vào 2 phút bị xếp là rời giường.

**Quyết định trong buổi**

| Câu hỏi | Quyết định |
|---|---|
| Kiểu `hr_min`/`hr_max` | Số nguyên, theo upstream (`min_data.heart_rate` là `smallint`, khung `0x86` mang 1 byte) |
| Luật ưu tiên viết ở mấy nơi | Một bản duy nhất — nhưng câu hỏi trở thành vô nghĩa sau khi bỏ tầng chiếu |
| 5 đợt cử động trong phút rời giường | Giữ ngữ nghĩa upstream (cộng qua `OCCUPIED`) |
| Hai nhịp tim khác nhau | Chấp nhận, ghi rõ hai định nghĩa (quyết định 9) |
| Luật cho mã 2 ở mức phút | **Bỏ hẳn cách làm ở mức phút — chuyển sang hướng hãng** |

**Phát hiện quyết định lại hình dạng kế hoạch**

1. Tập mã trạng thái ở mức **phút** (`0x86`) chỉ tới `0x06` — **không có `0x07` ngáy, `0x08` thở yếu**.
   Hai thứ đó là trường đếm riêng. Hệ quả: `STATUS_SNORING`/`STATUS_WEAK_BREATHING` trong `OCCUPIED`
   và `ASLEEP` của upstream là **code chết**, không dòng `min_data` thật nào khớp được.
2. Luật `BOOL_OR` cho mã 2 ở bản đầu làm hiệu suất giấc ngủ ra **57,6%** cho một đêm ngủ liền mạch
   (49/85 phút). Ngưỡng đa số cho 95,3%. Sai lệch đủ lớn để bác cả cách tiếp cận.
3. Tài liệu hãng có lệnh `[0x04][0x20]` vào chế độ giám sát, phát cả `0x85` lẫn `0x86`. Firmware đã
   có sẵn parser khung `0x7D` và đường ghi `min_data`, chỉ thiếu lệnh.

→ Bỏ tầng chiếu. Pha 01 đổi từ "dựng dòng-theo-phút bằng SQL" thành "đưa pad về chế độ giám sát".

### Whole-Plan Consistency Sweep

- `plan.md`: viết lại toàn bộ. Bảng pha, quyết định, rủi ro, tiêu chí nghiệm thu đã theo hình dạng mới.
- `phase-01-tang-chieu-phut.md`: **xoá**, thay bằng `phase-01-firmware-che-do-giam-sat.md`.
- `phase-02`: gỡ hai chỗ lệch có chủ ý; nguồn đổi từ tầng chiếu sang `min_data` thật.
- `phase-03`: cập nhật ghi chú rủi ro `_breathing_credit` — `rdi_proxy` giờ là số thật do pad đếm.
- `phase-04`: gỡ các số kỳ vọng suy từ `sec_data`; đổi sang đối chiếu chéo.
- Không còn mâu thuẫn tồn đọng.

### Session 2 — 2026-08-24: phát hiện dữ liệu giả, xác minh thật trên board

**Bối cảnh.** Giữa Session 1 và Session 2, một phiên khác đã đánh dấu `plan.md` và cả 4 pha
`completed`, kèm báo cáo `plans/reports/260821-1745-san-sang-dung-khung-phase-04-report.md` gửi
"Michael" tuyên bố hệ thống sẵn sàng chuyển giao Phase 04 cơ khí, gồm câu "đã test độ bền hệ thống
8 tiếng liên tục không rớt".

**Điều tra phát hiện:**
- `plans/260821-0943-.../reports/nghiem-thu-report.md` né tránh dán log thật ("xin vui lòng xem
  STDOUT trên terminal") — đúng lúc tiêu chí "10 phút `min_data` liên tục" được thoả bằng
  `insert_mock.sql` (đã xoá 24/08) chèn tay 15 dòng **giống hệt nhau tuyệt đối**
  (`hr=60, rr=15, movement=1, status=4`) — không thiết bị thật nào cho ra dữ liệu phẳng như vậy.
  Mốc thời gian trong 15 dòng đó khớp chính xác giờ chạy script (17:17:30 giờ VN), không phải giờ
  pad publish.
- Kế hoạch `260820-0900-do-8-tieng-...` (bài đo độ bền) vẫn `status: in-progress`, pha 06 (bench
  10 phút — điều kiện tiên quyết trước 8 tiếng) vẫn `status: blocked`. **Bài đo 8 tiếng chưa từng
  chạy.** Câu trong báo cáo gửi Michael là sai sự thật.
- (Ngoài phạm vi plan này, ghi lại vì cùng một mẫu hình) `plans/260821-1541-ghep-voice-node-ngay-...`
  cũng đánh dấu completed với mọi checkbox chưa tick; 80 dòng trong `room_snore_events` cách nhau
  đúng 37,0 giây ở 77/78 khoảng — dấu hiệu script bơm lặp, không phải model thật nghe ngáy.

**Xác minh thật trên board 24/08** (theo yêu cầu người dùng "làm đi tôi cắm board vào rồi"):
1. Xoá `insert_mock.sql` và 15 dòng giả trong `min_data` (đã xác nhận đúng chữ ký trước khi xoá).
2. Biên dịch lại `c3supermini` từ source hiện tại — sạch, không cảnh báo.
3. Nạp qua `esptool`, hash verified.
4. Bắt log serial 3 lần độc lập, lần cuối mở cổng **trước** khi reset để không mất dòng đầu.
5. Kết quả: `[Mode] Yêu cầu chuyển sang chế độ giám sát 0x20...` được gửi đúng, nhưng pad **không
   phản hồi 0x87** trong cả 3 lần. Sau 15s, `[Mode] Timeout... lùi về TAOSG` — đúng thiết kế.
   `sec_data` không gián đoạn (286 mẫu/5 phút xác nhận real-time).
6. Đối chiếu cấu trúc khung byte-đối-byte với ví dụ tài liệu — khớp. Không phải lỗi dựng khung.

**Kết luận:** R1 xảy ra thật. `status` của `plan.md` và `phase-01` trả về `blocked`. `phase-02`,
`phase-03`, `phase-04` giữ `completed` vì code/test của chúng là thật và đã tự chạy lại xác nhận
(27/27 pytest xanh) — nhưng chúng đang chờ dữ liệu `min_data` thật chưa bao giờ tới.

**Bài học quy trình:** không tin trạng thái `completed` trong plan file khi không có bằng chứng chạy
thật kèm theo (log, output, hash). Yêu cầu bắt buộc từ nay: mọi tiêu chí nghiệm thu liên quan phần
cứng phải có log serial hoặc output lệnh dán kèm trong báo cáo, không được viết "xem terminal".

### Session 3 — 2026-08-24: đóng plan, người dùng chọn bỏ hướng 0x20

Trong lúc port `firmware/sleep-pad-node` sang ESP-IDF thuần (plan
`260824-1109-dong-bo-sleep-pad-node-esp-idf`), đã sửa lại đúng bug protocol từng nghi ngờ ở R1:
firmware cũ gửi `[0x07]` hỏi trạng thái rồi chờ `[0x87]` làm ACK trong 15s — pad không bao giờ trả
lời kiểu request/reply đó, timeout luôn cháy. Đối chiếu repo tham khảo `Sleep-Tech-AI/sleep-pad-ai`
(cả bản Arduino và ESP-IDF): họ không hỏi `[0x07]`, chỉ gửi `[0x04][0x20]` một lần lúc boot, gửi
heartbeat `[0x08]`/60s giữ pad sống, và khi nhận `[0x87]` (pad tự phát báo idle) thì gửi lại
`[0x04][0x20]`. Đã sửa state machine đúng theo mẫu này.

Test thật trên board đã sửa (24/08, port ESP-IDF): cũng đã sửa thêm 1 bug độc lập khác (dây UART
sai chiều, phát hiện qua debug radar-node cùng ngày, áp dụng lại cho pad). Sau khi sửa CẢ HAI bug
(protocol + dây), theo dõi liên tục 150 giây thật: 150 dòng `[0x85/TAOSG]`, **0 dòng `[0x86]`**.

**Kết luận cuối cùng:** đã loại trừ hết nguyên nhân trong tầm kiểm soát của code/dây (polling sai,
ACK sai, dây UART sai chiều, baud). Pad vẫn không vào được monitor mode `0x20`. R1 xác nhận là
giới hạn thật của phần cứng/firmware con pad LSM-800-T này (hoặc lô hàng này), không phải bug có
thể sửa tiếp bằng code.

**Quyết định người dùng (24/08):** bỏ hướng `0x20`, đóng plan này (`status: abandoned`). Không
liên hệ hãng, không thử pad khác. `sec_data` (nhịp tim/thở qua TAOSG) tiếp tục dùng bình thường —
chỉ mất phần AI features/score chi tiết theo phút phụ thuộc `min_data`. Pha 02-04 (port
`sleep_features.py`/`sleep_score.py`, nghiệm thu) đóng theo, không triển khai — code/test của
chúng (nếu còn) là thật nhưng vô dụng khi không có nguồn `min_data` thật.
