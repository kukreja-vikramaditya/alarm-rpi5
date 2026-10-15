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
pacman -Rdd --noconfirm xf86-video-fbdev 2>/dev/null || true
pacman -Syu --needed --noconfirm \
    mesa libdrm \
    ttf-dejavu ttf-liberation noto-fonts \
    pipewire pipewire-pulse wireplumber

echo ""
case "$TARGET_DE" in
    xfce)
        echo "==> Step 2/3: Installing XFCE Desktop and LightDM display manager..."
        pacman -S --needed --noconfirm \
            xfce4 xfce4-goodies \
            lightdm lightdm-gtk-greeter \
            xorg-server xorg-xinit

        # Configure LightDM to use lightdm-gtk-greeter via drop-in and fix any typos
        mkdir -p /etc/lightdm/lightdm.conf.d
        cat > /etc/lightdm/lightdm.conf.d/60-lightdm-gtk-greeter.conf <<'GREETER'
[Seat:*]
greeter-session=lightdm-gtk-greeter
GREETER
        if [[ -f /etc/lightdm/lightdm.conf ]]; then
            sed -i 's/greeter-session-lightdm-gtk-greeter/greeter-session=lightdm-gtk-greeter/' /etc/lightdm/lightdm.conf
            sed -i 's/^#*greeter-session=.*/greeter-session=lightdm-gtk-greeter/' /etc/lightdm/lightdm.conf
        fi

        # Ensure Xorg uses native modesetting KMS driver with vc4
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
        pacman -S --needed --noconfirm \
            plasma-desktop plasma-wayland-session plasma-workspace \
            konsole dolphin sddm
        echo "==> Step 3/3: Enabling SDDM login manager service..."
        systemctl enable sddm.service
        ;;
    gnome)
        echo "==> Step 2/3: Installing GNOME Desktop and GDM display manager..."
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
