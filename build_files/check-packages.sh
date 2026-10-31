#!/bin/bash
# Check that every Fedora package named in packages.sh exists in Fedora 44.
# Run inside quay.io/fedora/fedora:44 (see `just check-packages`): the container
# provides dnf5 and the release repositories.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
source "$REPO/build_files/packages.sh"

if ! command -v dnf5 >/dev/null 2>&1; then
    echo "dnf5 is required; run this script in quay.io/fedora/fedora:44" >&2
    exit 1
fi

packages=()
for array in BASE_PACKAGES HARDWARE_PACKAGES POWER_PACKAGES DEVELOPMENT_PACKAGES \
    MULTIMEDIA_PACKAGES OPTIONAL_PACKAGES GNOME_PACKAGES DRIFTWM_PACKAGES; do
    declare -n list=$array
    packages+=("${list[@]}")
    unset -n list
done

mapfile -t packages < <(printf '%s\n' "${packages[@]}" | sort -u)

echo "resolving ${#packages[@]} Fedora packages"
missing=0
for package in "${packages[@]}"; do
    # --whatprovides also accepts virtual provides such as nodejs -> nodejs22
    if ! dnf5 -q repoquery --available --whatprovides "$package" --qf '%{name}\n' 2>/dev/null |
        grep -q .; then
        printf 'MISSING: %s\n' "$package" >&2
        missing=1
    fi
done

if ((missing)); then
    exit 1
fi

echo "all Fedora package names resolve"
echo
echo "third-party sources are not checked here:"
echo "  THIRD_PARTY_PACKAGES: ${THIRD_PARTY_PACKAGES[*]}"
echo "  DRIFTWM_COPR_PACKAGES: ${DRIFTWM_COPR_PACKAGES[*]}"
echo "  vendor RPMs and opencode are pinned with SHA256 and verified at build time"
