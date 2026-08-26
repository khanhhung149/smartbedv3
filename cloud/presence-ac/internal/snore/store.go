// Package snore stores room-level snore detections from voice-node.
//
// This table measures the room, not a specific sleeper or pad. The microphone
// cannot tell who snored, so the schema deliberately has no device_id; add a
// room column if the system later grows beyond one room.
//
// Keep this out of internal/sessions: that package owns the read path for sleep
// sessions, while room_snore_events is a separate write path for MQTT events.
package snore

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

const appendTimeout = 3 * time.Second

// Event is one confirmed room snore event.
type Event struct {
	T          time.Time
	DeviceMS   *int64
	Confidence float64
	DurationMS int
	Source     string
}

// Store writes room snore events to Postgres.
type Store struct {
	db *sql.DB
}

// Open attaches to an existing Postgres pool and creates the owned schema.
func Open(db *sql.DB) (*Store, error) {
	s := &Store{db: db}
	if err := s.ensureSchema(context.Background()); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *Store) ensureSchema(ctx context.Context) error {
	if s == nil || s.db == nil {
		return fmt.Errorf("snore store nil database")
	}
	if _, err := s.db.ExecContext(ctx, `
CREATE TABLE IF NOT EXISTS room_snore_events (
  id          BIGSERIAL PRIMARY KEY,
  t           TIMESTAMPTZ NOT NULL,
  device_ms   BIGINT,
  confidence  REAL        NOT NULL,
  duration_ms INTEGER     NOT NULL,
  source      TEXT        NOT NULL DEFAULT 'voice-node'
)`); err != nil {
		return fmt.Errorf("create room_snore_events: %w", err)
	}
	if _, err := s.db.ExecContext(ctx, `
CREATE INDEX IF NOT EXISTS idx_room_snore_t ON room_snore_events (t DESC)`); err != nil {
		return fmt.Errorf("create idx_room_snore_t: %w", err)
	}
	return nil
}

// Append inserts one snore event. It derives a short timeout from ctx so a slow
// database cannot stall the MQTT callback indefinitely.
func (s *Store) Append(ctx context.Context, ev Event) error {
	if s == nil || s.db == nil {
		return fmt.Errorf("snore store nil database")
	}
	if ev.Source == "" {
		ev.Source = "voice-node"
	}
	if ev.T.IsZero() {
		ev.T = time.Now().UTC()
	}

	ctx, cancel := context.WithTimeout(ctx, appendTimeout)
	defer cancel()

	_, err := s.db.ExecContext(ctx, `
INSERT INTO room_snore_events (t, device_ms, confidence, duration_ms, source)
VALUES ($1, $2, $3, $4, $5)`,
		ev.T, ev.DeviceMS, ev.Confidence, ev.DurationMS, ev.Source)
	if err != nil {
		return fmt.Errorf("insert room_snore_events: %w", err)
	}
	return nil
}

// CountBetween counts confirmed snore events in [from, to). No device_id
// filter — the table has none, see the package comment.
func (s *Store) CountBetween(ctx context.Context, from, to time.Time) (int, error) {
	if s == nil || s.db == nil {
		return 0, fmt.Errorf("snore store nil database")
	}
	var n int
	err := s.db.QueryRowContext(ctx, `
SELECT COUNT(*) FROM room_snore_events WHERE t >= $1 AND t < $2`, from, to).Scan(&n)
	if err != nil {
		return 0, fmt.Errorf("count room_snore_events: %w", err)
	}
	return n, nil
}
