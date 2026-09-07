---
type: brainstorm
date: 2026-08-21 09:43
slug: port-tang-ai-sleep-tech-projection-phut-tu-sec-data
status: thiết kế đã chốt, chờ lập kế hoạch
branch: master
nguồn đối chiếu: github.com/Sleep-Tech-AI/sleep-pad-ai (private, nhánh main, pushed 2026-08-19)
---

# Port tầng `ai/` từ Sleep-Tech-AI — chiếu `sec_data` thành dòng-theo-phút

## Vì sao có phiên này

Câu hỏi ban đầu: pad LSM-800-T có phát hiện ngáy không, hay phải gắn voice-node.

Trả lời: **có**. Cả tài liệu hãng lẫn repo Sleep-Tech-AI đều xác nhận mã trạng thái `0x07 = Snoring
for this second`, đọc từ cảm biến áp điện dưới lưng. Không cần micro. Đọc repo còn lộ ra nhiều
quyết định thiết kế đáng mang về, nên phiên này mở rộng thành bài toán port.

## Phát hiện từ repo đối chiếu

Repo Sleep-Tech-AI là bản gốc mà `cloud/sleeppad` tách ra — cùng module `auth`, `devices`, `mqtt`,
`alerts`, `sharing`, `watch`. Hai bên đã tiến hoá khác nhau: **họ thêm `ai/`, mình thêm `sessions/`**.

### Ngáy lấy từ pad, không từ micro

`backend/app/ai/sleep_features.py`:

```python
STATUS_SNORING = 7
OCCUPIED = {STATUS_IN_BED, STATUS_MOVEMENT, STATUS_SNORING, STATUS_WEAK_BREATHING}
ASLEEP   = {STATUS_IN_BED, STATUS_SNORING, STATUS_WEAK_BREATHING}
```

Phút có ngáy được tính là phút **đang ngủ**, không phải nhiễu cần loại.

### Tầng `ai/` của họ KHÔNG chạy được trên phần cứng này

Hỏng theo hai đường độc lập:

1. **Sai bảng.** `extract()` đọc `min_data`. Pad TAOSG không phát khung phút 0x86 → `min_data` rỗng
   vĩnh viễn → trả `None`, im lặng.
2. **Sai bộ mã.** Họ dùng `STATUS_IN_BED = 4`. Dòng TAOSG dùng **0** cho "đang nằm", chưa từng phát
   mã 4. `OCCUPIED` chỉ bắt được mã 2, và `if len(occupied) < 10: return None` chặn hầu hết đêm.

Cùng một con pad, hai chế độ mã hoá "đang nằm" khác nhau: khung `0x85` dùng 4, dòng TAOSG dùng 0.
Không tài liệu nào của dự án ghi điều này; chỉ lộ ra khi đối chiếu hai codebase.

### Bốn quyết định đáng học

| Quyết định | Của họ | Của mình hiện tại |
|---|---|---|
| Đếm tỉnh giấc | chuỗi ≥ 2 phút không-ngủ (`AWAKENING_MIN_MINUTES`) | đếm số giây mang mã 5 |
| Đơn vị báo cáo | `movement_index`, `snore_index` chia theo giờ ngủ | số thô, không so sánh được giữa các đêm |
| Dữ liệu mỏng | `if len(occupied) < 10: return None` + danh sách `warnings` | không có ngưỡng từ chối |
| Vật nặng (mã 6) | loại khỏi thời gian nằm | chưa xử lý |

### Ranh giới phiên: họ đơn giản hơn nhiều

Cắt theo khoảng trống nhiều **giờ** (`SESSION_GAP_HOURS`). Không máy trạng thái, không ngưỡng 30
giây mở / 30 phút đóng.

Đáng suy nghĩ: máy trạng thái của mình tinh vi hơn, và chính sự tinh vi đó vừa gây lỗi jitter làm
phiên không bao giờ mở (sửa sáng 21/08). Cách của họ thô hơn nhưng không có chế độ hỏng tương đương.

### Ranh giới LLM (không port đợt này)

Mọi con số tính bằng Python thuần; `fact_guard.py` chặn; LLM chỉ diễn giải.

> "The model never infers a clinical fact; it only explains facts this module has already
> established… a hallucinated sentence can still be wrong in tone, but it cannot invent an apnea
> event that the sensor never recorded."

`narrator.py` chạy `claude-opus-5`, có đường proxy `LLM_BASE_URL` cho dev, tự tính USD mỗi lần gọi.

## Phạm vi đã chốt

**Port:** `ai/sleep_features.py`, `ai/sleep_score.py`, cộng một tầng chiếu phút mới.

**KHÔNG port đợt này:** `narrator.py`, `fact_guard.py`, `prompts.py`, `ai/router.py`, `ai/demo.py`.
Lý do: hai file được port là số học thuần, tái lập được, không tốn tiền, không cần key. Tầng LLM
thêm prompt phải bảo trì và chi phí, không phục vụ mục tiêu trước mắt.

## Thiết kế

### Chỗ nối: tầng chiếu (projection), không viết lại `extract()`

Dựng dòng-theo-phút từ `sec_data` **giống hệt hình dạng `min_data`**, rồi đưa vào `extract()` gần
như nguyên văn.

Lý do bác phương án viết lại `extract()` theo giây: giữ ~90% code upstream không đổi → logic đã
kiểm chứng, và upstream sửa gì còn merge được. Viết lại là tạo **hai bản cùng một luật** — đúng cái
bẫy vừa mất cả buổi sáng 21/08 để gỡ với hai bộ dựng phiên Go/Python.

### Ánh xạ mã trạng thái

