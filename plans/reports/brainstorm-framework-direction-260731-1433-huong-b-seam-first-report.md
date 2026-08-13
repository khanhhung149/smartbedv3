# Brainstorm — Hướng xây framework SmartBed v3

- **Ngày:** 2026-07-31
- **Câu hỏi gốc:** "đọc plan và docs có trong folder, tôi nên xây dựng framework theo hướng nào"
- **Quyết định:** **Hướng B** — giữ nguyên plan, framework ở Phase 06 (Hưng chốt)
- **Ràng buộc user đặt:** không sửa plan files, chỉ làm những gì làm được trong plan hiện tại
- **Nguồn đọc:** `plans/260713-1019-smartbed-v3-mvp/` (plan + phase 00→07), `docs/system-architecture.md`, `docs/safety/hazard-analysis.md`, `plans/reports/handoff-260713-1628-*.md`, README các tầng

---

## 1. Trạng thái repo khi brainstorm

- **0 dòng code.** `firmware/`, `edge/`, `cloud/`, `app/`, `mech/` chỉ có README.
- **0 commit.** Mọi file đang staged, branch `master` chưa có commit nào → CI (`.github/workflows/lint.yml`) chưa từng chạy.
- Docs chắc: `system-architecture.md` §5 đã có sẵn ý capability manifest (address, type, unit, range, access, description, constraints) + MQTT namespace §5.1.
- `hazard-analysis.md`: **24 hazard** (DoD yêu cầu ≥15 — đạt). Vẫn `DRAFT`, chưa Michael duyệt.
- Không có file BOM nào trong repo (DoD Phase 00 yêu cầu).
- **Lệch lịch:** plan lập 13/07, Phase 00 dự kiến 2 tuần (hết ~27/07). Hôm nay 31/07.
- **Phần cứng:** Hưng xác nhận đã có đủ cảm biến chính (LD2510B + piezo pad) + ESP32 toolchain chạy → không còn gì chặn Phase 01.

---

## 2. Vấn đề đã nêu

Định vị nói "framework là sản phẩm" (Michael, 13/07), nhưng plan xếp framework API + template platform vào **Phase 06 — phase cuối**. Phase 01→05 sẽ được viết như app đóng rồi phải bóc ra làm lại.

Rủi ro nêu ra: "xây sản phẩm trước, bóc framework sau" hiếm khi xảy ra khi tới hạn — đúng mô hình đã cháy ~10B VND ở phase 1 (*"70% đã build, 0 doanh thu"*).

## 3. Ba hướng đã đánh giá

| Hướng | Nội dung | Ưu | Nhược |
|---|---|---|---|
| **A** Contract-first | Manifest + MQTT namespace + gateway mỏng ngay Phase 00/01, ngân sách ≤500 LOC. Mỗi phase sau chỉ thêm capability. Phase 06 thành phase rẻ nhất | Không thuế retrofit; manifest ép phát hiện ngay lỗi schema | 1 người junior, chưa có gì chạy → dễ thành hố sâu 3 tuần |
| **B** Giữ nguyên plan | Sản phẩm trước, bóc framework ở Phase 06 | Nhanh nhất tới demo Phase 02; không có việc "vô hình" phải giải trình | Thuế retrofit trên 5 phase; mâu thuẫn định vị |
| **C** Platform-first đầy đủ | SDK + plugin sandbox + template engine + marketplace ngay | — | Lặp lại đúng mô hình thất bại phase 1. Loại. |

## 4. Quyết định và trade-off ghi nhận

**Hưng chốt hướng B.** Lo ngại về thuế retrofit đã được nêu trước khi chốt; Hưng giữ nguyên quyết định. Trade-off ghi lại tại đây, **không tự ý đảo ngược** ở session sau.

Chi phí chấp nhận: khi Phase 06 tới, phải bọc lại tầng plumbing của Phase 01→05 để mọi input/output addressable từ ngoài.

