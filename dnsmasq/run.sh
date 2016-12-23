#!/bin/sh

# Setup dnsmasq according to the env vars
/bin/sed -i "s/#DNS_SERVER#/$DNS_SERVER/g" /etc/dnsmasq.conf
/bin/sed -i "s/#LAN_IFACE#/$LAN_IFACE/g" /etc/dnsmasq.conf
/bin/sed -i "s/#LAN_IP#/$LAN_IP/g" /etc/dnsmasq.conf
/bin/sed -i "s/#LAN_RANGE_MIN#/$LAN_RANGE_MIN/g" /etc/dnsmasq.conf
/bin/sed -i "s/#LAN_RANGE_MAX#/$LAN_RANGE_MAX/g" /etc/dnsmasq.conf

exec /usr/bin/supervisord -c /etc/supervisord.conf --nodaemon
