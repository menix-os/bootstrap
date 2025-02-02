# bootstrap

This repository builds a fully bootable distribution for the [menix](https://github.com/menix-os/menix) kernel.

It also includes several ports of popular apps and tools.

## Prerequisites
- `xbstrap` (via pip or from [source](https://github.com/managarm/xbstrap))
- `xbps`
- `docker`

## Build instructions

- Create a new directory, e.g. `build` and change your working directory to it. Don't leave this directory.

- Create a file named `bootstrap-site.yml`.

- Fill the file with the following content and replace the `$variables` with the respective values.

Name      | Description
----      | ---
`$arch`   | The CPU architecture you're building for, e.g. `x86_64`.
`$source` | The (relative or absolute) path to the directory where this README is stored.

```yaml
define_options:
  arch: $arch

labels:
  match:
  - $arch
  - noarch

pkg_management:
  format: xbps

container:
  runtime: docker
  image: menix-buildenv
  src_mount: /var/bootstrap-menix/src
  build_mount: /var/bootstrap-menix/build
  allow_containerless: true
```

Then, run the following commands:
```sh
# Build the Docker container
docker build -t menix-buildenv --build-arg=USER=$(id -u) $source/support
# Initialize the build directory
xbstrap init $source
# Build all packages
# Note that this will literally build *every* package and might take a while.
xbstrap build --all
# Create an empty image
xbstrap run empty-image
# Fill the image with files
xbstrap run make-image
```

To test in QEMU, either use the generated image directly, or run:
```sh
xbstrap run qemu
```
