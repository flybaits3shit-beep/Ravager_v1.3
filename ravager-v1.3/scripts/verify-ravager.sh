#!/usr/bin/env bash
# ============================================================================
# Ravager v1.3 — Post-Boot Verification Script
# Dell Latitude 3120 Custom Kernel (6.9.0-AnarchyRavager-v1.3)
# Rain's Computer Resurrection — Loris, SC
# ============================================================================
#
# Usage:
#   ./verify-ravager.sh
#
# Runs 13 subsystem checks after booting into the Ravager kernel:
#   1.  Kernel identity (uname, /proc/version)
#   2.  CPU target and features
#   3.  Preemption model and timer
#   4.  GPU driver (i915)
#   5.  WiFi driver (iwlwifi/iwlmvm)
#   6.  Bluetooth (btusb/btintel)
#   7.  Audio (snd_hda_intel / SOF)
#   8.  NVMe and I/O scheduler (BFQ)
#   9.  Memory (Zswap + ZRAM)
#   10. Network (BBR congestion control)
#   11. Security (AppArmor, Yama)
#   12. Power management (TLP, P-State)
#   13. Wayland environment
#
# ============================================================================

set -euo pipefail

readonly FULL_VERSION="6.9.0-AnarchyRavager-v1.3"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
TOTAL_CHECKS=0

check_pass() {
    echo -e "  ${GREEN}✓ PASS${NC}  $*"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
    TOTAL_CHECKS=$(( TOTAL_CHECKS + 1 ))
}

check_warn() {
    echo -e "  ${YELLOW}⚠ WARN${NC}  $*"
    WARN_COUNT=$(( WARN_COUNT + 1 ))
    TOTAL_CHECKS=$(( TOTAL_CHECKS + 1 ))
}

check_fail() {
    echo -e "  ${RED}✗ FAIL${NC}  $*"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
    TOTAL_CHECKS=$(( TOTAL_CHECKS + 1 ))
}

section() {
    echo ""
    echo -e "${CYAN}── $* ──${NC}"
}

# ============================================================================
# BANNER
# ============================================================================
echo -e "${MAGENTA}"
cat << 'BANNER'
    ██████╗  █████╗ ██╗   ██╗ █████╗  ██████╗ ███████╗██████╗
    ██╔══██╗██╔══██╗██║   ██║██╔══██╗██╔════╝ ██╔════╝██╔══██╗
    ██████╔╝███████║██║   ██║███████║██║  ███╗█████╗  ██████╔╝
    ██╔══██╗██╔══██║╚██╗ ██╔╝██╔══██║██║   ██║██╔══╝  ██╔══██╗
    ██║  ██║██║  ██║ ╚████╔╝ ██║  ██║╚██████╔╝███████╗██║  ██║
    ╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝
BANNER
echo -e "${CYAN}    Post-Boot Verification — 13 Subsystem Health Check${NC}"
echo -e "${WHITE}    Expected: ${FULL_VERSION}${NC}"
echo -e "${MAGENTA}══════════════════════════════════════════════════════════════${NC}"

# ============================================================================
# CHECK 1: KERNEL IDENTITY
# ============================================================================
section "1/13 — Kernel Identity"

current_kernel=$(uname -r)
if [ "${current_kernel}" = "${FULL_VERSION}" ]; then
    check_pass "uname -r: ${current_kernel}"
else
    check_fail "uname -r: ${current_kernel} (expected ${FULL_VERSION})"
fi

if [ -f /proc/version ]; then
    proc_version=$(cat /proc/version)
    if echo "${proc_version}" | grep -q "AnarchyRavager"; then
        check_pass "/proc/version contains AnarchyRavager branding"
    else
        check_warn "/proc/version missing AnarchyRavager branding"
    fi

    if echo "${proc_version}" | grep -q "ravager@AnarchyRavager"; then
        check_pass "Build identity: ravager@AnarchyRavager"
    else
        check_warn "Build identity not found in /proc/version"
    fi
