package voice

import (
	"bytes"
	"context"
	"encoding/binary"
	"log/slog"
	"net/http"
	"time"

	"github.com/coder/websocket"
)

const (
	bytesPerSample = 2 // PCM 16-bit
	channels       = 1 // mono

	// 10s -> 30s (31/07). Đo thật trên máy này: faster-whisper "small" mất 7.1s cho một câu 2.3s
	// khi máy RẢNH. Biên chỉ còn 2.9s, nên máy vừa bận (cắt lát in 3D) là hạn vỡ ngay.
	//
	// Không phải nới hạn để che lỗi — công việc VẪN HOÀN THÀNH ĐÚNG, chỉ là kết quả về muộn hơn
	// hạn nên bị vứt. Log 31/07: backend bỏ cuộc lúc 07:32:21, ASR trả đúng "Tắt máy lạnh." lúc
	// 07:32:35. Tệ hơn, bỏ cuộc KHÔNG dừng được việc bên ASR (tiến trình CPU-bound, uvicorn không
	// hủy giữa chừng): nó tiếp tục ngốn ~5 lõi cho một request đã chết, làm câu kế tiếp cũng trễ
	// và cũng timeout — vòng lặp tự nuôi, kéo dài 07:25→07:32 chứ không tự thoát.
	//
	// An toàn vì handleUtterance đã chạy ở goroutine worker riêng: ASR chậm không còn chặn vòng
	// select đọc frame. Cái giá là lệnh có thể tới muộn; firmware đã có nhịp IR + khoá lệnh tay
	// nên lệnh muộn không gây hại.
	asrTimeout = 30 * time.Second

	// silenceCheckInterval — nhịp kiểm tra "đã im lặng đủ lâu chưa" để cắt utterance.
	// Tách khỏi conn.Read vì coder/websocket ĐÓNG kết nối nếu context của Read hết hạn —
	// không thể dùng read-deadline để dò im lặng mà vẫn giữ WS mở.
	silenceCheckInterval = 100 * time.Millisecond
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
	MinUtterMS int    // SÀN thời lượng (ms) — ngắn hơn thì bỏ, không gọi ASR
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
// im lặng (nhưng GIỮ WS mở). Backend gom mọi frame nhận được vào utterance hiện tại; điểm hết câu
// là "không có frame mới trong SilenceMS". KHÔNG thể dùng read-deadline (context.WithTimeout cho
// conn.Read) để dò im lặng: coder/websocket đóng kết nối khi context Read hết hạn. Thay vào đó
// đọc trong goroutine riêng bằng context nền (chỉ lỗi khi kết nối đóng thật), còn vòng chính dùng
// ticker định kỳ để phát hiện khoảng lặng và flush utterance. Trần MaxUtterMS + trần byte vẫn giữ
// để chặn buffer phình vô hạn.
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

	// Đọc frame trong goroutine với context nền (kết nối) — conn.Read chỉ lỗi khi WS đóng thật,
	// không bao giờ vì read-deadline (nên WS không bị đóng lúc im lặng).
	frames := make(chan []byte, 16)
	readDone := make(chan struct{})
	go func() {
		defer close(readDone)
		for {
			msgType, data, err := conn.Read(ctx)
			if err != nil {
				return
			}
			if msgType != websocket.MessageBinary || len(data) == 0 {
				continue // node chỉ được kỳ vọng gửi binary PCM
			}
			select {
			case frames <- data:
			case <-ctx.Done():
				return
			}
		}
	}()

	// ASR chạy trong goroutine RIÊNG, không gọi thẳng trong vòng select dưới đây.
	//
	// Lý do (đo 31/07): faster-whisper "small" trên CPU này mất 7.1s cho câu 2.3s. Khi gọi đồng bộ
	// trong select thì suốt 7s đó vòng lặp không đọc frames và ticker không chạy — tiếng nói vẫn
	// dồn vào channel, rồi được nạp một lượt trong vài mili-giây. Hệ quả: điều kiện cắt theo
	// wall-clock (MaxUtterMS) KHÔNG BAO GIỜ đúng vì mọi chunk mang cùng một mốc now, và
	// flushIfSilent cũng không có cơ hội chạy. Đo được utterance dài dần 8.0 -> 10.8 -> 11.6 ->
	// 13.6s, mỗi file dính 3-4 câu — đúng dạng vòng lặp tự khuếch đại.
	//
	// Tác hại thật, không chỉ lúc thu mẫu: nói "tắt điều hòa" ngay sau "bật điều hòa" thì hai câu
	// dính vào một utterance chứa cả hai động từ -> ParseVietCommand loại vì mơ hồ -> không lệnh nào
	// chạy, trong khi người dùng đã nói rõ ràng.
	utterances := make(chan []byte, 1)
	defer close(utterances) // worker xử nốt phần còn lại rồi tự thoát, không chặn ServeHTTP
	go func() {
		// context.Background() chứ không phải r.Context(): câu cuối phải xử xong kể cả khi kết nối
		// đã đóng. handleUtterance tự bọc asrTimeout nên vẫn có giới hạn.
		for pcm := range utterances {
			h.handleUtterance(context.Background(), pcm)
		}
	}()

	ticker := time.NewTicker(silenceCheckInterval)
	defer ticker.Stop()

	for {
		select {
		case data := <-frames:
			if utterance, cut := buf.feed(data, time.Now()); cut {
				enqueueUtterance(utterances, utterance)
			}
		case <-ticker.C:
			// Hết câu = im lặng (không frame mới) đủ SilenceMS trong khi đang gom.
			if utterance, cut := buf.flushIfSilent(time.Now(), silenceLimit); cut {
				enqueueUtterance(utterances, utterance)
			}
		case <-readDone:
			// Kết nối đóng thật -> flush câu dở dang lần cuối.
			if pcm := buf.reset(); len(pcm) > 0 {
				enqueueUtterance(utterances, pcm)
			}
			return
		case <-ctx.Done():
			return
		}
	}
}

