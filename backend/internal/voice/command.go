// Package voice xử lý đường thoại: nhận PCM từ voice node, gom utterance, gọi ASR,
// parse lệnh tiếng Việt rồi publish qua mqttclient (interface ACPublisher).
package voice

import (
	"regexp"
	"strconv"
	"strings"
)

// vietDiacriticMap bỏ dấu tiếng Việt bằng bảng ánh xạ rune. Chỉ cần đủ cho các từ khóa lệnh
// AC cố định (không cần thư viện normalize nặng — YAGNI).
var vietDiacriticMap = map[rune]rune{
	'à': 'a', 'á': 'a', 'ạ': 'a', 'ả': 'a', 'ã': 'a',
	'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ậ': 'a', 'ẩ': 'a', 'ẫ': 'a',
	'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ặ': 'a', 'ẳ': 'a', 'ẵ': 'a',
	'è': 'e', 'é': 'e', 'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e',
	'ê': 'e', 'ề': 'e', 'ế': 'e', 'ệ': 'e', 'ể': 'e', 'ễ': 'e',
	'ì': 'i', 'í': 'i', 'ị': 'i', 'ỉ': 'i', 'ĩ': 'i',
	'ò': 'o', 'ó': 'o', 'ọ': 'o', 'ỏ': 'o', 'õ': 'o',
	'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ộ': 'o', 'ổ': 'o', 'ỗ': 'o',
	'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ợ': 'o', 'ở': 'o', 'ỡ': 'o',
	'ù': 'u', 'ú': 'u', 'ụ': 'u', 'ủ': 'u', 'ũ': 'u',
	'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ự': 'u', 'ử': 'u', 'ữ': 'u',
	'ỳ': 'y', 'ý': 'y', 'ỵ': 'y', 'ỷ': 'y', 'ỹ': 'y',
	'đ': 'd',
}

// stripDiacritics bỏ dấu để so khớp được cả câu ASR trả có dấu lẫn không dấu.
func stripDiacritics(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range s {
		if repl, ok := vietDiacriticMap[r]; ok {
			r = repl
		}
		b.WriteRune(r)
	}
	return b.String()
}

// Command — lệnh AC suy ra từ câu nói. Steps chỉ có nghĩa với KindTempUp/KindTempDown.
//
// Dùng struct thay vì trả string trần như bản đầu: lệnh nhiệt độ mang theo số bước, nhét nó vào
// chuỗi ("temp_up:2") thì phải parse lại ở đầu kia và mất luôn kiểm tra của trình biên dịch.
type Command struct {
	Kind  string
	Steps int
}

const (
	KindOn       = "on"
	KindOff      = "off"
	KindTempUp   = "temp_up"
	KindTempDown = "temp_down"
)

// Giới hạn số bước một lệnh được đổi. Người ta không nói "tăng 40 độ"; con số lớn gần như chắc
// chắn là ASR nghe nhầm, và kẹp lại rẻ hơn là để nó bắn một lệnh vô lý.
const stepsToiDa = 10

// soTiengViet — số đọc thành CHỮ. Bắt buộc phải có: đo 17/08 thấy sherpa trả về "TĂNG MỘT NHIỆT
// ĐỘ" cho câu "tăng 1 nhiệt độ", tức là chữ "MỘT" chứ không phải ký tự "1". Chỉ bắt chữ số thì mọi
// lệnh nhiều bước âm thầm rơi về 1 mà không ai phát hiện.
var soTiengViet = map[string]int{
	"mot": 1, "hai": 2, "ba": 3, "bon": 4, "nam": 5,
	"sau": 6, "bay": 7, "tam": 8, "chin": 9, "muoi": 10,
}

// reSoTruocDo — số (chữ số hoặc chữ) đứng trước "do", cho phép chen cụm "nhiet" ở giữa.
//
// Phần `(?:nhiet\s+)?` là bắt buộc: người dùng nói "giảm 2 NHIỆT ĐỘ" chứ không phải "giảm 2 độ".
// Luật cũ chỉ bắt số ngay sát "do" nên trong "giam 2 nhiet do" nó thấy "nhiet" và rơi về mặc định 1
// — hỏng âm thầm, đo được 17/08.
//
// Vẫn KHÔNG nhận "tăng tốc độ" / "nâng cao trình độ": ở đó thứ đứng trước "do" là "toc"/"trinh",
// không phải số.
var reSoTruocDo = regexp.MustCompile(`(\d+|[a-z]+)\s+(?:nhiet\s+)?do\b`)

