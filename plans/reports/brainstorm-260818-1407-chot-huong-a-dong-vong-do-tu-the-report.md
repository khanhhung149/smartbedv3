# Brainstorm — Chốt hướng A: đóng vòng đo tư thế trước khi sang Phase 01

- **Ngày:** 2026-08-18 14:07
- **Bối cảnh vào:** câu hỏi "bây giờ đến phase mấy"; ba hướng A/B/C được trình bày, Hưng chọn **A**
- **Kết quả:** A được chấp nhận, phạm vi khoá lại 5 bước, thêm 1 pha đo, chốt luật dừng

---

## 1. Vị trí thật của dự án (đọc từ repo 18/08)

| Lớp | Trạng thái |
|---|---|
| Plan MVP `260713-1019` | Cả 7 phase file vẫn ghi "chưa bắt đầu", không sửa từ 13/07 |
| Phase 00 | Quá hạn ~3 tuần (hạn 27/07). 2 doc xong nội dung chờ Michael duyệt; BOM + hệ toạ độ chặn ở người khác |
| Phase 01 | Chưa đụng. LD2510B + piezo **đã mua, chưa cắm dây lần nào** |
| Plan PoC `260814-1237` | completed 14/08, 4/4 phase |
| Nhánh phụ 14/08 → 18/08 | Đang chạy — việc nghiệm thu vision, thuộc tiền-Phase-05 |

**Kết luận:** chính thức ở Phase 00; thực tế đang làm việc tiền-Phase-05 trên nhánh công cụ `scripts/pose-poc/`. Không sai — đúng quyết định 14/08 ("test bằng đồ đã có trước khi tiêu tiền"). Nhưng tạo ảo giác tiến độ, và Phase 01 vẫn đứng yên.

## 2. Sửa lại ba điểm báo cáo sai lúc đầu phiên

Báo cáo đầu phiên dựa trên report 16/08, chưa đọc code chưa commit. Sau khi đọc `posture.py` + `protocol.py`:

| Nói lúc đầu | Thực tế |
|---|---|
| "Test chăn chưa làm" | **Đã làm 17/08.** Chăn KHÔNG giết phát hiện: 66–91% qua các lượt (`protocol.py:40`). Bác bỏ nỗi lo lớn nhất của brainstorm 14/08 |
| "posture.py là bước sau, bước trước chưa đóng" | Đã có **5 lượt đo** ngày 17/08. Luật tiến hoá 2 thế hệ |
| "Chưa nghiệm thu chất lượng pose" | Đúng phần kết luận, sai phần lý do — không phải chưa đo, mà là **chưa có lượt held-out** |

Thêm: đã bắt được bug thật — OV2640 bật sẵn hmirror → ảnh lật gương → **đảo ngữ nghĩa trái/phải của landmark**. Fix nằm trong `main.c`, chưa commit.

## 3. Vì sao A là lựa chọn đúng lúc này

A rẻ hơn nhiều so với ước lượng ban đầu: không phải "bắt đầu đo" mà là "chạy một lượt kiểm chứng + ghi + commit" ≈ một buổi.

Lập luận giữ A trên B (quay về Phase 01):
- Công đã bỏ ra 17/08 (5 lượt đo, 2 thế hệ luật, 1 bug firmware) hiện **chưa được commit và chưa vào docs**. Bỏ dở đúng lúc này là mất trắng phần đắt nhất — số đo có nhãn.
- Bước còn lại nhỏ và có điểm dừng rõ, khác với B là một vòng dài mở.
- B không bị mất: nó là việc kế tiếp, không phải việc cạnh tranh.

Điều A **không** làm: không mở khoá Phase 02, không chạm radar/piezo. Sau A, B vẫn là việc phải làm.

## 4. Ba bẫy đã nhận diện

### 4.1 Ngưỡng 0.12 được chọn từ chính 5 lượt sẽ dùng để chấm — NGHIÊM TRỌNG NHẤT

`posture.py:47` đặt `_SIDE_Z_MAGNITUDE = 0.12` vì nó nằm giữa khoảng trống 0.057–0.191 quan sát được ở 5 lượt 17/08. Chấm luật trên đúng bộ số đã dùng để đặt ngưỡng thì kết quả đo trí nhớ, không đo khả năng khái quát.

→ Lượt tới phải **held-out thật**. Xem §5 luật dừng.

