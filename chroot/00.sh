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

# Use --usepkg=n to avoid conflicts with cached binpkgs from older perl/python versions
MAKEOPTS="-j$(nproc)" emerge -q --usepkg=n eix gentoolkit dev-vcs/git
[[ -d /var/cache/eix ]] || mkdir /var/cache/eix
chown portage:portage /var/cache/eix
eix-update

rm -rf /var/cache/binpkgs/acct-user/
rm -rf /var/cache/binpkgs/acct-group/
rm -rf /var/cache/binpkgs/x11-libs/
rm -rf /var/cache/binpkgs/dev-lang/perl/
rm -rf /var/cache/binpkgs/dev-perl/
rm -rf /var/cache/binpkgs/virtual/perl-*
/usr/bin/eclean packages
