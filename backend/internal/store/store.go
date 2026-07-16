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
}

// Open mở (hoặc tạo) DB tại path và migrate schema.
func Open(path string) (*Store, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("mở sqlite %q: %w", path, err)
	}
	// 1 connection: tránh "database is locked" khi MQTT callback và HTTP handler ghi/đọc cùng lúc.
	db.SetMaxOpenConns(1)

	if _, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS events (
			id     INTEGER PRIMARY KEY AUTOINCREMENT,
			ts     INTEGER NOT NULL,
			kind   TEXT    NOT NULL,
			value  TEXT    NOT NULL,
			source TEXT    NOT NULL
		);
		CREATE INDEX IF NOT EXISTS idx_events_id_desc ON events(id DESC);
	`); err != nil {
		db.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}
	return &Store{db: db}, nil
}

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
