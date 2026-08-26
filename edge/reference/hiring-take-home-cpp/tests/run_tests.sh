#!/usr/bin/env bash
set -euo pipefail
BIN="${1:-./smartbed_stream_processor}"

if [[ ! -x "$BIN" ]]; then
  echo "Binary not found or not executable: $BIN" >&2
  exit 1
fi

rm -rf output_test_rr output_test_apnea

"$BIN" tests/synthetic_rr15.csv --outdir output_test_rr >/tmp/smartbed_test_rr.log
if ! grep -q "RESP_RATE" output_test_rr/events.log; then
  echo "FAIL: expected RESP_RATE event for synthetic_rr15.csv" >&2
  exit 1
fi
if ! awk '/RESP_RATE/ && /RR=15\./ {found=1} END {exit found ? 0 : 1}' output_test_rr/events.log; then
  echo "FAIL: expected RR around 15 bpm for synthetic_rr15.csv" >&2
  exit 1
fi

"$BIN" tests/synthetic_apnea.csv --outdir output_test_apnea >/tmp/smartbed_test_apnea.log
if ! grep -q "APNEA_ALERT" output_test_apnea/events.log; then
  echo "FAIL: expected APNEA_ALERT for synthetic_apnea.csv" >&2
  exit 1
fi
if ! grep -q "APNEA_END" output_test_apnea/events.log; then
  echo "FAIL: expected APNEA_END for synthetic_apnea.csv" >&2
  exit 1
fi
if ! grep -q "spo2_support=yes" output_test_apnea/events.log; then
  echo "FAIL: expected SpO2 corroboration for synthetic_apnea.csv" >&2
  exit 1
fi

echo "All tests passed."
