---
status: in-progress
priority: P3
scope: project
blockedBy: []
blocks: []
---

# Đổi Windows Terminal (WSL) sang phong cách Mac + statusline "rounded pill"

## Bối cảnh
Xem đầy đủ phân tích/quyết định: `plans/reports/brainstorm-terminal-and-statusline-260904-1049-mac-style-pill-design-report.md`.

Scope đã chốt qua brainstorm: làm cả (A) Windows Terminal (font MesloLGS NF + colorScheme Catppuccin Macchiato + acrylic), (B) module render "pill" dùng chung, (C) smartbedv3 statusline đổi giao diện pill nhưng giữ nguyên toàn bộ tính năng hiện có, (D) global statusline pill rút gọn cho project Claude Code khác.

## Mục tiêu (Definition of Done)
- [x] Windows Terminal profile "Ubuntu-Recovered" (guid `{d631440c-124e-5f2f-a177-265d1e3bdb2b}`) dùng font MesloLGS NF, colorScheme "Catppuccin Macchiato", `opacity: 82`, `useAcrylic: true`.
- [x] `~/.claude/lib/statusline-pill-theme.cjs` tồn tại, export `renderPill()`, không phụ thuộc `.ck.json`/session-state.
- [x] smartbedv3 statusline (`statusline.cjs` qua `statusline-render-modes.cjs`) hiển thị giao diện pill, giữ nguyên đủ section: directory, git, model, context%, quota, agents, todos, cost, activePlan — không regression (code + 175 test tự động verify; chỉ còn xem bằng mắt trong Windows Terminal thật là chưa làm).
- [x] `~/.claude/statusline.cjs` (global) + `~/.claude/settings.json` có `statusLine` trỏ script này, hiển thị pill rút gọn (dir/git/model/context) khi mở Claude Code ở project không có ClaudeKit hooks (verify bằng CLI; chưa mở Claude Code thật ở project khác để xem bằng mắt).

## Ngoài phạm vi
- Không đụng profile PowerShell/CMD/Azure Cloud Shell/Dev Command Prompt trong Windows Terminal.
- Không port agents/todos/quota/cost sang global script (project khác không có data nguồn — YAGNI).
- Không dùng "SF Mono Nerd Font" (không có bản patch hợp pháp, SF Mono là font độc quyền Apple).

## Kiến trúc chung
Phase 2 (module pill dùng chung) là nền tảng cho cả Phase 3 (project) và Phase 4 (global) — không trùng lặp code vẽ pill giữa 2 nơi (DRY). Phase 1 (Windows Terminal) độc lập hoàn toàn, có thể làm song song.

## Phases
1. `phase-01-windows-terminal-font-theme.md` — cài MesloLGS NF, colorScheme Catppuccin Macchiato, opacity/acrylic cho profile Ubuntu-Recovered.
2. `phase-02-shared-pill-render-module.md` — viết module `renderPill()` dùng chung (glyph Nerd Font bo tròn + palette Catppuccin Macchiato).
3. `phase-03-smartbedv3-statusline-pill.md` — hook module pill vào statusline hiện có của smartbedv3, giữ nguyên tính năng. **Phụ thuộc Phase 2.**
4. `phase-04-global-statusline-pill.md` — script global rút gọn dùng chung module pill. **Phụ thuộc Phase 2.**

## Rủi ro
- Cài font từ nguồn `romkatv/powerlevel10k-media` (ghim commit SHA cụ thể, xem Validation Log) — đã tải + cài + verify registry thành công lúc implement, rủi ro chỉ còn ở lần chạy lại sau này nếu commit bị xoá.
- Sửa `statusline-render-modes.cjs`/`statusline-section-registry.cjs` (Phase 3) có nguy cơ regression cho statusline hiện tại — code gốc có comment "zero regression guarantee" khi không có `statuslineLayout` config, Phase 3 phải giữ đúng nguyên tắc này (pill chỉ là 1 theme mới, không đổi default).
- Global settings.json (`~/.claude/settings.json`) hiện đã có `mcpServers.github` — Phase 4 chỉ thêm field `statusLine`, không được xoá/sửa field khác trong file này.

## Validation Log

