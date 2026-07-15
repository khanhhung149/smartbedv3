package voice

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/coder/websocket"
)

const (
	bytesPerSample = 2 // PCM 16-bit
	channels       = 1 // mono

	// energyThreshold — ngưỡng biên độ trung bình |sample int16| coi là "có tiếng nói".
	// VAD năng lượng đơn giản (không dùng model), đủ cho MVP; xem risk assessment ở plan
	// (dễ cắt câu sai nơi ồn — tune theo mic thực tế qua thử nghiệm, chưa cần cấu hình hóa).
	energyThreshold = 500

	asrTimeout = 10 * time.Second
)

// ACPublisher — interface tối giản publish lệnh AC (mqttclient.Client thỏa mãn qua PublishACCmd;
// api.Publisher cũng thỏa mãn vì method set là superset).
type ACPublisher interface {
	PublishACCmd(cmd string) error
}

// Config — tham số đường voice (nạp từ config.LoadVoice() ở router.go).
type Config struct {
	ASRURL     string // endpoint POST WAV multipart -> {"text":...}
	SilenceMS  int    // im lặng bao lâu (ms) thì coi là hết câu
	MaxUtterMS int    // trần thời lượng 1 utterance (ms), tránh giữ buffer vô hạn khi VAD không cắt được
	SampleRate int    // sample rate PCM voice node gửi lên (Hz), dùng để build header WAV
}

// Handler xử lý WS voice stream: nhận PCM, gom utterance, gọi ASR, parse lệnh, publish AC.
type Handler struct {
	pub ACPublisher
	asr *ASRClient
	cfg Config
}

// NewHandler tạo voice.Handler. pub publish lệnh AC (qua mqttclient hiện có).
func NewHandler(pub ACPublisher, cfg Config) *Handler {
	return &Handler{
		pub: pub,
		asr: NewASRClient(cfg.ASRURL, asrTimeout),
		cfg: cfg,
	}
}

// ServeHTTP — GET /api/voice/stream: nhận PCM 16-bit 16kHz mono LE qua WS binary frame.
//
// Kiến trúc voice node: VAD chạy TRÊN DEVICE — node chỉ gửi frame khi có tiếng, NGỪNG gửi khi
// im lặng. Vì vậy backend không thể chỉ dựa vào "chunk mới tới" để phát hiện hết câu (sẽ không
// bao giờ nhận được frame im lặng). Thay vào đó mỗi lần đọc dùng read-deadline = SilenceMS: nếu
// không có frame mới trong khoảng đó, coi như node đã ngừng gửi vì hết câu -> flush utterance
// đang gom. Trần MaxUtterMS (wall-clock) + trần byte vẫn giữ để chặn buffer phình vô hạn nếu
// node gửi liên tục nhanh hơn SilenceMS hoặc nhanh hơn thời gian thực.
//
// Build WAV, gọi ASR, parse lệnh tiếng Việt rồi publish home/room/ac_cmd. Lỗi ASR/publish -> log
// rồi bỏ qua, KHÔNG đóng kết nối WS (voice node tiếp tục stream được).
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		OriginPatterns: []string{"*"}, // LAN nội bộ, giống pattern hub.serveWS (ws.go)
	})
	if err != nil {
		return
	}
	defer conn.Close(websocket.StatusNormalClosure, "")

	ctx := r.Context()
	buf := newUtteranceBuffer(h.cfg)
	silenceLimit := time.Duration(h.cfg.SilenceMS) * time.Millisecond

	for {
		readCtx, cancel := context.WithTimeout(ctx, silenceLimit)
		msgType, data, err := conn.Read(readCtx)
		timedOut := errors.Is(readCtx.Err(), context.DeadlineExceeded)
		cancel()

		if err != nil {
			// Không có frame mới trong SilenceMS mà ctx cha (kết nối) vẫn còn sống -> KHÔNG phải
			// đóng kết nối, mà là node đã ngừng gửi vì im lặng (VAD trên device) -> hết câu.
			if timedOut && ctx.Err() == nil {
				if pcm := buf.reset(); len(pcm) > 0 {
					h.handleUtterance(ctx, pcm)
				}
				continue
			}
			// Kết nối đóng thật (client rớt / lỗi mạng / server shutdown) -> flush câu dở dang
			// lần cuối rồi thoát. Dùng context.Background() làm cha vì r.Context() có thể đã hủy;
			// handleUtterance tự bọc timeout riêng (asrTimeout) nên vẫn có giới hạn thời gian.
			if pcm := buf.reset(); len(pcm) > 0 {
				h.handleUtterance(context.Background(), pcm)
			}
			return
		}

		if msgType != websocket.MessageBinary || len(data) == 0 {
			continue // bỏ qua frame text/rỗng (node chỉ được kỳ vọng gửi binary PCM)
		}

		utterance, cut := buf.feed(data, time.Now())
		if cut {
			h.handleUtterance(ctx, utterance)
		}
	}
}

