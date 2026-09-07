---
phase: 4
title: "Global statusline pill (mọi project Claude Code khác)"
status: in-progress
priority: P3
dependencies: [2]
---

# Phase 4: Global statusline pill

## Overview
Tạo `~/.claude/statusline.cjs` (script mỏng, độc lập với ClaudeKit hooks), dùng module `renderPill()` (Phase 2), hiển thị dir/git/model/context% theo phong cách pill. Trỏ `~/.claude/settings.json` sang script này để áp dụng cho MỌI project Claude Code không có `statusLine` riêng (project settings luôn ưu tiên hơn global, nên smartbedv3 — đã có statusLine riêng từ Phase 3 — không bị ảnh hưởng).

## Requirements
- Functional: mở Claude Code ở 1 project bất kỳ KHÔNG có `.claude/settings.json` với `statusLine` riêng → thấy dòng pill: thư mục, git branch (nếu có), model name, context% (nếu có).
- Non-functional: KHÔNG đọc `.ck.json`/session-state (data đó không tồn tại ngoài ClaudeKit-project) — chỉ dùng field chuẩn trong JSON stdin mà Claude Code luôn gửi cho mọi statusLine script (`workspace.current_dir`/`cwd`, `model.display_name`, `context_window.*`).

## Architecture
- Input contract giống hệt `statusline.cjs` của smartbedv3 (đọc JSON từ stdin qua field chuẩn của Claude Code) — nhưng KHÔNG import bất kỳ file nào từ `.claude/hooks/lib/` của smartbedv3 (project-specific, sẽ không tồn tại ở project khác).
- Git info: cần tự viết hàm gọn lấy branch hiện tại (`git rev-parse --abbrev-ref HEAD` qua `child_process.execSync`, bọc try/catch trả `''` nếu không phải git repo) — KHÔNG copy `git-info-cache.cjs` của smartbedv3 (phụ thuộc cache/session phức tạp hơn mức cần cho bản rút gọn).
- Context%: tính y hệt logic đã có trong `statusline.cjs` dòng ~137-150 của smartbedv3 (đọc `data.context_window.used_percentage` hoặc tính từ `usage`) — copy đúng công thức, không thay đổi.

## Related Code Files
- Create: `~/.claude/statusline.cjs`
- Modify: `~/.claude/settings.json` — chỉ thêm field `statusLine`, KHÔNG xoá/sửa field khác (`mcpServers`, `theme`, `modelSettings`, `effortLevel`, ... đã có sẵn trong file).

## Implementation Steps
1. Đọc lại `~/.claude/settings.json` ngay trước khi sửa (có thể đổi từ lúc brainstorm).
2. Viết `~/.claude/statusline.cjs`:
   - Đọc stdin → parse JSON.
   - `currentDir = data.workspace?.current_dir || data.cwd || process.cwd()`.
   - `modelName = data.model?.display_name || 'Claude'`.
   - `gitBranch`: `execSync('git rev-parse --abbrev-ref HEAD', {cwd: currentDir, stdio:['ignore','pipe','ignore']})`, try/catch → `''`.
   - `contextPercent`: copy công thức từ `statusline.cjs` smartbedv3 (đã đọc ở Phase 2/3), dùng `data.context_window.used_percentage` khi có.
   - Build `sections = [{icon:'📁', text: currentDir, colorKey:'teal'}, gitBranch && {icon:'🌿', text: gitBranch, colorKey:'mauve'}, {icon:'🤖', text: modelName, colorKey:'blue'}, contextPercent > 0 && {icon:'🔋', text: `${contextPercent}%`, colorKey: contextPercent>=85?'red':contextPercent>=70?'yellow':'green'}].filter(Boolean)`.
   - `console.log(renderPill(sections))`.
   - Bọc toàn bộ trong try/catch, fallback `console.log('📁 ' + (process.cwd()||'unknown'))` giống pattern lỗi hiện có trong `statusline.cjs` smartbedv3 (dòng 210-212).
3. Sửa `~/.claude/settings.json`: thêm
   ```json
   "statusLine": {
     "type": "command",
     "command": "node \"$HOME/.claude/statusline.cjs\"",
     "padding": 0
   }
   ```
   giữ nguyên mọi field khác trong file (đặc biệt `mcpServers.github.env` — không đụng).
