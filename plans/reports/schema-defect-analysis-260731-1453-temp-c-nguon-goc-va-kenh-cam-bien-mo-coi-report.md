# [Bug Fix] Schema dữ liệu Phase 01 — `temp_c` và các kênh cảm biến mồ côi

**Date**: 2026-07-31
**Type**: Bug Fix (lỗi spec/schema, chưa có code)
**Priority**: High — chặn firmware Phase 01, phải đóng trước đêm ghi dữ liệu đầu tiên
**Template**: `plans/templates/bug-fix-template.md`
**Context Tokens**: ~140 words

## Executive Summary

Schema dữ liệu chốt ở `docs/system-architecture.md` §6 được copy nguyên từ CSV bài take-home tuyển dụng, vốn dựng trên **spec 2023**. Nó chưa bao giờ được đối chiếu với BOM v3 chốt ngày 13/07. Hệ quả: 2 cột không có cảm biến nào sinh ra được, và 5 kênh cảm biến đã chốt giữ thì không có chỗ lưu. Câu hỏi "`temp_c` là gì" đã có lời giải dứt khoát: **nhiệt độ không khí trong khoang, từ SHT**.

## Issue Analysis

### Symptoms

- [x] `temp_c` không nói rõ là nhiệt độ môi trường hay thân nhiệt — trong khi BOM v3 có **hai** cảm biến nhiệt (SHT + MLX90614)
- [x] `spo2` không có cảm biến nào sinh ra (MAX30102 đã cắt)
- [x] `weight_kg` không có cảm biến nào sinh ra (loadcell thay bằng piezo pad, piezo không cho cân nặng tuyệt đối)
- [x] Thân nhiệt bề mặt (MLX90614), CO₂, âm thanh (mic I2S), BCG (piezo), vị trí đa người (LD2510B) — **đo được nhưng không có cột lưu**
- [x] Vị trí đa người không nhét được vào hàng CSV phẳng dù cấu trúc schema hiện tại là phẳng

### Root Cause

`docs/system-architecture.md:180` nói thẳng: *"The record schema matches the take-home CSV exactly, so the simulated 10 Hz data already exercised by the recruiting exercise is drop-in replaceable with real data."*

Ý định đúng (tái dùng được code take-home), nhưng schema bị đóng băng theo **bộ cảm biến 2023**, không theo bộ cảm biến v3. Buổi họp 13/07 đổi 4 cảm biến (loadcell→piezo, LD2410B→LD2510B, cắt MAX30102, thêm CO₂) và §7 ghi lại đầy đủ các cảm biến bị cắt — nhưng §6 (schema) không được cập nhật theo.

### Evidence

**Kết luận `temp_c` = nhiệt độ môi trường khoang (SHT10/SHT31)** — 4 dòng bằng chứng độc lập:

1. **Nguồn gốc** — `system-architecture.md:180`: schema khớp CSV take-home, tức dựng trên spec 2023.

2. **Map 1-1 với bộ cảm biến 2023** — mọi cột khớp đúng một cảm biến cũ:

   | Cột CSV | Cảm biến spec 2023 |
   |---|---|
   | `presence`, `resp_amplitude`, `motion` | radar LD2410B |
   | `hr_bpm`, `spo2` | MAX30102 |
   | `weight_kg` | loadcell 150kg |
   | **`temp_c`, `humidity`** | **SHT** |

   Camera nhiệt/MLX90614, mic, MQ303B, MPS20N400D **không có cột nào** → `temp_c` không thể là MLX90614, vì MLX không xuất hiện trong CSV.

3. **Cặp `temp_c, humidity` liền kề** — chỉ SHT cho cả hai. MLX90614 không đo độ ẩm.

4. **Docs phân biệt nhất quán, 3 chỗ:**
   - `plans/.../phase-01-*.md:27` — "SHT (SHT10/SHT31) | Trong khoang, tránh hơi thở trực tiếp | **Nhiệt độ + độ ẩm môi trường**"
   - `plans/.../phase-03-*.md:22` — "đọc SHT (**nhiệt độ + độ ẩm khoang**) và MLX90614 (**thân nhiệt**)"
   - `docs/system-architecture.md:196-197` — "SHT10/31 | In pod | Temperature, humidity" ≠ "Thermal / MLX90614 | Forehead/neck | Surface body temperature"

**Affected Components**
- `docs/system-architecture.md` §6 (dòng 183), §6.1
- `plans/260713-1019-smartbed-v3-mvp/phase-01-*.md` (dòng 46)
- `firmware/sensor-node/` — chưa tồn tại, sẽ đọc I2C theo schema này
- `edge/collector/` — chưa tồn tại, sẽ tạo bảng DB theo schema này

