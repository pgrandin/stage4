#!/bin/bash

export stage4_fs="/stage4-runner/_work/stage4/stage4/stage4"

# Mount proc if not already mounted
if ! mountpoint -q "${stage4_fs}/proc"; then
    mount -t proc proc "${stage4_fs}/proc"
fi

# Mount dev using rbind if not mounted
if ! mountpoint -q "${stage4_fs}/dev"; then
    mount --rbind /dev "${stage4_fs}/dev"
fi

# Mount dev/pts if not mounted
if ! mountpoint -q "${stage4_fs}/dev/pts"; then
    mount -t devpts devpts "${stage4_fs}/dev/pts"
fi

# Mount dev/shm as tmpfs if not mounted
if ! mountpoint -q "${stage4_fs}/dev/shm"; then
    mount -t tmpfs tmpfs "${stage4_fs}/dev/shm"
fi

# Mount var/tmp as tmpfs if not mounted
if ! mountpoint -q "${stage4_fs}/var/tmp"; then
    mount -t tmpfs tmpfs "${stage4_fs}/var/tmp"
fi

# Mount var/cache as tmpfs if not mounted
if ! mountpoint -q "${stage4_fs}/var/cache"; then
    mount -t tmpfs tmpfs "${stage4_fs}/var/cache"
fi

