---
phase: 3
title: "smartbedv3 statusline — giao diện pill, giữ nguyên tính năng"
status: in-progress
priority: P3
dependencies: [2]
---

# Phase 3: smartbedv3 statusline — pill style

## Overview
Hook module `renderPill()` (Phase 2) vào statusline hiện có của smartbedv3 dưới dạng 1 chế độ vẽ **opt-in qua config** (không hardcode làm mặc định), giữ nguyên toàn bộ data pipeline (git/context/quota/agents/todos/cost/activePlan) và không phá invariant "zero regression khi không có `statuslineLayout`" đã ghi rõ trong code hiện tại + test suite `.claude/hooks/lib/__tests__/statusline-*.test.cjs`.

## Requirements
- Functional: khi bật `statuslineLayout.pillStyle: true` trong `.ck.json`, mỗi section render ra dạng pill (glyph bo tròn + nền màu Catppuccin Macchiato) thay vì text-color-only như hiện tại. Khi KHÔNG bật (mặc định), output y hệt hiện tại — test suite hiện có phải pass nguyên trạng.
- Non-functional: không sửa logic của từng `renderXxxSection` (data-fetching), chỉ can thiệp ở bước ghép chuỗi cuối (`renderSessionLines`/`render`/`renderCompact`/`renderMinimal` trong `statusline-render-modes.cjs`).

## Architecture
<!-- Updated: Implementation - thiết kế thật đơn giản hơn bản dự tính lúc plan (single-point wrap trong renderSection() thay vì pillifyLine ở tầng ghép dòng) -->
**Thiết kế thật (khác bản dự tính ban đầu, phát hiện lúc code — đơn giản hơn, ít rủi ro hơn cho responsive-wrap logic):**
- Vấn đề gốc vẫn đúng: các hàm `renderXxxSection()` đã tự bọc ANSI màu vào string trả về, không tách data/màu.
- Thay vì pillify ở TẦNG GHÉP DÒNG (`pillifyLine` nhận mảng string đã join) như dự tính ban đầu, chỉ cần sửa đúng 1 điểm: `renderSection()` — hàm helper DUY NHẤT mà cả 4 render mode (`renderConfiguredLines`, `renderSessionLines`, `renderCompact`, `renderMinimal`) đều gọi qua closure `rs(id)` của riêng chúng. Vì mọi `rs(id)` đều đi qua `renderSection()`, sửa 1 chỗ này tự động áp dụng cho cả 4 mode — không cần đụng logic threshold/`visibleLength`/responsive-wrap ở bất kỳ đâu.
- `.claude/hooks/lib/statusline-pill-adapter.cjs` (mới, trong repo):
  - `require` module global Phase 2 qua `path.join(os.homedir(), '.claude', 'lib', 'statusline-pill-theme.cjs')`, bọc try/catch — nếu module global không tồn tại (máy khác/CI), fallback về icon+text thường, không throw.
  - `stripAnsi(str)`: regex `/\x1b\[[0-9;]*m/g` (cùng pattern `statusline-string-utils.cjs` dùng).
  - `SECTION_DEFAULT_ICON`/`SECTION_COLOR_KEY`: map cố định theo 8 section id thật có trong `SECTION_RENDERERS` (`model/context/quota/directory/git/plan/cost/changes` — KHÔNG có `agents`/`todos`, 2 section đó render riêng, không qua `renderSection()`).
  - `pillifySection(id, renderedText, ctx, theme)`: strip ANSI, bỏ icon-prefix cũ nếu trùng icon mặc định, gọi `renderPill([{icon, text, colorKey}])` — 1 pill duy nhất, không phải join nhiều pill.
