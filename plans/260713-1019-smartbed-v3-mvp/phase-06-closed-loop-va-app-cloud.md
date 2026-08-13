# Phase 06 — Closed-loop + app + profile + **framework API**

- **Ưu tiên:** P2
- **Trạng thái:** chưa bắt đầu
- **Ước lượng:** 5-6 tuần
- **Rủi ro:** trung bình
- **Phụ thuộc:** Phase 02, 03, 04, 05

## Mục tiêu

Ghép tất cả lại thành sản phẩm v3 hoàn chỉnh: giường **tự phản ứng** với những gì nó thấy, người dùng mang được hồ sơ giấc ngủ đi bất cứ đâu — và **quan trọng nhất: mở hệ thống ra cho developer.**

> **Đây là phase hiện thực hoá định vị "framework, không phải sản phẩm".** Ba mục dưới (closed-loop, profile, app) là phần "sản phẩm". Mục 4 (framework API + template) là phần "nền tảng" — và đó mới là thứ Michael muốn.

## 1. Closed-loop (giá trị thật của cả dự án)

Đây là điểm mà SmartBed khác một cái đồng hồ theo dõi giấc ngủ: nó không chỉ báo cáo, nó **can thiệp**.

### Vòng lặp chống ngáy / ngưng thở (ưu tiên số 1)
```
Phát hiện ngáy hoặc apnea (Phase 02)
  + đang nằm ngửa (Phase 05)
    → nâng đầu giường 15-30 độ, thật chậm (Phase 04)
      → đo lại sau 5 phút: ngáy có giảm không?
        → có: giữ. không: hạ lại, thử nghiêng nhẹ
```
Chèn thêm ràng buộc an toàn từ Phase 04: chuyển động phải cực chậm, biên độ nhỏ, và bị chặn nếu phát hiện bất thường. Đây là ngoại lệ duy nhất cho quy tắc "cấm chuyển động khi ngủ" ở Phase 04, và phải được bật riêng, mặc định tắt cho tới khi test đủ.

### Vòng lặp nhiệt theo pha ngủ
Sleep stage (Phase 05) → điều chỉnh đường cong nhiệt (Phase 03). Mát sâu khi ngủ sâu, ấm dần trước khi dậy.

### Vòng lặp đánh thức thông minh
Đánh thức trong cửa sổ 30 phút quanh giờ báo thức, chọn đúng lúc đang ở giai đoạn ngủ nông. Đèn sáng dần + âm thanh nhẹ, không chuông chói tai.

## 2. Hồ sơ người dùng + passkey (giữ phần hay, bỏ blockchain)

Spec đề xuất blockchain riêng (Amate), NFT, trả token cho người dùng khi chia sẻ dữ liệu. **Cắt toàn bộ.** Nó không cải thiện giấc ngủ một chút nào, nhưng ngốn effort ngang một sản phẩm riêng, và kéo theo rủi ro pháp lý về tiền mã hoá.

Phần thực sự có giá trị, làm được bằng mã hoá thường:

- **Đăng ký bằng QR code + điện thoại** (giữ nguyên ý tưởng của spec, ý này hay).
- Dữ liệu mã hoá bằng khoá dẫn xuất từ passkey của người dùng, mở khoá bằng sinh trắc trên điện thoại (Face ID / vân tay). Đây chính là passkey/WebAuthn tiêu chuẩn, không cần chain.
- **Hồ sơ mang theo được:** nằm lên một SmartBed khác, quét QR, giường tự nạp lại tư thế và cài đặt quen thuộc. Đây là tính năng bán hàng mạnh (khách sạn, phòng khám), và làm được mà không cần blockchain.
- Chia sẻ dữ liệu cho nghiên cứu: opt-in, ẩn danh, xuất file. Chuyện trả token để sau, nếu thật sự có nhu cầu.

## 3. App + cloud

- **App Flutter** (chốt 13/07): chạy cả Android + iOS. Báo cáo giấc ngủ, điều khiển tư thế, cài lịch, ghi đè bằng tay, load template.
- **Backend: K8s** (Michael chốt 13/07 — K8s, không phải K3s).
  - ⚠️ *Ghi chú kỹ thuật:* với vài chục giường thì K8s là kiến trúc nặng hơn nhu cầu; một backend đơn + Postgres đã đủ. Nhưng Michael chốt K8s để không phải migrate khi mở rộng, và vì định vị framework/platform cần chỗ cho multi-tenant + marketplace về sau. Ghi lại trade-off này, không tự ý đảo ngược.
- **Offline-first, bắt buộc:** mất mạng thì giường vẫn phải chạy đủ mọi tính năng. Cloud chỉ để đồng bộ và xem lịch sử dài hạn. Không ai chấp nhận cái giường ngừng hoạt động vì rớt wifi.
- **Màn hình: tablet nhỏ** (iPad hoặc Android rẻ) gắn trong khoang — bỏ LCD 45". Dashboard cục bộ, điều khiển, load template. Dùng chung code Flutter với app.

