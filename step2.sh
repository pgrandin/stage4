set -e

branch=$1

env-update && source /etc/profile
emerge-webrsync

eselect profile set default/linux/amd64/17.1

MAKEOPTS="-j$(nproc)" emerge -q eix app-misc/jq
eix-update

kversion=$(eix gentoo-source|awk -F'[()]' '/ [~]?5.10/ {version=$2} END{print version}')
echo "=sys-kernel/gentoo-sources-$kversion ~amd64" > /etc/portage/package.keywords/gentoo-sources

wget http://packages.kazer.org:8080/Z390/kernel-${kversion}.tgz -O /tmp/kernel.tgz
tar xvfz /tmp/kernel.tgz -C /
pushd /usr/src
ln -s linux-${kversion}-gentoo linux
popd

echo "efibootmgr -c -d /dev/sda -p 1 -l 'linux-${kversion}-gentoo' -L 'Gentoo-${kversion}'" > /root/setup_efi.sh

MAKEOPTS="-j$(nproc)" emerge -eq @world --jobs 4

cp /usr/share/zoneinfo/America/Denver /etc/localtime
echo "America/Denver" > /etc/timezone

echo "root:scrambled" | chpasswd

netif=$(cat /config.json | jq --arg HOST $branch -r '.configs[] | select (.["host"]==$HOST) | .network_interface')

pushd /etc/init.d
ln -s net.lo net.${netif}
rc-update add net.${netif} default
rc-update add sshd default
rc-update add syslog-ng default
popd


sed -i -e "s/localhost/${branch}/" /etc/conf.d/hostname

[ -f /etc/step3.sh ] && /bin/bash /etc/step3.sh

useradd pierre
usermod -aG wheel,uucp,audio,video,usb,docker,kvm pierre
