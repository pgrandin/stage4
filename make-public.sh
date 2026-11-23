#!/bin/bash
# Convert a separate copy, or finalize a build already using the public policy.
set -euo pipefail
root=$(realpath "${1:?usage: make-public.sh <stage4-working-copy>}")
repo=$(cd -- "$(dirname -- "$0")" && pwd)
python3 "$repo/public_edition.py" configure "$root"
install -Dm755 "$repo/install-extras.sh" "$root/usr/local/sbin/install-stage4-extras"
install -Dm755 "$repo/public_edition.py" "$root/usr/local/libexec/stage4-public-edition.py"

if [[ ${2:-} != --finalize ]]; then
    # Conversion of an existing personal image may need to rebuild consumers.
    chroot "$root" emerge --update --deep --changed-use --with-bdeps=n @world
    chroot "$root" emerge --depclean --with-bdeps=n
    chroot "$root" emerge @preserved-rebuild
fi
mkdir -p "$root/usr/share/stage4"
chroot "$root" python3 /usr/local/libexec/stage4-public-edition.py audit / > "$root/usr/share/stage4/installed-packages.json"

# A public image must not inherit an enabled shared root password or host identity.
chroot "$root" passwd -l root
rm -f "$root"/etc/ssh/ssh_host_* "$root/etc/machine-id" "$root/var/lib/dbus/machine-id" "$root/etc/bind/rndc.key"
touch "$root/etc/machine-id"
rm -f "$root/root/.bash_history"
echo "Public edition prepared and installed packages audited"
