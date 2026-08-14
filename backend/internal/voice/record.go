package voice

import (
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"
)

// RecordHandler ghi thẳng PCM từ voice-node xuống file WAV — công cụ THU DỮ LIỆU HUẤN LUYỆN,
// không phải đường chạy thật.
//
// Vì sao cần: model snore hiện train trên dataset Khan 2019 (ngáy thu gần, phòng thu sạch) nên
// lệch miền so với mic INMP441 đặt cách giường 30-40cm — đo trên board 2026-08-14 thấy model có
// phản ứng (score 0,05-0,29) nhưng không đủ tự tin để vượt ngưỡng. Muốn thu hẹp khoảng cách đó
// thì phải có dữ liệu thu qua ĐÚNG mic, ĐÚNG vị trí, ĐÚNG nhiễu nền của phòng ngủ.
//
// Tách khỏi Handler (stream.go) thay vì thêm cờ vào đó: đường wakeword->ASR->lệnh AC đang chạy ổn
// định, không đáng để một tính năng thu dữ liệu tạm thời chen vào và làm nó phức tạp thêm.
type RecordHandler struct {
	dir        string
	segmentDur time.Duration
	sampleRate int
	// Đếm để đặt tên file không trùng khi có nhiều kết nối/lần thu trong cùng một giây.
	seq atomic.Uint64
}

// NewRecordHandler trả về nil nếu dir rỗng — gọi nơi dùng chỉ cần kiểm nil để biết tính năng có
// bật hay không, khỏi phải mang thêm cờ boolean song song.
func NewRecordHandler(dir string, segmentSeconds, sampleRate int) *RecordHandler {
	if dir == "" {
		return nil
	}
	if segmentSeconds <= 0 {
		segmentSeconds = 60
	}
	return &RecordHandler{
		dir:        dir,
		segmentDur: time.Duration(segmentSeconds) * time.Second,
		sampleRate: sampleRate,
	}
}

// ServeHTTP nhận WS binary PCM16 mono, cắt thành từng đoạn segmentDur rồi ghi WAV.
//
// Cắt đoạn thay vì ghi một file khổng lồ: thu qua đêm là hàng giờ audio, một file duy nhất vừa
// khó gán nhãn vừa mất trắng nếu tiến trình chết giữa chừng. Mỗi đoạn ghi xong là an toàn trên đĩa.
func (h *RecordHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		OriginPatterns: []string{"*"}, // LAN nội bộ, giống các endpoint WS khác
	})
	if err != nil {
		return
	}
	defer conn.Close(websocket.StatusNormalClosure, "")

	if err := os.MkdirAll(h.dir, 0o755); err != nil {
		slog.Error("record: tạo thư mục lỗi", "dir", h.dir, "err", err)
		return
	}

	// Nhãn do người thu đặt (?label=snore / ?label=quiet) — đi vào tên file để khỏi phải nhớ
	// đoạn nào là gì khi ngồi gán nhãn hàng trăm file sau này.
	label := r.URL.Query().Get("label")
	if label == "" {
		label = "raw"
	}

	ctx := r.Context()
	bytesPerSegment := h.sampleRate * 2 * int(h.segmentDur/time.Second) // 2 byte/mẫu, mono
	seg := make([]byte, 0, bytesPerSegment)
	total := 0

	slog.Info("record: bắt đầu thu", "dir", h.dir, "label", label,
		"segment_s", int(h.segmentDur/time.Second))

	flush := func() {
		if len(seg) == 0 {
			return
		}
		name := fmt.Sprintf("%s-%s-%03d-%.0fs.wav", label,
			time.Now().Format("20060102-150405"), h.seq.Add(1),
			float64(len(seg))/float64(h.sampleRate*2))
		path := filepath.Join(h.dir, name)
		if err := os.WriteFile(path, buildWAV(seg, h.sampleRate), 0o644); err != nil {
			slog.Error("record: ghi file lỗi", "path", path, "err", err)
		} else {
			slog.Info("record: lưu đoạn", "file", name, "bytes", len(seg))
		}
		seg = seg[:0]
	}
	defer flush() // đoạn dở dang lúc ngắt kết nối vẫn được giữ, không vứt đi

	for {
		msgType, data, err := conn.Read(ctx)
		if err != nil {
			slog.Info("record: kết thúc", "tổng_byte", total, "err", err)
			return
		}
		if msgType != websocket.MessageBinary || len(data) == 0 {
			continue
		}
		seg = append(seg, data...)
		total += len(data)
		if len(seg) >= bytesPerSegment {
			flush()
		}
	}
}
