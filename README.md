# OverTheBox virtual lab

This tool is made for development purposes only. It is only tested on archlinux.

## Requirements

* qemu
* dnsmasq

## Profiles

### Setup

You can configure profiles in the `profile.d` directory. Just add a new
directory and create your own modem files. The modem file contains the wan and
lan IPs. You can also use a custom script to configure your wan by placing it
in the `modem.wan.d` directory. If you use a custom wan script, set the
`MODEM_NETWORK_SCRIPT` variable in the modem configuration.

### Run

```sh
# List all the available commands
sudo ./vlab help
# Setup the modems using the custom_lab profile
sudo ./vlab profile use custom_lab
# Download the latest develop image
sudo ./vlab images download develop
# Use this image for booting qemu
sudo ./vlab images use latest-develop.img
# Start qemu
sudo ./vlab qemu

```
