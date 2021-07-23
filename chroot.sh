mount -t proc /proc ${stage4_fs}/proc
mount --rbind /dev ${stage4_fs}/dev

chroot /mnt/gentoo/ /bin/bash /step2.sh Z390

umount -l ${stage4_fs}/dev
umount -l ${stage4_fs}/proc

pushd ${stage4_fs}
tar cfz /stage4-.tgz .
popd
