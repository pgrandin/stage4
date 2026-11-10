#!/bin/bash
# Install a published stage4 image on a fresh machine. ERASES THE WHOLE DISK.
#
# Run as root from a live USB booted in UEFI mode (e.g. the Gentoo minimal
# install ISO), with the network up:
#   curl -fsSLO https://raw.githubusercontent.com/pgrandin/stage4/master/install.sh
#   bash install.sh /dev/nvme0n1 [XPS-9730]
#
# Layout: partition 1 = 1 GiB ESP (/boot/efi), partition 2 = ext4 root. The
# kernel boots straight from the ESP (EFI stub, no initramfs) and finds root
# through the PARTUUID built into its command line, so partition 2 gets it.
set -euo pipefail

yes=
[[ ${1:-} == --yes ]] && { yes=1; shift; }
disk=${1:?usage: install.sh [--yes] <disk> [target]}
target=${2:-XPS-9730}
url=https://s3.sd.kazer.org/public-artifacts/stage4/$target/$target-stage4.tgz
mnt=/mnt/gentoo

die() { echo "install.sh: $*" >&2; exit 1; }
[[ -b $disk ]] || die "$disk is not a block device"
[[ -d /sys/firmware/efi ]] || die "boot the USB key in UEFI mode"
if [[ -z $yes ]]; then
    lsblk "$disk"
    read -rp "Erase everything on $disk? Type $disk to confirm: " answer
    [[ $answer == "$disk" ]] || die "aborted"
fi

[[ $disk == *[0-9] ]] && part=${disk}p || part=$disk   # nvme0n1p1 vs sda1
sgdisk --zap-all "$disk"
sgdisk -n1:0:+1G -t1:ef00 -n2:0:0 -t2:8304 "$disk"
partprobe "$disk"
udevadm settle
mkfs.vfat -F 32 -n EFI "${part}1"
mkfs.ext4 -F -q -L gentoo "${part}2"

mkdir -p "$mnt"
mount "${part}2" "$mnt"
mkdir -p "$mnt/boot/efi"
mount "${part}1" "$mnt/boot/efi"

echo "Downloading and extracting $url"
curl -fsSL "$url" | tar xzpf - --xattrs-include='*.*' --numeric-owner -C "$mnt"

partuuid=$(grep -o 'root=PARTUUID=[0-9a-fA-F-]*' "$mnt/usr/src/linux/.config" | cut -d= -f3)
[[ -n $partuuid ]] || die "kernel has no built-in root=PARTUUID"
cat > "$mnt/etc/fstab" <<EOF
PARTUUID=$partuuid	/		ext4	noatime		0 1
UUID=$(blkid -s UUID -o value "${part}1")	/boot/efi	vfat	noatime,umask=0077	0 2
EOF

# /root/setup_efi.sh (written by the kernel build) copies the kernel to the ESP
# and adds a firmware boot entry for it.
mountpoint -q /sys/firmware/efi/efivars || mount -t efivarfs efivarfs /sys/firmware/efi/efivars
mount -t proc proc "$mnt/proc"
mount --rbind /sys "$mnt/sys" && mount --make-rslave "$mnt/sys"
mount --rbind /dev "$mnt/dev" && mount --make-rslave "$mnt/dev"
mkdir -p "$mnt/boot/efi/EFI"
sed "s#/dev/nvme0n1#$disk#" "$mnt/root/setup_efi.sh" | chroot "$mnt" /bin/bash -e
umount -R "$mnt"

sgdisk --partition-guid="2:$partuuid" "$disk"
echo "Installed $target on $disk. Remove the USB key and reboot; root's password is 'scrambled', change it."
