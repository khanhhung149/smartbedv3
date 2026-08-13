Title    : Meet - xvk-oxqt-fod
Code     : xvk-oxqt-fod
Status   : delivered
Organizer: michael@chtlab.io
Attendees: []
Start    : 2026-07-13T05:59:20.578292+00:00

===== TRANSCRIPT (38455 chars) =====
## Session 2026-07-13 06:55:48 UTC

- Meet code: xvk-oxqt-fod
- Segments: 1
- Total duration: 52m 6s

## Segment 2026-07-13 06:55:48 UTC

- Meet code: xvk-oxqt-fod
- Duration: 52m 6s

## Chunk 1 (+0s)

[00:00:00] Michael Phan (Sơn): Ok, mời mọi người.
[00:02:00] Michael Phan (Sơn): À
[00:07:00] Michael Phan (Sơn): đầu tiên cái cái cái cái plan này thì sẽ sửa thêm ha.
[00:12:00] Người nói B: Dạ.
[00:12:00] Michael Phan (Sơn): Một số cái mình sẽ thay đổi. Đầu tiên về phần safety, mình sẽ dùng tất cả là dùng ESP32, không có dùng STM cho thống nhất. ESP32 thì có thể dùng các cái loại version khác nhau.
[00:27:00] Michael Phan (Sơn): 10 điểm này thì mình sẽ thay bằng ba mảnh thôi, ba mảnh là một mảnh ở trên đầu, một mảnh nhỏ ở dưới chân, một cái mảnh lên xuống. Cái cung độ thì nhỏ thôi, tốc độ thì chậm, à độ ồn thì phải thấp.
[00:42:00] Michael Phan (Sơn): Còn à à 10 điểm thì để sau ha.
[00:49:00] Michael Phan (Sơn): Ờ về AI với lại bộ não thì dùng con Jetson Orin đã có thiết bị đây rồi.
[00:58:00] Michael Phan (Sơn): À màn hình thì không có dùng màn hình 45 inch mà mình dùng cái iPad nhỏ hoặc là cái Android thôi, Android cho rẻ tiền. App thì bằng Flutter để có thể lên cả Android, iOS.
[01:09:00] Michael Phan (Sơn): Và phía sau thì deploy bằng K8s chứ không phải K3s. K3s thì nó nhỏ xíu, mini.
[01:16:00] Michael Phan (Sơn): À offline, ok.
[01:19:00] Michael Phan (Sơn): Bỏ hết mấy cái Coral này nè. Mình sẽ làm 10 à bảy phase.
[01:25:00] Michael Phan (Sơn): Đây là phase đầu tiên là các cảm biến bị gạch chéo hết.
[01:31:00] Michael Phan (Sơn): Đầu tiên là Max 30120, SPO2, cái này là phải chạm nè, cái này để sau á. Rồi hít áp thì à cũng để sau luôn.
[01:46:00] Michael Phan (Sơn): Nồng độ cồn thì cũng để sau.
[01:49:00] Michael Phan (Sơn): Cảm biến hiện diện giữ nè, load cell thì thay bằng cái Piezoelectric pad đó ha để.
[01:55:00] Người nói B: Dạ.
[01:55:00] Michael Phan (Sơn): À tính được status nè, nhịp thở, nhịp tim, nhiệt độ cơ thể.
[02:03:00] Michael Phan (Sơn): À nhiệt độ, độ ẩm môi trường giữ nè, mic định hướng thì dùng cái mic Quân vừa đưa ha, mic gọi là đa hướng chứ không phải định hướng. Mic này là mic đa hướng. Còn mic định hướng là cái mic cục dài.
[02:18:00] Michael Phan (Sơn): Đây, mic định hướng là mic mic này.
[02:24:00] Michael Phan (Sơn): Đây.
[02:28:00] Michael Phan (Sơn): Nó nó như y chang như cái mic karaoke của em.
[02:31:00] Người nói B: Dạ.
[02:36:00] Michael Phan (Sơn): Um.
[02:41:00] Michael Phan (Sơn): Cái này giữ nè. Ok. Tới phase 1.
[02:46:00] Michael Phan (Sơn): Phase 1 thì à mình sẽ làm tới phase 7.
[02:52:00] Michael Phan (Sơn): Không, mình làm tới phase 5 là mình release được rồi.
[02:58:00] Michael Phan (Sơn): URT giữ, trên đầu chiếu xuống. Biên độ Lidar các khoảng cách, ổn.
[03:06:00] Michael Phan (Sơn): Cái con LD2410B này nè.
[03:10:00] Michael Phan (Sơn): Nó đo được nhịp thở với lại nhịp tim luôn, nhưng mà nó nó gần đúng thôi. Để nó xác định và khoảng cách luôn.
[03:18:00] Michael Phan (Sơn): Load cell. Nhớ mấy cái thông số này nha, ví dụ người ta đi gần hay là đi gì đó. Nhưng mà nên nâng con này lên là 2510B đi.
[03:28:00] Michael Phan (Sơn): Tại vì con 2510B nó track được nhiều người cùng lúc và nó track được cái vị trí luôn. Còn con 2410 thì nó gọi là approximate distance thôi, gọi là gần đúng.
[03:45:00] Michael Phan (Sơn): Load cell là bỏ này thay bằng Piezoelectric nè, ST này là nhiệt độ độ ẩm nè.
[03:51:00] Michael Phan (Sơn): À cái này là cái gì? À cái này là camera nhiệt ha.
[03:56:00] Michael Phan (Sơn): Mở đâu. Sắp xếp mà lạ quá trời.
[04:07:00] Michael Phan (Sơn): À thằng này là camera nhiệt.
[04:14:00] Michael Phan (Sơn): Camera nhiệt. Thì đó, thì bản thân nhiệt độ đó em thấy nè rất là nhiều cái thằng nó đẩy về nhiệt độ cho mình. Nào là pad, cái này nọ, nhiệt độ này là nhiệt độ môi trường nè, nhiệt thân nhiệt trên bề mặt.
[04:27:00] Michael Phan (Sơn): Mic gắn đầu giường, cảm âm thanh, phần mềm.
[04:33:00] Michael Phan (Sơn): Tất cả là chạy trên Orange Pi, à lộn trên con Jetson Nano, nó là Linux ha. Làm một cái dashboard.
[04:43:00] Michael Phan (Sơn): Rồi làm những gì đó.
[04:46:00] Michael Phan (Sơn): Theo cái này. Phase 2 bắt đầu làm thuật toán nè.
[04:53:00] Michael Phan (Sơn): À thật ra tất cả của những cái này á mục tiêu của anh là gì? Mục tiêu của anh á đang muốn là thật ra mình không phải làm một sản phẩm để bán mà mình làm một cái framework.
[05:08:00] Michael Phan (Sơn): Trong đó có rất là nhiều cái thông số đầu vào và nhiều cái lệnh điều khiển đầu ra và mình sẽ open cái đó ra để về sau rồi người ta có thể tự phát triển thêm chức năng gì đó người ta gắn vô. Giống giống như cái kiểu App Store vậy đó.
[05:25:00] Người nói B: Dạ.
[05:26:00] Michael Phan (Sơn): Hiểu không? Thì mình cố gắng mình thu thập càng nhiều dữ liệu, có có thể có những cái mình sẽ không dùng, nhưng mà mình về sau rồi dùng người dạng developer người ta cần cái đó để người ta phát triển một cái chức năng gì đó trong cái giường của mình thì người ta vẫn dùng được.
[05:40:00] Michael Phan (Sơn): Thì collect hết data. À và hơn nữa là sao?
[05:45:00] Michael Phan (Sơn): Về sau anh sẽ cho AI vô để mà nó học cái thói quen dựa trên cái dữ liệu đó, cho nên càng nhiều dữ liệu nó càng hiểu thì nó sẽ điều khiển cả cái giường này bằng AI luôn. Sau sau này nó sẽ có một cái chế độ là autopilot, bấm một cái là AI tự lo hết. Cái nhà này anh cũng đang làm thử nghiệm vậy đó. Giờ đi đâu làm gì ra lệnh giọng nói là quá đơn giản rồi.
[06:07:00] Michael Phan (Sơn): Giờ anh có thể
[06:10:00] Michael Phan (Sơn): ví dụ như đây, anh ví dụ cho em xem.
[06:15:00] Michael Phan (Sơn): Hồi xưa chua và rất khó nha. Dĩ nhiên anh nói cũng cũng được rồi nhưng mà thử chat cho em coi. À hãy mở đèn vàng.
[06:30:00] Michael Phan (Sơn): Để mình biết nó có bị...
[06:33:00] Michael Phan (Sơn): Điều chỉnh nhiệt độ với lại... xuống còn
[07:01:00] Michael Phan (Sơn): Anh xài AI nhiều quá. Nó bị hit limit á. Anh xài ba gói max luôn mà nó kéo không nổi. Anh phải build mấy con này. Con này anh mua bên Trung Quốc. Con này cũng là một dự án của công ty hay lắm. Làm cái con này, đó, mở đèn chỉnh nhiệt độ đó thấy không?
[07:14:00] Người nói B: Dạ.
[07:14:00] Michael Phan (Sơn): Anh phải track nó bằng đây. Anh flash lại firmware của nó để track cái usage của mình trên con Claude với con này.
[07:26:00] Michael Phan (Sơn): Để biết còn xài bao nhiêu.
[07:28:00] Michael Phan (Sơn): Ừ. Hit limit thì tự động nó sẽ dừng, đổi qua account khác hoặc là chậm lại. Nói chung em dùng cái level của anh bây giờ chỉ có một cái duy nhất để cản em lại thôi là cái token.
[07:41:00] Michael Phan (Sơn): Mẹ mà em anh làm con này anh cho em coi cái clip này em muốn hoảng hồn chim án luôn.
[07:47:00] Michael Phan (Sơn): Anh đang học tiến sĩ.
[07:49:00] Người nói B: Dạ.
[07:49:00] Michael Phan (Sơn): Cái này cũng là một cái bài tập nhỏ.
[07:56:00] Michael Phan (Sơn): Group của anh.
[07:58:00] Michael Phan (Sơn): Anh đang học về AI.
[08:03:00] Michael Phan (Sơn): Đây.
[08:10:00] Michael Phan (Sơn): Mình thuyết trình mình cười với cả mày. Anh tự lấy mình ra làm ví dụ luôn. Nè. Anh thuyết trình về cái detection đó cho lớp về. Nói chung nhóm anh chọn là YoloNAS. Yolo em biết đúng không?
[08:24:00] Người nói B: Dạ.
[08:25:00] Michael Phan (Sơn): Ừ nhưng mà YoloNAS là cái Yolo rất nhỏ, mini thôi, chạy được trên edge device, chạy được trên ESP32 này nọ nó mới khó chứ.
[08:33:00] Michael Phan (Sơn): Đó thì anh demo cho nguyên lớp luôn mà quên bữa đó mặc áo ba lỗ, nguyên lớp cười quá trời luôn. Lại được điểm cao. Thầy lại thích.
[08:50:00] Michael Phan (Sơn): Anh chăm chút đến từng cái nào ha, ví dụ đây là cái
[08:58:00] Michael Phan (Sơn): anh nhìn nè, Yolo là gì? Là trả về cái box,
[09:08:00] Michael Phan (Sơn): trả về cái box giống như nãy cái hình em coi á, và cái label
[09:12:00] Michael Phan (Sơn): và cái điểm confidence score.
[09:15:00] Người nói B: Dạ.
[09:16:00] Michael Phan (Sơn): Thì anh đã đóng khung cái chữ YoloNAS là đánh chữ YoloNAS label, mẹ tao confident 100% phải không? Nói chung sâu xa từng tí một như vậy thầy cũng nhận ra, hiểu không?
[09:30:00] Michael Phan (Sơn): Rồi phải chạy thật, demo ra kết quả.
[09:36:00] Michael Phan (Sơn): Mà slide em thấy không? Làm tất cả từ trên xuống dưới là phải đúng mẫu, form rồi hình ảnh nè, ví dụ hình này style này thì xuống những cái hình khác nó cũng phải style đó. Hiểu không? Trừ cái hình chart này là kết quả thì bắt buộc phải là chụp cái hình kết quả thật, tại vì mày mày làm chế thì là đéo uy tín rồi.
[09:55:00] Michael Phan (Sơn): Anh cho em coi vậy chứ có 17 slide thôi mà tụi anh tốn một tháng trời mới làm.
[10:00:00] Michael Phan (Sơn): Nè, từ những cái hình ví dụ mình phải chuẩn chỉnh từng tí một, cái level quốc tế nó khó khăn vậy đó.
[10:08:00] Michael Phan (Sơn): Ok, để đây à.
[10:11:00] Michael Phan (Sơn): Mất lại.
[10:14:00] Michael Phan (Sơn): Ờ đó, mấy cái này đúng hết rồi. Tiếp tục. Thuật toán thì đơn giản. Thuật toán chắc là em mạnh nhất rồi đúng không? Thuật toán chắc là em là khá nhất rồi.
[10:28:00] Michael Phan (Sơn): Môi trường, nhiệt độ,
[10:31:00] Michael Phan (Sơn): đó nó có một cái dải LED ha, dải LED RGB. LED này thì bình thường mà anh điều khiển LED á anh sẽ dùng thằng WLED, em biết không?
[10:44:00] Người nói B: Dạ.
[10:49:00] Michael Phan (Sơn): Vô đây flash nó có cái, hình như nó có flash online luôn á. Bấm một cái, gắn chip vô cái, flash là xong.
[11:01:00] Michael Phan (Sơn): Xong em có thể điều khiển mọi thứ hoặc API em nối qua.
[11:05:00] Michael Phan (Sơn): Cái mạnh của thằng này là sao? Nó có một cái bộ xử lý sóng rất là tốt.
[11:11:00] Michael Phan (Sơn): Tại vì nếu mà em tự điều khiển bằng SP cũng được, nói chung cái này tùy em.
[11:18:00] Michael Phan (Sơn): À nhưng mà khi mà em muốn chuyển động mượt á thì cái thuật toán của mình không bao giờ bằng thuật toán mấy thằng này được, em biết mà đúng không? Ví dụ như em
[11:27:00] Michael Phan (Sơn): ví dụ như em muốn chuyển một từ màu này qua màu kia á, ở giữa là bảy màu, em cứ if thử coi nó nó vậy nè. Còn thằng này là nó sẽ... cái thuật toán của nó là gọi là bá đạo rồi, hiểu không? Thì em gọi, nói chung sau khi làm nhiều
[11:42:00] Michael Phan (Sơn): về nặng hay nhẹ hơn thì thằng này nặng hơn một chút nha. Này nặng hơn một chút, nhưng mà
[11:49:00] Michael Phan (Sơn): anh thấy nó nó chạy trong con này, con này là con gì? Con là con cái con nhỏ xíu này nè, con a
[11:55:00] Michael Phan (Sơn): 8266 1S em biết không?
[11:58:00] Người nói B: Dạ.
[11:59:00] Michael Phan (Sơn): Con nhỏ xíu vậy nó còn chạy được mà.
[12:03:00] Michael Phan (Sơn): 01B này nè nó còn chạy được mà.
[12:07:00] Michael Phan (Sơn): Đó. Thì à mình sẽ có một cái gì? Mình sẽ có một cái
[12:13:00] Michael Phan (Sơn): nó đừng có sợ nhiều nha, anh có list, anh có ấy rồi chút anh sẽ gửi lại cho em.
[12:19:00] Michael Phan (Sơn): Àm đầu tiên là nhiệt nhiệt độ nè.
[12:23:00] Michael Phan (Sơn): Máy lạnh máy lạnh monoblock, nó là monoblock đó. Em search cái chữ này nó sẽ ra nhiều lắm.
[12:31:00] Michael Phan (Sơn): Ví dụ như là
[12:34:00] Michael Phan (Sơn): monoblock air conditioner.
[12:42:00] Michael Phan (Sơn): Đó, nó là dạng này, một block.
[12:47:00] Michael Phan (Sơn): Nói chung xấu cũng được hết, nó làm sao như cái ốp hồi nãy trên cabin là đẹp. Nè, nhìn như như con cá nằm ở phía trên này nè.
[12:55:00] Michael Phan (Sơn): Rồi. Tiếp.
[12:58:00] Michael Phan (Sơn): À nhiệt thì vậy ha.
[13:00:00] Người nói B: Dạ.
[13:02:00] Michael Phan (Sơn): À ánh sáng thì có một dải LED thôi, một dải LED chạy vòng vòng, nói chung làm sao để cái sản phẩm nhìn nó từ xa là nó đẹp, có LED liếc đẹp. Gần thì nó có hiệu quả là người ta có thể là một cái ánh sáng dịu. Tại vì
[13:21:00] Michael Phan (Sơn): như em đọc á, riêng cái ánh sáng từ LED á cũng là một cái phương pháp trị liệu. Em có thấy mấy cái, em coi phim có thấy hay người ta đắp cái mặt nạ đó rồi bật bật lên cái nó đỏ lè đó.
[13:33:00] Michael Phan (Sơn): Nó là trị liệu da bằng ánh sáng. Mỗi cái ánh sáng, cái cái màu sắc khác nhau nó sẽ có cái bước sóng khác nhau. Bước sóng đó nó sẽ ảnh hưởng đến cái bước sóng của cái não mình, hiểu không? Thì bây giờ em cứ tưởng tượng này nè, chắc bên vật lý thì em cũng biết sơ sơ đúng không? Hóa học cũng biết sơ sơ.
[13:55:00] Michael Phan (Sơn): Thật ra nguyên tắc là gì? Nguyên tắc tất cả mọi thứ trên cái vũ trụ này đều có

