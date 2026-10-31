#!/bin/bash
# Verify a remastered Classic ISO before it is published.
#
# Usage:
#   check-classic-iso.sh ISO VARIANT [--expected-ks PATH] [--payload-dir DIR]
#
# The checks cover the things that a plain "xorriso can read it" test misses:
# the volume label used by inst.stage2/inst.ks, both GRUB configurations, the
# embedded kickstart, its repository URLs, and the install payload files.

set -euo pipefail
export LC_ALL=C

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=repo-urls.sh
# shellcheck disable=SC1091
source "$REPO_ROOT/build_files/repo-urls.sh"

ISO=${1:?usage: check-classic-iso.sh ISO VARIANT [--expected-ks PATH] [--payload-dir DIR]}
VARIANT=${2:?usage: check-classic-iso.sh ISO VARIANT [--expected-ks PATH] [--payload-dir DIR]}
shift 2

case $VARIANT in
    driftwm|gnome) ;;
    *) echo "check-classic-iso.sh: unknown variant: $VARIANT" >&2; exit 2 ;;
esac

EXPECTED_KS="$REPO_ROOT/output/classic/$VARIANT/$VARIANT.ks"
PAYLOAD_DIR="$REPO_ROOT/output/classic/$VARIANT"

while (( $# )); do
    case $1 in
        --expected-ks)
            EXPECTED_KS=${2:?--expected-ks needs a path}
            shift 2
            ;;
        --payload-dir)
            PAYLOAD_DIR=${2:?--payload-dir needs a path}
            shift 2
            ;;
        *)
            echo "check-classic-iso.sh: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

MIN_ISO_BYTES=${MIN_ISO_BYTES:-1073741824}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
    printf 'ISO CHECK FAILED: %s\n' "$*" >&2
    exit 1
}

extract() {
    local src=$1 dst=$2
    if ! xorriso -indev "$ISO" -osirrox on -extract "$src" "$dst" \
            >/dev/null 2>"$TMP/xorriso.err"; then
        fail "cannot extract $src: $(tr '\n' ' ' < "$TMP/xorriso.err")"
    fi
}

[[ -f $ISO ]] || fail "ISO not found: $ISO"
iso_bytes=$(wc -c < "$ISO")
(( iso_bytes >= MIN_ISO_BYTES )) || fail "$ISO is $iso_bytes bytes, below $MIN_ISO_BYTES"

[[ $(dd if="$ISO" bs=1 skip=32769 count=5 2>/dev/null) == CD001 ]] \
    || fail "$ISO has no ISO 9660 primary volume descriptor"

pvd=$(xorriso -indev "$ISO" -pvd_info 2>/dev/null || true)
label=$(printf '%s\n' "$pvd" | sed -n "s/^Volume id *: *'\(.*\)'$/\1/p" | head -1)
if [[ -z $label ]]; then
    label=$(printf '%s\n' "$pvd" | sed -n 's/^Volume [Ii]d *: *//p' | head -1 | tr -d "'")
fi
[[ -n $label ]] || fail "cannot read the ISO volume label"
[[ $label == *"-${FEDORA_VERSION}" ]] \
    || fail "volume label '$label' does not contain Fedora $FEDORA_VERSION"

extract /.discinfo "$TMP/discinfo"
disc_version=$(sed -n '2p' "$TMP/discinfo")
disc_arch=$(sed -n '3p' "$TMP/discinfo")
[[ $disc_version == "$FEDORA_VERSION" ]] \
    || fail ".discinfo declares Fedora $disc_version instead of $FEDORA_VERSION"
[[ $disc_arch == "$ARCH" ]] \
    || fail ".discinfo declares architecture $disc_arch instead of $ARCH"

xorriso -indev "$ISO" -report_el_torito plain > "$TMP/torito.txt" 2>&1 \
    || fail "xorriso cannot read the El Torito boot catalog"
grep -q 'El Torito boot img' "$TMP/torito.txt" \
    || fail "$ISO has no El Torito boot image"

xorriso -indev "$ISO" -ls /images/pxeboot > "$TMP/pxeboot.txt" 2>&1 \
    || fail "$ISO has no /images/pxeboot"
grep -q 'vmlinuz' "$TMP/pxeboot.txt" \
    || fail "$ISO has no /images/pxeboot/vmlinuz"
