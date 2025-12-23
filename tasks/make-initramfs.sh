#!/bin/bash

set -e

JINX="$(realpath $1)"
BUILD_DIR="$(realpath $2)"
INITRAMFS_DIR="$BUILD_DIR/initramfs"
INITRAMFS_PATH="$(realpath $3)"

# Make sure the initramfs doesn't already exist.
rm -f $INITRAMFS_PATH
mkdir -p $INITRAMFS_DIR

# Install all the programs we want in the initrd to the directory.
cd $BUILD_DIR

# We want these packages in the initramfs.
PKGS=(
    base-files
    menix
    coreutils
    bash
    limine
    mlibc
    dinit
    fastfetch
    menix-utils
)
$JINX reinstall $INITRAMFS_DIR "${PKGS[@]}"

# `tar` operates on the CWD.
cd $INITRAMFS_DIR

# Create a symlink to init.
ln -fs usr/bin/dinit init
ln -fs usr/lib lib
ln -fs usr/bin bin

# From those packages, create the initramfs with the following files.
FILES=(
    # Compatibility symlinks
    bin
    lib
    # Supporting files
    etc/passwd
    # Kernel modules
    usr/share/menix/modules/*
    # libc and loader
    usr/lib/ld.so
    usr/lib/libc.so
    usr/lib/libpthread.so
    usr/lib/libm.so
    usr/lib/libstdc++.so*
    usr/lib/libgcc_s.so*
    # Init
    init
    usr/bin/dinit
    etc/dinit.d/*
    # Shell
    usr/bin/bash
    usr/bin/sh
    etc/bash.bashrc
    etc/bash.bash_logout
    usr/lib/libreadline.so*
    usr/lib/libintl.so*
    usr/lib/libiconv.so*
    usr/lib/libtinfo.so
    usr/lib/libtinfow.so
    # fastfetch
    usr/bin/fastfetch
    # Utils
    usr/bin/mount
    usr/bin/module
)
echo "Installing:" ${FILES[@]}

tar --format=ustar --owner 0 --group 0 -cf $INITRAMFS_PATH "${FILES[@]}"
