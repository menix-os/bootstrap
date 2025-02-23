#!/bin/bash

set -e

SYSROOT_DIR="$1"
INITRD_PATH="$2"

rm -f $INITRD_PATH
cd $SYSROOT_DIR
tar --format=ustar -cf $INITRD_PATH *