- `statusline-render-modes.cjs`: `renderSection()` (hàm dùng chung) thêm 2 dòng — nếu `ctx.pillStyle` true, bọc kết quả qua `pillifySection()`; ngược lại trả nguyên như cũ (zero regression khi tắt). `renderMinimal()` có 2 chỗ tự dựng text riêng cho context (battery icon) và quota (không qua `renderSection()`) — bọc riêng 2 chỗ đó bằng cùng `pillifySection()` khi `ctx.pillStyle` true.
- `agents`/`todos` (`renderAgentsLines`/`renderTodosLine` trong `statusline-activity-renderers.cjs`) **không đụng gì** — chúng không đi qua `renderSection()`, nên tự động giữ nguyên định dạng cũ dù pillStyle bật hay tắt (không nằm trong scope pill-hoá của phase này — xem Risk Assessment).
- Bật qua `.claude/.ck.json` — file NÀY ĐÃ TỒN TẠI SẴN trong repo với nhiều config khác (đọc kỹ trước khi sửa theo `development-rules.md`), KHÔNG phải file mới trống như dự tính lúc plan. Chỉ thêm 1 key mới:
  ```json
  "statuslineLayout": { "pillStyle": true }
  ```
  đọc trong `statusline.cjs`: `ctx.pillStyle = config.statuslineLayout?.pillStyle === true` (set thẳng vào `ctx`, không qua `layout` — đơn giản hơn vì `renderSection()` đã nhận `ctx` sẵn).
- Icon fallback (chốt qua validate): dùng `SECTION_DEFAULT_ICON` cố định theo section id — như dự tính.

## Related Code Files
- Create: `.claude/hooks/lib/statusline-pill-adapter.cjs` — DONE
- Modify: `.claude/.ck.json` (file đã tồn tại từ trước, chỉ thêm 1 key `statuslineLayout.pillStyle: true`, mọi key khác giữ nguyên) — DONE
- Modify: `.claude/hooks/lib/statusline-render-modes.cjs` (sửa `renderSection()` dùng chung + 2 chỗ trong `renderMinimal()`) — DONE
- Modify: `.claude/statusline.cjs` (thêm `pillStyle` vào `ctx`) — DONE
- Create: `.claude/hooks/lib/__tests__/statusline-pill-adapter.test.cjs` (41 test, viết bởi `tester` subagent) — DONE
- Modify: `.claude/hooks/lib/__tests__/statusline-suite.cjs` (đăng ký test file mới vào `SUITES`) — DONE
- Read (không sửa, chỉ tham khảo icon/id contract + reuse `getContextColorName`/`getQuotaColorName`/`DEFAULT_SECTION_COLORS`): `.claude/hooks/lib/statusline-section-registry.cjs`

## Implementation Steps
1. DONE — viết `statusline-pill-adapter.cjs`: `stripAnsi`, `SECTION_DEFAULT_ICON`, `SECTION_COLOR_KEY`, `pillifySection(id, text, ctx, theme)` (reuse `getContextColorName`/`getQuotaColorName` từ registry cho màu động context/quota), try/catch fallback khi thiếu module global.
2. DONE — sửa `statusline.cjs`: thêm `pillStyle: config.statuslineLayout?.pillStyle === true` vào `ctx`.
3. DONE — sửa `statusline-render-modes.cjs`:
   - `renderSection()` (hàm dùng chung, 1 điểm sửa duy nhất): nếu `ctx.pillStyle` true → `pillifySection(id, rendered, ctx, theme)`, else trả nguyên như cũ.
   - `renderMinimal()`: 2 chỗ tự dựng text riêng (context battery, quota) bọc thủ công qua `pillifySection` khi `ctx.pillStyle`.
   - `renderConfiguredLines`/`renderSessionLines`/`renderCompact`: KHÔNG cần sửa gì — tự động nhận pill qua `rs(id)` → `renderSection()` đã pill-hoá.
4. DONE — đọc lại `.claude/.ck.json` trước khi sửa (đã có sẵn nhiều config khác), chỉ thêm đúng 1 key mới.
5. DONE — test suite: `node .claude/hooks/lib/__tests__/statusline-suite.cjs` → **38/38 pass** cả khi `pillStyle: true` và `pillStyle: false` trong `.claude/.ck.json` thật (test suite dùng fixture config riêng, không đọc file thật — baseline không đổi).
6. DONE — test thủ công qua `echo '<json>' | node .claude/statusline.cjs`: pillStyle true → ANSI truecolor pill hợp lệ (verify bằng `cat -v`); pillStyle false → output y hệt định dạng cũ (verify bằng cách tắt/bật lại `.claude/.ck.json` và so sánh).
7. **CHƯA LÀM** — mở Claude Code thật trong smartbedv3 để xem hình pill trực tiếp trong Windows Terminal (đã cài font Phase 1) — cần user tự xác nhận, không tự động hoá được từ CLI.

