// Đường ghi của sleep session: đọc sec_data theo giây, dựng cửa sổ phiên bằng
// luật trong rules.go, tổng hợp chỉ số rồi upsert vào sleep_sessions.
//
// Luật dựng phiên chỉ tồn tại một bản, ở đây (Go), vì backend duy nhất phục vụ
// /api/sessions* cho app là binary này. Bản Python trong cloud/sleeppad chỉ còn
// giá trị tham chiếu giao thức, không được chạy song song trên cùng database:
// hai builder cùng upsert (device_id, started_at) sẽ ghi đè lẫn nhau.
package sessions

import (
	"context"
	"database/sql"
	"time"
)

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
