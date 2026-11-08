#!/usr/bin/env bash
# ==============================================================================
# 21CGS2KH00_s2idle: Modern Standby (s2idle / S0ix) Hardware Fix Installer
# Target Machine: Lenovo ThinkPad T14 Gen 3 AMD (Type 21CGS2KH00)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# 1. Root privilege check
if [ "$EUID" -ne 0 ]; then
    err "This script must be run as root. Re-running with sudo..."
    exec sudo "$0" "$@"
fi

echo -e "${BLUE}==================================================================${NC}"
echo -e "${BLUE}   ThinkPad T14 Gen 3 AMD (21CGS2KH00) s2idle Hardware Fix Setup   ${NC}"
echo -e "${BLUE}==================================================================${NC}"

# 2. Hardware verification check
PRODUCT_NAME="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
SYS_VENDOR="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"

info "Detected Hardware: Vendor='$SYS_VENDOR', Product='$PRODUCT_NAME'"

if [[ "$PRODUCT_NAME" != *"21CG"* ]] && [ "${1:-}" != "--force" ]; then
    warn "This system ($PRODUCT_NAME) does not strictly match ThinkPad T14 Gen 3 AMD (21CG*)."
    echo -n "Do you wish to continue anyway? [y/N]: "
    read -r resp
    if [[ ! "$resp" =~ ^[yY] ]]; then
        info "Aborting installation."
        exit 0
    fi
else
    ok "Hardware match confirmed (Lenovo ThinkPad T14 Gen 3 AMD)."
fi

# 3. Clean up conflicting / obsolete configurations
info "Cleaning up conflicting or obsolete configurations..."

# Remove thinkfan overrides if present (native EC is strictly preferred)
if [ -f /etc/modprobe.d/thinkfan.conf ]; then
    rm -f /etc/modprobe.d/thinkfan.conf
    ok "Removed obsolete /etc/modprobe.d/thinkfan.conf (ensuring native EC fan control)."
fi

# Clean up redundant disable-ac-wakeup service (superseded by disable-usb-wakeup.service)
if systemctl is-enabled disable-ac-wakeup.service &>/dev/null; then
    systemctl disable --now disable-ac-wakeup.service 2>/dev/null || true
    rm -f /etc/systemd/system/disable-ac-wakeup.service
    ok "Removed redundant disable-ac-wakeup.service (consolidated into disable-usb-wakeup)."
fi

# Mask or remove broken thinkfan sleep hooks if lingering
if [ -L /etc/systemd/system/sleep.target.wants/thinkfan-sleep.service ] || [ -L /etc/systemd/system/sleep.target.wants/thinkfan-wakeup.service ]; then
    rm -f /etc/systemd/system/sleep.target.wants/thinkfan-sleep.service 2>/dev/null || true
    rm -f /etc/systemd/system/sleep.target.wants/thinkfan-wakeup.service 2>/dev/null || true
    ok "Cleaned lingering thinkfan sleep.target.wants symlinks."
fi

# 4. Deploy system configuration files
info "Installing configuration files..."

