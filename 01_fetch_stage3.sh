set -e

export stage4_fs="/home/gentoo"

BASEURL="http://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc/"
STAGE3=$(wget -q -O - ${BASEURL} | grep -oP 'href="stage3-amd64-openrc-\d+T\d+Z\.tar\.xz"' | cut -d '"' -f 2 | head -n 1)

wget -nvc ${BASEURL}/$STAGE3
[ -f ${STAGE3} ] && rm -f ${STAGE3%.*}
unxz -k $STAGE3 && tar xpf ${STAGE3%.*} -C ${stage4_fs}

