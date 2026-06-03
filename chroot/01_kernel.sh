#!/bin/bash

set -e

target=$1
[[ -z ${target} ]] && exit 1
export kpath="linux"

[[ -d /tmp/kernel-configs-master ]] && rm -rf /tmp/kernel-configs-master
# Prepare kernel config
git clone https://github.com/pgrandin/kernel-configs.git /tmp/kernel-configs-master/
export kconfig_sha=$(cd /tmp/kernel-configs-master/ && git rev-parse HEAD)
export kversion=$(eix gentoo-source | awk -F'[()]' '/[[:space:]]~?6\.6\.[0-9]+/{version=$2} END{print version}')

echo "efibootmgr -c -d /dev/nvme0n1 -l '\EFI\gentoo-${kversion}' -L 'Gentoo-${kversion}'" > /root/setup_efi.sh
echo "cp /usr/src/${kpath}/arch/x86/boot/bzImage /boot/efi/EFI/gentoo-${kversion}" >> /root/setup_efi.sh

cat /tmp/kernel-configs-master/common_defconfig /tmp/kernel-configs-master/${target}_defconfig >/${target}_defconfig

confs=$(yq -r '.kernel_fragments[]' /config.yml)
for conf in $confs; do
	echo "# for ${conf}" >>/${target}_defconfig
	cat /tmp/kernel-configs-master/${conf}_defconfig >>/${target}_defconfig
done

# Don't treat compiler warnings as fatal. Stock gentoo-sources sets
# CONFIG_WERROR=y, so a benign upstream warning (e.g. the unused-function
# in drivers/bluetooth/btmtk.h that landed in 6.6.142) aborts the whole
# kernel build. We don't need -Werror for a self-built kernel.
echo "# disable -Werror so benign upstream warnings don't fail the build" >>/${target}_defconfig
echo "CONFIG_WERROR=n" >>/${target}_defconfig

echo "=sys-kernel/gentoo-sources-${kversion} ~amd64" >/etc/portage/package.accept_keywords/gentoo-sources
FEATURES="-getbinpkg" emerge -j$(nproc) -q =gentoo-sources-${kversion} sys-kernel/linux-firmware
cd /usr/src && ln -sf "$(ls -d linux-*-gentoo* 2>/dev/null | sort -V | tail -1)" linux

cat /usr/src/${kpath}/arch/x86/configs/x86_64_defconfig /${target}_defconfig > /usr/src/${kpath}/arch/x86/configs/${target}_defconfig
cd /usr/src/${kpath} && make defconfig ${target}_defconfig

cd /usr/src/${kpath} && make -j$(nproc) && make modules_install

# Use the actual built kernel version for the archive, in case eix and sources diverge
built_kversion=$(make -s -C /usr/src/${kpath} kernelrelease)
tar cvfz /kernel-${kversion}.tgz /lib/modules/${built_kversion} /usr/src/${kpath}/arch/x86_64/boot/bzImage /usr/src/${kpath}/arch/x86/configs/${target}_defconfig
