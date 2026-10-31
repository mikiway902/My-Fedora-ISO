#!/bin/bash
# Runs inside the freshly installed classic system (Anaconda %post).
# Finishes what the kickstart package set cannot: COPR/vendor packages,
# opencode CLI, DeepSeek Harness and the system_files overlay.
#
# Core steps (system_files, services, authselect) are fatal. Everything that
# needs a third-party server (RPM Fusion, Microsoft, COPR, GitHub, npm) is
# best-effort: a mirror outage must not leave an unbootable installation.

set -euo pipefail

VARIANT=${1:?usage: classic-post.sh driftwm|gnome}
PAYLOAD=/root/my-fedora-payload
LOG_DIR=/var/log/my-fedora-install
LOG="$LOG_DIR/classic-post.log"
WARNINGS="$LOG_DIR/warnings.log"
FAILURES="$LOG_DIR/failures.log"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG") 2>&1

on_error() {
    local rc=$?
    printf 'FAILED: classic-post.sh line %s (exit %s): %s\n' \
        "$LINENO" "$rc" "${BASH_COMMAND:-unknown}" | tee -a "$FAILURES" >&2
}
trap on_error ERR

printf 'classic-post: variant=%s started=%s\n' "$VARIANT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# dnf5 is the installed system's package manager in Fedora 44.  Its absence is
# a fatal post-install problem; third-party network failures below are not.
if ! command -v dnf5 >/dev/null 2>&1; then
    printf 'ERROR: dnf5 is not available in the installed system\n' >&2
    exit 1
fi

# package lists and pinned third-party URLs shared with the atomic build
# shellcheck disable=SC1091
source "$PAYLOAD/packages.sh"

# Retry three times, then report and keep going.
run_optional() {
    local description=$1
    shift
    if retry "$@"; then
        return 0
    fi
    printf 'WARNING: %s failed; continuing without it\n' "$description" \
        | tee -a "$WARNINGS" >&2
    return 0
}

log_environment() {
    # shellcheck disable=SC1091
    . /etc/os-release
    local arch repo_url
    arch=$(uname -m)
    repo_url="https://dl.fedoraproject.org/pub/fedora/linux/releases/${VERSION_ID}/Everything/${arch}/os/repodata/repomd.xml"
    {
        printf '== date\n'; date -u
        printf '\n== os-release\n'; cat /etc/os-release
        printf '\n== dnf5 version\n'; dnf5 --version || true
        printf '\n== dnf5 package\n'; rpm -q dnf5 || true
        printf '\n== repositories\n'; timeout 60 dnf5 repolist --all || true
        printf '\n== addresses\n'; ip addr || true
        printf '\n== routes\n'; ip route || true
        printf '\n== resolv.conf\n'; cat /etc/resolv.conf || true
        printf '\n== resolvectl\n'; resolvectl status || true
        printf '\n== dl.fedoraproject.org lookup\n'; getent hosts dl.fedoraproject.org || true
        printf '\n== release repomd\n'
        curl -sS -o /dev/null -w '%{http_code}\n' --connect-timeout 10 --max-time 30 \
            "$repo_url" || true
    } > "$LOG_DIR/system.txt" 2>&1 || true
}

log_environment

### system_files from the repo (greetd, skel profiles, services, lists)
# The archive is made by a normal user, so do not restore its numeric owner:
# everything under / must stay owned by root.
tar -xzf "$PAYLOAD/system_files.tar.gz" --no-same-owner -C /

if [[ $VARIANT == driftwm ]]; then
    tar -xzf "$PAYLOAD/driftwm-runtime.tar.gz" -C /
else
    # driftwm-only files; GNOME has its own charge limit toggle and firmware updates
    rm -rf /etc/greetd /etc/skel/.config/kanshi /etc/skel/.config/foot \
        /usr/lib/systemd/logind.conf.d/50-lid-ac.conf
fi

chmod +x /usr/libexec/my-fedora-* /usr/bin/my-fedora-* /usr/bin/thinkpad-diagnostics

# Fingerprint for login, sudo and polkit; with no enrolled finger PAM falls through to the password
authselect enable-feature with-fingerprint

