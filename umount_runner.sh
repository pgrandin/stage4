#!/bin/bash

stage4_fs="/stage4-runner/_work/stage4/stage4/stage4"

# Define all mount points in reverse order of how they were mounted
# This is important for properly unmounting without errors
mount_points=(
    "${stage4_fs}/var/cache"
    "${stage4_fs}/var/tmp"
    "${stage4_fs}/dev/shm"
    "${stage4_fs}/dev/pts"
    "${stage4_fs}/dev"
    "${stage4_fs}/proc"
)

for mount_point in "${mount_points[@]}"; do
    if mountpoint -q "$mount_point"; then
        echo "Unmounting $mount_point..."
        umount "$mount_point" || echo "Failed to unmount $mount_point. It might be in use."
    else
        echo "$mount_point is not a mount point."
    fi
done

