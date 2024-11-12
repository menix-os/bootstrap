BUILD_DIR?=build
INSTALL_DIR?=build/install
JOBS?=$(shell nproc)
ARCH?=x86_64
QEMU_FLAGS?=
QEMU_BIOS?=/usr/share/qemu/ovmf-x86_64.bin
IMAGE_NAME=menix
ifeq ($(DEBUG),1)
DEBUG_FLAG=--debug
endif

.PHONY: all
all: install

.PHONY: source
source:
	@cargo run --manifest-path=builder/Cargo.toml -- $(DEBUG_FLAG) -j $(JOBS) --arch $(ARCH) source

.PHONY: build
build:
	@cargo run --manifest-path=builder/Cargo.toml -- $(DEBUG_FLAG) -j $(JOBS) --arch $(ARCH) build

.PHONY: configure
configure:
	@cargo run --manifest-path=builder/Cargo.toml -- $(DEBUG_FLAG) -j $(JOBS) --arch $(ARCH) configure

.PHONY: install
install:
	@cargo run --manifest-path=builder/Cargo.toml -- $(DEBUG_FLAG) -j $(JOBS) --arch $(ARCH) install

.PHONY: clean
clean:
	@rm -rf $(BUILD_DIR)
	@echo "Cleaned output files"

ifeq ($(DEBUG),1)
QEMU_DEBUG=-d cpu_reset,int -s -S
endif

QEMU_COMMON=-name "menix $(ARCH)" \
	-serial stdio \
	-no-reboot -no-shutdown \
	-m 8G \
	-smp $(JOBS) \
	-drive format=raw,file=fat:rw:$(INSTALL_DIR),if=none,id=fatfs \
	-device virtio-gpu \
	-netdev user,id=net0 \
	-device virtio-net,disable-modern=on,netdev=net0 \
	-device nvme,serial=deadbeef,drive=fatfs \
	-device qemu-xhci,id=xhci \
	-device usb-kbd,bus=xhci.0 \
	-device usb-mouse,bus=xhci.0 \
	$(QEMU_DEBUG)

.PHONY: qemu qemu-x86_64 qemu-aarch64 qemu-riscv64 qemu-loongarch64
qemu: install qemu-$(ARCH)

qemu-x86_64:
	qemu-system-x86_64 -bios $(QEMU_BIOS) -machine q35 -cpu max -enable-kvm $(QEMU_COMMON) $(QEMU_FLAGS)

qemu-aarch64:
	qemu-system-aarch64 -bios $(QEMU_BIOS) -machine virt -cpu max $(QEMU_COMMON) $(QEMU_FLAGS)

qemu-riscv64:
	qemu-system-riscv64 -bios $(QEMU_BIOS) -machine virt -cpu max $(QEMU_COMMON) $(QEMU_FLAGS)

qemu-loongarch64:
	qemu-system-loongarch64 -bios $(QEMU_BIOS) -machine virt -cpu max $(QEMU_COMMON) $(QEMU_FLAGS)
