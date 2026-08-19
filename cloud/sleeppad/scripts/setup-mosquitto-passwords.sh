#!/usr/bin/env bash
# Generate Mosquitto password file for PRODUCTION.
#
# Creates two hashed entries from .env.prod:
#   - MQTT_USERNAME         (backend subscriber — read-all via acl-prod)
#   - MQTT_DEVICE_USERNAME  (shared device creds — publish only to sleeppad/%c/#)
#
# Usage:  ./scripts/setup-mosquitto-passwords.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$BACKEND_DIR/.env.prod"
PASSWORDS_FILE="$BACKEND_DIR/mosquitto/passwords"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: $ENV_FILE not found — copy .env.prod.example to .env.prod first" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

missing=()
[[ -z "${MQTT_USERNAME:-}" ]]        && missing+=("MQTT_USERNAME")
[[ -z "${MQTT_PASSWORD:-}" ]]        && missing+=("MQTT_PASSWORD")
[[ -z "${MQTT_DEVICE_USERNAME:-}" ]] && missing+=("MQTT_DEVICE_USERNAME")
[[ -z "${MQTT_DEVICE_PASSWORD:-}" ]] && missing+=("MQTT_DEVICE_PASSWORD")
if (( ${#missing[@]} )); then
  echo "error: missing in .env.prod: ${missing[*]}" >&2
  exit 1
fi

# Start fresh file with plaintext entries, then let mosquitto_passwd -U hash in place
{
  printf '%s:%s\n' "$MQTT_USERNAME"        "$MQTT_PASSWORD"
  printf '%s:%s\n' "$MQTT_DEVICE_USERNAME" "$MQTT_DEVICE_PASSWORD"
} > "$PASSWORDS_FILE"

docker run --rm \
  -v "$BACKEND_DIR/mosquitto:/mosquitto/config" \
  eclipse-mosquitto:2 \
  mosquitto_passwd -U /mosquitto/config/passwords

chmod 600 "$PASSWORDS_FILE"
echo "ok: $PASSWORDS_FILE written (mode 600) with 2 entries"
