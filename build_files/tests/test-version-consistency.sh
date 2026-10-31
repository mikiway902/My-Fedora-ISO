#!/bin/bash
# Fail if a build file still pins a different Fedora major than image-template.env.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=../repo-urls.sh
# shellcheck disable=SC1091
source "$REPO/build_files/repo-urls.sh"

EXPECTED=$FEDORA_VERSION

fail() {
    echo "version consistency: $*" >&2
    exit 1
}

check_pattern() {
    local file=$1 pattern=$2 extract=$3
    local match version
    while IFS= read -r match; do
        version=$(sed -E "$extract" <<<"$match")
        [[ $version == "$EXPECTED" ]] \
            || fail "$file contains '$match' (Fedora $version), expected Fedora $EXPECTED"
    done < <(grep -oE "$pattern" "$file" || true)
}

FILES=(
    "$REPO/Containerfile"
    "$REPO/Justfile"
    "$REPO/image-template.env"
    "$REPO"/build_files/*.sh
    "$REPO"/build_files/tests/*.sh
    "$REPO"/.github/workflows/*.yml
)

for file in "${FILES[@]}"; do
    [[ -f $file ]] || continue
    check_pattern "$file" 'fedora:[0-9]+' 's/^fedora:([0-9]+)$/\1/'
    check_pattern "$file" 'releases/[0-9]+' 's#^releases/([0-9]+)$#\1#'
    check_pattern "$file" 'updates/[0-9]+' 's#^updates/([0-9]+)$#\1#'
    check_pattern "$file" 'FEDORA_VERSION="[0-9]+"' 's/^FEDORA_VERSION="([0-9]+)"$/\1/'
    check_pattern "$file" 'FEDORA_VERSION=[0-9]+' 's/^FEDORA_VERSION=([0-9]+)$/\1/'
    check_pattern "$file" 'FEDORA_VERSION:-[0-9]+' 's/^FEDORA_VERSION:-([0-9]+)$/\1/'
    check_pattern "$file" 'FEDORA_VERSION", "[0-9]+' 's/^FEDORA_VERSION", "([0-9]+)$/\1/'
    check_pattern "$file" 'fedora_version:-[0-9]+' 's/^fedora_version:-([0-9]+)$/\1/'
done

# The generated kickstarts must use the same release in every URL.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
bash "$REPO/build_files/generate-kickstarts.sh" "$TMP" both >/dev/null
for ks in "$TMP"/*.ks; do
    while IFS= read -r version; do
        [[ $version == "$EXPECTED" ]] \
            || fail "$(basename "$ks") references Fedora $version, expected $EXPECTED"
    done < <(grep -oE '/(releases|updates)/[0-9]+/' "$ks" \
        | sed -E 's#^/(releases|updates)/([0-9]+)/#\2#' | sort -u)
done

echo "version consistency: OK (Fedora $EXPECTED)"
