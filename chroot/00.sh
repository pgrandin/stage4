#!/bin/bash

set -e

target=$1
[[ -z "${target}" ]] && exit 1

echo "nameserver 1.1.1.1" > /etc/resolv.conf

env-update && source /etc/profile
emerge-webrsync

export AWS_BUCKET="pierre-packages"

eselect profile set default/linux/amd64/23.0/split-usr

[[ -f /etc/portage/binrepos.conf/gentoobinhost.conf ]] && rm /etc/portage/binrepos.conf/gentoobinhost.conf
[[ -d /var/cache/distfiles ]] || mkdir /var/cache/distfiles

wget https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64 -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq

# Clean up cached binpkgs that may conflict with newer versions in stage3
rm -rf /var/cache/binpkgs/acct-user/
rm -rf /var/cache/binpkgs/acct-group/
rm -rf /var/cache/binpkgs/x11-libs/
rm -rf /var/cache/binpkgs/x11-base/
rm -rf /var/cache/binpkgs/x11-drivers/
rm -rf /var/cache/binpkgs/dev-lang/perl/
rm -rf /var/cache/binpkgs/dev-perl/
rm -rf /var/cache/binpkgs/virtual/

# Install base tools (use --usepkg=n to build from source and avoid potential conflicts)
# First update zlib to avoid circular dependency with cmake/curl
MAKEOPTS="-j$(nproc)" emerge -q --usepkg=n -1 sys-libs/zlib
MAKEOPTS="-j$(nproc)" emerge -q --usepkg=n eix gentoolkit dev-vcs/git
[[ -d /var/cache/eix ]] || mkdir /var/cache/eix
chown portage:portage /var/cache/eix
eix-update

/usr/bin/eclean packages
