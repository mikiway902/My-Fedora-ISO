#!/bin/bash
# Runs inside the freshly installed classic system (Anaconda %post).
# Finishes what the kickstart package set cannot: COPR/vendor packages,
# opencode CLI, desktop development tools and the system_files overlay.
#
# Core steps (system_files, services, authselect) are fatal. Everything that
# needs a third-party server (RPM Fusion, Microsoft, COPR, GitHub, npm) is
# best-effort, except the required desktop-nvidia driver setup.

set -Eeuo pipefail

VARIANT=${1:?usage: classic-post.sh driftwm|gnome}
HARDWARE_PROFILE=${HARDWARE_PROFILE:-generic}
case "$HARDWARE_PROFILE:$VARIANT" in
    generic:driftwm|generic:gnome|desktop-nvidia:gnome) ;;
    *) echo "unsupported hardware profile/variant: $HARDWARE_PROFILE/$VARIANT" >&2; exit 1 ;;
esac
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

printf 'classic-post: variant=%s hardware_profile=%s started=%s\n' \
    "$VARIANT" "$HARDWARE_PROFILE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# dnf5 is the installed system's package manager in Fedora 45.  Its absence is
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
    rm -f /etc/dconf/db/local.d/10-desktop-profile
    rm -rf /etc/skel/.local/share/gnome-shell/extensions
else
    # driftwm-only files; GNOME has its own charge limit toggle and firmware updates
    rm -rf /etc/greetd /etc/skel/.config/kanshi /etc/skel/.config/foot \
        /usr/lib/systemd/logind.conf.d/50-lid-ac.conf
fi

chmod +x /usr/libexec/my-fedora-* /usr/bin/my-fedora-* /usr/bin/thinkpad-diagnostics

# Fingerprint for login, sudo and polkit; with no enrolled finger PAM falls through to the password
if [[ $HARDWARE_PROFILE == generic ]]; then
    authselect enable-feature with-fingerprint
fi

systemctl set-default graphical.target
systemctl enable flatpak-preinstall.service
systemctl --global enable vscode-extensions.service

# Classic Fedora reads /etc/grub.d/40_custom, not bootupd's custom.cfg.
# grub2-mkconfig needs /proc, /sys and /dev, which Anaconda has in the chroot.
if [[ $HARDWARE_PROFILE == generic ]]; then
    install -m 0755 /usr/share/my-fedora/grub-40_custom /etc/grub.d/40_custom
    run_optional "GRUB Windows entry" grub2-mkconfig -o /boot/grub2/grub.cfg
else
    # These are overlay files for the P14s, not desktop defaults.
    rm -f /etc/tuned/ppd.conf /usr/share/my-fedora/grub-40_custom \
        /usr/share/my-fedora/grub-custom.cfg \
        /usr/lib/systemd/system/grub-windows-entry.service
    rm -rf /etc/tuned/profiles/my-fedora-p14s-*
fi

# Anaconda in kickstart mode does not create a user; let Initial Setup do it.
# If a user was created interactively, do not run the wizard again.
# GNOME uses gnome-initial-setup through GDM instead.
if [[ $VARIANT == driftwm ]] && \
   ! awk -F: '$3 >= 1000 && $3 < 60000 { found = 1 } END { exit !found }' /etc/passwd; then
    systemctl enable initial-setup.service
fi

### RPM Fusion (full codecs, unrar) and packages Anaconda did not install
install_rpmfusion() {
    # shellcheck disable=SC1091
    . /etc/os-release
    dnf5 -y install \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${VERSION_ID}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${VERSION_ID}.noarch.rpm"
}

install_codecs() {
    install_rpmfusion
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

install_nvidia() {
    local kernels kernel module signer
    install_rpmfusion
    # Generate the machine-local key before NVIDIA RPM scriptlets can build modules.
    dnf5 -y install akmods mokutil kernel-devel-matched
    kmodgenca -a
    dnf5 -y install akmod-nvidia xorg-x11-drv-nvidia-cuda

    # uname -r is the installer's kernel, not the installed system's kernels.
    kernels=$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n')
    [[ -n $kernels ]] || { echo "ERROR: no installed kernels for NVIDIA" >&2; return 1; }
    for kernel in $kernels; do
        dnf5 -y install "kernel-devel-$kernel"
        akmods --force --rebuild --akmod nvidia --kernels "$kernel"
        depmod -a "$kernel"
        for module in nvidia nvidia_modeset nvidia_drm nvidia_uvm; do
            modinfo -k "$kernel" "$module" >/dev/null
            signer=$(modinfo -k "$kernel" -F signer "$module")
            [[ -n $signer ]] || {
                echo "ERROR: unsigned $module module for $kernel" >&2
                return 1
            }
        done
        # Only regenerate the boot image after the built modules were verified.
        dracut --force --kver "$kernel"
    done
}

if [[ $HARDWARE_PROFILE == desktop-nvidia ]]; then
    # Deliberately not run_optional: this hardware profile requires its driver.
    install_nvidia
    mkdir -p /usr/share/my-fedora
    cat > /usr/share/my-fedora/NVIDIA-SECURE-BOOT.txt <<'EOF'
NVIDIA / Secure Boot (desktop-nvidia)

The installer generated a local akmods signing key on this installed machine.
No private key was embedded in the ISO. Keep /etc/pki/akmods/private private.
Secure Boot has NOT been disabled and no MOK enrollment has been requested.

With Secure Boot enabled, NVIDIA cannot load until you manually enroll the key.
If the graphical login is unavailable, use Ctrl+Alt+F3 for a text login.
Run on the installed system:
  sudo mokutil --sb-state
  sudo mokutil --import /etc/pki/akmods/certs/public_key.der
Choose a temporary enrollment password, then reboot. In the firmware MOK
Manager choose Enroll MOK, Continue, Yes, and enter that password. Reboot again.
Verify:
  mokutil --test-key /etc/pki/akmods/certs/public_key.der
  modinfo -F signer nvidia
  nvidia-smi

If no MOK Manager appears, consult your firmware/shim documentation. Do not
disable Secure Boot as a workaround. Future kernel updates rebuild via akmods;
wait for builds to finish before rebooting. Logs: /var/cache/akmods/nvidia/.
More details: /usr/share/doc/akmods/README.secureboot
EOF
fi

# code comes from the VS Code repo in system_files; unrar from RPM Fusion nonfree
run_optional "VS Code" dnf5 -y install code
run_optional "unrar" dnf5 -y install unrar

### Vendor RPMs (Happ); /opt is a normal directory on classic Fedora
while IFS=$'\t' read -r url sha; do
    run_optional "vendor RPM ${url##*/}" install_vendor_rpm "$url" "$sha"
done < <(vendor_rpms)

### opencode CLI (terminal), not the desktop app
run_optional "opencode CLI" install_opencode

if [[ $VARIANT == gnome ]]; then
    run_optional "Additional desktop applications and development tools" \
        /usr/libexec/my-fedora-install-tools
fi

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
    for schemas in /etc/skel/.local/share/gnome-shell/extensions/*/schemas; do
        [[ ! -d $schemas ]] || glib-compile-schemas --strict "$schemas"
    done
    dconf update
fi

if [[ -s $WARNINGS ]]; then
    printf 'classic-post: finished with warnings; see %s\n' "$WARNINGS"
else
    printf 'classic-post: finished without warnings\n'
fi
printf 'completed=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$LOG_DIR/completed"