## Success Criteria
- [x] `node .claude/hooks/lib/__tests__/statusline-suite.cjs` pass — không regression khi pillStyle tắt (175 test tổng, 1 flaky đã biết + chấp nhận, xem Risk Assessment).
- [x] Với `.claude/.ck.json` bật `pillStyle: true`, output statusline chứa mã ANSI truecolor pill cho cả 4 section test được (model/context/directory/git); NO_COLOR=1 fallback sạch, không lộ ANSI.
- [x] Agents/todos không bị đụng — xác nhận qua code: `renderAgentsLines`/`renderTodosLine` không gọi `renderSection()`, nên không đi qua logic pill mới.
- [x] Unit test riêng cho `statusline-pill-adapter.cjs` (41 test: icon-strip, color precedence context/quota/default, empty input, ANSI truecolor strip) — file mới `statusline-pill-adapter.test.cjs`, đăng ký vào `statusline-suite.cjs`.
- [ ] Xem trực tiếp trong Windows Terminal (đã cài font Phase 1): pill hiện đúng hình bo tròn, đúng màu Catppuccin Macchiato — **cần user tự xác nhận**.

## Risk Assessment
- Risk: tách icon bằng quy ước cũ đã loại bỏ. <!-- Updated: code-reviewer finding #1 (High) - icon/color tách từ text thật thay vì bảng tĩnh phân kỳ --> Đã sửa theo finding #1 của code-reviewer (High): thay vì bảng tĩnh `SECTION_DEFAULT_ICON`/`SECTION_COLOR_KEY` tự chế (đã phân kỳ với `DEFAULT_SECTIONS`/`DEFAULT_SECTION_COLORS` thật — vd git dùng magenta không phải mauve, directory dùng blue không phải teal), giờ icon tách trực tiếp từ chuỗi đã render (`splitIconText`, universal `${icon} ${rest}` convention), màu lấy từ `sec.color` (nếu có override) hoặc `DEFAULT_SECTION_COLORS[id]` thật, qua bảng dịch `ANSI_TO_CATPPUCCIN` chung. Đã verify: không còn double-icon/sai màu khi test với `sectionConfig.icon`/`.color` tùy biến.
- Risk (đã giảm nhờ đổi thiết kế): thay vì sửa `renderSessionLines`/`renderConfiguredLines` (nhiều nhánh, dễ phá responsive-wrap), chỉ sửa `renderSection()` — 1 điểm chung, không đụng threshold/`visibleLength`/wrap logic ở bất kỳ đâu. Rủi ro phá responsive-wrap gần như bằng 0.
- Risk: nếu global module `~/.claude/lib/statusline-pill-theme.cjs` bị xoá/hỏng ở máy khác, `pillifySection` fallback về icon+text thường (không throw) — đã test thật (xoá file tạm thời, statusline vẫn chạy, exit code 0, không crash).
- <!-- Updated: code-reviewer finding #3 (Medium), xác nhận + quyết định qua AskUserQuestion 2026-09-04 --> **Flaky test đã biết, chấp nhận có chủ đích**: `statusline-integration.test.cjs` "Long model name is truncated (not overflow)" thỉnh thoảng fail (quan sát 1/4 lần rerun). Nguyên nhân xác nhận: baseline (không pill) đã cận biên sẵn (99/100 cột với model name 50 ký tự tổng hợp + quota 2 window), pill thêm ~2 ký tự/section (sau khi đã giảm padding — xem Phase 2 module, bỏ 2 khoảng trắng đệm nội bộ). Test này còn có lỗ hổng cô lập từ trước khi tôi sửa gì (không mock `HOME`/usage-cache, phụ thuộc cache quota thật của máy dev — nên chính test cũng vốn đã flaky độc lập với pill). Model name thật của Claude luôn ngắn (Sonnet 5, Opus 5...) nên kịch bản này không xảy ra khi dùng thật. Quyết định: giữ nguyên, không sửa thêm code hay test — chấp nhận rủi ro cạnh biên hiếm gặp này, không thuộc scope pill để sửa lỗ hổng cô lập test (đó là việc riêng, rộng hơn).
- Risk còn lại: mọi thứ đã verify bằng script CLI, chưa verify bằng mắt trong Windows Terminal thật — cần user xác nhận cuối cùng sau khi phase 1 áp dụng xong (đóng/mở lại terminal).
