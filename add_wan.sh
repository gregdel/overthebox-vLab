#!/bin/sh

if [ "$#" -ne 2 ]; then
    echo "Usage: \n"
    echo "$0 <docker_name> <public_ip>"
    exit 1
fi

WAN_INTERFACE="wan"

DOCKER_NAME=$1
PUBLIC_IP=$2

# Get the host gw
HOST_GW=$(ip --oneline route get 8.8.8.8 | awk '{ print $3 }')
MAIN_INTERFACE=$(ip --oneline route get 8.8.8.8 | awk '{ print $5 }')

# Get a PID in the docker to get the correct network namespace
DOCKER_PID=$(docker inspect --format '{{.State.Pid}}' $DOCKER_NAME)

echo "Creating the interface to add in the docker"
ip link add link ${MAIN_INTERFACE} name ${WAN_INTERFACE} type macvlan
echo "Done"

echo "Addind the interface in the docker"
ip link set dev ${WAN_INTERFACE} netns ${DOCKER_PID}
echo "Done"

echo "Configuring IP"
docker exec ${DOCKER_NAME} ip link set ${WAN_INTERFACE} up
docker exec ${DOCKER_NAME} ip addr add ${PUBLIC_IP}/32 dev ${WAN_INTERFACE}
docker exec ${DOCKER_NAME} ip route add ${HOST_GW} dev ${WAN_INTERFACE}
docker exec ${DOCKER_NAME} ip route del default
docker exec ${DOCKER_NAME} ip route add default via ${HOST_GW}
echo "Done"

echo "Configuring iptables"
docker exec ${DOCKER_NAME} iptables -t nat -A POSTROUTING -s 192.168.0.0/16 -o ${WAN_INTERFACE} -j MASQUERADE
echo "Done"

echo "All done"