| `sec_data.status` | Nghĩa | → upstream |
|---|---|---|
| 0 | đang nằm | 4 (`IN_BED`) |
| 1 | rời giường | 1 |
| 2 | cử động | 2 |
| 3 | ngồi dậy | 3 *(upstream không có)* |
| 5 | tỉnh giấc | 5 *(upstream không có)* |
| 6 / 7 / 8 | vật nặng / ngáy / thở yếu | giữ nguyên |

**Lệch có chủ ý:** mở rộng `OCCUPIED` thành `{4,2,7,8,3,5}`, giữ `ASLEEP = {4,7,8}`. Giữ nguyên
`OCCUPIED` của upstream sẽ loại phút ngồi dậy khỏi thời gian nằm — sai, ngồi dậy vẫn ở trên giường.

### Chọn mã đại diện cho mỗi phút

60 giây nhiều mã lẫn lộn. **Không bỏ phiếu đa số** — sự kiện hiếm lấy đa số là mất sạch tín hiệu.

Luật: đa số giây là 1 → phút = 1. Còn lại ưu tiên `3 > 5 > 7 > 8 > 2 > 0`. Một phút có ngáy là phút
ngáy, kể cả chỉ ngáy 5 giây.

### Bộ đếm mỗi phút

`movement`, `snore_count`, `resp_disorder` = **số đợt** trong phút đó (chuyển vào mã 2/7/8), cùng
kiểu đã áp ở `service.py:_summarize` sáng 21/08. Không đếm giây.

### Cửa sổ phiên

Dùng `sleep_sessions` sẵn có, **không** dùng cách cắt theo `SESSION_GAP_HOURS` của upstream. Hai
định nghĩa "một đêm" trong cùng một hệ sẽ mâu thuẫn.

### Ranh giới sở hữu

Giữ nguyên `AND time >= (SELECT paired_at FROM devices WHERE id = $1)`. Đã xác minh
`devices.paired_at` tồn tại, NOT NULL, default `now()`.

## Rủi ro

### 1. Thành phần hô hấp có thể ăn trọn điểm bằng phép đo chưa từng xảy ra

`sleep_score._breathing_credit(rdi)` trả `1.0` khi `rdi < 5.0`. Nếu pad không phát mã 7/8 thì
`resp_disorder_total` luôn 0 → `rdi_proxy` luôn 0 → **luôn full điểm**.

**Quyết định của người dùng: giữ nguyên hành vi upstream.** Hợp lý *nếu* pad có phát mã 7/8.

→ **Bài thử ngáy là điều kiện tiên quyết, không phải việc phụ.** Âm tính thì phải quay lại điểm này.

### 2. Mã 7 chưa từng xuất hiện trong dữ liệu thật

Toàn bộ dữ liệu hiện có (gồm 85 phút ngủ thật đêm 21/08): chỉ thấy mã 0, 1, 2, 3, 5. Chưa có 7 hay 8.

Chưa phân biệt được "không ngáy" với "TAOSG không phát mã 7".

**Cách thử đúng:** nằm lên pad, tự phát tiếng ngáy bằng cổ họng 30–60 giây. **Không dùng loa điện
thoại** — pad là cảm biến áp điện (25 mẫu `sdata` mỗi khối TAOSG), nghe rung cơ học qua đệm chứ
không nghe âm thanh trong không khí; và lúc đó trên pad không có người nên `status` sẽ ra 1 hoặc 6.

### 3. `min_data` rỗng làm chết im lặng

`extract()` trả `None` khi thiếu dữ liệu. Cần log/warning rõ ràng, nếu không lặp lại đúng kiểu lỗi
`relation "samples" does not exist` đã giấu mình cả đêm 20/08.

## Tiêu chí nghiệm thu

- `extract()` chạy được trên phiên đêm 21/08 (00:13:43 → 01:39:20, 5.136 giây) và trả `SleepFeatures`
  khác `None`.
- `movement_total` khớp con số đã kiểm tay: **115 đợt** trên 570 giây mang mã 2.
- `time_in_bed_min` xấp xỉ 85, `total_sleep_min` ≤ `time_in_bed_min`.
- `hr_mean` xấp xỉ 56,8 và `rr_mean` xấp xỉ 15,5 (khớp `sleep_sessions` hiện tại).
- `sleep_score` tái lập: chạy hai lần trên cùng phiên ra cùng điểm.
- `warnings` có mục cảnh báo phiên dưới 1 giờ với phiên 09:10 (13 phút).
- Test chứng minh fail-without-fix cho luật chọn mã đại diện: một phút chứa đúng 5 giây mã 7 phải
  ra phút ngáy, không bị đa số mã 0 nuốt mất.

## Ngoài phạm vi đợt này

- Tầng LLM (`narrator`, `fact_guard`, `prompts`, `router`).
- Đổi ranh giới phiên sang cách của upstream.
- Đổi giao diện app để hiện điểm giấc ngủ.
- Bốn quyết định nhỏ ở bảng trên (đếm tỉnh giấc theo chuỗi, index theo giờ, ngưỡng từ chối, loại mã
  6) — chúng đến **kèm theo** `sleep_features.py` khi port, không cần làm riêng.

## Câu chưa trả lời

- Pad TAOSG có phát mã 7 và 8 không? Chặn rủi ro #1. Thử bằng cách nằm lên và ngáy bằng cổ họng.
- Sau khi có `sleep_score`, app hiện nó ở đâu? Thẻ ngoài tab Giấc ngủ đang hiện 4 ô, trong đó 2 ô
  vừa được sửa nguồn. Thêm điểm vào đó hay làm màn riêng?
- Có nên đồng bộ ngược `sessions/` sang cách cắt đơn giản của upstream không? Máy trạng thái hiện
  tại tinh vi hơn nhưng đã hỏng một lần vì jitter.
