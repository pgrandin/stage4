# LUKS Full Disk Encryption Setup

This document describes the LUKS encryption setup used for stage4 images.

## Overview

We use **LVM on LUKS** - a single LUKS-encrypted container with LVM logical volumes inside. This provides:
- Single passphrase entry at boot
- Flexible volume management (resize, add volumes)
- Hidden partition layout when locked

## Partition Layout

```
/dev/vda1 (512MB)  → /boot/efi  (vfat, unencrypted, ESP)
/dev/vda2 (512MB)  → /boot      (ext4, unencrypted)
/dev/vda3 (rest)   → LUKS container
  └── crypt-root   → LVM PV (Physical Volume)
      └── vg0      → VG (Volume Group)
          ├── lv_root (80%) → / (ext4)
          └── lv_home (20%) → /home (ext4)
```

### Why This Layout?

1. **EFI System Partition (ESP)** must be unencrypted for UEFI firmware to read bootloader
2. **/boot unencrypted** avoids GRUB cryptodisk complexity:
   - GRUB cryptodisk only supports LUKS1 (not LUKS2 with Argon2)
   - GRUB cryptodisk is slow and requires double passphrase entry
   - Modern approach: unencrypted /boot with signed kernels (Secure Boot)
3. **Single LUKS container** means one passphrase unlocks everything
4. **LVM inside LUKS** allows multiple filesystems without multiple passphrases

## Boot Process

1. UEFI loads GRUB from ESP (`/boot/efi`)
2. GRUB loads kernel and initramfs from `/boot`
3. Initramfs (genkernel) prompts for LUKS passphrase
4. Initramfs opens LUKS container → `/dev/mapper/crypt-root`
5. Initramfs activates LVM → `/dev/vg0/lv_root`, `/dev/vg0/lv_home`
6. Initramfs mounts root and passes control to init
7. OpenRC mounts remaining filesystems from `/etc/fstab`

## Configuration Files

### /etc/crypttab

```
# <name>      <device>                                    <keyfile>  <options>
crypt-root    UUID=<uuid-of-vda3>                         none       luks
```

- `none` for keyfile means interactive passphrase prompt
- Used by initramfs to know which device to unlock

### /etc/fstab

```
# <filesystem>          <mountpoint>  <type>  <options>         <dump> <pass>
/dev/vg0/lv_root        /             ext4    defaults          0      1
/dev/vg0/lv_home        /home         ext4    defaults          0      2
UUID=<esp-uuid>         /boot/efi     vfat    defaults,noatime  0      2
UUID=<boot-uuid>        /boot         ext4    defaults,noatime  0      2
```

### /etc/default/grub

```
GRUB_CMDLINE_LINUX="crypt_root=UUID=<luks-uuid> dolvm root=/dev/vg0/lv_root"
```

Key parameters:
- `crypt_root=UUID=<uuid>` - tells genkernel initramfs which device to unlock
- `dolvm` - activates LVM scanning in genkernel initramfs
- `root=/dev/vg0/lv_root` - root filesystem location after unlock

## Genkernel Configuration

Genkernel must be built with LUKS and LVM support:

### /etc/genkernel.conf

```
# Enable LUKS support in initramfs
LUKS="yes"

# Enable LVM support in initramfs
LVM="yes"
```

### Required Kernel Options

```
CONFIG_BLK_DEV_DM=y           # Device mapper
CONFIG_DM_CRYPT=y             # dm-crypt (LUKS)
CONFIG_CRYPTO_XTS=y           # XTS cipher mode
CONFIG_CRYPTO_AES=y           # AES cipher
CONFIG_CRYPTO_SHA256=y        # SHA256 for LUKS
CONFIG_MD=y                   # Multiple devices (LVM)
CONFIG_BLK_DEV_MD=y           # MD block device
CONFIG_DM_SNAPSHOT=y          # LVM snapshots (optional)
CONFIG_DM_MIRROR=y            # LVM mirrors (optional)
```

