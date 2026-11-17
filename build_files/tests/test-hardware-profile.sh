#!/bin/bash
# Exercise only profile setup and mocked driver functions, never host installation.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "hardware-profile: $*" >&2; exit 1; }

for script in build-classic-iso.sh check-classic-iso.sh classic-post.sh; do
    for profile in invalid 'generic;false'; do
        case $script in
            build-classic-iso.sh) args=(gnome) ;;
            check-classic-iso.sh) args=(missing.iso gnome) ;;
            classic-post.sh) args=(gnome) ;;
        esac
        if HARDWARE_PROFILE=$profile VARIANT=gnome bash "$REPO/build_files/$script" \
                "${args[@]}" > "$TMP/error" 2>&1; then
            fail "$script accepted invalid profile $profile"
        fi
        grep -q 'unsupported hardware profile/variant' "$TMP/error" \
            || fail "$script failed for the wrong reason"
    done
    case $script in
        build-classic-iso.sh) args=(driftwm) ;;
        check-classic-iso.sh) args=(missing.iso driftwm) ;;
        classic-post.sh) args=(driftwm) ;;
    esac
    if HARDWARE_PROFILE=desktop-nvidia VARIANT=driftwm bash "$REPO/build_files/$script" \
            "${args[@]}" > "$TMP/error" 2>&1; then
        fail "$script accepted desktop driftwm"
    fi
    grep -q 'unsupported hardware profile/variant' "$TMP/error" \
        || fail "$script did not reject desktop driftwm early"
done

# Run the real path setup in an isolated repository; stop before payload/build work.
mkdir -p "$TMP/repo/build_files"
cp "$REPO/build_files/repo-urls.sh" "$TMP/repo/build_files/"
cp "$REPO/image-template.env" "$TMP/repo/"
awk '/^echo "==> Generating/ { exit } { print }' \
    "$REPO/build_files/build-classic-iso.sh" > "$TMP/repo/build_files/paths.sh"
cat >> "$TMP/repo/build_files/paths.sh" <<'EOF'
printf '%s\n' "$WORK" "$OUT/my-fedora-classic-${VARIANT}${PROFILE_SUFFIX}.iso"
EOF
for profile in generic desktop-nvidia; do
    suffix=
    [[ $profile == generic ]] || suffix=-desktop-nvidia
    HARDWARE_PROFILE=$profile VARIANT=gnome bash "$TMP/repo/build_files/paths.sh" > "$TMP/paths"
    grep -Fxq "$TMP/repo/output/classic/gnome$suffix" "$TMP/paths" \
        || fail "wrong build work path for $profile"
    grep -Fxq "$TMP/repo/output/bootiso/my-fedora-classic-gnome$suffix.iso" "$TMP/paths" \
        || fail "wrong ISO name for $profile"
done
awk '/^MIN_ISO_BYTES=/ { exit } { print }' \
    "$REPO/build_files/check-classic-iso.sh" > "$TMP/repo/build_files/check-paths.sh"
# shellcheck disable=SC2016 # These variables belong to the generated script.
printf 'printf "%%s\\n" "$EXPECTED_KS" "$PAYLOAD_DIR"\n' >> "$TMP/repo/build_files/check-paths.sh"
HARDWARE_PROFILE=desktop-nvidia bash "$TMP/repo/build_files/check-paths.sh" missing.iso gnome > "$TMP/paths"
grep -Fxq "$TMP/repo/output/classic/gnome-desktop-nvidia/gnome.ks" "$TMP/paths" \
    || fail "checker uses the generic kickstart for desktop"
grep -Fxq "$TMP/repo/output/classic/gnome-desktop-nvidia" "$TMP/paths" \
    || fail "checker uses the generic payload for desktop"

# Exercise the post-install profile gate with every modifying command mocked.
awk '/^# Fingerprint / { copy = 1 } /^# Anaconda in kickstart/ { exit } copy { print }' \
    "$REPO/build_files/classic-post.sh" > "$TMP/profile-gate.sh"
