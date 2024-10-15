# bootstrap
Creates a complete distribution image for menix

## Getting started
1. Clone the Git repository.
```
$ git clone https://github.com/menix-os/bootstrap
```

2. Run `make <type>`

`<type>` selects the type of image to create:
- iso:		Creates an ISO9660 bootable image.
- rootfs:	Creates a rootfs image.

Optionally, you can choose to just build the packages with:
- install:	Run the install step
- build:	Run the build step
- configure:	Run the configure step
- source:	Run the source step

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
