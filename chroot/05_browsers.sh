#!/bin/bash
set -euo pipefail

stage4_fs=${1:?stage4 filesystem is required}

if [ ! -f "$stage4_fs/var/lib/portage/world" ]; then
    echo "The world file does not exist at $stage4_fs/var/lib/portage/world."
    exit 1
fi

if yq '.features[] | select(. == "X")' "$stage4_fs/config.yml" | grep -q X; then
    echo "X is present in features, building Firefox"
    echo "setting up firefox package from packages/www-client/firefox to $stage4_fs/etc/portage/"
    rsync -vrtza packages/www-client/firefox/ "$stage4_fs/etc/portage/"
    # Both stage4 runners have at least 13 GiB RAM. Keep Firefox's compiler
    # processes bounded even when the completed world stage is reused.
    sed -i 's/^MAKEOPTS=.*/MAKEOPTS="-j4 -l4"/' "$stage4_fs/etc/portage/make.conf"
    echo "Building firefox from chroot"
    chroot "$stage4_fs" emerge --update --newuse --oneshot --usepkg --getbinpkg media-libs/libvpx
    chroot "$stage4_fs" emerge --update --usepkg --getbinpkg --jobs=1 --load-average=4 www-client/firefox

    # chromium intentionally NOT built in CI: its ~12-15h from-source compile
    # can't reliably complete on the available runners (the skylake-compatible
    # hosts zgaming/dgaming are desktops that reboot mid-build; the 24/7 R630
    # servers are Haswell Xeons that SIGILL on -march=skylake). firefox covers
    # the browser need; re-add chromium here if a stable skylake-class build
    # host (or a seeded chromium binpkg on the binhost) becomes available.
else
    echo "X is not present in features, not building browsers"
fi
