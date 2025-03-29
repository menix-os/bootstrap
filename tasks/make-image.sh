#!/bin/bash

set -e

SYSTEM_ROOT="$1"
OUTPUT_IMAGE="$2"
ARCH="$3"

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
ROOT_DIR="$(realpath "$SCRIPT_DIR/..")"
BUILD_DIR="$ROOT_DIR/build-$ARCH"

# Setup loop device
LOOPDEV=$(sudo losetup --find --show --partscan "$OUTPUT_IMAGE")
ESP_PART="${LOOPDEV}p1"
ROOT_PART="${LOOPDEV}p2"

cleanup() {
    # Unmount and detach loop device
    sudo umount "$tmpdir/root/boot" || true
    sudo umount "$tmpdir/root" || true
    sudo losetup -d "$LOOPDEV" || true
    sudo rm -rf "$tmpdir" || true
}

trap 'cleanup' EXIT

# Create temporary directories
tmpdir=$(sudo mktemp -d)
sudo mkdir -p "$tmpdir/root"
# Mount root partition
sudo mount "$ROOT_PART" "$tmpdir/root"
# Mount the ESP inside /boot
sudo mkdir -p "$tmpdir/root/boot"
# FAT has no UIDs, so simulate a user, otherwise cp will complain.
sudo mount -o uid=1000,gid=1000 "$ESP_PART" "$tmpdir/root/boot"

# Copy system root
sudo rsync -avr --checksum "$SYSTEM_ROOT/" "$tmpdir/root"

# Install kernel and modules
sudo cp "$BUILD_DIR/pkgs/menix/usr/share/menix/menix" "$tmpdir/root/boot/"
sudo cp "$BUILD_DIR/pkgs/menix-debug/usr/share/menix/menix-debug" "$tmpdir/root/boot/"
sudo cp "$BUILD_DIR/pkgs/menix-modules/usr/lib/modules/"*.kso "$tmpdir/root/boot/"

# Install bootloader
sudo mkdir -p "$tmpdir/root/boot/EFI/BOOT"

efi_filename=""
case "${ARCH}" in
    x86_64) efi_filename="BOOTX64.EFI" ;;
    aarch64) efi_filename="BOOTAA64.EFI" ;;
    riscv64) efi_filename="BOOTRISCV64.EFI" ;;
    loongarch64) efi_filename="BOOTLOONGARCH64.EFI" ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

sudo cp "$BUILD_DIR/host-pkgs/limine/usr/local/share/limine/${efi_filename}" "$tmpdir/root/boot/EFI/BOOT/"
sudo cp "$ROOT_DIR/support/limine.conf" "$tmpdir/root/boot/"
