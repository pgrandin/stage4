#!/bin/bash
#
# test-stage4-vm.sh - Test a Gentoo stage4 archive in a QEMU/libvirt VM
#
# Usage: ./test-stage4-vm.sh <stage4.tgz> [vm-name]
#
# Requirements: qemu-img, qemu-nbd, virsh, virt-install, parted, grub, cryptsetup, lvm2
#

set -e

# Configuration
DISK_SIZE="50G"
RAM_MB="8192"
VCPUS="4"
NBD_DEVICE="/dev/nbd0"
MOUNT_ROOT="/mnt/stage4-test"
LIBVIRT_IMAGES="/var/lib/libvirt/images"

# LUKS Configuration
USE_LUKS=false
LUKS_PASSPHRASE="test"  # Default passphrase for testing
LUKS_NAME="crypt-root"
VG_NAME="vg0"
LV_ROOT="lv_root"
LV_HOME="lv_home"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup() {
    log_info "Cleaning up..."
    # Unmount in reverse order
    sudo umount "${MOUNT_ROOT}/run" 2>/dev/null || true
    sudo umount "${MOUNT_ROOT}/sys" 2>/dev/null || true
    sudo umount "${MOUNT_ROOT}/proc" 2>/dev/null || true
    sudo umount "${MOUNT_ROOT}/dev/pts" 2>/dev/null || true
    sudo umount "${MOUNT_ROOT}/dev" 2>/dev/null || true
    sudo umount "${MOUNT_ROOT}/home" 2>/dev/null || true
    sudo umount "${MOUNT_ROOT}/boot/efi" 2>/dev/null || true
    sudo umount "${MOUNT_ROOT}/boot" 2>/dev/null || true
    sudo umount "${MOUNT_ROOT}" 2>/dev/null || true
    # LUKS/LVM cleanup
    if [[ "${USE_LUKS}" == "true" ]]; then
        sudo vgchange -an "${VG_NAME}" 2>/dev/null || true
        sudo cryptsetup close "${LUKS_NAME}" 2>/dev/null || true
    fi
    sudo qemu-nbd --disconnect "${NBD_DEVICE}" 2>/dev/null || true
    sudo rmdir "${MOUNT_ROOT}" 2>/dev/null || true
}

trap cleanup EXIT

usage() {
    cat << EOF
Usage: $0 <stage4.tgz> [vm-name]

Test a Gentoo stage4 archive in a QEMU/libvirt VM.

Arguments:
    stage4.tgz    Path to the stage4 tarball
    vm-name       Optional VM name (default: derived from tarball name)

Options:
    -h, --help    Show this help message
    -s, --size    Disk size (default: ${DISK_SIZE})
    -m, --memory  RAM in MB (default: ${RAM_MB})
    -c, --cpus    Number of vCPUs (default: ${VCPUS})
    --no-start    Don't start the VM after creation
    --delete      Delete existing VM with same name first
    --luks        Enable LUKS full disk encryption (LVM on LUKS)
    --luks-passphrase <pass>  Set LUKS passphrase (default: test)

LUKS Mode:
    When --luks is enabled, the disk layout changes to:
      /dev/vda1 (512MB)  - EFI System Partition
      /dev/vda2 (512MB)  - /boot (unencrypted)
      /dev/vda3 (rest)   - LUKS container with LVM
        └── vg0/lv_root  - Root filesystem
        └── vg0/lv_home  - Home filesystem

    The VM will prompt for the LUKS passphrase at boot.

Examples:
    $0 XPS-9730-stage4.tgz
    $0 myimage.tgz my-test-vm
    $0 --size 100G --memory 16384 stage4.tgz
    $0 --luks --luks-passphrase mypassword stage4.tgz

EOF
    exit 1
}

check_requirements() {
    local missing=()
    local cmds=(qemu-img qemu-nbd virsh virt-install parted grub-install grub-mkstandalone)

    # Add LUKS-specific requirements
    if [[ "${USE_LUKS}" == "true" ]]; then
        cmds+=(cryptsetup pvcreate vgcreate lvcreate)
    fi

    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        exit 1
    fi

    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        log_warn "This script requires sudo privileges"
    fi
}

