# ---------------
# Generic targets
# ---------------

ARCH ?= x86_64

# Prepares a full image with all available packages
.PHONY: all
all: install-all image

# Cleans up the entire build directory
.PHONY: clean
clean:
	rm -rf build-$(ARCH)
	rm -rf .jinx-cache
	rm -rf sources
	rm -f jinx
	@echo "Cleaned repository"

# -------------
# Jinx packages
# -------------

jinx:
	@git clone https://codeberg.org/mintsuki/jinx.git jinx-repo
	@git -C jinx-repo checkout ba224a99377554d60e95a5279717a5cda5a09e45
	@mv jinx-repo/jinx ./
	@rm -rf jinx-repo

build-$(ARCH)/jinx-config:
	@mkdir -p build-$(ARCH)
	@ARCH=$(ARCH) envsubst '$${ARCH}' < support/jinx-config > build-$(ARCH)/jinx-config
	@cp support/jinx-parameters build-$(ARCH)/jinx-parameters

# Build all packages
.PHONY: install-all
install-all: jinx build-$(ARCH)/jinx-config
	@cd build-$(ARCH) && ../jinx build-if-needed '*'
	@cd build-$(ARCH) && ../jinx install sysroot '*'

# Build only a minimal selection of packages (kernel + bootloader + init + shell)
.PHONY: install-minimal
install-minimal: jinx build-$(ARCH)/jinx-config
	@cd build-$(ARCH) && ../jinx build-if-needed minimal
	@cd build-$(ARCH) && ../jinx install sysroot minimal

# --------------
# Image creation
# --------------

build-$(ARCH)/menix.img:
	@PATH=$$PATH:/usr/sbin:/sbin ./tasks/empty-image.sh $@ 1G 100M

# Build a disk image for direct use
.PHONY: image
image: jinx build-$(ARCH)/jinx-config build-$(ARCH)/menix.img
	@PATH=$$PATH:/usr/sbin:/sbin ./tasks/make-image.sh \
		build-$(ARCH)/sysroot \
		build-$(ARCH)/initrd \
		build-$(ARCH)/menix.img \
		$(ARCH)

# Build an ISO image
.PHONY: image
iso: jinx build-$(ARCH)/jinx-config
	./tasks/make-iso.sh \
		build-$(ARCH)/sysroot \
		build-$(ARCH)/initrd \
		build-$(ARCH)/menix.iso \
		$(ARCH)

# -----------
# Development
# -----------

# Shortcut to build and reinstall the kernel
.PHONY: remake-kernel
remake-kernel: jinx build-$(ARCH)/jinx-config
	@cd build-$(ARCH) && ../jinx build menix menix-debug
	@cd build-$(ARCH) && ../jinx reinstall sysroot menix menix-debug

ovmf/ovmf-code-$(ARCH).fd:
	mkdir -p ovmf
	curl -Lo $@ https://github.com/osdev0/edk2-ovmf-nightly/releases/latest/download/ovmf-code-$(ARCH).fd
	case "$(ARCH)" in \
		aarch64) dd if=/dev/zero of=$@ bs=1 count=0 seek=67108864 2>/dev/null;; \
		riscv64) dd if=/dev/zero of=$@ bs=1 count=0 seek=33554432 2>/dev/null;; \
	esac

SMP ?= 4
MEM ?= 2G
KVM ?= 1
QEMUFLAGS ?=

override QEMUFLAGS += -serial stdio \
	-m $(MEM) \
	-smp $(SMP) \
	-no-reboot \
	-no-shutdown \
	-drive if=pflash,unit=0,format=raw,file=ovmf/ovmf-code-$(ARCH).fd,readonly=on

ifeq ($(KVM), 1)
ifeq ($(shell test -r /dev/kvm && echo $(ARCH)),$(shell uname -m))
override QEMUFLAGS += -cpu host,migratable=off -accel kvm
else
override QEMUFLAGS += -cpu max -accel tcg
endif
else
override QEMUFLAGS += -cpu max -accel tcg
endif

ifeq ($(ARCH),x86_64)
override QEMUFLAGS += \
	-machine q35,smm=off
else
override QEMUFLAGS += \
	-machine virt
endif

.PHONY: qemu
qemu: ovmf/ovmf-code-$(ARCH).fd build-$(ARCH)/menix.img
	qemu-system-$(ARCH) $(QEMUFLAGS) \
		-drive format=raw,file=build-$(ARCH)/menix.img,if=none,id=disk \
		-device nvme,serial=FAKE_SERIAL_ID,drive=disk

.PHONY: qemu-iso
qemu-iso: ovmf/ovmf-code-$(ARCH).fd build-$(ARCH)/menix.iso
	qemu-system-$(ARCH) $(QEMUFLAGS) -cdrom build-$(ARCH)/menix.iso
