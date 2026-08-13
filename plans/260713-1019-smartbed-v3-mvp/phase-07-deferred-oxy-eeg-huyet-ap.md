# Phase 07 — Deferred: oxy, EEG, huyết áp, SpO2 tiếp xúc, đo cồn, 10 điểm nâng

- **Ưu tiên:** P3 (KHÔNG làm trong v3)
- **Trạng thái:** hoãn có chủ đích
- **Rủi ro:** rất cao

File này tồn tại để ghi lại **lý do hoãn**, tránh việc 6 tháng sau có người hỏi "sao spec có mà không làm" rồi lôi vào giữa chừng.

> Cập nhật 13/07: thêm vào danh sách hoãn — **MAX30102 (SpO2 tiếp xúc)**, **MQ303B (đo cồn)**, **10 điểm nâng** (v3 chỉ làm 3 mảng).

---

## 1. Oxy: hoãn, và nếu làm thì phải có khoá liên động

### Vì sao hoãn

Máy tạo oxy DEDAKJ 7 lít/phút bơm oxy 96% vào một **khoang kín cách âm**. Đây không phải tính năng, đây là rủi ro cháy.

- Không khí thường có 21% oxy. Chỉ cần lên **23-24%** là ngưỡng bắt cháy của mọi vật liệu trong khoang tụt xuống rõ rệt: vải, nệm, dây điện, nhựa. Vật liệu bình thường khó cháy sẽ cháy dữ dội.
- Trong khoang đó có: màn LCD 45 inch, dải LED, 10 động cơ servo, khoá điện, một máy tính. Toàn nguồn phát nhiệt và tia lửa tiềm tàng.
- Người nằm bên trong, cửa có khoá.
- Biện pháp trong spec (cảm biến khói Aqara + bình chữa cháy mini 500ml) là **chữa cháy sau khi đã cháy**. Trong môi trường giàu oxy, ngọn lửa lan nhanh tới mức 500ml là vô nghĩa.

Thêm nữa: khoang kín có người thở thì **CO₂ tích tụ**. Spec không hề nhắc tới CO₂ hay thông gió. Đây là lỗ hổng nghiêm trọng độc lập với chuyện oxy.

### Nếu sau này vẫn muốn làm, điều kiện tối thiểu

1. Cảm biến nồng độ **O₂** trong khoang, dư thừa hai con độc lập.
2. Cảm biến **CO₂**, và quạt thông gió cưỡng bức chạy nền, không phụ thuộc phần mềm.
3. **Khoá liên động phần cứng:** O₂ vượt 23% thì van đóng, quạt chạy tối đa, khoá cửa mở, không đi qua phần mềm.
4. Vật liệu trong khoang phải là loại chống cháy, đánh giá lại toàn bộ BOM.
5. Chữa cháy đúng chuẩn, không phải bình mini.
6. Tư vấn từ chuyên gia PCCC. Việc này ngoài năng lực của một team phần mềm và không nên tự làm.

### Thay thế rẻ và an toàn hơn (nên cân nhắc cho v3)

Spec có trích một nghiên cứu về **ion oxy âm** cải thiện chất lượng giấc ngủ (rút ngắn thời gian vào giấc, kéo dài giấc ngủ sóng chậm). Máy tạo ion âm rẻ, không làm tăng nồng độ oxy, không gây cháy. Nếu muốn có "yếu tố không khí" trong sản phẩm thì đây là đường đi hợp lý hơn nhiều so với máy tạo oxy y tế. Có thể thêm vào Phase 03.

**Thông gió thì bắt buộc phải làm ngay trong v3**, không hoãn: khoang kín có người ngủ 8 tiếng cần quạt thông gió và cảm biến CO₂. Đưa việc này về Phase 03.

---

## 2. EEG phi tiếp xúc: hoãn

Chính paper mà spec trích dẫn đã nói rõ giới hạn: nhiễu 2µVrms ở khoảng cách cảm biến 0.2mm, nhưng nhảy lên **17µVrms ở 3.2mm**. Tức là chỉ cần cách da đầu 3mm là tín hiệu đã tệ đi gần 9 lần.

Thực tế: đầu người trên gối xê dịch vài centimet suốt đêm, lại còn tóc, gối, chăn. Khoảng cách 0.2mm là điều kiện phòng thí nghiệm, không phải điều kiện ngủ.

Đây là tính năng rủi ro cao nhất, giá trị thấp nhất trong ngắn hạn. Và may là **không cần nó**: literature trong chính spec cho thấy sleep staging bằng camera rPPG đạt 81% accuracy, đủ dùng cho một sản phẩm wellness. Phase 05 làm việc đó.

