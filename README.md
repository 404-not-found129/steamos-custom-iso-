# Custom SteamOS ISO — NVIDIA Edition

A custom Arch-based live ISO modelled after SteamOS, with NVIDIA proprietary drivers (`nvidia-dkms`) pre-baked into the image and initramfs. Built using the [archiso](https://wiki.archlinux.org/title/Archiso) framework.

---

## Features

- NVIDIA proprietary drivers (`nvidia-dkms`, `nvidia-utils`, `lib32-nvidia-utils`) installed out-of-the-box
- DRM kernel mode-setting enabled by default (`nvidia-drm.modeset=1`) — required for Wayland and gamescope
- `nouveau` blacklisted to prevent driver conflicts
- NVIDIA modules baked into the initramfs (early KMS)
- Dual boot entries: **NVIDIA (recommended)** and **Fallback (nomodeset)**
- Supports UEFI (systemd-boot), BIOS/MBR (GRUB2 + Syslinux)
- Steam, gamescope, MangoHud, and Pipewire pre-installed
- Minimal KDE Plasma desktop (mirrors SteamOS Session)

---

## Requirements

### Build Host

| Requirement | Minimum |
|-------------|---------|
| OS | Arch Linux (or Arch-based: Manjaro, EndeavourOS, etc.) |
| Disk space | **20 GB** free |
| RAM | 4 GB (8 GB recommended) |
| CPU | x86\_64, any modern CPU |
| Privileges | **root** (`sudo`) |

### Build Dependencies (auto-installed by `build.sh`)

- `archiso`
- `arch-install-scripts`
- `libisoburn` (xorriso)
- `squashfs-tools`
- `dosfstools`
- `mtools`

---

## Project Structure

```
custom_steamosiso/
├── build.sh                              # Main build automation script
├── profile/
│   ├── profiledef.sh                     # archiso profile definition
│   ├── pacman.conf                       # pacman config (includes multilib)
│   ├── packages.x86_64                   # Full package list
│   ├── airootfs/
│   │   └── etc/
│   │       ├── mkinitcpio.conf           # NVIDIA modules in initramfs
│   │       ├── modules-load.d/
│   │       │   └── nvidia.conf           # systemd module autoload
│   │       └── modprobe.d/
│   │           ├── nvidia.conf           # DRM modeset + power options
│   │           └── blacklist-nouveau.conf
│   ├── efiboot/
│   │   └── loader/
│   │       ├── loader.conf               # systemd-boot config
│   │       └── entries/
│   │           ├── 01-archiso-x86_64-nvidia.conf    # UEFI NVIDIA entry
│   │           └── 02-archiso-x86_64-fallback.conf  # UEFI fallback entry
│   ├── grub/
│   │   └── grub.cfg                      # GRUB2 (BIOS El Torito)
│   └── syslinux/
│       └── archiso_sys-linux.cfg         # Syslinux (BIOS MBR)
├── build/                                # Build workspace (auto-created, gitignored)
├── out/                                  # ISO output directory (gitignored)
└── logs/                                 # Build logs (gitignored)
```

---

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/your-username/custom_steamosiso.git
cd custom_steamosiso
```

### 2. Run the build

```bash
sudo ./build.sh build
```

The script will:
1. Verify you have at least 20 GB of free disk space
2. Install missing build dependencies via pacman
3. Validate the ISO profile
4. Run `mkarchiso` to build the ISO
5. Write a SHA256 checksum file alongside the ISO

Output ISO will be in `./out/`.

---

## Build Script Reference

```
Usage: build.sh [COMMAND]

Commands:
  build     Build the custom SteamOS ISO (default)
  clean     Remove all build artifacts and output
  deps      Install build dependencies only
  validate  Validate the ISO profile without building
```

### Examples

```bash
# Full build
sudo ./build.sh build

# Validate profile only (no root required)
./build.sh validate

# Clean workspace and output
sudo ./build.sh clean

# Pre-install build deps only
sudo ./build.sh deps
```

---

## NVIDIA Configuration Details

### Packages installed

| Package | Purpose |
|---------|---------|
| `nvidia-dkms` | NVIDIA kernel module (DKMS — compiles against any installed kernel) |
| `nvidia-utils` | userspace utilities, OpenGL, Vulkan ICD |
| `lib32-nvidia-utils` | 32-bit compat for Steam (Proton games) |
| `nvidia-settings` | GUI configuration tool |
| `nvtop` | GPU process monitor |

> **Why `nvidia-dkms` and not `nvidia`?**
> The stock `nvidia` package targets the latest mainline kernel. For a custom or
> patched kernel such as `linux-neptune` (Valve's SteamOS kernel), `nvidia-dkms`
> is required — it recompiles the module against whichever kernel-headers are
> present at build/install time.

### Kernel parameters

Set in all three bootloader configs:

```
nvidia-drm.modeset=1   # Enable DRM kernel mode-setting (required for Wayland)
nvidia-drm.fbdev=1     # Expose /dev/fbX via DRM (smooth KMS console)
```

### mkinitcpio modules

Defined in `profile/airootfs/etc/mkinitcpio.conf`:

```bash
MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
```

Loading these modules early (before `udev`) means the NVIDIA driver takes control
of the GPU before the display server starts, which prevents mode-switching artifacts
and enables early KMS.

### nouveau blacklist

`profile/airootfs/etc/modprobe.d/blacklist-nouveau.conf` blocks the open-source
`nouveau` driver and its framebuffer aliases. Without this, the kernel may
auto-load `nouveau` on first boot before `nvidia`, causing a conflict.

---

## Optional: linux-neptune Kernel

To use Valve's patched kernel (closer to real SteamOS):

1. Uncomment the `[holoiso-main]` repository block in `profile/pacman.conf`
2. Replace the kernel packages in `profile/packages.x86_64`:

```diff
-linux
-linux-headers
+linux-neptune
+linux-neptune-headers
```

> **Note:** The HoloISO repository packages are unsigned. Review them before use in production.

---

## Flashing the ISO

### Linux — dd

```bash
sudo dd if=out/custom-steamosiso-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Replace `/dev/sdX` with your target USB device (verify with `lsblk` first).

### Linux — Ventoy

[Ventoy](https://www.ventoy.net) supports this ISO out-of-the-box. Simply copy the `.iso` file to your Ventoy drive.

### Windows — Rufus

Use **Rufus** in **DD image** mode (not ISO mode) for best compatibility.

---

## Verifying the ISO

```bash
sha256sum -c out/custom-steamosiso-*.iso.sha256
```

---

## Troubleshooting

### Black screen after boot

The NVIDIA driver failed to initialize. At the boot menu, select the **Fallback** entry (passes `nomodeset`). Once booted, run:

```bash
sudo nvidia-check.sh
```

### nvidia-dkms fails to build

The DKMS build requires matching kernel headers. Verify:

```bash
pacman -Q linux linux-headers nvidia-dkms
```

All three should report the same kernel version.

### Wayland session not available

Confirm DRM modeset is active:

```bash
cat /sys/module/nvidia_drm/parameters/modeset
# Expected: Y
```

If it shows `N`, ensure `nvidia-drm.modeset=1` is in your kernel parameters and reboot.

---

## Contributing

Pull requests are welcome. When modifying the package list, boot entries, or mkinitcpio config, test the full build before submitting. Attach the relevant section of `logs/build_*.log` if reporting a build failure.

---

## License

MIT — see [LICENSE](LICENSE) for details.
