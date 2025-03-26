#!/bin/bash

set -e

ARCH="$1"
BUILD_ROOT="$2"
PARALLELISM="$3"
OVMF="$4"
DEBUG="$5"
KVM="$6"

# Common flags
QEMU_FLAGS="-serial stdio \
	-no-reboot \
	-no-shutdown \
	-m 2G \
	-smp $PARALLELISM \
	-drive format=raw,file=$BUILD_ROOT/menix.img,if=none,id=disk \
	-device nvme,serial=FAKE_SERIAL_ID,drive=disk \
	-netdev user,id=net0 \
	-device virtio-net,disable-modern=on,netdev=net0 \
	-bios $OVMF"

# Debugging
if [[ ${DEBUG} -eq "1" ]]; then
	QEMU_FLAGS="${QEMU_FLAGS} -s -S -d int"
fi

# KVM
if [[ ${KVM} -eq "1" ]]; then
	QEMU_FLAGS="${QEMU_FLAGS} -cpu host -accel kvm"
else
	QEMU_FLAGS="${QEMU_FLAGS} -cpu max -accel tcg"
fi

# Architecture specific flags
case $ARCH in
x86_64)  QEMU_FLAGS="${QEMU_FLAGS} -machine q35,smm=off" ;;
riscv64) QEMU_FLAGS="${QEMU_FLAGS} -machine virt -device virtio-gpu" ;;
*)       QEMU_FLAGS="${QEMU_FLAGS}" ;;
esac

echo qemu-system-$ARCH $QEMU_FLAGS

qemu-system-$ARCH $QEMU_FLAGS
