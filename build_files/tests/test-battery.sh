#!/bin/bash
# Unit tests for my-fedora-battery against a fake sysfs tree.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
HELPER="$REPO/system_files/usr/bin/my-fedora-battery"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

BATTERY="$ROOT/class/power_supply/BAT0"
mkdir -p "$BATTERY"
printf 'Battery\n' >"$BATTERY/type"
printf '0\n' >"$BATTERY/charge_control_start_threshold"
printf '0\n' >"$BATTERY/charge_control_end_threshold"
CONFIG="$ROOT/battery.conf"
printf 'CHARGE_START=75\nCHARGE_END=80\n' >"$CONFIG"

run_battery() {
    MY_FEDORA_SYSFS_ROOT=$ROOT MY_FEDORA_BATTERY_CONFIG=$CONFIG bash "$HELPER" "$@"
}

# apply writes the configured values
run_battery apply >/dev/null
[[ $(cat "$BATTERY/charge_control_start_threshold") == 75 ]]
[[ $(cat "$BATTERY/charge_control_end_threshold") == 80 ]]

# set validates, persists and applies
run_battery set --start 40 --end 80 >/dev/null
grep -qx 'CHARGE_START=40' "$CONFIG"
[[ $(cat "$BATTERY/charge_control_start_threshold") == 40 ]]

# profiles
run_battery profile travel >/dev/null
grep -qx 'CHARGE_START=95' "$CONFIG"
grep -qx 'CHARGE_END=100' "$CONFIG"
[[ $(cat "$BATTERY/charge_control_end_threshold") == 100 ]]

# leading zeroes are decimal, not octal
run_battery set --start 075 --end 080 >/dev/null
[[ $(cat "$BATTERY/charge_control_start_threshold") == 75 ]]

# invalid ranges are rejected before anything is written
if run_battery set --start 90 --end 80 >/dev/null 2>&1; then
    echo "invalid range was accepted" >&2
    exit 1
fi

# a missing threshold file (old firmware) is not fatal
rm -f "$BATTERY/charge_control_start_threshold"
run_battery apply >/dev/null 2>&1

# no battery at all is not fatal (desktop or unsupported firmware)
rm -rf "$ROOT/class/power_supply/BAT0"
run_battery apply >/dev/null 2>&1
run_battery show >/dev/null 2>&1

echo "battery: OK"