fi

if [ -f "/boot/vmlinuz-${FULL_VERSION}" ]; then
    check_pass "Boot image exists: /boot/vmlinuz-${FULL_VERSION}"
else
    check_fail "Boot image missing: /boot/vmlinuz-${FULL_VERSION}"
fi

if [ -d "/lib/modules/${FULL_VERSION}" ]; then
    mod_count=$(find "/lib/modules/${FULL_VERSION}" -name "*.ko*" 2>/dev/null | wc -l)
    if [ "${mod_count}" -gt 0 ] && [ "${mod_count}" -lt 500 ]; then
        check_pass "Modules installed: ${mod_count} (lean build confirmed)"
    elif [ "${mod_count}" -ge 500 ]; then
        check_warn "Modules installed: ${mod_count} (higher than expected — check config)"
    else
        check_fail "No modules found in /lib/modules/${FULL_VERSION}"
    fi
else
    check_fail "Module directory missing: /lib/modules/${FULL_VERSION}"
fi

# ============================================================================
# CHECK 2: CPU TARGET AND FEATURES
# ============================================================================
section "2/13 — CPU Target & Features"

if [ -f "/boot/config-${FULL_VERSION}" ]; then
    if grep -q "CONFIG_MATOM=y" "/boot/config-${FULL_VERSION}"; then
        check_pass "CPU target: MATOM (Tremont/Atom-family)"
    else
        check_fail "CPU target: NOT MATOM — wrong instruction scheduling"
    fi
else
    check_warn "Config file not found — cannot verify CPU target"
fi

cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
if echo "${cpu_model}" | grep -qi "N5100\|N4500\|N6000\|Jasper"; then
    check_pass "CPU detected: ${cpu_model} (Jasper Lake confirmed)"
else
    check_warn "CPU detected: ${cpu_model} (verify Jasper Lake compatibility)"
fi

cpu_cores=$(nproc)
if [ "${cpu_cores}" -le 4 ]; then
    check_pass "CPU cores: ${cpu_cores} (matches NR_CPUS=4 config)"
else
    check_warn "CPU cores: ${cpu_cores} (config was tuned for 4)"
fi

if grep -q "aes" /proc/cpuinfo 2>/dev/null; then
    check_pass "AES-NI: available (hardware crypto active)"
else
    check_warn "AES-NI: not detected"
fi

# ============================================================================
# CHECK 3: PREEMPTION & TIMER
# ============================================================================
section "3/13 — Preemption Model & Timer"

if [ -f "/boot/config-${FULL_VERSION}" ]; then
    if grep -q "CONFIG_PREEMPT=y" "/boot/config-${FULL_VERSION}"; then
        check_pass "Preemption: Full PREEMPT (desktop responsiveness)"
    else
        check_warn "Preemption: NOT full PREEMPT"
    fi

    if grep -q "CONFIG_HZ_1000=y" "/boot/config-${FULL_VERSION}"; then
        check_pass "Timer frequency: 1000Hz (1ms tick)"
    else
        check_warn "Timer frequency: NOT 1000Hz"
    fi

    if grep -q "CONFIG_NO_HZ_IDLE=y" "/boot/config-${FULL_VERSION}"; then
        check_pass "Tickless: idle mode (power savings)"
    else
        check_warn "Tickless mode not configured"
    fi
fi

# ============================================================================
# CHECK 4: GPU (i915)
# ============================================================================
section "4/13 — GPU Driver (Intel i915)"

if [ -f "/boot/config-${FULL_VERSION}" ]; then
    if grep -q "CONFIG_DRM_I915=y" "/boot/config-${FULL_VERSION}"; then
        check_pass "i915: built-in (=y) — early KMS active"
    elif grep -q "CONFIG_DRM_I915=m" "/boot/config-${FULL_VERSION}"; then
        check_warn "i915: module (=m) — should be built-in for early KMS"
    else
        check_fail "i915: not configured"
    fi
