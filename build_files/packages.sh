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
    nodejs22 nodejs22-npm               # match the laptop's Node.js major
    gcc-c++ gdb java-25-openjdk-devel
    python3-pip python3-numpy python3-pandas python3-matplotlib python3-ipykernel
    binwalk radare2 rizin
    jq rsync unzip zip tree
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
    hunspell-ru langpacks-ru            # Russian locale and spell check
)

### GNOME only: the session itself comes from Silverblue
GNOME_PACKAGES=(
    gnome-shell-extension-appindicator gnome-shell-extension-dash-to-dock gnome-shell-extension-caffeine
    gnome-tweaks
    gnome-boxes gnome-connections gnome-browser-connector mediawriter
    gnome-weather gnome-clocks gnome-system-monitor
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
    wl-clipboard libnotify             # used by the driftwm extras scripts
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

### Third-party binaries: pinned versions with SHA256 from the release
### assets. Update the three values together when a
### new release is wanted; builds fail instead of installing an unverified file.
HAPP_VERSION="4.6.1"
HAPP_SHA256="374d175138040abe38ad49cbb783029c21f129dd2ba58ca83823cb9adbaabefb"
HAPP_RPM="Happ.linux.x64.rpm"
HAPP_URL="https://github.com/Happ-proxy/happ-desktop/releases/download/${HAPP_VERSION}/${HAPP_RPM}"

# opencode is the terminal (TUI) program; the desktop RPM is not used.
OPENCODE_VERSION="2.3.0"
OPENCODE_SHA256="fc0f81522aceeabac47693d88389efa2bc517ce74c2c38fd6967819fcc6e4d3b"
OPENCODE_URL="https://opencode.ai/files/bin/${OPENCODE_VERSION}/opencode-linux-x64.tar.gz"

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