cat > "$TMP/gate-test.sh" <<'EOF'
set -euo pipefail
record() { printf '%s\n' "$*" >> "$CALLS"; }
authselect() { record "authselect $*"; }
systemctl() { record "systemctl $*"; }
install() { record "install $*"; }
run_optional() { record "optional $*"; }
rm() { record "rm $*"; }
source "$1"
EOF
for profile in generic desktop-nvidia; do
    : > "$TMP/calls"
    CALLS="$TMP/calls" HARDWARE_PROFILE=$profile bash "$TMP/gate-test.sh" "$TMP/profile-gate.sh"
    if [[ $profile == generic ]]; then
        grep -q '^authselect enable-feature with-fingerprint$' "$TMP/calls" \
            || fail "generic fingerprint setup changed"
        grep -q '^install .* /etc/grub.d/40_custom$' "$TMP/calls" \
            || fail "generic Windows entry changed"
    else
        if grep -qE '^(authselect|install|optional) ' "$TMP/calls"; then
            fail "desktop enabled fingerprint or the P14s Windows entry"
        fi
        grep -Fq '/etc/tuned/ppd.conf' "$TMP/calls" || fail "desktop retained P14s PPD map"
        grep -Fq '/etc/tuned/profiles/my-fedora-p14s-' "$TMP/calls" \
            || fail "desktop retained P14s profiles"
        grep -Fq '/usr/share/my-fedora/grub-custom.cfg' "$TMP/calls" \
            || fail "desktop retained the custom Windows UUID"
    fi
done

# Extract just the function, not the chroot script's top-level side effects.
awk '/^install_nvidia\(\)/ { copy = 1 } copy { print } copy && /^}/ { exit }' \
    "$REPO/build_files/classic-post.sh" > "$TMP/driver-function.sh"
cat > "$TMP/driver-test.sh" <<'EOF'
set -euo pipefail
source "$1"
record() { printf '%s\n' "$*" >> "$CALLS"; }
install_rpmfusion() { record rpmfusion; [[ $FAIL_STEP != repo ]]; }
dnf5() { record "dnf5 $*"; [[ $FAIL_STEP != dnf ]]; }
kmodgenca() { record "kmodgenca $*"; [[ $FAIL_STEP != key ]]; }
rpm() {
    record "rpm $*"
    [[ $FAIL_STEP != rpm ]] || return 1
    [[ $FAIL_STEP != empty ]] || return 0
    printf '%s\n' 6.20.1-test.x86_64 6.20.2-test.x86_64
}
akmods() { record "akmods $*"; [[ $FAIL_STEP != build ]]; }
depmod() { record "depmod $*"; [[ $FAIL_STEP != depmod ]]; }
modinfo() {
    record "modinfo $*"
    [[ $FAIL_STEP != module ]] || return 1
    if [[ " $* " == *" -F signer "* && $FAIL_STEP != unsigned ]]; then
        echo 'akmods local signing CA'
    fi
    return 0
}
dracut() { record "dracut $*"; [[ $FAIL_STEP != initramfs ]]; }
uname() { echo 'ERROR: installer kernel must not be queried' >&2; exit 99; }
install_nvidia
record completed
EOF
CALLS="$TMP/calls" FAIL_STEP=none bash "$TMP/driver-test.sh" "$TMP/driver-function.sh"
for kernel in 6.20.1-test.x86_64 6.20.2-test.x86_64; do
    grep -Fxq "dnf5 -y install kernel-devel-$kernel" "$TMP/calls" \
        || fail "missing matching devel for $kernel"
    grep -Fxq "akmods --force --rebuild --akmod nvidia --kernels $kernel" "$TMP/calls" \
        || fail "missing explicit akmods kernel $kernel"
    grep -Fxq "dracut --force --kver $kernel" "$TMP/calls" \
        || fail "missing target initramfs $kernel"
done
key_line=$(grep -n '^kmodgenca -a$' "$TMP/calls" | cut -d: -f1)
driver_line=$(grep -n '^dnf5 -y install akmod-nvidia xorg-x11-drv-nvidia-cuda$' "$TMP/calls" | cut -d: -f1)
(( key_line < driver_line )) || fail "driver installed before key generation"
for step in repo dnf key rpm empty build depmod module unsigned initramfs; do
    : > "$TMP/calls"
    if CALLS="$TMP/calls" FAIL_STEP=$step bash "$TMP/driver-test.sh" \
            "$TMP/driver-function.sh" > "$TMP/error" 2>&1; then
        fail "$step failure was not fatal"
    fi
    if grep -qx completed "$TMP/calls"; then fail "$step continued to completion"; fi
    if [[ $step == build || $step == module || $step == unsigned ]] && \
            grep -q '^dracut ' "$TMP/calls"; then
        fail "$step regenerated the boot image before verification"
    fi
done
echo "hardware-profile: OK"
