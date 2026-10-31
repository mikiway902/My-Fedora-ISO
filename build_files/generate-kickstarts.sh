#!/bin/bash
# Generate Anaconda kickstart files for the classic (non-atomic) install ISOs.
# Package lists come from packages.sh so atomic and classic stay in sync.
#
# The installer source is pinned to official dl.fedoraproject.org URLs.  Without
# an explicit url/repo Anaconda falls back to "Closest mirror" and uses the
# netinst's enabled fedora/updates metalinks, which is the path that failed when
# mirrors.fedoraproject.org could not be resolved.  The installed system keeps
# Fedora's normal metalink repositories.

set -euo pipefail

OUT_DIR=${1:?usage: generate-kickstarts.sh OUT_DIR [driftwm|gnome|both]}
VARIANT=${2:-both}

# shellcheck source=repo-urls.sh
# shellcheck disable=SC1091
source "$(dirname "$0")/repo-urls.sh"
# shellcheck source=packages.sh
# shellcheck disable=SC1091
source "$(dirname "$0")/packages.sh"

mkdir -p "$OUT_DIR"

write_packages() {
    local -n packages=$1
    printf '    %s\n' "${packages[@]}"
}

write_common() {
    local label=$1
    cat <<EOF
# Classic Fedora ${FEDORA_VERSION} ${label}, installed by Anaconda from Fedora Everything.
# Storage is intentionally left interactive: this laptop dual-boots Windows.
#
# The installer uses explicit official URLs (not the mirrors.fedoraproject.org
# metalink).  The installed system keeps Fedora's normal repository files.

lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us,ru'
timezone Europe/Moscow --utc
selinux --enforcing
firewall --enabled --service=ssh
rootpw --lock

network --bootproto=dhcp --device=link --activate --onboot=on
url --url="$FEDORA_RELEASE_URL"
repo --name="fedora-updates" --baseurl="$FEDORA_UPDATES_URL"

EOF
}