## Creating LUKS Setup (Manual Steps)

```bash
# 1. Create partitions
parted /dev/vda mklabel gpt
parted /dev/vda mkpart ESP fat32 1MiB 513MiB
parted /dev/vda set 1 esp on
parted /dev/vda mkpart boot ext4 513MiB 1025MiB
parted /dev/vda mkpart luks 1025MiB 100%

# 2. Create LUKS container
cryptsetup luksFormat --type luks2 /dev/vda3
cryptsetup open /dev/vda3 crypt-root

# 3. Create LVM
pvcreate /dev/mapper/crypt-root
vgcreate vg0 /dev/mapper/crypt-root
lvcreate -l 80%VG -n lv_root vg0
lvcreate -l 100%FREE -n lv_home vg0

# 4. Create filesystems
mkfs.vfat -F32 /dev/vda1
mkfs.ext4 /dev/vda2
mkfs.ext4 /dev/vg0/lv_root
mkfs.ext4 /dev/vg0/lv_home

# 5. Mount and install
mount /dev/vg0/lv_root /mnt
mkdir -p /mnt/{boot,home}
mount /dev/vda2 /mnt/boot
mkdir -p /mnt/boot/efi
mount /dev/vda1 /mnt/boot/efi
mount /dev/vg0/lv_home /mnt/home

# Extract stage4...

# 6. Configure crypttab, fstab, grub (see above)

# 7. Rebuild initramfs
chroot /mnt genkernel --luks --lvm initramfs

# 8. Update GRUB
chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
```

## Host Reference (Dell XPS 9730)

The development host uses the same LVM-on-LUKS pattern:

```
/dev/nvme0n1p1 (1G)   → /boot/efi  (vfat)
/dev/nvme0n1p2 (2G)   → /boot      (ext4)
/dev/nvme0n1p3 (1.9T) → LUKS container (crypto_LUKS)
  └── dm_crypt-0      → LVM PV
      └── ubuntu-vg
          └── ubuntu-lv (1.86T) → / (ext4)
```

crypttab: `dm_crypt-0 UUID=8f7cffdb-de53-4d14-8642-9e881dee3703 none luks`

## Alternatives Considered

### GRUB Cryptodisk (Encrypted /boot)

Pros:
- /boot is encrypted, kernel/initramfs protected at rest

Cons:
- GRUB only supports LUKS1 (not LUKS2 with Argon2)
- Double passphrase entry (GRUB + initramfs) unless using keyfile hack
- Significantly slower unlock in GRUB
- Complex configuration

Verdict: Not recommended for most use cases. Use Secure Boot for boot integrity instead.

### Separate LUKS Partitions (No LVM)

Pros:
- Simpler conceptually
- No LVM overhead

Cons:
- Multiple passphrases or keyfile management
- Cannot resize partitions easily
- Partition layout visible when locked

Verdict: Use LVM-on-LUKS unless you have specific reasons not to.

### Dracut Instead of Genkernel

Pros:
- More modern, actively developed
- Better systemd integration
- Default for Gentoo distribution kernels

Cons:
- Different configuration syntax
- Stage4 currently uses genkernel

Verdict: Consider migrating to dracut in the future, but genkernel works fine.

## Troubleshooting

### "No key available with this passphrase"
- Wrong passphrase
- LUKS header corrupted (restore from backup)

### "Volume group not found"
- Add `dolvm` to kernel command line
- Ensure LVM tools in initramfs

### System boots to initramfs shell
- Check `crypt_root=` UUID matches actual LUKS partition
- Run `cryptsetup open /dev/vda3 crypt-root` manually
- Run `lvm vgscan && lvm vgchange -ay`
- Run `exit` to continue boot

### GRUB drops to shell
- Check grub.cfg paths
- Ensure /boot partition is readable
- Try `configfile (hd0,gpt2)/grub/grub.cfg`
