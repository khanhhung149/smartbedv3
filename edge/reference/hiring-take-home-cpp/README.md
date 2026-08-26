# SmartBed self-adjusting posture subsystem - C++ submission

This repository contains two deliverables for the SmartBed interview task:

1. `design_doc.md` / `design_doc.pdf` - short system design document for camera skeleton tracking to 10 servo linear actuators.
2. `src/smartbed_stream_processor.cpp` - C++17 stream processor for `smartbed-sensor-stream.csv`.

The design is based on the supplied SmartBed MVP PDF, which describes camera/skeleton sleep-position tracking, 10 servo lifter engines, 50 cm lift, 500 N push force, 7-12 mm/s movement, noise <42 dB, modular non-contact sensors, and emergency safety components. Since the MVP PDF is not a detailed actuator datasheet, missing electrical/mechanical parameters are listed as assumptions in the design doc.

## Why C++

I chose C++17 because I understand it better and it maps well to edge deployment. The implementation is dependency-free: no Python, pandas, NumPy, OpenCV, or plotting libraries are needed for the coding task. It compiles with a normal Linux/WSL `g++` toolchain and writes CSV/log/SVG outputs.

## Repository layout

```text
.
├── design_doc.md
├── design_doc.pdf
├── smartbed-sensor-stream.csv
├── Makefile
├── CMakeLists.txt
├── src/
│   └── smartbed_stream_processor.cpp
├── figures/
│   ├── control_block_diagram.png
│   └── mechanical_sketch.png
├── tests/
│   ├── run_tests.sh
│   ├── synthetic_rr15.csv
│   └── synthetic_apnea.csv
└── output/
    ├── events.log
    ├── processed_timeline.csv
    ├── state_segments.csv
    ├── state_timeline.svg
    ├── chest_disp.svg
    └── resp_rate.svg
```

## Build and run

### WSL / Linux / macOS

```bash
make clean
make
./smartbed_stream_processor smartbed-sensor-stream.csv --outdir output
```

### Without Makefile

```bash
g++ -std=c++17 -O2 -Wall -Wextra -pedantic src/smartbed_stream_processor.cpp -o smartbed_stream_processor
./smartbed_stream_processor smartbed-sensor-stream.csv --outdir output
```

### CMake

```bash
cmake -S . -B build
cmake --build build
./build/smartbed_stream_processor smartbed-sensor-stream.csv --outdir output
```

## Run tests

```bash
make test
```

The tests are small smoke/integration tests:

- `synthetic_rr15.csv`: checks that a clean breathing sine wave produces a respiratory rate around 15 bpm.
- `synthetic_apnea.csv`: checks that apnea alert, apnea end, and SpO2 corroboration are detected.

## Output files

- `output/events.log`: human-readable event timeline: state changes, respiratory rate estimates, HR dropouts, apnea alerts.
- `output/state_segments.csv`: compact state segments such as `LYING_STILL`, `MOVING`, `LEAVING`, `EMPTY`.
- `output/processed_timeline.csv`: every sample with cleaned HR/SpO2, state, respiratory-rate fields, apnea fields.
- `output/*.svg`: simple plots generated directly by C++.

Expected key apnea event on the supplied CSV:

```text
314.60s | APNEA_ALERT | breathing amplitude low for >10s while occupied/still; since=304.60s ... spo2_support=yes
325.20s | APNEA_END   | breathing amplitude recovered
```

## Algorithm overview

### 1. State classification by sensor fusion

The state classifier fuses:

- `loadcell_kg`: primary occupancy signal.
- `presence`: radar/mmWave occupancy confirmation.
- `motion_intensity`: distinguishes stillness, movement, and leaving.
- load slope: detects fast unloading when a person leaves the bed.

It uses hysteresis so the state does not flicker when loadcell readings oscillate around a threshold.

### 2. Heart-rate dropout handling

`hr_bpm = 0` is treated as sensor dropout, not real heart rate. Short gaps are interpolated for timeline continuity, but HR=0 is not used as a medical emergency trigger.

### 3. Respiratory rate estimation

Respiratory rate is estimated only during `LYING_STILL` with low motion. The pipeline is:

```text
chest_disp window -> interpolate missing -> moving average -> detrend -> peak detection -> median peak interval -> breaths/min
```

A 30-second sliding window gives enough cycles for stable RR estimation. Motion-heavy windows are skipped to avoid motion artifact.

### 4. Apnea detection

Apnea is detected from recent chest-displacement amplitude, not from the 30-second RR window alone. This avoids reporting a normal RR during an ongoing flat-breathing interval. If low amplitude persists for more than 10 seconds while occupied/still, the code emits `APNEA_ALERT` at detection time and includes the start time in `since=...`.

SpO2 is used as corroboration, not the primary trigger, because oxygen desaturation can lag breathing changes. The event reports `spo2_support=yes/no` based on recent low SpO2 or a drop from baseline.

## Edge deployment notes: Orange Pi / Coral / Jetson

For a real edge deployment:

- Replace batch CSV loading with a fixed-size ring buffer for streaming sensor input.
- Pre-allocate buffers and avoid repeated dynamic allocation inside the real-time loop.
- Run safety/control loop at higher priority than AI inference.
- Use ONNX Runtime/TensorRT on Jetson or TFLite/Coral for skeleton detection.
- Keep the Safety Supervisor independent from the AI model; AI can propose posture, but safety logic must gate actuator commands.
- Persist actuator state and last known safe position so power recovery never resumes a stale movement command.
- Add watchdog, E-stop input, driver fault lines, per-channel current sensing, and limit-switch checks before connecting real actuators.

## Design assumptions

The MVP PDF does not provide the actuator voltage, rated current, stall current, feedback type, duty cycle, backlash, mounting dimensions, or self-locking confirmation. The design therefore assumes position feedback and self-locking behavior; if the selected actuator lacks these features, they must be added through external sensors/brakes before any real bed test.
