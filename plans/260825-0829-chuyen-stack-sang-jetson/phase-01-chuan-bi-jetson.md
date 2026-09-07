---
phase: 1
title: "Chuẩn bị Jetson"
status: completed
priority: P1
dependencies: []
---

# Phase 1: Chuẩn bị Jetson

## Overview
Cài Docker Engine + Compose plugin trên Jetson, chốt IP tĩnh lâu dài để không phải flash lại node lần nữa sau này.

## Requirements
- Functional: `docker compose version` chạy được trên Jetson qua SSH từ laptop.
- Non-functional: không cài NVIDIA Container Toolkit / GPU runtime (không cần cho phạm vi lần này — presence-ac/sleeppad không dùng GPU).

## Architecture
Chạy toàn bộ lệnh qua `ssh mp@192.168.1.125 "..."` từ laptop, không thao tác trực tiếp tại Jetson.

## Related Code Files
- Không chạm code, chỉ setup máy Jetson.

## Implementation Steps
1. SSH vào Jetson, cài Docker theo hướng dẫn chính thức cho Ubuntu/JetPack (`apt-get install docker.io docker-compose-plugin` hoặc script `get.docker.com`).
2. Thêm user `mp` vào group `docker` (tránh phải `sudo` mỗi lệnh compose): `sudo usermod -aG docker mp`, sau đó cần đăng nhập lại SSH session để nhận group mới.
3. Verify: `docker run --rm hello-world` (kiểm tra Docker chạy được), `docker compose version`.
4. Xác định IP Jetson dùng lâu dài: đặt static IP trên Jetson (netplan/nmcli) hoặc DHCP reservation trên router cho MAC của Jetson, cố định về `192.168.1.125` nếu router hỗ trợ — tránh phải đổi lại `MQTT_HOST` sau này khi Jetson đổi IP.

## Success Criteria
- [x] `ssh mp@192.168.1.125 "docker compose version"` chạy không lỗi, không cần sudo — Docker 29.5.2 / Compose v5.1.4 đã có sẵn, chỉ cần thêm group.
- [x] IP Jetson đã cố định qua `nmcli` static (`ipv4.method manual`), `192.168.1.125/24`, không đổi qua reboot.

## Kết quả thực thi (2026-08-25)
- Docker + Compose plugin đã cài sẵn trên Jetson từ trước (không phải cài mới như dự đoán ban đầu).
- User `mp` đã thêm vào group `docker`, verify `docker ps` chạy không cần sudo.
- Lưu ý: Jetson đã có 1 container không liên quan project chạy sẵn (`llm-gw-postgres`, cổng 5432 bind localhost) — không đụng vào, tránh xung đột port khi dựng stack.
- Static IP set qua `nmcli connection modify mp ipv4.method manual ...` — áp dụng ngay, không cần reboot.

## Risk Assessment
- Docker cài qua `apt` trên JetPack có thể là bản cũ — nếu compose plugin thiếu, dùng `docker-compose` standalone (pip/binary) thay thế, miễn tương thích cú pháp `docker-compose.yml` hiện có trong repo.
- Đổi group docker cần logout/login SSH mới có hiệu lực — dễ quên, verify lại bằng lệnh không sudo trước khi qua Phase 2.
