#!/bin/sh

if [ "$#" -ne 3 ]; then
    echo "Usage: \n"
    echo "$0 <modem> <local_ip> <authorized_public_ip>"
    exit 1
fi

MODEM=$1
LOCAL_IP=$2
AUTHORIZED_IP=$3

echo "Authorizing ${AUTHORIZED_IP} to connect to ${LOCAL_IP} via ${MODEM}"
docker exec ${MODEM} iptables -t nat -F PREROUTING
docker exec ${MODEM} iptables -t nat -A PREROUTING -s ${AUTHORIZED_IP}/32 -p tcp -m tcp --dport 22 -j DNAT --to-destination ${LOCAL_IP}:22
docker exec ${MODEM} iptables -t nat -A PREROUTING -s ${AUTHORIZED_IP}/32 -p tcp -m tcp --dport 443 -j DNAT --to-destination ${LOCAL_IP}:443
echo "Done"

PUBLIC_WAN=$(docker exec ${MODEM} curl -s ifconfig.ovh)
echo "You can now connect with:"
echo "ssh root@${PUBLIC_WAN}"
echo "https://${PUBLIC_WAN}"

