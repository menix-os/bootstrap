#!/bin/bash

set -e

ARCH="$1"
BUILD_ROOT="$2"
PARALLELISM="$3"

QEMU_COMMON_FLAGS="-serial stdio \
	-no-reboot \
	-no-shutdown \
	-m 2G \
	-smp $PARALLELISM \
	-drive format=raw,file=$BUILD_ROOT/menix.img,if=none,id=disk \
	-netdev user,id=net0 \
	-device virtio-net,disable-modern=on,netdev=net0 \
	-device nvme,serial=deadbeef,drive=disk"

case $ARCH in
x86_64) QEMU_COMMON_FLAGS="$QEMU_COMMON_FLAGS -cpu host -accel kvm -machine q35,smm=off -bios /usr/share/ovmf/x64/OVMF.4m.fd" ;;
*)      QEMU_COMMON_FLAGS="$QEMU_COMMON_FLAGS -cpu max" ;;
esac

echo qemu-system-$ARCH $QEMU_COMMON_FLAGS

qemu-system-$ARCH $QEMU_COMMON_FLAGS
