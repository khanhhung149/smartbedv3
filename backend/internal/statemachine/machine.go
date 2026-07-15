// Package statemachine suy luận trạng thái phòng (occupied/empty) từ event
// motion + presence, và quyết định lệnh AC (on/off).
//
// Thiết kế tick-based để test xác định: mọi chuyển đổi theo thời gian được
// đánh giá trong evaluate(now); loop chính gọi Tick() định kỳ. Không dùng timer
// nội bộ → unit test tiêm mốc thời gian trực tiếp.
package statemachine

import (
	"sync"
	"time"
)

type Config struct {
	EnterWindow time.Duration // motion phải xảy ra trong khoảng này trước presence=true mới coi là vào
	ExitTimeout time.Duration // presence=false giữ đủ lâu → coi là ra
}

type Snapshot struct {
	Present        bool   `json:"present"`
	Occupied       bool   `json:"occupied"`
	ACDesired      bool   `json:"ac_desired"`
	LastMotionTS   int64  `json:"last_motion_ts"`
	LastPresenceTS int64  `json:"last_presence_ts"`
	LastACCmd      string `json:"last_ac_cmd"`
}

type Machine struct {
	cfg Config
	mu  sync.RWMutex

	present   bool
	occupied  bool
	acDesired bool

	lastMotionAt time.Time // lần motion gần nhất
	lastFalseAt  time.Time // lúc presence chuyển false gần nhất
	falseActive  bool      // đang trong trạng thái presence=false (đếm exit)

	lastMotionTS   int64
	lastPresenceTS int64
	lastACCmd      string
}

func New(cfg Config) *Machine {
	return &Machine{cfg: cfg}
}

// OnMotion ghi nhận event chuyển động. Trả "on"/"off" nếu lệnh AC mong muốn đổi, ngược lại nil.
func (m *Machine) OnMotion(ts int64, now time.Time) *string {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.lastMotionAt = now
	m.lastMotionTS = ts
	return m.evaluate(now)
}

// OnPresence ghi nhận trạng thái hiện diện từ radar.
func (m *Machine) OnPresence(present bool, ts int64, now time.Time) *string {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.present = present
	m.lastPresenceTS = ts
	if present {
		m.falseActive = false
	} else if !m.falseActive {
		m.falseActive = true
		m.lastFalseAt = now
	}
	return m.evaluate(now)
}

// Tick đánh giá các chuyển đổi theo thời gian (gọi định kỳ, vd mỗi giây).
func (m *Machine) Tick(now time.Time) *string {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.evaluate(now)
}

// evaluate áp dụng luật, trả lệnh nếu acDesired đổi.
func (m *Machine) evaluate(now time.Time) *string {
	// Vào: presence=true + có motion gần đây (chống false-positive radar xuyên tường)
	if m.present && !m.occupied {
		if !m.lastMotionAt.IsZero() && now.Sub(m.lastMotionAt) <= m.cfg.EnterWindow {
			m.occupied = true
		}
	}
	// Ra: presence=false giữ ổn định >= ExitTimeout
	if m.occupied && !m.present && m.falseActive {
		if now.Sub(m.lastFalseAt) >= m.cfg.ExitTimeout {
			m.occupied = false
		}
	}

	if m.occupied == m.acDesired {
		return nil
	}
	m.acDesired = m.occupied
	cmd := "off"
	if m.acDesired {
		cmd = "on"
	}
	m.lastACCmd = cmd
	return &cmd
}

func (m *Machine) Snapshot() Snapshot {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return Snapshot{
		Present:        m.present,
		Occupied:       m.occupied,
		ACDesired:      m.acDesired,
		LastMotionTS:   m.lastMotionTS,
		LastPresenceTS: m.lastPresenceTS,
		LastACCmd:      m.lastACCmd,
	}
}
