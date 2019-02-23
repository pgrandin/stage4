set -e

env-update && source /etc/profile
emerge-webrsync

wget -q https://raw.githubusercontent.com/pgrandin/kernel-configs/master/precision_defconfig -O /tmp/precision_defconfig
wget -q https://raw.githubusercontent.com/pgrandin/kernel-configs/master/docker_defconfig -O /tmp/docker_defconfig
wget -q https://raw.githubusercontent.com/pgrandin/kernel-configs/master/kvm_defconfig -O /tmp/kvm_defconfig

kversion="4.20.8"
FEATURES="-getbinpkg" emerge -q =gentoo-sources-$kversion

cd /usr/src/linux
cat arch/x86/configs/x86_64_defconfig /tmp/docker_defconfig /tmp/precision_defconfig /tmp/kvm_defconfig > arch/x86/configs/precision_defconfig
make defconfig precision_defconfig
make -j8
cp arch/x86_64/boot/bzImage /boot/linux-4.20.8-gentoo
make mrproper

perl-cleaner --all
emerge -q1 dev-perl/XML-Parser
FEATURES="-sandbox -usersandbox" emerge -NDuq @world

curl -L https://github.com/prusa3d/Slic3r/releases/download/version_1.41.3/Slic3rPE-1.41.3+linux64-full-201902121303.AppImage --output /usr/local/bin/Slic3rPE-1.41.3+linux64-full-201902121303.AppImage

cp /usr/share/zoneinfo/America/Denver /etc/localtime
echo "America/Denver" > /etc/timezone

echo "root:scrambled" | chpasswd

pushd /etc/init.d
ln -s net.lo net.eth0
ln -s net.lo net.wlp2s0
rc-update add net.eth0 default
rc-update add sshd default
popd


sed -i -e 's/localhost/dell/' /etc/conf.d/hostname 
sed -i -e 's/"xdm"/"slim"/' /etc/conf.d/xdm
sed -i -e 's/#default_user        simone/default_user        pierre/g' /etc/slim.conf
sed -i -e 's/current_theme       default/current_theme       slim-gentoo-simple/g' /etc/slim.conf
sed -i -e 's/#focus_password      no/focus_password      yes/g' /etc/slim.conf

useradd pierre
usermod -aG wheel,uucp,audio,video,usb,docker,kvm pierre
