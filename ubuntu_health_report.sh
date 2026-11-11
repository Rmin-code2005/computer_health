#!/usr/bin/env bash
# Ubuntu Hardware & Update Health Report
# Read-only with respect to installed packages/firmware.
# It refreshes APT package indexes, but does NOT install updates.

set -u
export LC_ALL=C

STAMP="$(date +%Y%m%d_%H%M%S)"
REPORT="${HOME}/ubuntu-health-report-${STAMP}.txt"
mkdir -p "$(dirname "$REPORT")"
touch "$REPORT"
exec > >(tee "$REPORT") 2>&1

section() {
    printf '\n\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

have() { command -v "$1" >/dev/null 2>&1; }

run_if_available() {
    local cmd="$1"; shift
    if have "$cmd"; then
        "$cmd" "$@" 2>&1 || true
    else
        echo "$cmd is not installed."
    fi
}

section "UBUNTU SYSTEM HEALTH REPORT"
echo "Generated: $(date -Is)"
echo "Report: $REPORT"
echo "User: ${USER:-unknown}"
echo

section "1. OPERATING SYSTEM"
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    echo "Distribution: ${PRETTY_NAME:-unknown}"
fi
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
echo "Last boot: $(uptime -s 2>/dev/null || echo unavailable)"

section "2. CPU"
if have lscpu; then
    lscpu | grep -E '^(Architecture|CPU\(s\)|On-line CPU|Thread|Core|Socket|Model name|Vendor ID|CPU max MHz|CPU min MHz):' || lscpu
else
    grep -m1 'model name' /proc/cpuinfo 2>/dev/null || true
fi
echo
echo "Load average:"
cat /proc/loadavg 2>/dev/null || true
echo
echo "CPU frequency (when exposed by the kernel):"
for f in /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq \
         /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq; do
    if [[ -r "$f" ]]; then
        printf '%s: %s MHz\n' "$(basename "$f")" "$(( $(cat "$f") / 1000 ))"
    fi
done

section "3. CPU / SYSTEM TEMPERATURES"
if have sensors; then
    sensors 2>&1 || true
else
    echo "The 'sensors' command is unavailable. Install with: sudo apt install lm-sensors"
    echo "Thermal-zone readings exposed by the kernel:"
    found=0
    for z in /sys/class/thermal/thermal_zone*; do
        [[ -r "$z/temp" ]] || continue
        found=1
        temp="$(cat "$z/temp" 2>/dev/null || echo '')"
        [[ "$temp" =~ ^[0-9]+$ ]] || continue
        printf '%s (%s): %.1f C\n' "$(basename "$z")" \
            "$(cat "$z/type" 2>/dev/null || echo unknown)" \
            "$(awk "BEGIN {print $temp/1000}")"
    done
    [[ "$found" -eq 1 ]] || echo "No readable thermal zones found."
fi

section "4. RAM AND SWAP"
free -h 2>&1 || true
echo
grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|Dirty|HardwareCorrupted):' /proc/meminfo 2>/dev/null || true
echo
if have vmstat; then
    vmstat -s 2>&1 | head -25
fi
echo
echo "ECC / EDAC status (if supported):"
if [[ -d /sys/devices/system/edac/mc ]]; then
    find /sys/devices/system/edac/mc -maxdepth 4 -type f \
        \( -name '*ce_count' -o -name '*ue_count' \) -print -exec cat {} \; 2>/dev/null || true
else
    echo "No EDAC memory-controller counters exposed. This does NOT prove RAM is error-free."
fi
if have ras-mc-ctl; then
    echo
    ras-mc-ctl --summary 2>&1 || true
fi

section "5. STORAGE DEVICES"
if have lsblk; then
    lsblk -e7 -o NAME,PATH,TYPE,SIZE,ROTA,TRAN,MODEL,SERIAL,FSTYPE,MOUNTPOINTS 2>&1 || \
        lsblk -o NAME,TYPE,SIZE,MODEL,MOUNTPOINT
else
    echo "lsblk unavailable."
fi
echo
echo "Filesystem space:"
df -hT -x tmpfs -x devtmpfs 2>&1 || true
echo
echo "Inodes:"
df -ih -x tmpfs -x devtmpfs 2>&1 || true

section "6. DISK SMART HEALTH"
if ! have smartctl; then
    echo "smartctl is not installed. Install with: sudo apt install smartmontools"
else
    mapfile -t DISKS < <(lsblk -dnpo NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}')
    if [[ "${#DISKS[@]}" -eq 0 ]]; then
        echo "No disk devices detected by lsblk."
    else
        for disk in "${DISKS[@]}"; do
            echo
            echo "----- $disk -----"
            smartctl -H "$disk" 2>&1 || true
            echo
            smartctl -A "$disk" 2>&1 || smartctl -x "$disk" 2>&1 || true
        done
    fi