fi

if [ -d /sys/class/drm/card0 ] || [ -d /sys/class/drm/card1 ]; then
    drm_driver=""
    for card in /sys/class/drm/card*/device/driver; do
        if [ -L "${card}" ]; then
            drm_driver=$(basename "$(readlink "${card}")")
            break
        fi
    done
    if [ "${drm_driver}" = "i915" ]; then
        check_pass "DRM driver active: i915"
    else
        check_warn "DRM driver active: ${drm_driver:-unknown} (expected i915)"
    fi
else
    check_warn "No DRM card detected in /sys/class/drm/"
fi

# Check i915 boot parameters
if [ -f /proc/cmdline ]; then
    cmdline=$(cat /proc/cmdline)

    if echo "${cmdline}" | grep -q "i915.enable_psr=2"; then
        check_pass "i915 PSR2: enabled (Panel Self Refresh)"
    else
        check_warn "i915 PSR2: not in boot params"
    fi

    if echo "${cmdline}" | grep -q "i915.enable_fbc=1"; then
        check_pass "i915 FBC: enabled (Framebuffer Compression)"
    else
        check_warn "i915 FBC: not in boot params"
    fi

    if echo "${cmdline}" | grep -q "i915.enable_guc=2"; then
        check_pass "i915 GuC: submission mode (scheduler offload)"
    else
        check_warn "i915 GuC: not in boot params"
    fi
fi

# ============================================================================
# CHECK 5: WIFI (iwlwifi)
# ============================================================================
section "5/13 — WiFi (Intel AX201)"

if lsmod 2>/dev/null | grep -q "iwlmvm"; then
    check_pass "iwlmvm: loaded"
else
    check_warn "iwlmvm: not loaded (load with: modprobe iwlmvm)"
fi

if lsmod 2>/dev/null | grep -q "iwlwifi"; then
    check_pass "iwlwifi: loaded"
else
    check_warn "iwlwifi: not loaded"
fi

wifi_iface=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}' | head -1)
if [ -n "${wifi_iface}" ]; then
    check_pass "WiFi interface: ${wifi_iface}"
else
    check_warn "No WiFi interface detected"
fi

# ============================================================================
# CHECK 6: BLUETOOTH
# ============================================================================
section "6/13 — Bluetooth (Intel AX201)"

if lsmod 2>/dev/null | grep -q "btusb"; then
    check_pass "btusb: loaded"
else
    check_warn "btusb: not loaded (load with: modprobe btusb)"
fi

if lsmod 2>/dev/null | grep -q "btintel"; then
    check_pass "btintel: loaded"
else
    check_warn "btintel: not loaded"
fi

if command -v bluetoothctl &>/dev/null; then
    bt_power=$(bluetoothctl show 2>/dev/null | grep "Powered:" | awk '{print $2}')
    if [ "${bt_power}" = "yes" ]; then
        check_pass "Bluetooth: powered on"
    else
        check_warn "Bluetooth: powered off"
    fi
fi

# ============================================================================
# CHECK 7: AUDIO
# ============================================================================
section "7/13 — Audio (Realtek ALC3246)"

if lsmod 2>/dev/null | grep -q "snd_hda_intel"; then
    check_pass "snd_hda_intel: loaded"
elif [ -f "/boot/config-${FULL_VERSION}" ] && grep -q "CONFIG_SND_HDA_INTEL=y" "/boot/config-${FULL_VERSION}"; then
    check_pass "snd_hda_intel: built-in"
else
    check_warn "snd_hda_intel: not detected"
fi

if lsmod 2>/dev/null | grep -q "snd_sof"; then
    check_pass "SOF (Sound Open Firmware): loaded"
else
    check_warn "SOF: not loaded (may use legacy HDA path — OK for ALC3246)"
fi