# Parse arguments
NO_START=false
DELETE_EXISTING=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -s|--size)
            DISK_SIZE="$2"
            shift 2
            ;;
        -m|--memory)
            RAM_MB="$2"
            shift 2
            ;;
        -c|--cpus)
            VCPUS="$2"
            shift 2
            ;;
        --no-start)
            NO_START=true
            shift
            ;;
        --delete)
            DELETE_EXISTING=true
            shift
            ;;
        --luks)
            USE_LUKS=true
            shift
            ;;
        --luks-passphrase)
            LUKS_PASSPHRASE="$2"
            shift 2
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            if [[ -z "${STAGE4_PATH:-}" ]]; then
                STAGE4_PATH="$1"
            elif [[ -z "${VM_NAME:-}" ]]; then
                VM_NAME="$1"
            else
                log_error "Too many arguments"
                usage
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "${STAGE4_PATH:-}" ]]; then
    log_error "No stage4 tarball specified"
    usage
fi

if [[ ! -f "${STAGE4_PATH}" ]]; then
    log_error "Stage4 file not found: ${STAGE4_PATH}"
    exit 1
fi

# Derive VM name from tarball if not specified
if [[ -z "${VM_NAME:-}" ]]; then
    VM_NAME=$(basename "${STAGE4_PATH}" .tgz | sed 's/-stage4$//')
    VM_NAME="${VM_NAME}-test"
fi

DISK_PATH="${LIBVIRT_IMAGES}/${VM_NAME}.qcow2"

log_info "Stage4 testing configuration:"
echo "  Tarball:   ${STAGE4_PATH}"
echo "  VM Name:   ${VM_NAME}"
echo "  Disk:      ${DISK_PATH} (${DISK_SIZE})"
echo "  RAM:       ${RAM_MB} MB"
echo "  vCPUs:     ${VCPUS}"
if [[ "${USE_LUKS}" == "true" ]]; then
    echo "  LUKS:      enabled (passphrase: ${LUKS_PASSPHRASE})"
fi
echo

check_requirements

# Check if VM already exists
if sudo virsh dominfo "${VM_NAME}" &>/dev/null; then
    if [[ "${DELETE_EXISTING}" == "true" ]]; then
        log_info "Deleting existing VM: ${VM_NAME}"
        sudo virsh destroy "${VM_NAME}" 2>/dev/null || true
        sudo virsh undefine "${VM_NAME}" --nvram 2>/dev/null || true
        sudo rm -f "${DISK_PATH}"
    else
        log_error "VM '${VM_NAME}' already exists. Use --delete to remove it first."
        exit 1
    fi
fi

# Step 1: Create disk image
log_info "Creating ${DISK_SIZE} disk image..."
sudo qemu-img create -f qcow2 "${DISK_PATH}" "${DISK_SIZE}"

# Step 2: Connect NBD and partition
log_info "Connecting disk via NBD..."
sudo modprobe nbd max_part=8
sudo qemu-nbd --connect="${NBD_DEVICE}" "${DISK_PATH}"
sleep 1

