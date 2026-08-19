// Package sessions implements the sleep-session read path against
// TimescaleDB (sec_data / min_data / sleep_sessions) in the same backend
// binary that already serves radar/AC.
//
// The time axis is the `time` column throughout. `time` is stamped by the
// backend on ingest — the pad's own clock never reaches the database. Do not
// wrap it in COALESCE(received_at, time): that expression loses the index
// range scan and defeats TimescaleDB chunk exclusion.
package sessions

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

// SessionRow is one row of sleep_sessions as read by the API.
// JSON tags match the FastAPI contract the app already parses (snake_case).
type SessionRow struct {
	ID                string     `json:"id"`
	DeviceID          string     `json:"device_id"`
	StartedAt         time.Time  `json:"started_at"`
	EndedAt           *time.Time `json:"ended_at"`
	DurationS         *int64     `json:"duration_s"`
	HRAvg             *float64   `json:"hr_avg"`
	HRMin             *int64     `json:"hr_min"`
	HRMax             *int64     `json:"hr_max"`
	RRAvg             *float64   `json:"rr_avg"`
	MovementTotal     *int64     `json:"movement_total"`
	SnoreTotal        *int64     `json:"snore_total"`
	RespDisorderTotal *int64     `json:"resp_disorder_total"`
	SitUpCount        *int64     `json:"sit_up_count"`
	WakeCount         *int64     `json:"wake_count"`
}

// TimelinePoint is one bucketed minute of a night, as the detail screen draws.
// JSON tags match the FastAPI TimelinePoint contract.
type TimelinePoint struct {
	T            time.Time `json:"t"`
	HR           *float64  `json:"hr"`
	RR           *float64  `json:"rr"`
	Movement     *int64    `json:"movement"`
	Snore        *int64    `json:"snore"`
	RespDisorder *int64    `json:"resp_disorder"`
	BedState     string    `json:"bed_state"` // "on_bed" | "off_bed"
	Events       []int     `json:"events"`
}

// PGStore reads sleep sessions from Postgres/TimescaleDB.
type PGStore struct {
	db *sql.DB
}

// NewPGStore opens a pool. Caller closes it.
func NewPGStore(ctx context.Context, url string) (*PGStore, error) {
	db, err := sql.Open("pgx", url)
	if err != nil {
		return nil, fmt.Errorf("mở Postgres: %w", err)
	}
	if err := db.PingContext(ctx); err != nil {
		db.Close()
		return nil, fmt.Errorf("ping Postgres: %w", err)
	}
	return &PGStore{db: db}, nil
}

// Close releases the pool.
func (s *PGStore) Close() error { return s.db.Close() }

// DB exposes the underlying pool for the rebuild loop.
func (s *PGStore) DB() *sql.DB { return s.db }

// ListSessions mirrors service.list_sessions: newest first, optional bounds.
func (s *PGStore) ListSessions(ctx context.Context, deviceID string, start, end *time.Time, limit int) ([]SessionRow, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, device_id, started_at, ended_at, duration_s,
		       hr_avg, hr_min, hr_max, rr_avg,
		       movement_total, snore_total, resp_disorder_total,
		       sit_up_count, wake_count
		FROM sleep_sessions
		WHERE device_id = $1
		  AND ($2::timestamptz IS NULL OR started_at >= $2)
		  AND ($3::timestamptz IS NULL OR started_at <  $3)
		ORDER BY started_at DESC
		LIMIT $4`,
		deviceID, start, end, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []SessionRow
	for rows.Next() {
		var r SessionRow
		if err := rows.Scan(
			&r.ID, &r.DeviceID, &r.StartedAt, &r.EndedAt, &r.DurationS,
			&r.HRAvg, &r.HRMin, &r.HRMax, &r.RRAvg,
			&r.MovementTotal, &r.SnoreTotal, &r.RespDisorderTotal,
			&r.SitUpCount, &r.WakeCount,
		); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// GetSession loads one session by id.
func (s *PGStore) GetSession(ctx context.Context, id string) (*SessionRow, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT id, device_id, started_at, ended_at, duration_s,
		       hr_avg, hr_min, hr_max, rr_avg,
		       movement_total, snore_total, resp_disorder_total,
		       sit_up_count, wake_count
		FROM sleep_sessions WHERE id = $1`, id)
	var r SessionRow
	if err := row.Scan(
		&r.ID, &r.DeviceID, &r.StartedAt, &r.EndedAt, &r.DurationS,
		&r.HRAvg, &r.HRMin, &r.HRMax, &r.RRAvg,
		&r.MovementTotal, &r.SnoreTotal, &r.RespDisorderTotal,
		&r.SitUpCount, &r.WakeCount,
	); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &r, nil
}

