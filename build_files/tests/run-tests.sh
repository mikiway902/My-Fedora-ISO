#!/bin/bash
# Run every local test that does not need root, podman or the hardware.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)

for test in "$DIR"/test-*.sh; do
    printf '==> %s\n' "$(basename "$test")"
    bash "$test"
done

echo "all local tests passed"
