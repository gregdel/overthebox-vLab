#!/bin/sh

if [ "$#" -ne 3 ]; then
    echo "Usage: \n"
    echo "$0 <modem> <rate> <latency>"
    echo "Example: $0 modem1 10mbit 50ms"
    exit 1
fi

MODEM=$1
RATE=$2
LATENCY=$3

MODULE_LOADED=$(sudo lsmod | grep sch_netem | wc -l)
if [ ${MODULE_LOADED} -ne 1 ]; then
    echo "Loading sch_netem kernel module"
    sudo modprobe sch_netem
fi

echo "Setting up ${MODEM} with a rate of ${RATE} and a latency of ${LATENCY}"
docker exec ${MODEM} tc qdisc replace dev wan root netem rate ${RATE} delay ${LATENCY} limit 1000
echo "Done"