if [ -d /proc/asound ]; then
    card_count=$(cat /proc/asound/cards 2>/dev/null | grep -c "^\s*[0-9]")
    if [ "${card_count}" -gt 0 ]; then
        check_pass "ALSA sound cards detected: ${card_count}"
    else
        check_warn "No ALSA sound cards detected"
    fi
fi

# ============================================================================
# CHECK 8: NVME & I/O SCHEDULER
# ============================================================================
section "8/13 — NVMe & I/O Scheduler (BFQ)"

if [ -b /dev/nvme0n1 ]; then
    check_pass "NVMe device: /dev/nvme0n1 present"

    nvme_model=$(cat /sys/block/nvme0n1/device/model 2>/dev/null | xargs)
    if [ -n "${nvme_model}" ]; then
        check_pass "NVMe model: ${nvme_model}"
    fi

    scheduler=$(cat /sys/block/nvme0n1/queue/scheduler 2>/dev/null)
    if echo "${scheduler}" | grep -q "\[bfq\]"; then
        check_pass "I/O scheduler: BFQ (active)"
    else
        check_warn "I/O scheduler: ${scheduler} (expected [bfq])"
    fi

    nr_requests=$(cat /sys/block/nvme0n1/queue/nr_requests 2>/dev/null)
    if [ "${nr_requests}" = "64" ]; then
        check_pass "Queue depth: 64 (DRAM-less NVMe optimized)"
    else
        check_warn "Queue depth: ${nr_requests} (expected 64)"
    fi

    read_ahead=$(cat /sys/block/nvme0n1/queue/read_ahead_kb 2>/dev/null)
    if [ "${read_ahead}" = "128" ]; then
        check_pass "Read-ahead: 128KB (4K random optimized)"
    else
        check_warn "Read-ahead: ${read_ahead}KB (expected 128)"
    fi
else
    check_warn "NVMe device not found at /dev/nvme0n1"
fi

# ============================================================================
# CHECK 9: MEMORY (ZSWAP + ZRAM)
# ============================================================================
section "9/13 — Memory Optimization"

total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
total_ram_mb=$(( total_ram_kb / 1024 ))
check_pass "Physical RAM: ${total_ram_mb}MB"

# Zswap
if [ -f /sys/module/zswap/parameters/enabled ]; then
    zswap_enabled=$(cat /sys/module/zswap/parameters/enabled)
    if [ "${zswap_enabled}" = "Y" ]; then
        check_pass "Zswap: enabled"

        zswap_comp=$(cat /sys/module/zswap/parameters/compressor 2>/dev/null)
        if [ "${zswap_comp}" = "lz4" ]; then
            check_pass "Zswap compressor: LZ4"
        else
            check_warn "Zswap compressor: ${zswap_comp} (expected lz4)"
        fi

        zswap_pool=$(cat /sys/module/zswap/parameters/max_pool_percent 2>/dev/null)
        check_pass "Zswap pool: ${zswap_pool}% of RAM"
    else
        check_warn "Zswap: disabled"
    fi
else
    check_warn "Zswap: not available"
fi

# ZRAM
if [ -b /dev/zram0 ]; then
    zram_size=$(cat /sys/block/zram0/disksize 2>/dev/null)
    zram_size_mb=$(( zram_size / 1048576 ))
    zram_algo=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')
    check_pass "ZRAM: ${zram_size_mb}MB (${zram_algo:-unknown} compressed)"

    if swapon --show 2>/dev/null | grep -q "zram0"; then
        check_pass "ZRAM swap: active"
    else
        check_warn "ZRAM swap: not active"
    fi
else
    check_warn "ZRAM: not configured (enable ravager-zram.service)"
fi

# Swappiness
swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null)
if [ "${swappiness}" = "10" ]; then
    check_pass "Swappiness: 10 (apps stay in RAM)"
else
    check_warn "Swappiness: ${swappiness} (expected 10)"
fi

# Effective memory estimate
effective_mb=${total_ram_mb}
if [ -b /dev/zram0 ]; then
    effective_mb=$(( effective_mb + zram_size_mb * 2 ))
