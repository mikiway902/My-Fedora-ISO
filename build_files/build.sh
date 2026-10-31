#!/bin/bash

set -euxo pipefail

# Package lists live in packages.sh so the classic kickstart installer can use them too.
# shellcheck disable=SC1091
source /ctx/packages.sh

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Per-variant package sets (GNOME's session and desktop come from Silverblue)
case $VARIANT in
    driftwm) SESSION=("${DRIFTWM_ALL_PACKAGES[@]}") ;;
    gnome) SESSION=("${GNOME_ALL_PACKAGES[@]}") ;;
    *)
        echo "unknown VARIANT: $VARIANT" >&2
        exit 1
        ;;
esac

if [[ $VARIANT == driftwm ]]; then
    for copr in "${DRIFTWM_COPRS[@]}"; do dnf5 -y copr enable "$copr"; done
fi

dnf5 -y install "${SESSION[@]}" "${THIRD_PARTY_PACKAGES[@]}"
install_vendor_rpms

if [[ $VARIANT == driftwm ]]; then
    dnf5 -y install "${DRIFTWM_COPR_PACKAGES[@]}"

    # Disable COPRs so they don't end up enabled on the final image
    for copr in "${DRIFTWM_COPRS[@]}"; do dnf5 -y copr disable "$copr"; done
fi

# tuned-ppd ships /etc/tuned/ppd.conf as %config(noreplace); re-copy our PPD
# mapping after the package install so it always wins. Profiles live in /etc,
# so the stock ones stay untouched.
install -Dm644 /ctx/system_files/etc/tuned/ppd.conf /etc/tuned/ppd.conf
cp -a /ctx/system_files/etc/tuned/profiles/. /etc/tuned/profiles/

# opencode CLI (terminal), not the desktop app. install_opencode verifies the
# pinned SHA256; /usr, not /usr/local, is part of the bootc image.
install_opencode

# DeepSeek Harness web UI, started with `dsh`
install_dsh

# git on Windows drops the exec bit; keep the helpers executable everywhere
chmod +x /usr/libexec/my-fedora-* /usr/bin/my-fedora-* /usr/bin/thinkpad-diagnostics

# Fingerprint for login, sudo and polkit; with no enrolled finger PAM falls through to the password
authselect enable-feature with-fingerprint

systemctl enable flatpak-preinstall.service grub-windows-entry.service
systemctl --global enable vscode-extensions.service

if [[ $VARIANT == driftwm ]]; then
    # Seed new users with the upstream extras (dashboard, scripts, themes), then our config on top
    XDG_CONFIG_HOME=/etc/skel/.config sh /usr/share/driftwm/extras/install.sh
    cp /usr/share/my-fedora/driftwm-config.toml /etc/skel/.config/driftwm/config.toml

    systemctl enable greetd.service cups.socket
    systemctl enable my-fedora-battery.service
    systemctl --global enable fwupd-notify.timer
    systemctl set-default graphical.target
else
    # driftwm-only files from system_files; GNOME manages the charge limit in
    # Settings and its own firmware notifications through GNOME Software
    rm -rf /etc/greetd /etc/skel/.config/kanshi /etc/skel/.config/foot \
        /usr/lib/systemd/logind.conf.d/50-lid-ac.conf
    glib-compile-schemas /usr/share/glib-2.0/schemas  # picks up zz1-my-fedora.gschema.override
    echo com.mattjakeman.ExtensionManager >> /usr/share/my-fedora/flatpaks
fi

# dnf and selinux-policy leave transient state in /run; it is not part of the
# image and only makes `bootc container lint` warn.
rm -rf /run/dnf /run/selinux-policy /run/tuned
