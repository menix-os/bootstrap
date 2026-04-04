#!/bin/bash

set -e

OUTPUT_IMAGE="$1"
IMAGE_SIZE="$2"
ESP_SIZE="$3"

# Create an empty disk image
truncate -s $IMAGE_SIZE "$OUTPUT_IMAGE"

# Setup loop device
LOOPDEV=$(sudo losetup --find --show "$OUTPUT_IMAGE")
ESP_PART="${LOOPDEV}p1"
ROOT_PART="${LOOPDEV}p2"

# Create partitions
sudo sgdisk "$LOOPDEV" \
    --new=1:1M:+${ESP_SIZE} --typecode=1:C12A7328-F81F-11D2-BA4B-00A0C93EC93B \
    --new=2:0:0 --typecode=2:0FC63DAF-8483-4772-8E79-3D69D8477DE4

# Re-read partition table
sudo partprobe "$LOOPDEV"

# Format partitions
sudo mkfs.vfat -F 32 "$ESP_PART"
sudo mkfs.ext2 "$ROOT_PART"

# Detach
sudo losetup -d "$LOOPDEV"
