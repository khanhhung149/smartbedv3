# Handoff Brief — SmartBed v3 (chuyển sang Claude Code project riêng)

- **Ngày:** 2026-07-13
- **Từ:** repo `mkt` (EVsafe/CHTLab marketing) — SmartBed đang bị nhét nhờ trong đây, cần tách ra
- **Đến:** Claude Code session mới, project riêng cho SmartBed v3
- **Cách dùng:** paste toàn bộ file này làm message đầu tiên cho session mới, kèm thư mục `plans/260713-1019-smartbed-v3-mvp/` và `docs/meetings/260713-1259-onboarding-khanh-hung-smartbed-v3/`

---

## 1. Bối cảnh — đọc trước khi làm gì

**SmartBed** là dự án phần cứng + AI của **CHTLab** (công ty mẹ; CEO là Patrick = Nguyễn Xuân Thời). Người dẫn dắt kỹ thuật là **Michael (Sơn)** — `michael@chtlab.io`.

Đây là **v3**. Trước đó:
- **Phase 1 (2023-2025):** đã tiêu ~10B VND, ra được Model 1 + Model 2 (giường chạy được, BOM 49.2M), app Flutter đã publish, 3 AI addon đã deploy trên edge. **Doanh thu: 0.** Team cũ giải tán. Charter tháng 5/2026 tự đánh giá: *"70% đã build, 0 doanh thu, sai thị trường."*
- **v3 (bây giờ):** làm lại, định vị lại.

**Quyết định 13/07: build mới phần cứng theo spec đã sửa** (không lấy Model 2 làm nền), nhưng **được tái sử dụng phần mềm/AI đã chạy** (repo `nott-smartbed`: YOLO11n-pose, CNN snore detection, HRV sleep-staging).

---

## 2. Định vị sản phẩm — ĐIỀU QUAN TRỌNG NHẤT

> "Mục tiêu của anh **không phải làm một sản phẩm để bán, mà làm một framework**." — Michael, 13/07/2026

SmartBed **không phải cái giường**. Nó là **nền tảng**: nhiều thông số đầu vào (cảm biến), nhiều lệnh điều khiển đầu ra, **mở cho developer** gắn thêm chức năng. Mô hình App Store.

Bốn hệ quả **bắt buộc** lên mọi quyết định kỹ thuật:

1. **Thu thập TẤT CẢ data** — kể cả data hôm nay chưa ai dùng. Developer sau này sẽ cần. Không được cắt cảm biến chỉ vì "chưa dùng tới". Chỉ cắt cái **sai về vật lý** hoặc **vi phạm nguyên tắc non-contact**.
2. **Kiến trúc là API/contract mở**, không phải app đóng. Mọi input/output phải addressable từ bên ngoài.
3. **Autopilot bằng AI** (về sau): điều khiển theo **intent** ("sáng quá", "hơi nóng"), không phải lệnh cứng. Michael đã chạy thật mô hình này tại nhà (MQTT + AI function-calling, điều khiển đèn/máy lạnh/cửa bằng câu nói tự nhiên) và sẽ bàn giao pattern.
4. **Moonshot — template platform:** public ~100 template mẫu (khó ngủ, đau đầu, sáng thức dậy, người già 75t, người trẻ 25-30t…). **Template là VĂN BẢN, không phải code** — AI convert sang logic hệ thống. Developer up template lên GitHub, người dùng bấm 1 cái trên tablet là load về. Mục tiêu: tạo **cộng đồng**.

**Định vị pháp lý: wellness device, KHÔNG claim y tế.** Mọi chỉ số (apnea, nhịp thở, sleep stage) gắn nhãn "tham khảo, không dùng chẩn đoán". Đây là điều kiện để đi nhanh mà không vướng chứng nhận thiết bị y tế.

---

## 3. Nhân sự

