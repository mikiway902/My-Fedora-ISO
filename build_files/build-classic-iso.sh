#!/bin/bash
# Build a classic (Anaconda/dnf) netinstall ISO with the same package set as
# the atomic images. The source ISO is Fedora Everything; packages are fetched
# from Fedora/RPM Fusion/COPR during installation.
#
# The install source and the updates repo are pinned to official
# dl.fedoraproject.org URLs by generate-kickstarts.sh.  CI verifies those URLs
# and the remastered ISO before publishing.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VARIANT=${VARIANT:-${1:-driftwm}}

# shellcheck source=repo-urls.sh
# shellcheck disable=SC1091
source "$REPO_ROOT/build_files/repo-urls.sh"

case $VARIANT in
    driftwm|gnome) ;;
    *) echo "unknown variant: $VARIANT" >&2; exit 1 ;;
esac

if [[ $ARCH != x86_64 ]]; then
    echo "unsupported ARCH: $ARCH (this project builds x86_64 ISOs)" >&2
    exit 1
fi

WORK="$REPO_ROOT/output/classic/$VARIANT"
CACHE="$REPO_ROOT/output/classic/cache"
OUT="$REPO_ROOT/output/bootiso"
mkdir -p "$WORK" "$CACHE" "$OUT"

echo "==> Generating kickstart for $VARIANT (Fedora $FEDORA_VERSION, $ARCH)"
FEDORA_VERSION="$FEDORA_VERSION" ARCH="$ARCH" \
    bash "$REPO_ROOT/build_files/generate-kickstarts.sh" "$WORK" "$VARIANT"

echo "==> Preparing install payload"
tar -C "$REPO_ROOT/system_files" -czf "$WORK/system_files.tar.gz" .
cp "$REPO_ROOT/build_files/classic-post.sh" "$REPO_ROOT/build_files/packages.sh" "$WORK/"

if [[ $VARIANT == driftwm ]]; then
    echo "==> Building driftwm from the Containerfile stage"
    podman build --target driftwm-build -t localhost/my-fedora-driftwm-build \
        -f "$REPO_ROOT/Containerfile" "$REPO_ROOT"
    podman run --rm localhost/my-fedora-driftwm-build tar -C /out -cf - . \
        | gzip -9 > "$WORK/driftwm-runtime.tar.gz"
else
    # gnome does not need the driftwm payload; keep the kickstart copy list simple
    tar -czf "$WORK/driftwm-runtime.tar.gz" -T /dev/null
fi

echo "==> Resolving Fedora Everything netinst ${FEDORA_VERSION}"
ISO_PAGE=$(curl -fsSL --connect-timeout 15 --max-time 120 --retry 3 --retry-all-errors \
    "${FEDORA_ISO_DIR}/")
ISO_NAME=$(grep -oE "Fedora-Everything-netinst-${ARCH}-[0-9][0-9.-]*\.iso" <<<"$ISO_PAGE" \
    | sort -u | sort -V | tail -1)
[[ -n $ISO_NAME ]] || { echo "could not find the netinst ISO in ${FEDORA_ISO_DIR}/" >&2; exit 1; }
[[ $ISO_NAME == *"-${FEDORA_VERSION}-"* ]] \
    || { echo "$ISO_NAME does not belong to Fedora $FEDORA_VERSION" >&2; exit 1; }

ISO="$CACHE/$ISO_NAME"
if [[ ! -f $ISO ]]; then
    echo "==> Downloading $ISO_NAME"
    curl -fL --http1.1 --connect-timeout 15 --max-time 3600 \
        --speed-limit 1024 --speed-time 60 \
        --retry 5 --retry-all-errors --continue-at - -o "$ISO.part" \
        "${FEDORA_ISO_DIR}/${ISO_NAME}"
    mv "$ISO.part" "$ISO"
fi

echo "==> Verifying SHA256 of $ISO_NAME"
if [[ $ISO_NAME =~ ^Fedora-Everything-netinst-${ARCH}-(.+)\.iso$ ]]; then
    RELEASE=${BASH_REMATCH[1]}
else
    echo "cannot parse the release from $ISO_NAME" >&2
    exit 1
fi
CHECKSUM_NAME="Fedora-Everything-${RELEASE}-${ARCH}-CHECKSUM"
CHECKSUM="$CACHE/$CHECKSUM_NAME"
if [[ ! -f $CHECKSUM ]]; then
    curl -fL --connect-timeout 15 --max-time 120 --retry 5 --retry-all-errors \
        -o "$CHECKSUM.part" "${FEDORA_ISO_DIR}/${CHECKSUM_NAME}"
    mv "$CHECKSUM.part" "$CHECKSUM"
fi
if ! ( cd "$CACHE" && grep -F "(${ISO_NAME})" "$CHECKSUM" | sha256sum -c - ); then
    echo "SHA256 verification failed for $ISO_NAME" >&2
    rm -f "$ISO"
    exit 1
fi

echo "==> Remastering ISO with kickstart and payload (mkksiso in Fedora container)"
rm -f "$WORK/out.iso"

# mkksiso calls mkefiboot -> losetup -> needs a rootful, privileged container
PODMAN_ROOT=(podman)
if [[ $EUID -ne 0 ]]; then
    command -v sudo >/dev/null || { echo "mkksiso needs sudo (rootful podman)" >&2; exit 1; }
    PODMAN_ROOT=(sudo podman)
fi

SEC_OPTS=()
[[ -e /sys/fs/selinux/enforce ]] && SEC_OPTS+=(--security-opt label=disable)

"${PODMAN_ROOT[@]}" run --rm --privileged "${SEC_OPTS[@]}" \
    -v "$WORK:/work" \
    -v "$CACHE:/cache:ro" \
    "quay.io/fedora/fedora:${FEDORA_VERSION}" \
    bash -euxo pipefail -c "
        dnf5 -y install lorax
        mkksiso \
            --ks /work/${VARIANT}.ks \
            --add /work/classic-post.sh \
            --add /work/packages.sh \
            --add /work/system_files.tar.gz \
            --add /work/driftwm-runtime.tar.gz \
            /cache/${ISO_NAME} /work/out.iso
    "

# rootful container writes the ISO as root when the script itself is not root
if [[ $EUID -ne 0 ]]; then
    sudo chown "$(id -u):$(id -g)" "$WORK/out.iso"
fi

echo "==> Verifying remastered ISO"
FEDORA_VERSION="$FEDORA_VERSION" ARCH="$ARCH" \
    bash "$REPO_ROOT/build_files/check-classic-iso.sh" \
        "$WORK/out.iso" "$VARIANT" \
        --expected-ks "$WORK/${VARIANT}.ks" \
        --payload-dir "$WORK"

mv -f "$WORK/out.iso" "$OUT/my-fedora-classic-${VARIANT}.iso"
echo "==> ISO: $OUT/my-fedora-classic-${VARIANT}.iso"
