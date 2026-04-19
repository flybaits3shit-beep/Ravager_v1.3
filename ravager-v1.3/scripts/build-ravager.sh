#!/usr/bin/env bash
# ============================================================================
# Ravager v1.3 — Auto-Build Script
# Dell Latitude 3120 Custom Kernel (6.9.0-AnarchyRavager-v1.3)
# Rain's Computer Resurrection — Loris, SC
# ============================================================================
#
# Usage:
#   ./build-ravager.sh [mode]
#
# Modes:
#   full        — Complete pipeline: deps → download → patch → config → build
#   deps        — Install build dependencies only
#   download    — Download and verify kernel source only
#   patch       — Apply Ravager patches only
#   config      — Load defconfig only
#   build       — Compile kernel only
#   install     — Run install script (calls install-ravager.sh)
#   menuconfig  — Interactive kernel configuration (ncurses)
#   clean       — Remove build artifacts, keep source
#   distclean   — Remove everything including source
#   info        — Print build environment info
#
# Requirements:
#   - Ubuntu/Debian-based system (KDE Neon)
#   - Root not required for build (only for install)
#   - ~25GB free disk space for build
#   - Internet connection for source download
#
# ============================================================================

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# CONSTANTS
# ============================================================================
readonly KERNEL_MAJOR="6"
readonly KERNEL_MINOR="9"
readonly KERNEL_PATCH="0"
readonly KERNEL_VERSION="${KERNEL_MAJOR}.${KERNEL_MINOR}.${KERNEL_PATCH}"
readonly EXTRAVERSION="-AnarchyRavager-v1.3"
readonly FULL_VERSION="${KERNEL_VERSION}${EXTRAVERSION}"
readonly KERNEL_NAME="Ravager v1.3"

readonly KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${KERNEL_VERSION}.tar.xz"
readonly KERNEL_SIG_URL="${KERNEL_URL}.sign"
readonly KERNEL_SHA_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/sha256sums.asc"

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
readonly BUILD_DIR="${PROJECT_DIR}/build"
readonly SOURCE_DIR="${BUILD_DIR}/linux-${KERNEL_VERSION}"
readonly PATCHES_DIR="${PROJECT_DIR}/patches"
readonly CONFIGS_DIR="${PROJECT_DIR}/configs"
readonly DEFCONFIG="ravager_v1.3_defconfig"
readonly LOG_DIR="${PROJECT_DIR}/logs"
readonly LOG_FILE="${LOG_DIR}/build-$(date +%Y%m%d-%H%M%S).log"

readonly KBUILD_BUILD_USER="ravager"
readonly KBUILD_BUILD_HOST="AnarchyRavager"

# Build parallelism — use all cores + 1
readonly NPROC="$(( $(nproc) + 1 ))"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# ============================================================================
# BANNER
# ============================================================================
print_banner() {
    echo -e "${MAGENTA}"
    cat << 'BANNER'
    ██████╗  █████╗ ██╗   ██╗ █████╗  ██████╗ ███████╗██████╗
    ██╔══██╗██╔══██╗██║   ██║██╔══██╗██╔════╝ ██╔════╝██╔══██╗
    ██████╔╝███████║██║   ██║███████║██║  ███╗█████╗  ██████╔╝
    ██╔══██╗██╔══██║╚██╗ ██╔╝██╔══██║██║   ██║██╔══╝  ██╔══██╗
    ██║  ██║██║  ██║ ╚████╔╝ ██║  ██║╚██████╔╝███████╗██║  ██║
    ╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝
BANNER
    echo -e "${CYAN}    Kernel v1.3 — Dell Latitude 3120 — Jasper Lake Tremont${NC}"
    echo -e "${WHITE}    6.9.0-AnarchyRavager-v1.3${NC}"
    echo -e "${YELLOW}    Rain's Computer Resurrection — Loris, SC${NC}"
    echo ""
}

# ============================================================================
# LOGGING
# ============================================================================
setup_logging() {
    mkdir -p "${LOG_DIR}"
    exec > >(tee -a "${LOG_FILE}") 2>&1
    log_info "Log file: ${LOG_FILE}"
}

