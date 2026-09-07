---
phase: 2
title: "Module render pill dùng chung (project + global)"
status: in-progress
priority: P3
dependencies: []
---

# Phase 2: Module render "pill" dùng chung

## Overview
Viết `~/.claude/lib/statusline-pill-theme.cjs` — hàm thuần render 1 dòng statusline dạng "pill" (glyph Nerd Font bo tròn 2 đầu + nền màu block, palette Catppuccin Macchiato), không phụ thuộc `.ck.json`/session-state của bất kỳ project nào, để Phase 3 (smartbedv3) và Phase 4 (global) cùng import.

## Requirements
- Functional: `renderPill(sections, opts)` nhận mảng `{icon, text, colorKey}` → trả về 1 chuỗi ANSI đã format, mỗi section là 1 "viên pill" nối tiếp nhau.
- Non-functional: file độc lập (không `require` gì từ `/mnt/d/smartbedv3/.claude/...`), chạy được bằng `node` trần, tôn trọng `NO_COLOR`/`FORCE_COLOR` giống quy ước đã thấy trong `colors.cjs` của smartbedv3.

## Architecture
- Vị trí: `~/.claude/lib/statusline-pill-theme.cjs` (ngoài mọi git repo — thư mục cấu hình global của user).
- Dùng ANSI truecolor 24-bit (`\x1b[38;2;r;g;bm` foreground, `\x1b[48;2;r;g;bm` background) để lên đúng màu Catppuccin Macchiato — bảng màu named 16-color không đủ độ chính xác cho hiệu ứng pill.
- Glyph bo tròn: dùng cặp Nerd Font Powerline half-circle `` (nắp trái, ` `) và `` (nắp phải, ` `) — 2 ký tự này chỉ hiện đúng khi terminal dùng Nerd Font (đã cài ở Phase 1), nếu không sẽ hiện tofu/box — chấp nhận được vì đây là tính năng phụ thuộc font, không phải bug.
- Palette Catppuccin Macchiato (8 màu accent dùng để phân loại section, map cố định trong module, không cấu hình được — giữ đơn giản theo YAGNI):
  ```js
  const PALETTE = {
    base:   [0x24, 0x27, 0x3A], // nền pill
    text:   [0xCA, 0xD3, 0xF5], // chữ mặc định
    blue:   [0x8A, 0xAD, 0xF4],
    green:  [0xA6, 0xDA, 0x95],
    yellow: [0xEE, 0xD4, 0x9F],
    red:    [0xED, 0x87, 0x96],
    mauve:  [0xC6, 0xA0, 0xF6],
    teal:   [0x8B, 0xD5, 0xCA],
    peach:  [0xF5, 0xA9, 0x7F],
  };
  ```
- Tôn trọng `NO_COLOR` env: nếu set, `renderPill` trả về text thuần (icon + text, không ANSI, không glyph bo tròn — dùng `[` `]` thay thế để vẫn phân tách được section).

## Related Code Files
- Create: `~/.claude/lib/statusline-pill-theme.cjs`

## Implementation Steps
1. Viết `PALETTE` (RGB) + 2 helper `fg(rgb)`/`bg(rgb)` sinh mã ANSI truecolor.
2. Viết `renderPill(sections, opts = {})`:
   - `sections`: `[{icon, text, colorKey}]`.
   - `opts.noColor`: override thủ công (mặc định đọc `process.env.NO_COLOR`).
   - Mỗi section → `<nắp trái bg=colorKey><icon> <text><nắp phải bg=colorKey>` nối cách nhau 1 space. <!-- Updated: Phase 3 code-reviewer finding #3 (width regression), 2026-09-04 --> Đã bỏ 2 khoảng trắng đệm nội bộ quanh `body` (còn `<nắp trái><icon> <text><nắp phải>`, không đệm thêm trước/sau) sau khi phát hiện overhead pill (4 ký tự/section) làm 1 test responsive-wrap trong smartbedv3 flaky ở cạnh biên — giảm còn 2 ký tự/section, đã user chấp nhận phần dư còn lại (xem `phase-03-smartbedv3-statusline-pill.md` Risk Assessment).
3. Viết fallback khi `noColor` true: `[icon text]` nối nhau bằng space, không mã ANSI.
4. Export `{ renderPill, PALETTE }` qua `module.exports`.
5. Test độc lập: `node -e "console.log(require('~/.claude/lib/statusline-pill-theme.cjs').renderPill([{icon:'📁',text:'smartbedv3',colorKey:'blue'}]))"` — xác nhận không throw, output có mã ANSI hợp lệ (dùng `cat -v` hoặc mở trong Windows Terminal đã cài font Phase 1 để xem hình dạng pill thật).

## Success Criteria
- [x] File tồn tại, `node --check` pass (không lỗi cú pháp).
- [x] `renderPill([])` trả về chuỗi rỗng, không throw.
- [x] `NO_COLOR=1 node -e "..."` cho output không chứa `\x1b`.
- [ ] Xem trực tiếp trong Windows Terminal (sau Phase 1) thấy đúng hình pill bo tròn, không phải ký tự lỗi/tofu.

## Risk Assessment
- Risk: nếu Phase 1 chưa xong (chưa có Nerd Font), glyph bo tròn hiện sai (ô vuông/dấu hỏi) — không phải lỗi code, chỉ cần làm Phase 1 trước khi test hình ảnh thật. Có thể code + unit-test logic (Success Criteria 1-3) độc lập với Phase 1.
- Risk: truecolor không hoạt động trên terminal cũ không hỗ trợ 24-bit — Windows Terminal hỗ trợ đầy đủ nên chấp nhận được, không cần fallback 16-color (YAGNI, vì phạm vi chỉ nhắm Windows Terminal).
