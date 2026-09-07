# Brainstorm: Mac-style Windows Terminal (WSL) + Rounded-Pill Statusline cho Claude Code

Date: 2026-09-04 | Status: Design approved, sang `/ck:plan`

## 1. Problem statement

User dùng Windows Terminal chạy WSL (Ubuntu), muốn UI/UX giống macOS iTerm2 + muốn statusline Claude Code có look "rounded pill" giống thanh trạng thái macOS, áp cho toàn bộ workflow Claude Code của họ (không chỉ project hiện tại).

## 2. Requirements (chốt qua AskUserQuestion)

- **Expected output**:
  a) Windows Terminal profile "Ubuntu-Recovered" (guid `{d631440c-124e-5f2f-a177-265d1e3bdb2b}`, = defaultProfile hiện tại) dùng font MesloLGS Nerd Font, colorScheme Catppuccin Macchiato, opacity ~82% + useAcrylic.
  b) Module render "pill" dùng chung (`~/.claude/lib/statusline-pill-theme.cjs`).
  c) smartbedv3: statusline hiện có (`statusline.cjs` + section-registry + render-modes) đổi giao diện sang pill, **giữ nguyên toàn bộ data/tính năng** (git, context%, quota, agents, todos, cost, activePlan).
  d) Global (`~/.claude/settings.json`): statusline pill rút gọn (dir/git/model/context) cho mọi project Claude Code khác không có ClaudeKit hooks.
- **Acceptance criteria**: font hiện đúng tên trong Windows Terminal font picker; scheme Catppuccin Macchiato + acrylic áp dụng đúng profile Ubuntu-Recovered; statusline smartbedv3 hiển thị pill nhưng không mất section nào so với hiện tại; statusline project khác (không .claude riêng) hiện pill rút gọn.
- **Scope boundary**: KHÔNG đụng profile PowerShell/CMD/Azure Cloud Shell/Dev Prompt. KHÔNG port agents/todos/quota sang global (không có data nguồn ở project khác — YAGNI).
- **Constraints**: font phải từ nguồn hợp pháp (Nerd Fonts official release), không dùng "SF Mono Nerd Font" (không tồn tại bản patch hợp pháp — SF Mono là font độc quyền Apple). Đổi trong smartbedv3 phải giữ "zero regression" như comment gốc trong `statusline-render-modes.cjs`. Global config không git-track (nằm ngoài repo).
- **Touchpoints**:
  - `/mnt/c/Users/HP/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json` (ngoài repo)
  - Windows Fonts (cài qua `powershell.exe` từ WSL)
  - Mới: `~/.claude/lib/statusline-pill-theme.cjs`, `~/.claude/statusline.cjs`, sửa `~/.claude/settings.json` (ngoài repo, global)
  - Sửa: `/mnt/d/smartbedv3/.claude/hooks/lib/statusline-render-modes.cjs`, `statusline-section-registry.cjs`, `.ck.json` (trong repo, cần commit theo conventional-commit)

## 3. Approaches đánh giá

| Approach | Ưu | Nhược | Quyết định |
|---|---|---|---|
| Chỉ smartbedv3 | An toàn, nhanh nhất | Không áp cho project Claude khác — không đúng yêu cầu gốc "toàn bộ dự án" | Không chọn |
| Chỉ global | 1 script, áp mọi nơi | Bỏ phí hệ thống statusline.cjs phức tạp đã có (agents/todos/quota) trong smartbedv3 nếu global ghi đè, hoặc không áp dụng gì cho smartbedv3 nếu không ghi đè | Không chọn |
| **Cả hai, module dùng chung** | Data-rich ở smartbedv3 vẫn giữ nguyên; project khác vẫn có pill nhìn nhất quán; không port tính năng vô nghĩa | Tốn thêm 1 module trung gian + phải test ở 2 nơi | **Chọn** — cân bằng đúng theo scope đã chốt |

## 4. Final solution (approved design)

**A. Windows Terminal** — sửa profile Ubuntu-Recovered only:
- `font.face: "MesloLGS Nerd Font"`
- Thêm `schemes[]` entry "Catppuccin Macchiato" (palette chính thức catppuccin/windows-terminal: bg `#24273A`, fg `#CAD3F5`, accent theo palette Macchiato chuẩn), set làm `colorScheme` của profile.
- `opacity: 82`, `useAcrylic: true`.
- Cài MesloLGS NF từ GitHub release chính thức `ryanoasis/nerd-fonts` qua `powershell.exe` (copy .ttf vào `%LOCALAPPDATA%\Microsoft\Windows\Fonts` + registry per-user, không cần admin).

**B. Module pill dùng chung** — `~/.claude/lib/statusline-pill-theme.cjs`:
- `renderPill(sections, theme)`: mỗi section `{icon, text, colorKey}` → in glyph Nerd Font bo tròn 2 đầu + nền màu block, map theo palette Catppuccin Macchiato 8 màu accent.
- Không phụ thuộc `.ck.json`/session-state → tái dùng được cả 2 nơi.

**C. smartbedv3** (trong repo, commit conventional):
- `statusline-section-registry.cjs` + `statusline-render-modes.cjs`: thêm theme "pill" gọi module B, giữ nguyên pipeline data hiện tại (git/context/quota/agents/todos/cost/activePlan).
- Bật qua `.ck.json` (`statuslineLayout.theme` hoặc field tương đương pattern hiện có).

**D. Global** (ngoài repo):
- `~/.claude/statusline.cjs` mới, dùng module B, chỉ có dir/git/model/context (data trực tiếp từ stdin JSON chuẩn Claude Code).
- `~/.claude/settings.json` thêm `statusLine` trỏ script này. Project settings vẫn ưu tiên hơn global nên smartbedv3 không bị ghi đè.

## 5. Risks & rollback

- Windows Terminal + font: rủi ro thấp, dễ revert (sửa lại `font.face`/xoá scheme entry, gỡ font qua Settings > Fonts).
- smartbedv3 statusline: đi qua git, rollback bằng `git checkout` nếu regression.
- Global script: file mới, không ảnh hưởng gì đang chạy (global chưa có `statusLine` trước đó).

## 6. Success metrics / validation

- Mở Windows Terminal → profile Ubuntu-Recovered hiện đúng font MesloLGS, màu Catppuccin Macchiato, nền hơi trong suốt.
- Trong smartbedv3: chạy Claude Code, statusline hiện dạng pill, đủ agents/todos/quota/git/context như trước (so sánh trước/sau).
- Mở Claude Code ở project khác (không .claude riêng): statusline hiện pill rút gọn dir/git/model/context.

## 7. Next steps

Chuyển sang `/ck:plan` để chia phase thực thi cụ thể (A/B/C/D ở trên là 4 nhóm việc tương đối độc lập, có thể làm phase riêng).

## Unresolved questions

Không còn — mọi quyết định (scope, font, color scheme, cách thực hiện) đã chốt qua AskUserQuestion trong phiên brainstorm này.
