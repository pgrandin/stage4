set -e

branch=$1

env-update && source /etc/profile
emerge-webrsync

eselect profile set default/linux/amd64/17.1

wget -q https://github.com/pgrandin/kernel-configs/archive/master.zip -O /tmp/kernel-configs.zip
pushd /tmp/
unzip kernel-configs.zip
popd

MAKEOPTS="-j$(nproc)" emerge -q eix jq
eix-update

kversion=$(eix gentoo-source|awk -F'[()]' '/ [~]5.5/ {version=$2} END{print version}')

echo "=sys-kernel/gentoo-sources-$kversion ~amd64" > /etc/portage/package.keywords/gentoo-sources

MAKEOPTS="-j$(nproc)" FEATURES="-getbinpkg" emerge -q =gentoo-sources-$kversion

cd /usr/src/linux
cat arch/x86/configs/x86_64_defconfig /tmp/kernel-configs-master/common_defconfig > arch/x86/configs/${branch}_defconfig

confs=$(cat /config.json | jq --arg HOST $branch -r '.configs[] | select (.["host"]==$HOST) | .kernel_configs |.[]' )
for conf in $confs; do
    cat /tmp/kernel-configs-master/${conf}_defconfig >> arch/x86/configs/${branch}_defconfig
done
cat /tmp/kernel-configs-master/${branch}_defconfig >> arch/x86/configs/${branch}_defconfig
make defconfig ${branch}_defconfig
make -j$(nproc)
make modules_install
cp arch/x86_64/boot/bzImage /boot/linux-${kversion}-gentoo

echo "efibootmgr -c -d /dev/sda -p 1 -l 'linux-${kversion}-gentoo' -L 'Gentoo-${kversion}'" > /root/setup_efi.sh

MAKEOPTS="-j$(nproc)" emerge -eq @world --jobs $(nproc)

make mrproper

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
