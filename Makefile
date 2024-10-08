BUILD_DIR=build
CACHE_DIR=tmp

###################################

.PHONY: all
all: iso

# Builds an ISO file
.PHONY: iso
iso: dir
	@echo "Building an ISO image..."
# TODO

# Builds a rootfs
.PHONY: rootfs
rootfs: dir
	@echo "Building a rootfs image..."
# TODO

# Only builds to a directory
.PHONY: dir
dir:
# TODO

# Removes all output files
.PHONY: clean
clean:
	@rm -rf $(BUILD_DIR)
	@rm -rf $(CACHE_DIR)
	@rm -rf builder/target/
	@echo "Cleaned output files"

###################################

ifeq ($(DEBUG),1)
QEMU_DEBUG=-d cpu_reset,int -s -S
endif
ifeq ($(FULL),1)
QEMU_FULL=-smp 8 -m 4G \
	-drive file=fat:rw:$(BUILD_DIR),if=none,id=fatfs \
	-device pcie-pci-bridge,id=bridge1 \
	-device virtio-gpu,bus=bridge1 \
	-device nvme,serial=deadbeef,drive=fatfs,bus=bridge1 \
	-device qemu-xhci,id=xhci,bus=bridge1 \
	-device usb-kbd,bus=xhci.0 \
	-device usb-mouse,bus=xhci.0
else
QEMU_FULL=-drive file=fat:rw:$(BUILD_DIR)
endif

.PHONY: qemu-x86_64
qemu-x86_64:
	@qemu-system-x86_64 -bios /usr/share/qemu/ovmf-x86_64.bin $(QEMU_DEBUG) -m 8G -no-reboot -no-shutdown -machine q35 -cpu max -serial stdio $(QEMU_FLAGS) $(QEMU_FULL)
