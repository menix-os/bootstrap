BUILD_DIR?=build
INSTALL_DIR?=build/install
JOBS?=$(shell nproc)
ARCH?=x86_64
QEMU_FLAGS?=
ifeq ($(DEBUG),1)
DEBUG_FLAG=--debug
endif

###################################

.PHONY: all
all: iso

# Builds an ISO file
.PHONY: iso
iso: install
	@echo "Building an ISO image..."
	# TODO

# Builds a rootfs
.PHONY: rootfs
rootfs: install
	@echo "Building a rootfs image..."
	# TODO


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

# Removes all output files
.PHONY: clean
clean:
	@rm -rf $(BUILD_DIR)
	@echo "Cleaned output files"

########
# QEMU #
########

ifeq ($(DEBUG),1)
QEMU_DEBUG=-d cpu_reset,int -s -S
endif
ifeq ($(FULL),1)
QEMU_FULL=-smp 8 -m 4G \
	-drive file=fat:rw:$(INSTALL_DIR),if=none,id=fatfs \
	-device pcie-pci-bridge,id=bridge1 \
	-device virtio-gpu,bus=bridge1 \
	-device nvme,serial=deadbeef,drive=fatfs,bus=bridge1 \
	-device qemu-xhci,id=xhci,bus=bridge1 \
	-device usb-kbd,bus=xhci.0 \
	-device usb-mouse,bus=xhci.0
else
QEMU_FULL=-drive file=fat:rw:$(INSTALL_DIR)
endif

.PHONY: qemu
qemu: install qemu-$(ARCH)

.PHONY: qemu-x86_64
qemu-x86_64:
	@qemu-system-x86_64 -bios /usr/share/qemu/ovmf-x86_64.bin $(QEMU_DEBUG) -m 8G -no-reboot -no-shutdown -machine q35 -cpu max -serial stdio $(QEMU_FLAGS) $(QEMU_FULL)
