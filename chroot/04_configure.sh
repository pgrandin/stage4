#!/bin/bash

set -e

target=$1
[[ -z ${target} ]] && exit 1

cp /usr/share/zoneinfo/America/Denver /etc/localtime
echo "America/Denver" > /etc/timezone

echo "root:scrambled" | chpasswd

netif=$(yq -r '.network_interface' /config.yml)

pushd /etc/init.d
ln -sf net.lo net.${netif}
rc-update add net.${netif} default
rc-update add sshd default
rc-update add syslog-ng default
popd

sed -i -e "s/localhost/${target}/" /etc/conf.d/hostname

# Install the target's display-manager selection where OpenRC reads it, and
# start it at boot along with the dbus and elogind sessions sddm relies on.
if [[ -f /etc/display-manager ]]; then
  cp /etc/display-manager /etc/conf.d/display-manager
  rc-update add elogind boot
  rc-update add dbus default
  rc-update add display-manager default
fi

if grep -q "app-containers/docker$" /var/lib/portage/world; then
  rc-update add docker default
fi

[[ -f /etc/libvirt/libvirtd.conf ]] && cat <<EOF > /etc/libvirt/libvirtd.conf
auth_unix_ro = "none"
auth_unix_rw = "none"
unix_sock_group = "libvirt"
unix_sock_ro_perms = "0777"
unix_sock_rw_perms = "0770"
EOF

id -u pierre >/dev/null 2>&1 || useradd pierre
usermod -aG wheel,uucp,audio,video,usb,docker,kvm pierre