## Chunk 2 (+840s)

[00:14:00] Michael Phan (Sơn): tạo bởi những cái hạt gọi là nguyên tử. Nguyên tử thì trong đó có gì? Là nhân, electron bao xung quanh. Có nghĩa là nó cứ chuyển động liên tục. Kể cả một cái bàn tay của mình vậy, thật ra tất cả mọi trong nó đang chuyển động liên tục liên tục liên tục tạo thành một cái logic gì đó.

[00:14:19] Michael Phan (Sơn): Thì theo nguyên tắc, cái gì chuyển động cũng tạo thành một cái sóng. Tại vì nó dịch chuyển từ bên đây qua bên kia, nó gây áp lực lên các hạt xung quanh nó tạo một cái sóng, sóng sung thích thôi, sóng sung kích lên gọi là vật chất.

[00:14:30] Người nói B: Dạ.

[00:14:32] Michael Phan (Sơn): Thì, thì con người mình cũng vậy. Cả cái cơ thể này hoạt động nó cũng tạo... Thật ra em để một cái đống, bây giờ nha, em em em để, em kéo một cái con quay, em thả vô một cái cái xô. Xong em kéo thêm con quay nữa thả vô cái xô.

[00:14:52] Michael Phan (Sơn): Thì tụi nó sẽ va nhau tùm lum tùm la các thứ các kiểu. Và tụi nó tạo gì? Tạo ra sóng.

