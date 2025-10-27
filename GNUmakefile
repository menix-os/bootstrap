# ---------------
# Generic targets
# ---------------

ARCH ?= x86_64

# Prepares an ISO with all packages
.PHONY: all
all: minimal-install iso

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
	@git -C jinx-repo checkout d29a3561dc90a7c0b42f62ae9521885f152fc877
	@mv jinx-repo/jinx ./
	@rm -rf jinx-repo

build-$(ARCH)/.jinx-parameters:
	@mkdir -p build-$(ARCH)
	@cd build-$(ARCH) && ../jinx init .. ARCH=$(ARCH)

# Build all packages
.PHONY: full-install
full-install: jinx build-$(ARCH)/.jinx-parameters
	@cd build-$(ARCH) && ../jinx update '*'
	@cd build-$(ARCH) && ../jinx install sysroot '*'

MINIMAL_PKGS = base-files menix limine mlibc openrc bash test fastfetch

# Build only a minimal selection of packages
.PHONY: minimal-install
minimal-install: jinx build-$(ARCH)/.jinx-parameters
	@cd build-$(ARCH) && ../jinx update $(MINIMAL_PKGS)
	@cd build-$(ARCH) && ../jinx install sysroot $(MINIMAL_PKGS)

# --------------
# Image creation
# --------------

build-$(ARCH)/menix.img:
	@PATH=$$PATH:/usr/sbin:/sbin ./tasks/empty-image.sh $@ 2G 256M

.PHONY: build-$(ARCH)/initramfs.tar
build-$(ARCH)/initramfs.tar:
	./tasks/make-initramfs.sh build-$(ARCH)/sysroot $@

# Build a disk image for direct use
.PHONY: image
image: jinx build-$(ARCH)/.jinx-parameters build-$(ARCH)/menix.img build-$(ARCH)/initramfs.tar
	@PATH=$$PATH:/usr/sbin:/sbin ./tasks/make-image.sh \
		build-$(ARCH)/sysroot \
		build-$(ARCH)/initramfs.tar \
		build-$(ARCH)/menix.img \
		$(ARCH)

# Build an ISO image
.PHONY: iso
iso: jinx build-$(ARCH)/.jinx-parameters build-$(ARCH)/initramfs.tar
	./tasks/make-iso.sh \
		build-$(ARCH)/sysroot \
		build-$(ARCH)/initramfs.tar \
		build-$(ARCH)/menix.iso \
		$(ARCH)

# -----------
# Development
# -----------

# Shortcut to build and reinstall the kernel
.PHONY: remake-kernel
remake-kernel: jinx build-$(ARCH)/.jinx-parameters
	@cd build-$(ARCH) && ../jinx build menix
	@cd build-$(ARCH) && ../jinx reinstall sysroot menix

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
	-device virtio-gpu \
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
endif

ifeq ($(ARCH),riscv64)
override QEMUFLAGS += \
	-machine virt,acpi=off
endif

.PHONY: qemu
qemu: ovmf/ovmf-code-$(ARCH).fd build-$(ARCH)/menix.img
	qemu-system-$(ARCH) $(QEMUFLAGS) \
		-drive format=raw,file=build-$(ARCH)/menix.img,if=none,id=disk \
		-device nvme,serial=FAKE_SERIAL_ID,drive=disk

.PHONY: qemu-iso
qemu-iso: ovmf/ovmf-code-$(ARCH).fd build-$(ARCH)/menix.iso
	qemu-system-$(ARCH) $(QEMUFLAGS) -cdrom build-$(ARCH)/menix.iso
