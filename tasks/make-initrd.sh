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
    # Modules
    usr/share/menix/modules/*
    # libc and loader
    usr/lib/ld.so
    usr/lib/libc.so
    usr/lib/libpthread.so
    usr/lib/libm.so
    # init
    init
    usr/sbin/openrc-init
    # Shell
    usr/bin/bash
    # Test binary
    usr/bin/test
    usr/bin/fastfetch
    # Libraries
    lib
    usr/lib/librc.so
    usr/lib/librc.so.1
    usr/lib/libeinfo.so
    usr/lib/libeinfo.so.1
    usr/lib/libreadline.so
    usr/lib/libreadline.so.8
    usr/lib/libreadline.so.8.2
    usr/lib/libintl.so
    usr/lib/libintl.so.8
    usr/lib/libintl.so.8.4.2
    usr/lib/libiconv.so
    usr/lib/libiconv.so.2
    usr/lib/libiconv.so.2.7.0
    usr/lib/libtinfo.so
    usr/lib/libtinfow.so
)
echo "Installing:" ${FILES[@]}

tar --format=ustar --owner 0 --group 0 -cf $INITRD_PATH "${FILES[@]}"
