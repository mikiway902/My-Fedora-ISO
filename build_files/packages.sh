#!/bin/bash
# Package lists shared by the atomic image (build.sh) and the classic
# kickstart installer (generate-kickstarts.sh). Keep them as plain Fedora
# package names so dnf can resolve them in both build paths.
# shellcheck disable=SC2034  # values are used by the scripts that source this file

### driftwm session: runtime libs, login screen, portals, shell around it
DRIFTWM_SESSION=(
    libseat libdisplay-info libinput mesa-libgbm libxkbcommon
    greetd tuigreet
    xwayland-satellite
    xdg-desktop-portal-gtk xdg-desktop-portal-wlr gnome-keyring
    foot fuzzel SwayNotificationCenter swaybg swayidle swaylock wlopm
    brightnessctl wireplumber pipewire-pulseaudio pavucontrol
    NetworkManager-wifi NetworkManager-tui bluez blueman
    polkit lxqt-policykit
    google-noto-sans-fonts google-noto-emoji-fonts
    jq wl-clipboard libnotify          # used by the driftwm extras scripts
    playerctl cliphist wlsunset kanshi
    cups system-config-printer         # printing
    flatpak                            # used by flatpak-preinstall.service
)

# Packages that only exist in COPRs. Installed separately so the repo can be
# enabled for the install and disabled again afterwards.
DRIFTWM_COPRS=(errornointernet/quickshell erikreider/swayosd)
DRIFTWM_COPR_PACKAGES=(quickshell swayosd)

### GNOME only: tray icons, dock, keep-awake toggle, Tweaks
GNOME_SESSION=(
    gnome-shell-extension-appindicator gnome-shell-extension-dash-to-dock gnome-shell-extension-caffeine
    gnome-tweaks
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
    nautilus file-roller 7zip
    mpv imv
    qbittorrent
    grim slurp swappy                  # screenshots (ShareX replacement)
    git curl
    libva-utils                        # vainfo, used in the laptop checks
    podman-docker podman-compose       # `docker` / `docker compose` on top of rootless podman
    btrfs-assistant snapper
    liberation-fonts-all google-carlito-fonts google-crosextra-caladea-fonts  # metric-compatible MS Office fonts
    jetbrains-mono-fonts-all           # monospace for VS Code and terminals
    hunspell-ru                        # Russian spell check (hunspell users: Firefox, GTK apps)
    nodejs npm                         # DeepSeek Harness and other terminal tooling
    dnf5-plugins                       # `dnf5 copr` for COPR packages
)

# Need repos that Anaconda should not touch directly: installed in %post after
# enabling RPM Fusion / importing the Microsoft VS Code key.
THIRD_PARTY_PACKAGES=(
    code                               # VS Code, repo in /etc/yum.repos.d/vscode.repo
    unrar                              # RPM Fusion nonfree
)

### Apps from vendor RPMs, always the latest release at build time
latest_tag() { curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's#.*/tag/##'; }

vendor_rpm_urls() {
    local pdfcraft
    pdfcraft=$(latest_tag storytold/pdfcraft)
    printf '%s\n' \
        "https://github.com/storytold/pdfcraft/releases/download/${pdfcraft}/pdfcraft-${pdfcraft#v}-linux-x86_64.rpm" \
        "https://github.com/Happ-proxy/happ-desktop/releases/latest/download/Happ.linux.x64.rpm"
}

# opencode is a terminal (TUI) program in this image; the desktop RPM is not used.
OPENCODE_URL="https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-x64.tar.gz"
DEEPSEEK_HARNESS_PACKAGE="@deepseek-ai/dsh"