// enqueueUtterance đẩy utterance sang worker ASR. Hàng đợi chỉ 1 slot: đầy nghĩa là ASR còn bận câu
// trước, khi đó BỎ câu CŨ và giữ câu MỚI.
//
// Giữ câu mới là đúng ngữ nghĩa cho thiết bị chấp hành: lệnh điều hoà chỉ có trạng thái CUỐI là có
// nghĩa, thi hành một lệnh đã 15 giây tuổi là làm ngược ý người nói. Cùng nguyên tắc với ô chờ IR
// một slot bên firmware voice-node. Hàng đợi không giới hạn thì độ trễ dồn vô hạn.
//
// Chỉ vòng select gọi hàm này nên sau khi rút bớt một phần tử là chắc chắn còn chỗ để đẩy vào.
func enqueueUtterance(q chan []byte, pcm []byte) {
	select {
	case q <- pcm:
		return
	default:
	}
	select {
	case <-q:
		slog.Warn("voice: ASR chưa xử lý kịp, bỏ utterance cũ để giữ câu mới nhất")
	default:
	}
	select {
	case q <- pcm:
	default:
	}
}

// handleUtterance build WAV từ pcm gom được, gọi ASR, parse lệnh rồi publish.
func (h *Handler) handleUtterance(ctx context.Context, pcm []byte) {
	if len(pcm) == 0 {
		return
	}

	// Ghi độ dài MỌI utterance, kể cả cái bị bỏ. Không có con số này thì không cách nào chọn
	// ngưỡng có căn cứ — chỉ đoán.
	utterMS := len(pcm) * 1000 / (h.cfg.SampleRate * 2) // PCM16 mono: 2 byte/mẫu

	// Sàn thời lượng: clip quá ngắn làm whisper nhại lại INITIAL_PROMPT, mà câu nhại chứa động
	// từ nên ParseVietCommand khớp rồi bắn IR THẬT. Đo 07/08: 8 lần bắn từ câu nhại, trong đó
	// có `"...tắt máy lạnh, tắt máy lạnh."` — lặp hai lần, chắc chắn không phải người nói.
	// Bật/tắt máy nén liên tục là thứ làm hỏng lốc, nên thà bỏ sót một lệnh còn hơn bắn thừa.
	if utterMS < h.cfg.MinUtterMS {
		slog.Info("voice: utterance quá ngắn, bỏ", "utter_ms", utterMS, "san_ms", h.cfg.MinUtterMS)
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
	slog.Info("voice: asr text", "text", text, "utter_ms", utterMS)

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

// feed nạp 1 chunk PCM 16-bit LE nhận được. Vì node đã tự VAD (chỉ gửi khi có tiếng), mọi frame
// tới đây đều là tiếng nói -> gom hết, cập nhật lastVoice. Trả về (utterance, true) khi chạm trần
// MaxUtterMS hoặc trần byte (lưới an toàn); điểm hết-câu-theo-im-lặng do flushIfSilent lo.
func (b *utteranceBuffer) feed(chunk []byte, now time.Time) ([]byte, bool) {
	if !b.talking {
		b.talking = true
		b.startedAt = now
		b.pcm = b.pcm[:0]
	}
	b.lastVoice = now
	b.pcm = append(b.pcm, chunk...)

	maxLimit := time.Duration(b.cfg.MaxUtterMS) * time.Millisecond
	if now.Sub(b.startedAt) >= maxLimit || len(b.pcm) >= b.maxUtterBytes() {
		return b.reset(), true
	}
	return nil, false
}

// flushIfSilent trả về (utterance, true) nếu đang gom mà không có frame mới trong silenceLimit —
// nghĩa là node đã ngừng gửi vì hết câu. Gọi định kỳ từ ticker ở ServeHTTP (không dựa read-deadline).
func (b *utteranceBuffer) flushIfSilent(now time.Time, silenceLimit time.Duration) ([]byte, bool) {
	if b.talking && len(b.pcm) > 0 && now.Sub(b.lastVoice) >= silenceLimit {
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
