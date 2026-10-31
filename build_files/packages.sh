#!/bin/bash
# Package lists and third-party sources shared by the atomic image
# (build_files/build.sh) and the classic kickstart installer
# (build_files/generate-kickstarts.sh, build_files/classic-post.sh).
#
# Rules:
#   - a package appears in exactly one category;
#   - categories are plain Fedora package names unless the section says otherwise;
#   - GNOME and DriftWM session packages never mix;
#   - tuned-ppd is the only power daemon: never add TLP, auto-cpufreq or a
#     second power-profiles-daemon.
# shellcheck disable=SC2034  # values are used by the scripts that source this file

### BASE: present in every edition, both desktops
BASE_PACKAGES=(
    flatpak                            # flatpak-preinstall.service
    dnf5-plugins                       # dnf5 copr, used while building/installing
    curl
    polkit
    NetworkManager-wifi NetworkManager-tui
    bluez                              # Bluetooth stack; GNOME and blueman use it
)

### HARDWARE: ThinkPad P14s Gen 2 AMD
HARDWARE_PACKAGES=(
    fwupd                              # BIOS/EC/fingerprint firmware via LVFS
    upower                             # battery information and charge threshold API
    fprintd fprintd-pam                # fingerprint: login, sudo, polkit
    pciutils usbutils                  # lspci/lsusb for thinkpad-diagnostics
    lm_sensors                         # hwmon/sensors temperatures
    iw rfkill                          # Wi-Fi power save and radio state
    nvme-cli smartmontools             # NVMe list and SMART (SMART read needs root)
)

### POWER: one power daemon only, driven through the PPD D-Bus interface
POWER_PACKAGES=(
    tuned-ppd
)

### DEVELOPMENT: terminal tooling and containers
DEVELOPMENT_PACKAGES=(
    git
    nodejs npm                         # DeepSeek Harness and terminal tooling
    podman-docker podman-compose       # docker / docker compose on rootless podman
)

### MULTIMEDIA: players and hardware decode checks
MULTIMEDIA_PACKAGES=(
    mpv imv
    libva-utils                        # vainfo, used by thinkpad-diagnostics
)

### OPTIONAL: conveniences and desktop applications
OPTIONAL_PACKAGES=(
    firefox
    nautilus file-roller 7zip
    qbittorrent
    grim slurp swappy                  # screenshots (ShareX replacement)
    btrfs-assistant snapper
    cups system-config-printer         # printing
    liberation-fonts-all google-carlito-fonts google-crosextra-caladea-fonts  # MS Office metric-compatible fonts
    jetbrains-mono-fonts-all           # monospace for VS Code and terminals
    hunspell-ru                        # Russian spell check (Firefox, GTK apps)
)

### GNOME only: the session itself comes from Silverblue
GNOME_PACKAGES=(
    gnome-shell-extension-appindicator gnome-shell-extension-dash-to-dock gnome-shell-extension-caffeine
    gnome-tweaks
)

### DriftWM only: runtime libs, login screen, portals and the shell around it
DRIFTWM_PACKAGES=(
    libseat libdisplay-info libinput mesa-libgbm libxkbcommon
    greetd tuigreet
    xwayland-satellite
    xdg-desktop-portal-gtk xdg-desktop-portal-wlr gnome-keyring
    foot fuzzel SwayNotificationCenter swaybg swayidle swaylock wlopm
    brightnessctl wireplumber pipewire-pulseaudio pavucontrol
    blueman
    lxqt-policykit
    google-noto-sans-fonts google-noto-emoji-fonts
    jq wl-clipboard libnotify          # used by the driftwm extras scripts
    playerctl cliphist wlsunset kanshi
)

### Packages that only exist in COPRs. Installed separately so the repo can be
### enabled for the build/install and disabled again afterwards.
DRIFTWM_COPRS=(errornointernet/quickshell erikreider/swayosd)
DRIFTWM_COPR_PACKAGES=(quickshell swayosd)

### Packages from third-party repositories that Anaconda must not touch
### directly: installed after RPM Fusion / the Microsoft VS Code key is set up.
THIRD_PARTY_PACKAGES=(
    code                               # VS Code, repo in /etc/yum.repos.d/vscode.repo
    unrar                              # RPM Fusion nonfree
)

