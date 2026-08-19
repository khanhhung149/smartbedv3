package config

import "testing"

func TestRedactedPostgresURL(t *testing.T) {
	tests := []struct {
		name string
		dsn  string
		want string
	}{
		{
			name: "mật khẩu bị che, phần còn lại giữ nguyên để còn chẩn đoán được",
			dsn:  "postgres://sleeptech:devpassword@host.docker.internal:5432/sleeptech",
			want: "postgres://sleeptech:xxxxx@host.docker.internal:5432/sleeptech",
		},
		{
			name: "không có mật khẩu thì không thêm gì",
			dsn:  "postgres://sleeptech@localhost:5432/sleeptech",
			want: "postgres://sleeptech@localhost:5432/sleeptech",
		},
		{
			name: "rỗng vẫn rỗng",
			dsn:  "",
			want: "",
		},
		{
			name: "DSN hỏng không được rơi ngược về chuỗi gốc",
			dsn:  "postgres://user:pw@%%%/db",
			want: "(DSN không phân tích được)",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Config{PostgresURL: tt.dsn}.RedactedPostgresURL()
			if got != tt.want {
				t.Fatalf("got %q, want %q", got, tt.want)
			}
		})
	}
}

// Mật khẩu không được lọt ra dù DSN có hình dạng nào.
func TestRedactedPostgresURLNeverLeaksSecret(t *testing.T) {
	const secret = "devpassword"
	for _, dsn := range []string{
		"postgres://sleeptech:" + secret + "@host:5432/db",
		"postgres://sleeptech:" + secret + "@host:5432/db?sslmode=disable",
		"postgresql://u:" + secret + "@[::1]:5432/db",
	} {
		if got := (Config{PostgresURL: dsn}).RedactedPostgresURL(); contains(got, secret) {
			t.Fatalf("mật khẩu lọt vào log: %q", got)
		}
	}
}

func contains(haystack, needle string) bool {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return true
		}
	}
	return false
}
