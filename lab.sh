#!/bin/sh
set -e

NETWORK_NAME=vLab

: "${LAB_NETWORK_PREFIX:=192.168}"
SUBNET="${LAB_NETWORK_PREFIX}.0.0/16"
GATEWAY="${LAB_NETWORK_PREFIX}.0.1"

_log_info() {
	printf "$(tput setaf 5)-->$(tput setaf 2) %s$(tput setaf 7)\n" "$@"
}

_log_error() {
	printf "$(tput setaf 6)-->$(tput setaf 9) %s$(tput setaf 7)\n" "$@"
	exit 1
}

# Creates the modem docker image
build_image() {
	_log_info "Building image..."
	docker build --quiet --tag modem dnsmasq/.
	_log_info "Done building image..."
}

# Creates the lab network
start_network() {
	if docker network inspect $NETWORK_NAME 2>/dev/null >/dev/null; then
		_log_info "The lab network $NETWORK_NAME is already created"
		return 0
	fi

	_log_info "Creating the lab network with the name: $NETWORK_NAME"
	docker network create \
		--driver bridge \
		--subnet "$SUBNET" \
		--gateway "$GATEWAY" \
		"$NETWORK_NAME"
	_log_info "Network created"
}

# Cleanup
cleanup() {
	_log_info "Deleting containers"
	MODEMS=$(docker ps --format '{{ .Names }}' | grep -Eo 'modem[0-9]+')
	for modem in $MODEMS; do
		docker rm -f "$modem"
	done
	_log_info "Deleting network"
	docker network rm $NETWORK_NAME
	_log_info "Network deleted"

	_log_info "Deleting docker images"
	docker rmi modem
	_log_info "Image deleted"
}

# Creates a container with the index $1
start_container() {
	modem_name="modem${1}"

	# Only start the container if it does not exists
	DOCKER_ID=$(docker inspect --format '{{ .Id }}' "$modem_name" 2> /dev/null)
	if [ -n "$DOCKER_ID" ]; then
		_log_info "Modem $1 with name $modem_name already started with id $DOCKER_ID"
		return 0
	fi

	_log_info "Starting modem $1 with name $modem_name ($DOCKER_ID)"
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
	_log_info "$modem_name started"
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
	modem=$1
	local_ip=$2
	authorized_ip=$3

	_log_info "Authorizing $authorized_ip to connect to $local_ip via $modem"
	docker exec "$modem" iptables -t nat -F PREROUTING
	docker exec "$modem" iptables -t nat -A PREROUTING -s "$authorized_ip"/32 -p tcp -m tcp --dport 22 -j DNAT --to-destination "$local_ip":22
	docker exec "$modem" iptables -t nat -A PREROUTING -s "$authorized_ip"/32 -p tcp -m tcp --dport 443 -j DNAT --to-destination "$local_ip":443
	_log_info "DNAT set up"

	public_wan=$(docker exec "$modem" curl -s ifconfig.ovh)
	_log_info "You can now connect with:"
	_log_info "ssh root@$public_wan"
	_log_info "https://$public_wan"
}

modem_traffic_switch() {
	modem=$1
	next_state=$2
	case $next_state in
		on)
			docker exec "$modem" iptables -t filter -P FORWARD ACCEPT
			_log_info "modem traffic allowed";;
		off)
			docker exec "$modem" iptables -t filter -P FORWARD DROP
			_log_info "modem traffic blocked";;
		*)
			_log_error "Only on/off values are allowed";;
	esac
}

modem_qos() {
	modem=$1
	rate=$2
	latency=$3
	_log_info "Setting up $modem with a rate of $rate and a latency of $latency"
	docker exec "$modem" tc qdisc replace dev eth0 root netem rate "$rate" delay "$latency"
	docker exec "$modem" tc qdisc replace dev wan root netem rate "$rate"
	_log_info "QoS setup done"
}

setup_wan_ip() {
	modem=$1
	wan_ip=$2
	if [ -z "$modem" ] || [ -z "$wan_ip" ]; then
		usage
		exit 1
	fi

	# Get the host gw
	host_gw main_interface
	host_gw=$(ip --oneline route get 8.8.8.8 | awk '{ print $3 }')
	main_interface=$(ip --oneline route get 8.8.8.8 | awk '{ print $5 }')

	# Get a PID in the docker to get the correct network namespace
	docker_pid
	docker_pid=$(docker inspect --format '{{.State.Pid}}' "$modem")
	[ "$docker_pid" ] || _log_error "Unable to find the docker PID for $modem"

	_log_info "Creating the interface to add in the docker"
	ip link add link "$main_interface" name wan type macvlan
	_log_info "Interface added"

	_log_info "Addind the interface in the container"
	ip link set dev wan netns "$docker_pid"
	_log_info "Interface added to the container namespace"

	_log_info "Configuring IP"
	docker exec "$modem" ip link set wan up
	docker exec "$modem" ip addr add "$wan_ip"/32 dev wan
	docker exec "$modem" ip route add "$host_gw" dev wan
	docker exec "$modem" ip route change default via "$host_gw"
	_log_info "IP configured"

	_log_info "Configuring iptables"
	docker exec "$modem" iptables -t nat -A POSTROUTING -s "$SUBNET" -o wan -j MASQUERADE
	_log_info "iptables configured"
}

usage() {
	echo "Usage:"
	echo "    --modem|-m <number>                           Creates the lab with a modem with the number <number>"
	echo "    --client|-c                                   Starts a temporary client"
	echo "    --cleanup|-d                                  Cleanup the lab"
	echo "    --dnat|-r <modem> <local_ip> <authorized_ip>  Setup dnat"
	echo "    --wan|-w <modem> <wan_ip>                     Add a public IP on the wan interface of a modem"
	echo "    --traffic|-t <modem> on|off                   Enable or disable the traffic on a modem"
	echo "    --netem|-n <modem> <rate> <latency>           Set the latency and rate of the modem"
	exit 1
}

[ "$(id -u)" -ne 0 ] && _log_error "This program must be run as root"

[ "$#" -lt 1 ] && usage

while [ -n "$1" ]; do
	case $1 in
		-m | --modem )
			build_image
			start_network
			start_container "$2"
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
