// Package config nạp cấu hình từ biến môi trường.
package config

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

type Config struct {
	MQTTHost     string
	MQTTPort     int
	MQTTUser     string
	MQTTPass     string
	MQTTClientID string

	EnterWindow time.Duration // motion→presence trong khoảng này mới coi là vào
	ExitTimeout time.Duration // presence=false giữ đủ lâu → coi là ra

	HTTPAddr string
	DBPath   string // file SQLite lưu lịch sử event; rỗng = tắt lịch sử
}

func Load() (Config, error) {
	c := Config{
		MQTTHost:     getenv("MQTT_HOST", ""),
		MQTTPort:     getenvInt("MQTT_PORT", 1883),
		MQTTUser:     getenv("MQTT_USER", ""),
		MQTTPass:     getenv("MQTT_PASS", ""),
		MQTTClientID: getenv("MQTT_CLIENT_ID", "home-backend"),
		EnterWindow:  time.Duration(getenvInt("ENTER_WINDOW_S", 15)) * time.Second,
		ExitTimeout:  time.Duration(getenvInt("EXIT_TIMEOUT_S", 60)) * time.Second,
		HTTPAddr:     getenv("HTTP_ADDR", ":8080"),
		DBPath:       lookupOr("DB_PATH", "/data/home.db"),
	}
	if c.MQTTHost == "" || c.MQTTUser == "" || c.MQTTPass == "" {
		return c, fmt.Errorf("MQTT_HOST, MQTT_USER, MQTT_PASS là bắt buộc")
	}
	return c, nil
}

// VoiceConfig — cấu hình đường voice (service ASR + tham số VAD). Tách khỏi Config chính vì
// không có biến bắt buộc (đều có default hợp lý) và router.go cần gọi độc lập, không phụ thuộc
// main.go phải truyền thêm cfg qua NewRouter (giữ nguyên chữ ký NewRouter hiện có).
type VoiceConfig struct {
	ASRURL        string // endpoint POST WAV (multipart) -> {"text":...} của service faster-whisper
	ASRSilenceMS  int    // im lặng bao lâu (ms) thì coi là hết câu (VAD end-of-utterance)
	ASRMaxUtterMS int    // trần thời lượng 1 utterance (ms) — tránh giữ buffer vô hạn
	ASRMinUtterMS int    // SÀN thời lượng (ms) — ngắn hơn thì bỏ, không gọi ASR
	SampleRate    int    // sample rate PCM voice node gửi lên (Hz)

	// Thu dữ liệu huấn luyện (công cụ, KHÔNG phải đường chạy thật). Rỗng = tắt hẳn, endpoint
	// /api/voice/record không được đăng ký. Bật bằng cách trỏ VOICE_RECORD_DIR vào một volume.
	RecordDir      string
	RecordSegmentS int // cắt WAV thành từng đoạn bao nhiêu giây (mặc định 60)
}

// LoadVoice nạp cấu hình voice/ASR từ biến môi trường. Không có biến bắt buộc (khác Load() ở
// trên) nên luôn trả về giá trị dùng được, kể cả khi ASR_* chưa được set (test/dev không cần
// khai báo thêm env).
func LoadVoice() VoiceConfig {
	return VoiceConfig{
		ASRURL:        getenv("ASR_URL", "http://asr:9000/transcribe"),
		ASRSilenceMS:  getenvInt("ASR_SILENCE_MS", 800),
		ASRMaxUtterMS: getenvInt("ASR_MAX_UTTER_MS", 8000),
		// Sàn 300ms: whisper nhại lại INITIAL_PROMPT khi audio gần im, và câu nhại chứa động từ
		// nên ParseVietCommand khớp rồi bắn IR thật (đo 07/08: 8 lần bắn từ câu nhại). Lọc theo
		// VĂN BẢN không tách được "nhại thuần" với "lệnh thật bị prompt bám vào"; lọc theo ĐỘ DÀI
		// thì không phải đoán. "bật điều hòa" nói bình thường ~800ms, nên 300 chỉ cắt tiếng động
		// vụn. Đặt thấp có chủ ý — nâng lên sau khi có số đo thật từ log `utter_ms`.
		ASRMinUtterMS: getenvInt("ASR_MIN_UTTER_MS", 300),
		SampleRate:    getenvInt("VOICE_SAMPLE_RATE", 16000),

		RecordDir:      getenv("VOICE_RECORD_DIR", ""),
		RecordSegmentS: getenvInt("VOICE_RECORD_SEGMENT_S", 60),
	}
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

// lookupOr phân biệt "không khai báo" với "khai báo rỗng" — khác getenv coi cả hai là
// chưa đặt. Cần cho DB_PATH: đặt DB_PATH= (rỗng, có chủ ý) phải TẮT được lịch sử,
// trong khi không khai báo thì dùng đường dẫn mặc định.
func lookupOr(k, def string) string {
	if v, ok := os.LookupEnv(k); ok {
		return v
	}
	return def
}

func getenvInt(k string, def int) int {
	if v := os.Getenv(k); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}
