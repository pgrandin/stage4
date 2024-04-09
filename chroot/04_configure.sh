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

[[ -f /etc/conf.d/display-manager ]] && sed -i -e 's/xdm/lightdm/g' /etc/conf.d/display-manager 

useradd pierre
usermod -aG wheel,uucp,audio,video,usb,docker,kvm pierre
