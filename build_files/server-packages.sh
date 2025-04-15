#!/usr/bin/bash

set ${SET_X:+-x} -eou pipefail

# Docker Repo
tee /etc/yum.repos.d/docker-ce.repo <<'EOF'
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=https://download.docker.com/linux/fedora/$releasever/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/fedora/gpg
EOF

dnf5 -y install dnf5-plugins

# Incus/Podman COPR Repo
dnf5 -y copr enable ganto/lxc4
dnf5 -y copr enable ganto/umoci

SERVER_PACKAGES=(
    binutils
    bootc
    erofs-utils
    just
    python-ramalama
    rclone
    sbsigntools
    socat
    tmux
    udica
)

# Incus Packages
SERVER_PACKAGES+=(
    edk2-ovmf
    genisoimage
    gvisor-tap-vsock
    qemu-char-spice
    qemu-device-display-virtio-gpu
    qemu-device-display-virtio-vga
    qemu-device-usb-redirect
    qemu-img
    qemu-kvm-core
    swtpm
    umoci
    virtiofsd
)

# Docker Packages
SERVER_PACKAGES+=(
    containerd.io
    docker-buildx-plugin
    docker-ce
    docker-ce-cli
    docker-compose-plugin
)

if [[ ${IMAGE} =~ ucore ]]; then
    dnf5 remove -y \
        containerd docker-cli moby-engine runc
fi

dnf5 install -y "${SERVER_PACKAGES[@]}"

# Bootupctl fix for ISO
if [[ $(rpm -E %fedora) -eq "40" && ! "${IMAGE}" =~ aurora|bluefin|ucore ]]; then
    /usr/bin/bootupctl backend generate-update-metadata
fi

# Put virtiofsd on PATH
ln -sf /usr/libexec/virtiofsd /usr/bin/virtiofsd

# Docker sysctl.d
mkdir -p /usr/lib/sysctl.d
echo "net.ipv4.ip_forward = 1" >/usr/lib/sysctl.d/docker-ce.conf

# Groups
groupmod -g 252 docker

SYSUSER_GROUP=(docker qemu)
for sys_group in "${SYSUSER_GROUP[@]}"; do
    tee "/usr/lib/sysusers.d/$sys_group.conf" <<EOF
g $sys_group -
EOF
done
