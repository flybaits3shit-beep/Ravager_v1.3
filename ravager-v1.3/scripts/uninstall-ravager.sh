#!/usr/bin/env bash
# ============================================================================
# Ravager v1.3 — Uninstaller
# Dell Latitude 3120 Custom Kernel (6.9.0-AnarchyRavager-v1.3)
# Rain's Computer Resurrection — Loris, SC
# ============================================================================
#
# Usage:
#   sudo ./uninstall-ravager.sh
#
# Safely removes all Ravager v1.3 components from the system:
#   Phase 1: Safety check (won't remove if it's the only kernel)
#   Phase 2: Remove kernel image and related boot files
#   Phase 3: Remove kernel modules
#   Phase 4: Remove system configuration files
#   Phase 5: Remove systemd services
#   Phase 6: Update GRUB
#
# ============================================================================

set -euo pipefail
IFS=$'\n\t'

readonly KERNEL_VERSION="6.9.0"
readonly EXTRAVERSION="-AnarchyRavager-v1.3"
readonly FULL_VERSION="${KERNEL_VERSION}${EXTRAVERSION}"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly MAGENTA='\033[0;35m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $*"; }
log_phase()   { echo -e "\n${MAGENTA}══ PHASE: $* ══${NC}\n"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# ============================================================================
# ROOT CHECK
# ============================================================================
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# ============================================================================
# PHASE 1: SAFETY CHECK
# ============================================================================
phase_safety_check() {
    log_phase "1/6 — Safety Check"

    local current_kernel
    current_kernel=$(uname -r)

    # Don't uninstall if we're currently running Ravager
    if [ "${current_kernel}" = "${FULL_VERSION}" ]; then
        log_error "You are currently running ${FULL_VERSION}"
        log_error "Boot into a different kernel first, then run this script"
        exit 1
    fi

    # Count available kernels — don't leave system unbootable
    local kernel_count
    kernel_count=$(ls /boot/vmlinuz-* 2>/dev/null | wc -l)

    if [ "${kernel_count}" -le 1 ]; then
        log_error "Only one kernel found in /boot — refusing to uninstall"
        log_error "This would leave your system unbootable"
        exit 1
    fi

    # Check if Ravager is actually installed
    if [ ! -f "/boot/vmlinuz-${FULL_VERSION}" ]; then
        log_warn "Ravager kernel not found in /boot — may already be uninstalled"
        log_info "Continuing to clean up configuration files..."
    fi

    log_info "Current kernel: ${current_kernel}"
    log_info "Kernels in /boot: ${kernel_count}"
    log_success "Safety check passed — safe to uninstall"
}

# ============================================================================
# PHASE 2: REMOVE BOOT FILES
# ============================================================================
phase_remove_boot() {
    log_phase "2/6 — Remove Kernel Boot Files"

    local files=(
        "/boot/vmlinuz-${FULL_VERSION}"
        "/boot/initrd.img-${FULL_VERSION}"
        "/boot/System.map-${FULL_VERSION}"
        "/boot/config-${FULL_VERSION}"
    )

    for f in "${files[@]}"; do
        if [ -f "${f}" ]; then
            rm -f "${f}"
            log_info "Removed: ${f}"
        else
            log_info "Not found (skipped): ${f}"
        fi
    done

    log_success "Boot files removed"
}

# ============================================================================
# PHASE 3: REMOVE MODULES
# ============================================================================
phase_remove_modules() {
    log_phase "3/6 — Remove Kernel Modules"

    local mod_dir="/lib/modules/${FULL_VERSION}"

    if [ -d "${mod_dir}" ]; then
        rm -rf "${mod_dir}"
        log_info "Removed: ${mod_dir}"
        log_success "Kernel modules removed"
    else
        log_info "Module directory not found (skipped): ${mod_dir}"
    fi
}

# ============================================================================
# PHASE 4: REMOVE CONFIGURATION FILES
# ============================================================================
phase_remove_configs() {
    log_phase "4/6 — Remove Configuration Files"

    local config_files=(
        "/etc/default/grub.d/ravager.cfg"
        "/etc/profile.d/ravager-wayland.sh"
        "/etc/sysctl.d/99-ravager.conf"
        "/etc/udev/rules.d/60-ravager-iosched.rules"
        "/etc/tlp.d/01-ravager.conf"
    )

    for f in "${config_files[@]}"; do
        if [ -f "${f}" ]; then
            rm -f "${f}"
            log_info "Removed: ${f}"
        else
            log_info "Not found (skipped): ${f}"
        fi
    done

    # Reload sysctl to remove Ravager tuning
    sysctl --system &>/dev/null || true
    log_info "Sysctl reloaded"

    # Reload udev rules
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
    log_info "udev rules reloaded"

    log_success "Configuration files removed"
}

# ============================================================================
# PHASE 5: REMOVE SYSTEMD SERVICES
# ============================================================================
phase_remove_services() {
    log_phase "5/6 — Remove Systemd Services"

    local service="ravager-zram.service"

    if systemctl is-enabled "${service}" &>/dev/null; then
        systemctl stop "${service}" 2>/dev/null || true
        systemctl disable "${service}" 2>/dev/null || true
        log_info "Stopped and disabled: ${service}"
    fi

    if [ -f "/etc/systemd/system/${service}" ]; then
        rm -f "/etc/systemd/system/${service}"
        log_info "Removed: /etc/systemd/system/${service}"
    fi

    systemctl daemon-reload 2>/dev/null || true
    log_success "Systemd services removed"
}

# ============================================================================
# PHASE 6: UPDATE GRUB
# ============================================================================
phase_update_grub() {
    log_phase "6/6 — Update GRUB"

    if command -v update-grub &>/dev/null; then
        update-grub
        log_success "GRUB updated — Ravager entry removed"
    elif command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg
        log_success "GRUB config regenerated — Ravager entry removed"
    else
        log_warn "Could not find update-grub or grub-mkconfig"
        log_warn "Update GRUB manually to remove Ravager entry"
    fi
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    echo -e "${MAGENTA}"
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║       RAVAGER v1.3 — Uninstaller                     ║"
    echo "  ║       6.9.0-AnarchyRavager-v1.3                      ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    check_root

    echo -e "${YELLOW}This will remove ALL Ravager v1.3 components from your system.${NC}"
    echo -e "${YELLOW}Components to be removed:${NC}"
    echo "  - Kernel image, initramfs, System.map, config from /boot"
    echo "  - Kernel modules from /lib/modules/${FULL_VERSION}"
    echo "  - GRUB configuration (ravager.cfg)"
    echo "  - Wayland environment variables"
    echo "  - Sysctl tuning"
    echo "  - ZRAM swap service"
    echo "  - BFQ udev rules"
    echo "  - TLP power profile"
    echo ""
    read -rp "Proceed with uninstallation? [y/N] " confirm

    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        log_info "Uninstallation cancelled"
        exit 0
    fi

    phase_safety_check
    phase_remove_boot
    phase_remove_modules
    phase_remove_configs
    phase_remove_services
    phase_update_grub

    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  RAVAGER v1.3 — UNINSTALLATION COMPLETE${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  All Ravager v1.3 components have been removed."
    echo -e "  Your system will boot the default kernel on next reboot."
    echo ""
    echo -e "  ${YELLOW}Note: Backup files in /boot/ravager-backup-* were preserved.${NC}"
    echo -e "  ${YELLOW}Remove them manually if no longer needed.${NC}"
    echo ""
}

main "$@"
