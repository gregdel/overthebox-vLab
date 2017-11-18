#!/bin/bash

NETWORK_NAME=vLab

: "${LAB_NETWORK_PREFIX:=192.168}"
SUBNET="${LAB_NETWORK_PREFIX}.0.0/16"
GATEWAY="${LAB_NETWORK_PREFIX}.0.1"

# Creates the modem docker image
build_image() {
	echo "[image] Building..."
	docker build --quiet --tag modem dnsmasq/.
	echo "[image] Done"
}

# Creates the lab network
start_network() {
	if docker network inspect $NETWORK_NAME &> /dev/null; then
		echo "[network] The lab network $NETWORK_NAME is already created"
		return 0
	fi

	echo "[network] Creating the lab network with the name: $NETWORK_NAME"
	docker network create \
		--driver bridge \
		--subnet "$SUBNET" \
		--gateway "$GATEWAY" \
		"$NETWORK_NAME"
	echo "[network] Network created"
}

# Cleanup
cleanup() {
	echo "[cleanup] Deleting dockers"
	MODEMS=$(docker ps --format '{{ .Names }}' | grep -Eo 'modem[0-9]+')
	for modem in $MODEMS; do
		docker rm -f "$modem"
	done
	echo "[cleanup] Deleting network"
	docker network rm $NETWORK_NAME
	echo "[cleanup] Done"

	echo "[cleanup] Deleting docker images"
	docker rmi modem
	echo "[cleanup] Done"
}

# Creates a container with the index $1
start_container() {
	local modem_name="modem${1}"

	# Only start the container if it does not exists
	DOCKER_ID=$(docker inspect --format '{{ .Id }}' "$modem_name" 2> /dev/null)
	if [ -n "$DOCKER_ID" ]; then
		echo "[container $1] $modem_name already started with ID $DOCKER_ID"
		return 0
	fi

	echo "[container $1] Starting $modem_name"
	# Start the docker container
	docker run \
		--detach \
		--network $NETWORK_NAME \
		--ip "${LAB_NETWORK_PREFIX}.${1}.1" \
		--cap-add NET_ADMIN \
		--name "$modem_name" \
		--hostname "$modem_name" \
		--restart always \
		--env LAN_IFACE=eth0 \
		--env DNS_SERVER="8.8.8.8" \
		--env LAN_IP="${LAB_NETWORK_PREFIX}.${1}.1" \
		--env LAN_RANGE_MIN="${LAB_NETWORK_PREFIX}.${1}.50" \
		--env LAN_RANGE_MAX="${LAB_NETWORK_PREFIX}.${1}.100" \
		modem
	echo "[container $1] $modem_name started"
}

# Starts a temporary client
start_temporary_client() {
	docker run \
		-it \
		--rm \
		--network $NETWORK_NAME \
		--cap-add NET_ADMIN \
		alpine sh
}

# Setup a dnat
setup_dnat() {
	local modem=$1
	local local_ip=$2
	local authorized_ip=$3

	echo "[dnat] Authorizing ${authorized_ip} to connect to ${local_ip} via ${modem}"
	docker exec "$modem" iptables -t nat -F PREROUTING
	docker exec "$modem" iptables -t nat -A PREROUTING -s "$authorized_ip"/32 -p tcp -m tcp --dport 22 -j DNAT --to-destination "$local_ip":22
	docker exec "$modem" iptables -t nat -A PREROUTING -s "$authorized_ip"/32 -p tcp -m tcp --dport 443 -j DNAT --to-destination "$local_ip":443
	echo "[dnat] Done"

	public_wan=$(docker exec "$modem" curl -s ifconfig.ovh)
	echo "[dnat] You can now connect with:"
	echo "[dnat] ssh root@${public_wan}"
	echo "[dnat] https://${public_wan}"
}

modem_traffic_switch() {
	local modem=$1
	local next_state=$2
	case $next_state in
		on)
			docker exec "$modem" iptables -t filter -P FORWARD ACCEPT
			echo "modem traffic allowed";;
		off)
			docker exec "$modem" iptables -t filter -P FORWARD DROP
			echo "modem traffic blocked";;
		*)
			echo "Only on/off values are allowed";
			exit 1;
	esac
}

modem_qos() {
	modem=$1
	rate=$2
	latency=$3
	echo "Setting up $modem with a rate of $rate and a latency of $latency"
	docker exec "$modem" tc qdisc replace dev eth0 root netem rate "$rate" delay "$latency"
	docker exec "$modem" tc qdisc replace dev wan root netem rate "$rate"
	echo "Done"
}

setup_wan_ip() {
	local modem=$1
	local wan_ip=$2
	if [ -z "$modem" ] || [ -z "$wan_ip" ]; then
		usage
		exit 1
	fi

	# Get the host gw
	local host_gw main_interface
	host_gw=$(ip --oneline route get 8.8.8.8 | awk '{ print $3 }')
	main_interface=$(ip --oneline route get 8.8.8.8 | awk '{ print $5 }')

	# Get a PID in the docker to get the correct network namespace
	local docker_pid
	docker_pid=$(docker inspect --format '{{.State.Pid}}' "$modem")
	if [ -z "$docker_pid" ]; then
		echo "[wan] Unable to find the docker PID for $modem"
		exit 1
	fi

	echo "[wan] Creating the interface to add in the docker"
	ip link add link "$main_interface" name wan type macvlan
	echo "[wan] Done"

	echo "[wan] Addind the interface in the docker"
	ip link set dev wan netns "$docker_pid"
	echo "[wan] Done"

	echo "[wan] Configuring IP"
	docker exec "$modem" ip link set wan up
	docker exec "$modem" ip addr add "$wan_ip"/32 dev wan
	docker exec "$modem" ip route add "$host_gw" dev wan
	docker exec "$modem" ip route change default via "$host_gw"
	echo "[wan] Done"

	echo "[wan] Configuring iptables"
	docker exec "$modem" iptables -t nat -A POSTROUTING -s "$SUBNET" -o wan -j MASQUERADE
	echo "[wan] Done"
}

usage() {
	echo -e "Usage:"
	echo -e "    --modem|-m <number>                           Creates the lab with a modem with the number <number>"
	echo -e "    --client|-c                                   Starts a temporary client"
	echo -e "    --cleanup|-d                                  Cleanup the lab"
	echo -e "    --dnat|-r <modem> <local_ip> <authorized_ip>  Setup dnat"
	echo -e "    --wan|-w <modem> <wan_ip>                     Add a public IP on the wan interface of a modem"
	echo -e "    --traffic|-t <modem> on|off                   Enable or disable the traffic on a modem"
	echo -e "    --netem|-n <modem> <rate> <latency>           Set the latency and rate of the modem"
	exit 1
}

if [ "$(id -u)" -ne 0 ]; then
	echo "This program must be run as root"
	exit 1
fi
[ "$#" -lt 1 ] && usage

while [ -n "$1" ]; do
	case $1 in
		-m | --modem )
			build_image
			start_network
			start_container "$1"
			shift
			;;
		-d | --cleanup )
			cleanup
			;;
		-t | --traffic )
			modem_traffic_switch "$2" "$3"
			shift 2
			;;
		-r | --dnat )
			setup_dnat "$2" "$3" "$4"
			shift 3
			;;
		-w | --wan )
			setup_wan_ip "$2" "$3"
			shift 2
			;;
		-c | --client )
			start_temporary_client
			;;
		-n | --netem )
			modem_qos "$2" "$3" "$4"
			shift 3
			;;
		* )
			usage
	esac
	shift
done