// handleUtterance build WAV từ pcm gom được, gọi ASR, parse lệnh rồi publish.
func (h *Handler) handleUtterance(ctx context.Context, pcm []byte) {
	if len(pcm) == 0 {
		return
	}
	wav := buildWAV(pcm, h.cfg.SampleRate)

	tctx, cancel := context.WithTimeout(ctx, asrTimeout)
	defer cancel()

	text, err := h.asr.Transcribe(tctx, wav)
	if err != nil {
		slog.Warn("voice: asr lỗi, bỏ qua utterance", "err", err)
		return
	}
	slog.Info("voice: asr text", "text", text)

	cmd, ok := ParseVietCommand(text)
	if !ok {
		slog.Info("voice: không khớp lệnh AC, bỏ qua", "text", text)
		return
	}
	if err := h.pub.PublishACCmd(cmd); err != nil {
		slog.Warn("voice: publish ac_cmd lỗi", "err", err, "cmd", cmd)
		return
	}
	slog.Info("voice: published ac_cmd", "cmd", cmd)
}

// utteranceBuffer gom chunk PCM theo utterance dựa trên VAD năng lượng: bắt đầu khi có tiếng,
// cắt khi im lặng đủ lâu (SilenceMS) hoặc khi vượt trần MaxUtterMS (tránh giữ buffer vô hạn
// nếu VAD không bắt được điểm dừng — ví dụ nhiễu nền liên tục).
type utteranceBuffer struct {
	cfg       Config
	pcm       []byte
	talking   bool
	lastVoice time.Time
	startedAt time.Time
}

func newUtteranceBuffer(cfg Config) *utteranceBuffer {
	return &utteranceBuffer{cfg: cfg}
}

// feed nạp 1 chunk PCM 16-bit LE. Trả về (utterance, true) khi phát hiện hết câu — buffer tự
// reset sau khi trả để sẵn sàng utterance kế tiếp. Chưa đủ điều kiện cắt -> (nil, false).
// Lưu ý: cắt câu theo "im lặng" chủ yếu xảy ra ở ServeHTTP (read-deadline, vì node ngừng gửi
// khi im lặng nên feed() không nhận được chunk im để tự phát hiện) — feed() chỉ còn giữ điều
// kiện MaxUtterMS/trần byte làm lưới an toàn thứ hai, và kiểm tra năng lượng chunk phòng khi
// node vẫn lọt vài frame năng lượng thấp.
func (b *utteranceBuffer) feed(chunk []byte, now time.Time) ([]byte, bool) {
	loud := chunkEnergy(chunk) >= energyThreshold

	if loud {
		if !b.talking {
			b.talking = true
			b.startedAt = now
			b.pcm = b.pcm[:0]
		}
		b.lastVoice = now
	}

	if !b.talking {
		return nil, false // im lặng trước khi có tiếng nói — bỏ, không giữ buffer vô ích
	}

	b.pcm = append(b.pcm, chunk...)

	silenceLimit := time.Duration(b.cfg.SilenceMS) * time.Millisecond
	maxLimit := time.Duration(b.cfg.MaxUtterMS) * time.Millisecond
	silence := now.Sub(b.lastVoice)
	total := now.Sub(b.startedAt)

	if (!loud && silence >= silenceLimit) || total >= maxLimit || len(b.pcm) >= b.maxUtterBytes() {
		return b.reset(), true
	}
	return nil, false
}

