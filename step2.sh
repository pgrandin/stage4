#!/bin/bash

set -e

target=$1
[[ -z "${target}" ]] && exit 1

echo "nameserver 1.1.1.1" > /etc/resolv.conf

env-update && source /etc/profile
emerge-webrsync

export AWS_BUCKET="pierre-packages"

eselect profile set default/linux/amd64/17.1

[[ -f /etc/portage/binrepos.conf/gentoobinhost.conf ]] && rm /etc/portage/binrepos.conf/gentoobinhost.conf
[[ -d /var/cache/distfiles ]] || mkdir /var/cache/distfiles

MAKEOPTS="-j$(nproc)" emerge -q eix app-misc/jq awscli gentoolkit dev-vcs/git
[[ -d /var/cache/eix ]] || mkdir /var/cache/eix
chown portage:portage /var/cache/eix
eix-update

aws s3 sync --delete s3://${AWS_BUCKET}/stage4/${target}/binpkgs/ /var/cache/binpkgs/
eclean packages
# push back changes (useful to remove outdated packages right away)
aws s3 sync --delete /var/cache/binpkgs/ s3://${AWS_BUCKET}/stage4/${target}/binpkgs/

[[ -d /tmp/kernel-configs-master ]] && rm -rf /tmp/kernel-configs-master
# Prepare kernel config
git clone https://github.com/pgrandin/kernel-configs.git /tmp/kernel-configs-master/
export kconfig_sha=$(cd /tmp/kernel-configs-master/ && git rev-parse HEAD)
export kversion=$(eix gentoo-source|awk -F'[()]' '/ [~]?6.1./ {version=$2} END{print version}')
cat /tmp/kernel-configs-master/common_defconfig /tmp/kernel-configs-master/${target}_defconfig > /${target}_defconfig

confs=$(cat /config.json | jq --arg HOST target -r '.configs[] | select (.["host"]=="'${target}'") | .kernel_configs |.[]' )
for conf in $confs; do
    echo "# for ${conf}" >> /${target}_defconfig
    cat /tmp/kernel-configs-master/${conf}_defconfig >> /${target}_defconfig
done

echo "=sys-kernel/gentoo-sources-${kversion} ~amd64" > /etc/portage/package.accept_keywords/gentoo-sources
FEATURES="-getbinpkg" emerge -j$(nproc) -q =gentoo-sources-${kversion}
cd /usr/src && ln -sf linux-${kversion}-gentoo linux
export kpath="linux"
cat /usr/src/${kpath}/arch/x86/configs/x86_64_defconfig /${target}_defconfig  > /usr/src/${kpath}/arch/x86/configs/${target}_defconfig
cd /usr/src/${kpath} && make defconfig ${target}_defconfig

cd /usr/src/${kpath} && make -j$(nproc) && make modules_install

tar cvfz /kernel-${kversion}.tgz /lib/modules/${kversion}-gentoo /usr/src/${kpath}/arch/x86_64/boot/bzImage

aws s3 cp /kernel-${kversion}.tgz s3://${AWS_BUCKET}/stage4/${target}/
aws s3 cp /usr/src/${kpath}/arch/x86/configs/${target}_defconfig s3://${AWS_BUCKET}/stage4/${target}/

# Extract PORTAGE_BINHOST value from make.conf
portage_binhost_value=$(grep 'PORTAGE_BINHOST=' /etc/portage/make.conf | cut -d'"' -f2)
# Infer kernel url
kernel_url="${portage_binhost_value%binpkgs/}kernel-${kversion}.tgz"
echo "${kernel_url}"

wget ${kernel_url} -O /tmp/kernel-${kversion}.tgz
tar xvfz /tmp/kernel-${kversion}.tgz -C /

echo "efibootmgr -c -d /dev/nvme0n1 -l '\EFI\gentoo-${kversion}' -L 'Gentoo-${kversion}'" > /root/setup_efi.sh

MAKEOPTS="-j$(nproc)" emerge -eq @world --jobs 4
aws s3 sync --delete /var/cache/binpkgs/ s3://${AWS_BUCKET}/stage4/${target}/binpkgs/

cp /usr/share/zoneinfo/America/Denver /etc/localtime
echo "America/Denver" > /etc/timezone

echo "root:scrambled" | chpasswd

netif=$(cat /config.json | jq --arg HOST "$target" -r '.configs[] | select (.["host"]==$HOST) | .network_interface')

pushd /etc/init.d
ln -s net.lo net.${netif}
rc-update add net.${netif} default
rc-update add sshd default
rc-update add syslog-ng default
popd


sed -i -e "s/localhost/${target}/" /etc/conf.d/hostname

[[ -f /etc/step3.sh ]] && /bin/bash /etc/step3.sh

useradd pierre
usermod -aG wheel,uucp,audio,video,usb,docker,kvm pierre

echo "Interactive shell from step2"
# start an interactive shell
/bin/bash