## Context Links

- **Related Plans**: `plans/260713-1019-smartbed-v3-mvp/phase-01-cum-cam-bien-va-data-pipeline.md` (DoD schema), `phase-03-*.md` (tiêu thụ MLX90614)
- **Related Report**: `plans/reports/brainstorm-framework-direction-260731-1433-huong-b-seam-first-report.md` §6 — nơi lỗi này được nêu lần đầu; báo cáo này đóng câu hỏi tồn đọng #2 của nó
- **Reference Docs**: `docs/system-architecture.md` §6, §6.1, §7
- **Dependencies**: BOM v3 chốt 13/07 (`docs/meetings/260713-1259-*/`)

## Solution Design

### Approach

Tách schema **lưu trữ** khỏi schema **export**. Lưu trữ theo đúng cái cảm biến v3 sinh ra được; giữ CSV take-home làm một SQL VIEW. Giữ nguyên lý do gốc của plan (data giả lập thay bằng data thật là drop-in) mà không đóng băng 2 cột chết vào DB.

### Changes Required

1. **`docs/system-architecture.md` §6** — thay schema phẳng bằng schema lưu trữ + view export:

   | Cột hiện tại | Xử lý | Lý do |
   |---|---|---|
   | `temp_c` | → `env_temp_c` | Rõ nghĩa. Nguồn: SHT. Không đổi ngữ nghĩa, chỉ đổi tên |
   | `humidity` | giữ | SHT |
   | `spo2` | **bỏ** | Không có nguồn. Ghi 0 vĩnh viễn đọc như dropout vĩnh viễn → phá nguyên tắc "dropout đánh dấu, không bịa" (§6) |
   | `weight_kg` | **bỏ**, thay bằng `piezo_amplitude` | Piezo không cho kg. Giữ tên mà đổi nghĩa là bẫy tệ nhất |
   | `presence`, `motion`, `resp_amplitude`, `hr_bpm` | giữ | Nguồn mới: LD2510B (presence, resp, HR thô) + piezo (motion, BCG→HR) |
   | — | **thêm** `body_temp_c` | MLX90614. Phase 03 cần |
   | — | **thêm** `co2_ppm` | Cảm biến CO₂ (§6.1). Là interlock an toàn H-14/thông gió |
   | — | **thêm** `sound_level` | Mic I2S |
   | — | **thêm** `bcg` | Piezo, kênh thô |

2. **Bảng riêng cho radar đa người** — không nhét được vào hàng phẳng:
   ```
   radar_target(t, target_id, x, y, ...)
   ```
   Hệ quả trực tiếp của việc chọn LD2510B (đã chốt), và là DoD Phase 01: *"LD2510B track được 2 người cùng lúc, ra được vị trí từng người"*.

3. **SQL VIEW `takehome_csv`** — sinh lại đúng 9 cột cũ cho code take-home. `spo2` và `weight_kg` trả NULL, không trả 0.

4. **`plans/.../phase-01-*.md:46`** — cập nhật dòng schema cho khớp.

> ⚠️ **Chặn phạm vi:** mục 1 và 4 sửa docs/plan. Hưng đã chốt "không được sửa plan" ở vòng brainstorm trước. Cần Hưng cho phép, hoặc áp lúc thực thi Phase 01. Report này chỉ khuyến nghị, chưa sửa file nào.

### Testing Changes

Chưa có test suite (repo 0 dòng code). Thay bằng kiểm chứng phần cứng:

- [ ] Đọc SHT và MLX90614 cùng lúc trên bus I2C, xác nhận 2 địa chỉ khác nhau, 2 giá trị khác nhau
- [ ] Ghi 1 đêm, xác nhận `env_temp_c` và `body_temp_c` không tương quan tuyệt đối (nếu bằng nhau → đấu nhầm cảm biến)
- [ ] Query VIEW `takehome_csv`, chạy lại code take-home không sửa dòng nào

## Implementation Steps

1. [ ] Chốt danh sách cột cuối với Michael (kèm bảng §Changes Required)
2. [ ] Sửa `docs/system-architecture.md` §6 — **cần Hưng cho phép sửa docs**
3. [ ] Sửa `plans/260713-1019-smartbed-v3-mvp/phase-01-*.md:46` — **cần Hưng cho phép sửa plan**
4. [ ] `firmware/sensor-node/` — đọc SHT + MLX90614 là 2 kênh tách biệt ngay từ commit đầu
5. [ ] `edge/collector/` — tạo bảng theo schema mới + bảng `radar_target` + VIEW `takehome_csv`
6. [ ] Ghi 1 đêm thử, verify đủ kênh trước khi chạy 3 đêm chính thức của DoD Phase 01