## 4. Framework API + AI intent + template platform (phần quan trọng nhất)

Đây là thứ biến SmartBed từ "cái giường" thành "nền tảng".

### 4.1. API mở
- Mọi **input** (cảm biến) và **output** (lệnh điều khiển) phải addressable từ bên ngoài qua API công khai.
- Developer bên thứ ba viết được chức năng mới mà không cần sửa code lõi.
- Contract phải ổn định — đã thiết kế từ Phase 00, đến đây là công bố.

### 4.2. AI intent-based (thay rule engine)
Thay vì lệnh cứng ("bật đèn", "giảm nhiệt độ"), hệ hiểu **ý định** theo ngữ cảnh:
- Người dùng nói *"sáng quá"* → AI suy ra: giảm độ sáng đèn.
- Nói *"hơi nóng"* → AI suy ra: hạ nhiệt độ máy lạnh.
- Không ai phải học cú pháp lệnh.

Kỹ thuật: **function calling / agentic AI** — định nghĩa các function (chỉnh đèn, chỉnh nhiệt, đổi nhạc, kể chuyện, đọc tin tức...) rồi để LLM chọn function theo intent + context.

**Michael đã chạy thật mô hình này tại nhà** (MQTT + AI intent, điều khiển đèn/máy lạnh/cửa bằng câu nói tự nhiên) và sẽ bàn giao lại pattern + stack. Không phải phát minh từ đầu.

**Bỏ Home Assistant + Node-RED.** Automation kéo-thả sẽ thành cản trở khi có AI.

### 4.3. Template platform (moonshot)
- Public ~**100 template mẫu**: khó ngủ, đau đầu, sáng thức dậy, mới vào giấc, người già 75 tuổi, người trẻ 25-30 tuổi…
- **Template là VĂN BẢN, không phải code.** AI convert văn bản → logic hệ thống.
- Developer/người dùng up template lên **GitHub**. Trên tablet bấm 1 cái → load về → giường có chức năng đó.
- Có **template của template** để lọc/chuẩn hoá template do cộng đồng đóng góp.
- Cần **long-term memory + short-term memory** cho AI.
- Mục tiêu: tạo **cộng đồng**, không phải bán một cái giường.

## Việc phải làm

1. Rule engine cho closed-loop (giai đoạn đầu: if-then có ràng buộc an toàn — dễ kiểm chứng). **Viết dưới dạng contract mở để AI thay thế được ở bước sau.**
2. Test vòng chống ngáy trên người thật, có giám sát, ban đầu chỉ chạy khi có người ngồi cạnh theo dõi.
3. Đăng ký QR + passkey + mã hoá dữ liệu.
4. App Flutter (báo cáo + điều khiển + load template).
5. Backend K8s + đồng bộ + xuất dữ liệu.
6. Web/Flutter app cho tablet trong khoang.
7. **API công khai** — mọi input/output addressable.
8. **AI intent + function calling** — bàn giao pattern từ hệ nhà Michael.
9. **Template engine + 100 template mẫu + repo GitHub cộng đồng.**
10. Kiểm thử mất mạng: rút wifi, mọi tính năng lõi phải còn nguyên.

## Định nghĩa hoàn thành

- [ ] Vòng chống ngáy chạy được và **đo được hiệu quả** (số phút ngáy giảm so với đêm không bật)
- [ ] Chuyển động ban đêm không đánh thức người dùng (kiểm chứng bằng chính dữ liệu sleep stage)
- [ ] Quét QR trên giường thứ hai, hồ sơ nạp lại đúng
- [ ] Rút mạng: mọi tính năng lõi vẫn chạy
- [ ] App hiện báo cáo giấc ngủ đọc hiểu được, không phải biểu đồ kỹ thuật khô khan
- [ ] **Nói "hơi nóng" → giường hiểu và hạ nhiệt độ.** Không cần cú pháp lệnh
- [ ] **Một developer ngoài team viết được 1 chức năng mới chỉ bằng API công khai + tài liệu, không cần hỏi ai**
- [ ] **Load được 1 template từ GitHub xuống giường qua tablet, chức năng chạy thật**

## Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Giường chuyển động ban đêm làm người dùng thức giấc, phản tác dụng | Chuyển động cực chậm, biên độ nhỏ. Đo bằng chính dữ liệu của mình: nếu số lần thức giấc tăng thì tính năng này thất bại, phải tắt và ghi nhận trung thực |
| Vòng closed-loop "sửa" sai và làm giấc ngủ tệ đi | Luôn có nhóm đối chứng (đêm bật / đêm tắt). Không tin cảm nhận chủ quan, tin số liệu |
| Kiến trúc cloud phình to sớm | Chống lại cám dỗ. Một backend + Postgres cho tới khi có vấn đề thật về quy mô |
