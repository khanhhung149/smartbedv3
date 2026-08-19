// Package sessions ports the sleep-session state machine from the Legact
// protocol PDF (see sleep_pad_AI/backend/app/sessions/rules.py).
//
// Every rule here comes from the protocol, not from guesswork:
//
//	p.2        a session opens after 30 consecutive seconds in bed, closes
//	           after 30 minutes out of bed, and a recording caps at 1440 minutes
//	p.4 §2.4.1 heart rate and respiration read 0 when the person leaves the bed
//
// `status` is an *event code* for that second, not a bed-occupancy flag. Codes:
// 01 off-bed, 02 movement, 03 sitting up, 04 asleep, 05 awake, 06 heavy object,
// 07 snoring, 08 weak breathing. There is no "currently in bed" code, so
// occupancy is never derived from `status`.
package sessions

import "time"

// Defaults mirror the PDF. Callers pass overrides; nothing here reads config
// directly so the package stays importable without an environment.
const (
	DefaultOpenSeconds  = 30
	DefaultCloseSeconds = 1800
	DefaultMaxMinutes   = 1440

	// Event codes from p.4 §2.4.1 that the summary counts.
	StatusSitUp = 0x03
	StatusAwake = 0x05
)

// Sample is one second of sec_data, already ordered by time.
type Sample struct {
	T      time.Time
	HR     *int32
	RR     *float64
	Status *int32
}

// SessionWindow is a closed or still-open session boundary pair.
//
// EndedAt is nil while the person is still in bed at the end of the input —
// the builder writes that as an open session and revisits it on a later tick.
type SessionWindow struct {
	StartedAt  time.Time
	EndedAt    *time.Time
	SitUpCount int
	WakeCount  int
}

// IsOnBed implements p.4 §2.4.1: both readings drop to 0 once the bed is empty.
func IsOnBed(hr *int32, rr *float64) bool {
	return (hr != nil && *hr > 0) || (rr != nil && *rr > 0)
}

// BuildSessions turns an ordered run of per-second samples into session windows.
//
// Three properties are easy to get wrong and are each asserted by the tests:
//
//   - A session's EndedAt is the moment the bed was left, not the moment the
//     30-minute confirmation elapsed. Reporting the later time would inflate
//     every night by half an hour.
//   - A hole in the data counts as time out of bed. The sensor publishes once a
//     second while occupied, so a gap is absence of evidence of presence, and
//     inventing presence across it would be fabricating a reading.
//   - Hitting the 1440-minute cap ends the recording but not the occupancy —
//     someone still in bed starts a fresh session at the cut.
//
// Pass now to apply the same absence rule to the silence after the last sample.
// Without it a night whose data simply stops — the pad unplugged in the
// morning — stays open forever and the app shows a session with no end. The
// close time is the last sample, the final moment presence was observed;
// guessing anything later would report bed time nobody recorded.
func BuildSessions(samples []Sample, opts BuildOptions) []SessionWindow {
	openSeconds := opts.OpenSeconds
	if openSeconds == 0 {
		openSeconds = DefaultOpenSeconds
	}
	closeSeconds := opts.CloseSeconds
	if closeSeconds == 0 {
		closeSeconds = DefaultCloseSeconds
	}
	maxMinutes := opts.MaxMinutes
	if maxMinutes == 0 {
		maxMinutes = DefaultMaxMinutes
	}
	maxDuration := time.Duration(maxMinutes) * time.Minute

	var windows []SessionWindow
	var startedAt *time.Time    // confirmed session start, nil = IDLE
	var pendingStart *time.Time // occupancy run not yet 30s long
	var absentSince *time.Time  // first second of the current absence
	sitUps, wakes := 0, 0
	var prevT *time.Time

	begin := func(at time.Time) {
		t := at
		startedAt = &t
		pendingStart = nil
		absentSince = nil
		sitUps, wakes = 0, 0
	}

	close := func(endedAt *time.Time) {
		windows = append(windows, SessionWindow{
			StartedAt:  *startedAt,
			EndedAt:    endedAt,
			SitUpCount: sitUps,
			WakeCount:  wakes,
		})
		startedAt = nil
	}

	for _, s := range samples {
		// A gap between consecutive rows is absence starting at the last known
		// second, so a dropout closes a session exactly like leaving the bed.
		if prevT != nil && s.T.Sub(*prevT).Seconds() > 1 {
			if startedAt != nil {
				if absentSince == nil {
					t := *prevT
					absentSince = &t
				}
				if s.T.Sub(*absentSince).Seconds() >= float64(closeSeconds) {
					close(absentSince)
					absentSince = nil
				}
			} else {
				pendingStart = nil
			}
		}
		t := s.T
		prevT = &t

		onBed := IsOnBed(s.HR, s.RR)

		if startedAt == nil {
			if !onBed {
				pendingStart = nil
				continue
			}
			if pendingStart == nil {
				t := s.T
				pendingStart = &t
				sitUps, wakes = 0, 0
			}
			if s.Status != nil && *s.Status == StatusSitUp {
				sitUps++
			}
			if s.Status != nil && *s.Status == StatusAwake {
				wakes++
			}
			// Inclusive span: the 30th consecutive second sits 29s after the
			// first, and the counters above already cover that qualifying run.
			if s.T.Sub(*pendingStart).Seconds() >= float64(openSeconds-1) {
				t := *pendingStart
				startedAt = &t
				pendingStart = nil
				absentSince = nil
			}
			continue
		}

		// IN_SESSION
		if onBed {
			absentSince = nil
			if s.Status != nil && *s.Status == StatusSitUp {
				sitUps++
			}
			if s.Status != nil && *s.Status == StatusAwake {
				wakes++
			}
		} else {
			if absentSince == nil {
				t := s.T
				absentSince = &t
			} else if s.T.Sub(*absentSince).Seconds() >= float64(closeSeconds) {
				close(absentSince)
				absentSince = nil
				continue
			}
		}

		if startedAt != nil && s.T.Sub(*startedAt) >= maxDuration {
			cut := startedAt.Add(maxDuration)
			close(&cut)
			// Still occupied — the cap ends the recording, not the night.
			if onBed {
				begin(cut)
			} else {
				absentSince = nil
			}
		}
	}

	if startedAt != nil {
		var endedAt *time.Time
		if absentSince != nil {
			endedAt = absentSince
		} else if opts.Now != nil && prevT != nil &&
			opts.Now.Sub(*prevT).Seconds() >= float64(closeSeconds) {
			t := *prevT
			endedAt = &t
		}
		// Absence that never reached the 30-minute threshold still ends the
		// session where the bed was left; ongoing occupancy leaves it open.
		close(endedAt)
	}
	return windows
}

// BuildOptions carries the tunable thresholds plus the "now" reference for
// closing sessions whose data simply stopped. Zero values fall back to the
// protocol defaults.
type BuildOptions struct {
	OpenSeconds  int
	CloseSeconds int
	MaxMinutes   int
	Now          *time.Time
}
