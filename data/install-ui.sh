#!/usr/bin/env bash
# /usr/local/bin/install-ui — Automated Desktop Environment installer for Arch Linux ARM (RPi 5)
set -euo pipefail

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
    echo "==> Error: This script must be run as root (or via sudo)."
    echo "    Usage: sudo install-ui [xfce|kde|plasma|gnome]"
    exit 1
fi

echo "========================================================"
echo "  Raspberry Pi 5 Desktop Environment (UI) Installer"
echo "========================================================"

TARGET_DE="${1:-}"

if [[ -z "$TARGET_DE" ]]; then
    echo ""
    echo "Choose a Desktop Environment to install:"
    echo "  1) XFCE        - Lightweight, fast, minimal RAM (~300MB idle) [Recommended]"
    echo "  2) KDE Plasma  - Modern, hardware-accelerated Wayland desktop"
    echo "  3) GNOME       - Polished, touch-friendly Wayland desktop"
    echo ""
    read -r -p "Enter choice [1-3, default: 1 (XFCE)]: " de_choice
    de_choice="${de_choice:-1}"
    case "$de_choice" in
        1|xfce|XFCE) TARGET_DE="xfce" ;;
        2|kde|plasma|KDE|Plasma) TARGET_DE="kde" ;;
        3|gnome|GNOME) TARGET_DE="gnome" ;;
        *)
            echo "Invalid option. Defaulting to XFCE."
            TARGET_DE="xfce"
            ;;
    esac
fi

TARGET_DE="$(echo "$TARGET_DE" | tr '[:upper:]' '[:lower:]')"

echo ""
echo "==> Step 1/3: Installing GPU acceleration drivers, fonts, and audio..."

# 1. Remove legacy fbdev driver:
# On Raspberry Pi 5 with vc4 KMS, xf86-video-fbdev tries to take over the display
# in legacy framebuffer mode, causing Xorg to crash with "Cannot run in framebuffer mode".
# Removing it forces Xorg to use the native kernel modesetting driver.
pacman -Rdd --noconfirm xf86-video-fbdev 2>/dev/null || true

# 2. Core graphics, fonts, and audio:
# - mesa: Hardware 3D OpenGL & Vulkan acceleration via Broadcom VideoCore VII (V3D 7.1)
# - libdrm: Direct Rendering Manager userspace library to communicate with Linux kernel DRM
# - ttf-*: Essential TrueType fonts to avoid missing glyphs ("tofu" boxes) in UI and browsers
# - pipewire & wireplumber: Low-latency audio server and modern session manager
pacman -Syu --needed --noconfirm \
    mesa libdrm \
    ttf-dejavu ttf-liberation noto-fonts \
    pipewire pipewire-pulse wireplumber

echo ""
case "$TARGET_DE" in
    xfce)
        echo "==> Step 2/3: Installing XFCE Desktop and LightDM display manager..."
        # - xfce4 & xfce4-goodies: Lightweight GTK desktop environment, panel, and companion plugins
        # - lightdm: Fast, lightweight background display manager daemon
        # - lightdm-gtk-greeter: Visual login screen GUI where credentials and session are entered
        # - xorg-server & xorg-xinit: X11 display server required for XFCE
        pacman -S --needed --noconfirm \
            xfce4 xfce4-goodies \
            lightdm lightdm-gtk-greeter \
            xorg-server xorg-xinit

        # Configure LightDM:
        # Use a systemd drop-in file (/etc/lightdm/lightdm.conf.d/) to cleanly specify the greeter
        # session without modifying or risking syntax errors in the upstream lightdm.conf file.
        mkdir -p /etc/lightdm/lightdm.conf.d
        cat > /etc/lightdm/lightdm.conf.d/60-lightdm-gtk-greeter.conf <<'GREETER'
[Seat:*]
greeter-session=lightdm-gtk-greeter
GREETER
        # Fix any legacy or malformed greeter lines in /etc/lightdm/lightdm.conf if present
        if [[ -f /etc/lightdm/lightdm.conf ]]; then
            sed -i 's/greeter-session-lightdm-gtk-greeter/greeter-session=lightdm-gtk-greeter/' /etc/lightdm/lightdm.conf
            sed -i 's/^#*greeter-session=.*/greeter-session=lightdm-gtk-greeter/' /etc/lightdm/lightdm.conf
        fi

        # Configure Xorg KMS driver for Raspberry Pi 5:
        # Binds the vc4 kernel DRM driver to the generic "modesetting" DDX driver with hardware
        # Glamor 2D/3D acceleration, marking it as PrimaryGPU to prevent multi-device busID errors.
        mkdir -p /etc/X11/xorg.conf.d
        rm -f /etc/X11/xorg.conf.d/20-modesetting.conf
        cat > /etc/X11/xorg.conf.d/99-vc4.conf <<'XORG'
Section "OutputClass"
    Identifier "vc4"
    MatchDriver "vc4"
    Driver "modesetting"
    Option "PrimaryGPU" "true"
EndSection
XORG

        echo "==> Step 3/3: Enabling LightDM login manager service..."
        systemctl enable lightdm.service
        ;;
    kde|plasma)
        echo "==> Step 2/3: Installing KDE Plasma and SDDM display manager..."
        # - plasma-desktop & plasma-workspace: Full modern KDE desktop shell and services
        # - plasma-wayland-session: Hardware-accelerated tearing-free Wayland session
        # - sddm: Simple Desktop Display Manager (default login manager for KDE Plasma)
        pacman -S --needed --noconfirm \
            plasma-desktop plasma-wayland-session plasma-workspace \
            konsole dolphin sddm
        echo "==> Step 3/3: Enabling SDDM login manager service..."
        systemctl enable sddm.service
        ;;
    gnome)
        echo "==> Step 2/3: Installing GNOME Desktop and GDM display manager..."
        # - gnome: Complete GNOME Shell desktop environment running natively on Wayland
        # - gdm: GNOME Display Manager with built-in Wayland session handling
        pacman -S --needed --noconfirm gnome gdm
        echo "==> Step 3/3: Enabling GDM login manager service..."
        systemctl enable gdm.service
        ;;
    *)
        echo "==> Error: Unknown desktop choice '$TARGET_DE'. Available: xfce, kde, gnome."
        exit 1
        ;;
esac

echo ""
echo "========================================================"
echo "  Installation Complete!"
echo "  Desktop ($TARGET_DE) and display manager have been enabled."
echo "========================================================"
echo ""

read -r -p "Reboot now to enter your desktop? [y/N]: " do_reboot
if [[ "$do_reboot" =~ ^[Yy] ]]; then
    echo "Rebooting..."
    reboot
else
    echo "Done! Run 'sudo reboot' when you are ready to enter your desktop."
fi
