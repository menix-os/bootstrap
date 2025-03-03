#!/bin/bash

set -e

ARCH="$1"
BUILD_ROOT="$2"
PARALLELISM="$3"
OVMF="$4"

QEMU_COMMON_FLAGS="-serial stdio \
	-no-reboot \
	-no-shutdown \
	-m 2G \
	-smp $PARALLELISM \
	-drive format=raw,file=$BUILD_ROOT/menix.img,if=none,id=disk \
	-device nvme,serial=FAKE_SERIAL_ID,drive=disk \
	-netdev user,id=net0 \
	-device virtio-net,disable-modern=on,netdev=net0 \
	"

case $ARCH in
x86_64) QEMU_FLAGS="-cpu host -accel kvm -machine q35,smm=off -bios $OVMF" ;;
*)      QEMU_FLAGS="-cpu max" ;;
esac

echo qemu-system-$ARCH $QEMU_COMMON_FLAGS $QEMU_FLAGS

qemu-system-$ARCH $QEMU_COMMON_FLAGS $QEMU_FLAGS
