#!/usr/bin/env bash

# Default values
RELEASE="stable"
BASE_URL="http://downloads.overthebox.ovh/${RELEASE}/x86/64"
IMG_NAME="openwrt-x86-64-combined-squashfs.img.gz"
IMG_URL="${BASE_URL}/${IMG_NAME}"
DISK_IMG="otb.img"
IF_NAME="otb0"
UP_SCRIPT=$(pwd)/qemu-ifup
DOWN_SCRIPT=$(pwd)/qemu-ifdown
DEFAULT_IMG_NAME="openwrt-x86-64-combined-squashfs.img.gz"
DISK_IMG="otb.img"

# Enforce root user
if [ "$(id -u)" -ne 0 ]; then
    echo "This program must be run as root"
    exit 1
fi

usage() {
    echo -e "Usage:"
    echo -e "    --image|-i <image_path> Use this image to create the disk"
    echo -e "    --disk|-d <disk_path>   Use this disk image to create the kvm"
}

# Get arguments
IMG_NAME=""
while [ "$1" != "" ]; do
    case $1 in
        -i | --image )
            shift
            IMG_NAME=$1
            shift
            ;;
        -d | --disk )
            shift
            DISK_IMG=$1
            shift
            ;;
        -h | --help )
            usage
            exit 0
            ;;
    esac
    shift
done

if [ -z "$IMG_NAME" ]; then
    if [ ! -f "$DEFAULT_IMG_NAME" ]; then
        echo "Downloading base image"
        wget "$IMG_URL"
    fi
    IMG_NAME=$DEFAULT_IMG_NAME
else
    if [ ! -f "$IMG_NAME" ]; then
        echo "File $IMG_NAME not found"
        exit 1
    fi
fi

if [ ! -f "$DISK_IMG" ]; then
    echo "Extracting base image"
    gunzip -c "$IMG_NAME" > "$DISK_IMG"
fi

kvm \
    -M q35 \
    -m size=1024M \
    -smp cpus=1,cores=1,threads=1 \
    -drive file="${DISK_IMG}",id=d0,if=none,bus=0,unit=0 -device ide-hd,drive=d0,bus=ide.0 \
    -net nic \
    -net tap,ifname="${IF_NAME}",script="${UP_SCRIPT}",downscript="${DOWN_SCRIPT}" \
    -nographic
