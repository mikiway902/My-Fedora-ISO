#!/bin/bash
# Official Fedora repositories used by the Classic (Anaconda/dnf) installer.
#
# The installer must not depend on mirrors.fedoraproject.org: that name is a
# wildcard CNAME with many A/AAAA records and was the failing part of the
# original DNS path.  dl.fedoraproject.org is the official Fedora download
# host and resolves directly.  Installed systems keep the normal Fedora
# metalink repositories; only the installer source is pinned here.
#
# This file is sourced, not executed.
# shellcheck disable=SC2034  # values are used by the scripts that source this file

_repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ -z ${FEDORA_VERSION:-} ]]; then
    FEDORA_VERSION=$(sed -n \
        's/^FEDORA_VERSION="\{0,1\}\([0-9][0-9]*\)"\{0,1\}$/\1/p' \
        "$_repo_root/image-template.env" | head -1)
fi
FEDORA_VERSION=${FEDORA_VERSION:-44}
ARCH=${ARCH:-x86_64}

if [[ ! $FEDORA_VERSION =~ ^[0-9]+$ ]]; then
    printf 'repo-urls.sh: FEDORA_VERSION must be numeric, got %q\n' "$FEDORA_VERSION" >&2
    exit 1
fi

if [[ ! $ARCH =~ ^[a-z0-9_]+$ ]]; then
    printf 'repo-urls.sh: unsupported ARCH %q\n' "$ARCH" >&2
    exit 1
fi

# Override only for tests; production always uses the official host.
FEDORA_MIRROR_BASE=${FEDORA_MIRROR_BASE:-https://dl.fedoraproject.org/pub/fedora/linux}

FEDORA_RELEASE_URL="${FEDORA_MIRROR_BASE}/releases/${FEDORA_VERSION}/Everything/${ARCH}/os/"
FEDORA_UPDATES_URL="${FEDORA_MIRROR_BASE}/updates/${FEDORA_VERSION}/Everything/${ARCH}/"
FEDORA_ISO_DIR="${FEDORA_MIRROR_BASE}/releases/${FEDORA_VERSION}/Everything/${ARCH}/iso"
