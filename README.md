# bootstrap

This repository builds a fully bootable distribution for the [menix](https://github.com/menix-os/menix) kernel.

It also includes several ports of popular apps and tools.

## Prerequisites

To build the distribution you will need the following tools installed on your system:

- A POSIX-compatible shell
- GNU make
- curl

To create a bootable image you will additionally need:

- dosfstools (for mkfs.vfat)
- e2fsprogs (for mkfs.ext2)
- parted (for partitioning the image)

To run the built image you will also need QEMU for the target architecture.

## Build instructions

The easiest way to get a bootable image is to run

```sh
make install-all
make image
```

in the root of the repository. This will build the kernel and the distribution and create a
bootable image named `menix.img` in the current directory.

You can also build separate packages by running `$bootstrap/jinx build <package>`
inside the respective build directory for the target architecture.

For example,
to build the `bash` package for the x86_64 architecture, you would run the following commands, assuming you are in the root of the repository:

```sh
$ cd build-x86_64 # Switch to the x86_64 build directory
$ ../jinx build bash # Build the bash package
```

The built package will be located in the `pkgs` directory.

## Running the image

To run the image, you can use the provided make target:

```sh
$ make run-image
```

This will run the image using QEMU with the appropriate options for the target architecture. If you want to pass your own QEMU flags, you can do so by setting the `QEMUFLAGS` variable:

```sh
$ make run-image QEMUFLAGS="-m 512M -smp 4"
```
