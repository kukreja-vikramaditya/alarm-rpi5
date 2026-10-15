# alarm-rpi5

Build an [Arch Linux ARM](https://archlinuxarm.org/) image for the **Raspberry Pi 5** from source — flashable via [Raspberry Pi Imager](https://www.raspberrypi.com/software/).

No third-party installers, no random GitHub projects. Just `pacstrap`, the official ALARM repos, and standard Linux tooling.

## What this produces

A compressed raw disk image:

```
dist/alarm-rpi5-0.1.0-20261015.img.xz
```

Flash it with RPi Imager → **"Use custom"**, or with `dd`:

```bash
xzcat dist/alarm-rpi5-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress
```

## Requirements

An **x86_64 Arch Linux** host (bare metal, VM, or container).

```bash
sudo pacman -S --needed \
  qemu-user-static qemu-user-static-binfmt \
  arch-install-scripts \
  dosfstools e2fsprogs \
  parted xz gum

sudo systemctl restart systemd-binfmt.service
```

## Quick start

```bash
git clone <this-repo> && cd alarm-rpi5
sudo ./build-alarm-rpi5.sh
```

Output lands in `dist/`. That's it.

## Project Structure

The project is structured modularly with a single root entry point:

```
alarm-rpi5/
├── build-alarm-rpi5.sh      # Primary root entry point
├── build.sh                 # Convenience alias symlink
├── src/
│   ├── ui.sh                # Terminal UI styling, Gum detection, logging, spinners
│   ├── cleanup.sh           # Safe EXIT/INT/TERM trap handler & idempotent cleanup
│   ├── cli.sh               # Command line argument parser & usage help
│   ├── config.sh            # Defaults, environment overrides, path calculation
│   ├── wizard.sh            # Interactive setup wizards (Charm Gum + pure Bash fallback)
│   ├── doctor.sh            # Environment diagnostics (--check) & preflight checks
│   └── build.sh             # 5-phase image builder, pacstrap, chroot config & shrink
├── tests/
│   └── test_cli.sh          # Automated test suite (45 checks)
└── dist/                    # Default output directory for generated images (.img.xz)
```

## Usage

```
sudo ./build-alarm-rpi5.sh [OPTIONS]

Options:
  -c, --check              Check host environment and dependencies without building
  -i, --interactive        Run interactive configuration wizard (default on TTY)
  -y, --non-interactive    Bypass interactive prompts and use defaults/flags
  -o, --output-dir DIR     Output directory       (default: ./dist)
  -v, --version VER        Image version string   (default: 0.1.0)
  -s, --img-size SIZE      Raw image size         (default: 4G)
      --hostname NAME      Target hostname        (default: raspberrypi)
      --no-compress        Skip xz compression
      --no-gum             Disable Gum styling and interactive elements
  -h, --help               Show help
```

### Examples

```bash
# Check if host environment has required tools & setup
./build-alarm-rpi5.sh --check

# Default build (launches interactive wizard automatically on terminal)
sudo ./build-alarm-rpi5.sh

# Non-interactive / unattended build (uses defaults or flags immediately)
sudo ./build-alarm-rpi5.sh -y

# Custom version and output
sudo ./build-alarm-rpi5.sh -v 1.0.0 -o /mnt/images

# Larger image with extra packages
IMG_SIZE=8G EXTRA_PACKAGES="git htop vim" sudo ./build-alarm-rpi5.sh

# Skip compression for faster iteration
sudo ./build-alarm-rpi5.sh --no-compress

# Override hostname, timezone, and user credentials
TARGET_HOSTNAME=mypi TIMEZONE=Asia/Kolkata ALARM_USER=vikram ALARM_PASSWORD=secret \
  sudo ./build-alarm-rpi5.sh
```

## Environment variables

All config has sensible defaults. Flags take precedence over environment variables.

| Variable | Default | Description |
|----------|---------|-------------|
| `IMG_SIZE` | `4G` | Raw image size before shrinking (fits on any SD card >=4GB) |
| `VERSION` | `0.1.0` | Embedded in output filename |
| `IMG_NAME` | `alarm-rpi5-{ver}-{date}` | Full override for output filename |
| `BOOT_SIZE_MIB` | `256` | Boot partition size in MiB |
| `TARGET_HOSTNAME` | `raspberrypi` | System hostname |
| `ROOT_PASSWORD` | `root` | Root password |
| `ALARM_USER` | `alarm` | Non-root user (wheel group) |
| `ALARM_PASSWORD` | `alarm` | Non-root user password |
| `TIMEZONE` | `UTC` | System timezone |
| `LOCALE` | `en_US.UTF-8` | System locale |
| `EXTRA_PACKAGES` | *(empty)* | Space-separated list of extra pacman packages |
| `ALARM_MIRROR` | `http://mirror.archlinuxarm.org` | ALARM mirror URL |
| `COMPRESS` | `1` | Set to `0` to skip xz compression |

## Flashing

### Raspberry Pi Imager (recommended)

1. Open Raspberry Pi Imager
2. **Choose OS** → scroll to bottom → **Use custom**
3. Select `dist/alarm-rpi5-*.img.xz`
4. **Choose Storage** → select your SD card
5. **Write**

> **Note:** The OS Customization dialog (Wi-Fi, SSH, hostname) is disabled for custom images. SSH and NetworkManager are pre-enabled in the image; connect via Ethernet on first boot.

### dd

```bash
xzcat dist/alarm-rpi5-0.1.0-20261015.img.xz | sudo dd of=/dev/sdX bs=4M status=progress
sync
```

### NVMe

The Pi 5 supports NVMe boot natively. Flash to your NVMe drive instead of SD, and edit `fstab` + `cmdline.txt` on the boot partition to replace `mmcblk0p*` with `nvme0n1p*`.

## First boot

1. Insert the SD card, connect Ethernet, power on
2. Find the Pi's IP from your router or use `nmap -sn 192.168.1.0/24`
3. SSH in:
   ```bash
   ssh alarm@<ip>       # password: alarm
   # or
   ssh root@<ip>            # password: root
   # or using hostname:
   ssh alarm@raspberrypi.local
   ```
4. Update immediately:
   ```bash
   sudo pacman -Syu
   ```
5. Change default passwords:
   ```bash
   passwd                  # change alarm's password
   sudo passwd root        # change root's password
   ```

## What's inside

The image ships with a minimal set of packages:

| Package | Why |
|---------|-----|
| `base` | Core Arch system |
| `linux-rpi` | RPi Foundation kernel with BCM2712 (Pi 5) support |
| `raspberrypi-firmware` | Boot firmware (`start4.elf`, device trees) |
| `archlinuxarm-keyring` | Package signing keys |
| `openssh` | Remote access (enabled by default) |
| `networkmanager` + `iwd` | Wired and wireless networking |
| `sudo` | Privilege escalation |
| `nano` | Text editor |

## How it works

```
x86_64 Host
    │
    ├─ truncate + parted → raw .img with MBR (FAT32 boot + ext4 root)
    ├─ losetup --partscan → attach as /dev/loopNpX
    ├─ qemu-user-static + binfmt_misc → transparent aarch64 emulation
    ├─ pacstrap → install ALARM packages into the image
    ├─ arch-chroot → configure locale, users, services, keyring
    ├─ resize2fs -M → shrink ext4 to minimum
    └─ xz -9 → compress for distribution
```

No U-Boot (Pi 5 can't use it). The boot chain is:

```
Pi 5 EEPROM → start4.elf → config.txt → linux-rpi kernel → systemd
```

## Source provenance

| Component | Source | License |
|-----------|--------|---------|
| Root filesystem | [archlinuxarm.org](https://archlinuxarm.org) repos | Various FOSS |
| Kernel (`linux-rpi`) | [archlinuxarm/PKGBUILDs](https://github.com/archlinuxarm/PKGBUILDs) | GPL-2.0 |
| Device trees | [raspberrypi/linux](https://github.com/raspberrypi/linux) | GPL-2.0 |
| Boot firmware | [raspberrypi/firmware](https://github.com/raspberrypi/firmware) | Broadcom proprietary ¹ |
| Build tooling | `pacstrap`, `qemu-user-static`, `parted` | GPL |

¹ The VideoCore GPU firmware blobs are proprietary Broadcom binaries. **Every** OS that boots on real Pi hardware uses them — there is no open-source alternative. This is a hardware requirement, not a software choice.

## Optional: build the kernel from source

If you want to compile `linux-rpi` yourself instead of using the ALARM binary:

```bash
# Clone ALARM's PKGBUILDs
git clone https://github.com/archlinuxarm/PKGBUILDs.git
cd PKGBUILDs/core/linux-rpi

# Build (native on Pi 5: ~60-90 min; under qemu: longer)
makepkg -s

# The PKGBUILD uses bcm2712_defconfig for Pi 5
# Output: linux-rpi-*.pkg.tar.zst
```

Or build directly from the RPi Foundation kernel tree:

```bash
git clone --depth=1 https://github.com/raspberrypi/linux.git -b rpi-6.6.y
cd linux
make ARCH=arm64 bcm2712_defconfig
make ARCH=arm64 -j$(nproc) Image modules dtbs
```

## Testing

Run the automated test suite:

```bash
./tests/test_cli.sh
```

To run diagnostic checks on your host system:

```bash
./build-alarm-rpi5.sh --check
```

## License

The build script in this repository is released under the [MIT License](LICENSE). The software it assembles is governed by its respective upstream licenses.
