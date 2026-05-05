<div class="article-body prose prose-lg dark:prose-invert max-w-none">

  <p>
    Giấc ngủ là một trong những quá trình sinh học phức tạp nhất mà con người thực hiện mỗi đêm, nhưng trong phần lớn lịch sử lại là hành vi ít được quan sát nhất. Bạn nhắm mắt, mất ý thức, và tám giờ sau thức dậy — hầu như không có thông tin đáng tin cậy nào về điều gì đã thực sự xảy ra ở giữa. Khoảng trống thông tin đó đang kết thúc. Trí tuệ nhân tạo kết hợp với thế hệ cảm biến môi trường xung quanh và dưới đệm mới đang mang đến cho các bác sĩ lâm sàng, nhà nghiên cứu và người bình thường một cửa sổ nhìn vào giấc ngủ mà năm năm trước chưa tồn tại.
  </p>

  <h2>Trước AI: Chúng Ta Đo Được Gì</h2>
  <p>
    Trước khi học máy bước vào phòng ngủ, về cơ bản có hai hướng đánh giá giấc ngủ. Tiêu chuẩn vàng là Polysomnography (PSG) — nghiên cứu qua đêm tại bệnh viện gắn điện cực lên da đầu, mặt, ngực và chân để theo dõi đồng thời sóng não (EEG), chuyển động mắt (EOG), hoạt động cơ (EMG), nhịp tim, độ bão hòa oxy và nỗ lực hô hấp. PSG toàn diện và chính xác, nhưng gần như không thể tiếp cận với bất kỳ ai chưa có triệu chứng đủ nghiêm trọng để được giới thiệu, chờ nhiều tháng lấy lịch phòng ngủ, và sẵn sàng ngủ trong môi trường lâm sàng.
  </p>
  <p>
    Hướng thứ hai là thiết bị đeo tiêu dùng — máy theo dõi hoạt động và đồng hồ thông minh suy luận giấc ngủ từ gia tốc kế cổ tay. Những thiết bị này tiện lợi và rẻ, nhưng độ tin cậy phát hiện giai đoạn ngủ nổi tiếng là không đáng tin. Một nghiên cứu năm 2019 đăng trên <em>npj Digital Medicine</em> cho thấy các thiết bị đeo cổ tay tiêu dùng chỉ đồng thuận với PSG trong phân loại giai đoạn ngủ khoảng 65–70%, và đặc biệt kém trong việc phân biệt giấc ngủ nhẹ với giấc ngủ sâu. Chúng đo chuyển động như một chỉ số thay thế cho giấc ngủ, không phải sinh lý học cơ bản.
  </p>
  <p>
    Giữa hai cực này — phòng thí nghiệm toàn diện và vòng đeo tay không chính xác — hầu như không có gì. Xét nghiệm giấc ngủ tại nhà cho chứng ngưng thở tồn tại, nhưng chỉ ghi nhận dữ liệu hô hấp, không phải kiến trúc giấc ngủ đầy đủ. Vùng trung gian rộng lớn của theo dõi giấc ngủ hàng ngày liên tục, phi lâm sàng thực tế không được lấp đầy.
  </p>

  <figure class="article-figure">
    <img src="/generated/news-how-ai-revolutionizes-sleep-monitoring-inline-1.png" alt="Tấm pad giám sát giấc ngủ mỏng bên dưới đệm, với dữ liệu được hiển thị như những tia sáng" loading="lazy" />
    <figcaption>Cảm biến giấc ngủ môi trường hiện đại có thể thu nhận tín hiệu tim và hô hấp qua vải đệm mà không cần thiết bị đeo nào. AI nằm ở lớp xử lý tín hiệu phía trên.</figcaption>
  </figure>

  <h2>Sự Thay Đổi Năm Năm: Điều Gì Đã Thay Đổi Và Tại Sao</h2>
  <p>
    Ba phát triển hội tụ trong năm năm qua đã lấp đầy khoảng cách đó một cách đáng kể.
  </p>
  <p>
    <strong>Thứ nhất, thu nhỏ cảm biến và tăng độ nhạy.</strong> Cảm biến piezoelectric và strain-gauge trở nên đủ nhỏ và nhạy để phát hiện các vi rung động do hô hấp và tim co bóp cơ học (lực cơ học của nhịp đập tim truyền qua cơ thể đến bất kỳ bề mặt đỡ nào) xuyên qua vài cm vật liệu đệm. Tín hiệu Ballistocardiographic (BCG) này đã được biết trong nghiên cứu lâm sàng từ những năm 1930, nhưng trích xuất nó một cách đáng tin cậy từ bề mặt ngủ trong môi trường gia đình thực tế là một thách thức kỹ thuật chỉ trở nên khả thi với cảm biến MEMS hiện đại và điện tử nhiễu thấp.
  </p>
  <p>
    <strong>Thứ hai, điện toán đám mây và biên.</strong> Tín hiệu BCG thô rất nhiễu. Các nhiễu chuyển động, chuyển động của người ngủ cùng, ghép nối hô hấp và rung động môi trường đều làm ô nhiễm tín hiệu tim. Làm sạch tín hiệu này theo thời gian thực đòi hỏi tính toán đáng kể. Năm năm trước, tính toán đó ở trên đám mây, gây độ trễ và cần kết nối liên tục. Ngày nay, các đơn vị xử lý thần kinh chuyên dụng trên chip biên tiêu thụ ít điện có thể chạy các thuật toán làm sạch tín hiệu và trích xuất đặc trưng cục bộ với độ trễ dưới một giây. Sự chuyển dịch sang suy luận biên này không chỉ nhanh hơn mà còn là cải tiến cơ bản về quyền riêng tư.
  </p>
  <p>
    <strong>Thứ ba, và quan trọng nhất, dữ liệu huấn luyện theo quy mô.</strong> Nút thắt cổ chai trong AI giấc ngủ không bao giờ là thuật toán — mà là dữ liệu có nhãn. Nhóm nghiên cứu của SleepTech, xây dựng trên hơn một thập kỷ hợp tác lâm sàng với các phòng thí nghiệm giấc ngủ đại học trên khắp Nhật Bản, Hàn Quốc và Đông Nam Á từ khi thành lập công ty tại Osaka năm 2012, đã tích lũy một trong những bộ dữ liệu huấn luyện BCG/PSG ghép cặp lớn nhất bên ngoài nghiên cứu bệnh viện học thuật. Các mô hình được huấn luyện trên kho dữ liệu này có thể xác định các giai đoạn ngủ — Thức, N1, N2, N3 (sóng chậm) và REM — với độ nhạy tiếp cận PSG ở người ngủ bình thường, mà không cần một điện cực nào trên cơ thể.
  </p>

  <h2>Điều AI Thấy Mà Con Người Bỏ Lỡ</h2>
  <p>
    Khía cạnh chuyển đổi nhất của phân tích giấc ngủ AI không phải là nó thay thế phán đoán của con người. Mà là nó hoạt động liên tục, ở độ phân giải thời gian mà không người quan sát nào có thể duy trì, và trên các chiều biến động vượt quá nhận thức không được hỗ trợ.
  </p>
  <p>
    Hãy xem xét phân tích khoảng tim. Trái tim người không đập đều như máy đếm nhịp; khoảng cách giữa các nhịp đập thay đổi theo mili giây theo các mẫu mã hóa mô tả phong phú về trạng thái hệ thần kinh tự chủ. Biến thiên nhịp tim (HRV) — đặc trưng thống kê của các khoảng giữa nhịp đó — đã được nghiên cứu như một chỉ số sức khỏe hơn bốn mươi năm. Tuy nhiên, tính toán HRV có ý nghĩa từ tín hiệu cảm biến môi trường nhiễu, qua cả đêm, tính đến thay đổi tư thế, các lần thức giấc và chuyển tiếp giai đoạn ngủ, là vấn đề đòi hỏi kỹ thuật đặc trưng và nhận dạng mẫu được học mà chỉ mạng thần kinh sâu mới xử lý tốt.
  </p>
  <p>
    Tương tự, phân tích mẫu hô hấp. Hơi thở bình thường trong khi ngủ không đồng đều. Nó tăng tốc và sâu hơn trong REM. Chậm lại trong N3. Có thể cho thấy sự phân cụm tuần hoàn ở những người có rối loạn thở khi ngủ nhẹ. Các mô hình AI được huấn luyện trên dữ liệu hô hấp có nhãn có thể phát hiện chữ ký cử động chi tuần hoàn, xác định mẫu hô hấp crescendo-decrescendo đặc trưng của thở Cheyne-Stokes, và đánh dấu sự kéo dài khoảng cách giữa hơi thở trước khi xảy ra sự kiện ngưng thở — thường 30 đến 90 giây trước khi sự kiện trở nên có ý nghĩa lâm sàng.
  </p>

  <blockquote>
    <p>"Cảm biến không mệt mỏi. Nó không mất tập trung lúc 3 giờ sáng. Nó không bối cảnh hóa những gì thấy với các giả định của hôm qua. Nó chỉ đo, mỗi đêm, với cùng độ chính xác."</p>
    <footer>— TS. Yuki Tanaka, Viện Nghiên cứu Giấc ngủ Osaka</footer>
  </blockquote>

  <h2>Phân Loại Giai Đoạn Ngủ: Học Sâu Hoạt Động Như Thế Nào</h2>
  <p>
    Phân loại giai đoạn ngủ hiện đại nhất từ cảm biến không tiếp xúc sử dụng các kiến trúc tích chập-hồi quy xử lý các đoạn cửa sổ của sóng tim và hô hấp đã được làm sạch, trích xuất các đặc trưng miền tần số (qua FFT hoặc bộ lọc được học), sau đó áp dụng mô hình chuỗi (LSTM hoặc Transformer) để nắm bắt các phụ thuộc thời gian qua đêm. Hiểu biết là phân loại giai đoạn ngủ không phải là vấn đề phân loại tĩnh mỗi cửa sổ; đó là vấn đề chuỗi thời gian, vì các chu kỳ ngủ tuân theo các mẫu vĩ mô có thể dự đoán (chu kỳ khoảng 90 phút từ nhẹ đến sâu đến REM). Mô hình thấy 30 phút tín hiệu sinh học trước đó vượt trội hơn mô hình phân loại từng epoch độc lập đáng kể.
  </p>
  <p>
    Mô hình trên thiết bị hiện tại của YumePad sử dụng biến thể của kiến trúc này, được tinh chỉnh theo từng người dùng trong hai tuần đầu sử dụng để tính đến sự khác biệt cơ sở cá nhân về động học nhịp tim và tần số hô hấp. Lớp cá nhân hóa này — đôi khi được gọi là "mô hình hiệu chỉnh người dùng" — là yếu tố phân biệt đáng kể so với các máy theo dõi giấc ngủ tiêu dùng thông thường áp dụng các mô hình cấp độ dân số mà không thích ứng theo từng người dùng.
  </p>

  <figure class="article-figure">
    <img src="/generated/news-how-ai-revolutionizes-sleep-monitoring-inline-2.png" alt="Trực quan hóa dữ liệu hiển thị các chuyển tiếp giai đoạn ngủ qua một đêm" loading="lazy" />
    <figcaption>Trực quan hóa kiến trúc giấc ngủ toàn đêm từ phiên YumePad. Mỗi epoch (30 giây) được mô hình AI trên thiết bị phân loại. Lưu ý các cụm REM đặc trưng trong nửa sau của đêm — một mẫu mà mô hình đã học cách cân bằng nhiều hơn khi gần sáng.</figcaption>
  </figure>

  <h2>Phát Hiện Những Gì Từng Cần Phòng Khám</h2>
  <p>
    Ý nghĩa lâm sàng rất đáng kể. Ngưng thở khi ngủ tắc nghẽn (OSA) ảnh hưởng đến ước tính 1 tỷ người trên toàn thế giới, phần lớn chưa được chẩn đoán. Con đường truyền thống đến chẩn đoán — PSG trong phòng thí nghiệm giấc ngủ — tốn hàng trăm đến hàng nghìn đô la và cần giới thiệu của bác sĩ. Kiểm tra giấc ngủ tại nhà (HST) với các thiết bị được phê duyệt tốn kém ít hơn nhưng vẫn cần gửi và trả thiết bị và thiếu thông tin phân loại giai đoạn ngủ cần thiết cho đánh giá đầy đủ.
  </p>
  <p>
    Cảm biến môi trường được hỗ trợ AI đang bắt đầu lấp đầy khoảng cách này. Hệ thống đo chỉ số sự kiện hô hấp hàng đêm (REI), các mẫu giảm bão hòa oxy (khi kết hợp với đo oxy mạch), và sự phân mảnh giấc ngủ qua nhiều tuần theo dõi liên tục có thể xác định những người có khả năng bị OSA có ý nghĩa lâm sàng với độ nhạy và độ đặc hiệu tiếp cận HST trong các nghiên cứu xác nhận. Đây không phải công cụ chẩn đoán — nó không thể thay thế phán đoán lâm sàng của bác sĩ hay chẩn đoán chính thức — nhưng như công cụ sàng lọc, nó có thể xác định ai cần đánh giá chính thức nhất. Chức năng sàng lọc cấp độ dân số này một mình có thể thu hẹp đáng kể khoảng cách chẩn đoán cho một trong những tình trạng được điều trị ít nhất trong y học toàn cầu.
  </p>

  <h2>Những Gì AI Vẫn Chưa Làm Được</h2>
  <p>
    Sự trung thực về giới hạn là điều kiện tiên quyết cho niềm tin. Các hệ thống AI giấc ngủ không tiếp xúc hiện tại có những giới hạn có ý nghĩa mà lĩnh vực vẫn đang cố gắng giải quyết.
  </p>
  <p>
    <strong>Suy giảm chất lượng tín hiệu.</strong> Khối lượng cơ thể rất cao, đệm cực mềm, hoặc lớp phủ đệm dày có thể làm giảm tín hiệu BCG xuống dưới ngưỡng có thể sử dụng. Người ngủ cùng giường tạo ra nhiễu chuyển động, mặc dù được bù một phần bởi các cấu hình vùng kép hiện đại.
  </p>
  <p>
    <strong>Khả năng khái quát hóa dân số.</strong> Các mô hình được huấn luyện chủ yếu trên các mẫu dân số châu Á (như hầu hết các thiết bị hiện tại) có thể cho thấy độ chính xác giảm ở những người có hồ sơ tim mạch hoặc hô hấp khác biệt đáng kể. Đây là vấn đề đã biết trong AI lâm sàng và đang được giải quyết thông qua các bộ dữ liệu huấn luyện đa dạng hơn.
  </p>
  <p>
    <strong>Đối với các sự kiện lâm sàng cá nhân.</strong> Kết quả dương tính được sàng lọc từ thiết bị AI tiêu dùng không phải là phát hiện lâm sàng. Đó là cờ hiệu cho đánh giá lâm sàng. Các hệ thống trình bày kết quả phân tích giấc ngủ AI như chẩn đoán dứt khoát tạo ra rủi ro. Cách tiếp cận của SleepTech là trình bày khoảng tin cậy và ước tính không chắc chắn rõ ràng cùng với tất cả các chỉ số sức khỏe có nguồn gốc từ AI.
  </p>

  <h2>Năm Năm Tới: Điều Gì Đang Đến</h2>
  <p>
    Một số quỹ đạo rõ ràng. Hợp nhất đa phương thức — kết hợp dữ liệu BCG từ pad với âm thanh từ microphone phòng (để phát hiện ngáy và phân tích âm thanh hô hấp), hồng ngoại từ camera bên giường, và PPG đeo được từ nhẫn hoặc vòng đeo tay tùy chọn — sẽ cải thiện đáng kể độ chính xác trên các trường hợp ngoài lề mà hệ thống đơn phương thức xử lý kém.
  </p>
  <p>
    Phát hiện thay đổi sức khỏe theo chiều dọc là ứng dụng gần nhất thú vị nhất. Hệ thống biết sâu sắc về cơ sở giấc ngủ của bạn — vì đã đo mỗi đêm trong hai năm — có thể phát hiện các sai lệch có ý nghĩa thống kê so với cơ sở đó nhiều tuần trước khi chúng biểu hiện thành triệu chứng. Đây là cảnh báo sớm bệnh mãn tính ở quy mô dân số: không phải ảnh chụp lâm sàng một lần, mà là tín hiệu sức khỏe liên tục từ cuộc sống hàng ngày.
  </p>
  <p>
    Tích hợp mô hình ngôn ngữ lớn đang bắt đầu cho phép huấn luyện giấc ngủ bằng ngôn ngữ tự nhiên: các giao diện đàm thoại có thể giải thích các mẫu giấc ngủ phức tạp cho người dùng không chuyên, đề xuất các can thiệp hành vi có bằng chứng, và cảnh báo người dùng khi các mẫu cho thấy cần tham khảo ý kiến bác sĩ.
  </p>

  <h2>Bắt Đầu</h2>
  <p>
    Nếu bạn tò mò về kiến trúc giấc ngủ thực sự của mình trông như thế nào — không phải những gì bạn hy vọng, không phải những gì bạn giả định dựa trên cảm giác buổi sáng, mà là những gì hồ sơ tín hiệu sinh học cho thấy — bước quan trọng nhất đơn giản là bắt đầu đo. Máy theo dõi giấc ngủ AI tiêu dùng đã đạt đến mức trưởng thành mà dữ liệu hàng đêm thực sự mang lại thông tin hữu ích, và bức tranh dọc tích lũy qua nhiều tuần và tháng có giá trị hơn nhiều so với bất kỳ ảnh chụp đơn đêm nào.
  </p>
  <p>
    Sẵn sàng nhìn giấc ngủ của bạn dưới ánh sáng mới chưa? Khám phá <a href="/vi#products">hệ thống YumePad</a> và bắt đầu xây dựng cơ sở sức khỏe của chính bạn — hoặc <a href="/vi/contact">liên hệ với nhóm của chúng tôi</a> để tìm hiểu thêm về quan hệ đối tác lâm sàng và chương trình nghiên cứu.
  </p>

</div>