systemctl set-default graphical.target
systemctl enable flatpak-preinstall.service
systemctl --global enable vscode-extensions.service

# Classic Fedora reads /etc/grub.d/40_custom, not bootupd's custom.cfg.
# grub2-mkconfig needs /proc, /sys and /dev, which Anaconda has in the chroot.
install -m 0755 /usr/share/my-fedora/grub-40_custom /etc/grub.d/40_custom
run_optional "GRUB Windows entry" grub2-mkconfig -o /boot/grub2/grub.cfg

# Anaconda in kickstart mode does not create a user; let Initial Setup do it.
# If a user was created interactively, do not run the wizard again.
# GNOME uses gnome-initial-setup through GDM instead.
if [[ $VARIANT == driftwm ]] && \
   ! awk -F: '$3 >= 1000 && $3 < 60000 { found = 1 } END { exit !found }' /etc/passwd; then
    systemctl enable initial-setup.service
fi

### RPM Fusion (full codecs, unrar) and packages Anaconda did not install
install_codecs() {
    # shellcheck disable=SC1091
    . /etc/os-release
    dnf5 -y install \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${VERSION_ID}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${VERSION_ID}.noarch.rpm"

    # Full Mesa codecs; the atomic images get these from negativo17
    dnf5 -y install mesa-va-drivers-freeworld
    if rpm -q mesa-vulkan-drivers >/dev/null 2>&1; then
        dnf5 -y swap mesa-vulkan-drivers mesa-vulkan-drivers-freeworld --allowerasing
    else
        dnf5 -y install mesa-vulkan-drivers-freeworld
    fi

    # Full codec stack instead of Fedora's ffmpeg-free
    if rpm -q ffmpeg-free >/dev/null 2>&1; then
        dnf5 -y swap ffmpeg-free ffmpeg --allowerasing
    else
        dnf5 -y install ffmpeg
    fi
    dnf5 -y install gstreamer1-plugins-ugly
}
run_optional "RPM Fusion and codecs" install_codecs

# code comes from the VS Code repo in system_files; unrar from RPM Fusion nonfree
run_optional "VS Code" dnf5 -y install code
run_optional "unrar" dnf5 -y install unrar

### Vendor RPMs (Happ, PdfCraft); /opt is a normal directory on classic Fedora
while IFS=$'\t' read -r url sha; do
    run_optional "vendor RPM ${url##*/}" install_vendor_rpm "$url" "$sha"
done < <(vendor_rpms)

### opencode CLI (terminal), not the desktop app
run_optional "opencode CLI" install_opencode

### DeepSeek Harness web UI, started with `dsh`
run_optional "DeepSeek Harness" install_dsh

if [[ $VARIANT == driftwm ]]; then
    for copr in "${DRIFTWM_COPRS[@]}"; do
        run_optional "COPR ${copr}" dnf5 -y copr enable "$copr"
    done
    for package in "${DRIFTWM_COPR_PACKAGES[@]}"; do
        run_optional "COPR package ${package}" dnf5 -y install "$package"
    done
    for copr in "${DRIFTWM_COPRS[@]}"; do
        dnf5 -y copr disable "$copr" >/dev/null 2>&1 || true
    done

    # Seed new users with the upstream extras (dashboard, scripts, themes), then our config on top
    XDG_CONFIG_HOME=/etc/skel/.config sh /usr/share/driftwm/extras/install.sh
    cp /usr/share/my-fedora/driftwm-config.toml /etc/skel/.config/driftwm/config.toml

    systemctl enable greetd.service cups.socket
    systemctl enable my-fedora-battery.service
    systemctl --global enable fwupd-notify.timer
else
    glib-compile-schemas /usr/share/glib-2.0/schemas  # picks up zz1-my-fedora.gschema.override
    echo com.mattjakeman.ExtensionManager >> /usr/share/my-fedora/flatpaks
fi

if [[ -s $WARNINGS ]]; then
    printf 'classic-post: finished with warnings; see %s\n' "$WARNINGS"
else
    printf 'classic-post: finished without warnings\n'
fi
printf 'completed=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$LOG_DIR/completed"