// LoadSamples reads per-second rows in [start, end) ordered by time.
func (s *PGStore) LoadSamples(ctx context.Context, deviceID string, start, end time.Time) ([]Sample, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT time, heart_rate, resp_rate, status
		FROM sec_data
		WHERE device_id = $1 AND time >= $2 AND time < $3
		ORDER BY time`,
		deviceID, start, end)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Sample
	for rows.Next() {
		var sm Sample
		var hr sql.NullInt64
		var rr sql.NullFloat64
		var st sql.NullInt64
		if err := rows.Scan(&sm.T, &hr, &rr, &st); err != nil {
			return nil, err
		}
		if hr.Valid {
			v := int32(hr.Int64)
			sm.HR = &v
		}
		if rr.Valid {
			v := rr.Float64
			sm.RR = &v
		}
		if st.Valid {
			v := int32(st.Int64)
			sm.Status = &v
		}
		out = append(out, sm)
	}
	return out, rows.Err()
}

// summarizeRow carries the aggregated metrics for one window.
type summarizeRow struct {
	HRAvg             *float64
	HRMin             *int64
	HRMax             *int64
	RRAvg             *float64
	MovementTotal     *int64
	SnoreTotal        *int64
	RespDisorderTotal *int64
}

// Summarize aggregates min_data over one session window. FILTER (WHERE ... > 0)
// is mandatory, not cosmetic: p.4 2.4.1 says the pad reports 0 when it cannot
// measure, so averaging those in would drag every night's heart rate toward
// zero in proportion to time spent out of bed.
func (s *PGStore) Summarize(ctx context.Context, deviceID string, start, end time.Time) (*summarizeRow, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT (AVG(heart_rate) FILTER (WHERE heart_rate > 0))::real AS hr_avg,
		       MIN(heart_rate) FILTER (WHERE heart_rate > 0)         AS hr_min,
		       MAX(heart_rate) FILTER (WHERE heart_rate > 0)         AS hr_max,
		       (AVG(resp_rate)  FILTER (WHERE resp_rate  > 0))::real  AS rr_avg,
		       SUM(movement)::int      AS movement_total,
		       SUM(snore_count)::int   AS snore_total,
		       SUM(resp_disorder)::int AS resp_disorder_total
		FROM min_data
		WHERE device_id = $1 AND time >= $2 AND time < $3`,
		deviceID, start, end)
	var r summarizeRow
	if err := row.Scan(
		&r.HRAvg, &r.HRMin, &r.HRMax, &r.RRAvg,
		&r.MovementTotal, &r.SnoreTotal, &r.RespDisorderTotal,
	); err != nil {
		return nil, err
	}
	return &r, nil
}

