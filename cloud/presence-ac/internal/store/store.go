// Package store lưu lịch sử event (motion/presence/ac_cmd) xuống SQLite để app đọc lại.
// State machine chỉ giữ trạng thái HIỆN TẠI trong RAM và mất sạch khi restart; store là nơi
// duy nhất còn lại dấu vết những gì đã xảy ra.
//
// Dùng modernc.org/sqlite (SQLite thuần Go) thay vì mattn/go-sqlite3: không cần CGO nên
// Dockerfile giữ nguyên build tĩnh, không phải kéo thêm gcc.
package store

import (
	"database/sql"
	"fmt"
	"sync"
	"time"

	_ "modernc.org/sqlite"
)

// Kind — loại event. Giá trị lưu thẳng vào cột kind, app lọc theo đây.
const (
	KindMotion   = "motion"
	KindPresence = "presence"
	KindACCmd    = "ac_cmd"
)

// Event — một dòng lịch sử.
type Event struct {
	ID     int64  `json:"id"`
	TS     int64  `json:"ts"`     // timestamp từ thiết bị (epoch giây, NTP) — 0 nếu backend tự sinh
	Kind   string `json:"kind"`   // motion | presence | ac_cmd
	Value  string `json:"value"`  // "true"/"false" cho motion/presence; "on"/"off" cho ac_cmd
	Source string `json:"source"` // node nào gửi: voice-node | room-node | backend
}

// maxRows — trần số event giữ lại. Vượt thì xoá cũ nhất. Chặn DB phình vô hạn: mỗi lần
// vào/ra phòng sinh vài event, chạy liên tục nhiều tháng vẫn nằm trong ngưỡng này.
const maxRows = 5000

// defaultLimit / maxLimit — phân trang cho List.
const (
	defaultLimit = 50
	maxLimit     = 500
)

type Store struct {
	db *sql.DB
	mu sync.Mutex // SQLite ghi 1 writer; giữ Append tuần tự thay vì để driver trả SQLITE_BUSY

	// Trần mẫu và nhịp cắt. Là field chứ không phải hằng để test hạ ngưỡng xuống —
	// không thể chèn 11 triệu dòng trong một bài test.
	maxSamples   int64
	trimInterval int64
	sinceTrim    int64
}

