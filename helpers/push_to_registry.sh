#!/bin/bash

IMG_NAME="overthebox"
BASE_URL="http://downloads.overthebox.ovh/stable/x86/64"
IMG_URL="${BASE_URL}/openwrt-x86-64-rootfs.tar.gz"
PACKAGES_FILE="${BASE_URL}/packages/overthebox/Packages"

# Get the verison from the package file of the repo
VERSION=$(curl -s ${PACKAGES_FILE} | grep "Package: overthebox" -A 1 | tail -n 1 | awk '{ print $2 }' | sed 's/-/./')

echo "Image: ${IMG_URL}"
echo "Version: ${VERSION}"

read -p "Continue ? " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi

docker import ${IMG_URL} ${IMG_NAME}
docker tag ${IMG_NAME} gregdel/${IMG_NAME}:${VERSION}
docker push gregdel/${IMG_NAME}:${VERSION}
