#!/bin/bash

set -e

SYSROOT_DIR="$1"
INITRAMFS_PATH="$(realpath $2)"

# Make sure the initrd doesn't already exist.
rm -f $INITRAMFS_PATH
# `tar` operates on the CWD.
cd $SYSROOT_DIR

# Create a symlink to init.
ln -fs usr/sbin/openrc-init init
ln -fs usr/lib lib
ln -fs usr/bin bin

# Create the initrd with the following files:
FILES=(
    # Common symlinks
    bin
    lib
    # Supporting files
    etc/passwd
    # Modules
    usr/share/menix/modules/*
    # libc and loader
    usr/lib/ld.so
    usr/lib/libc.so
    usr/lib/libpthread.so
    usr/lib/libm.so
    # OpenRC
    init
    usr/sbin/openrc
    usr/sbin/openrc-init
    usr/sbin/openrc-run
    usr/sbin/openrc-shutdown
    usr/sbin/rc-service
    usr/sbin/rc-update
    usr/sbin/start-stop-daemon
    usr/sbin/supervise-daemon
    usr/lib/librc.so*
    usr/lib/libeinfo.so*
    usr/libexec/rc/*
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
    # Test binaries
    usr/bin/test
    usr/bin/fastfetch
)
echo "Installing:" ${FILES[@]}

tar --format=ustar --owner 0 --group 0 -cf $INITRAMFS_PATH "${FILES[@]}"
