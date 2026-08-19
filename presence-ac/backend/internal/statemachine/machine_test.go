package statemachine

import (
	"testing"
	"time"
)

func cfg() Config {
	return Config{EnterWindow: 15 * time.Second, ExitTimeout: 60 * time.Second}
}

func TestEnterTurnsOn(t *testing.T) {
	base := time.Unix(1000, 0)
	m := New(cfg())
	if cmd := m.OnMotion(1, base); cmd != nil {
		t.Fatalf("motion đơn lẻ không nên ra lệnh, got %v", *cmd)
	}
	cmd := m.OnPresence(true, 2, base.Add(2*time.Second))
	if cmd == nil || *cmd != "on" {
		t.Fatalf("expected on, got %v", cmd)
	}
}

func TestPresenceWithoutMotionNoOn(t *testing.T) {
	base := time.Unix(1000, 0)
	m := New(cfg())
	if cmd := m.OnPresence(true, 1, base); cmd != nil {
		t.Fatalf("presence không kèm motion không nên bật (chống false-positive), got %v", *cmd)
	}
}

func TestMotionTooOldNoOn(t *testing.T) {
	base := time.Unix(1000, 0)
	m := New(cfg())
	m.OnMotion(1, base)
	// presence tới sau EnterWindow (15s) -> không coi là vào
	if cmd := m.OnPresence(true, 2, base.Add(20*time.Second)); cmd != nil {
		t.Fatalf("motion quá cũ không nên bật, got %v", *cmd)
	}
}

func TestExitAfterTimeout(t *testing.T) {
	base := time.Unix(1000, 0)
	m := New(cfg())
	m.OnMotion(1, base)
	if cmd := m.OnPresence(true, 2, base.Add(1*time.Second)); cmd == nil || *cmd != "on" {
		t.Fatalf("expected on, got %v", cmd)
	}
	if cmd := m.OnPresence(false, 3, base.Add(10*time.Second)); cmd != nil {
		t.Fatalf("không nên tắt ngay khi presence false, got %v", *cmd)
	}
	if cmd := m.Tick(base.Add(30 * time.Second)); cmd != nil {
		t.Fatalf("chưa đủ ExitTimeout không nên tắt, got %v", *cmd)
	}
	cmd := m.Tick(base.Add(75 * time.Second)) // false từ +10s, +60s = +70s
	if cmd == nil || *cmd != "off" {
		t.Fatalf("expected off, got %v", cmd)
	}
}

func TestFlickerNoOff(t *testing.T) {
	base := time.Unix(1000, 0)
	m := New(cfg())
	m.OnMotion(1, base)
	m.OnPresence(true, 2, base.Add(1*time.Second))  // on
	m.OnPresence(false, 3, base.Add(5*time.Second)) // blip false
	m.OnPresence(true, 4, base.Add(10*time.Second)) // true lại trước timeout
	if cmd := m.Tick(base.Add(120 * time.Second)); cmd != nil {
		t.Fatalf("nhấp nháy presence không nên tắt, got %v", *cmd)
	}
}

func TestReentryTurnsOnAgain(t *testing.T) {
	base := time.Unix(1000, 0)
	m := New(cfg())
	m.OnMotion(1, base)
	m.OnPresence(true, 2, base.Add(1*time.Second))   // on
	m.OnPresence(false, 3, base.Add(10*time.Second)) // rời
	if cmd := m.Tick(base.Add(75 * time.Second)); cmd == nil || *cmd != "off" {
		t.Fatalf("expected off, got %v", cmd)
	}
	// vào lại: motion + presence
	m.OnMotion(4, base.Add(100*time.Second))
	cmd := m.OnPresence(true, 5, base.Add(101*time.Second))
	if cmd == nil || *cmd != "on" {
		t.Fatalf("vào lại phải bật, got %v", cmd)
	}
}