// ParseVietCommand nhận text tiếng Việt (có hoặc không dấu) từ ASR, trả về lệnh AC.
//
// Bật/tắt: bắt buộc nhắc "điều hòa"/"điều hoà"/"máy lạnh" (bỏ dấu: "dieu hoa"/"may lanh") kèm
// "bật"/"tắt".
//
// Nhiệt độ: "tăng"/"giảm" kèm cụm "nhiệt độ", HOẶC kèm một SỐ đứng ngay trước "độ" ("tăng 2 độ").
// KHÔNG bắt buộc nhắc điều hoà — đo 17/08 cho thấy không câu nào người dùng nói có từ đó, giữ ràng
// buộc cũ thì mọi lệnh nhiệt độ đều trượt.
//
// Điều kiện "độ" phải chặt như trên vì bỏ ràng buộc nhắc điều hoà làm rộng bề mặt kích nhầm:
// "tăng tốc độ" và "nâng cao trình độ" đều chứa động từ tăng/nâng lẫn chuỗi "do" sau khi bỏ dấu.
// Cả hai không có "nhiet do", và trước "do" là chữ thường chứ không phải số, nên bị loại.
//
// Không khớp -> ok=false, caller log rồi bỏ qua (không publish gì).
//
// Câu mơ hồ bị LOẠI, không được chọn một trong hai — áp dụng cho cả cặp bật/tắt, cặp tăng/giảm,
// lẫn trường hợp trộn hai nhóm. Trước đây switch kiểm "bat" trước nên câu chứa cả hai luôn thành
// "on": kết quả do thứ tự case quyết định, không do ngữ nghĩa. Điều đó gây lỗi thật — người dùng
// nói "tắt điều hòa" (đã publish off), 3 giây sau whisper gặp nhiễu và nhại lại nguyên văn danh
// sách lệnh trong initial_prompt của service ASR ("... bật máy lạnh, tắt máy lạnh"), câu đó khớp
// nhánh "bat" -> publish on -> điều hoà bật lại ngay, ngược ý người dùng. Loại câu mơ hồ chặn cả
// lớp lỗi này bất kể ASR trả về gì.
func ParseVietCommand(text string) (Command, bool) {
	normalized := stripDiacritics(strings.ToLower(strings.TrimSpace(text)))

	hasAC := strings.Contains(normalized, "dieu hoa") || strings.Contains(normalized, "may lanh")
	wantOn := hasAC && strings.Contains(normalized, "bat")
	wantOff := hasAC && strings.Contains(normalized, "tat")

	hasTemp := strings.Contains(normalized, "nhiet do") || coSoTruocDo(normalized)
	wantUp := hasTemp && strings.Contains(normalized, "tang")
	wantDown := hasTemp && strings.Contains(normalized, "giam")

	nhomNguon := 0
	if wantOn || wantOff {
		nhomNguon++
	}
	if wantUp || wantDown {
		nhomNguon++
	}
	// Trộn hai nhóm ("bật điều hòa tăng nhiệt độ") cũng là mơ hồ: không biết bắn lệnh nào trước,
	// và câu nhại prompt hay rơi vào dạng này.
	if nhomNguon > 1 || (wantOn && wantOff) || (wantUp && wantDown) {
		return Command{}, false
	}

	switch {
	case wantOn:
		return Command{Kind: KindOn}, true
	case wantOff:
		return Command{Kind: KindOff}, true
	case wantUp:
		return Command{Kind: KindTempUp, Steps: docSoBuoc(normalized)}, true
	case wantDown:
		return Command{Kind: KindTempDown, Steps: docSoBuoc(normalized)}, true
	default:
		return Command{}, false
	}
}

// coSoTruocDo — có một số (chữ số hoặc chữ tiếng Việt) đứng trước "do" hay không.
func coSoTruocDo(normalized string) bool {
	_, co := timSoTruocDo(normalized)
	return co
}

// timSoTruocDo quét MỌI vị trí khớp chứ không chỉ vị trí đầu: câu có thể chứa một cụm "…độ" không
// mang số trước một cụm mang số ("tăng tốc độ rồi giảm 2 nhiệt độ"). Lấy match đầu tiên sẽ kết luận
// nhầm là không có số.
func timSoTruocDo(normalized string) (int, bool) {
	for _, m := range reSoTruocDo.FindAllStringSubmatch(normalized, -1) {
		if n, ok := soTiengViet[m[1]]; ok {
			return n, true
		}
		if n, err := strconv.Atoi(m[1]); err == nil {
			return n, true
		}
	}
	return 0, false
}

// docSoBuoc trả số bước, mặc định 1 khi câu không nói số. Kẹp về stepsToiDa thay vì loại câu:
// người dùng nói "tăng 100 độ" rõ ràng muốn tăng, chỉ là con số vô lý.
func docSoBuoc(normalized string) int {
	n, co := timSoTruocDo(normalized)
	if !co || n < 1 {
		return 1
	}
	if n > stepsToiDa {
		return stepsToiDa
	}
	return n
}
