set -e

target=$1

env-update && source /etc/profile
emerge-webrsync

eselect profile set default/linux/amd64/17.1

emerge -q1 dev-lang/perl app-misc/jq app-portage/gentoolkit
FEATURES="-getbinpkg" emerge -q1 XML-Parser
perl-cleaner --reallyall

MAKEOPTS="-j$(nproc)" emerge -NDUq @world --jobs $(nproc)

cp /usr/share/zoneinfo/America/Denver /etc/localtime
echo "America/Denver" > /etc/timezone

netif=$(cat /config.json | jq --arg HOST $target -r '.configs[] | select (.["host"]==$HOST) | .network_interface')

pushd /etc/init.d
ln -s net.lo net.${netif}
rc-update add net.${netif} default
rc-update add sshd default
popd

