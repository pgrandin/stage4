#!/bin/bash

target=$1
[[ -z "${target}" ]] && exit 1

cp /usr/share/zoneinfo/America/Denver /etc/localtime
echo "America/Denver" > /etc/timezone

echo "root:scrambled" | chpasswd

netif=$(yq -r '.network_interface' /config.yml)

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