[00:14:59] Người nói B: Dạ.

[00:15:00] Michael Phan (Sơn): Hiểu không? Vậy thì, giả sử anh có cái lịch sử sóng của tụi nó, hiểu không?

[00:15:05] Người nói B: Dạ.

[00:15:06] Michael Phan (Sơn): Anh có lịch sử sóng của tụi nó tạo ra như thế nào, kích thước tụi nó ra sao, cái cách thảy vô như thế nào, anh có thể hoàn toàn dịch lại được cái việc tụi nó va nhau như thế nào. Nghĩa là anh có thể dựng lại được mà anh đéo cần nhìn nó. Hiểu không? Anh chỉ cần nhìn sóng và anh nhìn cần điều kiện thôi là anh có thể dựng lại được.

[00:15:25] Người nói B: Dạ.

[00:15:26] Michael Phan (Sơn): Theo lý thuyết nha, anh đang nói lý thuyết, dĩ nhiên thực hành thực tế nó khác. Vậy thì sao? Vậy thì cái não mình nó cũng vậy, nó cũng hoạt động và riêng nó cũng tạo ra một cái tần số và nó kết hợp với cơ thể cũng tạo ra một tần số.

[00:15:39] Michael Phan (Sơn): Hiểu không? Miệng mình nói ra cũng là tần số. Miệng mình nói ra thật ra là cái dây thanh quản nó đập rộp rộp rộp rộp, tạo sóng xung kích ra ngoài, tạo thành sóng âm thanh qua cái vòm họng của mình là nó tạo ra các cái dạng âm thanh khác nhau.