---

## 5. Hệ quả chính: seam quyết định B đắt hay rẻ

> **Hướng B chỉ đắt nếu code không có seam. Có seam thì B ≈ A về tổng chi phí.**

Thuế retrofit không nằm ở "chưa có MQTT", mà ở **số điểm phải sửa** khi Phase 06 tới. Giữ số đó = 1 là code sạch bình thường — không tốn thêm giờ, không đụng plan, không dựng framework sớm.

### Ví dụ `edge/collector/` (Phase 01)

```python
# Rải rác — Phase 06 sửa 20 chỗ
def on_frame(f):
    db.execute("INSERT INTO night(hr) ...", f.hr)
    if f.presence: db.execute(...)
    chart.push(f.resp)

# Một seam — Phase 06 sửa đúng 1 hàm
CHANNELS = [                       # chính là manifest, chưa serialize
    ("radar/presence",  "bool",  None,       "LD2510B"),
    ("radar/resp_amp",  "float", (0, 100),   "LD2510B"),
    ("piezo/bcg",       "float", (-1, 1),    "piezo pad"),
    ("env/co2",         "ppm",   (400, 5000),"CO2 sensor"),
]

def on_frame(f):
    for name, *_ in CHANNELS:
        publish(name, read(f, name), f.t)

def publish(name, value, t):       # Phase 06 chèn MQTT vào đây. 3 dòng.
    db.write(name, value, t)
```

Tầng actuator (Phase 03) cùng nguyên tắc: mọi lệnh đèn/quạt/nhiệt qua đúng một `apply(name, value)`, không gọi GPIO rải rác. Tầng cơ khí (Phase 04) đã sẵn có seam theo thiết kế — mech-handler là điểm duy nhất chạm actuator.

### Ba việc chi phí bằng 0, không sửa plan

| Việc | Vì sao chi phí 0 | Cứu gì ở Phase 06 |
|---|---|---|
| Đặt tên kênh theo `system-architecture.md` §5.1 (`radar/presence`, `piezo/bcg`, `env/co2`) | Đằng nào cũng phải đặt tên | Map sang manifest 1-1, không phải rename |
| Một seam `publish()` / `apply()` mỗi module | Là code sạch bình thường | Chèn MQTT vào 1 điểm thay vì 20 |
| `docs/sensor-characterization.md` viết theo cột: address, unit, range, nguồn cảm biến, mô tả, giới hạn đã đo | File này **đã nằm trong DoD Phase 01** | Là ~80% nội dung manifest. Phase 06 chỉ serialize sang JSON |

Không dựng bus, không dựng registry, không dựng gateway ở giai đoạn này. Đúng hướng B.

---

## 6. Quyết định Phase 01 phải chốt: schema dữ liệu

Việc **trong** Phase 01, không phải sửa plan. Schema hiện chốt ở `system-architecture.md` §6:

```
t, presence, hr_bpm, resp_amplitude, motion, weight_kg, spo2, temp_c, humidity
```

### Ba lỗi vật lý

| Cột | Vấn đề |
|---|---|
| `spo2` | Không có nguồn — MAX30102 đã cắt (§7, tiếp xúc da). Ghi 0 vĩnh viễn đọc như dropout vĩnh viễn → phá nguyên tắc "dropout đánh dấu, không bịa" (§6) |
| `weight_kg` | Không có nguồn — piezo pad không cho cân nặng tuyệt đối. Giữ tên mà đổi nghĩa là bẫy tệ nhất |
| `temp_c` | Mơ hồ: SHT (môi trường) hay MLX90614 (thân nhiệt bề mặt)? §6.1 có cả hai cảm biến, schema chỉ một cột |

### Bốn kênh thiếu chỗ

`co2_ppm` · BCG từ piezo · mức âm thanh từ mic I2S · **vị trí đa người từ radar**.

