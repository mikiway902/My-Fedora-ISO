#!/bin/bash
# Source validation that does not build an image.
#
# Needs shellcheck, python3 and podman. Container checks use the same Fedora 44
# image as the classic ISO, so ksvalidator and systemd-analyze match Fedora.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAILED=0

step() { printf '\n== %s ==\n' "$*"; }

run_step() {
    local name=$1
    shift
    step "$name"
    if "$@"; then
        printf 'ok: %s\n' "$name"
    else
        printf 'FAILED: %s\n' "$name" >&2
        FAILED=1
    fi
}

scripts() {
    find . -path ./output -prune -o -type f \
        \( -name '*.sh' -o -path './system_files/usr/bin/*' -o -path './system_files/usr/libexec/*' \) \
        -print0
}

check_bash_syntax() {
    local file rc=0
    while IFS= read -r -d '' file; do
        bash -n "$file" || rc=1
    done < <(scripts)
    return $rc
}

check_shellcheck() {
    mapfile -d '' files < <(scripts)
    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck "${files[@]}"
    else
        # Local fallback. Pin the version Ubuntu 24.04 ships (used by CI) so
        # that checks added or removed between releases cannot diverge.
        podman run --rm --security-opt label=disable -v "$PWD:/mnt" -w /mnt \
            docker.io/koalaman/shellcheck:v0.9.0 "${files[@]}"
    fi
}

check_toml() {
    python3 - <<'PY'
import glob
import tomllib

for path in sorted(glob.glob("disk_config/*.toml")):
    with open(path, "rb") as stream:
        tomllib.load(stream)
    print(f"toml ok: {path}")
PY
}

check_actionlint() {
    podman run --rm --security-opt label=disable -v "$PWD:/repo" -w /repo docker.io/rhysd/actionlint:latest \
        -shellcheck= .github/workflows/*.yml
}

check_kickstarts() {
    bash build_files/generate-kickstarts.sh "$TMP/ks" both || return 1
    podman run --rm --security-opt label=disable -v "$TMP/ks:/ks" quay.io/fedora/fedora:44 bash -euxo pipefail -c '
        dnf5 -y install pykickstart >/dev/null
        ksvalidator /ks/driftwm.ks /ks/gnome.ks
    '
}

check_units() {
    podman run --rm --security-opt label=disable -v "$PWD/system_files:/sf:ro" -w /sf quay.io/fedora/fedora:44 bash -euxo pipefail -c '
        dnf5 -y install systemd >/dev/null
        cp -a usr/libexec/my-fedora-* /usr/libexec/
        cp -a usr/bin/my-fedora-* usr/bin/thinkpad-diagnostics /usr/bin/
        chmod +x /usr/libexec/my-fedora-* /usr/bin/my-fedora-* /usr/bin/thinkpad-diagnostics
        systemd-analyze verify usr/lib/systemd/system/*.service usr/lib/systemd/user/*.service usr/lib/systemd/user/*.timer
    '
}

check_containerfile() {
    podman run --rm --security-opt label=disable --entrypoint hadolint \
        -v "$PWD:/repo" -w /repo docker.io/hadolint/hadolint:latest \
        --failure-threshold error Containerfile
}

run_step "Bash syntax" check_bash_syntax
run_step "ShellCheck" check_shellcheck
run_step "TOML" check_toml
run_step "Actionlint" check_actionlint
run_step "Kickstarts" check_kickstarts
run_step "systemd units" check_units
run_step "Containerfile" check_containerfile
run_step "Local tests" bash build_files/tests/run-tests.sh

if ((FAILED)); then
    printf '\nvalidation failed\n' >&2
    exit 1
fi

printf '\nvalidation passed\n'
