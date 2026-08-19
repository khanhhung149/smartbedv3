#!/usr/bin/env python3
"""Client API everai.vn — sinh mẫu TTS tiếng Việt cho tập train wakeword.

    # sinh 1 clip cho mỗi giọng trong danh sách
    python3 scripts/tai-mau-everai.py --text "vừng ơi" --giong vi_female_thuytrang_mb --ra datasets/everai

    # đo tính tất định: gọi cùng tham số 3 lần rồi so hash
    python3 scripts/tai-mau-everai.py --text "vừng ơi" --giong vi_male_lehoang_mb --lap 3 --ra /tmp/tat-dinh

API key đọc theo thứ tự: biến môi trường `EVERAI_API_KEY`, rồi `~/.config/everai/api-key`.
KHÔNG hardcode, KHÔNG commit — plan phase-01 ràng buộc điều này.

Luồng API là BẤT ĐỒNG BỘ, không phải một phát ăn ngay:
    POST /api/v1/tts            -> {"result": {"request_id": ...}}
    GET  /api/v1/tts/{id}       -> lặp cho tới status == "done", lấy `audio_link`
    GET  audio_link             -> tải file

Xin `audio_type=wav`: mẫu dương nén MP3 trong khi mẫu giọng thật là WAV sạch sẽ dạy model phân
biệt ĐỘ NÉN thay vì phân biệt TỪ. Bẫy này ghi ở rủi ro 2 của plan. everai có hỗ trợ wav nên
không phải đánh đổi gì.

⚠️ CHƯA CHẠY ĐƯỢC END-TO-END: tài khoản 09/08 trả `402 — số dư credit trả phí không đủ`.
Gói Free KHÔNG có quyền API. Đường xác thực và đường lỗi đã kiểm; đường thành công thì chưa.
"""
import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API = "https://www.everai.vn/api/v1/tts"
DUONG_KEY = Path.home() / ".config" / "everai" / "api-key"


def doc_key() -> str:
    key = os.environ.get("EVERAI_API_KEY")
    if key:
        return key.strip()
    if DUONG_KEY.is_file():
        return DUONG_KEY.read_text(encoding="utf-8").strip()
    print(
        f"LỖI: không có API key. Đặt EVERAI_API_KEY hoặc ghi vào {DUONG_KEY} (chmod 600).",
        file=sys.stderr,
    )
    sys.exit(2)


def _goi(url: str, key: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST" if body else "GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        # Lỗi nghiệp vụ của everai nằm trong THÂN response, không chỉ ở mã HTTP. In cả hai.
        return json.loads(e.read() or b"{}") | {"_http": e.code}


def sinh_mot_clip(key: str, text: str, giong: str, **tuy_chon) -> dict:
    body = {"input_text": text, "voice_code": giong, "audio_type": "wav", **tuy_chon}
    r = _goi(API, key, body)
    if r.get("status") != 1:
        return {"loi": r.get("error_message") or r, "ma_loi": r.get("error_code") or r.get("_http")}
    return {"request_id": r["result"]["request_id"], "characters": r["result"].get("characters")}


def cho_xong(key: str, request_id: str, so_lan=40, nghi=3.0) -> dict:
    """Lặp cho tới khi render xong. everai không hứa thời gian nên phải lặp, không ngủ cứng."""
    for _ in range(so_lan):
        r = _goi(f"{API}/{request_id}", key)
        if r.get("status") != 1:
            return {"loi": r.get("error_message") or r}
        kq = r["result"]
        if str(kq.get("status", "")).lower() == "done":
            return {"audio_link": kq.get("audio_link"), "meta": kq}
        time.sleep(nghi)
    return {"loi": f"quá {so_lan} lần lặp mà chưa done"}


def tai_ve(url: str, dich: Path) -> str:
    with urllib.request.urlopen(url, timeout=120) as r:
        data = r.read()
    dich.write_bytes(data)
    return hashlib.sha256(data).hexdigest()[:16]


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--text", default="vừng ơi", help="văn bản cần đọc")
    ap.add_argument("--giong", action="append", required=True, help="voice_code, lặp cờ để thêm giọng")
    ap.add_argument("--ra", type=Path, required=True, help="thư mục ghi WAV")
    ap.add_argument("--lap", type=int, default=1, help="gọi lại N lần cùng tham số — để đo tính tất định")
    ap.add_argument("--speed", type=float, help="speed_rate 0.5-2.0")
    ap.add_argument("--model-id", help="everai-v1.6 (mặc định) | v1.5 | v1.5-turbo | v1")
    args = ap.parse_args()

    key = doc_key()
    args.ra.mkdir(parents=True, exist_ok=True)
    tuy_chon = {}
    if args.speed:
        tuy_chon["speed_rate"] = args.speed
    if args.model_id:
        tuy_chon["model_id"] = args.model_id

    hashes: dict[str, list[str]] = {}
    tong_ky_tu = 0
    for giong in args.giong:
        for lan in range(args.lap):
            r = sinh_mot_clip(key, args.text, giong, **tuy_chon)
            if "loi" in r:
                print(f"❌ {giong} — {r.get('ma_loi')} {r['loi']}", file=sys.stderr)
                continue
            tong_ky_tu += r.get("characters") or 0
            kq = cho_xong(key, r["request_id"])
            if "loi" in kq:
                print(f"❌ {giong} — {kq['loi']}", file=sys.stderr)
                continue
            ten = f"{giong}-{lan:02d}.wav"
            h = tai_ve(kq["audio_link"], args.ra / ten)
            hashes.setdefault(giong, []).append(h)
            print(f"✅ {ten}  sha256[:16]={h}")

    # Tất định hay không quyết định TRẦN clip phân biệt — không suy luận, so hash.
    if args.lap > 1:
        print("\n=== TÍNH TẤT ĐỊNH ===")
        for giong, hs in hashes.items():
            print(f"  {giong}: {len(set(hs))} hash khác nhau / {len(hs)} lần gọi"
                  f" ⇒ {'TẤT ĐỊNH — số request KHÔNG bằng số clip phân biệt' if len(set(hs)) == 1 else 'có ngẫu nhiên'}")

    print(f"\nTổng ký tự đã tính phí: {tong_ky_tu}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
