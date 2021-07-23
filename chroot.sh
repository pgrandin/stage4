target=$1

echo "Building for target ${target}"

mount -t proc /proc ${stage4_fs}/proc
mount --rbind /dev ${stage4_fs}/dev

chroot /mnt/gentoo/ /bin/bash /step2.sh $target

umount -l ${stage4_fs}/dev
umount -l ${stage4_fs}/proc

rm -rf ${stage4_fs}/var/cache && mkdir ${stage4_fs}/var/cache
rm -rf ${stage4_fs}/var/tmp && mkdir ${stage4_fs}/var/tmp
rm -rf ${stage4_fs}/use/portage && mkdir ${stage4_fs}/usr/portage

pushd ${stage4_fs}
tar cfz /stage4.tgz .
popd