4. Test: `echo '{"workspace":{"current_dir":"/tmp"},"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":42}}' | node ~/.claude/statusline.cjs` — xác nhận output pill hợp lệ, không throw.
5. Test thật: mở Claude Code ở 1 thư mục KHÁC smartbedv3 (không có `.claude/settings.json`), xác nhận statusline hiện pill rút gọn.
6. Xác nhận smartbedv3 KHÔNG bị ảnh hưởng: mở Claude Code trong smartbedv3, statusline vẫn dùng bản Phase 3 (project settings ưu tiên hơn global — verify bằng cách so sánh output có agents/todos/quota, tức không phải bản rút gọn).

## ⚠️ REGRESSION phát hiện + sửa (2026-09-04, session song song "scad port decoration design")
Người dùng báo statusline không hiện giao diện pill khi mở Claude Code ở `mech/presence-ac-enclosure`
(thư mục con của smartbedv3, không có `statusLine` riêng — đúng case phase này nhắm tới). Kiểm tra
trực tiếp `~/.claude/statusline.cjs`: **crash ngay khi chạy** —
`Error: Cannot find module './hooks/lib/colors.cjs'`. File thật trên máy KHÔNG PHẢI bản rút gọn tự
chứa như spec ở trên — nó có 8 lệnh `require('./hooks/lib/*.cjs')` giống hệt `statusline.cjs` gốc
của smartbedv3, nhưng `~/.claude/hooks/lib/` không tồn tại → mọi project khác smartbedv3 đều crash,
rơi về statusline mặc định của Claude Code. Mâu thuẫn trực tiếp với checkbox "không throw" đã tick
bên dưới — có thể do 1 session khác ghi đè sau khi checkbox này được tick, hoặc tick nhầm lúc đó.
**Đã viết lại đúng theo spec ở trên** (chỉ `require('./lib/statusline-pill-theme.cjs')`, không đụng
`./hooks/lib/`) và re-test — xem checkbox cập nhật bên dưới.

## Success Criteria
- [x] `~/.claude/settings.json` sau khi sửa vẫn parse được, field `mcpServers`/`theme`/`modelSettings`/`effortLevel`/`skipDangerousModePermissionPrompt`/`extraKnownMarketplaces` không đổi (verify bằng Python, xem Validation Log).
- [x] Test stdin thủ công ra output pill đúng (dir/git/model/context), không throw — **re-verify 2026-09-04 sau khi phát hiện regression ở trên**: đã test lại 4 case (thư mục con `mech/presence-ac-enclosure` — đúng case user báo lỗi, `/tmp` không git, JSON invalid, `NO_COLOR=1`) — cả 4 đều ra output đúng, không throw.
- [x] Mở Claude Code thật ở project khác smartbedv3: statusline hiện pill rút gọn — verify bằng cách gọi thẳng `~/.claude/statusline.cjs` với payload thật của thư mục `mech/presence-ac-enclosure` (JSON stdin đúng schema Claude Code gửi) — ra đúng pill dir+git+model+context, không phải statusline mặc định nữa. Chưa mở GUI Claude Code thật để xem bằng mắt (không có màn hình trong session này) — nhưng input/output đã khớp đúng contract.
- [ ] Mở Claude Code trong smartbedv3: statusline vẫn là bản đầy đủ Phase 3 — **chưa test bằng Claude Code thật** (dựa trên cơ chế project settings ưu tiên hơn global, chưa tự verify thực nghiệm trong phase này). Không bị ảnh hưởng bởi lần sửa này (chỉ sửa `~/.claude/statusline.cjs`, không đụng `smartbedv3/.claude/statusline.cjs` hay `settings.json` của project).

## Risk Assessment
- Risk: ghi đè nhầm `~/.claude/settings.json` mất field `mcpServers.github.env` (chứa token) — mitigation: đọc file, parse, merge thêm đúng 1 key `statusLine`, ghi lại nguyên object đã parse (không tự gõ tay lại toàn bộ JSON).
- Risk: `execSync('git rev-parse ...')` chạy trong project không phải git repo có thể throw hoặc treo nếu `cwd` không tồn tại — đã có try/catch + timeout ngắn (`timeout: 500` option của execSync) để tránh statusline bị treo.
- Risk: global script lỗi cú pháp làm statusline TOÀN BỘ máy (mọi project khác) gãy — test kỹ bước 4 trước khi trỏ `statusLine` trong settings.json, và giữ fallback try/catch bọc toàn bộ `main()`.