log_info()    { echo -e "${GREEN}[INFO]${NC}    $(date +%H:%M:%S) — $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $(date +%H:%M:%S) — $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $(date +%H:%M:%S) — $*"; }
log_phase()   { echo -e "\n${MAGENTA}══════════════════════════════════════════════════════════════${NC}"; echo -e "${MAGENTA}  PHASE: $*${NC}"; echo -e "${MAGENTA}══════════════════════════════════════════════════════════════${NC}\n"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $(date +%H:%M:%S) — $*"; }

# ============================================================================
# ERROR HANDLING
# ============================================================================
cleanup_on_error() {
    local exit_code=$?
    if [ ${exit_code} -ne 0 ]; then
        log_error "Build failed with exit code ${exit_code}"
        log_error "Check log: ${LOG_FILE}"
        log_error "Last 20 lines of build output:"
        tail -20 "${LOG_FILE}" 2>/dev/null || true
    fi
}
trap cleanup_on_error EXIT

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================
check_disk_space() {
    local required_gb=25
    local available_kb
    available_kb=$(df --output=avail "${PROJECT_DIR}" | tail -1)
    local available_gb=$(( available_kb / 1048576 ))

    if [ "${available_gb}" -lt "${required_gb}" ]; then
        log_error "Insufficient disk space: ${available_gb}GB available, ${required_gb}GB required"
        exit 1
    fi
    log_info "Disk space: ${available_gb}GB available (${required_gb}GB required)"
}

check_internet() {
    if ! ping -c 1 -W 5 cdn.kernel.org &>/dev/null; then
        log_error "Cannot reach cdn.kernel.org — check internet connection"
        exit 1
    fi
    log_info "Internet connectivity: OK"
}

elapsed_time() {
    local start=$1
    local end
    end=$(date +%s)
    local diff=$(( end - start ))
    local mins=$(( diff / 60 ))
    local secs=$(( diff % 60 ))
    echo "${mins}m ${secs}s"
}

# ============================================================================
# PHASE 1: INSTALL DEPENDENCIES
# ============================================================================
phase_deps() {
    log_phase "PHASE 1: Installing Build Dependencies"

    local packages=(
        build-essential
        bc
        bison
        flex
        libssl-dev
        libelf-dev
        libncurses-dev
        dwarves
        ccache
        cpio
        lz4
        xz-utils
        wget
        gnupg2
        fakeroot
        debhelper
        rsync
        kmod
        python3
    )

    log_info "Updating package lists..."
    sudo apt-get update -qq

    log_info "Installing ${#packages[@]} packages..."
    sudo apt-get install -y -qq "${packages[@]}"

    # Verify critical tools
    local tools=("gcc" "make" "bc" "bison" "flex" "ccache" "lz4")
    for tool in "${tools[@]}"; do
        if ! command -v "${tool}" &>/dev/null; then
            log_error "Required tool not found: ${tool}"
            exit 1
        fi
    done

    # Setup ccache
    if command -v ccache &>/dev/null; then
        export PATH="/usr/lib/ccache:${PATH}"
        ccache --max-size=10G 2>/dev/null || true
        log_info "ccache enabled (max 10GB)"
    fi

    log_info "GCC version: $(gcc --version | head -1)"
    log_info "Make version: $(make --version | head -1)"

    log_success "Phase 1 complete — all dependencies installed"
}

# ============================================================================
# PHASE 2: DOWNLOAD AND VERIFY KERNEL SOURCE
# ============================================================================
phase_download() {
    log_phase "PHASE 2: Preparing Linux ${KERNEL_VERSION} Source"

    cd "${BUILD_DIR}"

    # We are skipping all file checks and just looking for the 1.4GB folder
    if [ -d "${SOURCE_DIR}" ]; then
        log_info "Source directory found: ${SOURCE_DIR}"
    else
        log_error "Source directory not found! Ensure the 1.4GB folder is named ${SOURCE_DIR}"
        exit 1
    fi

    if [ ! -f "${SOURCE_DIR}/Makefile" ]; then
        log_error "Makefile not found in ${SOURCE_DIR}"
        exit 1
    fi

    log_success "Phase 2 complete — Ready for Jasper Lake patches"
}
# ============================================================================
# PHASE 3: APPLY RAVAGER PATCHES
# ============================================================================
phase_patch() {
    log_phase "PHASE 3: Applying Ravager Patches"

    cd "${SOURCE_DIR}"

    # Apply EXTRAVERSION via sed first (failsafe)
    log_info "Setting EXTRAVERSION = ${EXTRAVERSION} (sed failsafe)..."
    sed -i "s/^EXTRAVERSION =.*/EXTRAVERSION = ${EXTRAVERSION}/" Makefile

    # Verify EXTRAVERSION was set
    if grep -q "^EXTRAVERSION = ${EXTRAVERSION}" Makefile; then
        log_success "EXTRAVERSION verified in Makefile"
    else
        log_error "Failed to set EXTRAVERSION in Makefile"
        exit 1
    fi

    # Set build identity
    # export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-rain}" || true
    # export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-NeonAnarchy}" || true
    # log_info "Build identity: ${KBUILD_BUILD_USER}@${KBUILD_BUILD_HOST}"
   
    # Apply patch files
    local patch_count=0
    for patch in "${PATCHES_DIR}"/*.patch; do
        if [ -f "${patch}" ]; then
            local pname
            pname=$(basename "${patch}")
            log_info "Applying patch: ${pname}..."

            if patch --dry-run -p1 -N < "${patch}" &>/dev/null; then
                patch -p1 -N < "${patch}"
                log_success "Applied: ${pname}"
                patch_count=$(( patch_count + 1 ))
            else
                log_warn "Patch already applied or conflicts: ${pname} — skipping"
            fi
        fi
    done

    log_info "Applied ${patch_count} patches"

    local version_check
    version_check=$(make -s kernelversion 2>/dev/null || echo "unknown")
    log_info "Kernel version after patching: ${version_check}${EXTRAVERSION}"

    log_success "Phase 3 complete — all patches applied"
}

# ============================================================================
# PHASE 4: CONFIGURE KERNEL
# ============================================================================
phase_config() {
    log_phase "PHASE 4: Loading Ravager Defconfig"

    cd "${SOURCE_DIR}"

    local defconfig_path="${CONFIGS_DIR}/${DEFCONFIG}"

    if [ ! -f "${defconfig_path}" ]; then
        log_error "Defconfig not found: ${defconfig_path}"
        exit 1
    fi

    cp "${defconfig_path}" "arch/x86/configs/${DEFCONFIG}"
    log_info "Copied ${DEFCONFIG} to arch/x86/configs/"

    log_info "Loading defconfig..."
    make "${DEFCONFIG}" \
        KBUILD_BUILD_USER="${KBUILD_BUILD_USER}" \
        KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST}"

    log_info "Validating critical Ravager config options..."
    local critical_configs=(
        "CONFIG_LOCALVERSION=\"${EXTRAVERSION}\""
        "CONFIG_MATOM=y"
        "CONFIG_PREEMPT=y"
        "CONFIG_HZ_1000=y"
        "CONFIG_DRM_I915=y"
        "CONFIG_IOSCHED_BFQ=y"
        "CONFIG_DEFAULT_BFQ=y"
        "CONFIG_KERNEL_LZ4=y"
        "CONFIG_ZSWAP=y"
        "CONFIG_ZRAM=m"
        "CONFIG_IWLWIFI=m"
        "CONFIG_IWLMVM=m"
        "CONFIG_SND_HDA_INTEL=y"
        "CONFIG_SECURITY_APPARMOR=y"
    )

    local failed=0
    for config in "${critical_configs[@]}"; do
        local key="${config%%=*}"
        if grep -q "^${config}" .config; then
            log_info "  ✓ ${config}"
        else
            log_warn "  ✗ ${config} — NOT FOUND (may need menuconfig)"
            failed=$(( failed + 1 ))
        fi
    done

    if [ "${failed}" -gt 0 ]; then
        log_warn "${failed} config options not found — consider running menuconfig"
    else
        log_success "All critical config options verified"
    fi

    log_success "Phase 4 complete — kernel configured"
}

# ============================================================================
# PHASE 5: BUILD KERNEL
# ============================================================================
phase_build() {
    log_phase "PHASE 5: Building Ravager Kernel"

    cd "${SOURCE_DIR}"

    local build_start
    build_start=$(date +%s)

    if command -v ccache &>/dev/null; then
        export PATH="/usr/lib/ccache:${PATH}"
        log_info "ccache: enabled"
    fi

   # export KBUILD_BUILD_USER="${KBUILD_BUILD_USER}"
   # export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST}"

    log_info "Building bzImage (${NPROC} parallel jobs)..."
    make -j"${NPROC}" bzImage \
        LOCALVERSION="" \
        KBUILD_BUILD_USER="${KBUILD_BUILD_USER}" \
        KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST}"

    if [ ! -f "arch/x86/boot/bzImage" ]; then
        log_error "bzImage not found — kernel build failed"
        exit 1
    fi

    local image_size
    image_size=$(stat -c%s "arch/x86/boot/bzImage")
    log_info "bzImage size: $(( image_size / 1024 ))KB"

    log_info "Building modules (${NPROC} parallel jobs)..."
    make -j"${NPROC}" modules \
        LOCALVERSION="" \
        KBUILD_BUILD_USER="${KBUILD_BUILD_USER}" \
        KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST}"

    log_info "Staging modules..."
    local staging_dir="${BUILD_DIR}/staging"
    rm -rf "${staging_dir}"
    mkdir -p "${staging_dir}"

    make modules_install \
        INSTALL_MOD_PATH="${staging_dir}" \
        LOCALVERSION="" \
        KBUILD_BUILD_USER="${KBUILD_BUILD_USER}" \
        KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST}"

    local mod_count
    mod_count=$(find "${staging_dir}" -name "*.ko" 2>/dev/null | wc -l)
    log_info "Modules built: ${mod_count}"

    log_info "Staging kernel headers..."
    make headers_install \
        INSTALL_HDR_PATH="${staging_dir}/usr" \
        LOCALVERSION="" 2>/dev/null || true

    local elapsed
    elapsed=$(elapsed_time "${build_start}")

    echo ""
    log_success "═══════════════════════════════════════════════════"
    log_success "  RAVAGER v1.3 BUILD COMPLETE"
    log_success "  Version:  ${FULL_VERSION}"
    log_success "  Image:    arch/x86/boot/bzImage ($(( image_size / 1024 ))KB)"
    log_success "  Modules:  ${mod_count}"
    log_success "  Time:     ${elapsed}"
    log_success "  Staging:  ${staging_dir}"
    log_success "═══════════════════════════════════════════════════"
    echo ""
    log_info "Next step: sudo ./scripts/install-ravager.sh"
}

# ============================================================================
# MENUCONFIG
# ============================================================================
phase_menuconfig() {
    log_phase "Interactive Kernel Configuration"

    cd "${SOURCE_DIR}"

    if [ ! -f ".config" ]; then
        log_info "No .config found — loading defconfig first..."
        phase_config
    fi

    log_info "Launching menuconfig..."
    make menuconfig \
        KBUILD_BUILD_USER="${KBUILD_BUILD_USER}" \
        KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST}"

    log_info "Configuration saved. Run './build-ravager.sh build' to compile."
}

# ============================================================================
# CLEAN
# ============================================================================
phase_clean() {
    log_phase "Cleaning Build Artifacts"

    if [ -d "${SOURCE_DIR}" ]; then
        cd "${SOURCE_DIR}"
        make clean 2>/dev/null || true
        log_info "Kernel build artifacts cleaned"
    fi

    rm -rf "${BUILD_DIR}/staging"
    log_info "Staging directory removed"

    log_success "Clean complete — source tree preserved"
}

phase_distclean() {
    log_phase "Full Clean (Removing Everything)"

    rm -rf "${BUILD_DIR}"
    rm -rf "${LOG_DIR}"
    log_success "Distclean complete — all build files removed"
}

# ============================================================================
# INFO
# ============================================================================
phase_info() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Ravager v1.3 — Build Environment${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Kernel:        ${WHITE}${FULL_VERSION}${NC}"
    echo -e "  Source URL:    ${KERNEL_URL}"
    echo -e "  Build user:    ${KBUILD_BUILD_USER}@${KBUILD_BUILD_HOST}"
    echo -e "  Project dir:   ${PROJECT_DIR}"
    echo -e "  Build dir:     ${BUILD_DIR}"
    echo -e "  Source dir:    ${SOURCE_DIR}"
    echo -e "  Patches dir:   ${PATCHES_DIR}"
    echo -e "  Configs dir:   ${CONFIGS_DIR}"
    echo -e "  Defconfig:     ${DEFCONFIG}"
    echo -e "  Parallel jobs: ${NPROC}"
    echo ""
    echo -e "  ${WHITE}Host System:${NC}"
    echo -e "  OS:            $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
    echo -e "  Kernel:        $(uname -r)"
    echo -e "  GCC:           $(gcc --version 2>/dev/null | head -1 || echo 'not installed')"
    echo -e "  Make:          $(make --version 2>/dev/null | head -1 || echo 'not installed')"
    echo -e "  ccache:        $(ccache --version 2>/dev/null | head -1 || echo 'not installed')"
    echo -e "  CPU cores:     $(nproc)"
    echo -e "  RAM:           $(free -h | awk '/Mem:/{print $2}')"
    echo -e "  Disk free:     $(df -h "${PROJECT_DIR}" | awk 'NR==2{print $4}')"
    echo ""

    if [ -d "${SOURCE_DIR}" ]; then
        echo -e "  ${GREEN}Source tree: PRESENT${NC}"
        if [ -f "${SOURCE_DIR}/.config" ]; then
            echo -e "  ${GREEN}Config: LOADED${NC}"
        else
            echo -e "  ${YELLOW}Config: NOT LOADED${NC}"
        fi
        if [ -f "${SOURCE_DIR}/arch/x86/boot/bzImage" ]; then
            echo -e "  ${GREEN}bzImage: BUILT${NC}"
        else
            echo -e "  ${YELLOW}bzImage: NOT BUILT${NC}"
        fi
    else
        echo -e "  ${YELLOW}Source tree: NOT DOWNLOADED${NC}"
    fi
    echo ""
}

# ============================================================================
# FULL PIPELINE
# ============================================================================
phase_full() {
    local start_time
    start_time=$(date +%s)

    print_banner
    check_disk_space
    check_internet

    phase_deps
    phase_download
    phase_patch
    phase_config
    phase_build

    local total_elapsed
    total_elapsed=$(elapsed_time "${start_time}")

    echo ""
    echo -e "${MAGENTA}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  RAVAGER v1.3 — FULL BUILD PIPELINE COMPLETE${NC}"
    echo -e "${MAGENTA}  Total time: ${total_elapsed}${NC}"
    echo -e "${MAGENTA}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Next: ${WHITE}sudo ./scripts/install-ravager.sh${NC}"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    local mode="${1:-full}"

    setup_logging

    case "${mode}" in
        full)       phase_full ;;
        deps)       print_banner; phase_deps ;;
        download)   print_banner; phase_download ;;
        patch)      print_banner; phase_patch ;;
        config)     print_banner; phase_config ;;
        build)      print_banner; phase_build ;;
        install)
            print_banner
            if [ -f "${SCRIPT_DIR}/install-ravager.sh" ]; then
                sudo "${SCRIPT_DIR}/install-ravager.sh"
            else
                log_error "install-ravager.sh not found in ${SCRIPT_DIR}"
                exit 1
            fi
            ;;
        menuconfig) print_banner; phase_menuconfig ;;
        clean)      print_banner; phase_clean ;;
        distclean)  print_banner; phase_distclean ;;
        info)       print_banner; phase_info ;;
        *)
            print_banner
            echo "Usage: $0 {full|deps|download|patch|config|build|install|menuconfig|clean|distclean|info}"
            echo ""
            echo "Modes:"
            echo "  full        Complete pipeline (deps → download → patch → config → build)"
            echo "  deps        Install build dependencies only"
            echo "  download    Download and verify kernel source only"
            echo "  patch       Apply Ravager patches only"
            echo "  config      Load defconfig only"
            echo "  build       Compile kernel only"
            echo "  install     Install kernel to system (requires root)"
            echo "  menuconfig  Interactive kernel configuration"
            echo "  clean       Remove build artifacts, keep source"
            echo "  distclean   Remove everything including source"
            echo "  info        Print build environment info"
            exit 1
            ;;
    esac
}

main "$@"
