#!/bin/bash
set -euo pipefail

stage4_fs=${1:?stage4 filesystem is required}

if [ ! -f "$stage4_fs/var/lib/portage/world" ]; then
    echo "The world file does not exist at $stage4_fs/var/lib/portage/world."
    exit 1
fi

if yq '.features[] | select(. == "X")' "$stage4_fs/config.yml" | grep -q X; then
    echo "X is present in features, installing Firefox and Chromium"
    echo "setting up firefox package from packages/www-client/firefox to $stage4_fs/etc/portage/"
    rsync -vrtza packages/www-client/firefox/ "$stage4_fs/etc/portage/"
    # Both stage4 runners have at least 13 GiB RAM. Keep Firefox's compiler
    # processes bounded even when the completed world stage is reused.
    sed -i 's/^MAKEOPTS=.*/MAKEOPTS="-j4 -l4"/' "$stage4_fs/etc/portage/make.conf"
    echo "Building firefox from chroot"
    chroot "$stage4_fs" emerge --update --newuse --oneshot --usepkg --getbinpkg media-libs/libvpx
    chroot "$stage4_fs" emerge --update --usepkg --getbinpkg --jobs=1 --load-average=4 www-client/firefox

    # Gentoo removed native Chromium; use the maintained Flathub build.
    chroot "$stage4_fs" flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    chroot "$stage4_fs" flatpak install --system --noninteractive --assumeyes --or-update flathub org.chromium.Chromium
else
    echo "X is not present in features, not building browsers"
fi
