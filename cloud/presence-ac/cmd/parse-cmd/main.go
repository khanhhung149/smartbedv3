// parse-cmd — đọc text tiếng Việt từ stdin (mỗi dòng một câu), in kết quả parse dạng JSON.
//
// Vì sao tồn tại: bộ chấm điểm ASR cần biết một câu ASR trả về CÓ ra lệnh hay không. Trước đây
// asr/score_samples.py giữ một bản sao thủ công của ParseVietCommand bằng Python, và docstring của
// chính nó đã ghi "NGUỒN SỰ THẬT là file Go". Bản sao đó lệch ngay lần đầu bản Go đổi (thêm lệnh
// nhiệt độ, 17/08), và điểm đo khi đó phản ánh một parser không ai đang chạy.
//
// CLI này xoá hẳn khả năng lệch: chỉ có MỘT cài đặt, bộ chấm điểm gọi đúng nó.
//
// Build tĩnh để chạy được trong container chấm điểm (không có Go):
//
//	cd backend && CGO_ENABLED=0 go build -o bin/parse-cmd ./cmd/parse-cmd
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"

	"github.com/hung/home-backend/internal/voice"
)

type ketQua struct {
	Text  string `json:"text"`
	OK    bool   `json:"ok"`
	Kind  string `json:"kind"`
	Steps int    `json:"steps"`
}

func main() {
	in := bufio.NewScanner(os.Stdin)
	// Câu ASR trả về luôn ngắn, nhưng buffer mặc định 64KB vẫn có thể bị tràn nếu ai đó đưa nhầm
	// một file lớn vào — nới ra cho chắc, rẻ hơn là đi tìm lỗi "token too long" sau này.
	in.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	out := json.NewEncoder(os.Stdout)
	for in.Scan() {
		cmd, ok := voice.ParseVietCommand(in.Text())
		if err := out.Encode(ketQua{Text: in.Text(), OK: ok, Kind: cmd.Kind, Steps: cmd.Steps}); err != nil {
			fmt.Fprintln(os.Stderr, "ghi kết quả lỗi:", err)
			os.Exit(1)
		}
	}
	if err := in.Err(); err != nil {
		fmt.Fprintln(os.Stderr, "đọc stdin lỗi:", err)
		os.Exit(1)
	}
}
