#!/bin/bash

set -e

SYSTEM_ROOT="$1"
INITRAMFS_PATH="$2"
OUTPUT_IMAGE="$3"
ARCH="$4"

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
ROOT_DIR="$(realpath "$SCRIPT_DIR/..")"
BUILD_DIR="$ROOT_DIR/build-$ARCH"

cleanup() {
    sudo rm -rf "$tmpdir" || true
}

trap 'cleanup' EXIT

# Setup iso root
tmpdir=$(sudo mktemp -d)
sudo mkdir -p "$tmpdir"
sudo mkdir -p "$tmpdir/EFI/BOOT"

# Install kernel
sudo cp "$BUILD_DIR/sysroot/usr/share/menix/menix.elf" "$tmpdir/menix.elf"

# Install initrd
sudo cp "$INITRAMFS_PATH" "$tmpdir/initramfs.tar"

# Install bootloader
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

sudo cp "$BUILD_DIR/sysroot/usr/share/limine/${efi_filename}" "$tmpdir/EFI/BOOT/"
sudo cp "$BUILD_DIR/sysroot/usr/share/limine/limine-uefi-cd.bin" "$tmpdir/"
sudo cp "$ROOT_DIR/support/limine.conf" "$tmpdir/"

# Build the ISO file
sudo xorriso -as mkisofs -R -r -J --efi-boot limine-uefi-cd.bin \
    -efi-boot-part --efi-boot-image "$tmpdir" -o "$OUTPUT_IMAGE"