// Upsert writes or updates one session idempotently on (device_id, started_at).
func (s *PGStore) Upsert(ctx context.Context, deviceID string, w SessionWindow, sm *summarizeRow, end time.Time) error {
	var duration *int64
	if w.EndedAt != nil {
		d := int64(w.EndedAt.Sub(w.StartedAt).Seconds())
		duration = &d
	}
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO sleep_sessions
		  (device_id, started_at, ended_at, duration_s,
		   hr_avg, hr_min, hr_max, rr_avg,
		   movement_total, snore_total, resp_disorder_total,
		   sit_up_count, wake_count, computed_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, now())
		ON CONFLICT (device_id, started_at) DO UPDATE SET
		  ended_at            = EXCLUDED.ended_at,
		  duration_s          = EXCLUDED.duration_s,
		  hr_avg              = EXCLUDED.hr_avg,
		  hr_min              = EXCLUDED.hr_min,
		  hr_max              = EXCLUDED.hr_max,
		  rr_avg              = EXCLUDED.rr_avg,
		  movement_total      = EXCLUDED.movement_total,
		  snore_total         = EXCLUDED.snore_total,
		  resp_disorder_total = EXCLUDED.resp_disorder_total,
		  sit_up_count        = EXCLUDED.sit_up_count,
		  wake_count          = EXCLUDED.wake_count,
		  computed_at         = now()`,
		deviceID, w.StartedAt, w.EndedAt, duration,
		sm.HRAvg, sm.HRMin, sm.HRMax, sm.RRAvg,
		sm.MovementTotal, sm.SnoreTotal, sm.RespDisorderTotal,
		int64(w.SitUpCount), int64(w.WakeCount))
	return err
}

// RebuildDevice recomputes this device's sessions over [since, now] and upserts
// them. Returns how many windows were written.
func (s *PGStore) RebuildDevice(ctx context.Context, deviceID string, since, now time.Time, opts BuildOptions) (int, error) {
	samples, err := s.LoadSamples(ctx, deviceID, since, now)
	if err != nil {
		return 0, err
	}
	if len(samples) == 0 {
		return 0, nil
	}
	windows := BuildSessions(samples, opts)
	for _, w := range windows {
		end := now
		if w.EndedAt != nil {
			end = *w.EndedAt
		}
		sm, err := s.Summarize(ctx, deviceID, w.StartedAt, end)
		if err != nil {
			return 0, err
		}
		if err := s.Upsert(ctx, deviceID, w, sm, end); err != nil {
			return 0, err
		}
	}
	return len(windows), nil
}

// ActiveDeviceIDs lists devices that produced data since `since`.
func (s *PGStore) ActiveDeviceIDs(ctx context.Context, since time.Time) ([]string, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT DISTINCT device_id FROM sec_data WHERE time >= $1`, since)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