[00:15:53] Michael Phan (Sơn): Vậy thì tại sao anh hiểu em? Tại vì anh với em cùng nói tiếng Việt. Anh nói tiếng Israel hay gì đó thì em sẽ đéo hiểu là tại sao? Tại vì trong cái đầu của mình hai anh em mình đã có sẵn một bộ từ điển.

[00:16:07] Người nói B: Dạ.

[00:16:07] Michael Phan (Sơn): Và hai anh em mình quy ước với nhau à cái ngôn từ này nó ý nghĩa như vậy. Vậy thì sao? Vậy thì máy móc nó cũng phát ra một cái sóng. Đúng không? Nó cái bản chất nó cũng là hoạt động mà phát ra sóng. Vậy thì con người mới đo được có vài cái loại sóng thôi: sóng Wi-Fi, sóng ánh sáng, sóng âm thanh. Nhưng mà nó có rất là nhiều loại sóng, như anh đo sóng Wi-Fi, đó, anh có thể bao trùm được. Thật ra anh chỉ đo một cái thông số đó là cái độ lớn, gọi là biên của nó thôi, A.

[00:16:39] Người nói B: Dạ.

[00:16:39] Michael Phan (Sơn): Còn nó có rất là nhiều cái thông số trong đó. Tần số rồi năng lượng, mức năng lượng, nhiều thứ. Vậy thì giả sử anh bỏ em vô một cái hộp, anh thu hết sóng trong người em, thu tuyệt đối luôn, và anh biết gọi là điều kiện đầu vào của em. Vậy thì rõ ràng anh đủ điều kiện để anh xác định được em đang nghĩ cái gì, em đang làm cái gì, em đang vận động cái gì, nếu mà anh có một bộ từ điển đủ tốt. Hiểu không?

[00:17:13] Người nói B: Dạ.

[00:17:14] Michael Phan (Sơn): Thì AI nó đang tiến tới bước đó rồi. Từ điển của nó là gì? Nó gom hết tất cả những cái trí tuệ, knowledge base của nhân loại lại nó làm từ điển của nó chứ có mẹ gì đâu. Vậy thì mình ứng dụng vậy thì rõ ràng ánh sáng nó phát ra nó cũng tạo cái sóng, nó tác động vô cái não mình. Thì lúc đó một cái tổ hợp, ví dụ như cái não mình là riêng nhưng mà não nằm trong đầu, đầu nằm trong cổ, cổ nằm trên cơ thể lại là một cái tổ hợp.

[00:17:42] Michael Phan (Sơn): Vậy thì khi cơ thể mình đang vậy đúng không? Mình gắn một cái thiết bị vô, phát sóng vô nữa thì mình amplify, nó gọi là cộng hưởng vô cái cái hệ sóng này của nó, tác động ngược. Hiểu không? Thì đó là cái cơ chế của con cái cái cái cái sóng ánh sáng cho nên ánh sáng rất là quan trọng.

[00:17:59] Michael Phan (Sơn): Tất cả mọi thứ trên cái vũ trụ này hoạt động được là nhờ ánh sáng. Kể cả như việc là anh nhìn thấy cái một cái gì đó sau lưng anh qua bức tường này đi thì cũng thì sẽ có một cách nào đó anh để cái gương, ánh sáng chạy vòng vòng tới. Anh biết được trời mưa thì là do ánh sáng yếu đi. Nói chung là tất cả mọi thứ dữ liệu mình truyền bây giờ cũng là ánh sáng hết, cho nên sóng ánh sáng rất là quan trọng.

[00:18:23] Michael Phan (Sơn): Về âm thanh thì mình sẽ làm một cặp loa. Loa bình thường thôi. Loa thì anh nhiều lắm nha. Loa thì xuống dưới hầm, vừa xuống hết cầu thang rẽ trái có một cái, có một cái cái khe vậy nè. Ở đây anh làm một nửa là anh làm ô ô để anh để đồ á. Thì em xuống dưới em lấy loa, anh nhiều loa lắm. Loa nhỏ, to đều có, loa xịn, loa dỏm có. Anh có mấy cái cục loa Bose với lại cục loa Marshall với lại cục loa…

[00:18:48] Michael Phan (Sơn): gì đó? Ultimate Ears Bell gì đó. Ultimate Ears Bell. Âm thanh ha, một cặp loa thôi. 2.0 để cho ta nghe nhạc với lại mình sẽ phát một số cái cái cái bài nhạc cụ thể trong máy có sẵn. Ví dụ như bài nhạc, nhạc lúc mà nó căng thẳng, lúc nó gì thì sẽ sẽ tùy. Mình sẽ lấy nhạc trên trên YouTube của thầy.

[00:19:20] Michael Phan (Sơn): Nguyên Minh Thiền Sư. Anh này cũng là chuyên gia hàng đầu về về y học giấc ngủ của Việt Nam á. Thì thầy sáng tác rất là nhiều bài hát có tiếng Anh, tiếng Pháp, tiếng Việt mà toàn là nhạc để để ngủ. Mà thật ra thầy cũng sáng tác toàn là bằng AI. Thầy ra nhiều nhạc lắm. Nhưng mà cũng hay chứ không phải là dở.

[00:19:53] Michael Phan (Sơn): Ha, mình sẽ lấy, ngoài lấy của thầy ra cho thầy vui. Thật ra cũng hiệu quả chứ không phải không mà mình cũng phải dựa trên cái gọi là cái background của thầy là cái nhạc này là người hàng đầu sáng tác ra chuyên trị về việc ngủ thì đéo ai hỏi. Còn không thì tại sao cái này ngủ ngon? Mày đố mày giải thích được, hiểu không? Nói chung người dùng là những người rất là ngu xuẩn. Mình phải, mình phải ngu hơn nó thì mới ra được cái sản phẩm mà nó dùng được.

[00:20:28] Michael Phan (Sơn): Rồi tiếp. Thông gió ha. Cho thêm cái cảm biến CO2 nếu cần. Nhưng mà anh nghĩ là sau này mới cần. Nhưng mà nên có một cái gọi là cái quạt hút nhỏ nhỏ.

[00:20:45] Người nói B: Dạ.

[00:20:46] Michael Phan (Sơn): Nhỏ thôi. Thậm chí 12 12 thôi được. Rồi quạt hút đó cũng sẽ có một cái lớp màng che để bình thường là nó không mở. Nhưng mà cái cảm biến đo cái lượng CO2 trên một mức nào đó thì nó đẩy, nó hút đẩy. Đó thì…

