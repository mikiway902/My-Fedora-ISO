#!/bin/bash
# Generate Anaconda kickstart files for the classic (non-atomic) install ISOs.
# Package lists come from packages.sh so atomic and classic stay in sync.

set -euo pipefail

OUT_DIR=${1:?usage: generate-kickstarts.sh OUT_DIR [driftwm|gnome|both]}
VARIANT=${2:-both}

# shellcheck disable=SC1091
source "$(dirname "$0")/packages.sh"

mkdir -p "$OUT_DIR"

write_packages() {
    local -n packages=$1
    printf '    %s\n' "${packages[@]}"
}

write_driftwm() {
    cat <<EOF
# Classic Fedora + driftwm, installed by Anaconda from Fedora Everything.
# Storage is intentionally left interactive: this laptop dual-boots Windows.

lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us,ru'
timezone Europe/Moscow --utc
selinux --enforcing
firewall --enabled --service=ssh
rootpw --lock

%packages
@^custom-environment
@standard
@multimedia

    initial-setup
EOF
    write_packages DRIFTWM_SESSION
    write_packages LAPTOP
    write_packages APPS
    cat <<'EOF'

%end

%post --nochroot --interpreter=/bin/bash --erroronfail
set -euxo pipefail
PAYLOAD_SRC=""
for d in /run/install/repo /mnt/install/repo /run/install/isodir; do
    if [ -f "$d/classic-post.sh" ]; then PAYLOAD_SRC=$d; break; fi
done
[ -n "$PAYLOAD_SRC" ] || { echo "my-fedora payload not found on install media"; exit 1; }
mkdir -p /mnt/sysimage/root/my-fedora-payload
cp -a "$PAYLOAD_SRC"/classic-post.sh "$PAYLOAD_SRC"/packages.sh \
      "$PAYLOAD_SRC"/system_files.tar.gz "$PAYLOAD_SRC"/driftwm-runtime.tar.gz \
      /mnt/sysimage/root/my-fedora-payload/
%end

%post --interpreter=/bin/bash --erroronfail
set -euxo pipefail
bash /root/my-fedora-payload/classic-post.sh driftwm
rm -rf /root/my-fedora-payload
%end
EOF
}

write_gnome() {
    cat <<EOF
# Classic Fedora Workstation, installed by Anaconda from Fedora Everything.
# Storage is intentionally left interactive: this laptop dual-boots Windows.

lang en_US.UTF-8
keyboard --vckeymap=us --xlayouts='us,ru'
timezone Europe/Moscow --utc
selinux --enforcing
firewall --enabled --service=ssh
rootpw --lock

%packages
@^workstation-product-environment
@multimedia
-power-profiles-daemon

    gnome-initial-setup
EOF
    write_packages GNOME_SESSION
    write_packages LAPTOP
    write_packages APPS
    cat <<'EOF'

%end

%post --nochroot --interpreter=/bin/bash --erroronfail
set -euxo pipefail
PAYLOAD_SRC=""
for d in /run/install/repo /mnt/install/repo /run/install/isodir; do
    if [ -f "$d/classic-post.sh" ]; then PAYLOAD_SRC=$d; break; fi
done
[ -n "$PAYLOAD_SRC" ] || { echo "my-fedora payload not found on install media"; exit 1; }
mkdir -p /mnt/sysimage/root/my-fedora-payload
cp -a "$PAYLOAD_SRC"/classic-post.sh "$PAYLOAD_SRC"/packages.sh \
      "$PAYLOAD_SRC"/system_files.tar.gz "$PAYLOAD_SRC"/driftwm-runtime.tar.gz \
      /mnt/sysimage/root/my-fedora-payload/
%end

%post --interpreter=/bin/bash --erroronfail
set -euxo pipefail
bash /root/my-fedora-payload/classic-post.sh gnome
rm -rf /root/my-fedora-payload
%end
EOF
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