COMMON_PACKAGES=(
    "${BASE_PACKAGES[@]}"
    "${HARDWARE_PACKAGES[@]}"
    "${POWER_PACKAGES[@]}"
    "${DEVELOPMENT_PACKAGES[@]}"
    "${MULTIMEDIA_PACKAGES[@]}"
    "${OPTIONAL_PACKAGES[@]}"
)

GNOME_ALL_PACKAGES=("${COMMON_PACKAGES[@]}" "${GNOME_PACKAGES[@]}")
DRIFTWM_ALL_PACKAGES=("${COMMON_PACKAGES[@]}" "${DRIFTWM_PACKAGES[@]}")

### Third-party binaries: pinned versions with SHA256 from the GitHub release
### assets (the API exposes "digest"). Update the three values together when a
### new release is wanted; builds fail instead of installing an unverified file.
PDFCRAFT_VERSION="v0.16.1"
PDFCRAFT_SHA256="b5d30dde0d5dea634af7a8f0a7bb1f81b75861ae7338c5b4c76a9b1da66ef2d3"
PDFCRAFT_RPM="pdfcraft-${PDFCRAFT_VERSION#v}-linux-x86_64.rpm"
PDFCRAFT_URL="https://github.com/storytold/pdfcraft/releases/download/${PDFCRAFT_VERSION}/${PDFCRAFT_RPM}"

HAPP_VERSION="4.6.1"
HAPP_SHA256="374d175138040abe38ad49cbb783029c21f129dd2ba58ca83823cb9adbaabefb"
HAPP_RPM="Happ.linux.x64.rpm"
HAPP_URL="https://github.com/Happ-proxy/happ-desktop/releases/download/${HAPP_VERSION}/${HAPP_RPM}"

# opencode is the terminal (TUI) program; the desktop RPM is not used.
OPENCODE_VERSION="v1.19.5"
OPENCODE_SHA256="588310a336fa3b9df36b3f0225b26f679d453efaad0cf3d66c3651ef3ec1647a"
OPENCODE_URL="https://github.com/anomalyco/opencode/releases/download/${OPENCODE_VERSION}/opencode-linux-x64.tar.gz"

# DeepSeek Harness web UI, started with `dsh`; npm verifies the registry
# integrity hash, the version pin keeps builds reproducible.
DEEPSEEK_HARNESS_VERSION="0.2.1-rc.5"
DEEPSEEK_HARNESS_PACKAGE="@deepseek-ai/dsh@${DEEPSEEK_HARNESS_VERSION}"

### Helpers used by both build paths

retry() {
    local attempts=${RETRY_ATTEMPTS:-3} delay=${RETRY_DELAY:-5} i
    for ((i = 1; i <= attempts; i++)); do
        "$@" && return 0
        if ((i < attempts)); then sleep $((delay * i)); fi
    done
    return 1
}

# Print "URL<TAB>SHA256" for every vendor RPM.
vendor_rpms() {
    printf '%s\t%s\n' "$PDFCRAFT_URL" "$PDFCRAFT_SHA256"
    printf '%s\t%s\n' "$HAPP_URL" "$HAPP_SHA256"
}

install_vendor_rpm() {
    local url=$1 sha=$2 dir file
    dir=$(mktemp -d)
    file="$dir/${url##*/}"
    retry curl -fL --retry 3 --retry-all-errors -o "$file" "$url"
    printf '%s  %s\n' "$sha" "$file" | sha256sum -c -
    dnf5 -y install "$file"
    rm -rf "$dir"
}

install_vendor_rpms() {
    local url sha
    while IFS=$'\t' read -r url sha; do
        install_vendor_rpm "$url" "$sha"
    done < <(vendor_rpms)
}

install_opencode() {
    local dir file
    dir=$(mktemp -d)
    file="$dir/opencode-linux-x64.tar.gz"
    retry curl -fL --retry 3 --retry-all-errors -o "$file" "$OPENCODE_URL"
    printf '%s  %s\n' "$OPENCODE_SHA256" "$file" | sha256sum -c -
    tar -xzf "$file" -C /usr/bin opencode
    chown root:root /usr/bin/opencode
    chmod 755 /usr/bin/opencode
    rm -rf "$dir"
}

install_dsh() {
    retry npm install -g --prefix /usr --cache /tmp/npm-cache "$DEEPSEEK_HARNESS_PACKAGE"
    rm -rf /tmp/npm-cache
}
