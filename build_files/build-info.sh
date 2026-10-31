#!/bin/bash
# Print reproducible build metadata for an artifact.
# Usage: build-info.sh KIND FILE...
set -euo pipefail

kind=${1:?usage: build-info.sh KIND FILE...}
shift

repo=$(cd "$(dirname "$0")/.." && pwd)
commit=${GITHUB_SHA:-$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo unknown)}
fedora_version=${FEDORA_VERSION:-$(sed -n 's/^FEDORA_VERSION="\{0,1\}\([0-9][0-9]*\)"\{0,1\}$/\1/p' "$repo/image-template.env" | head -1)}
fedora_version=${fedora_version:-44}

printf 'kind=%s\n' "$kind"
printf 'commit=%s\n' "$commit"
printf 'fedora_version=%s\n' "$fedora_version"
printf 'built=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'packages_sha256=%s\n' "$(sha256sum "$repo/build_files/packages.sh" | awk '{print $1}')"

for file in "$@"; do
    [[ -f $file ]] || continue
    printf 'artifact_sha256=%s  %s\n' "$(sha256sum "$file" | awk '{print $1}')" "$(basename "$file")"
done