[00:21:08] Michael Phan (Sơn): Cái này, thật ra máy ion âm này cũng rất là rẻ, có cái cục nhỏ xíu thôi. Nếu mà có thì càng tốt. Cái này rất là hay ha. Cái này là làm ngủ ngon lắm, tại vì mình hay để cái dao với lại này nọ đó là mình để lấy cái ion. Buổi tối nó lạnh nó sẽ những cái hạt kim loại nào ở ngoài cái rìa nó sẽ bị rớt ra. Thì trong sắt nó gọi là nó ra mấy cái K+, Fe+ gì đó thì thật ra là ion âm chứ cái đéo gì đâu người ta để cái dao vô ngủ ngon là vậy chứ hiểu không? Ma cỏ gì.

[00:21:44] Michael Phan (Sơn): Rồi. Nè có một cái vấn đề nữa nè nha, cái máy lạnh này nó ồn. Cho nên mình phải tìm cái loại nào mà ít ồn.

[00:21:58] Michael Phan (Sơn): Biết sao không? Anh ghi âm để anh đưa luôn cho cái bạn tiếp theo đó. Để đỡ anh em mình phải ngồi lại buổi nữa.

[00:22:06] Michael Phan (Sơn): Phase 3, rồi tới phase 4 nè. Cơ khí. Cơ khí thì mình sẽ đổi lại thành ba cái mảng ha. Một mảng ở trên, một mảng ở giữa rộng và một mảng nhỏ ở dưới để nâng chân, mảng trên nâng đầu. Khung di chuyển thì nhỏ, tốc độ di chuyển thì chậm, độ ồn thì nó thấp.

[00:22:28] Michael Phan (Sơn): Logic thì phải có một cái gọi là một cái hệ quản trị riêng. Có nghĩa là một cái module quản trị riêng cho nó. Tất cả những cái khác chỉ giao tiếp qua cái module đó thôi. Và cái module đó gọi là handler đó đó.

[00:22:41] Người nói B: Dạ.

[00:22:42] Michael Phan (Sơn): Cái con handler đó là phải có một cái cơ chế safety trong đó. Ví dụ như nãy dữ liệu nhiều quá hoặc là chạy quá hoặc là này nọ nó phải tự động nó chặn hết mấy cái đó. Và nó… Anh nghe nè.

[00:23:14] Michael Phan (Sơn): Dạ dạ, đâu có mưa đâu anh. Không mưa. Dạ dạ. Dạ dạ dạ. Rồi. Với lại nữa là khi mà cái cơ cái cơ khí này nè, anh muốn là mình phải đo được, ví dụ như nó đang ở một cái cung rồi đó, không đến 100% đúng không? Thì nó đang ở vị trí số mấy. Ví dụ như cái cửa nhà mình.

[00:23:47] Michael Phan (Sơn): Này anh làm luôn. Nói chung khi cái bệnh của anh em kỹ thuật là cái quái què gì cũng thích tự làm. Hiểu không? Tại vì thật ra đéo có cái nào mà hài lòng được hết, hiểu không? Anh đã dùng rất là nhiều app anh mua của Trung Quốc, anh làm tất cả mọi thứ luôn cuối cùng anh chỉ đơn giản anh chỉ mong muốn là gì? Ba cái cửa: một cửa nhỏ, cửa bên trái, cửa bên phải nó hiện ra hết, đỡ phải bấm vô menu.

[00:24:12] Người nói B: Dạ.

[00:24:13] Michael Phan (Sơn): Tại vì đôi khi mình chỉ muốn mở nhỏ nhỏ một cái thôi để mình đi ra đi vô nhẹ nhàng thôi. Với lại cái cửa nhỏ này nè, nó phải link với hai cái thằng này. Tại vì cái cửa nhỏ này khi mở ra mà em, em mở cái cửa bên trái này một cái, nó kẹt vô đây luôn, nó kẹt vô luôn. Hiểu không? Thì cái cửa nhà tại vì mở là mở ra mà, hiểu không? Thì nó kẹt vô cái thanh sắt này. Thành ra á, khi nào mà thằng này đóng thì mấy thằng này mới được hoạt động. Còn khi thằng nào mở thì tự động kích, ngắt hết. Đó nó ngừng cái là mấy thằng này có bấm cũng không chạy được.

[00:24:45] Người nói B: Dạ.

[00:24:46] Michael Phan (Sơn): Muốn ấy thì phải vuốt, nói chung phải khó một chút thì mới chạy được. Rồi thứ hai nữa là anh muốn cái camera nó nằm ở trên cùng. Tại vì khi trên điện thoại á em vuốt á, nó mất cái camera mẹ đi, hiểu không? Thì mình bấm mà mình không thấy, mình lại phải vuốt lên camera. Cho nên là mấy cái app khác còn đéo có camera, còn phải qua hai ba app. Thì phải canh, thường thường shipper đến anh chỉ bấm xong anh bấm xong. Còn cái kia anh phải canh tùm lum hết.

[00:25:15] Michael Phan (Sơn): Hơn nữa là anh muốn ẩn camera cũng được mà, hiểu không? Hoặc là anh muốn coi camera khác, anh chỉ cần vuốt qua thôi. Đó, coi góc khác. Thấy không? Rồi muốn coi bốn cái một lúc thì sao? Đó. Rồi. Tại vì cái định, cái này nó mô tơ nó nặng á, nó kéo cái cái cửa này đâu cả tấn á, mấy trăm ký á cho nên tốn điện lắm. Mà mỗi lần mọi người mở hay mở cái cửa này chạy qua hết bên đây, thật ra mà thật ra mọi người chỉ đi có một chút à.

[00:25:54] Người nói B: Dạ.

[00:25:55] Michael Phan (Sơn): Thì anh mới chế lại là hai nút. Nút này anh làm mờ đi. Nút này là mở hết, nút này là mở nửa thôi, hiểu không? Đỡ tốn tiền điện.

[00:26:03] Michael Phan (Sơn): Vậy đó. Bấm vô coi lịch sử ai mở. Nói chung là đéo có chứ không phải là anh tự nhiên anh khùng anh tốn mẹ cả ngày trời anh… Mà chưa. Cái này chút xíu nữa xuống anh show cho em xem. Không biết là trên đây có coi lại hay không. Ở trên này anh mod lại hết hai cái cái cái cái mô tơ này luôn. Mod lại nguyên cái bo điều khiển của nó luôn. Anh cắm luôn cái bo điều khiển của anh vô. Thì anh có thể tắt, mở, ngắt nguồn nè, dừng, tất cả mọi thứ anh điều khiển được hết. Cộng với lại là gì biết không? Anh gắn thêm hai cái cái cái con này nè. Nó gọi là encoder. Em biết cái đó không?

[00:26:42] Người nói B: Dạ em biết.

[00:26:43] Michael Phan (Sơn): Mà không phải encoder bình thường. Anh cũng là thành viên vàng Shopee rồi chú phải hiểu rồi. Đây, đang mua cái cục nữa. Nè, có bánh xe mọi người. Kê vô, kê vô cái bánh răng của cái này. Thì khi nó chạy nó sẽ đẩy cái này, xong mình tuning nó thì nó sẽ biết được cái vị trí. Hồi xưa anh khổ lắm. Để biết được cái vị trí cửa đóng hay không tại tối mọi người hay mở ra rồi quên đóng á.

