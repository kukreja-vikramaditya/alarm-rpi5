FROM archlinux:latest

# Configure reliable mirrors and install build tools
RUN printf '%s\n' \
        'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' \
        'Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch' \
        'Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch' \
        > /etc/pacman.d/mirrorlist && \
    pacman-key --init && \
    pacman-key --populate archlinux && \
    pacman -Sy --noconfirm archlinux-keyring && \
    pacman -Syu --noconfirm --needed \
        arch-install-scripts \
        dosfstools \
        e2fsprogs \
        parted \
        xz \
        util-linux \
        coreutils \
        qemu-user-static \
        qemu-user-static-binfmt

WORKDIR /workspace

# Copy codebase
COPY . /workspace

ENTRYPOINT ["./build-alarm-rpi5.sh"]
CMD ["-y"]
