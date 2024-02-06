export stage4_fs="/home/gentoo"
target=$1
[[ -z "${target}" ]] && exit 1

mount -t proc /proc ${stage4_fs}/proc
mount --rbind /dev ${stage4_fs}/dev
mount -t tmpfs tmpfs ${stage4_fs}/var/tmp
mount -t tmpfs tmpfs ${stage4_fs}/var/cache


rsync -vrtza files/common/ ${stage4_fs}/
rsync -vrtza files/${target}/ ${stage4_fs}/

cp step2.sh ${stage4_fs}/
cp config.yml ${stage4_fs}/
cp /etc/resolv.conf ${stage4_fs}/etc/