# Udev rules
mkdir -p /etc/udev/rules.d
cp -v "$SCRIPT_DIR"/etc/udev/rules.d/*.rules /etc/udev/rules.d/
chmod 644 /etc/udev/rules.d/*.rules

# Systemd system services
mkdir -p /etc/systemd/system
cp -v "$SCRIPT_DIR"/etc/systemd/system/*.service /etc/systemd/system/
chmod 644 /etc/systemd/system/*.service

# Systemd logind & sleep drop-ins
mkdir -p /etc/systemd/logind.conf.d /etc/systemd/sleep.conf.d
cp -v "$SCRIPT_DIR"/etc/systemd/logind.conf.d/*.conf /etc/systemd/logind.conf.d/
cp -v "$SCRIPT_DIR"/etc/systemd/sleep.conf.d/*.conf /etc/systemd/sleep.conf.d/
chmod 644 /etc/systemd/logind.conf.d/*.conf /etc/systemd/sleep.conf.d/*.conf

# Tmpfiles
mkdir -p /etc/tmpfiles.d
cp -v "$SCRIPT_DIR"/etc/tmpfiles.d/*.conf /etc/tmpfiles.d/
chmod 644 /etc/tmpfiles.d/*.conf

# Modprobe
mkdir -p /etc/modprobe.d
cp -v "$SCRIPT_DIR"/etc/modprobe.d/*.conf /etc/modprobe.d/
chmod 644 /etc/modprobe.d/*.conf

# Environment & KWin
mkdir -p /etc/environment.d
cp -v "$SCRIPT_DIR"/etc/environment.d/*.conf /etc/environment.d/
chmod 644 /etc/environment.d/*.conf

if ! grep -q "KWIN_DRM_NO_DIRECT_SCANOUT=1" /etc/environment 2>/dev/null; then
    echo "KWIN_DRM_NO_DIRECT_SCANOUT=1" >> /etc/environment
    ok "Appended KWIN_DRM_NO_DIRECT_SCANOUT=1 to /etc/environment."
fi

# Helpers & Scripts
mkdir -p /usr/local/bin
cp -v "$SCRIPT_DIR"/bin/fprintd-led-watchdog.py /usr/local/bin/
chmod 755 /usr/local/bin/fprintd-led-watchdog.py

# Systemd user services (system-wide deployment)
mkdir -p /etc/systemd/user/plasma-powerdevil.service.d /etc/systemd/user/default.target.wants
cp -v "$SCRIPT_DIR"/etc/systemd/user/fprintd-led-watchdog.service /etc/systemd/user/
cp -v "$SCRIPT_DIR"/etc/systemd/user/plasma-powerdevil.service.d/*.conf /etc/systemd/user/plasma-powerdevil.service.d/
chmod 644 /etc/systemd/user/fprintd-led-watchdog.service
chmod 644 /etc/systemd/user/plasma-powerdevil.service.d/*.conf

# Enable user watchdog globally across all graphical user sessions
ln -sf /etc/systemd/user/fprintd-led-watchdog.service /etc/systemd/user/default.target.wants/fprintd-led-watchdog.service

ok "All configuration files deployed successfully."

# 5. Reload system state
info "Reloading udev and systemd..."
udevadm control --reload-rules
udevadm trigger --subsystem-match=platform --subsystem-match=i2c --subsystem-match=usb || true

systemd-tmpfiles --create /etc/tmpfiles.d/suspend-sync.conf

systemctl daemon-reload
systemctl enable --now disable-usb-wakeup.service

ok "Daemons and device triggers reloaded."

# 6. Kernel Command-Line Parameters
info "Auditing kernel command-line parameters..."

REQUIRED_ARGS=(
    "amdgpu.dcdebugmask=0x610"
    "amdgpu.abmlevel=0"
    "amdgpu.gpu_recovery=1"
    "acpi.prefer_microsoft_dsm_guid=1"
    "nvme_core.default_ps_max_latency_us=0"
    "workqueue.power_efficient=0"
    "usbcore.quirks=0bda:9201:l,27c6:6594:b"
    "button.lid_init_state=open"
)

CURRENT_CMDLINE="$(cat /proc/cmdline)"
MISSING_ARGS=()

for arg in "${REQUIRED_ARGS[@]}"; do
    key="${arg%%=*}"
    if [[ "$CURRENT_CMDLINE" != *"$key"* ]]; then
        MISSING_ARGS+=("$arg")
    fi
done

if [ ${#MISSING_ARGS[@]} -eq 0 ]; then
    ok "All required kernel arguments are already active in the running kernel."
else
    info "Missing kernel arguments in running kernel: ${MISSING_ARGS[*]}"
    
    # Check for grubby tool (Fedora, RHEL, CentOS)
    if command -v grubby &>/dev/null; then
        info "Applying missing arguments via grubby..."
        for arg in "${MISSING_ARGS[@]}"; do
            grubby --update-kernel=ALL --args="$arg"
        done
        ok "Kernel arguments updated via grubby."
    elif [ -f /etc/default/grub ]; then
        info "Updating /etc/default/grub..."
        # Safely append missing args to GRUB_CMDLINE_LINUX
        for arg in "${MISSING_ARGS[@]}"; do
            if ! grep -q "$arg" /etc/default/grub; then
                sed -i "s/\(GRUB_CMDLINE_LINUX=\".*\)\"/\1 $arg\"/" /etc/default/grub
            fi
        done
        
        # Regenerate grub config
        if command -v update-grub &>/dev/null; then
            update-grub
        elif command -v grub-mkconfig &>/dev/null; then
            if [ -d /boot/grub ]; then
                grub-mkconfig -o /boot/grub/grub.cfg
            elif [ -d /boot/grub2 ]; then
                grub-mkconfig -o /boot/grub2/grub.cfg
            fi
        elif command -v grub2-mkconfig &>/dev/null; then
            grub2-mkconfig -o /boot/grub2/grub.cfg
        fi
        ok "/etc/default/grub updated and configuration regenerated."
    elif [ -f /etc/kernel/cmdline ]; then
        info "Updating systemd-boot /etc/kernel/cmdline..."
        for arg in "${MISSING_ARGS[@]}"; do
            if ! grep -q "$arg" /etc/kernel/cmdline; then
                echo -n " $arg" >> /etc/kernel/cmdline
            fi
        done
        ok "/etc/kernel/cmdline updated."
    else
        warn "Could not automatically determine bootloader configuration tool."
        warn "Please ensure the following arguments are appended to your bootloader configuration:"
        echo -e "${YELLOW}${REQUIRED_ARGS[*]}${NC}"
    fi
fi

# 7. Check KDE PowerDevil user configuration
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    POWERDEVIL_RC="$USER_HOME/.config/powerdevilrc"
    if [ -f "$POWERDEVIL_RC" ]; then
        if grep -qi "keyboardbrightness" "$POWERDEVIL_RC"; then
            info "Purging keyboardbrightness restoration from $POWERDEVIL_RC to prevent EC resume locks..."
            sed -i '/keyboardbrightness/d' "$POWERDEVIL_RC"
            ok "Cleaned $POWERDEVIL_RC."
        fi
    fi
fi

echo -e "${GREEN}==================================================================${NC}"
echo -e "${GREEN}   Installation complete! Hardware is configured for clean s2idle. ${NC}"
echo -e "${GREEN}==================================================================${NC}"
