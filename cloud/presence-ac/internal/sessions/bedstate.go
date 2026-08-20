package sessions

// IsOnBed nói một mẫu sec_data có phải lúc người đang nằm trên đệm hay không,
// theo giao thức Legact Pro p.4 §2.4.1: nhịp tim và nhịp thở cùng về 0 khi rời
// giường. `status` là mã sự kiện của giây đó, không phải cờ chiếm giường, nên
// không suy ra occupancy từ nó.
//
// Đây là mảnh duy nhất của luật phiên còn nằm trong backend Go, và chỉ phục vụ
// cột bed_state của timeline. Luật dựng phiên (mở 30s, đóng 1800s, cap 1440
// phút) thuộc về builder Python trong backend sleep-pad-ai — Go chỉ đọc bảng
// sleep_sessions mà builder đó ghi. Nếu sửa ngưỡng ở đây thì phải sửa cùng chỗ
// trong sessions/rules.py, nếu không timeline và tóm tắt phiên sẽ lệch nhau.
func IsOnBed(hr *int32, rr *float64) bool {
	return (hr != nil && *hr > 0) || (rr != nil && *rr > 0)
}
