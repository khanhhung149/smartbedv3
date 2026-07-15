// Package voice xử lý đường thoại: nhận PCM từ voice node, gom utterance, gọi ASR,
// parse lệnh tiếng Việt rồi publish qua mqttclient (interface ACPublisher).
package voice

import "strings"

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

// ParseVietCommand nhận text tiếng Việt (có hoặc không dấu) từ ASR, trả về lệnh AC.
// Khớp: có nhắc tới "điều hòa"/"điều hoà"/"máy lạnh" (đã bỏ dấu: "dieu hoa"/"may lanh")
// kèm "bật" ("bat") -> ("on", true); kèm "tắt" ("tat") -> ("off", true).
// Không khớp -> ("", false), caller log rồi bỏ qua (không publish gì).
func ParseVietCommand(text string) (string, bool) {
	normalized := stripDiacritics(strings.ToLower(strings.TrimSpace(text)))

	hasAC := strings.Contains(normalized, "dieu hoa") || strings.Contains(normalized, "may lanh")
	if !hasAC {
		return "", false
	}
	switch {
	case strings.Contains(normalized, "bat"):
		return "on", true
	case strings.Contains(normalized, "tat"):
		return "off", true
	default:
		return "", false
	}
}
