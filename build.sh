#!/bin/bash

set -e

stage4_fs="stage4_fs"

BASEURL="http://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64/"
STAGE3=`wget -q -O - ${BASEURL}|grep -o 'stage3-amd64-2[^<]\{15\}.tar.xz'|uniq`
wget -nv ${BASEURL}/$STAGE3

[[ -e ${STAGE3%.*} ]] && rm ${STAGE3%.*}

unxz -k $STAGE3
[[ -d ${stage4_fs} ]] || mkdir ${stage4_fs}
sudo tar xpf ${STAGE3%.*} -C ${stage4_fs}

rsync -vrtza files/ ${stage4_fs}/

mount -t proc /proc ${stage4_fs}/proc
mount --rbind /sys ${stage4_fs}/sys
mount --make-rslave ${stage4_fs}/sys
mount --rbind /dev ${stage4_fs}/dev
mount --make-rslave ${stage4_fs}/dev

mount -t tmpfs tmpfs ${stage4_fs}/var/cache
mount -t tmpfs tmpfs ${stage4_fs}/var/tmp

cp /etc/resolv.conf ${stage4_fs}/etc/resolv.conf
cp step2.sh ${stage4_fs}/

chroot ${stage4_fs} /bin/bash /step2.sh

for m in var/cache var/tmp dev sys proc; do
	umount -l ${stage4_fs}/$m
done

rsync -vrtza ${stage4_fs}/usr/portage/packages -e "ssh -o StrictHostKeyChecking=no -i gentoo/skylake/stage4builder.rsa" ubuntu@packages.kazer.org:/packages/precision/
