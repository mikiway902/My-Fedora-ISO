#!/bin/bash

set -ouex pipefail

# Package lists live in packages.sh so the classic kickstart installer can use them too
# shellcheck disable=SC1091
source /ctx/packages.sh

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Per-variant package sets (GNOME's session and desktop come from Silverblue)
SESSION=()
[[ $VARIANT == driftwm ]] && SESSION=("${DRIFTWM_SESSION[@]}")
[[ $VARIANT == gnome ]] && SESSION=("${GNOME_SESSION[@]}")

if [[ $VARIANT == driftwm ]]; then
    for copr in "${DRIFTWM_COPRS[@]}"; do dnf5 -y copr enable "$copr"; done
fi

VENDOR_RPMS=()
while IFS= read -r url; do VENDOR_RPMS+=("$url"); done < <(vendor_rpm_urls)

dnf5 -y install "${SESSION[@]}" "${LAPTOP[@]}" "${APPS[@]}" "${THIRD_PARTY_PACKAGES[@]}" "${VENDOR_RPMS[@]}"

if [[ $VARIANT == driftwm ]]; then
    dnf5 -y install "${DRIFTWM_COPR_PACKAGES[@]}"

    # Disable COPRs so they don't end up enabled on the final image
    for copr in "${DRIFTWM_COPRS[@]}"; do dnf5 -y copr disable "$copr"; done
fi

# opencode CLI (terminal), not the desktop app.
# /usr, not /usr/local: on bootc /usr/local is a symlink to /var and is not part of the image.
curl -fsSL "${OPENCODE_URL}" | tar -xz -C /usr/bin opencode
chown root:root /usr/bin/opencode
chmod 755 /usr/bin/opencode

# DeepSeek Harness web UI, started with `dsh`
npm install -g --prefix /usr --cache /tmp/npm-cache "${DEEPSEEK_HARNESS_PACKAGE}"
rm -rf /tmp/npm-cache

chmod +x /usr/libexec/my-fedora-*  # git on Windows drops the exec bit

# Fingerprint for login, sudo and polkit; with no enrolled finger PAM falls through to the password
authselect enable-feature with-fingerprint

systemctl enable flatpak-preinstall.service grub-windows-entry.service
systemctl --global enable vscode-extensions.service

if [[ $VARIANT == driftwm ]]; then
    # Seed new users with the upstream extras (dashboard, scripts, themes), then our config on top
    XDG_CONFIG_HOME=/etc/skel/.config sh /usr/share/driftwm/extras/install.sh
    cp /usr/share/my-fedora/driftwm-config.toml /etc/skel/.config/driftwm/config.toml

    systemctl enable greetd.service cups.socket
    systemctl --global enable fwupd-notify.timer
    systemctl set-default graphical.target
else
    # driftwm-only files from system_files; GNOME has its own charge limit toggle and firmware updates
    rm -rf /etc/greetd /etc/skel/.config/kanshi /etc/skel/.config/foot \
        /usr/lib/tmpfiles.d/thinkpad-battery.conf /usr/lib/systemd/logind.conf.d/50-lid-ac.conf
    glib-compile-schemas /usr/share/glib-2.0/schemas  # picks up zz1-my-fedora.gschema.override
    echo com.mattjakeman.ExtensionManager >> /usr/share/my-fedora/flatpaks
fi
