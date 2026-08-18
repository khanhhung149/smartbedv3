"""Bài đo có nhãn: điều phối các pha tư thế theo thời gian và chấm điểm luật đoán.

Vì sao cần: phiên 17/08 đo 3 phút với đủ 4 tư thế, nhưng không ghi lại lúc nào là tư
thế nào. Kết quả chỉ đọc được tới mức "nhãn nhấp nháy giữa hai lớp" mà không biết lớp
nào mới đúng. Không có nhãn thật thì không chấm được luật, chỉ mô tả được triệu chứng.

Ở đây người nằm chính là nguồn nhãn: script bảo nằm tư thế gì, người nằm đúng thế, nên
mọi frame trong pha đó có nhãn thật. Đổi lại phải nằm theo nhịp của máy — chấp nhận
được cho một bài đo 3 phút.

Đây vẫn là công cụ nghiệm thu. Ma trận nó in ra đo trên MỘT người, MỘT bố trí camera,
MỘT phiên — đủ để thấy luật sai ở đâu, KHÔNG đủ để công bố độ chính xác.
"""

import sys
import threading

import posture

# Người nằm đo thì không nhìn được màn hình — nằm sấp hay nhắm mắt là mất luôn kênh
# chữ trên cửa sổ. Báo bằng tiếng để biết lúc nào đổi tư thế.
_BEEP_HZ_SWITCH = 880
_BEEP_HZ_DONE = 523
_BEEP_MS = 250


def _beep_blocking(frequency: int, duration_ms: int, times: int) -> None:
    try:
        import winsound

        for _ in range(times):
            winsound.Beep(frequency, duration_ms)
    except (ImportError, RuntimeError):
        # Không phải Windows, hoặc không có thiết bị âm thanh: BEL ra terminal. Im
        # lặng khi stdout bị chuyển hướng ra file, nên đây chỉ là phương án chống đỡ.
        for _ in range(times):
            sys.stdout.write("\a")
            sys.stdout.flush()


def _beep_async(frequency: int, times: int) -> None:
    """Kêu bíp không chặn vòng lặp chính.

    winsound.Beep chặn suốt thời gian kêu; gọi thẳng trong vòng đọc frame thì mất
    ngần ấy mili-giây dữ liệu ngay đúng lúc người đang đổi tư thế.
    """
    threading.Thread(target=_beep_blocking, args=(frequency, _BEEP_MS, times), daemon=True).start()


def beep_switch() -> None:
    """Hai tiếng cao: sang pha mới, đổi tư thế."""
    _beep_async(_BEEP_HZ_SWITCH, 2)


def beep_done() -> None:
    """Ba tiếng thấp: hết bài, nằm yên cũng được rồi."""
    _beep_async(_BEEP_HZ_DONE, 3)


# (tên pha, nhãn kỳ vọng, tên ASCII vẽ lên cửa sổ, số giây)
#
# Pha đắp chăn đã bỏ theo quyết định 17/08. Câu hỏi nó đặt ra đã được trả lời: chăn
# KHÔNG giết phát hiện (66–91% qua các lượt), bác bỏ nỗi lo lớn nhất của report
# brainstorm 14/08. Giữ lại chỉ tốn thời gian nằm mà không thêm thông tin.
#
# Pha nằm ngửa BẮT BUỘC phải có, dù luật đã nhận ngửa tốt 99%. Câu hỏi đang mở là
# "tách nằm nghiêng khỏi nằm ngửa" — bỏ pha ngửa đi thì không thể biết một tín hiệu
# có tách được hai lớp hay không, chỉ thấy được nửa bức tranh. Bài đo hai pha nghiêng
# (thử ngày 17/08) đo được độ nhạy nhưng mù hoàn toàn với dương tính giả.
DEFAULT_PHASES = [
    ("nằm ngửa", posture.SUPINE, "NAM NGUA", 60),
    ("nghiêng trái", posture.SIDE_LEFT, "NGHIENG TRAI", 60),
    ("nghiêng phải", posture.SIDE_RIGHT, "NGHIENG PHAI", 60),
]

# Vài giây đầu mỗi pha là lúc người đang trở mình, chưa vào đúng tư thế. Chấm cả quãng
# đó thì luật bị đổ oan cho chuyển động. Bỏ qua, và nói rõ là đã bỏ.
SETTLE_S = 5


