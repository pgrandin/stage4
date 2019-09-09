set -e

branch=$1

env-update && source /etc/profile
emerge-webrsync

eselect profile set default/linux/amd64/17.1

wget -q https://github.com/pgrandin/kernel-configs/archive/master.zip -O /tmp/kernel-configs.zip
pushd /tmp/
unzip kernel-configs.zip
popd

emerge -q eix
eix-update

kversion=$(eix gentoo-source|awk -F'[()]' '/ 4.19/ {version=$2} END{print version}')

echo "=sys-kernel/gentoo-sources-$kversion ~amd64" > /etc/portage/package.keywords/gentoo-sources

FEATURES="-getbinpkg" emerge -q =gentoo-sources-$kversion

cd /usr/src/linux
cat arch/x86/configs/x86_64_defconfig /tmp/kernel-configs-master/docker_defconfig /tmp/kernel-configs-master/${branch}_defconfig > arch/x86/configs/${branch}_defconfig
make defconfig ${branch}_defconfig
make -j8
make modules_install
cp arch/x86_64/boot/bzImage /boot/linux-${kversion}-gentoo

FEATURES="-sandbox -usersandbox" emerge -eq @world

make mrproper

cp /usr/share/zoneinfo/America/Denver /etc/localtime
echo "America/Denver" > /etc/timezone

echo "root:scrambled" | chpasswd

pushd /etc/init.d
ln -s net.lo net.eno1
rc-update add net.eno1 default
rc-update add sshd default
popd


sed -i -e "s/localhost/${branch}/" /etc/conf.d/hostname

useradd pierre
usermod -aG wheel,uucp,audio,video,usb,docker,kvm pierre
