package store

import (
	"database/sql"
	"path/filepath"
	"testing"
	"time"
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

func sampleFixture() Sample {
	return Sample{
		TS:            1753000000000,
		Presence:      true,
		HRBpm:         0, // radar không đo được -> 0, không bịa số
		RespAmplitude: 0,
		Motion:        1,
		WeightKg:      0,
		Spo2:          0,
		TempC:         0,
		Humidity:      0,
		MovingDistCm:  120,
		MovingEnergy:  68,
		StillDistCm:   0,
		StillEnergy:   0,
		UARTOK:        true,
	}
}

func TestAppendSampleRoundTrip(t *testing.T) {
	s := newTestStore(t)
	in := sampleFixture()
	if err := s.AppendSample(in); err != nil {
		t.Fatalf("AppendSample: %v", err)
	}
	got, err := s.SamplesBetween(in.TS-1000, in.TS+1000)
	if err != nil {
		t.Fatalf("SamplesBetween: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("muốn 1 sample, có %d", len(got))
	}
	if got[0].TS != in.TS || !got[0].Presence || !got[0].UARTOK ||
		got[0].MovingDistCm != in.MovingDistCm || got[0].MovingEnergy != in.MovingEnergy {
		t.Errorf("sample lệch:\n got  %+v\n muốn %+v", got[0], in)
	}
}

func TestSamplesBetweenFiltersByWindow(t *testing.T) {
	s := newTestStore(t)
	// Mốc thật (epoch-ms) chứ không phải 1000/2000/3000: AppendSample loại mẫu có
	// ts vô lý, và trước đây bộ ba số đồ chơi này đi lọt vì chưa có cửa chặn.
	base := time.Now().UnixMilli()
	for _, off := range []int64{0, 1000, 2000} {
		sm := sampleFixture()
		sm.TS = base + off
		if err := s.AppendSample(sm); err != nil {
			t.Fatalf("AppendSample %d: %v", sm.TS, err)
		}
	}
	got, err := s.SamplesBetween(base+500, base+2000) // [+500, +2000) -> chỉ +1000
	if err != nil {
		t.Fatalf("SamplesBetween: %v", err)
	}
	if len(got) != 1 || got[0].TS != base+1000 {
		t.Errorf("muốn [+500,+2000) trả đúng +1000, có %+v", got)
	}
}

func TestRetainNightsKeeps30Nights(t *testing.T) {
	s := newTestStore(t)
	now := time.Now().UTC()
	base := now.Truncate(24 * time.Hour)

	// Mẫu 35 đêm trước: phải bị dọn.
	oldTS := base.AddDate(0, 0, -35).UnixMilli()
	// Mẫu 1 ngày trước: phải còn.
	recentTS := base.AddDate(0, 0, -1).UnixMilli()

	for _, ts := range []int64{oldTS, recentTS} {
		sm := sampleFixture()
		sm.TS = ts
		if err := s.AppendSample(sm); err != nil {
			t.Fatalf("AppendSample: %v", err)
		}
	}
	if err := s.RetainNights(30); err != nil {
		t.Fatalf("RetainNights: %v", err)
	}
	got, err := s.SamplesBetween(0, now.Add(24*time.Hour).UnixMilli())
	if err != nil {
		t.Fatalf("SamplesBetween: %v", err)
	}
	if len(got) != 1 || got[0].TS != recentTS {
		t.Errorf("retention phải dọn mẫu cũ hơn 30 đêm, chỉ giữ mẫu gần: %+v", got)
	}
}

// ---- seq/boot: truy nguyên nhân mất mẫu ----

func u32p(v uint32) *uint32 { return &v }

func TestAppendSampleRoundTripsSeqAndBoot(t *testing.T) {
	s := newTestStore(t)
	in := sampleFixture()
	in.Seq = u32p(7)
	in.Boot = u32p(2)
	if err := s.AppendSample(in); err != nil {
		t.Fatalf("AppendSample: %v", err)
	}
	got, err := s.SamplesBetween(in.TS-1000, in.TS+1000)
	if err != nil {
		t.Fatalf("SamplesBetween: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("muốn 1 sample, có %d", len(got))
	}
	if got[0].Seq == nil || *got[0].Seq != 7 {
		t.Errorf("seq: có %v, muốn 7", got[0].Seq)
	}
	if got[0].Boot == nil || *got[0].Boot != 2 {
		t.Errorf("boot: có %v, muốn 2", got[0].Boot)
	}
}

// Phân biệt "firmware chưa gửi seq" với "mẫu đầu tiên sau boot, seq=0" là toàn bộ lý do
// hai cột này nullable. Gộp hai trạng thái thành 0 làm hỏng phép đếm mất mẫu.
func TestAppendSampleKeepsNilSeqDistinctFromZero(t *testing.T) {
	s := newTestStore(t)
	old := sampleFixture()
	old.TS = 1753000000000
	fresh := sampleFixture()
	fresh.TS = 1753000000100
	fresh.Seq = u32p(0)
	fresh.Boot = u32p(0)
	for _, sm := range []Sample{old, fresh} {
		if err := s.AppendSample(sm); err != nil {
			t.Fatalf("AppendSample: %v", err)
		}
	}
	got, err := s.SamplesBetween(1753000000000, 1753000001000)
	if err != nil {
		t.Fatalf("SamplesBetween: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("muốn 2 sample, có %d", len(got))
	}
	if got[0].Seq != nil {
		t.Errorf("mẫu firmware cũ phải có seq=NULL, có %v", *got[0].Seq)
	}
	if got[1].Seq == nil || *got[1].Seq != 0 {
		t.Errorf("mẫu đầu sau boot phải có seq=0 (không phải NULL), có %v", got[1].Seq)
	}
}

func TestMigrationAddsSeqBootToExistingDb(t *testing.T) {
	path := filepath.Join(t.TempDir(), "legacy.db")
	// Dựng DB theo schema cũ (không có seq/boot) rồi để Open migrate.
	raw, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatalf("sql.Open: %v", err)
	}
	if _, err := raw.Exec(`CREATE TABLE samples (
		id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL,
		presence INTEGER NOT NULL DEFAULT 0, hr_bpm INTEGER NOT NULL DEFAULT 0,
		resp_amp REAL NOT NULL DEFAULT 0, motion INTEGER NOT NULL DEFAULT 0,
		weight_kg REAL NOT NULL DEFAULT 0, spo2 INTEGER NOT NULL DEFAULT 0,
		temp_c REAL NOT NULL DEFAULT 0, humidity REAL NOT NULL DEFAULT 0,
		moving_dist INTEGER NOT NULL DEFAULT 0, moving_eng INTEGER NOT NULL DEFAULT 0,
		still_dist INTEGER NOT NULL DEFAULT 0, still_eng INTEGER NOT NULL DEFAULT 0,
		uart_ok INTEGER NOT NULL DEFAULT 0)`); err != nil {
		t.Fatalf("dựng schema cũ: %v", err)
	}
	raw.Close()

	s, err := Open(path)
	if err != nil {
		t.Fatalf("Open trên DB cũ: %v", err)
	}
	defer s.Close()

	in := sampleFixture()
	in.Seq = u32p(11)
	if err := s.AppendSample(in); err != nil {
		t.Fatalf("AppendSample sau migrate: %v", err)
	}
	got, err := s.SamplesBetween(in.TS-1000, in.TS+1000)
	if err != nil {
		t.Fatalf("SamplesBetween: %v", err)
	}
	if len(got) != 1 || got[0].Seq == nil || *got[0].Seq != 11 {
		t.Errorf("migrate không thêm được cột: %+v", got)
	}
}

func TestOpenTwiceDoesNotDuplicateColumns(t *testing.T) {
	path := filepath.Join(t.TempDir(), "twice.db")
	s1, err := Open(path)
	if err != nil {
		t.Fatalf("Open lần 1: %v", err)
	}
	s1.Close()
	s2, err := Open(path)
	if err != nil {
		t.Fatalf("Open lần 2 (migrate phải idempotent): %v", err)
	}
	s2.Close()
}

// ---- độ bền ghi ở 10Hz ----

func TestOpenEnablesWAL(t *testing.T) {
	s := newTestStore(t)
	var mode string
	if err := s.db.QueryRow(`PRAGMA journal_mode`).Scan(&mode); err != nil {
		t.Fatalf("PRAGMA journal_mode: %v", err)
	}
	if mode != "wal" {
		t.Errorf("journal_mode=%q, muốn \"wal\" — rollback journal fsync mỗi commit, không theo kịp 10Hz", mode)
	}
}

func TestOpenSetsSynchronousNormal(t *testing.T) {
	s := newTestStore(t)
	var sync int
	if err := s.db.QueryRow(`PRAGMA synchronous`).Scan(&sync); err != nil {
		t.Fatalf("PRAGMA synchronous: %v", err)
	}
	if sync != 1 {
		t.Errorf("synchronous=%d, muốn 1 (NORMAL)", sync)
	}
}

func TestAppendSampleEnforcesCapAfterTrimInterval(t *testing.T) {
	s := newTestStore(t)
	s.maxSamples, s.trimInterval = 50, 10
	for i := 0; i < 200; i++ {
		sm := sampleFixture()
		sm.TS += int64(i)
		if err := s.AppendSample(sm); err != nil {
			t.Fatalf("AppendSample %d: %v", i, err)
		}
	}
	var n int64
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM samples`).Scan(&n); err != nil {
		t.Fatalf("count: %v", err)
	}
	// Giãn câu cắt nghĩa là vượt trần tối đa trimInterval dòng — không phải bỏ trần.
	if n > s.maxSamples+s.trimInterval {
		t.Errorf("có %d mẫu, trần %d + giãn %d", n, s.maxSamples, s.trimInterval)
	}
}

// Chứng minh câu DELETE thật sự đã được giãn: trần bằng 1 mà 10 mẫu vẫn còn nguyên
// vì chưa tới kỳ cắt. Nếu DELETE còn chạy mỗi insert thì chỉ còn 1 dòng.
func TestAppendSampleDoesNotTrimEveryInsert(t *testing.T) {
	s := newTestStore(t)
	s.maxSamples, s.trimInterval = 1, 100
	for i := 0; i < 10; i++ {
		sm := sampleFixture()
		sm.TS += int64(i)
		if err := s.AppendSample(sm); err != nil {
			t.Fatalf("AppendSample %d: %v", i, err)
		}
	}
	var n int64
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM samples`).Scan(&n); err != nil {
		t.Fatalf("count: %v", err)
	}
	if n != 10 {
		t.Errorf("có %d mẫu, muốn 10 — DELETE vẫn đang chạy mỗi insert", n)
	}
}

// Mẫu có mốc thời gian vô lý phải bị chặn ở cửa. Trường hợp 9999999999999 là
// dòng thật đã lọt vào home.db và kéo trục thời gian của biểu đồ ra năm 2286.
func TestAppendSampleRejectsImplausibleTS(t *testing.T) {
	st := newTestStore(t)
	now := time.Now().UnixMilli()

	for _, tc := range []struct {
		ten     string
		ts      int64
		muonLoi bool
	}{
		{"mốc rác xa tương lai", 9999999999999, true},
		{"MCU chưa đồng bộ NTP", 1000, true},
		{"epoch 0", 0, true},
		{"mốc hiện tại", now, false},
		{"lệch đồng hồ 1 giờ tới", now + 3600_000, false},
	} {
		err := st.AppendSample(Sample{TS: tc.ts, UARTOK: true})
		if tc.muonLoi && err == nil {
			t.Errorf("%s: ts=%d phải bị loại nhưng lại ghi được", tc.ten, tc.ts)
		}
		if !tc.muonLoi && err != nil {
			t.Errorf("%s: ts=%d phải ghi được, lỗi: %v", tc.ten, tc.ts, err)
		}
	}

	got, err := st.SamplesBetween(0, 1<<62)
	if err != nil {
		t.Fatalf("SamplesBetween: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("còn %d mẫu trong DB, muốn 2 (chỉ hai mốc hợp lệ)", len(got))
	}
}