// Open mở (hoặc tạo) DB tại path và migrate schema.
func Open(path string) (*Store, error) {
	// WAL + synchronous=NORMAL: đường ghi mẫu chạy 10Hz liên tục cả đêm. Rollback journal
	// với synchronous=FULL bắt fsync mỗi commit — không theo kịp, và mẫu mất vì backend
	// chậm sẽ lẫn vào đúng con số tỷ lệ mất mẫu đang cần đo.
	// Đánh đổi: mất điện đột ngột có thể mất các transaction chưa checkpoint. Process crash
	// không mất gì. Chấp nhận được — mất điện giữa đêm làm hỏng bài đo dù cấu hình nào.
	dsn := path + "?_pragma=journal_mode(WAL)&_pragma=synchronous(NORMAL)&_pragma=busy_timeout(5000)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("mở sqlite %q: %w", path, err)
	}
	// 1 connection: tránh "database is locked" khi MQTT callback và HTTP handler ghi/đọc cùng lúc.
	db.SetMaxOpenConns(1)

	// Xác nhận WAL bật thật. Chạy tiếp im lặng ở chế độ chậm là kiểu hỏng khó tìm nhất:
	// mọi thứ vẫn "chạy", chỉ là mất mẫu.
	var journalMode string
	if err := db.QueryRow(`PRAGMA journal_mode`).Scan(&journalMode); err != nil {
		db.Close()
		return nil, fmt.Errorf("đọc journal_mode %q: %w", path, err)
	}
	if journalMode != "wal" {
		db.Close()
		return nil, fmt.Errorf("journal_mode của %q là %q, cần \"wal\"", path, journalMode)
	}

	if _, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS events (
			id     INTEGER PRIMARY KEY AUTOINCREMENT,
			ts     INTEGER NOT NULL,
			kind   TEXT    NOT NULL,
			value  TEXT    NOT NULL,
			source TEXT    NOT NULL
		);
		CREATE INDEX IF NOT EXISTS idx_events_id_desc ON events(id DESC);

		-- Bảng mẫu 10Hz Phase 01: schema khớp CSV take-home
		--   t, presence, hr_bpm, resp_amplitude, motion, weight_kg, spo2, temp_c, humidity
		-- + kênh raw radar (moving/still distance+energy) + cờ lỗi uart_ok.
		-- Lưu TẤT CẢ kênh, kể cả kênh chưa ai dùng (yêu cầu framework).
		CREATE TABLE IF NOT EXISTS samples (
			id          INTEGER PRIMARY KEY AUTOINCREMENT,
			ts          INTEGER NOT NULL,          -- epoch ms, gắn tại MCU
			presence    INTEGER NOT NULL DEFAULT 0,
			hr_bpm      INTEGER NOT NULL DEFAULT 0,
			resp_amp    REAL    NOT NULL DEFAULT 0,
			motion      INTEGER NOT NULL DEFAULT 0,
			weight_kg   REAL    NOT NULL DEFAULT 0,
			spo2        INTEGER NOT NULL DEFAULT 0,
			temp_c      REAL    NOT NULL DEFAULT 0,
			humidity    REAL    NOT NULL DEFAULT 0,
			moving_dist INTEGER NOT NULL DEFAULT 0,
			moving_eng  INTEGER NOT NULL DEFAULT 0,
			still_dist  INTEGER NOT NULL DEFAULT 0,
			still_eng   INTEGER NOT NULL DEFAULT 0,
			uart_ok     INTEGER NOT NULL DEFAULT 0,
			-- seq/boot NULL nghĩa là node gửi mẫu này chạy firmware chưa có bộ đếm.
			-- Nullable chứ không DEFAULT 0: seq=0 là mẫu đầu tiên sau khi khởi động,
			-- gộp hai trạng thái lại làm hỏng phép đếm mất mẫu.
			seq         INTEGER,
			boot        INTEGER
		);
		CREATE INDEX IF NOT EXISTS idx_samples_ts ON samples(ts DESC);
	`); err != nil {
		db.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}

	// DB dựng trước khi có seq/boot không được CREATE TABLE IF NOT EXISTS đụng tới.
	if err := addMissingSampleColumns(db); err != nil {
		db.Close()
		return nil, err
	}

	return &Store{db: db, maxSamples: defaultMaxSamples, trimInterval: defaultTrimInterval}, nil
}

// addMissingSampleColumns thêm cột còn thiếu vào bảng samples đã tồn tại.
// Hỏi table_info trước thay vì ALTER rồi nuốt lỗi: nuốt lỗi giấu luôn cả lỗi thật.
func addMissingSampleColumns(db *sql.DB) error {
	rows, err := db.Query(`PRAGMA table_info(samples)`)
	if err != nil {
		return fmt.Errorf("đọc cột bảng samples: %w", err)
	}
	have := map[string]bool{}
	for rows.Next() {
		var cid int
		var name, ctype string
		var notNull, pk int
		var dflt any
		if err := rows.Scan(&cid, &name, &ctype, &notNull, &dflt, &pk); err != nil {
			rows.Close()
			return fmt.Errorf("scan cột bảng samples: %w", err)
		}
		have[name] = true
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return fmt.Errorf("đọc cột bảng samples: %w", err)
	}

	for _, col := range []string{"seq", "boot"} {
		if have[col] {
			continue
		}
		if _, err := db.Exec(`ALTER TABLE samples ADD COLUMN ` + col + ` INTEGER`); err != nil {
			return fmt.Errorf("thêm cột samples.%s: %w", col, err)
		}
	}
	return nil
}

// defaultMaxSamples — trần mẫu giữ lại. 30 đêm × 10Hz × 3600s = 10.8M mẫu; SQLite dư sức chứa.
const defaultMaxSamples = 11_000_000

// defaultTrimInterval — số mẫu giữa hai lần chạy câu cắt trần. Chạy sau MỖI insert nghĩa là
// nhân đôi số transaction ở 10Hz cho một câu DELETE gần như luôn xoá 0 dòng (trần chỉ chạm
// tới sau ~30 đêm). Giãn ra làm DB vượt trần tối đa từng này dòng — không đáng kể.
const defaultTrimInterval = 10_000

// Append ghi 1 event rồi cắt bớt phần vượt maxRows.
// Lỗi ở đây KHÔNG được làm sập luồng MQTT — caller chỉ log rồi đi tiếp.
func (s *Store) Append(e Event) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, err := s.db.Exec(
		`INSERT INTO events (ts, kind, value, source) VALUES (?, ?, ?, ?)`,
		e.TS, e.Kind, e.Value, e.Source,
	); err != nil {
		return fmt.Errorf("insert event: %w", err)
	}
	// Xoá theo id (tăng đơn điệu) chứ không theo ts: ts đến từ thiết bị, có thể lệch/nhảy lùi
	// khi NTP chưa sync — xoá theo ts sẽ cắt nhầm event mới.
	if _, err := s.db.Exec(
		`DELETE FROM events WHERE id <= (SELECT MAX(id) FROM events) - ?`, maxRows,
	); err != nil {
		return fmt.Errorf("cắt bớt event cũ: %w", err)
	}
	return nil
}

// List trả event mới nhất trước. before>0 → chỉ lấy event có id < before (phân trang tiếp trang).
func (s *Store) List(limit int, before int64) ([]Event, error) {
	if limit <= 0 {
		limit = defaultLimit
	}
	if limit > maxLimit {
		limit = maxLimit
	}

	q := `SELECT id, ts, kind, value, source FROM events`
	args := []any{}
	if before > 0 {
		q += ` WHERE id < ?`
		args = append(args, before)
	}
	q += ` ORDER BY id DESC LIMIT ?`
	args = append(args, limit)

	rows, err := s.db.Query(q, args...)
	if err != nil {
		return nil, fmt.Errorf("query events: %w", err)
	}
	defer rows.Close()

	out := []Event{} // slice rỗng chứ không nil: JSON ra [] thay vì null
	for rows.Next() {
		var e Event
		if err := rows.Scan(&e.ID, &e.TS, &e.Kind, &e.Value, &e.Source); err != nil {
			return nil, fmt.Errorf("scan event: %w", err)
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (s *Store) Close() error { return s.db.Close() }

// DropSamples xoá toàn bộ bảng samples — dùng cho công cụ seed dữ liệu test (cmd/seed-csv).
func (s *Store) DropSamples() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, err := s.db.Exec(`DELETE FROM samples`); err != nil {
		return fmt.Errorf("drop samples: %w", err)
	}
	return nil
}

// Sample — một dòng mẫu 10Hz (schema CSV take-home + kênh raw).
// Copy từ events.Sample để store không phụ thuộc package events.
type Sample struct {
	ID            int64   `json:"id"`
	TS            int64   `json:"t"` // epoch ms, gắn tại MCU
	Presence      bool    `json:"presence"`
	HRBpm         int     `json:"hr_bpm"`
	RespAmplitude float64 `json:"resp_amplitude"`
	Motion        int     `json:"motion"`
	WeightKg      float64 `json:"weight_kg"`
	Spo2          int     `json:"spo2"`
	TempC         float64 `json:"temp_c"`
	Humidity      float64 `json:"humidity"`
	MovingDistCm  int     `json:"moving_dist_cm"`
	MovingEnergy  int     `json:"moving_energy"`
	StillDistCm   int     `json:"still_dist_cm"`
	StillEnergy   int     `json:"still_energy"`
	UARTOK        bool    `json:"uart_ok"`

	// Seq tăng 1 mỗi mẫu MCU dựng; Boot tăng 1 mỗi lần MCU khởi động. Hai trường này tách
	// bạch ba nguyên nhân mất mẫu: seq thủng lỗ với ts liền mạch = mất trên đường; seq liền
	// với ts nhảy quãng = MCU trượt nhịp; boot tăng = MCU reset.
	// nil = firmware chưa có bộ đếm (phân biệt với 0 = mẫu đầu tiên sau khởi động).
	Seq  *uint32 `json:"seq,omitempty"`
	Boot *uint32 `json:"boot,omitempty"`
}

// tsPlausible chặn mốc thời gian vô lý trước khi nó vào DB.
//
// Không phải phòng xa: một mẫu có ts=9999999999999 (năm 2286) đã lọt vào
// home.db thật. Một dòng như thế kéo trục thời gian của mọi biểu đồ ra hàng
// thế kỷ, và vì nó nằm ở max(ts) nên chính các câu truy vấn "mẫu mới nhất"
// vớ phải nó đầu tiên. Chặn ở cửa rẻ hơn nhiều so với đi dọn về sau.
//
// Cận dưới 2020-01-01: MCU chưa đồng bộ NTP báo mốc quanh 1970. Cận trên là
// hiện tại cộng một ngày, đủ rộng cho lệch đồng hồ thật, đủ hẹp để bắt rác.
func tsPlausible(tsMs int64, now time.Time) bool {
	const minMs = 1577836800000 // 2020-01-01T00:00:00Z
	return tsMs >= minMs && tsMs <= now.Add(24*time.Hour).UnixMilli()
}

// AppendSample ghi 1 mẫu 10Hz. Lỗi KHÔNG được làm sập luồng MQTT — caller log rồi đi tiếp.
// Mẫu cũ hơn 30 đêm sẽ bị RetainNights dọn; trần tuyệt đối chống DB phình khi retention lỗi.
func (s *Store) AppendSample(sm Sample) error {
	if !tsPlausible(sm.TS, time.Now()) {
		return fmt.Errorf("loại mẫu có ts vô lý: %d", sm.TS)
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	if _, err := s.db.Exec(
		`INSERT INTO samples
		   (ts, presence, hr_bpm, resp_amp, motion, weight_kg, spo2, temp_c, humidity,
		    moving_dist, moving_eng, still_dist, still_eng, uart_ok, seq, boot)
		 VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
		sm.TS, boolInt(sm.Presence), sm.HRBpm, sm.RespAmplitude, sm.Motion,
		sm.WeightKg, sm.Spo2, sm.TempC, sm.Humidity,
		sm.MovingDistCm, sm.MovingEnergy, sm.StillDistCm, sm.StillEnergy, boolInt(sm.UARTOK),
		u32Arg(sm.Seq), u32Arg(sm.Boot),
	); err != nil {
		return fmt.Errorf("insert sample: %w", err)
	}

	// Cắt trần theo nhịp, không phải mỗi insert — xem defaultTrimInterval.
	s.sinceTrim++
	if s.sinceTrim < s.trimInterval {
		return nil
	}
	s.sinceTrim = 0
	if _, err := s.db.Exec(
		`DELETE FROM samples WHERE id <= (SELECT MAX(id) FROM samples) - ?`, s.maxSamples,
	); err != nil {
		return fmt.Errorf("cắt bớt sample cũ: %w", err)
	}
	return nil
}

