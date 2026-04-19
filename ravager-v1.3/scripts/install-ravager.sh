#!/usr/bin/env bash
# ============================================================================
# Ravager v1.3 — System Installer
# Dell Latitude 3120 Custom Kernel (6.9.0-AnarchyRavager-v1.3)
# Rain's Computer Resurrection — Loris, SC
# ============================================================================
#
# Usage:
#   sudo ./install-ravager.sh
#
# This script installs the compiled Ravager kernel to the system:
#   Phase 1:  Backup existing kernel
#   Phase 2:  Install kernel image (vmlinuz)
#   Phase 3:  Install kernel modules
#   Phase 4:  Generate initramfs
#   Phase 5:  Configure GRUB bootloader
#   Phase 6:  Install Wayland environment variables
#   Phase 7:  Install sysctl tuning
#   Phase 8:  Install ZRAM compressed swap service
#   Phase 9:  Install BFQ udev I/O scheduler rules
#   Phase 10: Install TLP power management profile
#
# ============================================================================

set -euo pipefail
IFS=$'\n\t'

readonly KERNEL_VERSION="6.9.0"
readonly EXTRAVERSION="-AnarchyRavager-v1.3"
readonly FULL_VERSION="${KERNEL_VERSION}${EXTRAVERSION}"
readonly KERNEL_NAME="Ravager v1.3"

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
readonly BUILD_DIR="${PROJECT_DIR}/build"
readonly SOURCE_DIR="${BUILD_DIR}/linux-${KERNEL_VERSION}"
readonly STAGING_DIR="${BUILD_DIR}/staging"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $*"; }
log_phase()   { echo -e "\n${MAGENTA}══ PHASE: $* ══${NC}\n"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_build_exists() {
    if [ ! -f "${SOURCE_DIR}/arch/x86/boot/bzImage" ]; then
        log_error "bzImage not found — run build-ravager.sh first"
        exit 1
    fi
    if [ ! -d "${STAGING_DIR}/lib/modules/${FULL_VERSION}" ]; then
        log_error "Staged modules not found — run build-ravager.sh first"
        exit 1
    fi
}

# ============================================================================
# PHASE 1: BACKUP
# ============================================================================
phase_backup() {
    log_phase "1/10 — Backup Existing Kernel"

    local backup_dir="/boot/ravager-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${backup_dir}"

    local current_kernel
    current_kernel=$(uname -r)

    for f in /boot/vmlinuz-"${current_kernel}" \
             /boot/initrd.img-"${current_kernel}" \
             /boot/System.map-"${current_kernel}" \
             /boot/config-"${current_kernel}"; do
        if [ -f "${f}" ]; then
            cp "${f}" "${backup_dir}/"
            log_info "Backed up: $(basename "${f}")"
        fi
    done

    if [ -f /etc/default/grub ]; then
        cp /etc/default/grub "${backup_dir}/grub.bak"
        log_info "Backed up: GRUB config"
    fi

    log_success "Backup saved to ${backup_dir}"
}

# ============================================================================
# PHASE 2: INSTALL KERNEL IMAGE
# ============================================================================
phase_install_kernel() {
    log_phase "2/10 — Install Kernel Image"

    cp "${SOURCE_DIR}/arch/x86/boot/bzImage" "/boot/vmlinuz-${FULL_VERSION}"
    log_info "Installed: /boot/vmlinuz-${FULL_VERSION}"

    if [ -f "${SOURCE_DIR}/System.map" ]; then
        cp "${SOURCE_DIR}/System.map" "/boot/System.map-${FULL_VERSION}"
        log_info "Installed: /boot/System.map-${FULL_VERSION}"
    fi

    cp "${SOURCE_DIR}/.config" "/boot/config-${FULL_VERSION}"
    log_info "Installed: /boot/config-${FULL_VERSION}"

    local size
    size=$(stat -c%s "/boot/vmlinuz-${FULL_VERSION}")
    log_success "Kernel image installed ($(( size / 1024 ))KB)"
}

# ============================================================================
# PHASE 3: INSTALL MODULES
# ============================================================================
phase_install_modules() {
    log_phase "3/10 — Install Kernel Modules"

    if [ -d "/lib/modules/${FULL_VERSION}" ]; then
        rm -rf "/lib/modules/${FULL_VERSION}"
        log_info "Removed old Ravager modules"
    fi

    cp -a "${STAGING_DIR}/lib/modules/${FULL_VERSION}" "/lib/modules/${FULL_VERSION}"
    depmod "${FULL_VERSION}"

    local mod_count
    mod_count=$(find "/lib/modules/${FULL_VERSION}" -name "*.ko*" | wc -l)
    log_success "Installed ${mod_count} modules to /lib/modules/${FULL_VERSION}"
}

# ============================================================================
# PHASE 4: GENERATE INITRAMFS
# ============================================================================
phase_initramfs() {
    log_phase "4/10 — Generate initramfs"

    if command -v update-initramfs &>/dev/null; then
        update-initramfs -c -k "${FULL_VERSION}"
        log_success "initramfs generated via update-initramfs"
    elif command -v dracut &>/dev/null; then
        dracut --force "/boot/initrd.img-${FULL_VERSION}" "${FULL_VERSION}"
        log_success "initramfs generated via dracut"
    elif command -v mkinitcpio &>/dev/null; then
        mkinitcpio -k "${FULL_VERSION}" -g "/boot/initrd.img-${FULL_VERSION}"
        log_success "initramfs generated via mkinitcpio"
    else
        log_error "No initramfs generator found (tried update-initramfs, dracut, mkinitcpio)"
        exit 1
    fi

    if [ -f "/boot/initrd.img-${FULL_VERSION}" ]; then
        local size
        size=$(stat -c%s "/boot/initrd.img-${FULL_VERSION}")
        log_info "initramfs size: $(( size / 1048576 ))MB"
    fi
}

# ============================================================================
# PHASE 5: CONFIGURE GRUB
# ============================================================================
phase_grub() {
    log_phase "5/10 — Configure GRUB Bootloader"

    local grub_cfg="/etc/default/grub.d/ravager.cfg"
    mkdir -p /etc/default/grub.d

    cat > "${grub_cfg}" << 'GRUB_CFG'
# ============================================================================
# Ravager v1.3 — GRUB Configuration
# Dell Latitude 3120 — Jasper Lake Optimized Boot Parameters
# ============================================================================
#
# i915.enable_psr=2        Panel Self Refresh level 2 (power savings)
# i915.enable_fbc=1        Framebuffer Compression (memory bandwidth)
# i915.enable_guc=2        GuC submission (GPU scheduler offload)
# intel_idle.max_cstate=8  Deep idle states (battery life)
# intel_pstate=active      Intel P-State driver (frequency scaling)
# zswap.enabled=1          Zswap compressed cache (memory expansion)
# zswap.compressor=lz4     LZ4 compression (fast on Tremont)
# zswap.max_pool_percent=25  25% of RAM for zswap pool
# zswap.zpool=z3fold       z3fold allocator (3:1 compression ratio)
# nowatchdog               Disable watchdog (reduce overhead)
# nmi_watchdog=0           Disable NMI watchdog (reduce overhead)
#
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 i915.enable_psr=2 i915.enable_fbc=1 i915.enable_guc=2 intel_idle.max_cstate=8 intel_pstate=active zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=25 zswap.zpool=z3fold nowatchdog nmi_watchdog=0"
GRUB_CFG

    log_info "Wrote GRUB config: ${grub_cfg}"

    if command -v update-grub &>/dev/null; then
        update-grub
        log_success "GRUB updated"
    elif command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg
        log_success "GRUB config regenerated"
    else
        log_warn "Could not find update-grub or grub-mkconfig — update GRUB manually"
    fi
}

# ============================================================================
# PHASE 6: WAYLAND ENVIRONMENT
# ============================================================================
phase_wayland_env() {
    log_phase "6/10 — Wayland Environment Variables"

    cat > /etc/profile.d/ravager-wayland.sh << 'WAYLAND_ENV'
# ============================================================================
# Ravager v1.3 — Wayland Environment Variables
# Ensures all toolkits use native Wayland rendering on KDE Neon Plasma
# ============================================================================

# Qt — prefer Wayland, fall back to XCB
export QT_QPA_PLATFORM="wayland;xcb"
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# GTK — prefer Wayland, fall back to X11
export GDK_BACKEND="wayland,x11"

# Firefox — native Wayland rendering + VA-API hardware video decode
export MOZ_ENABLE_WAYLAND=1
export MOZ_WAYLAND_USE_VAAPI=1

# SDL2 — Wayland-first for games and media apps
export SDL_VIDEODRIVER="wayland,x11"

# Clutter (GNOME apps running on Plasma)
export CLUTTER_BACKEND="wayland"

# EFL (Enlightenment Foundation Libraries)
export ECORE_EVAS_ENGINE="wayland_egl"
export ELM_ENGINE="wayland_egl"

# Java AWT — fix for tiling/stacking issues under Wayland
export _JAVA_AWT_WM_NONREPARENTING=1

# Electron apps (VS Code, Discord, Slack, etc.)
export ELECTRON_OZONE_PLATFORM_HINT="auto"

# XDG session type — tells desktop components we're on Wayland
export XDG_SESSION_TYPE="wayland"
export XDG_CURRENT_DESKTOP="KDE"
WAYLAND_ENV

    chmod 644 /etc/profile.d/ravager-wayland.sh
    log_success "Wayland environment installed: /etc/profile.d/ravager-wayland.sh"
}

# ============================================================================
# PHASE 7: SYSCTL TUNING
# ============================================================================
phase_sysctl() {
    log_phase "7/10 — Sysctl Memory & Network Tuning"

    cat > /etc/sysctl.d/99-ravager.conf << 'SYSCTL_CONF'
# ============================================================================
# Ravager v1.3 — Sysctl Tuning
# Dell Latitude 3120 — 4GB RAM Optimization + Network + Security
# ============================================================================

# --- Memory Management ---
# Swappiness: 10 = strongly prefer keeping apps in RAM
# (default 60 is too aggressive for 4GB desktop)
vm.swappiness = 10

# Dirty page ratios: aggressive writeback to prevent I/O stalls
# 5% dirty_ratio = ~200MB max dirty pages before synchronous flush
# 2% dirty_background_ratio = ~80MB before async writeback starts
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2

# VFS cache pressure: 75 = slightly favor keeping dentries/inodes
# (helps Baloo file indexer and KDE file dialogs)
vm.vfs_cache_pressure = 75

# Proactive compaction: reduce memory fragmentation
vm.compaction_proactiveness = 20

# Watermark boost: 0 = disable (reduces kswapd wake-ups)
vm.watermark_boost_factor = 0

# Max memory mappings (Plasma + Electron apps need this)
vm.max_map_count = 1048576

# --- Network (BBR + Fast Open) ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3

# TCP buffer tuning (WiFi-optimized)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 131072 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Disable SYN cookies (not a server)
net.ipv4.tcp_syncookies = 0

# --- Security ---
# Restrict dmesg access to root
kernel.dmesg_restrict = 1

# Hide kernel pointers from non-root
kernel.kptr_restrict = 2

# Yama ptrace scope: 1 = only parent can ptrace children
kernel.yama.ptrace_scope = 1

# SysRq: enable safe subset (sync, remount-ro, reboot)
# 176 = 128 (reboot) + 32 (remount-ro) + 16 (sync)
kernel.sysrq = 176

# --- Filesystem ---
# inotify watches: 524288 for Baloo file indexer
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
SYSCTL_CONF

    chmod 644 /etc/sysctl.d/99-ravager.conf
    sysctl --system &>/dev/null || true
    log_success "Sysctl tuning installed: /etc/sysctl.d/99-ravager.conf"
}

# ============================================================================
# PHASE 8: ZRAM COMPRESSED SWAP
# ============================================================================
phase_zram() {
    log_phase "8/10 — ZRAM Compressed Swap Service"

    cat > /etc/systemd/system/ravager-zram.service << 'ZRAM_SERVICE'
# ============================================================================
# Ravager v1.3 — ZRAM Compressed Swap
# 2GB LZ4 compressed → ~4GB effective swap from RAM
# ============================================================================
[Unit]
Description=Ravager v1.3 — ZRAM Compressed Swap (2GB LZ4)
After=local-fs.target
Before=swap.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '\
    modprobe zram num_devices=1 && \
    echo lz4 > /sys/block/zram0/comp_algorithm && \
    echo 2G > /sys/block/zram0/disksize && \
    mkswap /dev/zram0 && \
    swapon -p 100 /dev/zram0 \
'
ExecStop=/bin/bash -c '\
    swapoff /dev/zram0 2>/dev/null; \
    echo 1 > /sys/block/zram0/reset \
'

[Install]
WantedBy=multi-user.target
ZRAM_SERVICE

    systemctl daemon-reload
    systemctl enable ravager-zram.service
    log_success "ZRAM service installed and enabled (2GB LZ4 compressed swap)"
}

# ============================================================================
# PHASE 9: BFQ UDEV RULES
# ============================================================================
phase_udev_bfq() {
    log_phase "9/10 — BFQ I/O Scheduler udev Rules"

    cat > /etc/udev/rules.d/60-ravager-iosched.rules << 'UDEV_RULES'
# ============================================================================
# Ravager v1.3 — I/O Scheduler Rules
# KIOXIA BG4 128GB NVMe (DRAM-less HMB) — BFQ required
# ============================================================================

# --- NVMe: BFQ with tuned queue depth ---
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/nr_requests}="64"
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/read_ahead_kb}="128"
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/iosched/low_latency}="1"
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/iostats}="0"
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/wbt_lat_usec}="2000"