fi
if [ -f /sys/module/zswap/parameters/enabled ] && [ "$(cat /sys/module/zswap/parameters/enabled)" = "Y" ]; then
    zswap_effective=$(( total_ram_mb * ${zswap_pool:-25} / 100 * 2 ))
    effective_mb=$(( effective_mb + zswap_effective ))
fi
check_pass "Effective memory estimate: ~${effective_mb}MB"

# ============================================================================
# CHECK 10: NETWORK (BBR)
# ============================================================================
section "10/13 — Network (TCP BBR)"

tcp_cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)
if [ "${tcp_cc}" = "bbr" ]; then
    check_pass "TCP congestion control: BBR"
else
    check_warn "TCP congestion control: ${tcp_cc} (expected bbr)"
fi

qdisc=$(cat /proc/sys/net/core/default_qdisc 2>/dev/null)
if [ "${qdisc}" = "fq" ]; then
    check_pass "Default qdisc: fq (Fair Queueing)"
else
    check_warn "Default qdisc: ${qdisc} (expected fq)"
fi

tcp_fastopen=$(cat /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null)
if [ "${tcp_fastopen}" = "3" ]; then
    check_pass "TCP Fast Open: enabled (client + server)"
else
    check_warn "TCP Fast Open: ${tcp_fastopen} (expected 3)"
fi

# ============================================================================
# CHECK 11: SECURITY
# ============================================================================
section "11/13 — Security (AppArmor + Yama)"

if [ -d /sys/kernel/security/apparmor ]; then
    aa_profiles=$(cat /sys/kernel/security/apparmor/profiles 2>/dev/null | wc -l)
    check_pass "AppArmor: active (${aa_profiles} profiles loaded)"
else
    check_warn "AppArmor: not active"
fi

if [ -f /proc/sys/kernel/yama/ptrace_scope ]; then
    yama_scope=$(cat /proc/sys/kernel/yama/ptrace_scope)
    if [ "${yama_scope}" = "1" ]; then
        check_pass "Yama ptrace_scope: 1 (restricted)"
    else
        check_warn "Yama ptrace_scope: ${yama_scope} (expected 1)"
    fi
else
    check_warn "Yama: not available"
fi

kptr=$(cat /proc/sys/kernel/kptr_restrict 2>/dev/null)
if [ "${kptr}" = "2" ]; then
    check_pass "kptr_restrict: 2 (kernel pointers hidden)"
else
    check_warn "kptr_restrict: ${kptr} (expected 2)"
fi

dmesg_restrict=$(cat /proc/sys/kernel/dmesg_restrict 2>/dev/null)
if [ "${dmesg_restrict}" = "1" ]; then
    check_pass "dmesg_restrict: 1 (root-only)"
else
    check_warn "dmesg_restrict: ${dmesg_restrict} (expected 1)"
fi

# ============================================================================
# CHECK 12: POWER MANAGEMENT
# ============================================================================
section "12/13 — Power Management"

if [ -d /sys/devices/system/cpu/intel_pstate ]; then
    pstate_status=$(cat /sys/devices/system/cpu/intel_pstate/status 2>/dev/null)
    check_pass "Intel P-State: ${pstate_status}"
else
    check_warn "Intel P-State: not detected"
fi

governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
if [ -n "${governor}" ]; then
    check_pass "CPU governor: ${governor}"
else
    check_warn "CPU governor: unknown"
fi

if command -v tlp-stat &>/dev/null; then
    check_pass "TLP: installed"
    if systemctl is-active tlp.service &>/dev/null; then
        check_pass "TLP service: active"
    else
        check_warn "TLP service: not running"
    fi
else
    check_warn "TLP: not installed (recommended for battery life)"
fi

