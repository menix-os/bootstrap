#!/bin/bash

set -e

OUTPUT_IMAGE="$1"
IMAGE_SIZE="$2"
ESP_SIZE="$3"

# Create an empty disk image
dd if=/dev/zero of="$OUTPUT_IMAGE" bs=1G count=${IMAGE_SIZE%%G}

# Create partitions
parted -s "$OUTPUT_IMAGE" mklabel gpt
parted -s "$OUTPUT_IMAGE" mkpart ESP fat32 1MiB ${ESP_SIZE}
parted -s "$OUTPUT_IMAGE" set 1 esp on
parted -s "$OUTPUT_IMAGE" mkpart ROOT ext4 ${ESP_SIZE} 100%