// reset trả về pcm hiện tại và đưa buffer về trạng thái rảnh (chưa nói) — dùng khi flush
// utterance, dù do cắt câu bình thường (feed), do im lặng quá SilenceMS không có frame mới, hay
// khi kết nối đóng (ServeHTTP). Buffer rỗng/chưa nói -> trả về pcm rỗng, không phải nil khác biệt
// gì về mặt xử lý (caller chỉ check len>0).
func (b *utteranceBuffer) reset() []byte {
	out := b.pcm
	b.pcm = nil
	b.talking = false
	return out
}

// maxUtterBytes — trần theo byte song song với trần wall-clock (MaxUtterMS), phòng khi client
// gửi dữ liệu nhanh hơn thời gian thực (vd replay file WAV) khiến wall-clock chưa tới hạn nhưng
// buffer đã phình to bất thường. safetyFactor nới thêm biên để không cắt non-realtime quá sớm.
func (b *utteranceBuffer) maxUtterBytes() int {
	const safetyFactor = 2
	bytesPerMS := b.cfg.SampleRate * bytesPerSample * channels / 1000
	return b.cfg.MaxUtterMS * bytesPerMS * safetyFactor
}

// chunkEnergy tính biên độ trung bình tuyệt đối các sample int16 LE trong chunk — heuristic VAD
// đơn giản (YAGNI, chưa cần model VAD phức tạp).
func chunkEnergy(chunk []byte) int {
	n := len(chunk) / bytesPerSample
	if n == 0 {
		return 0
	}
	var sum int64
	for i := 0; i < n; i++ {
		s := int16(binary.LittleEndian.Uint16(chunk[i*2 : i*2+2]))
		if s < 0 {
			s = -s
		}
		sum += int64(s)
	}
	return int(sum / int64(n))
}

// buildWAV bọc pcm (16-bit mono LE) bằng header WAV chuẩn 44 byte — tự viết, không cần lib ngoài.
func buildWAV(pcm []byte, sampleRate int) []byte {
	const bitsPerSample = 16
	byteRate := sampleRate * channels * bitsPerSample / 8
	blockAlign := channels * bitsPerSample / 8
	dataLen := len(pcm)

	var buf bytes.Buffer
	buf.Grow(44 + dataLen)
	buf.WriteString("RIFF")
	_ = binary.Write(&buf, binary.LittleEndian, uint32(36+dataLen))
	buf.WriteString("WAVE")
	buf.WriteString("fmt ")
	_ = binary.Write(&buf, binary.LittleEndian, uint32(16)) // kích thước chunk fmt (PCM)
	_ = binary.Write(&buf, binary.LittleEndian, uint16(1))  // audio format = 1 (PCM)
	_ = binary.Write(&buf, binary.LittleEndian, uint16(channels))
	_ = binary.Write(&buf, binary.LittleEndian, uint32(sampleRate))
	_ = binary.Write(&buf, binary.LittleEndian, uint32(byteRate))
	_ = binary.Write(&buf, binary.LittleEndian, uint16(blockAlign))
	_ = binary.Write(&buf, binary.LittleEndian, uint16(bitsPerSample))
	buf.WriteString("data")
	_ = binary.Write(&buf, binary.LittleEndian, uint32(dataLen))
	buf.Write(pcm)
	return buf.Bytes()
}
