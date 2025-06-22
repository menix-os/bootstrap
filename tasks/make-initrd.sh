#!/bin/bash

set -e

SYSROOT_DIR="$1"
INITRD_PATH="$(realpath $2)"

# Make sure the initrd doesn't already exist.
rm -f $INITRD_PATH
# `tar` operates on the CWD.
cd $SYSROOT_DIR

# Create the initrd with the following files:
FILES=(
    # libc and loader
    usr/lib/ld.so
    usr/lib/libc.so
    # Kernel modules
    usr/share/menix/modules/*
    # Init
    usr/sbin/openrc-init
    usr/lib/librc.so.1
    usr/lib/libeinfo.so.1
)
echo $FILES
tar --format=ustar --owner 0 --group 0 -cf $INITRD_PATH "${FILES[@]}"
