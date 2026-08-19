package voice

import "testing"

func TestParseVietCommand(t *testing.T) {
	cases := []struct {
		name      string
		text      string
		wantCmd   string
		wantSteps int
		wantOK    bool
	}{
		{"bật có dấu", "bật điều hòa", "on", 0, true},
		{"tắt có dấu, máy lạnh", "tắt máy lạnh", "off", 0, true},
		{"bật không dấu", "bat dieu hoa", "on", 0, true},
		{"tắt không dấu", "tat may lanh", "off", 0, true},
		{"điều hoà chính tả mới", "bật điều hoà lên", "on", 0, true},
		{"không khớp - đèn", "mở đèn", "", 0, false},
		{"không khớp - rỗng", "", "", 0, false},
		{"không khớp - chỉ nhắc AC không có bật/tắt", "điều hòa đang chạy tốt", "", 0, false},
		{"hoa in", "BẬT ĐIỀU HÒA", "on", 0, true},
		// Whisper nhại lại initial_prompt của service ASR khi gặp nhiễu. Câu này từng làm điều hoà
		// bật lại ngay sau khi user ra lệnh tắt, vì switch kiểm "bat" trước "tat".
		{"ảo giác nhại prompt - chứa cả bật lẫn tắt", "Lệnh điều khiển điều hòa, bật máy lạnh, tắt máy lạnh.", "", 0, false},
		{"mơ hồ - tắt trước bật sau", "tắt điều hòa rồi bật lại", "", 0, false},

		// ── Lệnh nhiệt độ ────────────────────────────────────────────────────────
		// Chuỗi lấy TRỰC TIẾP từ sherpa-onnx khi nói vào mic INMP441 (đo 17/08). Số đọc thành
		// CHỮ ("MỘT") chứ không phải ký tự "1" — chỉ bắt chữ số là hỏng mọi lệnh nhiều bước.
		{"ASR thật - tăng", "TĂNG MỘT NHIỆT ĐỘ", "temp_up", 1, true},
		{"ASR thật - có đuôi wakeword", "HƠI TĂNG MỘT NHIỆT ĐỘ", "temp_up", 1, true},
		{"ASR thật - giảm", "ƠI GIẢM MỘT NHIỆT ĐỘ", "temp_down", 1, true},
		// Lần thứ 4 trong buổi đo: ASR nuốt mất động từ. Phải bỏ qua, KHÔNG được đoán.
		{"ASR thật - mất động từ", "ƠI NHIỆT ĐỘ", "", 0, false},

		{"không nói số - mặc định 1", "tăng nhiệt độ", "temp_up", 1, true},
		{"số bằng chữ", "giảm hai độ", "temp_down", 2, true},
		{"số bằng chữ số", "tăng 3 độ", "temp_up", 3, true},
		{"không dấu", "giam nhiet do", "temp_down", 1, true},
		{"kẹp trên - nói quá to số", "tăng 100 độ", "temp_up", 10, true},

		// KHÔNG bắt buộc nhắc "điều hoà" cho lệnh nhiệt độ — không câu nào trong buổi đo có từ đó.
		{"có nhắc điều hoà cũng được", "tăng nhiệt độ điều hòa", "temp_up", 1, true},

		// Câu đời thường chứa "tăng"/"nâng" + "độ" nhưng KHÔNG phải lệnh. Đây là lớp lỗi chính
		// khi bỏ ràng buộc phải nhắc điều hoà.
		{"không khớp - tăng tốc độ", "tăng tốc độ lên", "", 0, false},
		{"không khớp - trình độ", "nâng cao trình độ", "", 0, false},
		{"không khớp - tăng âm lượng", "tăng âm lượng", "", 0, false},

		{"mơ hồ - cả tăng lẫn giảm", "tăng rồi giảm nhiệt độ", "", 0, false},
		{"ảo giác nhại prompt dạng nhiệt độ", "Lệnh điều khiển: tăng nhiệt độ, giảm nhiệt độ.", "", 0, false},
		// Trộn hai nhóm lệnh trong một câu -> không suy ra được ý định, thà không làm gì.
		{"mơ hồ - trộn bật với tăng", "bật điều hòa tăng nhiệt độ", "", 0, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := ParseVietCommand(tc.text)
			if got.Kind != tc.wantCmd || got.Steps != tc.wantSteps || ok != tc.wantOK {
				t.Fatalf("ParseVietCommand(%q) = (%+v, %v), muốn ({Kind:%s Steps:%d}, %v)",
					tc.text, got, ok, tc.wantCmd, tc.wantSteps, tc.wantOK)
			}
		})
	}
}