if [[ "${USE_LUKS}" == "true" ]]; then
    # LUKS mode: EFI + boot + LUKS(LVM)
    log_info "Creating GPT partition table (LUKS mode)..."
    sudo parted "${NBD_DEVICE}" --script \
        mklabel gpt \
        mkpart ESP fat32 1MiB 513MiB \
        set 1 esp on \
        mkpart boot ext4 513MiB 1025MiB \
        mkpart luks 1025MiB 100%

    sudo partprobe "${NBD_DEVICE}"
    sleep 1

    # Step 3: Create LUKS container
    log_info "Creating LUKS container..."
    printf "%s" "${LUKS_PASSPHRASE}" | sudo cryptsetup luksFormat --type luks2 --batch-mode "${NBD_DEVICE}p3" -
    printf "%s" "${LUKS_PASSPHRASE}" | sudo cryptsetup open "${NBD_DEVICE}p3" "${LUKS_NAME}" -

    # Step 4: Create LVM
    log_info "Creating LVM volumes..."
    sudo pvcreate "/dev/mapper/${LUKS_NAME}"
    sudo vgcreate "${VG_NAME}" "/dev/mapper/${LUKS_NAME}"
    sudo lvcreate -l 80%VG -n "${LV_ROOT}" "${VG_NAME}"
    sudo lvcreate -l 100%FREE -n "${LV_HOME}" "${VG_NAME}"

    # Step 5: Format partitions
    log_info "Formatting partitions..."
    sudo mkfs.vfat -F32 -n EFI "${NBD_DEVICE}p1"
    sudo mkfs.ext4 -L boot "${NBD_DEVICE}p2"
    sudo mkfs.ext4 -L root "/dev/${VG_NAME}/${LV_ROOT}"
    sudo mkfs.ext4 -L home "/dev/${VG_NAME}/${LV_HOME}"

    # Get UUIDs
    EFI_UUID=$(sudo blkid -s UUID -o value "${NBD_DEVICE}p1")
    BOOT_UUID=$(sudo blkid -s UUID -o value "${NBD_DEVICE}p2")
    LUKS_UUID=$(sudo blkid -s UUID -o value "${NBD_DEVICE}p3")

    log_info "EFI UUID:  ${EFI_UUID}"
    log_info "Boot UUID: ${BOOT_UUID}"
    log_info "LUKS UUID: ${LUKS_UUID}"

    # Step 6: Mount
    log_info "Mounting partitions..."
    sudo mkdir -p "${MOUNT_ROOT}"
    sudo mount "/dev/${VG_NAME}/${LV_ROOT}" "${MOUNT_ROOT}"
    sudo mkdir -p "${MOUNT_ROOT}/boot"
    sudo mount "${NBD_DEVICE}p2" "${MOUNT_ROOT}/boot"
    sudo mkdir -p "${MOUNT_ROOT}/boot/efi"
    sudo mount "${NBD_DEVICE}p1" "${MOUNT_ROOT}/boot/efi"
    sudo mkdir -p "${MOUNT_ROOT}/home"
    sudo mount "/dev/${VG_NAME}/${LV_HOME}" "${MOUNT_ROOT}/home"
else
    # Standard mode: EFI + root
    log_info "Creating GPT partition table..."
    sudo parted "${NBD_DEVICE}" --script \
        mklabel gpt \
        mkpart ESP fat32 1MiB 513MiB \
        set 1 esp on \
        mkpart root ext4 513MiB 100%

    sudo partprobe "${NBD_DEVICE}"
    sleep 1

    # Step 3: Format partitions
    log_info "Formatting partitions..."
    sudo mkfs.vfat -F32 -n EFI "${NBD_DEVICE}p1"
    sudo mkfs.ext4 -L gentoo "${NBD_DEVICE}p2"

    # Get UUIDs
    EFI_UUID=$(sudo blkid -s UUID -o value "${NBD_DEVICE}p1")
    ROOT_UUID=$(sudo blkid -s UUID -o value "${NBD_DEVICE}p2")

    log_info "EFI UUID:  ${EFI_UUID}"
    log_info "Root UUID: ${ROOT_UUID}"

    # Step 4: Mount and extract stage4
    log_info "Mounting partitions..."
    sudo mkdir -p "${MOUNT_ROOT}"
    sudo mount "${NBD_DEVICE}p2" "${MOUNT_ROOT}"
    sudo mkdir -p "${MOUNT_ROOT}/boot/efi"
    sudo mount "${NBD_DEVICE}p1" "${MOUNT_ROOT}/boot/efi"
fi

log_info "Extracting stage4 (this may take a while)..."
sudo tar -xpf "${STAGE4_PATH}" -C "${MOUNT_ROOT}" --xattrs-include='*.*' --numeric-owner 2>/dev/null || \
sudo tar -xpf "${STAGE4_PATH}" -C "${MOUNT_ROOT}" --numeric-owner

