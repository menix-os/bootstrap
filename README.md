# bootstrap

This repository builds a fully bootable distribution image for the [menix](https://github.com/menix-os/menix) kernel.

It also includes several ports of popular apps and tools.

## Prerequisites
- xbstrap (via pip or from [source](https://github.com/managarm/xbstrap))
- xbps
- docker

## Build instructions

Name      | Description
----      | ---
`$arch`   | The CPU architecture you're building for, e.g. `x86_64`.
`$source` | The path to the directory where this README is stored.

- Create a new directory, e.g. `build` and change your working directory to it.

- Create a file named `bootstrap-site.yml`

- Fill the file with the following content:
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

- Build the Docker container
```sh
docker build -t menix-buildenv --build-arg=USER=$(id -u) $source/support
```

- Initialize the build directory
```sh
xbstrap init $source
```

- Finally, run
```sh
xbstrap build --all
```
