package events

import (
	"encoding/json"
	"testing"
)

// Firmware chưa có bộ đếm vẫn phải parse được — hai loại node có thể chạy lẫn trên cùng
// broker trong lúc chuyển đổi.
func TestSampleWithoutSeqLeavesCountersNil(t *testing.T) {
	raw := `{"t":1753000000000,"presence":true,"hr_bpm":0,"resp_amplitude":0,"motion":1,
	         "weight_kg":0,"spo2":0,"temp_c":0,"humidity":0,"moving_dist_cm":120,
	         "moving_energy":68,"still_dist_cm":0,"still_energy":0,"uart_ok":true}`
	var sm Sample
	if err := json.Unmarshal([]byte(raw), &sm); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if sm.Seq != nil || sm.Boot != nil {
		t.Errorf("firmware cũ phải cho seq/boot nil, có %v/%v", sm.Seq, sm.Boot)
	}
	if sm.TS != 1753000000000 || !sm.Presence || sm.MovingDistCm != 120 {
		t.Errorf("các trường còn lại lệch: %+v", sm)
	}
}

func TestSampleParsesSeqAndBoot(t *testing.T) {
	raw := `{"t":1753000000000,"presence":false,"hr_bpm":0,"resp_amplitude":0,"motion":0,
	         "weight_kg":0,"spo2":0,"temp_c":0,"humidity":0,"moving_dist_cm":0,
	         "moving_energy":0,"still_dist_cm":0,"still_energy":0,"uart_ok":false,
	         "seq":0,"boot":3}`
	var sm Sample
	if err := json.Unmarshal([]byte(raw), &sm); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	// seq=0 là mẫu đầu tiên sau khởi động — phải là con trỏ khác nil, không phải nil.
	if sm.Seq == nil || *sm.Seq != 0 {
		t.Errorf("seq: có %v, muốn con trỏ tới 0", sm.Seq)
	}
	if sm.Boot == nil || *sm.Boot != 3 {
		t.Errorf("boot: có %v, muốn 3", sm.Boot)
	}
}

func TestSampleAcceptsMaxUint32Counters(t *testing.T) {
	raw := `{"t":1,"seq":4294967295,"boot":4294967295}`
	var sm Sample
	if err := json.Unmarshal([]byte(raw), &sm); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if sm.Seq == nil || *sm.Seq != 4294967295 {
		t.Errorf("seq tràn: %v", sm.Seq)
	}
}

// Payload thật do build_sample_json dựng ở giá trị dài nhất — 259 byte, sát trần buffer 288
// của firmware. Đây là ca từng làm snprintf cắt cụt im lặng khi buffer còn 256.
func TestSampleParsesLongestFirmwarePayload(t *testing.T) {
	const golden = `{"t":9999999999999,"presence":false,"hr_bpm":0,"resp_amplitude":0,` +
		`"motion":0,"weight_kg":0,"spo2":0,"temp_c":0,"humidity":0,"moving_dist_cm":65535,` +
		`"moving_energy":255,"still_dist_cm":65535,"still_energy":255,"uart_ok":false,` +
		`"seq":4294967295,"boot":4294967295}`
	if len(golden) != 259 {
		t.Fatalf("payload mẫu dài %d byte, phải là 259 — firmware đã đổi schema?", len(golden))
	}
	var sm Sample
	if err := json.Unmarshal([]byte(golden), &sm); err != nil {
		t.Fatalf("Unmarshal payload dài nhất: %v", err)
	}
	if sm.Seq == nil || *sm.Seq != 4294967295 || sm.Boot == nil || *sm.Boot != 4294967295 {
		t.Errorf("bộ đếm lệch: seq=%v boot=%v", sm.Seq, sm.Boot)
	}
	if sm.MovingDistCm != 65535 || sm.StillEnergy != 255 {
		t.Errorf("kênh raw lệch: %+v", sm)
	}
}
