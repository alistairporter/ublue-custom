#!/usr/bin/env bash

et ${SET_X:+-x} -eou pipefail

# ublue staging repo needed for misc packages provided by ublue
$DNF -y copr enable ublue-os/staging

# VSCode because it's still better for a lot of things
tee /etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# common packages
$DNF install --setopt=install_weak_deps=False -y \
    btop \
    ccache \
    cockpit-bridge \
    cockpit-files \
    cockpit-machines \
    cockpit-networkmanager \
    cockpit-ostree \
    cockpit-podman \
    cockpit-selinux \
    cockpit-storaged \
    cockpit-system \
    code \
    edk2-ovmf \
    git \
    gnome-shell-extension-no-overview \
    guestfs-tools \
    htop \
    jetbrains-mono-fonts-all \
    libpcap-devel \
    libretls \
    libvirt \
    libvirt-daemon-kvm \
    libvirt-ssh-proxy \
    libvirt-nss \
    lm_sensors \
    ltrace \
    make \
    nerd-fonts \
    patch \
    pipx \
    powerline-fonts \
    qemu-img \
    qemu-kvm \
    rpmrebuild \
    sbsigntools \
    strace \
    tmux \
    xorriso \
    zsh
