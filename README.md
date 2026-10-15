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

## Default Usernames & Passwords

The built image is pre-configured with default credentials and passwordless `sudo` privileges for the `wheel` group:

| Account | Username | Default Password | Privileges / Group | SSH Access |
| :--- | :--- | :--- | :--- | :--- |
| **Standard User** | `alarm` | `alarm` | `wheel` (`sudo` privileges) | Enabled |
| **Root User** | `root` | `root` | Superuser / Administrator | Enabled |

> [!TIP]
> **Customizing Credentials During Build:**
> - **Interactive Wizard:** Run `./docker-build.sh` or `sudo ./build-alarm-rpi5.sh` without `-y` to customize usernames and passwords interactively.
> - **Environment Variables:** Set `ALARM_USER`, `ALARM_PASSWORD`, `ROOT_USER`, and `ROOT_PASSWORD` (e.g., `ALARM_USER=myuser ALARM_PASSWORD=mypass ./docker-build.sh -y`).

> [!IMPORTANT]
> **Security Notice:**
> Always change default passwords upon your first login:
> ```bash
> passwd             # Changes password for current user (alarm)
> sudo passwd root   # Changes password for root
> ```

## Requirements

An **x86_64 Arch Linux** host (bare metal, VM, or container).

```bash
sudo pacman -S --needed --noconfirm \
  qemu-user-static qemu-user-static-binfmt \
  arch-install-scripts \
  dosfstools e2fsprogs \
  parted xz gum

sudo systemctl restart systemd-binfmt.service
```

## Quick start

### Method 1: Docker (Recommended — 100% Isolated, Zero Host Pollution)

No packages or build tools need to be installed on your host system:

```bash
./docker-build.sh
```

Or pass custom flags:
```bash
./docker-build.sh --version 1.0.0 --img-size 8G
```

### Method 2: Native Host Build

```bash
sudo ./build-alarm-rpi5.sh
```

Output lands in `dist/`. That's it.

## Project Structure

The project is structured modularly with Docker and native entry points:

```
alarm-rpi5/
├── Dockerfile               # Container definition for isolated builds
├── docker-build.sh          # One-command Docker build launcher
├── .dockerignore            # Docker build context exclusions
├── build-alarm-rpi5.sh      # Primary root entry point
├── build.sh                 # Convenience alias symlink
├── data/                    # Configuration templates and static files deployed to rootfs
│   ├── 20-wired.network     # Wired Ethernet DHCP configuration (systemd-networkd)
│   ├── alarm-expand-root.service # One-shot systemd service to expand partition on first boot
│   ├── alarm-expand-root.sh # Root filesystem auto-expansion script
│   ├── cmdline.txt          # Kernel boot cmdline parameters
│   ├── config.txt           # Pi 5 bootloader configuration
│   ├── fstab                # Partition mount definitions
│   ├── hosts                # Local hostname mapping template
│   ├── install-ui.sh        # Pre-installed automated desktop environment installer
│   ├── locale.conf          # System locale configuration template
│   ├── locale.gen           # Locale generation definitions
│   ├── pacman-bootstrap.conf# Temporary pacman config for pacstrap on host
│   ├── pacman-runtime.conf  # Target pacman.conf with signature verification
│   └── sudoers-wheel        # Sudo permissions for wheel group
├── src/
│   ├── terminal.sh          # Terminal styling, Gum detection, spinners, status badges
│   ├── logger.sh            # Structured logging (info/warn/error/phase) & fatal die exit
│   ├── cleanup.sh           # Safe EXIT/INT/TERM trap handler & idempotent cleanup
│   ├── cli.sh               # Command line argument parser & usage help
│   ├── config.sh            # Defaults, environment overrides, path calculation
│   ├── wizard.sh            # Interactive setup wizards (Charm Gum + pure Bash fallback)
│   ├── doctor.sh            # Environment diagnostics (--check) & preflight checks
│   └── build.sh             # 5-phase image builder, pacstrap, chroot config & shrink
├── tests/
│   ├── run_all.sh           # Master test runner (all 10 suites)
│   ├── test_helper.sh       # Shared assertion library and reporter
│   ├── test_lint.sh         # ShellCheck & shfmt validation suite
│   ├── test_terminal.sh     # Terminal styling, Gum detection, badge & spinner tests
│   ├── test_logger.sh       # Structured logging, error format, and die exit tests
│   ├── test_cleanup.sh      # Unmounts, trap handling, temp file cleanup tests
│   ├── test_cli.sh          # Argument parsing, flags, and usage tests
│   ├── test_config.sh       # Defaults, overrides, image path calculation tests
│   ├── test_wizard.sh       # Interactive wizard input processing & TTY guard tests
│   ├── test_doctor.sh       # Dependency checks, package mappings, preflight tests
│   ├── test_build.sh        # Boot configuration, fstab, pacman generation tests
│   └── test_entrypoint.sh   # Root entry points, CLI dispatch, non-root checks
└── dist/                    # Default output directory for generated images (.img.xz)
```

