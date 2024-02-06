export stage4_fs="/home/gentoo"

mount -t proc /proc ${stage4_fs}/proc
mount --rbind /dev ${stage4_fs}/dev
mount -t tmpfs tmpfs ${stage4_fs}/var/tmp
mount -t tmpfs tmpfs ${stage4_fs}/var/cache


rsync -vrtza files/common/ /home/gentoo/
rsync -vrtza files/R710/ /home/gentoo/

cp step2.sh /home/gentoo/
cp config.yml /home/gentoo/
cp /etc/resolv.conf /home/gentoo/etc/

