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
    /tmp/config-rpms/*.rpm \
    /tmp/akmods-zfs/*.rpm \
    /tmp/akmods-rpms/*kvmfr*.rpm \
    /tmp/akmods-rpms/*xpadneo*.rpm \
    /tmp/akmods-rpms/*xone*.rpm \
    /tmp/akmods-rpms/*openrazer*.rpm \
    /tmp/akmods-rpms/*wl*.rpm \
    /tmp/akmods-rpms/*v4l2loopback*.rpm \
    /tmp/kernel-rpms/kernel-[0-9]*.rpm \
    /tmp/kernel-rpms/kernel-core-*.rpm \
    /tmp/kernel-rpms/kernel-modules-*.rpm

sed -i 's@enabled=1@enabled=0@g' /etc/yum.repos.d/negativo17-fedora-multimedia.repo

KERNEL_SUFFIX=""
QUALIFIED_KERNEL="$(rpm -qa | grep -P 'kernel-(|'"$KERNEL_SUFFIX"'-)(\d+\.\d+\.\d+)' | sed -E 's/kernel-(|'"$KERNEL_SUFFIX"'-)//')"

depmod -a -v "$QUALIFIED_KERNEL"
echo "zfs" > /usr/lib/modules-load.d/zfs.conf

rpm-ostree install \
    bash-color-prompt \
    bcache-tools \
    bootc \
    evtest \
    fastfetch \
    fish \
    firewall-config \
    foo2zjs \
    gcc \
    glow \
    gum \
    hplip \
    ifuse \
    libimobiledevice \
    libxcrypt-compat \
    lm_sensors \
    make \
    mesa-libGLU \
    nerd-fonts \
    playerctl \
    pulseaudio-utils \
    python3-pip \
    rclone \
    restic \
    samba-dcerpc \
    samba-ldb-ldap-modules \
    samba-winbind-clients \
    samba-winbind-modules \
    samba \
    solaar \
    tailscale \
    tmux \
    usbmuxd \
    wireguard-tools \
    xprop \
    wl-clipboard

rpm-ostree install ublue-update