### Verification Results (Validation Session 1, 2026-09-04)
- Tier: Standard (4 phase → Fact Checker + Contract Verifier)
- Claims checked: ~12 (guid/defaultProfile, profiles.defaults, schemes[] rỗng, colors.cjs 16-color, statusline-string-utils.cjs ANSI-strip pattern, test suite tồn tại + chạy được, config file path, resolveLayout() shape, ~/.claude/settings.json fields, statusline.cjs fallback pattern, context_window.used_percentage field)
- Verified: 11 | Failed: 1 | Unverified: 0
- Failures: Phase 3 ghi sai đường dẫn config `.ck.json` (root) — thật ra `loadConfig()` đọc `.claude/.ck.json` (`ck-config-utils.cjs:13`, `LOCAL_CONFIG_PATH`). Đã sửa trong `phase-03-smartbedv3-statusline-pill.md` (Architecture, Related Code Files, Implementation Steps, Success Criteria).
- Baseline test suite trước khi implement: `node .claude/hooks/lib/__tests__/statusline-suite.cjs` → 38/38 pass.

### Quyết định (2026-09-04)
1. ~~Icon fallback trong pillifyLine (Phase 3): dùng bảng SECTION_DEFAULT_ICON cố định theo section id~~ — <!-- Updated: Implementation Session, superseded --> **SUPERSEDED lúc implement**: thiết kế thật đơn giản/robust hơn — icon tách trực tiếp từ chuỗi đã render (`splitIconText`, quy ước `${icon} ${rest}` universal), không dùng bảng tĩnh nào (bảng tĩnh ban đầu đã gây ra bug thật, xem code-reviewer finding #1 bên dưới).
2. **Font MesloLGS NF (Phase 1)**: nguồn thật là `romkatv/powerlevel10k-media` (không phải `ryanoasis/nerd-fonts` như ước tính brainstorm — family name không khớp) — đã ghim commit SHA `145eb9fbc2f42ee408dacd9b22d8e6e0e553f83d` để reproducible.
3. **Opacity Windows Terminal (Phase 1)**: giữ nguyên 82% như thiết kế ban đầu.

### Implementation Session (2026-09-04)
- Phase 1, 2, 4: implement xong, verify bằng CLI (registry font, diff settings.json, stdin test).
- Phase 3: implement xong, `code-reviewer` subagent review phát hiện:
  - **High (đã sửa)**: icon/màu pill bị đoán sai khi có `sectionConfig.icon`/`.color` tùy biến — bảng tĩnh tự chế (`SECTION_DEFAULT_ICON`/`SECTION_COLOR_KEY`) đã phân kỳ với `DEFAULT_SECTIONS`/`DEFAULT_SECTION_COLORS` thật (vd git magenta vs mauve, directory blue vs teal). Sửa: icon tách từ text thật (`splitIconText`), màu qua `sec.color` hoặc `DEFAULT_SECTION_COLORS[id]` thật + bảng dịch `ANSI_TO_CATPPUCCIN` chung.
  - **Medium (đã đầu tư giảm, user chấp nhận phần còn lại)**: test `statusline-integration.test.cjs` "Long model name is truncated" flaky cạnh biên (baseline vốn đã 99/100 cột, pill thêm overhead). Đã giảm padding pill (4→2 ký tự/section). User quyết định (AskUserQuestion): giữ nguyên, chấp nhận rủi ro — kịch bản (tên model 50 ký tự) không xảy ra thực tế.
  - **Medium (đã sửa)**: thiếu test cho `statusline-pill-adapter.cjs` — `tester` subagent viết 41 test mới, tổng suite 175 test (134 cũ + 41 mới).
  - **Low (chưa sửa, không blocking)**: catch-and-swallow không log debug khi module pill global lỗi; require() thất bại không cache. Chấp nhận để lại — cosmetic dev-tooling, không crash, không ảnh hưởng chức năng.
- Tất cả `.claude/*` (trừ `.claude/rules/`) bị gitignore trong repo này — không có gì để `git commit` cho Phase 2-4; thay đổi trong smartbedv3 chỉ tồn tại local, giống bản chất global (`~/.claude/*`) và Windows Terminal.

### Whole-Plan Consistency Sweep
Đã đọc lại `plan.md` + 4 phase file sau vòng implement + code-review + test. Đã sửa quyết định #1 (icon fallback) thành SUPERSEDED khớp với code thật. Không còn chỗ nào nhắc `.ck.json` (root) theo nghĩa sai. Không mâu thuẫn còn lại — 3/4 mục DoD hoàn tất bằng code+test tự động, còn duy nhất bước xem bằng mắt (Windows Terminal, Claude Code session thật) cần user tự làm, đã note rõ trong mọi phase file liên quan.
