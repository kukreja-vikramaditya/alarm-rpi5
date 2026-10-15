FROM archlinux:base-devel

# Initialize pacman keyring and install build tools
RUN pacman-key --init && \
    pacman-key --populate archlinux && \
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
