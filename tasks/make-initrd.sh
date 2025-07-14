#!/bin/bash

set -e

SYSROOT_DIR="$1"
INITRD_PATH="$(realpath $2)"

# Make sure the initrd doesn't already exist.
rm -f $INITRD_PATH
# `tar` operates on the CWD.
cd $SYSROOT_DIR

# Create a symlink to init.
ln -fs usr/sbin/openrc-init init
ln -fs usr/lib lib

# Create the initrd with the following files:
FILES=(
    # libc and loader
    usr/lib/ld.so
    usr/lib/libc.so
    # Kernel modules
    usr/share/menix/modules/*
    # Init
    init
    usr/sbin/openrc-init
    # Shell
    usr/bin/bash
    # Libraries
    lib
    usr/lib/librc.so.1
    usr/lib/libeinfo.so.1
    usr/lib/librc.so
    usr/lib/libeinfo.so
)
echo "Installing:" ${FILES[@]}

tar --format=ustar --owner 0 --group 0 -cf $INITRD_PATH "${FILES[@]}"
