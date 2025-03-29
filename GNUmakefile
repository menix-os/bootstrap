ARCH ?= x86_64
SMP ?= 4
QEMUFLAGS ?= -m 2G -serial stdio -smp $(SMP)

override QEMUFLAGS += \
	-no-reboot \
	-no-shutdown \
	-netdev user,id=net0 \
	-device virtio-net,disable-modern=on,netdev=net0 \
	-drive if=pflash,unit=0,format=raw,file=ovmf/ovmf-code-$(ARCH).fd,readonly=on

ifeq ($(shell test -r /dev/kvm && echo $(ARCH)),$(shell uname -m))
    override QEMUFLAGS += -cpu host -accel kvm
else
    override QEMUFLAGS += -cpu max -accel tcg
endif

ifeq ($(ARCH),x86_64)
    override QEMUFLAGS += \
		-machine q35,smm=off
else
    override QEMUFLAGS += \
		-machine virt \
		-device virtio-gpu
endif

jinx:
	curl -Lo $@ https://raw.githubusercontent.com/mintsuki/jinx/789408aae58a56500cc9cca43754cf4e8afc00ee/jinx
	chmod +x $@

ovmf/ovmf-code-$(ARCH).fd:
	mkdir -p ovmf
	curl -Lo $@ https://github.com/osdev0/edk2-ovmf-nightly/releases/latest/download/ovmf-code-$(ARCH).fd
	case "$(ARCH)" in \
		aarch64) dd if=/dev/zero of=$@ bs=1 count=0 seek=67108864 2>/dev/null;; \
		riscv64) dd if=/dev/zero of=$@ bs=1 count=0 seek=33554432 2>/dev/null;; \
	esac

# .PHONY: run-iso
# run-iso: ovmf/ovmf-code-$(ARCH).fd iso

.PHONY: run-image
run-image: ovmf/ovmf-code-$(ARCH).fd image
	qemu-system-$(ARCH) $(QEMUFLAGS) \
		-drive format=raw,file=menix.img,if=none,id=disk \
		-device nvme,serial=FAKE_SERIAL_ID,drive=disk

# .PHONY: iso
# iso: jinx
# 	@./tasks/make-iso.sh

menix.img:
	@PATH=$$PATH:/usr/sbin:/sbin ./tasks/empty-image.sh $@ 2G 100M

build-$(ARCH)/jinx-config:
	@mkdir -p build-$(ARCH)
	@ARCH=$(ARCH) envsubst '$${ARCH}' < support/jinx-config > build-$(ARCH)/jinx-config
	@cp support/jinx-parameters build-$(ARCH)/jinx-parameters

.PHONY: image
image: jinx menix.img build-$(ARCH)/jinx-config
	@cd build-$(ARCH) && ../jinx install sysroot '*'
	@cd build-$(ARCH) && ../jinx host-build limine
	@PATH=$$PATH:/usr/sbin:/sbin ./tasks/make-image.sh build-$(ARCH)/sysroot menix.img $(ARCH)
