#!/usr/bin/bash

set -eoux pipefail

# Add Staging repo
curl -Lo /etc/yum.repos.d/ublue-os-staging-fedora-"${FEDORA_VERSION}".repo \
    https://copr.fedorainfracloud.org/coprs/ublue-os/staging/repo/fedora-"${FEDORA_VERSION}"/ublue-os-staging-fedora-"${FEDORA_VERSION}".repo

# Add Bling repo
curl -Lo /etc/yum.repos.d/ublue-os-bling-fedora-"${FEDORA_VERSION}".repo \
    https://copr.fedorainfracloud.org/coprs/ublue-os/bling/repo/fedora-"${FEDORA_VERSION}"/ublue-os-bling-fedora-"${FEDORA_VERSION}".repo

# Tailscale
curl -Lo /etc/yum.repos.d/tailscale.repo \
    https://pkgs.tailscale.com/stable/fedora/tailscale.repo && \

# Add Nerd Fonts
curl -Lo /etc/yum.repos.d/_copr_che-nerd-fonts-"${FEDORA_VERSION}".repo \
    https://copr.fedorainfracloud.org/coprs/che/nerd-fonts/repo/fedora-"${FEDORA_VERSION}"/che-nerd-fonts-fedora-"${FEDORA_VERSION}".repo

# Add Looking Glass
curl -Lo /etc/yum.repos.d/hikariknight-looking-glass-kvmfr-fedora-"${FEDORA_VERSION}".repo \
    https://copr.fedorainfracloud.org/coprs/hikariknight/looking-glass-kvmfr/repo/fedora-"${FEDORA_VERSION}"/hikariknight-looking-glass-kvmfr-fedora-"${FEDORA_VERSION}".repo

# Add Negativo17 Repo
curl -Lo /etc/yum.repos.d/negativo17-fedora-multimedia.repo \
    https://negativo17.org/repos/fedora-multimedia.repo


# Akmods Repo
tee /etc/yum.repos.d/_copr_ublue-os-akmods.repo <<'EOF'
[copr:copr.fedorainfracloud.org:ublue-os:akmods]
name=Copr repo for akmods owned by ublue-os
baseurl=https://download.copr.fedorainfracloud.org/results/ublue-os/akmods/fedora-$releasever-$basearch/
type=rpm-md
skip_if_unavailable=True
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/ublue-os/akmods/pubkey.gpg
repo_gpgcheck=0
enabled=1
enabled_metadata=1
priority=90
EOF

#Charm Repo
tee /etc/yum.repos.d/charm.repo <<'EOF'
[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key
EOF


rpm-ostree override replace --experimental \
    --install=pv \
    --install=ptyxis \
    --install=bash-color-prompt \
    --install=bcache-tools \
    --install=bootc \
    --install=evtest \
    --install=fastfetch \
    --install=fish \
    --install=firewall-config \
    --install=foo2zjs \
    --install=gcc \
    --install=glow \
    --install=gum \
    --install=hplip \
    --install=ifuse \
    --install=libimobiledevice \
    --install=libxcrypt-compat \
    --install=lm_sensors \
    --install=make \
    --install=mesa-libGLU \
    --install=nerd-fonts \
    --install=playerctl \
    --install=pulseaudio-utils \
    --install=python3-pip \
    --install=rclone \
    --install=restic \
    --install=samba-dcerpc \
    --install=samba-ldb-ldap-modules \
    --install=samba-winbind-clients \
    --install=samba-winbind-modules \
    --install=samba \
    --install=solaar \
    --install=tailscale \
    --install=tmux \
    --install=usbmuxd \
    --install=wireguard-tools \
    --install=xprop \
    --install=wl-clipboard \
    /tmp/akmods-zfs/*.rpm \
    /tmp/akmods/*kvmfr*.rpm \
    /tmp/akmods/*xpadneo*.rpm \
    /tmp/akmods/*xone*.rpm \
    /tmp/akmods/*openrazer*.rpm \
    /tmp/akmods/*wl*.rpm \
    /tmp/akmods/*v4l2loopback*.rpm \
    /tmp/kernel-rpms/kernel-[0-9]*.rpm \
    /tmp/kernel-rpms/kernel-core-*.rpm \
    /tmp/kernel-rpms/kernel-modules-*.rpm

sed -i 's@enabled=1@enabled=0@g' /etc/yum.repos.d/negativo17-fedora-multimedia.repo

# curl -Lo /tmp/nvidia-install.sh \
#     https://raw.githubusercontent.com/ublue-os/hwe/main/nvidia-install.sh
# chmod +x /tmp/nvidia-install.sh
# IMAGE_NAME="base" RPMFUSION_MIRROR="" /tmp/nvidia-install.sh
# rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json

KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"

depmod -a -v "$QUALIFIED_KERNEL"
echo "zfs" > /usr/lib/modules-load.d/zfs.conf

# Topgrade Install
pip install --prefix=/usr topgrade

rpm-ostree install ublue-update

# /usr/libexec/rpm-ostree/wrapped/dracut --no-hostonly --kver "$QUALIFIED_KERNEL" --reproducible -v --add ostree -f "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"

chmod 0600 "/lib/modules/$QUALIFIED_KERNEL/initramfs.img"
