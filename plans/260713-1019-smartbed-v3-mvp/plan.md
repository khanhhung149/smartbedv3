# SmartBed v3 — Implementation Plan (MVP → nâng cấp dần)

- **Ngày lập:** 2026-07-13
- **Cập nhật:** 2026-07-13 sau buổi onboarding Hưng (meet `xvk-oxqt-fod`, 52 phút) — Michael review plan và sửa spec trực tiếp
- **Nguồn spec:** `[SmartBed] MVP Specs slight introduction.pdf` (bản 2023, release plan đã lệch 2 năm)
- **Biên bản họp:** `docs/meetings/260713-1259-onboarding-khanh-hung-smartbed-v3/`
- **Nhân sự:** Hưng (KS điện tử, vào làm 13/07) · anh Khanh (cơ khí) · Michael (định hướng, hạn chế nhúng tay)
- **Nguyên tắc chia phase:** mỗi phase ra được sản phẩm chạy thật; phần mềm và cảm biến (an toàn thấp) làm trước, cơ khí nâng người (rủi ro cao) làm sau; oxy/EEG/huyết áp đẩy về cuối hoặc bỏ.

---

## Định vị sản phẩm — CHỐT 13/07 (thay đổi lớn nhất)

> "Mục tiêu của anh không phải làm một sản phẩm để bán, mà làm một **framework**." — Michael

SmartBed không phải cái giường. Nó là **nền tảng**: nhiều thông số đầu vào, nhiều lệnh điều khiển đầu ra, **mở cho developer** gắn thêm chức năng. Mô hình App Store.

Bốn hệ quả bắt buộc lên mọi phase:

1. **Thu thập TẤT CẢ data** — kể cả data hôm nay chưa dùng. Developer sau này sẽ cần. Không được cắt bớt cảm biến chỉ vì "chưa dùng tới".
2. **Kiến trúc là API/contract mở**, không phải app đóng. Mọi input/output phải addressable từ bên ngoài.
3. **Autopilot bằng AI** (về sau): AI học thói quen từ data → tự lái cả giường. Điều khiển theo **intent** ("sáng quá", "hơi nóng"), không phải lệnh cứng. Michael đã chạy thật mô hình này tại nhà, sẽ truyền lại.
4. **Moonshot — platform template:** public ~100 template mẫu (khó ngủ, đau đầu, sáng thức dậy, mới vào giấc…). Developer up template lên GitHub, người dùng bấm 1 cái trên tablet là load về. **Template là văn bản, không phải code** — AI convert sang logic hệ thống.

**Bỏ Home Assistant + Node-RED.** Automation dựa trên AI hiểu intent, không phải người kéo-thả. (Michael: HA mạnh nhưng "sẽ thành cản trở".)

**Wellness device, KHÔNG claim y tế.** Mọi chỉ số (apnea, nhịp thở, sleep stage) gắn nhãn "tham khảo, không dùng chẩn đoán".

---

## Kiến trúc lõi (đã cập nhật theo họp 13/07)

| Tầng | Chạy trên | Nhiệm vụ | Nguyên tắc |
|---|---|---|---|
| Safety / real-time | **ESP32** (bỏ STM32) | Actuator, e-stop, phát hiện kẹt bằng dòng, khoá liên động, watchdog | Không phụ thuộc Linux. Linux chết thì tầng này vẫn an toàn. **Thống nhất 1 dòng MCU duy nhất** cho toàn hệ (được dùng nhiều biến thể ESP32) |
| Perception / AI | **Jetson Orin** (đã có sẵn thiết bị) | Đọc cảm biến, xử lý tín hiệu, CV (MediaPipe Pose trên GPU), sleep staging | Không được phép ra lệnh chuyển động trực tiếp, chỉ gửi "yêu cầu" xuống MCU |
| UX / Cloud | **Tablet nhỏ (iPad / Android rẻ)**, Flutter app, **K8s** backend | Hiển thị, báo cáo, hồ sơ người dùng, load template | Offline-first, mất mạng vẫn ngủ được |

### Thay đổi so với bản sáng 13/07

| Hạng mục | Cũ | Chốt trong họp |
|---|---|---|
| MCU | STM32 | **ESP32 duy nhất** |
| AI compute | Orange Pi 5+ → Jetson từ Phase 05 | **Jetson Orin ngay từ đầu** (đã có thiết bị) |
| Coral USB | Cắt | Cắt (giữ nguyên) |
| Màn hình | LCD 45" | **Tablet nhỏ** (iPad / Android rẻ) |
| Backend | k3s | **K8s** |
| App | Flutter | Flutter (giữ nguyên) |
| Cơ khí | 10 điểm nâng | **3 mảng** (đầu / giữa rộng / chân) — 10 điểm để sau |
| Radar | HLK-LD2410B | **HLK-LD2510B** (track nhiều người + vị trí thật) |
| Cân nặng | Loadcell 150kg | **Piezoelectric pad** |
| Mic | Mic định hướng | **Mic đa hướng**, gắn đầu giường |
| Vision model | MoveNet / YOLO-pose | **MediaPipe Pose** |
| Home Assistant | (ngầm định dùng) | **Bỏ** — build hệ thống riêng |

