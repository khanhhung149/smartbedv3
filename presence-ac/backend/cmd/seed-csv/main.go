// seed-csv — import dữ liệu take-home CSV (smartbed-sensor-stream) vào bảng samples SQLite.
//
// Công cụ PHASE 01 cho dashboard: khi chưa có sensor thật, seed dữ liệu chuẩn 10Hz này vào
// DB để xem trước dashboard "xem lại một đêm". Schema CSV thực tế của dataset:
//
//	timestamp_s, loadcell_kg, presence, motion_intensity, chest_disp, hr_bpm, spo2
//
// ánh xạ sang bảng samples:
//
//	t(epoch ms), presence, weight_kg(loadcell), motion, resp_amplitude(chest_disp),
//	hr_bpm, spo2 — các kênh dataset không có (temp_c, humidity, moving/still) để 0/NULL.
//
// Cách dùng:
//
//	go run ./cmd/seed-csv -db /tmp/samples.db -csv /path/to/smartbed-sensor-stream.csv \
//	    -start 2026-08-18T12:00:00Z    # mốc đêm để xem trên dashboard
package main

import (
	"encoding/csv"
	"flag"
	"fmt"
	"io"
	"os"
	"strconv"
	"time"

	"github.com/hung/home-backend/internal/store"
)

func main() {
	var dbPath, csvPath, startStr string
	var drop bool
	flag.StringVar(&dbPath, "db", "samples.db", "đường dẫn SQLite (tạo mới nếu chưa có)")
	flag.StringVar(&csvPath, "csv", "", "đường dẫn CSV take-home")
	flag.StringVar(&startStr, "start", "2026-08-18T12:00:00Z", "mốc UTC cho timestamp_s=0 (đêm cần xem)")
	flag.BoolVar(&drop, "drop", false, "xoá bảng samples hiện có trước khi seed")
	flag.Parse()

	if csvPath == "" {
		fmt.Fprintln(os.Stderr, "thiếu -csv")
		flag.Usage()
		os.Exit(2)
	}
	start, err := time.Parse(time.RFC3339, startStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "-start sai định dạng RFC3339: %v\n", err)
		os.Exit(2)
	}

	st, err := store.Open(dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "mở db: %v\n", err)
		os.Exit(1)
	}
	defer st.Close()

	if drop {
		if err := st.DropSamples(); err != nil {
			fmt.Fprintf(os.Stderr, "drop samples: %v\n", err)
			os.Exit(1)
		}
	}

	f, err := os.Open(csvPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "mở csv: %v\n", err)
		os.Exit(1)
	}
	defer f.Close()

	r := csv.NewReader(f)
	header, err := r.Read()
	if err != nil {
		fmt.Fprintf(os.Stderr, "đọc header: %v\n", err)
		os.Exit(1)
	}
	_ = header // bỏ qua: dùng vị trí cố định theo thứ tự cột của dataset
	// timestamp_s, loadcell_kg, presence, motion_intensity, chest_disp, hr_bpm, spo2

	var n int
	for {
		rec, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			fmt.Fprintf(os.Stderr, "đọc dòng %d: %v\n", n+2, err)
			os.Exit(1)
		}
		tsSec, _ := strconv.ParseFloat(rec[0], 64)
		load, _ := strconv.ParseFloat(rec[1], 64)
		present := rec[2] == "1"
		motion, _ := strconv.ParseFloat(rec[3], 64)
		chestDisp, _ := strconv.ParseFloat(rec[4], 64)
		hr, _ := strconv.ParseFloat(rec[5], 64)
		spo2, _ := strconv.ParseFloat(rec[6], 64)

		sm := store.Sample{
			TS:            start.Add(time.Duration(tsSec * float64(time.Second))).UnixMilli(),
			Presence:      present,
			HRBpm:         int(hr),
			RespAmplitude: chestDisp,
			Motion:        int(motion),
			WeightKg:      load,
			Spo2:          int(spo2),
			UARTOK:        true,
		}
		if err := st.AppendSample(sm); err != nil {
			fmt.Fprintf(os.Stderr, "seed dòng %d: %v\n", n+2, err)
			os.Exit(1)
		}
		n++
	}
	fmt.Printf("seeded %d mẫu vào %s (từ %s)\n", n, dbPath, start.Format(time.RFC3339))
}