fi

section "7. NVME DETAILS"
if have nvme; then
    nvme list 2>&1 || true
    while read -r dev; do
        [[ -n "$dev" ]] || continue
        echo
        echo "----- NVMe SMART: $dev -----"
        nvme smart-log "$dev" 2>&1 || true
    done < <(nvme list 2>/dev/null | awk '/^\/dev\/nvme[0-9]+n[0-9]+/ {print $1}')
else
    echo "nvme-cli is not installed. Install with: sudo apt install nvme-cli"
fi

section "8. GPU AND GRAPHICS DRIVER"
if have lspci; then
    lspci -nnk 2>/dev/null | grep -A4 -Ei 'VGA compatible controller|3D controller|Display controller' || true
fi
if have nvidia-smi; then
    echo
    nvidia-smi 2>&1 || true
else
    echo "nvidia-smi unavailable (NVIDIA driver may not be installed, or this system may not use NVIDIA)."
fi

section "9. HARDWARE / KERNEL ERRORS SINCE BOOT"
if have journalctl; then
    journalctl -k -b -p err --no-pager -n 100 2>&1 || true
    echo
    echo "Filtered hardware-related kernel messages:"
    journalctl -k -b --no-pager 2>/dev/null |
        grep -Ei 'hardware error|mce:|machine check|edac|uncorrected|I/O error|nvme.*(error|critical)|ata[0-9].*error|thermal.*(critical|thrott)' |
        tail -100 || echo "No matching messages found in the current boot journal."
else
    echo "journalctl unavailable."
fi

section "10. APT PACKAGE UPDATES"
if have apt-get; then
    echo "Refreshing package indexes (this does not install or upgrade packages)..."
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        apt-get update 2>&1 || echo "WARNING: apt-get update encountered errors."
    elif have sudo && sudo -n true 2>/dev/null; then
        sudo apt-get update 2>&1 || echo "WARNING: apt-get update encountered errors."
    elif have sudo; then
        echo "Administrator permission is needed to refresh APT indexes."
        sudo apt-get update 2>&1 || echo "WARNING: apt-get update encountered errors."
    else
        echo "Cannot refresh APT indexes without sudo. Showing cached information."
    fi
    echo
    echo "Packages that can be upgraded:"
    apt list --upgradable 2>/dev/null || true
    echo
    echo "Upgrade simulation (does NOT install anything):"
    if have apt-get; then
        apt-get -s full-upgrade 2>&1 | tail -80 || true
    fi
else
    echo "APT not found."
fi

section "11. SNAP UPDATES"
if have snap; then
    snap refresh --list 2>&1 || true
else
    echo "Snap is not installed."
fi

section "12. FLATPAK UPDATES"
if have flatpak; then
    flatpak remote-ls --updates 2>&1 || true
else
    echo "Flatpak is not installed."
fi

section "13. FIRMWARE UPDATES (BIOS / DEVICES)"
if have fwupdmgr; then
    fwupdmgr get-devices 2>&1 || true
    echo
    fwupdmgr get-updates 2>&1 || true
else
    echo "fwupdmgr is not installed. Install with: sudo apt install fwupd"
fi

section "14. AUTOMATIC SECURITY UPDATE CONFIGURATION"
if have systemctl; then
    systemctl is-enabled unattended-upgrades 2>&1 || true
    systemctl is-active unattended-upgrades 2>&1 || true
fi
if dpkg-query -W -f='${Status}\n' unattended-upgrades 2>/dev/null | grep -q 'install ok installed'; then
    echo "unattended-upgrades package is installed."
else
    echo "unattended-upgrades package is not installed."
fi

section "15. OPTIONAL DIAGNOSTIC TOOLS"
for pkg in smartmontools nvme-cli lm-sensors fwupd memtester; do
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed'; then
        echo "[INSTALLED] $pkg"
    else
        echo "[MISSING]   $pkg"
    fi
done

section "REPORT COMPLETE"
echo "No package, driver, firmware, or BIOS updates were installed by this script."
echo "APT package indexes may have been refreshed."
echo "Report saved to: $REPORT"
echo
echo "Important:"
echo "- SMART is an early-warning indicator, not a guarantee against disk failure."
echo "- RAM usage is not a RAM health test. Use Memtest86+ from the boot menu for a proper test."
echo "- Temperature limits vary by CPU/GPU model; interpret sensor readings using vendor specifications."
echo "- Firmware updates should be reviewed carefully and performed with AC power connected."
