# Development Rules

Use this file when editing code, tests, scripts, or configuration.

## Baseline

- Follow project docs in `docs/` and existing local patterns.
- Prefer YAGNI, KISS, and DRY in that order.
- Implement real behavior. Do not add fake data, mocks, or temporary shortcuts just to satisfy a check.
- Keep changes scoped to the request and the affected contracts.
- Use descriptive kebab-case file names for new files when the repo has no stronger convention.
- Split code only when it reduces real complexity or matches existing module boundaries.

## Quality Gates

- Run the narrowest useful test first, then broaden when shared behavior or public contracts changed.
- Do not hide failing tests, lint, type, build, or syntax errors.
- Preserve public contracts unless the change intentionally updates them and the user accepted that scope.
- Keep commits focused and use conventional commit format without AI references.
- Never commit secrets, dotenv files, tokens, private keys, database credentials, or personal data.

## Tooling

- Use `gh` for GitHub operations when needed.
- Use current docs only when the API/tooling may have changed.
- Use relevant skills by reading their descriptions first, then opening only the needed `SKILL.md`.
- Use `/ck:preview` only when a visual explanation will materially help the user understand the change.

## Cấu hình máy và bí mật đã tồn tại

- Trước khi ghi bất kỳ file cấu hình per-machine nào (`.env`, `.env.dev`, `firmware/**/config.h`, `passwd`), **đọc file đang có trước**. Kể cả khi file bị gitignore và không thấy trong `git status`, nó vẫn có thể chứa giá trị thật đang chạy.
- Không bao giờ tự bịa username/password/token rồi ghi vào config. Lấy từ file thật, từ `*.bak`, hoặc hỏi người dùng. Một mật khẩu bịa sẽ chạy qua build và chỉ lộ ra ở tầng runtime (`disconnected: not authorised`), tốn cả chu kỳ nạp lại firmware.
- Không `cp` đè file cấu hình sang checkout khác khi chưa kiểm tra đích có gì. Kiểm tra đích tồn tại chưa, và nếu có thì so sánh trước.
- Khi hai checkout (worktree và bản chính) cùng có file gitignored, chúng độc lập với nhau. Xác định người dùng thực sự chạy ở đâu trước khi sửa.

## Build sản phẩm từ đúng cây làm việc

- File **untracked** không nằm trong commit. `git checkout <branch> -- <path>` chỉ lấy nội dung đã commit, nên build từ đó sẽ thiếu module chưa commit và tính năng biến mất mà không có lỗi biên dịch.
- Trước khi build artifact để giao (APK, binary), kiểm tra `git status` của cây nguồn: nếu có file untracked hoặc thay đổi chưa commit thuộc phạm vi build, phải build tại chính cây đó.
- Đọc `README.md` của module trước khi truyền tham số build. Ví dụ đã gặp: `API_BASE_URL` của app Flutter bắt buộc kết thúc bằng `/api` và trỏ cổng backend Go, thiếu là 404 dù mọi thứ khác đúng.
- Sau khi copy artifact, đối chiếu kích thước và checksum với bản nguồn. Copy trúng lúc tiến trình build còn đang ghi sẽ ra file cụt mà không báo lỗi.