// Lệnh tay phải giữ nguyên qua các Tick khi phòng không đổi trạng thái. Trước đây
// evaluate() so occupied != acDesired nên bẻ lại lệnh tay ngay ở Tick kế tiếp:
// người dùng bật điều hoà trong phòng trống thì công tắc nảy về tắt sau ~1 giây.
func TestManualSurvivesTicksWhileOccupancyUnchanged(t *testing.T) {
	base := time.Unix(1000, 0)
	m := New(cfg())

	m.SetManual(true)
	for i := 1; i <= 5; i++ {
		if cmd := m.Tick(base.Add(time.Duration(i) * time.Second)); cmd != nil {
			t.Fatalf("tick %d bẻ lại lệnh tay: %v", i, *cmd)
		}
	}
	if !m.Snapshot().ACDesired {
		t.Fatal("ac_desired phải giữ true sau lệnh tay")
	}
}

// Nhưng khi phòng THỰC SỰ đổi trạng thái thì tự động được quyền ghi đè lệnh tay —
// đúng giao kèo app hiển thị: "Lệnh tay có thể bị ghi đè khi phòng đổi trạng thái."
func TestOccupancyChangeOverridesManual(t *testing.T) {
	base := time.Unix(1000, 0)
	m := New(cfg())

	m.SetManual(true) // bật tay trong phòng trống
	m.OnMotion(1, base)
	cmd := m.OnPresence(true, 2, base.Add(2*time.Second))
	if cmd != nil {
		t.Fatalf("vào phòng khi đã bật tay: không cần lệnh mới, got %v", *cmd)
	}

	m.OnPresence(false, 3, base.Add(3*time.Second))
	cmd = m.Tick(base.Add(3*time.Second + cfg().ExitTimeout))
	if cmd == nil || *cmd != "off" {
		t.Fatalf("rời phòng phải tắt dù trước đó bật tay, got %v", cmd)
	}
	if m.Snapshot().ACDesired {
		t.Fatal("ac_desired phải là false sau khi ra khỏi phòng")
	}
}

// TestSetACStateGiuNguyenACDesired khoá lại ranh giới giữa hai khái niệm dễ lẫn:
// ACDesired là thứ HỆ muốn (do lệnh bật/tắt quyết định), còn ACReported* là thứ voice-node BÁO VỀ.
// Trộn hai cái là công tắc trong app nhảy lung tung mỗi khi board báo trạng thái.
func TestSetACStateGiuNguyenACDesired(t *testing.T) {
	m := New(Config{})
	m.SetManual(true)

	m.SetACState(false, 26)

	s := m.Snapshot()
	if !s.ACDesired {
		t.Fatal("SetACState không được đụng vào ACDesired")
	}
	if !s.ACStateKnown || s.ACReportedOn {
		t.Fatalf("known=%v on=%v, muốn known=true on=false", s.ACStateKnown, s.ACReportedOn)
	}
	if s.ACReportedTemp != 26 {
		t.Fatalf("ACReportedTemp = %d, muốn 26", s.ACReportedTemp)
	}
}

// Chưa nhận ac_state nào thì phải báo là chưa biết — 0 độ và "chưa biết" không được lẫn.
func TestACStateChuaBietThiCoCo(t *testing.T) {
	s := New(Config{}).Snapshot()
	if s.ACStateKnown {
		t.Fatal("chưa có ac_state mà ACStateKnown đã true")
	}
}

// Snapshot phải so sánh được bằng ==: main.go dùng `snap != lastSnap` để quyết định có đẩy lên
// WebSocket hay không. Thêm field kiểu con trỏ vào đây là so địa chỉ, luôn ra "đã đổi", và ticker
// mỗi giây sẽ bơm WS liên tục.
func TestSnapshotSoSanhDuocBangGiaTri(t *testing.T) {
	m := New(Config{})
	m.SetACState(true, 25)
	if m.Snapshot() != m.Snapshot() {
		t.Fatal("hai Snapshot cùng trạng thái phải bằng nhau — có field không so sánh theo giá trị")
	}
	m.SetACState(true, 26)
	if m.Snapshot() == (Snapshot{ACStateKnown: true, ACReportedOn: true, ACReportedTemp: 25}) {
		t.Fatal("đổi nhiệt độ mà Snapshot không đổi")
	}
}
