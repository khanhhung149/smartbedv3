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

// IsOnBed implements p.4 §2.4.1: heart rate and respiration both read 0 once
// the bed is empty. GetTimeline derives bed_state from it, which is why the
// rule stays here after the session-building state machine moved out.
func IsOnBed(hr *int32, rr *float64) bool {
	return (hr != nil && *hr > 0) || (rr != nil && *rr > 0)
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
		Movement     *int64
		Snore        *int64
		RespDisorder *int64
	}
	byT := map[time.Time]mrow{}
	var minuteOrder []time.Time
	for minuteRows.Next() {
		var t time.Time
		var m mrow
		if err := minuteRows.Scan(&t, &m.Movement, &m.Snore, &m.RespDisorder); err != nil {
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
		       (AVG(heart_rate) FILTER (WHERE heart_rate > 0))::real AS hr,
		       (AVG(resp_rate)  FILTER (WHERE resp_rate  > 0))::real AS rr,
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
		HR, RR *float64
		Events []int
	}
	secByT := map[time.Time]srow{}
	for secRows.Next() {
		var t time.Time
		var sr srow
		if err := secRows.Scan(&t, &sr.HRMax, &sr.RRMax, &sr.HR, &sr.RR, pqArray(&sr.Events)); err != nil {
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
			p.Movement, p.Snore, p.RespDisorder = m.Movement, m.Snore, m.RespDisorder
		}
		if hasSec {
			// hr/rr lấy từ sec_data (1 Hz), không phải min_data: pad LSM-800-T nói
			// giao thức TAOSG và không phát khung phút, nên min_data rỗng vĩnh viễn
			// và biểu đồ nhịp tim của một đêm sẽ trống trơn.
			p.HR, p.RR = sr.HR, sr.RR
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

// MorningReport is the v0 sleep summary: no AHI, just what sec_data and the
// room snore table already give us for real (Michael: ship LD2410C-era data
// first, don't wait on min_data/piezo/SpO2).
//
// ApneaEvents is a non-diagnostic hint, not AHI: see plan
// 260826-1434-apnea-signal-v0 for the OR-fusion design (status==8 WEAK_BREATHING
// native flag, or heart_rate>0 && resp_rate==0 while presumably on-bed).
type MorningReport struct {
	OnBedSeconds      int64        `json:"on_bed_seconds"`
	OffBedTransitions int          `json:"off_bed_transitions"`
	AvgHeartRate      *float64     `json:"avg_heart_rate"`
	AvgRespRate       *float64     `json:"avg_resp_rate"`
	ApneaEvents       []ApneaEvent `json:"apnea_events"`
	ApneaCount        int          `json:"apnea_count"`
	Disclaimer        string       `json:"disclaimer"`
}

// ApneaEvent is one candidate breathing-pause window. confidence is
// corroborated by sdata (piezo peak amplitude) dropping vs its own 60s
// baseline — the closest stand-in for the SpO2 corroboration the reference
// algorithm uses, since this hardware has no SpO2 sensor.
type ApneaEvent struct {
	StartS     float64 `json:"start_s"`
	EndS       float64 `json:"end_s"`
	DurationS  float64 `json:"duration_s"`
	Confidence string  `json:"confidence"` // "supported" | "weak"
}

const (
	apneaMinRunS          = 10.0
	apneaExcludeAfterS    = 25.0 // status protocol: HR/RR need 25s of stillness to compute
	apneaSdataBaselineS   = 60.0
	apneaSdataDropForCorr = 0.70 // event mean sdata < 70% of baseline median → "supported"
	statusMovement        = 2
	statusSitUp           = 3
	statusWeakBreathing   = 8
)

type secDataRow struct {
	t      time.Time
	hr     *int32
	rr     *float64
	status *int32
	sdata  *float64
}

// MorningReport aggregates sec_data over [from, to) into on-bed time,
// off-bed transitions, and apnea signal v0. It loads the night into memory
// rather than a SQL window function: a night is at most tens of thousands of
// 1Hz rows, so the loop cost is negligible and the logic stays readable
// (YAGNI).
//
// A large gap between consecutive rows (node dropout) is treated as "still in
// the previous bed state" until the next row — accepted imprecision for v0,
// see plan Validation Log.
func (s *PGStore) MorningReport(ctx context.Context, deviceID string, from, to time.Time) (*MorningReport, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT time, heart_rate, resp_rate, status, sdata
		FROM sec_data
		WHERE device_id = $1 AND time >= $2 AND time < $3
		ORDER BY time`, deviceID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var samples []secDataRow
	for rows.Next() {
		var t time.Time
		var hr, status, sdata sql.NullInt64
		var rr sql.NullFloat64
		if err := rows.Scan(&t, &hr, &rr, &status, &sdata); err != nil {
			return nil, err
		}
		row := secDataRow{t: t}
		if hr.Valid {
			v := int32(hr.Int64)
			row.hr = &v
		}
		if rr.Valid {
			v := rr.Float64
			row.rr = &v
		}
		if status.Valid {
			v := int32(status.Int64)
			row.status = &v
		}
		if sdata.Valid {
			v := float64(sdata.Int64)
			row.sdata = &v
		}
		samples = append(samples, row)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	out := &MorningReport{
		Disclaimer: "Tóm tắt giấc ngủ, không phải chẩn đoán y tế. apnea_events là tín hiệu tham khảo dựa trên resp_rate/status, không phải AHI y tế, chưa qua kiểm chứng lâm sàng.",
	}

	var prevT time.Time
	var havePrev bool
	var wasOnBed bool
	var hrSum, rrSum float64
	var hrCount, rrCount int64

	for _, row := range samples {
		if row.hr != nil && *row.hr > 0 {
			hrSum += float64(*row.hr)
			hrCount++
		}
		if row.rr != nil && *row.rr > 0 {
			rrSum += *row.rr
			rrCount++
		}
		onBed := IsOnBed(row.hr, row.rr)

		if havePrev {
			delta := row.t.Sub(prevT)
			if wasOnBed {
				out.OnBedSeconds += int64(delta.Seconds())
			}
			if wasOnBed && !onBed {
				out.OffBedTransitions++
			}
		}
		prevT = row.t
		wasOnBed = onBed
		havePrev = true
	}

	if hrCount > 0 {
		v := hrSum / float64(hrCount)
		out.AvgHeartRate = &v
	}
	if rrCount > 0 {
		v := rrSum / float64(rrCount)
		out.AvgRespRate = &v
	}

	out.ApneaEvents = detectApneaEvents(samples)
	out.ApneaCount = len(out.ApneaEvents)
	return out, nil
}

// detectApneaEvents runs the OR-fusion described in plan
// 260826-1434-apnea-signal-v0: signal A (status==8, native) and signal B
// (heart_rate>0 && resp_rate==0, inferred) each accumulate independently;
// overlapping runs from either signal merge into one event.
func detectApneaEvents(samples []secDataRow) []ApneaEvent {
	var runsA, runsB []timeRun

	var aStart time.Time
	aActive := false
	var bStart time.Time
	bActive := false
	var lastMoveOrSitUp time.Time
	haveLastMoveOrSitUp := false

	closeRun := func(active *bool, start time.Time, end time.Time, dst *[]timeRun) {
		if *active {
			if end.Sub(start).Seconds() >= apneaMinRunS {
				*dst = append(*dst, timeRun{start: start, end: end})
			}
			*active = false
		}
	}

	for _, row := range samples {
		if row.status != nil && (*row.status == statusMovement || *row.status == statusSitUp) {
			lastMoveOrSitUp = row.t
			haveLastMoveOrSitUp = true
		}

		isA := row.status != nil && *row.status == statusWeakBreathing
		if isA {
			if !aActive {
				aStart = row.t
				aActive = true
			}
		} else {
			closeRun(&aActive, aStart, row.t, &runsA)
		}

		excludedByRecentMovement := haveLastMoveOrSitUp && row.t.Sub(lastMoveOrSitUp).Seconds() < apneaExcludeAfterS
		isB := row.hr != nil && *row.hr > 0 && row.rr != nil && *row.rr == 0 && !excludedByRecentMovement
		if isB {
			if !bActive {
				bStart = row.t
				bActive = true
			}
		} else {
			closeRun(&bActive, bStart, row.t, &runsB)
		}
	}
	if len(samples) > 0 {
		last := samples[len(samples)-1].t
		closeRun(&aActive, aStart, last, &runsA)
		closeRun(&bActive, bStart, last, &runsB)
	}

	merged := mergeOverlappingRuns(append(runsA, runsB...))

	events := make([]ApneaEvent, 0, len(merged))
	for _, r := range merged {
		events = append(events, ApneaEvent{
			StartS:     0, // filled below relative to first sample
			EndS:       0,
			DurationS:  r.end.Sub(r.start).Seconds(),
			Confidence: apneaConfidence(samples, r.start, r.end),
		})
	}
	if len(samples) > 0 {
		base := samples[0].t
		for i, r := range merged {
			events[i].StartS = r.start.Sub(base).Seconds()
			events[i].EndS = r.end.Sub(base).Seconds()
		}
	}
	return events
}

type timeRun struct{ start, end time.Time }

func mergeOverlappingRuns(runs []timeRun) []timeRun {
	if len(runs) == 0 {
		return nil
	}
	sortRuns(runs)
	out := []timeRun{runs[0]}
	for _, r := range runs[1:] {
		last := &out[len(out)-1]
		if r.start.Before(last.end) || r.start.Equal(last.end) {
			if r.end.After(last.end) {
				last.end = r.end
			}
		} else {
			out = append(out, r)
		}
	}
	return out
}

func sortRuns(runs []timeRun) {
	for i := 1; i < len(runs); i++ {
		for j := i; j > 0 && runs[j].start.Before(runs[j-1].start); j-- {
			runs[j], runs[j-1] = runs[j-1], runs[j]
		}
	}
}

// apneaConfidence corroborates an event with sdata (piezo peak amplitude) —
// the closest stand-in for SpO2 on hardware that has no SpO2 sensor. "supported"
// means sdata during the event dropped notably vs. its own recent baseline.
func apneaConfidence(samples []secDataRow, start, end time.Time) string {
	var baseline []float64
	var duringSum float64
	var duringCount int
	for _, row := range samples {
		if row.sdata == nil {
			continue
		}
		if row.t.Before(start) && start.Sub(row.t).Seconds() <= apneaSdataBaselineS {
			baseline = append(baseline, *row.sdata)
		}
		if !row.t.Before(start) && row.t.Before(end) {
			duringSum += *row.sdata
			duringCount++
		}
	}
	if len(baseline) == 0 || duringCount == 0 {
		return "weak"
	}
	medianBaseline := medianFloat(baseline)
	duringMean := duringSum / float64(duringCount)
	if medianBaseline > 0 && duringMean < apneaSdataDropForCorr*medianBaseline {
		return "supported"
	}
	return "weak"
}

func medianFloat(vals []float64) float64 {
	sorted := append([]float64(nil), vals...)
	for i := 1; i < len(sorted); i++ {
		for j := i; j > 0 && sorted[j] < sorted[j-1]; j-- {
			sorted[j], sorted[j-1] = sorted[j-1], sorted[j]
		}
	}
	n := len(sorted)
	if n == 0 {
		return 0
	}
	if n%2 == 1 {
		return sorted[n/2]
	}
	return (sorted[n/2-1] + sorted[n/2]) / 2
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

// LatestSec là dòng sec_data mới nhất của một thiết bị — nguồn cho màn xem trực tiếp.
// Khác Sample (dùng để dựng phiên): giữ nguyên sdata/pdata vì màn realtime hiển thị
// chúng, còn luật dựng phiên không dùng tới.
type LatestSec struct {
	T      time.Time `json:"t"`
	Status *int32    `json:"status"`
	HR     *int32    `json:"heart_rate"`
	RR     *float64  `json:"resp_rate"`
	SData  *int32    `json:"sdata"`
	PData  *int32    `json:"pdata"`
}

// GetLatestSec trả dòng mới nhất, hoặc nil nếu thiết bị chưa gửi mẫu nào.
// Không lọc theo thời gian: màn realtime tự quyết định số cũ bao nhiêu thì coi là mất tín hiệu,
// vì chỉ nó biết ngưỡng hợp lý cho người xem.
func (s *PGStore) GetLatestSec(ctx context.Context, deviceID string) (*LatestSec, error) {
	row := s.db.QueryRowContext(ctx, `
		SELECT time, status, heart_rate, resp_rate, sdata, pdata
		FROM sec_data
		WHERE device_id = $1
		ORDER BY time DESC
		LIMIT 1`, deviceID)

	var out LatestSec
	var st, hr, sd, pd sql.NullInt64
	var rr sql.NullFloat64
	switch err := row.Scan(&out.T, &st, &hr, &rr, &sd, &pd); err {
	case nil:
	case sql.ErrNoRows:
		return nil, nil
	default:
		return nil, err
	}
	if st.Valid {
		v := int32(st.Int64)
		out.Status = &v
	}
	if hr.Valid {
		v := int32(hr.Int64)
		out.HR = &v
	}
	if rr.Valid {
		v := rr.Float64
		out.RR = &v
	}
	if sd.Valid {
		v := int32(sd.Int64)
		out.SData = &v
	}
	if pd.Valid {
		v := int32(pd.Int64)
		out.PData = &v
	}
	return &out, nil
}
