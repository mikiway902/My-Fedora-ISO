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
    foot fuzzel SwayNotificationCenter swaybg swayidle swaylock
    brightnessctl wireplumber pipewire-pulseaudio pavucontrol
    NetworkManager-wifi NetworkManager-tui bluez blueman
    polkit lxqt-policykit
    google-noto-sans-fonts google-noto-emoji-fonts
)

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

dnf5 -y install "${SESSION[@]}" "${LAPTOP[@]}" "${APPS[@]}" "${VENDOR_RPMS[@]}"

chmod +x /usr/libexec/my-fedora-preinstall  # git on Windows drops the exec bit

systemctl enable flatpak-preinstall.service grub-windows-entry.service
systemctl --global enable vscode-extensions.service

if [[ $VARIANT == driftwm ]]; then
    systemctl enable greetd.service
    systemctl set-default graphical.target
else
    rm -rf /etc/greetd /etc/skel/.config/driftwm  # driftwm-only files from system_files
fi
