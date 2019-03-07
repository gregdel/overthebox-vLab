#!/bin/sh
set -e

# lib
. ./lib/lab.sh

[ "$(id -u)" != 0 ] && _log_error "This program must be run as root"

RELEASE="develop"
IMG_URL="http://downloads.overthebox.net/$RELEASE/targets/x86/64/latest.img.gz"
DISK_IMG="otb.img"
IF_NAME="otb0"
UP_SCRIPT=$(pwd)/qemu.hooks.d/ifup
DOWN_SCRIPT=$(pwd)/qemu.hooks.d/ifdown
DEFAULT_IMG_NAME="latest.img.gz"
DISK_IMG="otb.img"
DOCKER_NETWORK="true"

usage() {
	echo "Usage:"
	echo "  --image|-i <image_path> Use this image to create the disk"
	echo "  --disk|-d <disk_path>   Use this disk image to create the kvm"
	echo "  --host-network|-n       Use the host network instead of docker"
}

# Get arguments
IMG_NAME=
while [ -n "$1" ]; do
	case $1 in
		-i | --image )
			IMG_NAME=$2
			shift
			;;
		-d | --disk )
			DISK_IMG=$2
			shift
			;;
		-n | --host-network )
			DOCKER_NETWORK="false"
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

NET_PARAMS="-net nic -net tap,ifname=$IF_NAME,script=$UP_SCRIPT,downscript=$DOWN_SCRIPT"
[ "$DOCKER_NETWORK" = "false" ] && NET_PARAMS="-net nic -net tap,ifname=qemu0,script=no,downscript=no"

# shellcheck disable=2086
qemu-system-x86_64 \
	-enable-kvm \
	-M q35 \
	-m size=1024M \
	-smp cpus=1,cores=1,threads=1 \
	-drive format=raw,file="$DISK_IMG",id=d0,if=none,bus=0,unit=0 -device ide-hd,drive=d0,bus=ide.0 \
	$NET_PARAMS \
	-nographic
