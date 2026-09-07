package events

import (
	"encoding/json"
	"testing"
)

func TestSnoreEventUnmarshalFirmwarePayload(t *testing.T) {
	var got SnoreEvent
	if err := json.Unmarshal([]byte(`{"ts":123456,"confidence":0.873,"duration_ms":3000}`), &got); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if got.TS != 123456 || got.Confidence != 0.873 || got.DurationMS != 3000 {
		t.Fatalf("payload lệch: %+v", got)
	}
}

func TestSnoreEventUnmarshalAllowsMissingDuration(t *testing.T) {
	var got SnoreEvent
	if err := json.Unmarshal([]byte(`{"ts":123456,"confidence":0.873}`), &got); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if got.DurationMS != 0 {
		t.Fatalf("duration_ms thiếu phải là 0, có %d", got.DurationMS)
	}
}

func TestSnoreEventUnmarshalRejectsGarbage(t *testing.T) {
	var got SnoreEvent
	if err := json.Unmarshal([]byte(`not json`), &got); err == nil {
		t.Fatal("payload rác phải lỗi")
	}
}

func TestSnoreEventUnmarshalKeepsOutOfRangeConfidence(t *testing.T) {
	var got SnoreEvent
	if err := json.Unmarshal([]byte(`{"ts":1,"confidence":1.25,"duration_ms":1000}`), &got); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if got.Confidence != 1.25 {
		t.Fatalf("confidence phải được lưu nguyên, có %v", got.Confidence)
	}
}
