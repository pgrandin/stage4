#!/bin/bash

stage4_fs=$1

if [ ! -f "$stage4_fs/var/lib/portage/world" ]; then
    echo "The world file does not exist at $stage4_fs/var/lib/portage/world."
    exit 1
fi

if yq '.features[] | select(. == "X")' "$stage4_fs/config.yml" | grep -q X; then
    echo "X is present in features, building browsers"
    echo "setting up firefox package from packages/www-client/firefox to $stage4_fs/etc/portage/"
    rsync -vrtza packages/www-client/firefox/ $stage4_fs/etc/portage/
    echo "Building firefox from chroot"
    chroot ${stage4_fs} /bin/bash emerge -q www-client/firefox

    echo "setting up chromium package from packages/www-client/chromium to $stage4_fs/etc/portage/"
    rsync -vrtza packages/www-client/chromium/ $stage4_fs/etc/portage/
    echo "Building chromium from chroot"
    chroot ${stage4_fs} /bin/bash emerge -q www-client/chromium
else
    echo "X is not present in features, not building browsers"
fi