Kênh cuối không nhét được vào một hàng CSV phẳng → cần bảng riêng `radar_target(t, target_id, x, y, ...)`. Hệ quả trực tiếp của việc chọn LD2510B (đã chốt), và là DoD Phase 01 ("track được 2 người cùng lúc, ra vị trí từng người").

### Đề xuất

Lưu trữ theo đúng cái cảm biến sinh ra được. **Giữ CSV take-home làm view export, không phải schema lưu trữ** — một câu SQL VIEW. Vẫn giữ lý do gốc của plan ("data giả lập thay bằng data thật là drop-in", §6 / phase-01) mà không đóng băng hai cột chết vào DB.

---

## 7. Trạng thái DoD Phase 00

| DoD | Trạng thái |
|---|---|
| Repo có cấu trúc, CI chạy lint cơ bản | File CI có; **0 commit → CI chưa chạy lần nào** |
| `system-architecture.md` Michael duyệt (có định nghĩa API/contract mở) | Vẫn `DRAFT`. Contract đã có (§5) |
| `hazard-analysis.md` ≥15 hazard | **24 hazard** ✅ (vẫn `DRAFT`) |
| BOM có giá, tổng chi phí | **Không có file trong repo** |
| Bench rig đứng được | Không kiểm được từ repo |
| ESP32 toolchain flash được | Hưng xác nhận đã có |

## 8. Việc làm được ngay (phần cứng đã đủ, không còn blocker)

1. Commit repo → CI xanh lần đầu (đóng DoD #1).
2. Viết BOM có giá + link nhà cung cấp (DoD #4, đang thiếu hẳn).
3. Gửi Michael duyệt 2 file `DRAFT` (`system-architecture.md`, `hazard-analysis.md`).
4. Chốt schema Phase 01 theo §6 report này.
5. Firmware thu thập 10 Hz trên ESP32, verify jitter bằng oscilloscope.
6. **Test LD2510B với 2 người nằm cùng lúc** — lý do duy nhất chọn 2510B thay 2410B; verify sớm nhất có thể (phase-01 rủi ro #3).
7. Test piezo pad xuyên nệm dày (phase-01 rủi ro #2) — cả 2 test này plan yêu cầu làm ngay tuần 1.

## 9. Rủi ro của hướng đã chọn

| Rủi ro | Giảm thiểu |
|---|---|
| Phase 06 phình to vì phải bọc lại plumbing của 5 phase | Giữ một seam mỗi module (§5). Đây là toàn bộ biện pháp giảm thiểu khả thi trong hướng B |
| Michael hỏi "framework đâu" trước Phase 06 | `CHANNELS` + `sensor-characterization.md` là bằng chứng cụ thể contract đang được tôn trọng, dù chưa expose ra ngoài |
| Schema đóng băng nhầm cột chết → developer sau kế thừa ghost của spec 2023 | Chốt schema theo §6 report này **trước khi** ghi đêm dữ liệu đầu tiên. Sau 3 đêm data thật thì sửa schema đắt hơn nhiều |
| Đặt tên kênh tuỳ tiện ở Phase 01 | Dùng namespace §5.1 ngay từ dòng code đầu |

## 10. Câu hỏi tồn đọng

1. **Trần ngân sách BOM** — vẫn chưa có (handoff §9.3, hạn Michael 26/07 đã qua). Chặn DoD Phase 00 #4.
2. **`temp_c` là môi trường hay thân nhiệt?** Cần chốt trước khi viết firmware — quyết định số cột và số cảm biến I2C trên bus.
3. **Michael duyệt 2 file DRAFT chưa?** Chặn DoD Phase 00 #2.
4. **Bench rig đã dựng chưa?** Không kiểm được từ repo.
5. Các câu hỏi tồn đọng từ handoff §9 (anh Khanh, người kế tiếp, site pilot, bản quyền nhạc, MOU, deadline cứng, advisor y khoa) — chưa có cái nào đóng.