## Usage

```
sudo ./build-alarm-rpi5.sh [OPTIONS]

Options:
  -c, --check              Check host environment and dependencies without building
  -i, --interactive        Run interactive configuration wizard (default on TTY)
  -y, --non-interactive,   Bypass interactive prompts and use defaults/flags
      --batch
  -o, --output-dir DIR     Output directory       (default: ./dist)
  -v, --version VER        Image version string   (default: 0.1.0)
  -s, --img-size SIZE      Raw image size         (default: 3G)
      --hostname NAME      Target hostname        (default: raspberrypi)
  -u, --user USER          Non-root username      (default: alarm)
  -p, --password PASS      Non-root user password (default: alarm)
      --root-user USER     Root username          (default: root)
      --root-password PASS Root password          (default: root)
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

## Configuration & Environment Variables

All settings have sensible defaults. Precedence order: **CLI Flags > `alarm.conf` > Environment Variables > Defaults**.

### Configuration File (`alarm.conf`)

You can configure all options declaratively in an `alarm.conf` file:

```bash
cp alarm.conf.example alarm.conf
nano alarm.conf
```

### Supported Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `IMG_SIZE` | `3G` | Raw image size (fits on any SD card >=4GB; sparse zeros compress to ~340MB) |
| `VERSION` | `0.1.0` | Embedded in output filename |
| `IMG_NAME` | `alarm-rpi5-{ver}-{date}` | Full override for output filename |
| `BOOT_SIZE_MIB` | `256` | Boot partition size in MiB |
| `TARGET_HOSTNAME` | `raspberrypi` | System hostname |
| `ROOT_USER` | `root` | Root username |
| `ROOT_PASSWORD` | `root` | Root password |
| `ALARM_USER` | `alarm` | Non-root user (wheel group) |
| `ALARM_PASSWORD` | `alarm` | Non-root user password |
| `TIMEZONE` | `Asia/Kolkata` | System timezone |
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

> **Note:** The OS Customization dialog (Wi-Fi, SSH, hostname) is disabled for custom images. SSH and `systemd-networkd` wired DHCP are pre-enabled in the image; connect via Ethernet on first boot.

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
   ssh alarm@<ip>           # password: alarm
   # or
   ssh root@<ip>            # password: root
   # or using hostname:
   ssh alarm@raspberrypi.local
   ```
4. Update immediately:
   ```bash
   sudo pacman -Syu --noconfirm
   ```
5. Change default passwords:
   ```bash
   passwd                  # change alarm's password
   sudo passwd root        # change root's password
   ```

## Installing a Desktop Environment (UI)

The base image boots into a clean command-line interface. An automated installer script `install-ui` is **pre-installed in `/usr/local/bin`** so you don't have to manually type out multiple long package lists.

