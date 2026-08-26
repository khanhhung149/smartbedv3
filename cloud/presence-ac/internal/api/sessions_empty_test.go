package api

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/hung/home-backend/internal/sessions"
)

// emptySessions trả về đúng thứ PGStore trả khi thiết bị chưa có phiên nào:
// slice nil, không phải slice rỗng.
type emptySessions struct{}

func (emptySessions) ListSessions(context.Context, string, *time.Time, *time.Time, int) ([]sessions.SessionRow, error) {
	return nil, nil
}
func (emptySessions) GetSession(context.Context, string) (*sessions.SessionRow, error) {
	return nil, nil
}
func (emptySessions) GetTimeline(context.Context, string, time.Time, *time.Time, string) ([]sessions.TimelinePoint, error) {
	return nil, nil
}
func (emptySessions) GetLatestSec(context.Context, string) (*sessions.LatestSec, error) {
	return nil, nil
}
func (emptySessions) MorningReport(context.Context, string, time.Time, time.Time) (*sessions.MorningReport, error) {
	return nil, nil
}

// Thiết bị chưa có phiên nào phải trả `[]`, không phải `null`.
//
// Slice nil của Go encode ra `null`; client ép thẳng sang mảng sẽ nổ. Đã xảy ra
// thật: app Flutter văng "type 'Null' is not a subtype of type 'List<dynamic>'"
// ngay khi trỏ vào một thiết bị mới chưa qua đêm nào.
func TestListSessionsEmptyReturnsArrayNotNull(t *testing.T) {
	h := NewRouterFull(fakeSP{}, &fakePub{}, nil, nil, nil, emptySessions{}, nil)
	w := do(t, h, http.MethodGet, "/api/sessions?device_id=NEWDEVICE", "")

	if w.Code != http.StatusOK {
		t.Fatalf("mã trạng thái = %d, muốn 200", w.Code)
	}
	if got := trimSpace(w.Body.String()); got != "[]" {
		t.Fatalf("thân phản hồi = %q, muốn %q", got, "[]")
	}
}

func trimSpace(s string) string {
	for len(s) > 0 && (s[len(s)-1] == '\n' || s[len(s)-1] == ' ' || s[len(s)-1] == '\t') {
		s = s[:len(s)-1]
	}
	return s
}
