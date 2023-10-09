set -e

target=$1

env-update && source /etc/profile
emerge-webrsync

eselect profile set default/linux/amd64/17.1

MAKEOPTS="-j$(nproc)" emerge -q eix app-misc/jq
[ -d /var/cache/eix ] || mkdir /var/cache/eix
chown portage:portage /var/cache/eix

eix-update

kversion=$(eix gentoo-source|awk -F'[()]' '/ [~]?6.1./ {version=$2} END{print version}')
echo "=sys-kernel/gentoo-sources-$kversion ~amd64" > /etc/portage/package.accept_keywords/gentoo-sources
MAKEOPTS="-j$(nproc)" FEATURES="-getbinpkg" emerge -q =gentoo-sources-$kversion
pushd /usr/src
ln -s linux-${kversion}-gentoo linux
popd

# Extract PORTAGE_BINHOST value from make.conf
portage_binhost_value=$(grep 'PORTAGE_BINHOST=' /etc/portage/make.conf | cut -d'"' -f2)
# Infer kernel url
kernel_url="${portage_binhost_value%binpkgs/}kernel-${kversion}.tgz"
echo "$kernel_url"

wget ${kernel_url} -O /tmp/kernel-${kversion}.tgz
tar xvfz /tmp/kernel-${kversion}.tgz -C /

echo "efibootmgr -c -d /dev/nvme0n1 -l '\EFI\gentoo-${kversion}' -L 'Gentoo-${kversion}'" > /root/setup_efi.sh

MAKEOPTS="-j$(nproc)" emerge -eq @world --jobs 4

cp /usr/share/zoneinfo/America/Denver /etc/localtime
echo "America/Denver" > /etc/timezone

echo "root:scrambled" | chpasswd

netif=$(cat /config.json | jq --arg HOST $target -r '.configs[] | select (.["host"]==$HOST) | .network_interface')

pushd /etc/init.d
ln -s net.lo net.${netif}
rc-update add net.${netif} default
rc-update add sshd default
rc-update add syslog-ng default
popd


sed -i -e "s/localhost/${target}/" /etc/conf.d/hostname

[ -f /etc/step3.sh ] && /bin/bash /etc/step3.sh

useradd pierre
usermod -aG wheel,uucp,audio,video,usb,docker,kvm pierre
