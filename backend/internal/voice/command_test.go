package voice

import "testing"

func TestParseVietCommand(t *testing.T) {
	cases := []struct {
		name    string
		text    string
		wantCmd string
		wantOK  bool
	}{
		{"bật có dấu", "bật điều hòa", "on", true},
		{"tắt có dấu, máy lạnh", "tắt máy lạnh", "off", true},
		{"bật không dấu", "bat dieu hoa", "on", true},
		{"tắt không dấu", "tat may lanh", "off", true},
		{"điều hoà chính tả mới", "bật điều hoà lên", "on", true},
		{"không khớp - đèn", "mở đèn", "", false},
		{"không khớp - rỗng", "", "", false},
		{"không khớp - chỉ nhắc AC không có bật/tắt", "điều hòa đang chạy tốt", "", false},
		{"hoa in", "BẬT ĐIỀU HÒA", "on", true},
		// Whisper nhại lại initial_prompt của service ASR khi gặp nhiễu. Câu này từng làm điều hoà
		// bật lại ngay sau khi user ra lệnh tắt, vì switch kiểm "bat" trước "tat".
		{"ảo giác nhại prompt - chứa cả bật lẫn tắt", "Lệnh điều khiển điều hòa, bật máy lạnh, tắt máy lạnh.", "", false},
		{"mơ hồ - tắt trước bật sau", "tắt điều hòa rồi bật lại", "", false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			cmd, ok := ParseVietCommand(tc.text)
			if cmd != tc.wantCmd || ok != tc.wantOK {
				t.Fatalf("ParseVietCommand(%q) = (%q, %v), muốn (%q, %v)", tc.text, cmd, ok, tc.wantCmd, tc.wantOK)
			}
		})
	}
}