[00:27:19] Người nói B: Dạ.

[00:27:20] Michael Phan (Sơn): Đây chú coi anh phải làm cái gì đây. Anh phải dán… Tại vì anh lấy cái cái khung này để anh detect, anh dùng AI. Anh detect mở hay đóng hay vị trí nào được lắm, ngon lắm. Anh detect theo cái đường thẳng vuông góc xuống cái horizon này. Nhưng mà có hai vấn đề xảy ra. Một, là con đĩ này nó cũng là thanh thẳng, hiểu không? A không, chưa, câu chuyện này chưa đến. Thì cái này ban đêm á, đụ nó tối thui. Nó không thấy gì hết. Cái cái hồng ngoại của thằng này thì màu giống nhau hết, đụ không nhận ra.

## Chunk 3 (+1680s)

[00:28:00] Michael Phan (Sơn): Thế xong anh phải mua hai miếng băng keo gọi là phản quang á.
[00:28:02] Người nói B: Dạ.
[00:28:03] Michael Phan (Sơn): Anh dán vào đây, dán vào đây xong rồi detect là detect là thêm phải có cái cột thẳng màu trắng. Thì đụ mẹ buổi sáng cái cái thằng này cũng cột thẳng màu trắng mà nó cũng vuông góc thẳng y chang thằng này. Nói chung là nó anh đã tối ưu mọi cách, hiểu không?
[00:28:19] Michael Phan (Sơn): Mà cái góc này đéo xử lý được. Cuối cùng đụ má chơi cơ luôn. Chơi cơ mẹ đi, còn gắn con encoder ở đây mẹ đo chính xác. À nhưng mà có một cái vấn đề là vậy nè.
[00:28:30] Michael Phan (Sơn): Anh giới thiệu cho em thật ra không phải để khoe khoang gì đâu mà để để em thấy là từ một, từ một cái người có thể là chuyên môn anh không phải là những cái này nhưng mà anh vẫn giải quyết được cái nhu cầu của anh đúng với cái mong muốn của mình bằng AI.
[00:28:46] Michael Phan (Sơn): Nhá. Thật ra cái này vậy thôi chứ nó phức tạp lắm em ạ. Nó phải đồng bộ RTSP, nó phải MQTT rồi nó nhiều thứ. Ví dụ, cái encoder nó sẽ có một cái lỗi là vậy nè, lâu lâu nó bị lạch.
[00:28:59] Michael Phan (Sơn): Biết mà đúng không? Có thể là trơn trượt hoặc cái gì đó.
[00:29:04] Người nói B: Dạ.
[00:29:05] Michael Phan (Sơn): Thì phải làm một cái calibrate. Em bấm hết ra ngoài, em lưu lại vị trí, em bấm hết vô trong, em lưu lại vị trí.
[00:29:15] Michael Phan (Sơn): Xong thằng em anh, nói chung không phải thằng em, cũng một đứa nhân viên trước đây cũng làm ở ngoài, hỏi xong vô đây cũng ở với anh mấy ngày thì nó gợi ý là gắn thêm hai cái công tắc hai bên nữa. Cái công tắc hành trình á, đến là nó nhấp một cái thì nó tự động nó cân luôn. Nhưng mà đụ mẹ anh, anh đã lỡ gắn vô rồi, mỗi lần gắn cái này nó phức tạp, leo trèo rồi nó khoan biếc rồi khoan đục rồi, anh còn phải in 3D vỏ hộp nó đầy đủ hết rồi, giờ gắn thêm nó phức tạp quá.
[00:29:42] Michael Phan (Sơn): Mà anh thấy ủa, thằng này nó đã, bản thân nó đã có hai cái gọi là hai cái giới hạn. Nó thì không phải dùng công tắc hành trình mà nó dùng cảm biến từ trường. Có nghĩa là nó gắn hai cục nam châm đây nè, gắn cái cảm biến đi tới đây kịch, dừng. Thì ban đầu anh định là thôi nối con mẹ ra, câu thêm hai giây nữa lấy luôn cái tín hiệu này, hiểu không? Nhưng mà mới phát hiện ra á là nó dừng ở đây nhưng mà cái mút ở đằng kia thì sao? Là phải nối dây dài ra đằng kia hay sao? Mà cái cửa là nó di chuyển, hiểu không? Nói chung là bế tắc.
[00:30:17] Michael Phan (Sơn): Thì anh mới có một cách là anh dùng thuật toán. Anh kể với em một tiêu câu chuyện này cuối cùng là cái chữ này nè, chữ thuật toán. Đó là quan trọng là trí tuệ thôi em. Ủa, tới đó nó vẫn dừng. Tới đây nó vẫn dừng, nó có cơ chế an toàn rồi thì bây giờ anh thuật toán của anh như sau.
[00:30:35] Michael Phan (Sơn): Thuật toán của anh là nếu mà nó đang chạy á, mà nó tới cái vị trí gần đầu mút, chỉ còn có nhỏ hơn 15% và gần đầu mút này nhỏ hơn 15%. Nói chung gần hai đầu mút nhỏ hơn 15%. Và không phải người dừng, à người dùng ra lệnh dừng, mà nó tự dừng. Vậy thì có nghĩa là nó đã dừng cái điểm giới hạn của nó thì tự động lấy cái điểm đó, sync vô luôn.
[00:31:05] Người nói B: Dạ.
[00:31:06] Michael Phan (Sơn): Thì anh đâu calibrate lại.
[00:31:07] Người nói B: Dạ.
[00:31:07] Michael Phan (Sơn): Thì anh không cần calibrate, anh cũng không cần mua công tắc luôn. Hiểu không? Có nghĩa là thuật toán mình có thể giải quyết được. Dĩ nhiên, lâu lâu nó vẫn lạch một 2% nhưng mà cứ có người bấm một cái là nó hết.
[00:31:28] Michael Phan (Sơn): Nè, anh còn đo điện áp của gia đình anh nè, ai xài cái gì, thiết bị nào, bao nhiêu trong nhà, tầng nào, công suất sao là anh biết hết, năng lượng mặt trời vô ra bao nhiêu, pin của từng thứ.
[00:31:44] Michael Phan (Sơn): Mực nước mưa. Nè, riêng MQTT con server của anh nó nhiêu đây thiết bị.
[00:31:51] Michael Phan (Sơn): Thấy không? Nói chung là tụi nhà này đều hiểu hết. Mà anh cho AI làm hết. Nhưng mà AI nó hay cái chỗ là vậy nè. Ví dụ như hồi xưa là mình phải dụ turn off the light, turn on the light.
[00:32:14] Người nói B: Dạ dạ.
[00:32:15] Michael Phan (Sơn): Còn bây giờ ví dụ như anh nói là sáng quá rồi. Ví dụ như anh nói hai câu đi ha, ví dụ anh nói là sáng quá và hơi nóng. Ví dụ vậy đi. Để nó hiểu, để là gì? Cái intent là cái ý định của mình dựa trên cái context là toàn bộ cái gì nãy giờ nó nói, nó với mình trao đổi. Ví dụ như anh nói sáng quá, anh đâu có kêu tắt đèn đâu. Anh cũng không kêu, giảm máy lạnh, à tăng máy lạnh. Em xem nè.
[00:32:45] Michael Phan (Sơn): Nè, máy lạnh lên 25 độ rồi nè. Đèn vàng là công tắc on/off, không chuyển được độ sáng nên tôi đổi sang backlight.
[00:32:55] Michael Phan (Sơn): Đó. Hiểu không? Có nghĩa là nó hiểu cái intent.
[00:32:59] Người nói B: Dạ.
[00:32:59] Michael Phan (Sơn): Vậy thì sau này cái giường của mình cũng y chang như vậy. Hiểu không? Anh, tất cả những cái này không phải là anh chơi mà anh đang test cho em luôn á. Hiểu không? Anh thử trước.
[00:33:10] Người nói B: Dạ.
[00:33:11] Michael Phan (Sơn): Để em tới cái đoạn đó là em dùng luôn cái bộ anh đã test sẵn rồi. Còn mẹ em mò được tới đây là rất là công phu đó em ạ. Và cái này anh phải truyền lại cho vài thằng. Chứ không, cái này nó sẽ mai một, hiểu không? Để để AI mà nó hiểu nó gọi là nó nó hiểu được cái gọi là là cái pattern hoạt động rất là khó.
[00:33:38] Michael Phan (Sơn): Nó phải fine-tuning, nó phải RAG rất là nhiều thứ trong đó. Nhưng mà dĩ nhiên từ từ anh cho em làm hết. Nói chung cái dự án này anh sẽ hạn chế nhúng tay vô. Hiểu không? Tại vì bên nước ngoài nó có cái từ porn á, là giống như phim sex á. Là em coi em em cảm giác là em được làm rồi nhưng mà thật ra em chưa biết mẹ gì hết á. Hiểu không? Thì cái chữ porn tiếng Việt dịch ra hơi tục tiểu nhưng mà ở nước ngoài nó là ví dụ như porn world, porn world là mấy cái hình ảnh đẹp của thế giới đó, porn landscape, hiểu không?
[00:34:10] Michael Phan (Sơn): Nghĩa là mình nhìn cái cảnh đó mình mình thấy nó sướng quá, nó đẹp quá, mình cảm giác mình đang tới đó rồi nhưng mà thật ra không có gì hết. Không đọng lại gì hết. TikTok nó cũng vậy. Thì anh muốn em phải tự làm hết. Anh sẽ hỗ trợ, anh sẽ cung cấp đầy đủ tài nguyên và hướng dẫn em cách làm nhưng mà em phải tự làm hết. Tại vì anh không còn nhiều thời gian.
[00:34:32] Michael Phan (Sơn): Tại vì thêm vài tuổi nữa là muốn nói cho thằng khác cũng nó rất là mệt, hiểu không? Cũng quên hết mẹ rồi. Cho nên anh phải trong vòng khoảng 4, 5 năm nữa thì anh phải đẩy hết cái này cho anh nhẹ đầu. Tất cả phải có bốn năm thằng đệ làm được y chang như mình thì mới okay, hiểu không? Đó. Thì người dùng người ta sẽ ở hơi lạnh một chút.
[00:34:57] Người nói B: Dạ.
[00:34:58] Michael Phan (Sơn): Ờ hơi nóng một chút. Nhưng mà nếu dùng cái đèn...
[00:35:01] Người nói B: Kiểu như nó chạy được.
[00:35:02] Michael Phan (Sơn): À đúng rồi đúng rồi đúng rồi.
[00:35:03] Người nói B: Dạ.
[00:35:03] Michael Phan (Sơn): Và cái đèn này nó có chỉnh được độ sáng nha. Cái con nó sẽ chỉnh được gọi là cái pitch, pitch, pitch power current á thì nó sẽ tăng độ sáng lên, tăng màu sắc. Nói chung là mấy cái pattern đó khi làm tới mình sẽ dùng những cái có sẵn, đã chứng minh khoa học rồi chứ mình không có tự chế ra tùm lum la la đâu.
[00:35:23] Michael Phan (Sơn): Ờ đó. Ờ kể chuyện đi hoặc là đặt tin tức hoặc là đổi bài hát. Hiểu không? Mấy cái đó mình sẽ làm functional xong mình cho con này gọi là intent call function thì lúc đó em sẽ được anh hướng dẫn cho em làm một cái gọi là một cái app AI hoàn chỉnh. Nó có gọi là functional agentic AI. Hiểu không? Thì trước đây anh sẽ dùng cái bộ gọi là Home Assistant. Tại vì nó có, nó quản lý được nhiều với lại nó có sẵn nhiều. Nhưng mà sắp tới anh muốn á, Home Assistant thì có một cái rất là mạnh đó là Node-RED.
[00:36:01] Người nói B: Dạ.
[00:36:01] Michael Phan (Sơn): Nó automation tự động mình có thể kéo thả này nọ, tưới cây, chuông báo động. Nói chung là mình thích gì mình kéo thả. Nhưng mà sau khi có AI và làm nhiều hệ thống thì anh thấy cái này là sẽ thành cản trở.
[00:36:17] Người nói B: Dạ.
[00:36:18] Michael Phan (Sơn): Hiểu không? Mình sẽ build một cái hệ thống riêng, quản lý riêng. Tự động hóa thì cũng sẽ dựa trên AI chứ không dựa trên người kéo nữa. Và sau này anh muốn á, cái này thì hơi xa vời, nhưng mà moonshot mà. Bắn một phát phải lên tới mặt trăng chứ, đúng không? Mẹ đã lỡ bắn thì phải nói tao bắn tới mặt trăng, bay tới đâu tới. Ờ anh muốn xây dựng một cái platform mở để những cái tự động, thật ra như cái skill của AI bây giờ cũng là một cái file text thôi có con mẹ gì.
[00:36:57] Michael Phan (Sơn): Hiểu không? Thì về sau mình cũng sẽ đi, mình sẽ public khoảng tầm 100 cái template mẫu. Ví dụ như là khó ngủ nè, đang đau đầu hoặc là buổi sáng thức dậy hoặc là mới vô giấc thì như thế nào. Hiểu không? Nói chung là sẽ mình sẽ public một khoảng 100 cái. Nhưng mà mình sẽ đi đưa ra cái gọi là cái template cho người dùng có thể up lên. Hiểu không? Người dùng có thể public, developer có thể public lên cái GitHub đó.
[00:37:28] Michael Phan (Sơn): Và trong cái iPad thí dụ như mình thích cái nào mình bấm một cái, nó load về, nó có chức năng đó. Hiểu ý không?
[00:37:35] Người nói B: Dạ.
[00:37:36] Michael Phan (Sơn): Tạo thành một cái cộng đồng. Ví dụ như anh, ok, anh down cái template của em về và anh anh dùng AI hoặc cái gì đó anh xài ra một cái template khác. Ví dụ như em có một cái template là buổi sáng thức dậy cho người khoảng 25 tuổi đến 30 tuổi. Còn anh không phải anh già rồi anh 60 tuổi, thì ba ví dụ ba anh 75 tuổi đi, thì anh phải mua cái giường cho ổng rồi anh phải load những cái, anh phải sửa lại rồi người già thì phải như thế nào nào. Nói chung cái template này không phải là lập trình. Template chữ. Và con AI nó sẽ phải convert hết cái đó qua cái logic của mình.
[00:38:13] Michael Phan (Sơn): Hiểu không?
[00:38:13] Người nói B: Dạ.
[00:38:14] Michael Phan (Sơn): Đó. Dĩ nhiên mình cũng có cái template của template để cái để sau khi nó làm vô cái template nó đẩy vô một cái là mình lại lọc lại phát nữa. Hiểu không? Nó gọi là long-term memory với lại short-term memory. Hiểu không? Rồi. Những cái này á là anh làm hết rồi đó nha. Anh test hết ở đâu đó cũng khoảng ngày cái khác. Chứ anh đã loại hết những cái gọi là impossible rồi.
[00:38:49] Michael Phan (Sơn): Ờ cái cái cơ khí thì mình sẽ làm việc với anh Khanh ha.
[00:38:53] Người nói B: Dạ.
[00:38:54] Michael Phan (Sơn): Rồi. Ờ camera, camera thì đơn giản thôi. Ờ... gắn camera lên. Đưa về cái khung xương của người, tư thế nằm, đang lạng quạng, nghiêng trái, nghiêng phải, cong người, nằm sấp, co chân, dang tay, cái gì nói chung một số cái nào mà em detect được thì em cứ để vô.
[00:39:26] Michael Phan (Sơn): anh có một cái thằng khá là hay. Hình như anh để trong cái mấy cái thuật toán nó gọi là gì ta? À pose vision. À AI deep learning. Nói chung nhiều lắm em ạ.
[00:39:51] Người nói B: Dạ.
[00:39:52] Michael Phan (Sơn): Mà em phải... em phải, phải xử lý được trên GPU nữa.
[00:40:15] Michael Phan (Sơn): Ờ MediaPipe, quên.
[00:40:19] Michael Phan (Sơn): Pose. Đây. Nói chung dễ ờm à. Hiểu không? Anh làm có một hai ba câu lệnh là nó chạy cái module này xong nạp cái source camera vô là nó ra thôi. Nó ra cái này. Thì từ cái này em phải dùng AI để em tính toán được cái khoảng cách giữa các điểm. Nó ra một cái matrix, ma trận. Từ cái ma trận đó em mới xác định được là cái tư thế ngủ của người ta. Nói chung cũng cái này trên mạng đụ má 20 năm rồi. Không phải mới đâu nha.
[00:41:00] Người nói B: Dạ.
[00:41:01] Michael Phan (Sơn): Thẳng nè, nghiêng nè, úp nè. Nằm nghiêng nửa nè. Rồi. Sau khi hết cái này rồi á thì mình sẽ hoàn thành một cái app và profile. Xong cái này là mình prototype. Còn cái này nữa thì từ từ mình tính nhá.
[00:41:26] Michael Phan (Sơn): (silence)
[00:41:39] Michael Phan (Sơn): Làm hoàn toàn bằng AI. Cái hồi nãy á, có thể dùng terminal hoặc là dùng cái app, nó cũng có app luôn, No-code.
[00:41:51] Michael Phan (Sơn): Ha? Ok.
[00:41:53] Michael Phan (Sơn): Đưa đủ chưa ta? Cái này không cần đâu nè. Cái này với cái này với cái này là đủ rồi đúng không?
[00:41:57] Người nói B: Dạ, nãy anh đưa ba cái.
[00:41:59] Michael Phan (Sơn): Không.

