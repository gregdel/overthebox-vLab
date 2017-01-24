#!/usr/bin/env bash

RELEASE="stable"
BASE_URL="http://downloads.overthebox.ovh/${RELEASE}/x86/64"
IMG_NAME="openwrt-x86-64-combined-squashfs.img.gz"
IMG_URL="${BASE_URL}/${IMG_NAME}"
OTB_IMG="otb.img"
IF_NAME="otb0"
UP_SCRIPT=$(pwd)/qemu-ifup
DOWN_SCRIPT=$(pwd)/qemu-ifdown

if [ ! -f ${IMG_NAME} ]; then
    echo "Downloading base image"
    wget ${IMG_URL}
fi

if [ ! -f ${OTB_IMG} ]; then
    echo "Extracting base image"
    gunzip -c ${IMG_NAME} > ${OTB_IMG}
fi

sudo kvm \
    -M q35 \
    -m size=1024M \
    -smp cpus=1,cores=1,threads=1 \
    -drive file=${OTB_IMG},id=d0,if=none,bus=0,unit=0 -device ide-hd,drive=d0,bus=ide.0 \
    -net nic \
    -net tap,ifname=${IF_NAME},script=${UP_SCRIPT},downscript=${DOWN_SCRIPT} \
    -nographic
