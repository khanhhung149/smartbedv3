#!/usr/bin/env python3
"""Chấm điểm model snore trên file WAV, chạy trên PC thay vì board.

Vì sao cần: muốn đặt lại ngưỡng phát hiện ngáy thì phải biết model chấm bao nhiêu điểm cho từng
loại tín hiệu. Đo trên board thì mỗi lần thử phải nạp lại firmware (~7 phút) và chỉ đọc được log
trôi qua, không đối chiếu được nhiều mẫu. Script này chạy đúng model đó trên WAV đã thu, in score
theo từng cửa sổ 1 giây.

Điều kiện tiên quyết — frontend PHẢI khớp firmware (src/snore_features.cpp). Lệch bất kỳ tham số
nào thì model vẫn chạy không lỗi và vẫn trả score đẹp trong [0,1], nhưng con số vô nghĩa. Vì vậy
có chế độ --tu-kiem: chạy trên mẫu board đã đo và so khoảng score với thực tế board báo.

Chạy trong Docker (không cài TensorFlow vào host):

    docker run --rm \\
      -v /mnt/d/esp32-presence-ac:/repo \\
      -v /mnt/d/snore-dataset:/data \\
      tensorflow/tensorflow:latest \\
      python /repo/scripts/cham-diem-snore-offline.py /data/quiet
"""

import argparse
import json
import statistics
import sys
import wave
from pathlib import Path

import numpy as np
import tensorflow as tf
from tensorflow.lite.experimental.microfrontend.python.ops import audio_microfrontend_op

sys.path.insert(0, str(Path(__file__).parent))
from snore_nhip import phan_tich_nhip  # noqa: E402

# Tham số frontend lấy TRỰC TIẾP từ SnoreFeatures::begin() (firmware/voice-node/src/snore_features.cpp).
# Model được train trên đúng bộ này; lệch một field là lệch phân bố đặc trưng so với lúc train.
FRONTEND = dict(
    sample_rate=16000,
    window_size=32,       # ms
    window_step=16,       # ms
    num_channels=30,
    lower_band_limit=40.0,
    upper_band_limit=6000.0,
    smoothing_bits=10,
    even_smoothing=0.025,
    odd_smoothing=0.06,
    min_signal_remaining=0.05,
    enable_pcan=True,
    pcan_strength=0.95,
    pcan_offset=80.0,
    gain_bits=21,
    enable_log=True,
    scale_shift=6,
)

SLICE_COUNT = 61      # input model [1, 61*30] — 61 slice = đúng 1 giây @16kHz, model KHÔNG streaming
NUM_CHANNELS = 30

# Mỗi slice ứng với window_step của frontend. Cần con số này để đổi bước trượt (tính bằng slice)
# sang giây khi chấm nhịp — thuật toán nhịp làm việc theo thời gian thật, không theo chỉ số mẫu.
GIAY_MOI_SLICE = FRONTEND["window_step"] / 1000.0

# Bước trượt khi chấm nhịp: 15 slice = 0,24s (~4,2Hz). KHÔNG dùng mặc định 61 slice (1Hz) được —
# chu kỳ ngáy ngắn nhất là 2s, lấy mẫu 1Hz nằm sát giới hạn Nyquist nên đo nhịp không tin được.
HOP_NHIP_SLICE = 15

# Ngưỡng đối chiếu khi thống kê. 0,5 là mức firmware coi là "tự tin"; 0,2/0,3 để thấy phân bố đuôi.
NGUONG_THONG_KE = (0.2, 0.3, 0.5)

# Khoảng score board thật đã báo khi chạy trong phòng (đo 2026-08-14): "score 0,05-0,29, 5 lần vượt
# 0,5". Hai vế đó nói rõ 0,05-0,29 là khoảng ĐIỂN HÌNH chứ không phải min/max tuyệt đối — board vẫn
# có cửa sổ vượt 0,5. Nên tự kiểm so MEDIAN vào khoảng này, đồng thời đòi có một ít cửa sổ vượt 0,5;
# so min/max sẽ luôn FAIL dù frontend đúng.
BOARD_SCORE_MIN, BOARD_SCORE_MAX = 0.05, 0.29
TU_KIEM_DUNG_SAI = 0.05


def doc_wav(path):
    """Đọc WAV mono 16-bit 16kHz thành mảng int16. Từ chối thẳng định dạng khác thay vì tự chuyển
    đổi — mẫu thu từ voice-node luôn đúng định dạng này, file lệch nghĩa là nhầm nguồn dữ liệu."""
    with wave.open(str(path)) as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2 or w.getframerate() != 16000:
            raise ValueError(
                f"{path.name}: cần mono/16-bit/16kHz, gặp {w.getnchannels()}ch/"
                f"{w.getsampwidth() * 8}bit/{w.getframerate()}Hz"
            )
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)