### Quick Start: Automated 1-Command Installer

SSH into your Pi (or use the local console) and run:

```bash
sudo install-ui
```

This presents a simple menu:
```text
Choose a Desktop Environment to install:
  1) XFCE        - Lightweight, fast, minimal RAM (~300MB idle) [Recommended]
  2) KDE Plasma  - Modern, hardware-accelerated Wayland desktop
  3) GNOME       - Polished, touch-friendly Wayland desktop
```

Or pass the target desktop directly for a completely non-interactive installation:
```bash
sudo install-ui xfce      # Installs XFCE + LightDM + GPU drivers & reboots into GUI
sudo install-ui kde       # Installs KDE Plasma + SDDM on Wayland
sudo install-ui gnome     # Installs GNOME + GDM on Wayland
```

---

### Manual Installation & Architecture Breakdown

If you prefer installing components manually, or want to understand the role of each package:

| Layer | Component | What It Does | Example |
| :--- | :--- | :--- | :--- |
| **Graphics Driver** | DRM / Mesa | Translates OpenGL/Vulkan graphics commands directly into hardware instructions for the Pi 5 VideoCore VII GPU. | `mesa`, `libdrm` |
| **Display Server / Protocol** | Wayland or X11 | The communication protocol that manages windows, screen buffers, mouse clicks, and keystrokes. | Wayland (native on Pi 5) or `xorg-server` |
| **Display Manager (DM)** | System Service | The background daemon that starts on boot and handles user authentication and session startup. Without this, you only get a text terminal login prompt (`login:`). | `lightdm`, `sddm`, `gdm` |
| **Greeter** | Login Screen UI | The visual login screen box (rendered by the Display Manager) where you type your username/password and choose your desktop session. | `lightdm-gtk-greeter` |
| **Desktop Environment (DE)** | Full Interface | The user-facing software suite: taskbar, app launcher, window borders, wallpaper, file manager, and system settings. | `xfce4`, `plasma-desktop`, `gnome` |

---

### Step 1: Install Core GPU Drivers, Fonts & Audio

```bash
sudo pacman -Syu --needed --noconfirm \
  mesa libdrm \
  ttf-dejavu ttf-liberation noto-fonts \
  pipewire pipewire-pulse wireplumber
```

#### What each package does:
* **`mesa`**: The open-source 3D graphics library. Provides the `v3d` driver that enables hardware OpenGL and Vulkan acceleration on the Raspberry Pi 5's VideoCore VII GPU. Without Mesa, window rendering falls back to slow software emulation on the CPU.
* **`libdrm`**: Direct Rendering Manager library. A low-level userspace library that lets programs talk directly to the Linux kernel graphics subsystem to allocate display buffers and manage video modes.
* **`ttf-dejavu`, `ttf-liberation`, `noto-fonts`**: High-quality TrueType fonts covering Latin and international character sets. Without fonts installed, web browsers and UI apps render blank boxes ("tofu") instead of text.
* **`pipewire`**: Modern, low-latency multimedia routing framework that handles sound playback and microphone input.
* **`pipewire-pulse`**: Drop-in PulseAudio compatibility layer that allows standard audio applications (browsers, Spotify, media players) to play sound through PipeWire seamlessly.
* **`wireplumber`**: The modular session manager for PipeWire that dynamically switches between audio devices (e.g., HDMI audio, 3.5mm, USB headsets, or Bluetooth).

---

### Step 2: Choose and Install a Desktop Environment

#### Option A: XFCE (Lightweight & Stable — Recommended)
Extremely fast, minimal RAM footprint (~300MB idle), and rock-solid:

```bash
# 1. Remove legacy fbdev driver to prevent "Cannot run in framebuffer mode" error
sudo pacman -Rdd --noconfirm xf86-video-fbdev 2>/dev/null || true

# 2. Install XFCE, LightDM greeter, and Xorg
sudo pacman -S --needed --noconfirm \
  xfce4 xfce4-goodies \
  lightdm lightdm-gtk-greeter \
  xorg-server xorg-xinit

# 3. Configure Xorg to bind the Pi 5 vc4 KMS driver as primary GPU
sudo mkdir -p /etc/X11/xorg.conf.d
sudo rm -f /etc/X11/xorg.conf.d/20-modesetting.conf
cat <<'EOF' | sudo tee /etc/X11/xorg.conf.d/99-vc4.conf
Section "OutputClass"
    Identifier "vc4"
    MatchDriver "vc4"
    Driver "modesetting"
    Option "PrimaryGPU" "true"
EndSection
EOF

# 4. Configure LightDM to use lightdm-gtk-greeter
sudo sed -i 's/^#*greeter-session=.*/greeter-session=lightdm-gtk-greeter/' /etc/lightdm/lightdm.conf

# 5. Enable and start LightDM
sudo systemctl enable lightdm.service
sudo reboot
```

* **`xfce4`**: The core desktop environment meta-package containing the window manager (`xfwm4`), desktop background/icon manager (`xfdesktop`), application launcher panel (`xfce4-panel`), and session coordinator.
* **`xfce4-goodies`**: Useful companion plugins and utilities (task manager, battery monitor, screenshot utility, text editor, and image viewer).
* **`lightdm`**: **Light Display Manager**. A fast, lightweight background service that starts the graphical environment at boot and coordinates user logins.
* **`lightdm-gtk-greeter`**: The visual GTK-based login screen UI rendered by LightDM where you enter your username and password.
* **`xorg-server`**: The traditional X11 display server required by X11-based desktops like XFCE.
* **`xorg-xinit`**: Utility for launching and configuring manual X11 sessions (provides `startx`).
* **`99-vc4.conf`**: Directs Xorg to bind the Raspberry Pi 5 `vc4` kernel DRM driver to the native `modesetting` DDX driver with hardware Glamor acceleration, preventing the fatal multi-device framebuffer busID crash.

---

#### Option B: KDE Plasma (Modern, Hardware-Accelerated Wayland)
Feature-rich, highly customizable desktop that runs natively on Wayland with full hardware acceleration on the Pi 5:

```bash
sudo pacman -S --needed --noconfirm \
  plasma-desktop plasma-wayland-session plasma-workspace \
  konsole dolphin sddm

sudo systemctl enable sddm.service
sudo reboot
```

* **`plasma-desktop`**: The core KDE Plasma desktop shell (desktop canvas, taskbar panel, system tray, and desktop widgets).
* **`plasma-wayland-session`**: Enables Plasma to run on **Wayland** (the modern, tearing-free display protocol) taking direct advantage of the Pi 5's `v3d` GPU driver.
* **`plasma-workspace`**: Supporting desktop services (lock screen, notification server, window switcher, and clipboard manager).
* **`konsole`**: KDE's feature-packed terminal emulator.
* **`dolphin`**: KDE's graphical file manager.
* **`sddm`**: **Simple Desktop Display Manager**. The default display and login manager developed for modern KDE Plasma and Wayland sessions.

---

#### Option C: GNOME (Polished & Touch-Friendly Wayland Desktop)
A clean, tablet/touch-friendly desktop environment:

```bash
sudo pacman -S --needed --noconfirm gnome gdm

sudo systemctl enable gdm.service
sudo reboot
```

* **`gnome`**: Meta-package containing GNOME Shell, the Mutter compositor/window manager, Nautilus file manager, GNOME Settings, and core apps.
* **`gdm`**: **GNOME Display Manager**. The native login and lock screen manager for GNOME with built-in Wayland support.

---

### Step 3: Verify Hardware Acceleration
After logging into your desktop environment, open a terminal and verify that the Broadcom VideoCore VII GPU is actively rendering graphics:

```bash
glxinfo | grep -E "(OpenGL renderer|OpenGL vendor)"
```