grep -q 'initrd.img' "$TMP/pxeboot.txt" \
    || fail "$ISO has no /images/pxeboot/initrd.img"

xorriso -indev "$ISO" -ls /images > "$TMP/images.txt" 2>&1 \
    || fail "$ISO has no /images directory"
grep -q 'install.img' "$TMP/images.txt" \
    || fail "$ISO has no /images/install.img (no Anaconda stage2)"

extract /EFI/BOOT/grub.cfg "$TMP/grub-efi.cfg"
extract /boot/grub2/grub.cfg "$TMP/grub-bios.cfg"

for cfg in "$TMP/grub-efi.cfg" "$TMP/grub-bios.cfg"; do
    grep -Fq "inst.stage2=hd:LABEL=${label}" "$cfg" \
        || fail "$(basename "$cfg") does not use inst.stage2=hd:LABEL=${label}"
    grep -Fq "inst.ks=hd:LABEL=${label}:/${VARIANT}.ks" "$cfg" \
        || fail "$(basename "$cfg") does not load /${VARIANT}.ks from the ISO"
    if grep -q 'inst.repo=' "$cfg"; then
        fail "$(basename "$cfg") contains inst.repo; the kickstart url must be the only source"
    fi
done

extract "/${VARIANT}.ks" "$TMP/embedded.ks"
[[ -f $EXPECTED_KS ]] || fail "expected kickstart not found: $EXPECTED_KS"
if ! cmp -s "$TMP/embedded.ks" "$EXPECTED_KS"; then
    diff -u "$EXPECTED_KS" "$TMP/embedded.ks" | head -60 >&2 || true
    fail "embedded /${VARIANT}.ks differs from $EXPECTED_KS"
fi

grep -Fq "url --url=\"${FEDORA_RELEASE_URL}\"" "$TMP/embedded.ks" \
    || fail "embedded kickstart does not use ${FEDORA_RELEASE_URL}"
grep -Fq "repo --name=\"fedora-updates\" --baseurl=\"${FEDORA_UPDATES_URL}\"" "$TMP/embedded.ks" \
    || fail "embedded kickstart does not use ${FEDORA_UPDATES_URL}"
if grep -qE '^(url|repo) .*(mirrors\.fedoraproject\.org|download\.fedoraproject\.org)' "$TMP/embedded.ks"; then
    fail "embedded kickstart still references a Fedora metalink/redirect host"
fi

while IFS= read -r version; do
    [[ $version == "$FEDORA_VERSION" ]] \
        || fail "embedded kickstart references Fedora $version instead of $FEDORA_VERSION"
done < <(grep -oE '/(releases|updates)/[0-9]+/' "$TMP/embedded.ks" \
    | sed -E 's#^/(releases|updates)/([0-9]+)/#\2#' | sort -u)

grep -q '^%pre ' "$TMP/embedded.ks" || fail "embedded kickstart has no %pre section"
grep -q '^%post --nochroot ' "$TMP/embedded.ks" || fail "embedded kickstart has no %post --nochroot"
grep -q '^%post --interpreter=' "$TMP/embedded.ks" || fail "embedded kickstart has no chroot %post"
grep -Fq "bash /root/my-fedora-payload/classic-post.sh ${VARIANT}" "$TMP/embedded.ks" \
    || fail "embedded kickstart does not run classic-post.sh $VARIANT"

for file in classic-post.sh packages.sh system_files.tar.gz driftwm-runtime.tar.gz; do
    extract "/${file}" "$TMP/${file}"
    [[ -f $PAYLOAD_DIR/$file ]] || fail "payload source is missing: $PAYLOAD_DIR/$file"
    cmp -s "$TMP/${file}" "$PAYLOAD_DIR/$file" \
        || fail "${file} inside the ISO differs from $PAYLOAD_DIR/$file"
done

gzip -t "$TMP/system_files.tar.gz" || fail "system_files.tar.gz is not a valid gzip file"
gzip -t "$TMP/driftwm-runtime.tar.gz" || fail "driftwm-runtime.tar.gz is not a valid gzip file"
tar -tzf "$TMP/system_files.tar.gz" >/dev/null || fail "system_files.tar.gz is not a valid tar archive"

printf 'ISO check OK: %s (label %s, Fedora %s, %s)\n' \
    "$ISO" "$label" "$FEDORA_VERSION" "$VARIANT"
