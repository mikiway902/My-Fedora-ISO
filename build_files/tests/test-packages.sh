#!/bin/bash
# Package list invariants: one category per package, no conflicting power
# daemons, pinned third-party sources and a consistent TuneD mapping.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC1091
source "$REPO/build_files/packages.sh"

fail() {
    echo "packages: $*" >&2
    exit 1
}

for array in BASE_PACKAGES HARDWARE_PACKAGES POWER_PACKAGES DEVELOPMENT_PACKAGES \
    MULTIMEDIA_PACKAGES OPTIONAL_PACKAGES GNOME_PACKAGES DRIFTWM_PACKAGES \
    GNOME_ALL_PACKAGES DRIFTWM_ALL_PACKAGES; do
    declare -n list=$array
    ((${#list[@]} > 0)) || fail "$array is empty"
    unset -n list
done

# A package must not be listed in two categories.
declare -A seen=()
for array in BASE_PACKAGES HARDWARE_PACKAGES POWER_PACKAGES DEVELOPMENT_PACKAGES \
    MULTIMEDIA_PACKAGES OPTIONAL_PACKAGES GNOME_PACKAGES DRIFTWM_PACKAGES; do
    declare -n list=$array
    for package in "${list[@]}"; do
        [[ -z ${seen[$package]:-} ]] || fail "$package is listed in ${seen[$package]} and $array"
        seen[$package]=$array
    done
    unset -n list
done

contains() {
    local needle=$1
    shift
    local item
    for item in "$@"; do
        [[ $item == "$needle" ]] && return 0
    done
    return 1
}

for forbidden in tlp auto-cpufreq power-profiles-daemon; do
    if contains "$forbidden" "${COMMON_PACKAGES[@]}" "${GNOME_PACKAGES[@]}" "${DRIFTWM_PACKAGES[@]}"; then
        fail "$forbidden must not be installed next to tuned-ppd"
    fi
done

contains tuned-ppd "${POWER_PACKAGES[@]}" || fail "tuned-ppd is missing from POWER_PACKAGES"
contains greetd "${DRIFTWM_PACKAGES[@]}" || fail "greetd is missing from DRIFTWM_PACKAGES"
contains gnome-tweaks "${GNOME_PACKAGES[@]}" || fail "gnome-tweaks is missing from GNOME_PACKAGES"
contains quickshell "${DRIFTWM_COPR_PACKAGES[@]}" || fail "quickshell is missing from DRIFTWM_COPR_PACKAGES"
contains code "${THIRD_PARTY_PACKAGES[@]}" || fail "code is missing from THIRD_PARTY_PACKAGES"

# The two desktops must stay separate.
if contains greetd "${GNOME_ALL_PACKAGES[@]}"; then fail "greetd leaked into the GNOME package set"; fi
if contains gnome-tweaks "${DRIFTWM_ALL_PACKAGES[@]}"; then fail "gnome-tweaks leaked into the DriftWM package set"; fi

# Every third-party download has a pinned version and a real SHA256.
for value in "$PDFCRAFT_VERSION" "$HAPP_VERSION" "$OPENCODE_VERSION"; do
    [[ -n $value ]] || fail "a third-party version is not pinned"
done
for sum in "$PDFCRAFT_SHA256" "$HAPP_SHA256" "$OPENCODE_SHA256"; do
    [[ $sum =~ ^[0-9a-f]{64}$ ]] || fail "invalid SHA256: $sum"
done
[[ $DEEPSEEK_HARNESS_PACKAGE == @deepseek-ai/dsh@* ]] || fail "DeepSeek Harness is not version-pinned"

# ppd.conf must only reference profiles that exist in the repo.
PPD="$REPO/system_files/etc/tuned/ppd.conf"
[[ -r $PPD ]] || fail "missing $PPD"
while IFS= read -r profile; do
    [[ -r "$REPO/system_files/etc/tuned/profiles/$profile/tuned.conf" ]] ||
        fail "ppd.conf references missing profile $profile"
done < <(sed -n 's/^[a-z-]*=\(my-fedora-[a-z0-9-]*\)$/\1/p' "$PPD")

echo "packages: OK"