## Chunk 4 (+2520s)

[00:00:00] Michael Phan (Sơn): cảm biến, à, phát ra remote, cảm biến hiện diện.
[00:07:54] Michael Phan (Sơn): Mic.
[00:10:07] Michael Phan (Sơn): Anh tính thu thêm tiếng nữa, phân tích coi người ta đang ngủ hay không.
[00:16:47] Michael Phan (Sơn): Nhá.
[00:22:98] Michael Phan (Sơn): Cần cái nguồn không? Cần dây nguồn không?
[00:24:908] Người nói A: Dạ không.
[00:25:528] Michael Phan (Sơn): Hả?
[00:27:148] Người nói A: Để em check ra hàng em mua thêm theo dây điện.
[00:31:708] Michael Phan (Sơn): Đang qua đây lấy. Thích cái gì qua đây lấy. Dây nguồn trên bàn.
[00:37:628] Michael Phan (Sơn): Dây nguồn đúng không?
[02:08:953] Michael Phan (Sơn): Như nguồn em nói với lap được không ta?
[02:11:153] Người nói A: Được. Anh với lại có yếu không anh?
[02:13:953] Michael Phan (Sơn): À không biết.
[02:16:323] Người nói A: Em sợ yếu nó bắt đầu kêu.
[02:18:223] Michael Phan (Sơn): Em không em không có nói nguồn nhé. Thật ra phải có cái... Nói chung kinh nghiệm của anh là đôi khi anh vì cái vụ áp yếu của laptop là anh loay hoay miệt mài cuối cùng... Dạ.
[02:31:733] Michael Phan (Sơn): Đây.
[02:33:533] Michael Phan (Sơn): Mà hai cái phòng nó điên. Cho nên là kinh nghiệm của anh là cứ cấp nguồn riêng.
[02:40:483] Michael Phan (Sơn): Dạ.
[02:41:693] Michael Phan (Sơn): À em biết á cái, mấy cái mà trục trặc liên quan tới điện đóm đồ nó khó diễn tả lắm. Hiểu không?
[02:48:983] Người nói A: Dạ.
[02:49:503] Michael Phan (Sơn): Không biết được khi nào nó bị nữa. Nó cũng random lắm.
[02:55:403] Michael Phan (Sơn): Ok, vậy thì à,
[03:00:603] Michael Phan (Sơn): mạch hàn hiết cần cái gì thì qua đây lấy, ha?
[03:04:133] Người nói A: Dạ.
[03:05:743] Michael Phan (Sơn): Đây, cho em, thôi anh đưa luôn cho em một cái bộ.
[04:42:075] Michael Phan (Sơn): Cần gì thì gõ cửa lấy nha.
[04:45:905] Người nói A: Dạ.

