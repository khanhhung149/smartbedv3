package sessions

import (
	"testing"
	"time"
)

var t0 = time.Date(2026, 8, 18, 23, 0, 0, 0, time.UTC)

func onBed(hr int32, rr float64) Sample {
	h, r := hr, rr
	return Sample{T: t0, HR: &h, RR: &r}
}

// run builds a per-second sample list from (duration_seconds, on_bed) segments.
// skip drops seconds by offset so a data gap can be expressed; statusAt stamps
// an event code on one second.
func run(t *testing.T, spec [][2]int, statusAt map[int]int, skip map[int]bool) []Sample {
	t.Helper()
	var samples []Sample
	offset := 0
	for _, seg := range spec {
		seconds, bed := seg[0], seg[1] == 1
		for i := 0; i < seconds; i++ {
			if !skip[offset] {
				var st *int32
				if c, ok := statusAt[offset]; ok {
					v := int32(c)
					st = &v
				}
				h, r := int32(62), 15.0
				if !bed {
					h, r = 0, 0.0
				}
				samples = append(samples, Sample{
					T:      t0.Add(time.Duration(offset) * time.Second),
					HR:     &h,
					RR:     &r,
					Status: st,
				})
			}
			offset++
		}
	}
	return samples
}

func checkIsOnBed(t *testing.T, hr *int32, rr *float64, want bool) {
	t.Helper()
	if got := IsOnBed(hr, rr); got != want {
		t.Fatalf("IsOnBed(%v, %v) = %v, want %v", hr, rr, got, want)
	}
}

func TestIsOnBed(t *testing.T) {
	// p.4 2.4.1 — either reading being non-zero means the bed is occupied.
	h62, h0 := int32(62), int32(0)
	r15, r0 := 15.0, 0.0
	checkIsOnBed(t, &h62, &r15, true)
	checkIsOnBed(t, &h0, &r15, true)
	checkIsOnBed(t, &h62, &r0, true)
	checkIsOnBed(t, &h0, &r0, false)
	checkIsOnBed(t, nil, nil, false)
	checkIsOnBed(t, &h0, nil, false)
}

func Test29SecondsDoesNotOpenASession(t *testing.T) {
	if out := BuildSessions(run(t, [][2]int{{29, 1}, {60, 0}}, nil, nil), BuildOptions{}); len(out) != 0 {
		t.Fatalf("want no session, got %d", len(out))
	}
}

func Test30SecondsOpensExactlyOneSession(t *testing.T) {
	out := BuildSessions(run(t, [][2]int{{30, 1}, {3600, 0}}, nil, nil), BuildOptions{})
	if len(out) != 1 {
		t.Fatalf("want 1 session, got %d", len(out))
	}
	if !out[0].StartedAt.Equal(t0) {
		t.Errorf("StartedAt = %v, want %v", out[0].StartedAt, t0)
	}
	wantEnd := t0.Add(30 * time.Second)
	if out[0].EndedAt == nil || !out[0].EndedAt.Equal(wantEnd) {
		t.Errorf("EndedAt = %v, want %v", out[0].EndedAt, wantEnd)
	}
}

func TestAbsenceOf25MinutesDoesNotSplitTheNight(t *testing.T) {
	out := BuildSessions(run(t, [][2]int{{3600, 1}, {1500, 0}, {3600, 1}, {3600, 0}}, nil, nil), BuildOptions{})
	if len(out) != 1 {
		t.Fatalf("want 1 session, got %d", len(out))
	}
}

func TestAbsenceOf31MinutesSplitsAndEndsAtTheMomentOfLeaving(t *testing.T) {
	leftAt := t0.Add(3600 * time.Second)
	out := BuildSessions(run(t, [][2]int{{3600, 1}, {1860, 0}, {3600, 1}, {3600, 0}}, nil, nil), BuildOptions{})
	if len(out) != 2 {
		t.Fatalf("want 2 sessions, got %d", len(out))
	}
	// Not the moment the 30-minute timer expired — that would add half an hour
	// of bed time that never happened.
	if out[0].EndedAt == nil || !out[0].EndedAt.Equal(leftAt) {
		t.Errorf("first EndedAt = %v, want %v", out[0].EndedAt, leftAt)
	}
	wantStart := t0.Add((3600 + 1860) * time.Second)
	if !out[1].StartedAt.Equal(wantStart) {
		t.Errorf("second StartedAt = %v, want %v", out[1].StartedAt, wantStart)
	}
}

