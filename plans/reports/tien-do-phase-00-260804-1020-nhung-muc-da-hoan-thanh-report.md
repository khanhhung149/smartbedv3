# Tiến độ Phase 00 — những mục đã hoàn thành

- **Ngày:** 2026-08-04 10:20
- **Phạm vi:** 8 việc trong `plans/260713-1019-smartbed-v3-mvp/phase-00-nen-tang-kien-truc-an-toan.md`
- **Cách kiểm:** đọc trực tiếp file trong repo, không dựa vào báo cáo cũ
- **Mốc:** plan lập 13/07 · Phase 00 hạn ~27/07 · hôm nay 04/08 (**quá hạn 8 ngày**)

---

## Tổng kết

| # | Việc | Trạng thái | Chặn bởi |
|---|---|---|---|
| 1 | Dựng repo monorepo | **Nửa** — cấu trúc xong, chưa commit | không gì |
| 2 | `docs/system-architecture.md` | **Xong nội dung** — chờ duyệt | Michael |
| 3 | `docs/safety/hazard-analysis.md` | **Xong nội dung** — chờ duyệt | Michael |
| 4 | BOM có giá + link | **Chưa** | Michael (trần ngân sách) |
| 5 | Bench rig | không kiểm được từ repo | — |
| 6 | Hệ toạ độ + vị trí 3 mảng nâng | **Chưa** | anh Khanh (scope) |
| 7 | ESP32 toolchain + WLED ESP8266 | **Mâu thuẫn** — xem §5 | — |
| 8 | Đặt mua LD2510B + piezo pad | **XONG** | — |

**Đọc nhanh:** phần trí óc nặng nhất (mục 2, 3) đã xong. Ba mục chưa xong thì hai chặn ở người khác. Việc duy nhất tự làm được ngay mà chưa làm là **commit**.

---

## 1. Mục 2 — `system-architecture.md`: XONG NỘI DUNG

230 dòng, 8 chương. `Status: DRAFT`, ngày 13/07.

Yêu cầu của Phase 00 là ba thứ. Cả ba đều có:

### a) Sơ đồ 3 tầng — §2

Safety/real-time (ESP32) · Perception/AI (Jetson Orin) · UX/Cloud (tablet + K8s).
§2.1 giải thích vì sao Linux không được lái actuator.

### b) Giao thức giữa các tầng, **có frame format thật** — §4

Không phải mô tả suông. §4.1:

```
│ SOF │ TYPE │ LEN │ SEQ │ PAYLOAD │ CRC16 │
```

- `CRC16` — CCITT, tính trên `TYPE..PAYLOAD`. Frame hỏng thì **drop, không đoán**.
- Transport: **UART trước**, CAN sau nếu nhiễu hoặc cần địa chỉ đa node. Framing sống sót qua cả hai.
- §4.2 message types · §4.3 watchdog (verify: rút cáp UART giữa lúc nâng, chuyển động phải dừng) · §4.4 "từ chối là bình thường, không phải ngoại lệ".

### c) Contract như API công khai ngay từ đầu — §5

Đây là chương trả lời trực tiếp định vị "framework, không phải app đóng" mà Michael chốt 13/07.

**§5.1 Addressing** — mọi input/output có địa chỉ ổn định:

```
smartbed/sensor/radar/presence
smartbed/sensor/radar/respiration_rate
smartbed/sensor/piezo/bcg
smartbed/sensor/env/co2
smartbed/actuator/plate/head/position
smartbed/actuator/light/scene
smartbed/actuator/fan/speed
```

**§5.2 Capability manifest** — mỗi capability khai báo một lần, máy đọc được:

```jsonc
{
  "address": "smartbed/actuator/fan/speed",
  "type": "number",
  "unit": "percent",
  "range": [0, 100],
  "access": "rw",
  "description": "Extraction fan speed. Raises air exchange and lowers CO2.",
  "constraints": ["software may only INCREASE this value; it may never switch the fan off"]
}
```

Trường `description` không phải trang trí — nó là thứ cho LLM liệt kê được giường làm được gì và giải "trong này sáng quá" thành một lệnh ghi vào `smartbed/actuator/light/scene`. **Manifest chính là function-calling schema.** Một cơ chế phục vụ cùng lúc ba thứ: API mở, AI autopilot, template platform.

**§5.3** constraints là một phần của contract · **§5.4** templates.

Còn có §6 luồng dữ liệu cảm biến, §6.1 danh sách cảm biến, §7 cắt gì khỏi spec 2023 và vì sao, §8 câu hỏi mở.

---

## 2. Mục 3 — `hazard-analysis.md`: XONG NỘI DUNG

97 dòng. `Status: DRAFT`, ngày 13/07.
Phạm vi tự khai: *"every way this machine can hurt the person lying on it"*.

**24 hazard** — DoD Phase 00 yêu cầu ≥15. **Vượt 60%.**

Bảng đủ 6 cột:

```
| ID | Hazard | Sev | Mitigation | Phase | Verify |
```

Tức đúng yêu cầu *"mỗi hazard gắn với biện pháp giảm thiểu và phase nào xử lý"* — và có thêm cột `Verify` (cách kiểm chứng) mà yêu cầu không đòi.

---

## 3. Mục 8 — Đặt mua cảm biến: XONG

**LD2510B** + **piezoelectric pad** đã có. Hạn đặt là 18/07.

