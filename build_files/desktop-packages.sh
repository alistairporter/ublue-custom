#!/usr/bin/bash

set ${SET_X:+-x} -eou pipefail

# Ublue Staging
dnf5 -y copr enable ublue-os/staging

# Ublue Packages
dnf5 -y copr enable ublue-os/packages

# Bazzite Repos
dnf5 -y copr enable bazzite-org/bazzite
dnf5 -y copr enable bazzite-org/bazzite-multilib
dnf5 -y copr enable bazzite-org/LatencyFleX

# Sunshine
dnf5 -y copr enable lizardbyte/beta

# Webapp Manager
dnf5 -y copr enable bazzite-org/webapp-manager

# Layered Applications
LAYERED_PACKAGES=(
    tmux
    zsh
    nextcloud-desktop
    adw-gtk3-theme
    sunshine
    webapp-manager
}

dnf5 install --setopt=install_weak_deps=False -y "${LAYERED_PACKAGES[@]}"

# Call other Scripts
#/ctx/desktop-defaults.sh
/ctx/flatpak.sh
