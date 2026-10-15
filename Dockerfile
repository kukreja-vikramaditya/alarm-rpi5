FROM archlinux:latest

# Configure reliable mirrors and install build tools
RUN sed -i 's/^#DisableSandbox/DisableSandbox/' /etc/pacman.conf || true && \
    grep -q '^DisableSandbox' /etc/pacman.conf || echo 'DisableSandbox' >> /etc/pacman.conf && \
    printf '%s\n' \
        'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' \
        'Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch' \
        'Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch' \
        > /etc/pacman.d/mirrorlist && \
    pacman-key --init && \
    pacman-key --populate archlinux && \
    pacman -Syu --noconfirm --needed \
        arch-install-scripts \
        dosfstools \
        e2fsprogs \
        parted \
        xz \
        util-linux \
        coreutils \
        curl \
        qemu-user-static \
        qemu-user-static-binfmt && \
    rm -rf /var/cache/pacman/pkg/*

WORKDIR /workspace

# Copy codebase
COPY . /workspace

ENTRYPOINT ["./build-alarm-rpi5.sh"]
CMD ["-y"]
