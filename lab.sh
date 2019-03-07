#!/bin/sh
set -e

# lib
. ./lib/lab.sh

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

[ "$(id -u)" != 0 ] && _log_error "This program must be run as root"

case $1 in
	-mc | --modem-create )
		_create_modem "$2" "$3" "$4" "$5"
		;;
	-md | --modem-delete )
		_delete_modem "$2"
		;;
	-me | --modem-enter )
		_modem_enter "$2"
		;;
	-d | --cleanup )
		cleanup
		;;
	-t | --traffic )
		modem_traffic_switch "$2" "$3"
		;;
	-r | --dnat )
		setup_dnat "$2" "$3" "$4"
		;;
	-w | --wan )
		setup_wan_ip "$2" "$3" "$4"
		;;
	-c | --client )
		start_temporary_client
		;;
	-n | --netem )
		modem_qos "$2" "$3" "$4"
		;;
	* )
		_usage
		;;
esac
