"""Sleep-session state machine — pure functions, no database.

Every rule here comes from the Legact Pro V2 protocol PDF, not from guesswork:

  p.2      a session opens after 30 consecutive seconds in bed, closes after
           30 minutes out of bed, and a single recording caps at 1440 minutes
  p.4 §2.4.1  heart rate and respiration read 0 when the person leaves the bed

`status` is an *event code* for that second, not a bed-occupancy flag. The codes
are 01 off-bed, 02 movement, 03 sitting up, 04 asleep, 05 awake, 06 heavy object,
07 snoring, 08 weak breathing. There is no "currently in bed" code, so occupancy
is never derived from `status`.

Caveat carried from the plan (R1): hr/rr = 0 also means "could not be computed",
so `is_on_bed` conflates an empty bed with a noisy sensor. The thresholds live in
config for exactly that reason. Treat session boundaries as provisional until
they have been checked against a real night.
"""

from dataclasses import dataclass
from datetime import datetime, timedelta

# Defaults mirror the PDF. Callers pass overrides from Settings; nothing here
# reads config directly so the module stays importable without an environment.
SESSION_OPEN_SECONDS = 30
SESSION_CLOSE_SECONDS = 1800
SESSION_MAX_MINUTES = 1440

# Event codes from p.4 §2.4.1 that the summary counts.
STATUS_SIT_UP = 0x03
STATUS_AWAKE = 0x05


@dataclass(frozen=True)
class Sample:
    """One second of sec_data, already ordered by time."""

    t: datetime
    hr: int | None
    rr: float | None
    status: int | None


@dataclass(frozen=True)
class SessionWindow:
    """A closed or still-open session boundary pair.

    `ended_at` is None while the person is still in bed at the end of the input —
    the builder writes that as an open session and revisits it on a later tick.
    """

    started_at: datetime
    ended_at: datetime | None
    sit_up_count: int
    wake_count: int


def is_on_bed(hr: int | None, rr: float | None) -> bool:
    """p.4 §2.4.1: both readings drop to 0 once the bed is empty."""
    return (hr or 0) > 0 or (rr or 0) > 0


def build_sessions(
    samples: list[Sample],
    *,
    now: datetime | None = None,
    open_seconds: int = SESSION_OPEN_SECONDS,
    close_seconds: int = SESSION_CLOSE_SECONDS,
    max_minutes: int = SESSION_MAX_MINUTES,
) -> list[SessionWindow]:
    """Turn an ordered run of per-second samples into session windows.

    Three properties are easy to get wrong and are each asserted by the tests:

    * A session's `ended_at` is the moment the bed was left, not the moment the
      30-minute confirmation elapsed. Reporting the later time would inflate
      every night by half an hour.
    * A hole in the data counts as time out of bed. The sensor publishes once a
      second while occupied, so a gap is absence of evidence of presence, and
      inventing presence across it would be fabricating a reading.
    * Hitting the 1440-minute cap ends the recording but not the occupancy —
      someone still in bed starts a fresh session at the cut.

    Pass `now` to apply the same absence rule to the silence after the last
    sample. Without it a night whose data simply stops — the pad unplugged in
    the morning — stays open forever and the app shows a session with no end.
    The close time is the last sample, the final moment presence was observed;
    guessing anything later would report bed time nobody recorded.
    """
    windows: list[SessionWindow] = []
    max_duration = timedelta(minutes=max_minutes)

    started_at: datetime | None = None      # confirmed session start, None = IDLE
    pending_start: datetime | None = None   # occupancy run not yet 30s long
    absent_since: datetime | None = None    # first second of the current absence
    sit_ups = 0
    wakes = 0
    prev_t: datetime | None = None

    def begin(at: datetime) -> None:
        nonlocal started_at, pending_start, absent_since, sit_ups, wakes
        started_at = at
        pending_start = None
        absent_since = None
        sit_ups = 0
        wakes = 0

    def close(ended_at: datetime | None) -> None:
        nonlocal started_at
        windows.append(
            SessionWindow(
                started_at=started_at,  # type: ignore[arg-type]
                ended_at=ended_at,
                sit_up_count=sit_ups,
                wake_count=wakes,
            )
        )
        started_at = None

    for s in samples:
        # A gap between consecutive rows is absence starting at the last known
        # second, so a dropout closes a session exactly like leaving the bed.
        if prev_t is not None and (s.t - prev_t).total_seconds() > 1:
            if started_at is not None:
                if absent_since is None:
                    absent_since = prev_t
                if (s.t - absent_since).total_seconds() >= close_seconds:
                    close(absent_since)
                    absent_since = None
            else:
                pending_start = None
        prev_t = s.t

        on_bed = is_on_bed(s.hr, s.rr)

        if started_at is None:
            if not on_bed:
                pending_start = None
                continue
            if pending_start is None:
                pending_start = s.t
                sit_ups = 0
                wakes = 0
            sit_ups += s.status == STATUS_SIT_UP
            wakes += s.status == STATUS_AWAKE
            # Inclusive span: the 30th consecutive second sits 29s after the first,
            # and the counters above already cover that qualifying run.
            if (s.t - pending_start).total_seconds() >= open_seconds - 1:
                started_at = pending_start
                pending_start = None
                absent_since = None
            continue

        # IN_SESSION
        if on_bed:
            absent_since = None
            sit_ups += s.status == STATUS_SIT_UP
            wakes += s.status == STATUS_AWAKE
        else:
            if absent_since is None:
                absent_since = s.t
            elif (s.t - absent_since).total_seconds() >= close_seconds:
                close(absent_since)
                absent_since = None
                continue

        if started_at is not None and s.t - started_at >= max_duration:
            cut = started_at + max_duration
            close(cut)
            # Still occupied — the cap ends the recording, not the night.
            if on_bed:
                begin(cut)
            else:
                absent_since = None

    if started_at is not None:
        ended_at = absent_since
        if ended_at is None and now is not None and prev_t is not None:
            if (now - prev_t).total_seconds() >= close_seconds:
                ended_at = prev_t
        # Absence that never reached the 30-minute threshold still ends the
        # session where the bed was left; ongoing occupancy leaves it open.
        close(ended_at)
    return windows
