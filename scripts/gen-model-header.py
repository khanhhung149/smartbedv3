#!/usr/bin/env python3
"""Nhúng một file .tflite thành mảng C để firmware nạp thẳng từ flash.

    python3 scripts/gen-model-header.py <model.tflite> <ten_bien> <output.h>

Ví dụ:
    python3 scripts/gen-model-header.py \
        firmware/voice-node/models/alexa.tflite kAlexaModel \
        firmware/voice-node/src/model_alexa.h

Vì sao nhúng thành mảng thay vì board_build.embed_files: embed_files đổi CMakeLists ->
CMake reconfigure -> rebuild toàn bộ Arduino framework. Một lần lỡ tay như thế trên /mnt/d
đã ngốn 2,5 giờ. Mảng const nằm ở .rodata, đọc trực tiếp từ flash, không tốn RAM.
"""
import sys
from pathlib import Path

COLS = 16  # 16 byte/dòng cho vừa màn hình và khớp file đã sinh trước đó


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2

    src, ten_bien, dst = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
    data = src.read_bytes()

    # TFLite flatbuffer để magic "TFL3" ở offset 4. Kiểm ở đây để lỗi lộ ra lúc sinh header,
    # chứ không phải lúc GetModel() trả rác trên board rồi ngồi đoán.
    if data[4:8] != b"TFL3":
        print(f"LỖI: {src} không phải flatbuffer TFLite (thiếu magic TFL3)", file=sys.stderr)
        return 1

    dong = [
        "    " + ", ".join(f"0x{b:02x}" for b in data[i : i + COLS]) + ","
        for i in range(0, len(data), COLS)
    ]

    dst.write_text(
        f"// SINH TỰ ĐỘNG từ {src.as_posix()} — ĐỪNG SỬA TAY.\n"
        f"// Sinh lại:  python3 scripts/gen-model-header.py "
        f"{src.as_posix()} {ten_bien} {dst.as_posix()}\n"
        "//\n"
        "// alignas(16): TFLite Micro yêu cầu con trỏ model thẳng hàng, lệch là GetModel()\n"
        "// trả rác — và nó trả rác im lặng, không báo lỗi.\n"
        "#pragma once\n"
        "#include <cstddef>\n"
        "#include <cstdint>\n"
        "\n"
        f"alignas(16) const unsigned char {ten_bien}[] = {{\n"
        + "\n".join(dong)
        + "\n};\n"
        f"const size_t {ten_bien}Len = {len(data)};\n",
        encoding="utf-8",
    )
    print(f"{dst} — {len(data)} byte, biến {ten_bien}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