### 4.2 Nhánh `PRONE` chưa bao giờ được đo — LỖ HỔNG THẬT

`DEFAULT_PHASES` có 3 pha; `classify()` trả 4 nhãn. `PRONE` là **nhánh cuối cùng**, nuốt mọi frame có `|z| < 0.12` **và** mặt không nhìn rõ:

```python
return (SUPINE if face_visibility >= 0.5 else PRONE)
```

Hệ quả: mọi lúc mặt bị che mà thân vẫn thấy — tay vắt lên mặt, chăn kéo tới cổ, mặt trong vùng tối — hệ thống lặng lẽ trả "nằm sấp".

Bài đo 3 pha **đo được** false-PRONE (hiện ở cột "đoán SAI thành" của pha ngửa) nhưng **mù** với câu hỏi ngược: người nằm sấp thật có bắt đúng không?

Vì sao đáng 1 phút nằm thêm: luật này sẽ được kế thừa. Phase 06 closed-loop chống ngáy quyết nâng đầu giường dựa trên *"đang nằm ngửa"*. Nhãn ngửa/sấp sai = nâng nhầm lúc.

### 4.3 Fix mirror chưa commit — thứ tự làm việc quan trọng

Board đang chạy firmware dirty. Ngày 16/08 đã một lần nạp lại "từ HEAD sạch" để gỡ lỗi. Lặp lại chuyện đó **sau** khi đo → mirror quay về → quy ước dấu (trái dương / phải âm) đảo ngược → 5 lượt cũ thành rác, không có gì báo động.

→ **Commit firmware TRƯỚC khi đo.**

## 4.4 Hướng đặt camera — số đo đã có, khiếm khuyết đã biết

Bổ sung sau khi đọc kỹ report 16/08 mục "Hướng khung hình" (bỏ sót ở lần đọc đầu).

**Trục ngắm:** treo cao, chĩa thẳng xuống giường. Bài đo có nhãn 17/08 chạy với camera đã gắn. Câu "còn để trên bàn" trong report 16/08 là mô tả *trước* khi gắn, không còn đúng.

**Trục xoay — ràng buộc cứng:**

| Xoay trước suy luận | Phát hiện |
|---|---|
| 0° | 83% |
| **90°** | **99.7%** |
| 270° | **0%** |

Lệch 180° là **mất trắng**, không giảm dần. Với bố trí hiện tại `--rotate 90` (`ROTATE_90_COUNTERCLOCKWISE`) ⇒ trong ảnh thô, đầu người ở **mép phải** khung.

**Trục ngang — camera lệch khỏi giữa giường:**

| Pha | ngang, 0° | ngang, xoay 90° | dọc, 0° |
|---|---|---|---|
| nghiêng trái | 90% | 59% | **99%** |
| nghiêng phải | 11% | **25%** | **25%** |

Nghiêng phải đứng im 25% qua hai cấu hình khác hẳn nhau. Hướng khung không giải thích được; report 16/08 quy cho nguyên nhân vật lý (camera lệch bên giường, hoặc ánh sáng một bên) và đề xuất dời vào giữa rồi đo lại.

**Quyết định 18/08 (Hưng): giữ nguyên bố trí, dời camera làm sau.** Hệ quả phải chấp nhận: hàng "nghiêng phải" trong ma trận sẽ dựng trên ~25% số frame của pha đó — đọc như chỉ báo, không như tỉ lệ. Điều kiện này phải ghi kèm số đo ở bước 4, nếu không số vô nghĩa khi đọc lại.

## 5. Quyết định chốt phiên này

| # | Quyết định | Người quyết |
|---|---|---|
| 1 | Chọn hướng **A** — đóng vòng đo tư thế, chưa sang Phase 01 | Hưng 18/08 |
| 2 | Bài đo **4 pha**: ngửa / nghiêng trái / nghiêng phải / **nằm sấp**, mỗi pha 60s | Hưng 18/08 |
| 3 | **Luật dừng: ghi nhận, không chỉnh ngưỡng.** Lượt kiểm chứng là bản án. Trượt thì ghi vào docs là luật chưa đạt, dừng vòng, để lại cho Phase 05 | Hưng 18/08 |
| 4 | **Giữ nguyên bố trí camera hiện tại.** Không dời vào giữa giường vòng này — xem §4.4 và hệ quả kèm theo | Hưng 18/08 |
| 5 | **Ràng buộc lắp đặt (270° = 0%) để Phase 05 ghi**, không viết tài liệu phần cứng vòng này. Điều kiện đo vẫn ghi kèm số ở bước 4 | Hưng 18/08 |

