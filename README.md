# 21CGS2KH00_s2idle

Hardware quirks and sleep/wake fixes for the Lenovo ThinkPad T14 Gen 3 AMD (`21CGS2KH00`).

## Overview

AMD Rembrandt mobile processors (Ryzen 6000 series) lack ACPI S3 (Suspend-to-RAM). All low-power states run through `s2idle` (Modern Standby / S0ix).

On Linux, out-of-the-box driver and firmware misalignments on this model cause several regressions:
- eDP panel does not wake when opening the lid (AMDGPU PSR and Panel Replay timeouts).
- NVMe SSD drops off the PCIe bus after deep sleep states.
- Touchscreen and touchpad lock up due to AMD I2C controller runtime suspend.
- Machine wakes in bags when USB devices move or when plugging in AC power.
- Suspend hangs indefinitely when network or FUSE filesystems (such as `rclone`) are mounted.
- Goodix fingerprint reader keeps its LED lit and stays in USB D0 after login.

Running `./run.sh` applies the required kernel parameters, udev rules, systemd units, and desktop environment overrides across any Linux distribution.

## Installation

```bash
git clone https://github.com/evaunit13/21CGS2KH00_s2idle.git
cd 21CGS2KH00_s2idle
sudo ./run.sh
```

A system reboot is required for kernel command-line changes to take effect.

## Fixes Implemented

### Kernel Parameters
| Parameter | Purpose |
| :--- | :--- |
| `amdgpu.dcdebugmask=0x610` | Disables Panel Self Refresh (PSR) and Panel Replay to stop black screens on wake. |
| `amdgpu.abmlevel=0` | Disables Adaptive Backlight Management to prevent PWM flicker. |
| `amdgpu.gpu_recovery=1` | Recovers the GPU automatically if an atomic flip stalls on resume. |
| `acpi.prefer_microsoft_dsm_guid=1` | Uses Microsoft DSM GUID for S0ix handling expected by Lenovo BIOS 1.64. |
| `button.lid_init_state=open` | Prevents the ACPI button driver from initializing the lid as closed. |
| `nvme_core.default_ps_max_latency_us=0` | Clamps APST latency so the NVMe SSD stays in operational power states. |
| `workqueue.power_efficient=0` | Prevents workqueue deferrals during resume. |
| `usbcore.quirks=0bda:9201:l,27c6:6594:b` | Applies `RESET_RESUME` to Goodix fingerprint sensor and Realtek bridge. |

### System & Userspace
- **Touch & I2C (`80-i2c-touch-power.rules`):** Forces AMD I2C host (`AMDI0010:*`) and ELAN touchscreen into D0, avoiding interrupt deadlocks.
- **Touchpad Wake (`70-touchpad-disable-wake.rules`):** Disables touchpad ACPI wakeup to prevent accidental resume.
- **Fingerprint Reader (`50-goodix.rules`, `fprintd-led-watchdog.py`):** Enables USB autosuspend after 2 seconds and stops `fprintd` upon unlock so the LED turns off.
- **USB & AC Wake (`disable-usb-wakeup.service`):** Clears wake flags on `XHC0`–`XHC4` and `ACDC` in `/proc/acpi/wakeup`.
- **Lid Policy (`lid.conf`):** Enforces suspend on lid close with a 3-second holdoff and overrides lingering inhibitors.
- **Sleep Mode (`disable-hibernate.conf`):** Disables hibernation and hybrid sleep, exposing only `s2idle`.
- **FUSE / Task Freeze (`suspend-sync.conf`):** Disables `sync_on_suspend` and reduces `pm_freeze_timeout` to 3000 ms.
- **KWin Display Wake (`10-kwin.conf`):** Sets `KWIN_DRM_NO_DIRECT_SCANOUT=1` to prevent atomic commit deadlocks on resume.
- **PowerDevil (`override.conf`):** Sets `POWERDEVIL_NO_DDCUTIL=1` to prevent DDC/CI probe hangs on the internal display.

## Fan Control

This repository deliberately omits `thinkfan`. On Rembrandt ThinkPads, writing fan speeds to `/proc/acpi/ibm/fan` triggers SMIs via I/O port `0xB2` that freeze CPU cores. Fan management is left to Lenovo Embedded Controller firmware via ACPI platform profiles (`low-power`, `balanced`, `performance`).