**Cắt khỏi spec:** Coral USB, MAX30102 (tiếp xúc), MPS20N400D (không đo được huyết áp), MQ303B (đo cồn), toàn bộ blockchain/NFT/token, máy tạo oxy.

---

## Các phase

Michael chốt: **7 phase, nhưng release được từ Phase 05.**

| Phase | Tên | Ra được gì | Ước lượng | Rủi ro |
|---|---|---|---|---|
| [00](phase-00-nen-tang-kien-truc-an-toan.md) | Nền tảng, BOM, khung an toàn | Kiến trúc chốt, BOM, repo, bench rig | 2 tuần | Thấp |
| [01](phase-01-cum-cam-bien-va-data-pipeline.md) | Cụm cảm biến + data pipeline | Giường ghi dữ liệu thật cả đêm | 3-4 tuần | Thấp |
| [02](phase-02-thuat-toan-giac-ngu-apnea.md) | Thuật toán giấc ngủ + apnea | **Sản phẩm bán được #1**: sleep tracker phi tiếp xúc | 3-4 tuần | Thấp |
| [03](phase-03-moi-truong-nhiet-anh-sang-am-thanh.md) | Môi trường: nhiệt, sáng, âm, thông gió | **Sản phẩm #2**: pod điều hoà môi trường ngủ | 3 tuần | Thấp |
| [04](phase-04-co-khi-va-dieu-khien-chuyen-dong.md) | Cơ khí 3 mảng + handler + điều khiển | Chỉnh tư thế bằng app (có người) | 5-6 tuần | **Cao** |
| [05](phase-05-camera-edge-ai.md) | Camera + Edge-AI (MediaPipe Pose) | **PROTOTYPE — release được từ đây** | 5-6 tuần | Trung bình |
| [06](phase-06-closed-loop-va-app-cloud.md) | Closed-loop + app + profile + framework API | **Sản phẩm hoàn chỉnh v3** | 5-6 tuần | Trung bình |
| [07](phase-07-deferred-oxy-eeg-huyet-ap.md) | Deferred: oxy, EEG, huyết áp, 10 điểm | Module tuỳ chọn | — | **Rất cao** |

Phase 02 và 03 mỗi cái đã là một sản phẩm demo/bán thử được. Không phải chờ hết 8 tháng mới có gì cho khách xem.

## Phụ thuộc

```
00 ──► 01 ──► 02 ──┬──► 06
              │    │
              └──► 03
                   │
       04 ─────────┼──► 05 ──► 06
       (chỉ bắt đầu sau khi 02 xong: cần state machine biết người đang nằm/ngủ)
```

Phase 03 và 04 chạy song song được: **03 = Hưng** (phần mềm + điều khiển đơn giản), **04 = anh Khanh** (cơ khí) + Hưng (phần điện/firmware).

## Safety gate (áp cho mọi phase có chuyển động hoặc khí)

Không phase nào cho người nằm lên giường khi chưa qua đủ:
1. Test tải giả (bao cát 100kg) chạy 500 chu kỳ không lỗi.
2. E-stop cắt nguồn actuator dưới 100ms, verify bằng oscilloscope.
3. Phát hiện kẹt bằng dòng: chặn vật cản (khúc gỗ) ở mọi mảng nâng, actuator phải dừng và lùi.
4. Mất điện đột ngột: actuator tự khoá, không rơi tự do. Khoá cửa fail-open (tự mở).
5. Checklist ký tên, lưu trong `docs/safety/`.

---

## Cách làm việc (Michael đặt kỳ vọng 13/07)

> "Anh sẽ hạn chế nhúng tay vô. Anh hỗ trợ, cung cấp đầy đủ tài nguyên và hướng dẫn, **nhưng em phải tự làm hết**."

- Hưng tự làm, Michael không code hộ. Lý do: xem người khác làm thì tưởng mình biết, thực ra chưa biết gì.
- Ràng buộc duy nhất: **token AI**.
- Kỳ vọng đã set: **chủ động báo cáo tiến độ hằng ngày**, không đợi hỏi.
- Quy tắc phần cứng Michael dặn: **luôn cấp nguồn riêng cho mạch, không lấy nguồn từ laptop** — sụt áp gây lỗi random cực khó debug.

## Câu hỏi tồn đọng

1. **"Bạn tiếp theo" là ai?** Michael ghi âm buổi onboarding để đưa cho người kế tiếp → sẽ có thêm 1 người. Khoa Nguyên (85đ) có offer không?
2. Anh Khanh: in-house / ngoài / đối tác? Scope + chi phí phần cơ khí?
3. Ngân sách phần cứng v3 (BOM sơ bộ Phase 00 sẽ ra con số, cần trần để chọn linh kiện).
4. Site pilot — có mốc "pod tại site thật" không, hay tầm nhìn framework đã đổi mục tiêu sang prototype nội bộ?
5. Nhạc thầy Nguyên Minh Thiền Sư — đã xin phép sử dụng chưa (bản quyền)?
6. Mốc deadline cứng nào không (demo nhà đầu tư, hội chợ)?