def trich_dac_trung(pcm):
    """PCM16 -> đặc trưng uint8 [n_slice, 30] đã rescale đúng như firmware.

    Chạy frontend trên TOÀN BỘ file một lần chứ không cắt từng giây rồi chạy riêng: noise reduction
    và PCAN của frontend có trạng thái chạy dọc theo tín hiệu, và firmware cũng không reset state
    giữa các lần pushSamples(). Cắt nhỏ rồi chạy riêng sẽ cho trạng thái khác board.
    """
    raw = audio_microfrontend_op.audio_microfrontend(
        tf.convert_to_tensor(pcm, dtype=tf.int16), out_type=tf.uint16, **FRONTEND
    ).numpy()

    # Quy đổi ĐÚNG như SnoreFeatures::pushSamples(): raw*128/335, clamp 0..255. Model được train
    # trên đặc trưng đã qua bước rescale thủ công này (input_data.py repo gốc), bỏ nó thì input
    # lệch hẳn phân bố lúc train.
    return np.clip(raw.astype(np.int32) * 128 // 335, 0, 255).astype(np.uint8)


class ModelSnore:
    """Bọc tflite Interpreter, ghi/đọc tensor đúng cách firmware làm (src/snore_model.cpp)."""

    def __init__(self, model_path):
        self.interp = tf.lite.Interpreter(model_path=str(model_path))
        self.interp.allocate_tensors()
        self.inp = self.interp.get_input_details()[0]
        self.out = self.interp.get_output_details()[0]

        can_elems = SLICE_COUNT * NUM_CHANNELS
        if self.inp["dtype"] != np.uint8 or int(np.prod(self.inp["shape"])) != can_elems:
            raise ValueError(
                f"input model là {self.inp['dtype']}/{self.inp['shape']}, "
                f"cần uint8/{can_elems} phần tử — model không khớp firmware"
            )
        if self.out["dtype"] != np.uint8:
            raise ValueError(f"output model là {self.out['dtype']}, cần uint8")

        # Output dùng affine-quantize thật đọc từ tensor, không giả định cứng raw/255.
        self.scale, self.zero_point = self.out["quantization"]

    def cham_diem(self, dac_trung_1s):
        """Trả điểm lớp 'snoring' (index 0) trong [0,1] cho đúng 61 slice."""
        # Ghi THẲNG uint8 — input tensor model này không mang ý nghĩa affine-quantize chuẩn TFLite,
        # nó là đặc trưng thô đã rescale sẵn.
        self.interp.set_tensor(self.inp["index"], dac_trung_1s.reshape(self.inp["shape"]))
        self.interp.invoke()
        raw = int(self.interp.get_tensor(self.out["index"]).flatten()[0])
        return (raw - self.zero_point) * self.scale


def cham_diem_file(model, path, hop):
    """Trả (danh sách score theo cửa sổ, cảnh báo phân bố đặc trưng)."""
    dac_trung = trich_dac_trung(doc_wav(path))

    # Cảnh báo sai rescale: đặc trưng dồn hết về 0 hoặc 255 nghĩa là bước quy đổi lệch, score sau đó
    # vô nghĩa dù model vẫn chạy.
    ti_le_bien = float(np.mean((dac_trung == 0) | (dac_trung == 255)))
    canh_bao = ti_le_bien > 0.9

    scores = []
    for start in range(0, len(dac_trung) - SLICE_COUNT + 1, hop):
        scores.append(model.cham_diem(dac_trung[start:start + SLICE_COUNT]))
    return scores, canh_bao, ti_le_bien


def thong_ke(scores):
    if not scores:
        return {}
    s = sorted(scores)
    pct = lambda p: s[min(len(s) - 1, int(len(s) * p))]
    return {
        "n": len(s),
        "min": round(s[0], 4),
        "median": round(statistics.median(s), 4),
        "p95": round(pct(0.95), 4),
        "p99": round(pct(0.99), 4),
        "max": round(s[-1], 4),
        **{f"vuot_{ng}": sum(1 for x in s if x > ng) for ng in NGUONG_THONG_KE},
    }


def liet_ke_wav(muc_tieu):
    p = Path(muc_tieu)
    if p.is_dir():
        return sorted(p.glob("*.wav"))
    if p.is_file():
        return [p]
    raise FileNotFoundError(muc_tieu)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("muc_tieu", nargs="+", help="file WAV hoặc thư mục chứa WAV")
    ap.add_argument("--model", default="/repo/firmware/voice-node/models/snore.tflite")
    ap.add_argument("--hop", type=int, default=None,
                    help=f"bước trượt tính theo slice (mặc định {SLICE_COUNT} = 1s, không chồng lấn; "
                         f"với --nhip thì mặc định {HOP_NHIP_SLICE})")
    ap.add_argument("--json", action="store_true", help="in JSON thay vì bảng")
    ap.add_argument("--nhip", action="store_true",
                    help=f"chấm NHỊP thay vì thống kê ngưỡng: tự đặt --hop={HOP_NHIP_SLICE} "
                         "(~4,2Hz) rồi tìm đợt lặp đều theo chu kỳ thở (xem scripts/snore_nhip.py)")
    ap.add_argument("--tu-kiem", action="store_true",
                    help="kiểm tra frontend có khớp firmware không, bằng cách so khoảng score với "
                         f"mức board thật đã báo ({BOARD_SCORE_MIN}-{BOARD_SCORE_MAX})")
    args = ap.parse_args()

    hop = args.hop if args.hop is not None else (HOP_NHIP_SLICE if args.nhip else SLICE_COUNT)
    chu_ky_mau_s = hop * GIAY_MOI_SLICE

    model = ModelSnore(args.model)
    ket_qua = {}

    for muc_tieu in args.muc_tieu:
        files = liet_ke_wav(muc_tieu)
        if not files:
            print(f"CẢNH BÁO: {muc_tieu} không có file .wav nào", file=sys.stderr)
            continue

        gop = []
        chi_tiet = {}
        nhip = {}
        for f in files:
            scores, canh_bao, ti_le_bien = cham_diem_file(model, f, hop)
            gop.extend(scores)
            chi_tiet[f.name] = thong_ke(scores)
            if args.nhip:
                # Chấm nhịp TỪNG FILE, không gộp: các file là những đoạn 60s rời rạc, nối chuỗi
                # score của chúng lại sẽ tạo ra khoảng cách giả ở chỗ ghép.
                nhip[f.name] = phan_tich_nhip(scores, chu_ky_mau_s)
            if canh_bao:
                print(f"CẢNH BÁO {f.name}: {ti_le_bien:.0%} đặc trưng dồn ở biên 0/255 — nghi bước "
                      f"rescale sai, score không tin được", file=sys.stderr)

        ket_qua[muc_tieu] = {"tong_hop": thong_ke(gop), "theo_file": chi_tiet, "nhip": nhip}

    if args.json:
        print(json.dumps(ket_qua, ensure_ascii=False, indent=2))
    else:
        for muc_tieu, kq in ket_qua.items():
            t = kq["tong_hop"]
            print(f"\n=== {muc_tieu}  ({t.get('n', 0)} cửa sổ) ===")
            print(f"  min={t['min']}  median={t['median']}  p95={t['p95']}  p99={t['p99']}  max={t['max']}")
            print("  " + "  ".join(f">{ng}: {t[f'vuot_{ng}']}" for ng in NGUONG_THONG_KE))
            if args.nhip:
                print(f"  -- NHỊP (mẫu mỗi {chu_ky_mau_s:.2f}s) --")
                for ten, n in kq["nhip"].items():
                    ket = "NGÁY" if n["la_ngay"] else "-   "
                    print(f"    {ket} {ten:42s} đợt={n['so_dot']:3d} "
                          f"khoảng={str(n['khoang_trung_vi_s']):>6s}s CV={str(n['cv']):>6s} "
                          f"nền={n['nen']:.3f} {n['ly_do']}")
            else:
                for ten, s in kq["theo_file"].items():
                    print(f"    {ten:45s} median={s['median']:.4f} max={s['max']:.4f} >0.5={s['vuot_0.5']}")

    if args.tu_kiem:
        gop = [kq["tong_hop"] for kq in ket_qua.values() if kq["tong_hop"]]
        if not gop:
            print("\nTỰ KIỂM: không có dữ liệu", file=sys.stderr)
            return 1

        med = statistics.median([s["median"] for s in gop])
        tong_cua_so = sum(s["n"] for s in gop)
        tong_vuot = sum(s["vuot_0.5"] for s in gop)
        ti_le_vuot = tong_vuot / tong_cua_so if tong_cua_so else 0.0

        med_dat = (BOARD_SCORE_MIN - TU_KIEM_DUNG_SAI) <= med <= (BOARD_SCORE_MAX + TU_KIEM_DUNG_SAI)
        # Board báo có vượt 0,5 nhưng thưa. Không có cửa sổ nào vượt, hoặc vượt quá nửa số cửa sổ,
        # đều là dấu hiệu phân bố lệch hẳn so với board.
        vuot_dat = 0 < ti_le_vuot < 0.5
        dat = med_dat and vuot_dat

        print(f"\nTỰ KIỂM: median={med:.4f} (board báo điển hình {BOARD_SCORE_MIN}-{BOARD_SCORE_MAX}, "
              f"dung sai ±{TU_KIEM_DUNG_SAI}) | vượt 0,5: {tong_vuot}/{tong_cua_so} = {ti_le_vuot:.1%}")
        print("  => " + ("PASS — frontend khớp firmware, số đo tin được"
                         if dat else
                         "FAIL — frontend LỆCH firmware. KHÔNG dùng số đo này để đặt ngưỡng."))
        return 0 if dat else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