Expected output:
```text
OpenGL vendor string: Broadcom
OpenGL renderer string: V3D 7.1
```

## What's inside

The image ships with a minimal set of packages:

| Package | Why |
|---------|-----|
| `base` | Core Arch system (includes `systemd-networkd` & `systemd-resolved`) |
| `linux-rpi` | RPi Foundation kernel with BCM2712 (Pi 5) support |
| `firmware-raspberrypi` | Broadcom wireless/Bluetooth firmware |
| `raspberrypi-bootloader` | Boot firmware (`start4.elf`, `fixup4.dat`, etc.) |
| `archlinuxarm-keyring` | Package signing keys |
| `openssh` | Remote access (enabled by default) |
| `sudo` | Privilege escalation |
| `nano` | Text editor |
| `git` | Version control |
| `tmux` | Terminal multiplexer |
| `zsh` | Interactive Z shell |
| `curl` + `wget` | Network download utilities |
| `unzip` | Archive extraction utility |

## How it works

```
x86_64 Host
    │
    ├─ Pre-flight sudo check & automatic cleanup of previous installation attempts (stale mounts/loops/debris)
    ├─ Phase 1: Clean previous attempts & create disk image with GPT (FAT32 boot ESP + ext4 root)
    ├─ losetup --partscan → attach as /dev/loopNpX
    ├─ qemu-user-static + binfmt_misc → transparent aarch64 emulation
    ├─ Phase 2: pacstrap → install ALARM packages into isolated /tmp/alarm-rootfs.*
    ├─ Phase 3: configure bootloader (config.txt, cmdline.txt, fstab)
    ├─ Phase 4: arch-chroot → configure locale, users, services, keyring, network
    ├─ Phase 5: sparse zero-fill & finalize image (xz -9 compress for distribution)
    └─ Print output path, and clean up temporary installation files/mounts
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

Run all unit and integration test suites (10 suites, 277 automated checks across every module):

```bash
./tests/run_all.sh
```

Or run test suites for individual components directly:

```bash
./tests/test_lint.sh        # Shell linting & formatting (shellcheck & shfmt)
./tests/test_terminal.sh    # src/terminal.sh (Gum discovery, styling, badges, spinners)
./tests/test_logger.sh      # src/logger.sh (structured logging, format, fatal exits)
./tests/test_cleanup.sh     # src/cleanup.sh (unmounts, signal traps, temp cleanup)
./tests/test_cli.sh         # src/cli.sh (argument parsing, flags, usage)
./tests/test_config.sh      # src/config.sh (defaults, env overrides, path math)
./tests/test_wizard.sh      # src/wizard.sh (interactive wizards, tty guards)
./tests/test_doctor.sh      # src/doctor.sh (environment diagnostics, package map)
./tests/test_build.sh       # src/build.sh (boot configs, partition math, pacman)
./tests/test_entrypoint.sh  # build-alarm-rpi5.sh & build.sh
```

To run diagnostic checks on your host system without building:

```bash
./build-alarm-rpi5.sh --check
```

## Continuous Integration & Automated Releases

A GitHub Actions workflow ([`.github/workflows/build.yml`](.github/workflows/build.yml)) automates testing, image building, and distribution:

1. **Lint & Test**: On every push and pull request, ShellCheck, `shfmt`, and all 10 unit test suites run automatically.
2. **Build**: On every commit to `main` (or manual `workflow_dispatch`), an Arch Linux container runs the batch build pipeline using QEMU ARM64 binfmt emulation.
3. **Publish**:
   - Generates SHA-256 checksums (`SHA256SUMS`).
   - Attaches the compressed `.img.xz` artifact to the workflow run.
   - Publishes to GitHub Releases under a rolling `latest` release tag (or dedicated version tag for `v*` pushes).

## License

The build script in this repository is released under the [MIT License](LICENSE). The software it assembles is governed by its respective upstream licenses.