## Verification Plan

### Test Cases

- [ ] **Phân biệt nguồn nhiệt**: che MLX90614 bằng tay → `body_temp_c` đổi, `env_temp_c` không đổi
- [ ] **Không cột ma**: `SELECT` schema lưu trữ, không có cột nào luôn NULL/0 suốt đêm
- [ ] **Không cảm biến mồ côi**: mỗi cảm biến trong `system-architecture.md` §6.1 map được tới ≥1 cột
- [ ] **Đa người**: 2 người nằm → `radar_target` có 2 `target_id`, mỗi cái có x,y riêng
- [ ] **Regression**: VIEW `takehome_csv` chạy được code take-home không sửa

### Rollback Plan

Chưa có code nên rollback rẻ. Nếu schema mới sai:
1. `git revert` commit sửa docs
2. Chưa có đêm dữ liệu nào lưu theo schema mới → không mất data
3. **Sau khi đã ghi 3 đêm chính thức thì rollback đắt** — đó là lý do phải chốt schema TRƯỚC đêm đầu tiên

## Risk Assessment

| Risk | Impact | Mitigation |
|---|---|---|
| Chốt schema chậm → ghi 3 đêm DoD bằng schema cũ, thiếu 5 kênh | **High** | Chốt trước khi cắm cảm biến. Sửa schema sau 3 đêm data thật đắt hơn nhiều lần |
| Đổi tên `temp_c`→`env_temp_c` phá code take-home | Low | VIEW `takehome_csv` giữ tên cũ. Code take-home không cần sửa |
| Michael muốn giữ schema y hệt take-home vì lý do khác chưa nêu | Medium | Đưa bảng bằng chứng §Evidence, để Michael quyết. Đây là quyết định của người chốt spec, không tự quyết |
| Bỏ `spo2` bị hiểu là bỏ luôn tính năng SpO₂ | Low | Ghi rõ trong docs: cắt cảm biến (§7, tiếp xúc da), không phải cắt cột. Nếu sau này làm phụ kiện rời thì thêm cột lại |
| Sửa docs/plan vượt phạm vi Hưng đã đặt | Medium | Report chỉ khuyến nghị. Chờ Hưng cho phép |

## TODO Checklist

- [ ] Hưng duyệt: có cho sửa `docs/system-architecture.md` §6 không
- [ ] Hưng duyệt: có cho sửa `phase-01-*.md:46` không
- [ ] Michael chốt danh sách cột cuối
- [ ] Sửa docs + plan
- [ ] Firmware đọc SHT + MLX tách kênh
- [ ] Collector tạo bảng + VIEW
- [ ] Verify 1 đêm thử trước 3 đêm DoD

## Câu hỏi tồn đọng

1. **Có được sửa `docs/system-architecture.md` và `phase-01-*.md` không?** Hưng đã chốt "không sửa plan" ở vòng trước. Không sửa thì schema sai đi thẳng vào firmware.
2. **`hr_bpm` lấy từ đâu ở v3?** MAX30102 đã cắt. §6.1 nói LD2510B cho "coarse heart rate", piezo cho BCG. Cần chốt: một cột `hr_bpm` hợp nhất, hay hai cột `hr_radar` + `hr_bcg` riêng để so sánh chéo? (Hợp nhất sớm là mất data — trái nguyên tắc framework.)
3. **Mic I2S lưu thế nào?** `sound_level` 10 Hz là đủ, hay cần lưu waveform thô để Phase 02 train CNN phát hiện ngáy? Lưu thô tốn disk nhưng `phase-02` cần audio thật để train.
4. **Camera nhiệt hay MLX90614?** Docs dùng lẫn lộn "Camera nhiệt / MLX90614" (`phase-00:37`, `phase-01:28`). MLX90614 là cảm biến **1 điểm**, không phải camera (camera nhiệt là mảng như MLX90640). Ảnh hưởng số cột: 1 điểm → 1 float; mảng → phải lưu frame. **Cần chốt mua con nào.**
5. **CO₂ chưa có model cụ thể** trong BOM (§6.1 chỉ ghi "CO₂ | I2C"). Ảnh hưởng đơn vị và range của `co2_ppm`.
