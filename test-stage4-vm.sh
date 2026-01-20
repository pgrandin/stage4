#!/bin/bash
#
# test-stage4-vm.sh - Test a Gentoo stage4 archive in a QEMU/libvirt VM
#
# Usage: ./test-stage4-vm.sh <stage4.tgz> [vm-name]
#
# Requirements: qemu-img, qemu-nbd, virsh, virt-install, parted, grub
#

set -e

# Configuration
DISK_SIZE="50G"
RAM_MB="8192"
VCPUS="4"
NBD_DEVICE="/dev/nbd0"
MOUNT_ROOT="/mnt/stage4-test"
LIBVIRT_IMAGES="/var/lib/libvirt/images"

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
    sudo umount "${MOUNT_ROOT}/boot/efi" 2>/dev/null || true
    sudo umount "${MOUNT_ROOT}" 2>/dev/null || true
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

Examples:
    $0 XPS-9730-stage4.tgz
    $0 myimage.tgz my-test-vm
    $0 --size 100G --memory 16384 stage4.tgz

EOF
    exit 1
}

check_requirements() {
    local missing=()

    for cmd in qemu-img qemu-nbd virsh virt-install parted grub-install grub-mkstandalone; do
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

# Step 6: Create fstab
log_info "Creating fstab..."
cat << EOF | sudo tee "${MOUNT_ROOT}/etc/fstab" > /dev/null
# /etc/fstab - Generated by test-stage4-vm.sh
/dev/vda2   /           ext4    defaults,noatime    0 1
/dev/vda1   /boot/efi   vfat    defaults            0 2
EOF

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

# Create standalone GRUB EFI with embedded config
cat << EOF > /tmp/grub-embedded.cfg
set default=0
set timeout=5
set root='hd0,gpt2'
configfile /boot/grub/grub.cfg
EOF

sudo grub-mkstandalone \
    --format=x86_64-efi \
    --output="${MOUNT_ROOT}/boot/efi/EFI/BOOT/BOOTX64.EFI" \
    --modules="part_gpt ext2 normal linux" \
    --locales="" \
    --fonts="" \
    "boot/grub/grub.cfg=/tmp/grub-embedded.cfg" 2>/dev/null || log_warn "grub-mkstandalone had warnings"

# Step 8: Create xinitrc for i3 if i3 is installed
if [[ -x "${MOUNT_ROOT}/usr/bin/i3" ]]; then
    log_info "i3 detected, creating .xinitrc..."
    echo "exec i3" | sudo tee "${MOUNT_ROOT}/root/.xinitrc" > /dev/null
fi

# Step 9: Unmount
log_info "Unmounting..."
sudo umount "${MOUNT_ROOT}/boot/efi"
sudo umount "${MOUNT_ROOT}"
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
echo

if [[ "${NO_START}" == "false" ]]; then
    log_info "Starting VM..."
    sudo virsh start "${VM_NAME}"

    echo
    log_info "Waiting for VM to boot..."
    sleep 10

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
