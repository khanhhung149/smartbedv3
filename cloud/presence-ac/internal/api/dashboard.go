package api

import (
	"embed"
	"io/fs"
)

//go:embed dashboard/index.html
var dashboardFiles embed.FS

// dashboardFS trả FS chứa trang dashboard local web. Chỉ có 1 file nên trả trực tiếp
// subtree gốc để http.FileServer tìm /index.html mặc định.
func dashboardFS() (fs.FS, error) {
	return fs.Sub(dashboardFiles, "dashboard")
}
