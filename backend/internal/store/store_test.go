package store

import (
	"path/filepath"
	"testing"
)

func newTestStore(t *testing.T) *Store {
	t.Helper()
	s, err := Open(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

func TestAppendThenListRoundTrip(t *testing.T) {
	s := newTestStore(t)
	in := Event{TS: 1752600000, Kind: KindPresence, Value: "true", Source: "room-node"}
	if err := s.Append(in); err != nil {
		t.Fatalf("Append: %v", err)
	}

	got, err := s.List(10, 0)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("muốn 1 event, có %d", len(got))
	}
	if got[0].TS != in.TS || got[0].Kind != in.Kind || got[0].Value != in.Value || got[0].Source != in.Source {
		t.Errorf("event lệch:\n got  %+v\n muốn %+v", got[0], in)
	}
	if got[0].ID == 0 {
		t.Error("ID phải được gán tự động, đang là 0")
	}
}

func TestListReturnsNewestFirst(t *testing.T) {
	s := newTestStore(t)
	for _, v := range []string{"a", "b", "c"} {
		if err := s.Append(Event{TS: 1, Kind: KindACCmd, Value: v, Source: "backend"}); err != nil {
			t.Fatalf("Append %s: %v", v, err)
		}
	}
	got, err := s.List(10, 0)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	want := []string{"c", "b", "a"}
	for i, w := range want {
		if got[i].Value != w {
			t.Errorf("vị trí %d: có %q, muốn %q (phải mới nhất trước)", i, got[i].Value, w)
		}
	}
}

func TestListPaginatesWithBefore(t *testing.T) {
	s := newTestStore(t)
	for i := 0; i < 5; i++ {
		if err := s.Append(Event{TS: int64(i), Kind: KindMotion, Value: "true", Source: "voice-node"}); err != nil {
			t.Fatalf("Append: %v", err)
		}
	}
	page1, err := s.List(2, 0)
	if err != nil {
		t.Fatalf("List trang 1: %v", err)
	}
	if len(page1) != 2 {
		t.Fatalf("trang 1 muốn 2 event, có %d", len(page1))
	}

	page2, err := s.List(2, page1[len(page1)-1].ID)
	if err != nil {
		t.Fatalf("List trang 2: %v", err)
	}
	if len(page2) != 2 {
		t.Fatalf("trang 2 muốn 2 event, có %d", len(page2))
	}
	if page2[0].ID >= page1[len(page1)-1].ID {
		t.Errorf("trang 2 phải toàn id nhỏ hơn trang 1: page2[0].ID=%d, page1 cuối=%d",
			page2[0].ID, page1[len(page1)-1].ID)
	}
}

func TestListEmptyReturnsEmptySliceNotNil(t *testing.T) {
	s := newTestStore(t)
	got, err := s.List(10, 0)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if got == nil {
		t.Error("phải trả slice rỗng (JSON ra []), đang trả nil (JSON ra null)")
	}
	if len(got) != 0 {
		t.Errorf("muốn 0 event, có %d", len(got))
	}
}

func TestListClampsLimit(t *testing.T) {
	s := newTestStore(t)
	for i := 0; i < 3; i++ {
		if err := s.Append(Event{TS: 1, Kind: KindMotion, Value: "true", Source: "voice-node"}); err != nil {
			t.Fatalf("Append: %v", err)
		}
	}
	// limit<=0 → dùng default, không trả rỗng
	got, err := s.List(0, 0)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(got) != 3 {
		t.Errorf("limit=0 phải dùng default (%d), có %d event", defaultLimit, len(got))
	}
}

func TestAppendTrimsBeyondMaxRows(t *testing.T) {
	s := newTestStore(t)
	for i := 0; i < maxRows+10; i++ {
		if err := s.Append(Event{TS: int64(i), Kind: KindMotion, Value: "true", Source: "voice-node"}); err != nil {
			t.Fatalf("Append %d: %v", i, err)
		}
	}
	var n int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM events`).Scan(&n); err != nil {
		t.Fatalf("count: %v", err)
	}
	if n > maxRows {
		t.Errorf("có %d event, không được vượt maxRows=%d", n, maxRows)
	}
	// Event mới nhất phải còn — cắt phải bỏ CŨ nhất, không phải mới nhất.
	got, err := s.List(1, 0)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if got[0].TS != int64(maxRows+9) {
		t.Errorf("event mới nhất TS=%d, muốn %d — cắt nhầm phía mới", got[0].TS, maxRows+9)
	}
}

func TestReopenKeepsData(t *testing.T) {
	path := filepath.Join(t.TempDir(), "persist.db")
	s1, err := Open(path)
	if err != nil {
		t.Fatalf("Open lần 1: %v", err)
	}
	if err := s1.Append(Event{TS: 42, Kind: KindACCmd, Value: "on", Source: "backend"}); err != nil {
		t.Fatalf("Append: %v", err)
	}
	s1.Close()

	// Mở lại = mô phỏng restart backend: dữ liệu phải còn, đây là lý do tồn tại của store.
	s2, err := Open(path)
	if err != nil {
		t.Fatalf("Open lần 2: %v", err)
	}
	defer s2.Close()

	got, err := s2.List(10, 0)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(got) != 1 || got[0].TS != 42 {
		t.Errorf("dữ liệu không sống qua restart: %+v", got)
	}
}
