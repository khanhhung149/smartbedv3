---
phase: 1
title: "Windows Terminal — font MesloLGS NF + Catppuccin Macchiato + acrylic"
status: completed
priority: P3
dependencies: []
---

# Phase 1: Windows Terminal — font + colorScheme + transparency

## Overview
Cài MesloLGS NF trên Windows, set làm font cho profile WSL "Ubuntu-Recovered", thêm colorScheme "Catppuccin Macchiato" và bật acrylic/opacity cho đúng profile đó — không đụng profile khác.

## Requirements
- Functional: profile Ubuntu-Recovered hiển thị đúng font MesloLGS NF, màu Catppuccin Macchiato, nền hơi trong suốt (acrylic).
- Non-functional: không phá vỡ profile PowerShell/CMD/Azure Cloud Shell/Dev Command Prompt/2 profile "Ubuntu" khác — chỉ sửa đúng 1 profile theo guid.

## Architecture
File đích: `/mnt/c/Users/HP/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json` (ngoài repo git, sửa qua đường dẫn `/mnt/c/...` từ WSL).

Cấu trúc hiện tại (đã scout 2026-09-04):
- `defaultProfile`: `{d631440c-124e-5f2f-a177-265d1e3bdb2b}` = profile tên "Ubuntu-Recovered".
- `profiles.defaults`: `{"colorScheme": "One Half Dark", "font": {"face": "CaskaydiaCove Nerd Font"}}` — đây là default áp cho MỌI profile không override riêng.
- `schemes[]`: rỗng.

Vì `profiles.defaults` áp cho mọi profile, KHÔNG được sửa `profiles.defaults` (sẽ đổi cả PowerShell/CMD/... trái với "Ngoài phạm vi" trong plan.md). Phải override riêng trong entry của guid `{d631440c-124e-5f2f-a177-265d1e3bdb2b}` trong `profiles.list[]`.

## Related Code Files
- Modify (ngoài repo): `/mnt/c/Users/HP/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json`
  - Thêm entry vào `schemes[]`:
    ```json
    {
      "name": "Catppuccin Macchiato",
      "background": "#24273A",
      "foreground": "#CAD3F5",
      "cursorColor": "#F4DBD6",
      "selectionBackground": "#5B6078",
      "black": "#494D64",
      "red": "#ED8796",
      "green": "#A6DA95",
      "yellow": "#EED49F",
      "blue": "#8AADF4",
      "purple": "#F5BDE6",
      "cyan": "#8BD5CA",
      "white": "#B8C0E0",
      "brightBlack": "#5B6078",
      "brightRed": "#ED8796",
      "brightGreen": "#A6DA95",
      "brightYellow": "#EED49F",
      "brightBlue": "#8AADF4",
      "brightPurple": "#F5BDE6",
      "brightCyan": "#8BD5CA",
      "brightWhite": "#A5ADCB"
    }
    ```
  - Trong `profiles.list[]`, tìm entry `guid == "{d631440c-124e-5f2f-a177-265d1e3bdb2b}"`, thêm/sửa các field:
    ```json
    "font": { "face": "MesloLGS NF" },
    "colorScheme": "Catppuccin Macchiato",
    "opacity": 82,
    "useAcrylic": true
    ```
    <!-- Updated: Implementation - family name thật là "MesloLGS NF", tên "MesloLGS Nerd Font" ở brainstorm chỉ là ước tính, không đúng thực tế -->
    Font-family name đúng là **"MesloLGS NF"** — xác nhận lúc implement qua `font.md` chính thức của `romkatv/powerlevel10k` (brainstorm ước tính sai tên).

## Implementation Steps
1. ~~Đọc lại file settings.json ngay trước khi sửa~~ — DONE (đọc lại, không đổi gì so với lúc brainstorm).
2. <!-- Updated: Implementation - nguồn font đổi từ ryanoasis/nerd-fonts sang powerlevel10k-media --> **Đổi nguồn so với dự tính ban đầu**: `ryanoasis/nerd-fonts` (Meslo.zip) đóng gói font family name khác, không khớp đúng chuỗi "MesloLGS NF" mà mọi hướng dẫn Mac/iTerm2/Powerlevel10k dùng. Nguồn đúng, xác nhận qua `font.md` chính thức của `romkatv/powerlevel10k`: 4 file ttf tại repo `romkatv/powerlevel10k-media`. Đã ghim commit SHA `145eb9fbc2f42ee408dacd9b22d8e6e0e553f83d` (thay vì `master`, đúng quyết định "ghim version cụ thể" ở validate) — DONE, tải qua `curl` (WSL có mạng trực tiếp, không cần PowerShell cho bước tải), 4 file ~2.5-2.6MB mỗi file, đúng kích thước hợp lý.
3. DONE — cài 4 file vào `%LOCALAPPDATA%\Microsoft\Windows\Fonts` + đăng ký registry `HKCU:\...\CurrentVersion\Fonts` qua PowerShell (copy qua thư mục tạm `/mnt/c/Users/HP/AppData/Local/Temp/meslo-nf-install`, dọn sau khi cài).
4. DONE — verify registry: cả 4 entry "MesloLGS NF Regular/Bold/Italic/Bold Italic (TrueType)" xuất hiện, trỏ đúng đường dẫn file đã copy.
5. DONE — sửa `settings.json`: thêm scheme "Catppuccin Macchiato", thêm 4 field vào đúng entry guid Ubuntu-Recovered (`font.face: "MesloLGS NF"`).
6. DONE — diff bằng Python so `.bak` vs bản mới: `defaultProfile` không đổi, `profiles.defaults` không đổi, chỉ đúng 1 profile (Ubuntu-Recovered) đổi (+4 field), `schemes[]` từ rỗng → 1 entry.
7. Chờ user tự đóng/mở lại Windows Terminal để áp dụng (Windows Terminal không tự hot-reload font mới cài vào registry ngay lập tức trong mọi trường hợp).

## Success Criteria
- [x] File `.bak` được tạo trước khi ghi đè (`settings.json.bak` cùng thư mục).
- [x] `schemes[]` có đúng 1 entry tên "Catppuccin Macchiato" với các hex màu ở trên.
- [x] Entry guid `{d631440c-124e-5f2f-a177-265d1e3bdb2b}` trong `profiles.list[]` có đủ 4 field: `font.face: "MesloLGS NF"`, colorScheme, opacity, useAcrylic.
- [x] Không field nào khác trong file bị đổi so với bản `.bak` (diff Python xác nhận sạch).
- [x] Font "MesloLGS NF" (4 style) xuất hiện trong registry fonts sau khi cài.

## Risk Assessment
- Risk: `profiles.defaults` bị sửa nhầm thay vì entry riêng — sẽ đổi luôn PowerShell/CMD, vi phạm scope. Mitigation: luôn sửa qua `profiles.list[]` theo guid cụ thể, không đụng `profiles.defaults`.
- Risk: PowerShell tải font từ GitHub có thể bị chặn bởi proxy/firewall công ty — nếu `Invoke-WebRequest` fail, fallback: báo lỗi rõ ràng cho người dùng, không giả vờ thành công.
- Risk: ghi JSON bằng Python có thể đổi thứ tự key/format khác bản gốc Windows Terminal tự sinh (không gây lỗi nhưng khó diff bằng mắt) — chấp nhận được vì Windows Terminal parse JSON, không quan tâm thứ tự key.