// RetainNights xoá mẫu cũ hơn `nights` đêm (theo mốc UTC nửa đêm). Giữ 30 đêm gần nhất.
func (s *Store) RetainNights(nights int) error {
	cutoff := time.Now().UTC().Truncate(24*time.Hour).AddDate(0, 0, -nights).UnixMilli()
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, err := s.db.Exec(`DELETE FROM samples WHERE ts < ?`, cutoff); err != nil {
		return fmt.Errorf("xoá sample quá hạn: %w", err)
	}
	return nil
}

// SamplesBetween trả mẫu trong [fromMs, toMs) — dashboard "xem lại một đêm".
func (s *Store) SamplesBetween(fromMs, toMs int64) ([]Sample, error) {
	rows, err := s.db.Query(
		`SELECT id, ts, presence, hr_bpm, resp_amp, motion, weight_kg, spo2, temp_c, humidity,
		        moving_dist, moving_eng, still_dist, still_eng, uart_ok, seq, boot
		 FROM samples WHERE ts >= ? AND ts < ? ORDER BY ts`,
		fromMs, toMs,
	)
	if err != nil {
		return nil, fmt.Errorf("query samples: %w", err)
	}
	defer rows.Close()

	out := []Sample{}
	for rows.Next() {
		var sm Sample
		var presence, uartOK int
		var seq, boot sql.NullInt64
		if err := rows.Scan(&sm.ID, &sm.TS, &presence, &sm.HRBpm, &sm.RespAmplitude, &sm.Motion,
			&sm.WeightKg, &sm.Spo2, &sm.TempC, &sm.Humidity,
			&sm.MovingDistCm, &sm.MovingEnergy, &sm.StillDistCm, &sm.StillEnergy, &uartOK,
			&seq, &boot); err != nil {
			return nil, fmt.Errorf("scan sample: %w", err)
		}
		sm.Presence = presence != 0
		sm.UARTOK = uartOK != 0
		sm.Seq = nullU32(seq)
		sm.Boot = nullU32(boot)
		out = append(out, sm)
	}
	return out, rows.Err()
}

func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

// u32Arg trả nil (ghi NULL) khi con trỏ rỗng, giữ 0 là một giá trị thật.
func u32Arg(v *uint32) any {
	if v == nil {
		return nil
	}
	return int64(*v)
}

func nullU32(v sql.NullInt64) *uint32 {
	if !v.Valid {
		return nil
	}
	u := uint32(v.Int64)
	return &u
}
