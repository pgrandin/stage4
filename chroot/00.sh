#!/bin/bash

set -e

target=$1
[[ -z "${target}" ]] && exit 1

echo "nameserver 1.1.1.1" > /etc/resolv.conf

env-update && source /etc/profile
emerge-webrsync

eselect profile set default/linux/amd64/23.0/split-usr

[[ -f /etc/portage/binrepos.conf/gentoobinhost.conf ]] && rm /etc/portage/binrepos.conf/gentoobinhost.conf
[[ -d /var/cache/distfiles ]] || mkdir /var/cache/distfiles

wget https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64 -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq

# Reindex retained packages; Portage checks version, USE and ABI compatibility.
emaint binhost --fix

# Install base tools (use --usepkg=n to build from source and avoid potential conflicts)
# First update zlib to avoid circular dependency with cmake/curl
MAKEOPTS="-j$(nproc)" emerge -q --usepkg=n -1 sys-libs/zlib

# Bootstrap pam without elogind to break circular dep: elogind->libudev->systemd-utils->libcap->pam->elogind
USE="-elogind" MAKEOPTS="-j$(nproc)" emerge -q --usepkg=n -1 sys-libs/pam sys-libs/libcap

MAKEOPTS="-j$(nproc)" emerge -q --usepkg=n eix gentoolkit dev-vcs/git
[[ -d /var/cache/eix ]] || mkdir /var/cache/eix
chown portage:portage /var/cache/eix
eix-update

# --unique-use: drop older builds of the same version+USE. buildpkg +
# binpkg-multi-instance otherwise keeps every rebuild (git/gentoolkit are
# rebuilt with --usepkg=n each run) and the binhost grew to 59 GiB.
/usr/bin/eclean packages --unique-use