# Step 5: Check for kernel and extract if needed
KERNEL_TGZ=$(find "${MOUNT_ROOT}" -maxdepth 1 -name "kernel-*.tgz" | head -1)
if [[ -n "${KERNEL_TGZ}" ]]; then
    log_info "Found kernel archive: $(basename "${KERNEL_TGZ}")"
    KERNEL_VERSION=$(basename "${KERNEL_TGZ}" .tgz | sed 's/kernel-//')

    # Extract kernel image
    cd "${MOUNT_ROOT}"
    sudo tar -xf "${KERNEL_TGZ}" usr/src/linux/arch/x86_64/boot/bzImage 2>/dev/null || \
    sudo tar -xf "${KERNEL_TGZ}" usr/src/linux/arch/x86/boot/bzImage 2>/dev/null || true

    if [[ -f usr/src/linux/arch/x86_64/boot/bzImage ]]; then
        sudo cp usr/src/linux/arch/x86_64/boot/bzImage "boot/vmlinuz-${KERNEL_VERSION}-gentoo"
    elif [[ -f usr/src/linux/arch/x86/boot/bzImage ]]; then
        sudo cp usr/src/linux/arch/x86/boot/bzImage "boot/vmlinuz-${KERNEL_VERSION}-gentoo"
    fi
    cd - >/dev/null
fi

# Find the kernel
KERNEL=$(find "${MOUNT_ROOT}/boot" -name "vmlinuz-*" -o -name "kernel-*" | head -1)
if [[ -z "${KERNEL}" ]]; then
    log_error "No kernel found in stage4!"
    exit 1
fi
KERNEL_FILE=$(basename "${KERNEL}")
log_info "Using kernel: ${KERNEL_FILE}"

# Create fstab
log_info "Creating fstab..."
if [[ "${USE_LUKS}" == "true" ]]; then
    cat << EOF | sudo tee "${MOUNT_ROOT}/etc/fstab" > /dev/null
# /etc/fstab - Generated by test-stage4-vm.sh (LUKS mode)
/dev/${VG_NAME}/${LV_ROOT}    /           ext4    defaults,noatime    0 1
/dev/${VG_NAME}/${LV_HOME}    /home       ext4    defaults,noatime    0 2
UUID=${BOOT_UUID}             /boot       ext4    defaults,noatime    0 2
UUID=${EFI_UUID}              /boot/efi   vfat    defaults,noatime    0 2
EOF

    # Create crypttab
    log_info "Creating crypttab..."
    cat << EOF | sudo tee "${MOUNT_ROOT}/etc/crypttab" > /dev/null
# /etc/crypttab - Generated by test-stage4-vm.sh
${LUKS_NAME}    UUID=${LUKS_UUID}    none    luks
EOF
else
    cat << EOF | sudo tee "${MOUNT_ROOT}/etc/fstab" > /dev/null
# /etc/fstab - Generated by test-stage4-vm.sh
/dev/vda2   /           ext4    defaults,noatime    0 1
/dev/vda1   /boot/efi   vfat    defaults            0 2
EOF
fi

# Step 7: Install GRUB
log_info "Installing GRUB bootloader..."
sudo grub-install \
    --target=x86_64-efi \
    --efi-directory="${MOUNT_ROOT}/boot/efi" \
    --boot-directory="${MOUNT_ROOT}/boot" \
    --removable \
    --no-nvram 2>/dev/null || log_warn "grub-install had warnings"

# Create GRUB config
log_info "Creating GRUB configuration..."
if [[ "${USE_LUKS}" == "true" ]]; then
    # LUKS mode GRUB config - boot partition is on gpt2
    cat << EOF | sudo tee "${MOUNT_ROOT}/boot/grub/grub.cfg" > /dev/null
set default=0
set timeout=5
set root='hd0,gpt2'

insmod part_gpt
insmod ext2