Nếu sau này muốn EEG thật, con đường thực tế là **một băng đô đeo tuỳ chọn** (contact EEG, đã có sản phẩm thương mại chạy được), bán kèm cho ai cần dữ liệu sâu, thay vì cố nhét cảm biến vào gối.

---

## 3. Huyết áp qua camera (IPPG): hoãn

Kỹ thuật thì có paper, nhưng vấn đề không nằm ở kỹ thuật, nằm ở **pháp lý và niềm tin**.

Ngay khi sản phẩm nói "đo huyết áp", nó bước vào địa hạt thiết bị y tế. Kéo theo: chứng nhận, kiểm định lâm sàng, trách nhiệm pháp lý khi số sai. Một người cao huyết áp tin vào con số sai của cái giường rồi bỏ thuốc là kịch bản không ai muốn.

Ba lựa chọn, và tôi đề xuất chọn cái đầu:

1. **Bỏ khỏi v3.** Sạch sẽ, không mất gì đáng kể.
2. Giữ nhưng gọi là "chỉ số xu hướng tuần hoàn", không phải mmHg, không phải huyết áp. Nửa vời, dễ gây hiểu nhầm.
3. Làm nghiêm túc theo hướng thiết bị y tế: nhánh riêng, ngân sách riêng, timeline riêng. Không nhét vào v3.

---

---

## 4. SpO2 tiếp xúc (MAX30102): để sau

Michael chốt 13/07: **để sau, vì phải chạm vào người.** Toàn bộ triết lý sản phẩm là **non-contact** — mọi cảm biến giấu khỏi tầm nhìn, không ai phải đeo gì. Nhét một con cảm biến phải áp vào da là phá vỡ chính điều làm sản phẩm này khác biệt.

Nếu sau này thật sự cần SpO2: đi đường **phụ kiện tuỳ chọn** (kẹp ngón tay / nhẫn), bán rời cho ai cần, không nhét vào giường.

---

## 5. Đo nồng độ cồn (MQ303B): để sau

Không đóng góp gì cho chất lượng giấc ngủ. Là một cảm biến cồn, không phải "máy phân tích hơi thở" như tên gọi trong spec gợi ý.

---

## 6. 10 điểm nâng: hoãn — v3 chỉ làm 3 mảng

Michael chốt 13/07: **10 điểm → 3 mảng** (đầu / giữa rộng / chân).

Lý do hợp lý:
- 10 actuator độc lập = 10 lần rủi ro kẹp, 10 lần chi phí, 10 lần điểm hỏng.
- 3 mảng đã chỉnh được các tư thế có giá trị lâm sàng thật (nâng đầu chống ngáy, nâng chân giảm áp lực lưng).
- Con số "10 điểm" là con số trong slide 2023, **không phải yêu cầu sinh lý** — chưa ai chứng minh 10 tốt hơn 3.

Mở lại 10 điểm khi: có dữ liệu thật từ người dùng cho thấy 3 mảng **không đủ**, và có ngân sách + người làm cơ khí ổn định.

---

## Tóm lại

| Tính năng trong spec | Quyết định v3 | Điều kiện để mở lại |
|---|---|---|
| Máy tạo oxy | **Cắt** | Có cảm biến O₂/CO₂ + khoá liên động phần cứng + tư vấn PCCC |
| Ion oxy âm | **Đưa vào Phase 03 — nên có** | Rẻ, an toàn, có literature. Đã chốt 13/07 |
| Thông gió + cảm biến CO₂ | **Làm ngay, đưa về Phase 03** | Bắt buộc cho mọi khoang kín có người |
| EEG trong gối | **Hoãn** | Chỉ khi có bằng chứng tín hiệu sạch trong điều kiện ngủ thật |
| Huyết áp qua camera | **Bỏ khỏi v3** | Chỉ khi quyết định đi đường thiết bị y tế |
| MAX30102 (SpO2 tiếp xúc) | **Để sau** | Chỉ dưới dạng phụ kiện tuỳ chọn, không nhét vào giường |
| MQ303B (đo cồn) | **Để sau** | Không có nhu cầu thật |
| 10 điểm nâng | **Hoãn — v3 làm 3 mảng** | Khi có data thật chứng minh 3 mảng không đủ |
| Blockchain / NFT / token | **Cắt hẳn** | Không có điều kiện nào. Nó không thuộc về sản phẩm này |
| Home Assistant / Node-RED | **Cắt** | Automation đi đường AI intent, không kéo-thả |
