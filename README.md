# bootstrap
Creates a complete distribution image for menix

## Getting started
1. Clone the Git repository.
```
$ git clone https://github.com/menix-os/bootstrap
```

2. Run `make <type>`

`<type>` selects the type of image to create:
- dir:		Only build all packages.
- iso:		Creates an ISO9660 bootable image.
- rootfs:	Creates a rootfs image.

The `make` also command takes optional parameters:
Name | Description | Default | Allowed Values
--- | --- | --- | ----
ARCH | The architecture to build for | x86_64 | x86_64, aarch64, riscv64, loongarch64
DIR | Path to the build directory | build | Paths relative to this directory

Example:
```
$ make iso
```

## Testing in QEMU
The Makefile provides a target to launch a full image in QEMU.
To run it, call:
```
make qemu-<arch>
```
where `<arch>` is the architecture used for step 2.