# --- USB mass storage: BFQ conservative ---
ACTION=="add|change", KERNEL=="sd[a-z]", ATTRS{removable}=="1", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTRS{removable}=="1", ATTR{queue/nr_requests}="32"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTRS{removable}=="1", ATTR{queue/read_ahead_kb}="64"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTRS{removable}=="1", ATTR{queue/iosched/low_latency}="1"

# --- SATA/SCSI (external dock) ---
ACTION=="add|change", KERNEL=="sd[a-z]", ATTRS{removable}=="0", ATTR{queue/scheduler}="bfq"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTRS{removable}=="0", ATTR{queue/nr_requests}="128"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTRS{removable}=="0", ATTR{queue/read_ahead_kb}="256"
UDEV_RULES

    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
    log_success "BFQ udev rules installed: /etc/udev/rules.d/60-ravager-iosched.rules"
}

# ============================================================================
# PHASE 10: TLP POWER MANAGEMENT
# ============================================================================
phase_tlp() {
    log_phase "10/10 — TLP Power Management Profile"

    if ! command -v tlp &>/dev/null; then
        log_info "Installing TLP..."
        apt-get install -y -qq tlp tlp-rdw 2>/dev/null || true
    fi

    if command -v tlp &>/dev/null; then
        mkdir -p /etc/tlp.d
        cat > /etc/tlp.d/01-ravager.conf << 'TLP_CONF'
# ============================================================================
# Ravager v1.3 — TLP Power Profile
# Jasper Lake N5100 — 6W TDP / 42Wh Battery
# ============================================================================

# CPU governor: performance on AC, schedutil on battery
CPU_SCALING_GOVERNOR_ON_AC=performance
CPU_SCALING_GOVERNOR_ON_BAT=schedutil

# Energy performance preference
CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power

# CPU boost: enable on AC, disable on battery (thermal/power savings)
CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=0

# HWP dynamic boost
CPU_HWP_DYN_BOOST_ON_AC=1
CPU_HWP_DYN_BOOST_ON_BAT=0

# WiFi power saving: off on AC (low latency), on battery (power savings)
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=on

# AHCI runtime PM (no SATA in this chassis, but covers USB docks)
AHCI_RUNTIME_PM_ON_AC=on
AHCI_RUNTIME_PM_ON_BAT=auto

# USB autosuspend
USB_AUTOSUSPEND=1

# Runtime PM
RUNTIME_PM_ON_AC=auto
RUNTIME_PM_ON_BAT=auto

# Audio power saving (1 second timeout)
SOUND_POWER_SAVE_ON_AC=1
SOUND_POWER_SAVE_ON_BAT=1

# Platform profile
PLATFORM_PROFILE_ON_AC=balanced
PLATFORM_PROFILE_ON_BAT=low-power
TLP_CONF

        systemctl enable tlp.service 2>/dev/null || true
        tlp start 2>/dev/null || true
        log_success "TLP power profile installed: /etc/tlp.d/01-ravager.conf"
    else
        log_warn "TLP not available — skipping power management"
    fi
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    echo -e "${MAGENTA}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║       RAVAGER v1.3 — System Installer                ║"
    echo "  ║       6.9.0-AnarchyRavager-v1.3                      ║"
    echo "  ║       Dell Latitude 3120 — Jasper Lake Tremont        ║"
    echo "  ║       Rain's Computer Resurrection — Loris, SC        ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_root
    check_build_exists

    phase_backup
    phase_install_kernel
    phase_install_modules
    phase_initramfs
    phase_grub
    phase_wayland_env
    phase_sysctl
    phase_zram
    phase_udev_bfq
    phase_tlp

    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  RAVAGER v1.3 — INSTALLATION COMPLETE${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Kernel:      ${WHITE}/boot/vmlinuz-${FULL_VERSION}${NC}"
    echo -e "  Modules:     ${WHITE}/lib/modules/${FULL_VERSION}/${NC}"
    echo -e "  initramfs:   ${WHITE}/boot/initrd.img-${FULL_VERSION}${NC}"
    echo -e "  GRUB config: ${WHITE}/etc/default/grub.d/ravager.cfg${NC}"
    echo -e "  Wayland env: ${WHITE}/etc/profile.d/ravager-wayland.sh${NC}"
    echo -e "  Sysctl:      ${WHITE}/etc/sysctl.d/99-ravager.conf${NC}"
    echo -e "  ZRAM:        ${WHITE}ravager-zram.service (2GB LZ4)${NC}"
    echo -e "  BFQ rules:   ${WHITE}/etc/udev/rules.d/60-ravager-iosched.rules${NC}"
    echo -e "  TLP:         ${WHITE}/etc/tlp.d/01-ravager.conf${NC}"
    echo ""
    echo -e "  ${YELLOW}Reboot and select '${FULL_VERSION}' from GRUB menu${NC}"
    echo -e "  ${YELLOW}After boot: ./scripts/verify-ravager.sh${NC}"
    echo ""
}

main "$@"