menuentry "Gentoo Linux (${KERNEL_FILE}) - LUKS" {
    linux /${KERNEL_FILE} rd.luks.uuid=${LUKS_UUID} rd.lvm.lv=${VG_NAME}/${LV_ROOT} rd.lvm.lv=${VG_NAME}/${LV_HOME} root=/dev/mapper/${VG_NAME}-${LV_ROOT} ro console=tty0 console=ttyS0,115200
    initrd /initramfs-${KERNEL_FILE#vmlinuz-}.img
}

menuentry "Gentoo Linux (${KERNEL_FILE}) - LUKS verbose" {
    linux /${KERNEL_FILE} rd.luks.uuid=${LUKS_UUID} rd.lvm.lv=${VG_NAME}/${LV_ROOT} rd.lvm.lv=${VG_NAME}/${LV_HOME} root=/dev/mapper/${VG_NAME}-${LV_ROOT} ro console=tty0 console=ttyS0,115200 rd.debug
    initrd /initramfs-${KERNEL_FILE#vmlinuz-}.img
}
EOF
else
    cat << EOF | sudo tee "${MOUNT_ROOT}/boot/grub/grub.cfg" > /dev/null
set default=0
set timeout=5
set root='hd0,gpt2'

insmod part_gpt
insmod ext2

menuentry "Gentoo Linux (${KERNEL_FILE})" {
    linux /boot/${KERNEL_FILE} root=/dev/vda2 ro console=tty0 console=ttyS0,115200
}

menuentry "Gentoo Linux (${KERNEL_FILE}) - verbose" {
    linux /boot/${KERNEL_FILE} root=/dev/vda2 ro console=tty0 console=ttyS0,115200 earlyprintk=serial,ttyS0,115200
}
EOF
fi

# Create standalone GRUB EFI with embedded config
if [[ "${USE_LUKS}" == "true" ]]; then
    # LUKS mode: boot partition is gpt2, grub.cfg is at /grub/grub.cfg on that partition
    cat << EOF > /tmp/grub-embedded.cfg
set default=0
set timeout=5
set root='hd0,gpt2'
configfile /grub/grub.cfg
EOF
else
    cat << EOF > /tmp/grub-embedded.cfg
set default=0
set timeout=5
set root='hd0,gpt2'
configfile /boot/grub/grub.cfg
EOF
fi

sudo grub-mkstandalone \
    --format=x86_64-efi \
    --output="${MOUNT_ROOT}/boot/efi/EFI/BOOT/BOOTX64.EFI" \
    --modules="part_gpt ext2 normal linux all_video" \
    --locales="" \
    --fonts="" \
    "boot/grub/grub.cfg=/tmp/grub-embedded.cfg" 2>/dev/null || log_warn "grub-mkstandalone had warnings"

# In LUKS mode, also copy grub.cfg to /grub/ on boot partition
if [[ "${USE_LUKS}" == "true" ]]; then
    sudo mkdir -p "${MOUNT_ROOT}/boot/grub"
    sudo cp "${MOUNT_ROOT}/boot/grub/grub.cfg" "${MOUNT_ROOT}/boot/grub/grub.cfg" 2>/dev/null || true
fi

# Create xinitrc for i3 if i3 is installed
if [[ -x "${MOUNT_ROOT}/usr/bin/i3" ]]; then
    log_info "i3 detected, creating .xinitrc..."
    echo "exec i3" | sudo tee "${MOUNT_ROOT}/root/.xinitrc" > /dev/null
fi

# LUKS: Install dracut and generate initramfs with LUKS+LVM support
if [[ "${USE_LUKS}" == "true" ]]; then
    log_info "Setting up LUKS boot support..."

    # Mount chroot prerequisites
    sudo mount --bind /dev "${MOUNT_ROOT}/dev"
    sudo mount --bind /dev/pts "${MOUNT_ROOT}/dev/pts"
    sudo mount --bind /proc "${MOUNT_ROOT}/proc"
    sudo mount --bind /sys "${MOUNT_ROOT}/sys"
    sudo mount --bind /run "${MOUNT_ROOT}/run"

    # Check if dracut is available, install if not
    if ! sudo chroot "${MOUNT_ROOT}" which dracut &>/dev/null; then
        log_info "Installing dracut, cryptsetup, and lvm2..."
        sudo chroot "${MOUNT_ROOT}" emerge --ask=n --getbinpkg=y sys-kernel/dracut sys-fs/cryptsetup sys-fs/lvm2 2>&1 | tail -10
    fi

    # Check lvm USE flag
    if ! sudo chroot "${MOUNT_ROOT}" test -f /sbin/lvm; then
        log_info "Rebuilding lvm2 with lvm USE flag..."
        echo "sys-fs/lvm2 lvm" | sudo tee "${MOUNT_ROOT}/etc/portage/package.use/lvm2" > /dev/null
        sudo chroot "${MOUNT_ROOT}" emerge --ask=n --oneshot sys-fs/lvm2 2>&1 | tail -10
    fi

    # Configure dracut for LUKS+LVM
    sudo mkdir -p "${MOUNT_ROOT}/etc/dracut.conf.d"
    cat << EOF | sudo tee "${MOUNT_ROOT}/etc/dracut.conf.d/crypt.conf" > /dev/null
# Enable LUKS and LVM support
add_dracutmodules+=" crypt dm lvm rootfs-block "
install_items+=" /etc/crypttab "
EOF

    # Check kernel has dm_crypt support
    KERNEL_VERSION="${KERNEL_FILE#vmlinuz-}"
    if ! grep -q "CONFIG_DM_CRYPT=y" "${MOUNT_ROOT}/usr/src/linux/.config" 2>/dev/null; then
        log_warn "Kernel may lack dm_crypt support. Attempting to enable..."
        if [[ -f "${MOUNT_ROOT}/usr/src/linux/.config" ]]; then
            sudo sed -i 's/# CONFIG_DM_CRYPT is not set/CONFIG_DM_CRYPT=y/' "${MOUNT_ROOT}/usr/src/linux/.config"
            log_info "Rebuilding kernel with dm_crypt support..."
            sudo chroot "${MOUNT_ROOT}" bash -c "cd /usr/src/linux && make olddefconfig && make -j\$(nproc) bzImage modules && make modules_install" 2>&1 | tail -20
            sudo cp "${MOUNT_ROOT}/usr/src/linux/arch/x86/boot/bzImage" "${MOUNT_ROOT}/boot/${KERNEL_FILE}"
        fi
    fi

    # Generate initramfs
    log_info "Generating initramfs with LUKS+LVM support..."
    sudo chroot "${MOUNT_ROOT}" dracut --force --kver "${KERNEL_VERSION}" "/boot/initramfs-${KERNEL_VERSION}.img" 2>&1 | grep -E "Including|Error|crypt|lvm" || true

    # Unmount chroot mounts
    sudo umount "${MOUNT_ROOT}/run" 2>/dev/null || true
    sudo umount "${MOUNT_ROOT}/sys" 2>/dev/null || true
    sudo umount "${MOUNT_ROOT}/proc" 2>/dev/null || true
    sudo umount "${MOUNT_ROOT}/dev/pts" 2>/dev/null || true
    sudo umount "${MOUNT_ROOT}/dev" 2>/dev/null || true
fi

# Unmount
log_info "Unmounting..."
if [[ "${USE_LUKS}" == "true" ]]; then
    sudo umount "${MOUNT_ROOT}/home"
    sudo umount "${MOUNT_ROOT}/boot/efi"
    sudo umount "${MOUNT_ROOT}/boot"
    sudo umount "${MOUNT_ROOT}"
    sudo vgchange -an "${VG_NAME}"
    sudo cryptsetup close "${LUKS_NAME}"
else
    sudo umount "${MOUNT_ROOT}/boot/efi"
    sudo umount "${MOUNT_ROOT}"
fi
sudo qemu-nbd --disconnect "${NBD_DEVICE}"
sudo rmdir "${MOUNT_ROOT}" 2>/dev/null || true

# Remove trap since we cleaned up successfully
trap - EXIT

# Step 10: Create and optionally start VM
log_info "Creating libvirt VM definition..."

# Find OVMF firmware (prefer non-Secure Boot version)
OVMF_CODE=""
OVMF_VARS=""
for path in \
    /usr/share/OVMF/OVMF_CODE_4M.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/edk2/ovmf/OVMF_CODE.fd \
    /usr/share/qemu/OVMF_CODE.fd \
    /usr/share/ovmf/OVMF.fd; do
    if [[ -f "$path" ]]; then
        OVMF_CODE="$path"
        break
    fi
done

for path in \
    /usr/share/OVMF/OVMF_VARS_4M.fd \
    /usr/share/OVMF/OVMF_VARS.fd \
    /usr/share/edk2/ovmf/OVMF_VARS.fd; do
    if [[ -f "$path" ]]; then
        OVMF_VARS="$path"
        break
    fi
done

if [[ -z "${OVMF_CODE}" ]]; then
    log_error "OVMF firmware not found. Please install OVMF/edk2."
    exit 1
fi

log_info "Using OVMF: ${OVMF_CODE}"

# Build boot arguments - explicitly disable Secure Boot
BOOT_ARGS="--boot uefi,loader=${OVMF_CODE},loader_ro=yes,loader_type=pflash"
if [[ -n "${OVMF_VARS}" ]]; then
    BOOT_ARGS="${BOOT_ARGS},nvram_template=${OVMF_VARS}"
fi

sudo virt-install \
    --name "${VM_NAME}" \
    --memory "${RAM_MB}" \
    --vcpus "${VCPUS}" \
    --cpu host-passthrough \
    --machine q35 \
    ${BOOT_ARGS} \
    --disk "${DISK_PATH},bus=virtio" \
    --network network=default,model=virtio \
    --graphics spice \
    --video virtio \
    --console pty,target_type=serial \
    --os-variant gentoo \
    --import \
    --noautoconsole \
    --print-xml > "/tmp/${VM_NAME}.xml"

sudo virsh define "/tmp/${VM_NAME}.xml"

log_info "VM '${VM_NAME}' created successfully!"
echo
echo "VM Management:"
echo "  Start:      sudo virsh start ${VM_NAME}"
echo "  Console:    virt-viewer ${VM_NAME}"
echo "  SSH:        ssh root@\$(sudo virsh domifaddr ${VM_NAME} | grep -oE '192\.[0-9.]+') (password: scrambled)"
echo "  Stop:       sudo virsh shutdown ${VM_NAME}"
echo "  Delete:     sudo virsh destroy ${VM_NAME}; sudo virsh undefine ${VM_NAME} --nvram"
if [[ "${USE_LUKS}" == "true" ]]; then
    echo
    echo "LUKS Encryption:"
    echo "  Passphrase: ${LUKS_PASSPHRASE}"
    echo "  The VM will prompt for the passphrase at boot."
    echo "  Use virt-viewer or vncviewer to enter it."
fi
echo

if [[ "${NO_START}" == "false" ]]; then
    log_info "Starting VM..."
    sudo virsh start "${VM_NAME}"

    echo
    if [[ "${USE_LUKS}" == "true" ]]; then
        log_info "VM started. Open virt-viewer to enter LUKS passphrase: ${LUKS_PASSPHRASE}"
        log_info "Waiting for passphrase entry and boot..."
        sleep 5
    else
        log_info "Waiting for VM to boot..."
        sleep 10
    fi

    # Try to get IP
    IP=$(sudo virsh domifaddr "${VM_NAME}" 2>/dev/null | grep -oE '192\.[0-9.]+' | head -1)
    if [[ -n "${IP}" ]]; then
        log_info "VM IP address: ${IP}"
    else
        log_warn "VM IP not yet available. Run: sudo virsh domifaddr ${VM_NAME}"
    fi

    echo
    log_info "To view the VM display, run: virt-viewer ${VM_NAME}"
fi

log_info "Done!"
