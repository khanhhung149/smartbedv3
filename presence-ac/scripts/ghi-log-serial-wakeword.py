#!/usr/bin/env python3
"""Ghi log serial voice-node ra file + tự đếm TRIGGER/score, dùng cho bài đo true-positive/
false-trigger ở phase-04 (plans/260810-0843-voice-node-wakeword-gate/).

Lý do không dùng `pio device monitor` thẳng: `miniterm` gọi termios.tcgetattr() ngay cả khi
không có TTY thật (chạy nền/background), lỗi "Inappropriate ioctl for device". Script này đọc
thẳng qua pyserial, không cần TTY.

Trước khi chạy (WSL2 + board cắm qua USB Windows):
    powershell.exe -Command "usbipd list"                       # tìm busid của CH340
    powershell.exe -Command "usbipd bind --busid <busid>"        # 1 lần/board mới, cần admin
    powershell.exe -Command "usbipd attach --wsl --busid <busid>"  # mỗi lần cắm lại

Dùng:
    # ghi 5 phút, tự in tổng kết TRIGGER/score cuối cùng
    python3 scripts/ghi-log-serial-wakeword.py /dev/ttyUSB0 300 tp-test.log

    # đổi baud nếu khác 115200 (xem monitor_speed trong platformio.ini)
    python3 scripts/ghi-log-serial-wakeword.py /dev/ttyUSB0 300 tp-test.log --baud 115200

Bài đo true-positive (phase-04 step 2) cần ĐẾM CHÍNH XÁC số lần nói "Vừng ơi" — hô to số thứ tự
("một, Vừng ơi" / "hai, Vừng ơi"...) trước mỗi lần để đối chiếu bằng tai lúc nghe lại nếu cần,
rồi tự ghi tổng số lần đã nói ra ngoài (script không đếm được giọng nói, chỉ đếm log board).
"""
import argparse
import re
import sys
import time

import serial


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("port", help="vd /dev/ttyUSB0")
    parser.add_argument("duration", type=float, help="giây")
    parser.add_argument("outfile", help="file log output")
    parser.add_argument("--baud", type=int, default=115200)
    args = parser.parse_args()

    ser = serial.Serial(args.port, args.baud, timeout=1)
    start = time.time()
    print(f"Đang ghi {args.duration:.0f}s vào {args.outfile}...", file=sys.stderr)
    with open(args.outfile, "ab", buffering=0) as f:
        while time.time() - start < args.duration:
            line = ser.readline()
            if line:
                f.write(line)
    ser.close()

    with open(args.outfile, "rb") as f:
        text = f.read().decode("utf-8", errors="replace")

    scores = [float(m) for m in re.findall(r"\[wakeword\] score=([\d.]+)", text)]
    triggers = re.findall(r"\[wakeword\] TRIGGER score=([\d.]+)", text)

    print(f"\n--- Tổng kết {args.outfile} ---")
    print(f"Dòng [wakeword] score=: {len(scores)}")
    if scores:
        print(f"Score cao nhất: {max(scores):.3f} | Số score > 0.5: {sum(1 for s in scores if s > 0.5)}")
    print(f"TRIGGER: {len(triggers)} — {triggers}")


if __name__ == "__main__":
    main()
