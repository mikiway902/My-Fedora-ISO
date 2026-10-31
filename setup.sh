#!/usr/bin/env bash
# Post-install for Fedora Workstation/KDE on ThinkPad P14s Gen 2 AMD. Not for Bluefin/Aurora.
set -euo pipefail

# Firmware: BIOS, EC, fingerprint reader via LVFS
sudo fwupdmgr refresh --force
sudo fwupdmgr update -y || true  # exits non-zero when nothing to update

# RPM Fusion
sudo dnf install -y \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

# Full codecs + H.264/HEVC hardware decode on Vega 8
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf install -y mesa-va-drivers-freeworld libva-utils
sudo dnf swap -y mesa-vulkan-drivers mesa-vulkan-drivers-freeworld

# Power daemons that fight tuned-ppd / power-profiles-daemon
sudo dnf remove -y tlp auto-cpufreq thermald 2>/dev/null || true

echo "amd_pstate: $(cat /sys/devices/system/cpu/amd_pstate/status 2>/dev/null || echo 'нет (acpi-cpufreq)')"
# tuned-ppd has no powerprofilesctl binary; read the PPD D-Bus property directly
busctl get-property net.hadess.PowerProfiles /net/hadess/PowerProfiles \
  net.hadess.PowerProfiles ActiveProfile 2>/dev/null |
  awk '{print "power profile: " $2}' | tr -d '"' || echo "power profile: недоступен"
vainfo 2>/dev/null | grep -E 'H264|HEVC' || echo "VA-API: H264/HEVC не найдены"
