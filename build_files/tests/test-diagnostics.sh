#!/bin/bash
# Smoke tests for the read-only tools shipped in the image.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

DIAG="$REPO/system_files/usr/bin/thinkpad-diagnostics"
bash "$DIAG" --report "$TMP/report.txt" >/dev/null
[[ -s $TMP/report.txt ]]
grep -q '== CPU ==' "$TMP/report.txt"
grep -q '== Аккумулятор ==' "$TMP/report.txt"

# list works without a running tuned-ppd
PROFILE="$REPO/system_files/usr/bin/my-fedora-power-profile"
[[ $(bash "$PROFILE" list | wc -l) -eq 3 ]]

# help does not require root or hardware
bash "$PROFILE" --help >/dev/null
bash "$REPO/system_files/usr/bin/my-fedora-battery" --help >/dev/null

echo "diagnostics: OK"