// GetTimeline builds the bucketed series for one night. `interval` is a
// server-owned constant (e.g. "'1 minute'"), never a value from the query
// string — it is interpolated because time_bucket() takes an interval literal,
// not a bind parameter.
//
// Buckets with no rows are simply absent from the result. That is deliberate:
// the app draws a hole where data is missing rather than joining across it,
// because a line spanning a 40-minute dropout is a reading nobody took.
func (s *PGStore) GetTimeline(ctx context.Context, deviceID string, start time.Time, end *time.Time, interval string) ([]TimelinePoint, error) {
	stop := time.Now().UTC()
	if end != nil {
		stop = *end
	}

	minuteRows, err := s.db.QueryContext(ctx, fmt.Sprintf(`
		SELECT time_bucket('%s', time) AS t,
		       (AVG(heart_rate) FILTER (WHERE heart_rate > 0))::real AS hr,
		       (AVG(resp_rate)  FILTER (WHERE resp_rate  > 0))::real AS rr,
		       SUM(movement)::int      AS movement,
		       SUM(snore_count)::int   AS snore,
		       SUM(resp_disorder)::int AS resp_disorder
		FROM min_data
		WHERE device_id = $1 AND time >= $2 AND time < $3
		GROUP BY t ORDER BY t`, interval), deviceID, start, stop)
	if err != nil {
		return nil, err
	}
	defer minuteRows.Close()

	type mrow struct {
		HR, RR       *float64
		Movement     *int64
		Snore        *int64
		RespDisorder *int64
	}
	byT := map[time.Time]mrow{}
	var minuteOrder []time.Time
	for minuteRows.Next() {
		var t time.Time
		var m mrow
		if err := minuteRows.Scan(&t, &m.HR, &m.RR, &m.Movement, &m.Snore, &m.RespDisorder); err != nil {
			return nil, err
		}
		byT[t] = m
		minuteOrder = append(minuteOrder, t)
	}
	if err := minuteRows.Err(); err != nil {
		return nil, err
	}

	// Occupancy and event codes live in sec_data, so they come from a second
	// query bucketed the same way and are joined in Go.
	secRows, err := s.db.QueryContext(ctx, fmt.Sprintf(`
		SELECT time_bucket('%s', time) AS t,
		       MAX(heart_rate) AS hr_max,
		       MAX(resp_rate)  AS rr_max,
		       array_agg(DISTINCT status) FILTER (WHERE status IS NOT NULL) AS events
		FROM sec_data
		WHERE device_id = $1 AND time >= $2 AND time < $3
		GROUP BY t ORDER BY t`, interval), deviceID, start, stop)
	if err != nil {
		return nil, err
	}
	defer secRows.Close()

	type srow struct {
		HRMax  *int64
		RRMax  *float64
		Events []int
	}
	secByT := map[time.Time]srow{}
	for secRows.Next() {
		var t time.Time
		var sr srow
		if err := secRows.Scan(&t, &sr.HRMax, &sr.RRMax, pqArray(&sr.Events)); err != nil {
			return nil, err
		}
		secByT[t] = sr
	}
	if err := secRows.Err(); err != nil {
		return nil, err
	}

	// Union the two bucket keys, ordered.
	keys := make(map[time.Time]bool)
	for t := range byT {
		keys[t] = true
	}
	for t := range secByT {
		keys[t] = true
	}
	order := make([]time.Time, 0, len(keys))
	for t := range keys {
		order = append(order, t)
	}
	sortTimes(order)

	points := make([]TimelinePoint, 0, len(order))
	for _, t := range order {
		m, hasMin := byT[t]
		sr, hasSec := secByT[t]
		p := TimelinePoint{T: t}
		if hasMin {
			p.HR, p.RR = m.HR, m.RR
			p.Movement, p.Snore, p.RespDisorder = m.Movement, m.Snore, m.RespDisorder
		}
		if hasSec {
			// bed_state comes from the same hr/rr rule the session builder
			// uses, not from `status` — no status code means "in bed".
			onBed := IsOnBed(toI32Ptr(sr.HRMax), sr.RRMax)
			if onBed {
				p.BedState = "on_bed"
			} else {
				p.BedState = "off_bed"
			}
			p.Events = sr.Events
		}
		points = append(points, p)
	}
	return points, nil
}

// pqArray adapts a *[]int to a scanner for a Postgres integer array.
func pqArray(dst *[]int) sql.Scanner {
	return &intArrayScanner{dst: dst}
}

type intArrayScanner struct {
	dst *[]int
}

func (a *intArrayScanner) Scan(src any) error {
	switch v := src.(type) {
	case nil:
		*a.dst = nil
		return nil
	case []byte:
		return scanIntArray(string(v), a.dst)
	case string:
		return scanIntArray(v, a.dst)
	default:
		return fmt.Errorf("unexpected array type %T", src)
	}
}

func scanIntArray(s string, dst *[]int) error {
	// Postgres text array: {1,3,5} — values are simple integers here.
	if len(s) < 2 || s[0] != '{' || s[len(s)-1] != '}' {
		*dst = nil
		return nil
	}
	inner := s[1 : len(s)-1]
	if inner == "" {
		*dst = nil
		return nil
	}
	var out []int
	cur := 0
	for _, r := range inner {
		switch {
		case r >= '0' && r <= '9':
			cur = cur*10 + int(r-'0')
		case r == ',':
			out = append(out, cur)
			cur = 0
		default:
			// skip whitespace/other
		}
	}
	out = append(out, cur)
	*dst = out
	return nil
}

func toI32Ptr(v *int64) *int32 {
	if v == nil {
		return nil
	}
	x := int32(*v)
	return &x
}

func sortTimes(ts []time.Time) {
	for i := 1; i < len(ts); i++ {
		for j := i; j > 0 && ts[j].Before(ts[j-1]); j-- {
			ts[j], ts[j-1] = ts[j-1], ts[j]
		}
	}
}