Đây là mục quan trọng nhất trong 8 mục về mặt tháo chốt: nó là thứ duy nhất **chặn Phase 01**. Có cảm biến trong tay nghĩa là Phase 01 khởi động được bất cứ lúc nào.

---

## 4. Mục 1 — Repo: XONG CẤU TRÚC, CHƯA COMMIT

**Đã có:**

| | |
|---|---|
| Thư mục | `firmware/` `edge/` `cloud/` `app/` `mech/` `docs/` `plans/` `scripts/` |
| README từng tầng | 7 file, tổng 429 dòng cả docs |
| Lint config | `.clang-format` (C/C++), `ruff.toml` (Python) |
| CI | `.github/workflows/lint.yml` |
| Biên bản họp | `docs/meetings/260713-1259-onboarding-khanh-hung-smartbed-v3/` — có cả minutes và transcript |
| Templates | `plans/templates/` — 4 file |

README không phải placeholder. Ví dụ `mech/README.md` đã chốt cấu hình 3 mảng (đầu / giữa rộng / chân), tải tĩnh 150kg hệ số an toàn ≥2, vít me tự hãm, cấm khí nén và thuỷ lực, và ghi rõ *"tính lại lực và hành trình từ đầu — con số 500N/50cm là của thiết kế 10 điểm 2023, vô nghĩa với 3 mảng"*.

**Thiếu đúng một thứ: `git commit`.**

39 file đang staged trên nhánh `master`. **0 commit.** Hệ quả:

- CI chưa chạy lần nào → DoD #1 (*"repo có cấu trúc, CI chạy lint cơ bản"*) chưa đóng được, dù file CI đã có
- Toàn bộ công sức ở mục 2 và 3 **không nhìn thấy được từ ngoài**. Ai mở repo lên cũng thấy `master` rỗng từ 13/07

---

## 5. Mục 7 — Mâu thuẫn phải xử lý

`firmware/README.md` dòng cuối tự ghi:

> *"Toolchain: PlatformIO (or ESP-IDF). **Not chosen yet — Phase 00 task.**"*

Nhưng báo cáo 31/07 (`brainstorm-framework-direction-...`) ghi Hưng xác nhận ESP32 toolchain đã flash được.

Hai chỗ nói ngược nhau. Nếu toolchain thật sự chạy rồi thì **phải sửa dòng README đó** — nó đang là bằng chứng chống lại chính mình. Còn WLED trên ESP8266 chưa thấy dấu vết ở đâu trong repo.

---

## 6. Ba mục chưa xong

| Mục | Vì sao chưa | Ai gỡ |
|---|---|---|
| **4. BOM có giá** | Không có file nào trong repo. Không chọn được linh kiện khi chưa biết trần chi | **Michael** — hạn 26/07 đã qua |
| **6. Hệ toạ độ + 3 mảng** | `mech/` mới có README khái niệm. Không hệ toạ độ, không kích thước, không bản vẽ | **anh Khanh** — chủ sở hữu `mech/`, scope chưa rõ |
| **5. Bench rig** | Việc vật lý, không kiểm được từ repo | — |

---

## 7. Đánh giá thật

Phase 00 **không phải 0%**. Ước lượng **50-60%**:

- 2/8 mục xong hẳn (3, 8) — tính cả mục 2 là 3/8
- 2/8 xong nội dung, chỉ chờ chữ ký (2, 3)
- 1/8 xong 90%, thiếu một câu lệnh (1)
- 2/8 chặn ở người khác (4, 6)
- 1/8 không kiểm được (5)

**Vấn đề không phải làm ít, mà là làm rồi không ai thấy.** Với kỳ vọng Michael đặt 13/07 là *"chủ động báo cáo tiến độ hằng ngày"*, một repo 0 commit sau 3 tuần đọc như bỏ bê, trong khi thực tế có 2 tài liệu kiến trúc và an toàn viết khá kỹ.

### Việc rẻ nhất, đòn bẩy lớn nhất

`git commit` — 30 giây. Nó:

1. Đóng DoD #1 (CI chạy lần đầu)
2. Làm mục 1, 2, 3 hiện ra với người ngoài
3. Biến "0% nhìn từ ngoài" thành "60%"

Không có lý do kỹ thuật nào để hoãn.

---

## Câu chưa giải quyết

1. **Trần ngân sách BOM** — chặn mục 4. Hạn Michael 26/07 đã qua, chưa có.
2. **Michael đã duyệt 2 file `DRAFT` chưa?** — chặn DoD #2. Cả `system-architecture.md` và `hazard-analysis.md` đều còn `Status: DRAFT`.
3. **`temp_c` là nhiệt độ môi trường (SHT) hay thân nhiệt bề mặt (MLX90614)?** — §6.1 có cả hai cảm biến, schema §6 chỉ một cột. Phải chốt trước khi viết firmware vì nó quyết định số cột và số cảm biến trên bus I2C.
4. **ESP32 toolchain đã chạy chưa?** — `firmware/README.md` và báo cáo 31/07 nói ngược nhau. Cần chốt rồi sửa file sai.
5. **Bench rig đã dựng chưa?** — không kiểm được từ repo.
6. **Anh Khanh: in-house / thuê ngoài / đối tác?** Scope + chi phí phần cơ khí — chặn mục 6. Treo từ 13/07.
7. **Repo `sleep_pad_AI` có phải là Phase 01 đang chạy ở chỗ khác không?** Nếu có, plan smartbedv3 đang báo sai trạng thái và nên gộp hoặc liên kết lại.