| Người | Vai trò | Ghi chú |
|---|---|---|
| **Michael (Sơn)** | Định hướng kỹ thuật, chốt quyết định | **Hạn chế nhúng tay có chủ đích.** "Anh hỗ trợ, cung cấp tài nguyên và hướng dẫn, nhưng em phải tự làm hết." Đang học tiến sĩ về AI |
| **Hưng** (Cao Huỳnh Khánh Hưng) | KS điện tử — điện, firmware, AI | **Onboard 13/07/2026** (ngày đầu). Take-home 87/100 (#1). Junior. Điểm cần rèn: **chủ động báo cáo tiến độ hằng ngày**, không đợi hỏi |
| **anh Khanh** | **Cơ khí** | Gỡ được blocker số 1 của dự án. Chưa rõ in-house / ngoài / đối tác |
| **"bạn tiếp theo"** | ? | Michael ghi âm buổi onboarding để đưa cho người kế tiếp → sẽ có thêm 1 người. Có thể là Khoa Nguyên (85đ) |

**Ràng buộc duy nhất với Hưng:** token AI (Michael đang dùng 3 gói max vẫn hit limit).

---

## 4. Stack đã chốt (meet 13/07) — KHÁC spec PDF 2023

Spec gốc là `[SmartBed] MVP Specs slight introduction.pdf` (52 slides, bản **2023**, release plan đã lệch 2 năm). **Đừng coi PDF đó là chuẩn.** Nó có 4 lỗi linh kiện và 2 mâu thuẫn nội tại. Bảng dưới là spec thật.

| Hạng mục | PDF 2023 | **CHỐT v3** |
|---|---|---|
| MCU | STM32 | **ESP32 duy nhất** (được dùng nhiều biến thể; ESP8266 cho việc nhẹ) |
| AI / bộ não | Orange Pi 5+ / Coral / Jetson | **Jetson Orin** (đã có sẵn thiết bị). **Bỏ Coral** |
| Màn hình | LCD 45" 4K | **Tablet nhỏ** (iPad / Android rẻ) |
| App | Flutter | **Flutter** (giữ) — Android + iOS |
| Backend | k3s + CockroachDB + Mongo + Redis | **K8s** |
| Cơ khí | **10 điểm nâng** | **3 mảng**: đầu / giữa rộng / chân. Cung độ nhỏ, tốc độ chậm, ồn thấp. 10 điểm → hoãn |
| Radar | HLK-LD2410B | **HLK-LD2510B** (track nhiều người cùng lúc + vị trí thật; 2410B chỉ cho khoảng cách gần đúng) |
| Cân nặng | Loadcell 150kg | **Piezoelectric pad** (cho thêm BCG, không trôi theo nhiệt) |
| Mic | Mic định hướng (shotgun) | **Mic đa hướng**, gắn đầu giường |
| Vision | (không rõ) | **MediaPipe Pose** trên GPU Jetson |
| LED | Dải RGB | **WLED** (flash online; thuật toán chuyển màu mượt hơn tự viết nhiều) |
| Âm thanh | Denon 5.1 | **1 cặp loa 2.0** (dùng loa có sẵn trong kho). Nhạc: **thầy Nguyên Minh Thiền Sư** (chuyên gia y học giấc ngủ VN) — ⚠️ **chưa xin bản quyền** |
| Nhiệt | Máy lạnh monoblock 300W @ 55dB | **Monoblock loại ÍT ỒN** (ràng buộc mua hàng, không phải mong muốn) |
| Thông gió | (không có — lỗ hổng) | **Quạt hút 12V + màng che + cảm biến CO₂.** Phần mềm chỉ được TĂNG tốc quạt, không được tắt |
| Ion âm | (không có) | **Nên có** — rẻ, an toàn. *Khác hoàn toàn máy tạo oxy* |
| Automation | Home Assistant | **BỎ HA + Node-RED.** Build hệ riêng, automation bằng AI intent |

### CẮT / HOÃN — đừng đề xuất làm lại

| Bỏ | Lý do |
|---|---|
| **Máy tạo oxy (DEDAKJ 7 LPM)** | 96% O₂ vào pod kín = môi trường giàu oxy → vật liệu thường trở nên dễ bắt cháy, cạnh nguồn điện + LCD + motor. Bình chữa cháy mini 500ml không phải biện pháp kiểm soát rủi ro |
| **EEG phi tiếp xúc qua gối** | Paper gốc đo 2µVrms @ **0.2mm**, 17µVrms @ 3.2mm. Qua gối + tóc = vài cm → SNR sụp. Là research-grade, không phải MVP-grade |
| **Huyết áp (MPS20N400D)** | Sai linh kiện — đó là cảm biến áp suất khí công nghiệp, không đo được huyết áp |
| **MAX30102 (SpO2)** | Phải chạm da → phá vỡ triết lý non-contact. Nếu cần: đi đường phụ kiện rời |
| **MQ303B ("breath analyzer")** | Chỉ đo cồn. Không đóng góp gì cho giấc ngủ |
| **Blockchain / NFT / token (Amate)** | Không giải quyết vấn đề nào của khách. Vướng pháp lý |
| **10 điểm nâng** | v3 làm 3 mảng. Mở lại khi có data chứng minh 3 mảng không đủ |

---

## 5. Plan — 7 phase, **release được từ Phase 05**

Thư mục: `plans/260713-1019-smartbed-v3-mvp/` (`plan.md` + `phase-00` … `phase-07`).

| Phase | Nội dung | Ra được gì | Ước lượng |
|---|---|---|---|
| **00** | Nền tảng, BOM, khung an toàn | Kiến trúc chốt, repo, bench rig | 2 tuần |
| **01** | Cụm cảm biến + data pipeline | Giường ghi data thật cả đêm | 3-4 tuần |
| **02** | Thuật toán giấc ngủ + apnea | **Sản phẩm bán được #1** (sleep tracker phi tiếp xúc) | 3-4 tuần |
| **03** | Môi trường: nhiệt, sáng, âm, thông gió | **Sản phẩm #2** (pod điều hoà môi trường ngủ) | 3 tuần |
| **04** | Cơ khí 3 mảng + handler + điều khiển | Chỉnh tư thế bằng app | 5-6 tuần · **rủi ro cao nhất** |
| **05** | Camera + MediaPipe Pose | **PROTOTYPE — RELEASE ĐƯỢC TỪ ĐÂY** | 5-6 tuần |
| **06** | Closed-loop + app + **framework API + template platform** | Sản phẩm v3 hoàn chỉnh | 5-6 tuần |
| **07** | Deferred: oxy, EEG, huyết áp, 10 điểm | Ghi lại lý do hoãn | — |

Phase 02 và 03 mỗi cái **đã là một sản phẩm bán thử được**. Không phải chờ hết 8 tháng mới có gì cho khách xem.

Phase 03 và 04 chạy song song: **03 = Hưng** (phần mềm), **04 = anh Khanh** (cơ khí) + Hưng (điện/firmware).

---

## 6. Ba yêu cầu kỹ thuật đặc biệt Michael chốt (đừng bỏ sót)

**1. Handler module cho cơ khí (bắt buộc).**
Cơ khí phải có **một module quản trị riêng**. Mọi thành phần khác **chỉ được giao tiếp qua handler**, không ai đụng thẳng vào actuator. **Cơ chế safety nằm BÊN TRONG handler** (tự chặn khi lệnh dồn quá nhiều, khi chạy vượt giới hạn, khi dòng bất thường) — không rải rác ở tầng trên.

**2. Position feedback + auto-calibrate.**
Hệ phải biết mình đang ở **vị trí nào (%)**, không chỉ biết "đang chạy". Dùng encoder.
Pattern Michael đã chạy thật trên hệ cửa tự động ở nhà:
> Nếu actuator **tự dừng** (không phải người ra lệnh dừng) ở vùng **< 15% gần đầu mút hành trình** → đó chính là điểm giới hạn vật lý → **tự sync vị trí về 0%/100%**.

Lợi ích: không cần công tắc hành trình, không cần calibrate thủ công. Encoder trượt vài % thì lần chạm biên kế tiếp tự sửa. *Thuật toán thay thế phần cứng.*

**3. Nguyên tắc kiến trúc an toàn (không thoả hiệp).**
Tầng Linux/AI (Jetson) **không được ra lệnh chuyển động trực tiếp**. Nó gửi "yêu cầu tư thế" xuống ESP32, và **ESP32 có quyền từ chối**. Linux không real-time; actuator đang đè lên người mà kernel bận 200ms là đủ gây thương tích. ESP32 phải giữ được 3 việc kể cả khi Linux treo: **dừng khẩn cấp, phát hiện kẹt, khoá vị trí khi mất điện**.

**Quy tắc phần cứng Michael dặn:** **luôn cấp nguồn riêng cho mạch, KHÔNG lấy nguồn từ laptop.** Sụt áp gây lỗi random cực khó debug.

---

## 7. Safety gate — không có đường tắt

Không cho người nằm lên giường khi chưa qua đủ:
1. Test tải giả (bao cát 100kg) chạy 500 chu kỳ không lỗi.
2. E-stop cắt nguồn actuator dưới 100ms (verify bằng oscilloscope). Nút phải **trong tầm với của người đang nằm**.
3. Phát hiện kẹt bằng dòng: chèn vật cản ở mọi mảng → actuator dừng dưới 200ms và lùi.
4. Mất điện đột ngột: actuator tự khoá, không rơi tự do. Khoá cửa **fail-open** (tự mở).
5. CO₂ < 1000ppm sau 8h người ngủ, cửa đóng.
6. Checklist ký tên, lưu `docs/safety/`.

**Người đầu tiên nằm lên phải là kỹ sư, không phải khách.**
Mặc định: **cấm mọi chuyển động tự động khi người đang ngủ.** Chỉ chỉnh khi người còn thức hoặc chủ động ra lệnh.

---

## 8. Việc cần làm ngay (tuần này)

| Việc | Owner | Hạn |
|---|---|---|
| Gửi Hưng list linh kiện + tài nguyên đã hứa trong buổi họp | Michael | 14/07 |
| Đặt mua **LD2510B** + **piezoelectric pad** | Hưng | 18/07 |
| Kết nối Hưng ↔ anh Khanh; brief 3 mảng + handler + position feedback | Michael | 18/07 |
| Setup ESP32 toolchain; flash thử WLED trên ESP8266 | Hưng | 18/07 |
| Kiểm kê kho cảm biến/compute thật (có gì, còn sống không, thiếu gì) | Hưng | 18/07 |
| Tìm máy lạnh monoblock **ít ồn** (đo dB thật, không tin datasheet) | Hưng | 25/07 |
| Chốt trần ngân sách BOM v3 | Michael | 26/07 |

---

## 9. Câu hỏi chưa giải quyết (hỏi Michael trước khi tự quyết)

1. **Anh Khanh** là ai — in-house / ngoài / đối tác? Scope + chi phí phần cơ khí?
2. **"Bạn tiếp theo"** là ai? (Michael ghi âm buổi onboarding để đưa cho người kế tiếp)
3. **Ngân sách BOM v3** — chưa có con số. Ước 60-90M/pod (đã trừ oxy).
4. **Site pilot** — có mốc "pod tại site thật" không, hay định vị framework đã đổi mục tiêu sang prototype nội bộ? (Buổi họp 13/07 không nhắc tới pilot.)
5. **Bản quyền nhạc** thầy Nguyên Minh Thiền Sư — xin phép chưa?
6. **MOU bàn giao** với CHTLab + Phan Đình Sơn **chưa ký** → IP/brand chưa rõ chủ. Chặn thương mại hoá, chưa chặn kỹ thuật.
7. **Mốc deadline cứng** nào không (demo nhà đầu tư, hội chợ)?
8. Advisor y khoa về giấc ngủ **trống từ 10/2025** (GS Dương Quý Sỹ) — cần trước khi công bố bất kỳ claim sức khoẻ nào.

---

## 10. Lưu ý về tên (tránh nhầm người)

- **Michael = Sơn** (1 người). **Patrick = Thời** (1 người, CEO CHTLab).
- **Michael (Sơn)** ≠ **Phan Đình Sơn** (tech manager phase 1 của CHTLab).
- **Ming / Lê Quang Minh** (KS điện tử EVsafe, làm trụ sạc) ≠ **Nguyễn Quang Minh** (ứng viên intern).
- **Cao Huỳnh Khánh Hưng** (take-home 87đ, đã onboard) ≠ **Cao Huỳnh Khánh Hùng** (ứng viên khác, fresh HUTECH).

---

## Tài liệu kèm theo

```
plans/260713-1019-smartbed-v3-mvp/
├── plan.md                                    ← đọc file này trước
├── phase-00-nen-tang-kien-truc-an-toan.md
├── phase-01-cum-cam-bien-va-data-pipeline.md
├── phase-02-thuat-toan-giac-ngu-apnea.md
├── phase-03-moi-truong-nhiet-anh-sang-am-thanh.md
├── phase-04-co-khi-va-dieu-khien-chuyen-dong.md
├── phase-05-camera-edge-ai.md
├── phase-06-closed-loop-va-app-cloud.md
└── phase-07-deferred-oxy-eeg-huyet-ap.md

docs/meetings/260713-1259-onboarding-khanh-hung-smartbed-v3/
├── meeting-minutes-260713-1259-*.md           ← biên bản chốt spec
└── transcript-260713-1259-*.md                ← transcript đầy đủ 52 phút
```

**Nguồn spec gốc (tham khảo, KHÔNG phải chuẩn):** `[SmartBed] MVP Specs slight introduction.pdf` — bản 2023, đã lỗi thời.
