// Package events định nghĩa payload MQTT theo contract firmware/mqtt/README.md.
package events

// Motion — home/door/motion
type Motion struct {
	TS     int64 `json:"ts"`
	Motion bool  `json:"motion"`
}

// Presence — home/room/presence
type Presence struct {
	TS      int64 `json:"ts"`
	Present bool  `json:"present"`
}

// SnoreEvent — home/room/snore_event.
//
// TS is voice-node millis() uptime, not epoch time: the firmware has not synced
// NTP before publishing this event. Backend stamps receive time; TS is only for
// ordering events from the board and spotting resets when the value drops.
type SnoreEvent struct {
	TS         uint64  `json:"ts"`
	Confidence float64 `json:"confidence"`
	DurationMS uint32  `json:"duration_ms"`
}

// Sample — home/room/sample. Frame 10Hz chuẩn Phase 01, schema khớp CSV take-home:
//
//	t, presence, hr_bpm, resp_amplitude, motion, weight_kg, spo2, temp_c, humidity
//
// Giữ THÊM kênh raw của LD2410 (moving/still distance+energy) và cờ lỗi uart_ok để
// downstream biết mẫu nào là dữ liệu thật. Cảm biến không đo được kênh nào thì ghi 0
// (kèm cờ), KHÔNG bịa số.
//
// TS: epoch MILI-giây, gắn tại MCU (net_epoch_ms) — không gắn ở Linux.
type Sample struct {
	TS            int64   `json:"t"`              // epoch ms, gắn tại MCU
	Presence      bool    `json:"presence"`       // có người (OUT hoặc UART thấy mục tiêu)
	HRBpm         int     `json:"hr_bpm"`         // 0 = không đo được (radar không cho HR)
	RespAmplitude float64 `json:"resp_amplitude"` // 0 = không đo được
	Motion        int     `json:"motion"`         // 0/1: radar thấy cử động
	WeightKg      float64 `json:"weight_kg"`      // 0 = không đo được (không phải loadcell)
	Spo2          int     `json:"spo2"`           // 0 = không đo được
	TempC         float64 `json:"temp_c"`         // 0 = không đo được (không có SHT trên node này)
	Humidity      float64 `json:"humidity"`       // 0 = không đo được

	// Kênh raw radar — lưu tất cả, kể cả chưa ai dùng (yêu cầu framework).
	MovingDistCm int `json:"moving_dist_cm"`
	MovingEnergy int `json:"moving_energy"`
	StillDistCm  int `json:"still_dist_cm"`
	StillEnergy  int `json:"still_energy"`

	// Cờ lỗi: uart_ok=false = UART radar chết/không có khung hợp lệ (dropout).
	// presence vẫn đáng tin nếu chân OUT OK; các kênh số liệu còn lại KHÔNG đáng tin.
	UARTOK bool `json:"uart_ok"`

	// Seq tăng 1 mỗi mẫu MCU dựng; Boot tăng 1 mỗi lần MCU khởi động (lưu NVS).
	// Không có hai trường này thì tỷ lệ mất mẫu vẫn tính được nhưng không truy được
	// nguyên nhân: seq thủng lỗ với t liền mạch = mất trên đường; seq liền với t nhảy
	// quãng = MCU trượt nhịp; boot tăng = MCU reset.
	//
	// Con trỏ chứ không phải giá trị: nil = firmware chưa có bộ đếm, khác hẳn 0 = mẫu
	// đầu tiên sau khi khởi động.
	Seq  *uint32 `json:"seq"`
	Boot *uint32 `json:"boot"`
}