# Check power source
if [ -f /sys/class/power_supply/AC/online ]; then
    ac_online=$(cat /sys/class/power_supply/AC/online 2>/dev/null)
    if [ "${ac_online}" = "1" ]; then
        check_pass "Power source: AC (plugged in)"
    else
        check_pass "Power source: Battery"
        # Show battery percentage if available
        for bat in /sys/class/power_supply/BAT*; do
            if [ -f "${bat}/capacity" ]; then
                bat_pct=$(cat "${bat}/capacity")
                check_pass "Battery level: ${bat_pct}%"
            fi
        done
    fi
fi

# ============================================================================
# CHECK 13: WAYLAND ENVIRONMENT
# ============================================================================
section "13/13 — Wayland Environment"

if [ -f /etc/profile.d/ravager-wayland.sh ]; then
    check_pass "Wayland env file: installed"
else
    check_warn "Wayland env file: not found"
fi

session_type="${XDG_SESSION_TYPE:-unknown}"
if [ "${session_type}" = "wayland" ]; then
    check_pass "Session type: Wayland"
else
    check_warn "Session type: ${session_type} (expected wayland)"
fi

if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    check_pass "Wayland display: ${WAYLAND_DISPLAY}"
else
    check_warn "Wayland display: not set (may not be in a graphical session)"
fi

desktop="${XDG_CURRENT_DESKTOP:-unknown}"
if echo "${desktop}" | grep -qi "KDE"; then
    check_pass "Desktop environment: ${desktop}"
else
    check_warn "Desktop environment: ${desktop} (expected KDE)"
fi

if [ "${MOZ_ENABLE_WAYLAND:-0}" = "1" ]; then
    check_pass "Firefox Wayland: enabled"
else
    check_warn "Firefox Wayland: not set (source /etc/profile.d/ravager-wayland.sh)"
fi

# ============================================================================
# RESULTS SUMMARY
# ============================================================================
echo ""
echo -e "${MAGENTA}══════════════════════════════════════════════════════════════${NC}"
echo -e "${MAGENTA}  RAVAGER v1.3 — VERIFICATION RESULTS${NC}"
echo -e "${MAGENTA}══════════════════════════════════════════════════════════════${NC}"
echo ""

# Health bar
health_pct=0
if [ "${TOTAL_CHECKS}" -gt 0 ]; then
    health_pct=$(( (PASS_COUNT * 100) / TOTAL_CHECKS ))
fi

bar_width=40
filled=$(( health_pct * bar_width / 100 ))
empty=$(( bar_width - filled ))

if [ "${health_pct}" -ge 80 ]; then
    bar_color="${GREEN}"
elif [ "${health_pct}" -ge 60 ]; then
    bar_color="${YELLOW}"
else
    bar_color="${RED}"
fi

printf "  Health: ${bar_color}["
printf "%0.s█" $(seq 1 ${filled} 2>/dev/null) || true
printf "%0.s░" $(seq 1 ${empty} 2>/dev/null) || true
printf "]${NC} ${WHITE}%d%%${NC}\n" "${health_pct}"

echo ""
echo -e "  ${GREEN}PASS:${NC} ${PASS_COUNT}    ${YELLOW}WARN:${NC} ${WARN_COUNT}    ${RED}FAIL:${NC} ${FAIL_COUNT}    Total: ${TOTAL_CHECKS}"
echo ""

if [ "${FAIL_COUNT}" -eq 0 ] && [ "${WARN_COUNT}" -eq 0 ]; then
    echo -e "  ${GREEN}★ PERFECT SCORE — Ravager v1.3 is fully operational ★${NC}"
elif [ "${FAIL_COUNT}" -eq 0 ]; then
    echo -e "  ${GREEN}Ravager v1.3 is operational${NC} (${WARN_COUNT} warnings — review above)"
else
    echo -e "  ${RED}Ravager v1.3 has ${FAIL_COUNT} failures — review above${NC}"
fi

echo ""
echo -e "${YELLOW}  Rain's Computer Resurrection — Loris, SC${NC}"
echo -e "${WHITE}  \"I'm good at what I do, and I do what I do well.\"${NC}"
echo ""