class Protocol:
    """Theo dõi pha hiện tại theo đồng hồ và cộng dồn kết quả chấm."""

    def __init__(self, phases=None, settle_s: int = SETTLE_S):
        self.phases = phases or DEFAULT_PHASES
        self.settle_s = settle_s
        self.total_s = sum(phase[3] for phase in self.phases)
        # {tên pha: {"kỳ vọng": nhãn, "đoán": {nhãn: số frame}, "trượt": số frame}}
        self.tally: dict[str, dict] = {
            name: {"kỳ vọng": expected, "đoán": {}, "trượt": 0, "tín_hiệu": {}}
            for name, expected, _, _ in self.phases
        }

    def current(self, elapsed_s: float):
        """Trả (tên pha, tên ASCII, giây còn lại, đang-trong-lúc-ổn-định) hoặc None khi hết bài."""
        offset = 0.0
        for name, _expected, ascii_name, seconds in self.phases:
            if elapsed_s < offset + seconds:
                into_phase = elapsed_s - offset
                return name, ascii_name, offset + seconds - elapsed_s, into_phase < self.settle_s
            offset += seconds
        return None

    def record(self, phase_name: str, predicted: str | None, signals: dict | None = None) -> None:
        """Ghi một frame. `predicted=None` nghĩa là model không thấy người."""
        entry = self.tally[phase_name]
        if predicted is None:
            entry["trượt"] += 1
        else:
            entry["đoán"][predicted] = entry["đoán"].get(predicted, 0) + 1
        if signals:
            for name, value in signals.items():
                entry["tín_hiệu"].setdefault(name, []).append(value)

    def signal_lines(self) -> list[str]:
        """Trung vị từng tín hiệu ứng viên theo từng pha.

        Đọc bảng này bằng cách so hai dòng `nghiêng trái` và `nghiêng phải`: tín hiệu
        nào ĐỔI DẤU giữa hai dòng đó là tín hiệu phân biệt được bên. Tín hiệu giữ
        nguyên dấu thì vô dụng, dù giá trị tuyệt đối có lớn tới đâu.
        """
        names: list[str] = []
        for entry in self.tally.values():
            for name in entry["tín_hiệu"]:
                if name not in names:
                    names.append(name)
        if not names:
            return []

        lines = [
            "",
            "===== TÍN HIỆU ỨNG VIÊN (trung vị) =====",
            "so hai pha nghiêng: tín hiệu nào ĐỔI DẤU thì dùng được",
        ]
        header = f"{'pha':<18}" + "".join(f"{name:>16}" for name in names)
        lines.append(header)
        for phase_name, entry in self.tally.items():
            cells = ""
            for name in names:
                values = sorted(entry["tín_hiệu"].get(name, []))
                cells += f"{values[len(values) // 2]:>16.3f}" if values else f"{'—':>16}"
            lines.append(f"{phase_name:<18}{cells}")
        return lines

    def report_lines(self) -> list[str]:
        """Ma trận nhầm lẫn dạng chữ, một khối cho mỗi pha."""
        lines = [
            "",
            "===== BÀI ĐO CÓ NHÃN =====",
            f"(bỏ {self.settle_s}s đầu mỗi pha lúc đang trở mình)",
        ]
        for name, expected, _ascii, seconds in self.phases:
            entry = self.tally[name]
            scored = sum(entry["đoán"].values())
            missed = entry["trượt"]
            total = scored + missed
            if not total:
                lines.append(f"\n[{name}] không có frame nào được chấm.")
                continue

            correct = entry["đoán"].get(expected, 0)
            lines.append(
                f"\n[{name}] {seconds}s — nhãn thật: {expected}"
                f"\n  phát hiện được người : {scored}/{total} frame ({100 * scored / total:.0f}%)"
            )
            if scored:
                lines.append(
                    f"  đoán ĐÚNG            : {correct}/{scored} frame "
                    f"({100 * correct / scored:.0f}%)"
                )
                wrong = {k: v for k, v in entry["đoán"].items() if k != expected}
                if wrong:
                    detail = ", ".join(
                        f"{label} {100 * count / scored:.0f}%"
                        for label, count in sorted(wrong.items(), key=lambda x: -x[1])
                    )
                    lines.append(f"  đoán SAI thành       : {detail}")

        lines.append(
            "\n⚠️ Một người, một bố trí camera, một phiên. Đủ để thấy luật sai ở đâu, "
            "KHÔNG đủ để công bố độ chính xác."
        )
        return lines
