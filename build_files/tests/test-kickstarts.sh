#!/bin/bash
# Kickstart invariants: Classic must never call bootc, both variants use the
# shared package lists and carry the whole install payload.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

bash "$REPO/build_files/generate-kickstarts.sh" "$TMP" both >/dev/null

fail() {
    echo "kickstarts: $*" >&2
    exit 1
}

for ks in "$TMP/driftwm.ks" "$TMP/gnome.ks"; do
    [[ -s $ks ]] || fail "$ks was not generated"
    grep -q 'classic-post.sh' "$ks" || fail "$ks does not run classic-post.sh"
    grep -q 'system_files.tar.gz' "$ks" || fail "$ks does not carry system_files"
    grep -q 'driftwm-runtime.tar.gz' "$ks" || fail "$ks does not carry the driftwm payload"
    grep -q '^    tuned-ppd$' "$ks" || fail "$ks does not install tuned-ppd"
    if grep -q 'bootc' "$ks"; then
        fail "$ks contains bootc; Classic must stay independent of bootc"
    fi
    if grep -qE '^    (tlp|auto-cpufreq|power-profiles-daemon)$' "$ks"; then
        fail "$ks installs a conflicting power daemon"
    fi
done

grep -q '^@\^custom-environment$' "$TMP/driftwm.ks" || fail "driftwm does not use the custom environment"
grep -q '^    initial-setup$' "$TMP/driftwm.ks" || fail "driftwm has no initial-setup"
grep -q 'classic-post.sh driftwm' "$TMP/driftwm.ks" || fail "driftwm %post uses the wrong variant"
grep -q '^    greetd$' "$TMP/driftwm.ks" || fail "driftwm kickstart has no greetd"
if grep -q '^    gnome-tweaks$' "$TMP/driftwm.ks"; then
    fail "gnome-tweaks leaked into the driftwm kickstart"
fi

grep -q '^@\^workstation-product-environment$' "$TMP/gnome.ks" || fail "gnome does not use workstation-product"
grep -q '^    gnome-initial-setup$' "$TMP/gnome.ks" || fail "gnome has no gnome-initial-setup"
grep -q '^-power-profiles-daemon$' "$TMP/gnome.ks" || fail "gnome does not exclude power-profiles-daemon"
grep -q 'classic-post.sh gnome' "$TMP/gnome.ks" || fail "gnome %post uses the wrong variant"
if grep -q '^    greetd$' "$TMP/gnome.ks"; then
    fail "greetd leaked into the gnome kickstart"
fi

# The Atomic installers do switch to the published image, with a readable retry.
for toml in "$REPO"/disk_config/iso-*.toml; do
    grep -q 'bootc switch --mutate-in-place' "$toml" || fail "$toml does not switch to the bootc image"
    grep -q 'for attempt in 1 2 3' "$toml" || fail "$toml has no retry loop"
    grep -q 'getent hosts ghcr.io' "$toml" || fail "$toml does not check network/DNS"
done

echo "kickstarts: OK"