// TestSoBuocTruocCumNhietDo khoá lại lỗi đo được 17/08: "giảm 2 nhiệt độ" ra steps=1.
//
// Luật cũ chỉ tìm số đứng NGAY TRƯỚC "do", nên trong "giam 2 nhiet do" thứ đứng trước "do" là
// "nhiet" -> không thấy số -> rơi về mặc định 1. Hỏng âm thầm: không log, không báo, chỉ chỉnh sai
// số bậc. Chưa lộ ra suốt buổi thử vì người dùng toàn nói "tăng 1 nhiệt độ", mà 1 đúng bằng mặc định.
func TestSoBuocTruocCumNhietDo(t *testing.T) {
	cases := []struct {
		text      string
		wantCmd   string
		wantSteps int
	}{
		{"giảm 2 nhiệt độ", "temp_down", 2},
		{"giảm hai nhiệt độ", "temp_down", 2},
		{"tăng 3 nhiệt độ", "temp_up", 3},
		{"TĂNG BA NHIỆT ĐỘ", "temp_up", 3},
		{"giam 2 nhiet do", "temp_down", 2},
		// Dạng cũ vẫn phải giữ nguyên.
		{"giảm 2 độ", "temp_down", 2},
		{"tăng nhiệt độ", "temp_up", 1},
		{"TĂNG MỘT NHIỆT ĐỘ", "temp_up", 1},
	}
	for _, tc := range cases {
		t.Run(tc.text, func(t *testing.T) {
			got, ok := ParseVietCommand(tc.text)
			if !ok || got.Kind != tc.wantCmd || got.Steps != tc.wantSteps {
				t.Fatalf("ParseVietCommand(%q) = (%+v, %v), muốn ({%s %d}, true)",
					tc.text, got, ok, tc.wantCmd, tc.wantSteps)
			}
		})
	}
}

// Câu đời thường chứa động từ + "độ" vẫn phải trượt sau khi nới luật bắt số.
func TestNoiLuatKhongLamLotCauDoiThuong(t *testing.T) {
	for _, text := range []string{"tăng tốc độ lên", "nâng cao trình độ", "tăng tốc độ 2 lần"} {
		if _, ok := ParseVietCommand(text); ok {
			t.Fatalf("ParseVietCommand(%q) khớp lệnh — không được", text)
		}
	}
}

// TestTuDongNghia — cho phép nói từ khác cho cùng một ý định.
//
// Vì sao: đo 17/08 trên giọng thật qua mic INMP441 cho thấy chênh lệch ổn định giữa các động từ.
// "tắt" 4/5 và "giảm" 6/7, trong khi "bật" 2/5 và "tăng" 3/5. Ba buổi đo độc lập cùng một hướng.
// Hai từ yếu đều là thanh ngang, âm ngắn, phụ âm đầu nhẹ — "bật" bị nghe thành "mặc", "tăng"
// thành "ăn". Thêm từ đồng nghĩa có phụ âm rõ hơn cho người dùng một đường thoát, rẻ hơn nhiều so
// với chỉnh cấu hình giải mã ASR.
func TestTuDongNghia(t *testing.T) {
	cases := []struct {
		text    string
		wantCmd string
	}{
		{"mở điều hòa", KindOn},
		{"MỞ MÁY LẠNH", KindOn},
		{"nâng nhiệt độ", KindTempUp},
		{"lên 2 độ", KindTempUp},
		{"hạ nhiệt độ", KindTempDown},
		{"xuống 2 độ", KindTempDown},
	}
	for _, tc := range cases {
		t.Run(tc.text, func(t *testing.T) {
			got, ok := ParseVietCommand(tc.text)
			if !ok || got.Kind != tc.wantCmd {
				t.Fatalf("ParseVietCommand(%q) = (%+v, %v), muốn Kind=%s", tc.text, got, ok, tc.wantCmd)
			}
		})
	}
}

// Từ đồng nghĩa KHÔNG được làm lọt câu đời thường, và luật loại câu mơ hồ vẫn phải giữ.
func TestTuDongNghiaKhongLamLotCauKhac(t *testing.T) {
	for _, text := range []string{
		"mở cửa sổ",             // "mở" nhưng không nhắc điều hoà
		"lên tốc độ",            // "lên" + "độ" nhưng không phải nhiệt độ
		"nâng cao trình độ",     // đã có từ trước, giữ nguyên
		"nâng rồi hạ nhiệt độ",  // mơ hồ: cả tăng lẫn giảm
		"mở rồi tắt điều hòa",   // mơ hồ: cả bật lẫn tắt
	} {
		if got, ok := ParseVietCommand(text); ok {
			t.Fatalf("ParseVietCommand(%q) = %+v — không được khớp", text, got)
		}
	}
}

// So khớp phải tính theo TỪ TRỌN VẸN, không phải chuỗi con: "mo" nằm trong "mot" (một), "ha" nằm
// trong "nhanh". Dùng Contains thì "tắt máy lạnh một lúc" khớp cả bật lẫn tắt rồi bị loại oan.
func TestSoKhopTheoTuTronVen(t *testing.T) {
	got, ok := ParseVietCommand("tắt máy lạnh một lúc")
	if !ok || got.Kind != KindOff {
		t.Fatalf("ParseVietCommand(\"tắt máy lạnh một lúc\") = (%+v, %v), muốn off", got, ok)
	}
}
