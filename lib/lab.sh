# vim: set ft=sh noexpandtab tabstop=4 shiftwidth=4 softtabstop=4 :

BRIDGE_NAME="vlab"

_usage() {
	echo "Usage:"
	echo "    --modem-create|-mc <number> <wan_ip> <lan_ip> [script] Creates a modem"
	echo "    --modem-delete|-md <number>                            Deletes a modem"
	echo "    --modem-enter|-me <number>                             Enters in the network namespace of the modem"
	echo "    --client|-c                                      Starts a temporary client"
	echo "    --cleanup|-d                                     Cleanup the lab"
	echo "    --dnat|-r <modem> <local_ip> <authorized_ip>     Setup dnat"
	echo "    --traffic|-t <modem> on|off                      Enable or disable the traffic on a modem"
	echo "    --netem|-n <modem> <rate> <latency>              Set the latency and rate of the modem"
	exit 1
}

_log_info() {
	printf "$(tput setaf 5)-->$(tput setaf 2) %s$(tput setaf 7)\n" "$@"
}

_log_error() {
	printf "$(tput setaf 6)-->$(tput setaf 9) %s$(tput setaf 7)\n" "$@"
	exit 1
}

_setup_sysctl() {
	sysctl_conf="/etc/sysctl.d/gregdel-vlab.conf"
	[ -f "$sysctl_conf" ] && return 0

	_log_info "Enabling forwarding on the host"
	cat > "$sysctl_conf" <<-EOF
	net.ipv4.ip_forward = 1
	net.ipv4.conf.all.rp_filter = 0
	EOF
	sysctl -p "$sysctl_conf"
}

_create_modem() {
	modem_number=$1
	wan_ip=$2
	lan_ip=$3
	script=${4:-default}
	[ "$modem_number" ] || usage
	[ "$wan_ip" ] || usage
	[ "$lan_ip" ] || usage

	modem_name="modem$modem_number"

	netns_path="/var/run/netns/$modem_name"
	[ -f "$netns_path" ] && _log_error "$modem_name already exists"

	_setup_sysctl
	_create_lan_bridge

	_log_info "Creating namespace for $modem_name"
	ip netns add "$modem_name"

	_log_info "Adding $wan_ip in container $modem_name using the $script script"

	# Configure the WAN
	"./modem.wan.d/$script" "$modem_name" "$wan_ip"

	# Configure the LAN
	_log_info "Creating veth interface for the LAN"
	pseudo_random_name=$(date +%N)
	lan_name="${modem_name}_lan"
	ip link add "$lan_name" type veth peer name "$pseudo_random_name"
	ip link set "$lan_name" master "$BRIDGE_NAME" up
	ip link set "$pseudo_random_name" netns "$modem_name"
	ip -n "$modem_name" link set "$pseudo_random_name" name lan
	ip -n "$modem_name" link set lo up
	ip -n "$modem_name" link set lan up
	ip -n "$modem_name" addr add "$lan_ip" dev lan
	ip netns exec "$modem_name" iptables -t nat -A POSTROUTING -s "$lan_ip" -o wan -j MASQUERADE
}

_delete_modem() {
	modem_number=$1
	[ "$modem_number" ] || _usage
	modem_name="modem$modem_number"

	_log_info "Deleting namespace for $modem_name"
	ip netns del "$modem_name"

	# TODO delete the bridge if there's nothing in it
}

_modem_enter() {
	modem_number=$1
	[ "$modem_number" ] || _usage
	modem_name="modem$modem_number"
	PS1="[modem $modem_number] # " sudo ip netns exec "$modem_name" sh
}

_create_lan_bridge() {
	ip link show "$BRIDGE_NAME" >/dev/null 2>/dev/null && return 0
	ip link add name "$BRIDGE_NAME" type bridge
	ip link set "$BRIDGE_NAME" up
}
