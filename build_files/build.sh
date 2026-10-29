#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### driftwm session: runtime libs, login screen, portals, shell around it (gnome image has all this from Silverblue)
SESSION=()
[[ $VARIANT == driftwm ]] && SESSION=(
    libseat libdisplay-info libinput mesa-libgbm libxkbcommon
    greetd tuigreet
    xwayland-satellite
    xdg-desktop-portal-gtk xdg-desktop-portal-wlr gnome-keyring
    foot fuzzel SwayNotificationCenter swaybg swayidle swaylock wlopm
    brightnessctl wireplumber pipewire-pulseaudio pavucontrol
    NetworkManager-wifi NetworkManager-tui bluez blueman
    polkit lxqt-policykit
    google-noto-sans-fonts google-noto-emoji-fonts
    quickshell swayosd                 # dashboard and volume/brightness OSD, from COPRs below
    jq wl-clipboard libnotify          # used by the driftwm extras scripts
    playerctl cliphist wlsunset kanshi
    cups system-config-printer         # printing, Silverblue already has it
)
DRIFTWM_COPRS=(errornointernet/quickshell erikreider/swayosd)

### ThinkPad P14s Gen 2 AMD
LAPTOP=(
    tuned-ppd          # power profiles; never add TLP/auto-cpufreq next to it
    fwupd              # BIOS/EC/fingerprint firmware via LVFS
    fprintd fprintd-pam
    upower             # battery charge threshold (thinkpad_acpi)
)

### Preinstalled apps from repos. GUI apps that update often go to system_files/usr/share/my-fedora/flatpaks
APPS=(
    firefox
    nautilus file-roller 7zip unrar
    mpv imv
    qbittorrent
    grim slurp swappy                  # screenshots (ShareX replacement)
    code                               # VS Code, repo in /etc/yum.repos.d/vscode.repo
    git
    podman-docker podman-compose       # `docker` / `docker compose` on top of rootless podman
    btrfs-assistant snapper
    liberation-fonts-all google-carlito-fonts google-crosextra-caladea-fonts  # metric-compatible MS Office fonts
    jetbrains-mono-fonts-all           # monospace for VS Code and terminals
    hunspell-ru                        # Russian spell check (hunspell users: Firefox, GTK apps)
)

### GNOME only: tray icons, dock, keep-awake toggle, Tweaks
[[ $VARIANT == gnome ]] && SESSION=(
    gnome-shell-extension-appindicator gnome-shell-extension-dash-to-dock gnome-shell-extension-caffeine
    gnome-tweaks
)

### Apps from vendor RPMs, always the latest release at build time
latest_tag() { curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's#.*/tag/##'; }
PDFCRAFT=$(latest_tag storytold/pdfcraft)
RUDESKTOP=$(curl -fsSL https://rudesktop.ru/downloads/ | grep -oE 'rudesktop-[0-9.]+-x86_64\.rpm' | head -1)
VENDOR_RPMS=(
    "https://github.com/storytold/pdfcraft/releases/download/${PDFCRAFT}/pdfcraft-${PDFCRAFT#v}-linux-x86_64.rpm"
    "https://github.com/Happ-proxy/happ-desktop/releases/latest/download/Happ.linux.x64.rpm"
    "https://github.com/anomalyco/opencode/releases/latest/download/opencode-desktop-linux-x86_64.rpm"
    "https://storage.rudesktop.ru/download/${RUDESKTOP}"  # built for RED OS, not Fedora
)

if [[ $VARIANT == driftwm ]]; then
    for copr in "${DRIFTWM_COPRS[@]}"; do dnf5 -y copr enable "$copr"; done
fi

dnf5 -y install "${SESSION[@]}" "${LAPTOP[@]}" "${APPS[@]}" "${VENDOR_RPMS[@]}"

if [[ $VARIANT == driftwm ]]; then
    # Disable COPRs so they don't end up enabled on the final image
    for copr in "${DRIFTWM_COPRS[@]}"; do dnf5 -y copr disable "$copr"; done
fi

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
