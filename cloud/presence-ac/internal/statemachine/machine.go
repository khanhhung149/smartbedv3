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

	// ACReported* — trạng thái voice-node TỰ BÁO qua home/room/ac_state sau mỗi lần bắn IR.
	//
	// Khác ACDesired: ACDesired là thứ hệ MUỐN (suy từ lệnh bật/tắt), còn đây là thứ board nói nó
	// vừa gửi đi. Hai cái lệch nhau được, và trộn chúng làm công tắc trong app nhảy lung tung.
	//
	// ACStateKnown=false nghĩa là CHƯA nhận ac_state nào; khi đó hai trường dưới vô nghĩa, đừng
	// hiển thị. Cần cờ này vì "0" ở ACReportedTemp đọc ra là 0 độ C — không phân biệt được với
	// "chưa biết".
	//
	// Dùng cờ + giá trị chứ KHÔNG dùng con trỏ, dù con trỏ hợp cách viết Go hơn: main.go phát hiện
	// thay đổi bằng `snap != lastSnap`, mà so sánh con trỏ là so ĐỊA CHỈ. Snapshot() cấp phát mới
	// mỗi lần gọi nên mọi so sánh đều ra "đã đổi", và ticker mỗi giây sẽ bơm WebSocket liên tục.
	//
	// Lưu ý khi đọc: đây là Ý ĐỊNH của voice-node, không phải nhiệt độ đo được của phòng hay của
	// máy. Ai đó cầm remote chỉnh tay thì con số này lệch cho tới lệnh kế tiếp.
	ACStateKnown   bool `json:"ac_state_known"`
	ACReportedOn   bool `json:"ac_reported_on"`
	ACReportedTemp int  `json:"ac_reported_temp"`
}

type Machine struct {
	cfg Config
	mu  sync.RWMutex

	present   bool
	occupied  bool
	acDesired bool

	// occupied ở lần tự động áp dụng gần nhất. Auto chỉ can thiệp khi occupied ĐỔI
	// giá trị; giữa hai lần đổi, acDesired thuộc về lệnh tay.
	prevOccupied bool

	lastMotionAt time.Time // lần motion gần nhất
	lastFalseAt  time.Time // lúc presence chuyển false gần nhất
	falseActive  bool      // đang trong trạng thái presence=false (đếm exit)

	lastMotionTS   int64
	lastPresenceTS int64
	lastACCmd      string

	// acStateKnown=false cho tới khi voice-node báo ac_state lần đầu.
	acStateKnown   bool
	acReportedOn   bool
	acReportedTemp int
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

	// Tự động chỉ can thiệp khi occupied ĐỔI giá trị, không phải mỗi khi nó lệch
	// acDesired. So trực tiếp occupied != acDesired thì lệnh tay bị bẻ lại ngay ở
	// lần Tick kế tiếp (Tick chạy mỗi giây) — người dùng bật điều hoà trong phòng
	// trống là tắt lại tức thì, công tắc trong app nảy về chỗ cũ.
	if m.occupied == m.prevOccupied {
		return nil
	}
	m.prevOccupied = m.occupied

	if m.acDesired == m.occupied {
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

// SetManual áp lệnh tay (app hoặc voice) lên trạng thái mong muốn. Lệnh giữ
// nguyên cho tới khi phòng đổi trạng thái occupied — đúng giao kèo app hiển thị
// cho người dùng: "Lệnh tay có thể bị ghi đè khi phòng đổi trạng thái."
func (m *Machine) SetManual(on bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.acDesired = on
	m.lastACCmd = "off"
	if on {
		m.lastACCmd = "on"
	}
}

// SetACState ghi nhận trạng thái voice-node báo về. CỐ Ý không đụng tới acDesired: đây là báo cáo
// từ board, không phải lệnh của người dùng. Để nó ghi đè acDesired thì mỗi lần board báo lại là
// công tắc trong app nhảy một cái.
func (m *Machine) SetACState(power bool, temp int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.acStateKnown = true
	m.acReportedOn = power
	m.acReportedTemp = temp
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
		ACStateKnown:   m.acStateKnown,
		ACReportedOn:   m.acReportedOn,
		ACReportedTemp: m.acReportedTemp,
	}
}
