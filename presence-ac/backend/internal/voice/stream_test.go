package voice

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"
)

type noopPublisher struct{}

func (noopPublisher) PublishACCmd(string) error       { return nil }
func (noopPublisher) PublishACTemp(string, int) error { return nil }

// slowASR giả lập faster-whisper: chậm hơn thời gian thực (đo thật 31/07: 7.1s cho câu 2.3s).
// Ghi lại kích thước từng body nhận được để biết utterance có bị gộp không.
type slowASR struct {
	delay  time.Duration
	mu     sync.Mutex
	bodies []int
}

func (s *slowASR) handler(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	time.Sleep(s.delay)
	s.mu.Lock()
	s.bodies = append(s.bodies, len(body))
	s.mu.Unlock()
	w.Header().Set("Content-Type", "application/json")
	io.WriteString(w, `{"text":"bật điều hòa"}`)
}

func (s *slowASR) snapshot() []int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]int(nil), s.bodies...)
}

// TestUtterancesStaySeparateWhileASRIsSlow khoá lại lỗi: gọi ASR đồng bộ trong vòng select làm
// vòng lặp ngừng đọc frame và ngừng chạy ticker suốt thời gian ASR chạy. Tiếng nói đến trong lúc đó
// dồn lại rồi được nạp một lượt với cùng mốc thời gian, nên cả điều kiện cắt theo wall-clock lẫn
// cắt theo im lặng đều không kích hoạt -> nhiều câu dính vào một utterance.
//
// Hậu quả thật: nói "tắt điều hòa" ngay sau "bật điều hòa" thì hai câu vào chung một utterance chứa
// cả hai động từ, ParseVietCommand loại vì mơ hồ, không lệnh nào chạy.
//
// Điều kiện bắt được lỗi rất kén, sai là test xanh với cả bản lỗi: khoảng lặng giữa 2 đợt phải
// DÀI HƠN SilenceMS (để bản đúng cắt được) nhưng NGẮN HƠN thời gian ASR chạy (để tiếng đợt sau đến
// đúng lúc vòng lặp đang bị chặn). Lặng 400ms với ASR 300ms thì không đợt nào đến trong lúc ASR
// bận, và bản lỗi cũng qua.
//
// Điểm phân biệt là KÍCH THƯỚC utterance, không phải số lượng: hàng đợi 1 slot của bản đúng cố ý
// bỏ bớt câu cũ khi ASR không theo kịp, nên đếm số lần gọi thì cả hai bản đều ra như nhau.
func TestUtterancesStaySeparateWhileASRIsSlow(t *testing.T) {
	const (
		frameBytes = 640 // 20ms PCM 16kHz mono 16-bit
		framesPer  = 5   // 1 đợt = 3200 byte
		bursts     = 3
	)

	asr := &slowASR{delay: 600 * time.Millisecond}
	asrSrv := httptest.NewServer(http.HandlerFunc(asr.handler))
	defer asrSrv.Close()

	h := NewHandler(noopPublisher{}, Config{
		ASRURL:     asrSrv.URL,
		SilenceMS:  100,
		MaxUtterMS: 5000, // cao để phép thử chỉ phụ thuộc đường cắt-theo-im-lặng
		SampleRate: 16000,
	})
	wsSrv := httptest.NewServer(h)
	defer wsSrv.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	conn, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(wsSrv.URL, "http"), nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer conn.Close(websocket.StatusNormalClosure, "")

	frame := make([]byte, frameBytes)
	for b := 0; b < bursts; b++ {
		for i := 0; i < framesPer; i++ {
			if err := conn.Write(ctx, websocket.MessageBinary, frame); err != nil {
				t.Fatalf("write đợt %d: %v", b, err)
			}
			time.Sleep(10 * time.Millisecond)
		}
		// Lặng 200ms: dài hơn SilenceMS=100 (bản đúng cắt được) nhưng ngắn hơn ASR 600ms
		// (đợt sau đến đúng lúc vòng lặp bị chặn, nếu ASR chạy đồng bộ).
		time.Sleep(200 * time.Millisecond)
	}

	// Đủ để worker xử nốt hàng đợi (tối đa 2 câu đang chờ × 600ms).
	time.Sleep(2500 * time.Millisecond)

	got := asr.snapshot()
	if len(got) == 0 {
		t.Fatal("không utterance nào tới ASR")
	}

	// Không utterance nào được to hơn MỘT đợt. WAV header 44 byte + phần bao multipart ~400 byte;
	// hai đợt gộp lại là 6400 byte, vượt xa ngưỡng này.
	maxBody := framesPer*frameBytes + 44 + 800
	for i, n := range got {
		if n > maxBody {
			t.Errorf("utterance %d dài %d byte > %d — nhiều đợt bị gộp vào một câu vì vòng select "+
				"bị lời gọi ASR chặn (sizes=%v)", i, n, maxBody, got)
		}
	}
}
