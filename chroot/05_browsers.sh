#!/bin/bash

stage4_fs=$1

set -x

if [ ! -f "$stage4_fs/var/lib/portage/world" ]; then
    echo "The world file does not exist at $stage4_fs/var/lib/portage/world."
    exit 1
fi

if yq '.features[] | select(. == "X")' "$stage4_fs/config.yml" | grep -q X; then
    echo "X is present in features, building browsers"
    echo "setting up firefox package from packages/www-client/firefox to $stage4_fs/etc/portage/"
    rsync -vrtza packages/www-client/firefox/ $stage4_fs/etc/portage/
    echo "Building firefox from chroot"
    chroot "${stage4_fs}" env -i HOSTNAME=localhost HOME="$HOME" TERM="$TERM" PATH="$PATH" FEATURES="$FEATURES" emerge -q1 media-libs/libvpx
    chroot ${stage4_fs} emerge -q www-client/firefox

    # chromium intentionally NOT built in CI: its ~12-15h from-source compile
    # can't reliably complete on the available runners (the skylake-compatible
    # hosts zgaming/dgaming are desktops that reboot mid-build; the 24/7 R630
    # servers are Haswell Xeons that SIGILL on -march=skylake). firefox covers
    # the browser need; re-add chromium here if a stable skylake-class build
    # host (or a seeded chromium binpkg on the binhost) becomes available.
else
    echo "X is not present in features, not building browsers"
fi