func TestContinuousOccupancyIsCutAtThe1440MinuteCap(t *testing.T) {
	out := BuildSessions(run(t, [][2]int{{1500 * 60, 1}}, nil, nil), BuildOptions{})
	if !out[0].StartedAt.Equal(t0) {
		t.Errorf("StartedAt = %v, want %v", out[0].StartedAt, t0)
	}
	wantEnd := t0.Add(1440 * time.Minute)
	if out[0].EndedAt == nil || !out[0].EndedAt.Equal(wantEnd) {
		t.Errorf("EndedAt = %v, want %v", out[0].EndedAt, wantEnd)
	}
	// The cap ends the recording, not the occupancy: the remaining hour is a
	// session of its own rather than silently discarded data.
	if len(out) != 2 {
		t.Fatalf("want 2 sessions, got %d", len(out))
	}
	wantStart := t0.Add(1440 * time.Minute)
	if !out[1].StartedAt.Equal(wantStart) {
		t.Errorf("second StartedAt = %v, want %v", out[1].StartedAt, wantStart)
	}
}

func TestDataGapOf40MinutesClosesTheSession(t *testing.T) {
	// Drop 40 minutes of rows outright — a hole is not evidence of presence.
	skip := map[int]bool{}
	for i := 3600; i < 3600+40*60; i++ {
		skip[i] = true
	}
	out := BuildSessions(run(t, [][2]int{{3600, 1}, {2400, 1}, {3600, 1}, {3600, 0}}, nil, skip), BuildOptions{})
	if len(out) != 2 {
		t.Fatalf("want 2 sessions, got %d", len(out))
	}
	wantEnd := t0.Add(3599 * time.Second)
	if out[0].EndedAt == nil || !out[0].EndedAt.Equal(wantEnd) {
		t.Errorf("EndedAt = %v, want %v", out[0].EndedAt, wantEnd)
	}
}

func TestEventCodesAreCountedWithinTheSession(t *testing.T) {
	out := BuildSessions(
		run(t, [][2]int{{600, 1}, {3600, 0}},
			map[int]int{100: 0x03, 200: 0x03, 300: 0x05, 400: 0x07}, nil),
		BuildOptions{},
	)
	if len(out) != 1 {
		t.Fatalf("want 1 session, got %d", len(out))
	}
	if out[0].SitUpCount != 2 {
		t.Errorf("SitUpCount = %d, want 2", out[0].SitUpCount)
	}
	if out[0].WakeCount != 1 {
		t.Errorf("WakeCount = %d, want 1", out[0].WakeCount)
	}
}

func TestStillInBedAtTheEndLeavesTheSessionOpen(t *testing.T) {
	out := BuildSessions(run(t, [][2]int{{3600, 1}}, nil, nil), BuildOptions{})
	if len(out) != 1 {
		t.Fatalf("want 1 session, got %d", len(out))
	}
	if out[0].EndedAt != nil {
		t.Errorf("EndedAt = %v, want nil", out[0].EndedAt)
	}
}

func TestThresholdsAreParametersNotConstants(t *testing.T) {
	// R1: the on-bed rule is an inference, so the boundaries must stay tunable.
	if out := BuildSessions(run(t, [][2]int{{10, 1}, {3600, 0}}, nil, nil), BuildOptions{OpenSeconds: 10}); len(out) != 1 {
		t.Fatalf("with open_seconds=10 want 1 session, got %d", len(out))
	}
	if out := BuildSessions(run(t, [][2]int{{10, 1}, {3600, 0}}, nil, nil), BuildOptions{}); len(out) != 0 {
		t.Fatalf("with defaults want 0 sessions, got %d", len(out))
	}
}

func TestDataThatSimplyStopsClosesTheSessionAtTheLastSample(t *testing.T) {
	// The pad unplugged in the morning: no "off bed" rows ever arrive. Without
	// `now` the night would stay open forever and the app would show a session
	// with no end time.
	samples := run(t, [][2]int{{3600, 1}}, nil, nil)
	last := samples[len(samples)-1].T
	now := last.Add(31 * time.Minute)
	out := BuildSessions(samples, BuildOptions{Now: &now})
	if len(out) != 1 {
		t.Fatalf("want 1 session, got %d", len(out))
	}
	if out[0].EndedAt == nil || !out[0].EndedAt.Equal(last) {
		t.Errorf("EndedAt = %v, want %v", out[0].EndedAt, last)
	}
}

func TestRecentSilenceLeavesTheSessionOpen(t *testing.T) {
	// Only 5 minutes quiet — the person may simply still be in bed.
	samples := run(t, [][2]int{{3600, 1}}, nil, nil)
	last := samples[len(samples)-1].T
	now := last.Add(5 * time.Minute)
	out := BuildSessions(samples, BuildOptions{Now: &now})
	if out[0].EndedAt != nil {
		t.Errorf("EndedAt = %v, want nil", out[0].EndedAt)
	}
}
