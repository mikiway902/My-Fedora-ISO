#!/bin/bash
# Runs inside the freshly installed classic system (Anaconda %post).
# Finishes what the kickstart package set cannot: COPR/vendor packages,
# opencode CLI, DeepSeek Harness and the system_files overlay.

set -euo pipefail

VARIANT=${1:?usage: classic-post.sh driftwm|gnome}
PAYLOAD=/root/my-fedora-payload

# package lists and URLs shared with the atomic build
# shellcheck disable=SC1091
source "$PAYLOAD/packages.sh"

### system_files from the repo (greetd, skel profiles, services, lists)
# The archive is made by a normal user, so do not restore its numeric owner:
# everything under / must stay owned by root.
tar -xzf "$PAYLOAD/system_files.tar.gz" --no-same-owner -C /

if [[ $VARIANT == driftwm ]]; then
    tar -xzf "$PAYLOAD/driftwm-runtime.tar.gz" -C /
else
    # driftwm-only files; GNOME has its own charge limit toggle and firmware updates
    rm -rf /etc/greetd /etc/skel/.config/kanshi /etc/skel/.config/foot \
        /usr/lib/tmpfiles.d/thinkpad-battery.conf /usr/lib/systemd/logind.conf.d/50-lid-ac.conf
fi

chmod +x /usr/libexec/my-fedora-*  # git on Windows drops the exec bit

# Fingerprint for login, sudo and polkit; with no enrolled finger PAM falls through to the password
authselect enable-feature with-fingerprint

systemctl set-default graphical.target
systemctl enable flatpak-preinstall.service grub-windows-entry.service
systemctl --global enable vscode-extensions.service

# Anaconda in kickstart mode does not create a user; let Initial Setup do it.
# If a user was created interactively, do not run the wizard again.
# GNOME uses gnome-initial-setup through GDM instead.
if [[ $VARIANT == driftwm ]] && \
   ! awk -F: '$3 >= 1000 && $3 < 60000 { found = 1 } END { exit !found }' /etc/passwd; then
    systemctl enable initial-setup.service
fi

### RPM Fusion (full codecs, unrar) and packages Anaconda did not install
# shellcheck disable=SC1091
. /etc/os-release
dnf5 -y install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${VERSION_ID}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${VERSION_ID}.noarch.rpm"

# Full Mesa codecs; the atomic images get these from negativo17
dnf5 -y install mesa-va-drivers-freeworld libva-utils
if rpm -q mesa-vulkan-drivers >/dev/null 2>&1; then
    dnf5 -y swap mesa-vulkan-drivers mesa-vulkan-drivers-freeworld --allowerasing
else
    dnf5 -y install mesa-vulkan-drivers-freeworld
fi

# code comes from the VS Code repo in system_files; unrar from RPM Fusion nonfree
dnf5 -y install "${THIRD_PARTY_PACKAGES[@]}"

# Full codec stack instead of Fedora's ffmpeg-free
if rpm -q ffmpeg-free >/dev/null 2>&1; then
    dnf5 -y swap ffmpeg-free ffmpeg --allowerasing
else
    dnf5 -y install ffmpeg
fi
dnf5 -y install gstreamer1-plugins-ugly

### Vendor RPMs (Happ, PdfCraft); /opt is a normal directory on classic Fedora
mapfile -t VENDOR_RPMS < <(vendor_rpm_urls)
dnf5 -y install "${VENDOR_RPMS[@]}"

### opencode CLI (terminal), not the desktop app
curl -fsSL "$OPENCODE_URL" | tar -xz -C /usr/bin opencode
chown root:root /usr/bin/opencode
chmod 755 /usr/bin/opencode

### DeepSeek Harness web UI, started with `dsh`
npm install -g --prefix /usr --cache /tmp/npm-cache "$DEEPSEEK_HARNESS_PACKAGE"
rm -rf /tmp/npm-cache

if [[ $VARIANT == driftwm ]]; then
    for copr in "${DRIFTWM_COPRS[@]}"; do dnf5 -y copr enable "$copr"; done
    dnf5 -y install "${DRIFTWM_COPR_PACKAGES[@]}"
    for copr in "${DRIFTWM_COPRS[@]}"; do dnf5 -y copr disable "$copr"; done

    # Seed new users with the upstream extras (dashboard, scripts, themes), then our config on top
    XDG_CONFIG_HOME=/etc/skel/.config sh /usr/share/driftwm/extras/install.sh
    cp /usr/share/my-fedora/driftwm-config.toml /etc/skel/.config/driftwm/config.toml

    systemctl enable greetd.service cups.socket
    systemctl --global enable fwupd-notify.timer
else
    glib-compile-schemas /usr/share/glib-2.0/schemas  # picks up zz1-my-fedora.gschema.override
    echo com.mattjakeman.ExtensionManager >> /usr/share/my-fedora/flatpaks
fi
