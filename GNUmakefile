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
	@rm -rf build-$(ARCH)
	@rm -f jinx
	@echo "Cleaned build directory for $(ARCH)"

# -------------
# Jinx packages
# -------------

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

.PHONY: remake-kernel
remake-kernel: jinx build-$(ARCH)/jinx-config
	@cd build-$(ARCH) && ../jinx build menix menix-debug
	@cd build-$(ARCH) && ../jinx reinstall sysroot menix menix-debug

jinx:
	git clone https://codeberg.org/mintsuki/jinx.git jinx-repo
	git -C jinx-repo checkout 4dff15d1d86ff82d7339f4403c92928e510e1b09
	mv jinx-repo/jinx ./
	rm -rf jinx-repo

build-$(ARCH)/jinx-config:
	@mkdir -p build-$(ARCH)
	@ARCH=$(ARCH) envsubst '$${ARCH}' < support/jinx-config > build-$(ARCH)/jinx-config
	@cp support/jinx-parameters build-$(ARCH)/jinx-parameters

# --------------
# Image creation
# --------------

# Build a disk image for direct use
.PHONY: image
image: jinx build-$(ARCH)/jinx-config menix.img
	@PATH=$$PATH:/usr/sbin:/sbin ./tasks/make-image.sh build-$(ARCH)/sysroot menix.img $(ARCH)

menix.img:
	@PATH=$$PATH:/usr/sbin:/sbin ./tasks/empty-image.sh $@ 1G 100M

# --------------
# QEMU Emulation
# --------------

SMP ?= 4
MEM ?= 2G
KVM ?= 1
QEMUFLAGS ?=

override QEMUFLAGS += -m $(MEM) -serial stdio -smp $(SMP) \
	-no-reboot \
	-no-shutdown \
	-netdev user,id=net0 \
	-device virtio-net,disable-modern=on,netdev=net0 \
	-drive if=pflash,unit=0,format=raw,file=ovmf/ovmf-code-$(ARCH).fd,readonly=on \
	-device virtio-gpu

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
qemu: ovmf/ovmf-code-$(ARCH).fd
	qemu-system-$(ARCH) $(QEMUFLAGS) \
		-drive format=raw,file=menix.img,if=none,id=disk \
		-device nvme,serial=FAKE_SERIAL_ID,drive=disk

ovmf/ovmf-code-$(ARCH).fd:
	mkdir -p ovmf
	curl -Lo $@ https://github.com/osdev0/edk2-ovmf-nightly/releases/latest/download/ovmf-code-$(ARCH).fd
	case "$(ARCH)" in \
		aarch64) dd if=/dev/zero of=$@ bs=1 count=0 seek=67108864 2>/dev/null;; \
		riscv64) dd if=/dev/zero of=$@ bs=1 count=0 seek=33554432 2>/dev/null;; \
	esac
