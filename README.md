# alarm-rpi5

Build an [Arch Linux ARM](https://archlinuxarm.org/) image for the **Raspberry Pi 5** from source — flashable via [Raspberry Pi Imager](https://www.raspberrypi.com/software/).

No third-party installers, no random GitHub projects. Just `pacstrap`, the official ALARM repos, and standard Linux tooling.

## What this produces

A compressed raw disk image:

```
dist/alarm-rpi5-1.1.0-snapshot-20261016.img.xz
```

Flash it with Raspberry Pi Imager → **"Use custom"**.

## Default Usernames & Passwords

The built image is pre-configured with default credentials and passwordless `sudo` privileges for the `wheel` group:

| Account | Username | Default Password | Privileges / Group | SSH Access |
| :--- | :--- | :--- | :--- | :--- |
| **Standard User** | `alarm` | `alarm` | `wheel` (`sudo` privileges) | Enabled |
| **Root User** | `root` | `root` | Superuser / Administrator | Enabled |

> [!TIP]
> **Customizing Credentials During Build:**
> - **Interactive Wizard:** Run `./build.sh` without `-y` to customize usernames and passwords interactively.
> - **Environment Variables:** Set `USERNAME` (or `ALARM_USER`), `PASSWORD` (or `ALARM_PASSWORD`), `ROOT_USER`, and `ROOT_PASSWORD` (e.g., `USERNAME=myuser PASSWORD=mypass ./build.sh -y`).

> [!IMPORTANT]
> **Security Notice:**
> Always change default passwords upon your first login:
> ```bash
> passwd             # Changes password for current user (alarm)
> sudo passwd root   # Changes password for root
> ```

## Requirements

- **Docker** (Docker Desktop on Windows/macOS, or Docker Engine on Linux).
  Docker is strictly required. You do **not** need an Arch Linux PC. Everything (including `pacstrap`, `arch-chroot`, `qemu-user-static`, and Charm `gum`) is pre-installed and executed inside the isolated Arch Linux builder container.

## Quick start

Build directly from any Linux distribution (Ubuntu, Debian, Fedora, Arch), macOS, or Windows (WSL 2):

```bash
./build.sh
```

- When run in a terminal, it launches the interactive **Charm Gum Wizard** automatically.
- For unattended / automated runs (e.g. CI or scripts), pass `-y`:

```bash
./build.sh -y
```

Or pass custom flags:
```bash
./build.sh -y --version 1.1.0-snapshot --img-size 4G --user pi
```

Output lands in `dist/`. That's it.

## Usage

```
./build.sh [OPTIONS]

Options:
  -c, --check              Check host environment and dependencies without building
  -i, --interactive        Run interactive configuration wizard (default on TTY)
  -y, --non-interactive,   Bypass interactive prompts and use defaults/flags
      --batch
  -o, --output-dir DIR     Output directory       (default: ./dist)
  -v, --version VER        Image version string   (default: from VERSION file or 1.1.0-snapshot)
  -s, --img-size SIZE      Raw image size         (default: 3G)
      --hostname NAME      Target hostname        (default: raspberrypi)
  -u, --user USER          Non-root username      (default: alarm)
  -p, --password PASS      Non-root user password (default: alarm)
      --root-user USER     Root username          (default: root)
      --root-password PASS Root password          (default: root)
      --no-compress        Skip xz compression
  -h, --help               Show help
```

### Examples

```bash
# Check if host environment has required tools & setup
./build.sh --check

# Default build (launches interactive wizard automatically on terminal)
./build.sh

# Non-interactive / unattended build (uses defaults or flags immediately)
./build.sh -y

# Custom version and output
./build.sh -y -v 1.1.0-snapshot -o ./dist

# Larger image with extra packages
IMAGE_SIZE=8G PACKAGES="git htop vim" ./build.sh -y

# Skip compression for faster iteration
./build.sh -y --no-compress

# Override hostname, timezone, locale, and user credentials
HOSTNAME=mypi TZ=Asia/Kolkata LANG=en_US.UTF-8 USERNAME=vikram PASSWORD=secret \
  ./build.sh -y
```

## Configuration & Environment Variables

All settings have sensible defaults. Precedence order: **CLI Flags > `alarm.conf` > Environment Variables > Defaults**.

### Configuration File (`alarm.conf`)

You can configure all options declaratively directly in `alarm.conf`. Both standard POSIX/UNIX names and legacy aliases are supported.

### Supported Settings

| Variable | Legacy Alias | Default | Description |
|----------|--------------|---------|-------------|
| `TZ` | `TIMEZONE` | `Asia/Kolkata` | System timezone (POSIX standard) |
| `LANG` | `LOCALE` | `en_US.UTF-8` | System locale (POSIX standard) |
| `HOSTNAME` | `TARGET_HOSTNAME` | `raspberrypi` | System hostname |
| `USERNAME` | `ALARM_USER` | `alarm` | Non-root user (wheel group / sudo privileges) |
| `PASSWORD` | `ALARM_PASSWORD` | `alarm` | Non-root user password |
| `ROOT_USER` | — | `root` | Root administrator username |
| `ROOT_PASSWORD` | — | `root` | Root administrator password |
| `PACKAGES` | `EXTRA_PACKAGES` | `git curl wget vim neovim tmux zsh` | Space-separated list of extra pacman packages |
| `IMAGE_SIZE` | `IMG_SIZE` | `3G` | Raw disk image size (fits on any SD card >=4GB) |
| `BOOT_SIZE` | `BOOT_SIZE_MIB` | `256M` | Boot partition size |
| `MIRROR` | `ALARM_MIRROR` | `http://mirror.archlinuxarm.org` | Arch Linux ARM mirror URL |
| `COMPRESS` | — | `1` | Set to `0` to skip xz compression (.img raw) |
| `OUTPUT_DIR` | — | `./dist` | Output directory for built images |
| `VERSION` | — | `1.1.0-snapshot` | Embedded in output filename (tracks root `VERSION` file) |
| `IMG_NAME` | — | `alarm-rpi5-{ver}-{date}` | Full override for output filename |

## Flashing

1. Open **[Raspberry Pi Imager](https://www.raspberrypi.com/software/)**
2. **Choose OS** → scroll to bottom → **Use custom**
3. Select `dist/alarm-rpi5-*.img.xz`
4. **Choose Storage** → select your SD card
5. **Write**

> [!NOTE]
> The OS Customization dialog (Wi-Fi, SSH, hostname) is disabled for custom images. SSH and `systemd-networkd` wired DHCP are pre-enabled in the image; connect via Ethernet on first boot.

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
./tests/test_wizard.sh      # wizard.sh (standalone interactive TUI & command generator)
./tests/test_doctor.sh      # src/doctor.sh (environment diagnostics, package map)
./tests/test_build.sh       # src/build.sh (boot configs, partition math, pacman)
./tests/test_entrypoint.sh  # build.sh root entry point
```

To run diagnostic checks on your host system without building:

```bash
./build.sh --check
```

## Continuous Integration & Automated Releases

GitHub Actions workflows automate testing, image building, and distribution:

1. **Continuous Integration & Releases ([`.github/workflows/build.yml`](.github/workflows/build.yml))**:
   - **Lint & Test**: On every push and pull request, ShellCheck, `shfmt`, and all 10 unit test suites run automatically.
   - **Build**: On every commit to `main` (or manual `workflow_dispatch`), an Arch Linux container builds the image via QEMU ARM64 binfmt emulation.
   - **Publish**: Generates SHA-256 checksums (`SHA256SUMS`) and publishes to GitHub Releases under rolling `latest` or tagged version releases (e.g. `v1.0.1`).

2. **Scheduled Rolling Snapshots ([`.github/workflows/nightly-release.yml`](.github/workflows/nightly-release.yml))**:
   - **Schedule**: Runs automatically on a bi-weekly cron (1st & 15th of each month) and via manual dispatch.
   - **Purpose**: Arch Linux is a rolling-release distribution. Older pre-built images require extensive `pacman -Syu` downloads on first boot. This workflow publishes an updated `latest-snapshot` release containing the freshest packages directly from upstream mirrors.

3. **Skipping CI Builds**:
   - **Automatic skip for documentation**: Commits that only modify documentation (`README.md`, `LICENSE`, `*.md`) or repository ignore files (`.gitignore`, `.dockerignore`) automatically skip the entire CI pipeline via GitHub Actions `paths-ignore`.
   - **Manual CI skip**: Include `[skip ci]` or `[ci skip]` in your commit message to skip the entire CI workflow for any commit.
   - **Skip image building only**: Include `[skip build]` or `[skip image]` in your commit message to run the fast linter and unit tests while skipping the resource-intensive OS image generation and release step.

## License

The build script in this repository is released under the [MIT License](LICENSE). The software it assembles is governed by its respective upstream licenses.