Quyết định 3 có hệ quả: ghi chú `posture.py:52` ("nếu tầng 1 trượt, quay về `vai_thân`") **không được thực hiện trong vòng này**. Nó là đề xuất cho vòng sau, không phải nước đi tiếp theo. Giữ nguyên chữ trong file, nhưng vòng này không đụng.

## 6. Phạm vi A — 5 bước

1. **Commit trước khi đo.** `main.c` (fix mirror) + `posture.py` + `protocol.py` + `pose_poc.py` + 2 report untracked
2. **Thêm pha nằm sấp** vào `DEFAULT_PHASES` (`protocol.py:44`): `("nằm sấp", posture.PRONE, "NAM SAP", 60)` — đặt cuối, thành chuỗi lăn tự nhiên ngửa → trái → phải → sấp. Kèm ghi chú lý do thêm, sóng đôi với ghi chú lý do bỏ pha chăn
3. **Chốt ngưỡng, không đụng nữa.** Chạy `pose_poc.py --protocol` một lượt
4. **Ghi kết quả** vào `docs/sensor-characterization.md` §"Not measured yet" → mục *Full-body framing* đã chừa sẵn chỗ
5. **Giữ nguyên câu giới hạn** khi chuyển sang docs: một người, một bố trí camera, một phiên. Đủ thấy luật sai ở đâu, KHÔNG đủ công bố độ chính xác. Cả `posture.py` lẫn `protocol.py` đều đã tự viết câu này

## 7. Tiêu chí đóng vòng

- [ ] `git status` sạch, fix mirror nằm trong lịch sử
- [ ] `DEFAULT_PHASES` có 4 pha, tổng 240s
- [ ] Một lượt `--protocol` chạy hết, in đủ ma trận nhầm lẫn 4 khối
- [ ] Ngưỡng trong `posture.py` **không đổi** giữa lúc chạy và lúc ghi docs
- [ ] `docs/sensor-characterization.md` có số thật cho full-body framing + 4 tư thế, kèm câu giới hạn
- [ ] Số đo ghi kèm **điều kiện**: bố trí camera lệch bên, `--rotate 90`, tỉ lệ phát hiện từng pha
- [ ] `ruff check scripts/` pass

## 8. Ngoài scope vòng này

Phase 01 (cắm radar/piezo), camera IR, MediaPipe trên Jetson, `edge/vision/`, rPPG, ghi landmark ra đĩa (đụng H-25 — phải viết lại hazard trước khi viết code, không ngược lại).

## 9. Việc kế tiếp sau A

Hai việc hoãn có chủ đích, đã ghi để không rơi: **dời camera vào giữa giường rồi đo lại** (§4.4), và **ghi ràng buộc lắp đặt vào tài liệu phần cứng** (270° = 0% phát hiện).

**Hướng B — quay về Phase 01**, cắm LD2510B + piezo. Đó mới là đường tới Phase 02 (sản phẩm bán được đầu tiên). Theo brainstorm 14/08, radar+piezo cũng là công cụ đúng cho "phân loại tư thế cả đêm" — chức năng mà `posture.py` đang thử làm bằng vision.

Song song, không tốn công kỹ thuật: đòi Michael trần ngân sách BOM + duyệt 2 doc; đòi anh Khanh scope cơ khí. Ba thứ này chặn Phase 00 và đều nằm ở người khác.

## Câu hỏi tồn đọng

1. ~~Camera còn treo chĩa xuống giường không?~~ **Đã trả lời** — có, đã gắn từ 17/08; xem §4.4. Câu hỏi còn lại đã chuyển thành quyết định 4.
2. Ai cập nhật bảng rủi ro `phase-05` cho khớp quyết định 14/08 (tách 3 nhánh, loadcell đã bị cắt khỏi BOM) — làm ngay hay đợi Phase 05 khởi động? Câu này tồn từ report 14/08, chưa ai nhận.
3. Chức năng "khớp 3 mảng nâng" chạy khi người mới nằm xuống — phát hiện thời điểm đó bằng gì: radar presence, piezo, hay người dùng bấm nút? Chưa ai chốt. Tồn từ 14/08.