write_pre() {
    cat <<'EOF'
%pre --interpreter=/bin/bash --log=/tmp/pre-anaconda-logs/my-fedora-pre.log
set -u

PAYLOAD_FILES=(classic-post.sh packages.sh system_files.tar.gz driftwm-runtime.tar.gz)
STAGE=/run/install/my-fedora-payload
MOUNT_POINT=/run/install/my-fedora-media
PAYLOAD_SRC=

have_payload() {
    local dir=$1 file
    for file in "${PAYLOAD_FILES[@]}"; do
        [ -f "$dir/$file" ] || return 1
    done
    return 0
}

for dir in /run/install/repo /mnt/install/repo /run/install/isodir /mnt/install/isodir; do
    if have_payload "$dir"; then PAYLOAD_SRC=$dir; break; fi
done

if [ -z "$PAYLOAD_SRC" ]; then
    for dir in /run/media/*/*; do
        if have_payload "$dir"; then PAYLOAD_SRC=$dir; break; fi
    done
fi

if [ -z "$PAYLOAD_SRC" ]; then
    # Fall back to the label in inst.stage2/inst.ks and mount the media read-only.
    label=$(sed -n 's/.*inst\.\(ks\|stage2\)=hd:LABEL=\([^ :]*\).*/\2/p' /proc/cmdline | head -1)
    if [ -n "$label" ]; then
        mkdir -p "$MOUNT_POINT"
        for dev in /dev/disk/by-label/*; do
            [ "$(basename "$dev")" = "$label" ] || continue
            if mount -o ro "$dev" "$MOUNT_POINT" 2>/dev/null; then
                if have_payload "$MOUNT_POINT"; then PAYLOAD_SRC=$MOUNT_POINT; fi
            fi
            break
        done
    fi
fi

mkdir -p "$STAGE"
if [ -n "$PAYLOAD_SRC" ]; then
    if cp -a "$PAYLOAD_SRC"/classic-post.sh "$PAYLOAD_SRC"/packages.sh \
            "$PAYLOAD_SRC"/system_files.tar.gz "$PAYLOAD_SRC"/driftwm-runtime.tar.gz \
            "$STAGE"/; then
        printf 'staged from %s\n' "$PAYLOAD_SRC" > "$STAGE/status"
    else
        printf 'copy failed from %s\n' "$PAYLOAD_SRC" > "$STAGE/status"
    fi
else
    printf 'payload not found; post-install will retry discovery\n' > "$STAGE/status"
fi

{
    date -u
    printf '\n== /proc/cmdline\n'
    cat /proc/cmdline
    printf '\n== install mounts\n'
    findmnt -R /run/install || true
    printf '\n== block devices\n'
    lsblk -f || true
    printf '\n== payload status\n'
    cat "$STAGE/status" 2>/dev/null || true
} > "$STAGE/diagnostics.txt" 2>&1

exit 0
%end
EOF
}

write_post_nochroot() {
    cat <<'EOF'
%post --nochroot --interpreter=/bin/bash --erroronfail --log=/mnt/sysimage/var/log/my-fedora-install/post-nochroot.log
set -euo pipefail

PAYLOAD_FILES=(classic-post.sh packages.sh system_files.tar.gz driftwm-runtime.tar.gz)
STAGE=/run/install/my-fedora-payload
MOUNT_POINT=/run/install/my-fedora-media
LOG_DIR=/mnt/sysimage/var/log/my-fedora-install
PAYLOAD_SRC=
KS_SRC=

have_payload() {
    local dir=$1 file
    for file in "${PAYLOAD_FILES[@]}"; do
        [ -f "$dir/$file" ] || return 1
    done
    return 0
}

mkdir -p "$LOG_DIR/installer/pre" "$LOG_DIR/installer/payload" || true

if have_payload "$STAGE"; then PAYLOAD_SRC=$STAGE; fi
if [ -z "$PAYLOAD_SRC" ]; then
    for dir in /run/install/repo /mnt/install/repo /run/install/isodir /mnt/install/isodir; do
        if have_payload "$dir"; then PAYLOAD_SRC=$dir; break; fi
    done
fi
if [ -z "$PAYLOAD_SRC" ]; then
    for dir in /run/media/*/*; do
        if have_payload "$dir"; then PAYLOAD_SRC=$dir; break; fi
    done
fi
if [ -z "$PAYLOAD_SRC" ]; then
    label=$(sed -n 's/.*inst\.\(ks\|stage2\)=hd:LABEL=\([^ :]*\).*/\2/p' /proc/cmdline | head -1)
    if [ -n "$label" ]; then
        mkdir -p "$MOUNT_POINT"
        for dev in /dev/disk/by-label/*; do
            [ "$(basename "$dev")" = "$label" ] || continue
            if mount -o ro "$dev" "$MOUNT_POINT" 2>/dev/null; then
                if have_payload "$MOUNT_POINT"; then PAYLOAD_SRC=$MOUNT_POINT; fi
            fi
            break
        done
    fi
fi

if [ -z "$PAYLOAD_SRC" ]; then
    printf 'my-fedora: install payload not found on media; cannot run classic-post.sh\n' >&2
    exit 1
fi

mkdir -p /mnt/sysimage/root/my-fedora-payload
cp -a "$PAYLOAD_SRC"/classic-post.sh "$PAYLOAD_SRC"/packages.sh \
      "$PAYLOAD_SRC"/system_files.tar.gz "$PAYLOAD_SRC"/driftwm-runtime.tar.gz \
      /mnt/sysimage/root/my-fedora-payload/

# Keep the exact kickstart and the repository lines that Anaconda used.
for dir in "$PAYLOAD_SRC" /run/install/isodir /mnt/install/isodir /run/install/repo /mnt/install/repo; do
    if [ -z "$KS_SRC" ]; then
        for ks in "$dir"/*.ks; do
            if [ -f "$ks" ]; then KS_SRC=$ks; break; fi
        done
    fi
done
if [ -n "$KS_SRC" ]; then
    cp -a "$KS_SRC" "$LOG_DIR/installer/payload/" || true
    awk '/^(url|repo) /' "$KS_SRC" > "$LOG_DIR/installer/repos.txt" || true
fi

# Network and repository diagnostics, written on the installed system.
{
    printf '== date\n'; date -u
    printf '\n== kernel cmdline\n'; cat /proc/cmdline
    printf '\n== addresses\n'; ip addr || true
    printf '\n== routes\n'; ip route || true
    printf '\n== resolv.conf\n'; cat /etc/resolv.conf || true
    printf '\n== resolvectl\n'; resolvectl status || true
    printf '\n== dl.fedoraproject.org lookup\n'; getent hosts dl.fedoraproject.org || true
    printf '\n== installer repositories\n'; cat "$LOG_DIR/installer/repos.txt" 2>/dev/null || true
    if [ -n "$KS_SRC" ]; then
        release_url=$(sed -n 's/^url --url="\(.*\)"$/\1/p' "$KS_SRC" | head -1)
        updates_url=$(sed -n 's/^repo --name="fedora-updates" --baseurl="\(.*\)"$/\1/p' "$KS_SRC" | head -1)
        if [ -n "$release_url" ]; then
            printf '\n== release repomd\n'
            curl -sS -o /dev/null -w '%{http_code}\n' --connect-timeout 10 --max-time 30 \
                "${release_url}repodata/repomd.xml" || true
        fi
        if [ -n "$updates_url" ]; then
            printf '\n== updates repomd\n'
            curl -sS -o /dev/null -w '%{http_code}\n' --connect-timeout 10 --max-time 30 \
                "${updates_url}repodata/repomd.xml" || true
        fi
    fi
} > "$LOG_DIR/installer/network.txt" 2>&1 || true

# Anaconda logs live in /tmp.  Copy the ones that matter for a failed install.
for log in anaconda.log packaging.log storage.log program.log dnf.log yum.log syslog ifcfg.log; do
    if [ -f "/tmp/$log" ]; then cp -a "/tmp/$log" "$LOG_DIR/installer/" || true; fi
done
if [ -d /tmp/pre-anaconda-logs ]; then
    cp -a /tmp/pre-anaconda-logs/. "$LOG_DIR/installer/pre/" || true
fi
if [ -f "$STAGE/diagnostics.txt" ]; then
    cp -a "$STAGE/diagnostics.txt" "$LOG_DIR/installer/payload/" || true
fi
if [ -f "$STAGE/status" ]; then
    cp -a "$STAGE/status" "$LOG_DIR/installer/payload/" || true
fi

printf 'my-fedora: payload copied from %s\n' "$PAYLOAD_SRC"
%end
EOF
}

write_post() {
    local variant=$1
    cat <<EOF
%post --interpreter=/bin/bash --erroronfail --log=/var/log/my-fedora-install/post.log
set -euo pipefail
bash /root/my-fedora-payload/classic-post.sh $variant
rm -rf /root/my-fedora-payload
%end
EOF
}

write_driftwm() {
    write_common "+ driftwm"
    cat <<'EOF'
%packages --retries=5 --timeout=60
@^custom-environment
@standard
@multimedia

    initial-setup
EOF
    write_packages DRIFTWM_ALL_PACKAGES
    cat <<'EOF'

%end

EOF
    write_pre
    printf '\n'
    write_post_nochroot
    printf '\n'
    write_post driftwm
}

write_gnome() {
    write_common "Workstation"
    cat <<'EOF'
%packages --retries=5 --timeout=60
@^workstation-product-environment
@multimedia
-power-profiles-daemon

    gnome-initial-setup
EOF
    write_packages GNOME_ALL_PACKAGES
    cat <<'EOF'

%end

EOF
    write_pre
    printf '\n'
    write_post_nochroot
    printf '\n'
    write_post gnome
}

case $VARIANT in
    driftwm) write_driftwm > "$OUT_DIR/driftwm.ks" ;;
    gnome) write_gnome > "$OUT_DIR/gnome.ks" ;;
    both)
        write_driftwm > "$OUT_DIR/driftwm.ks"
        write_gnome > "$OUT_DIR/gnome.ks"
        ;;
    *) echo "unknown variant: $VARIANT" >&2; exit 1 ;;
esac

echo "Kickstarts written to $OUT_DIR"
