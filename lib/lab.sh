# vim: set ft=sh noexpandtab tabstop=4 shiftwidth=4 softtabstop=4 :

IMG_DIR=$(pwd)/images
PROFILE_DIR=$(pwd)/profile.d
CURRENT_PROFILE="$PROFILE_DIR/current"
BRIDGE_NAME="vlab"
QEMU_UP_SCRIPT=$(pwd)/qemu.hooks.d/ifup
QEMU_DOWN_SCRIPT=$(pwd)/qemu.hooks.d/ifdown
QEMU_IMAGE="$IMG_DIR/otb.img"

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

_dhcp_server_start() {
	modem_name=$1
	# shellcheck source=/dev/null
	.  "$CURRENT_PROFILE/$modem_name"
	modem_ip=${MODEM_PRIVATE_IP%%/*}

	ip netns exec "$modem_name" \
		dnsmasq \
			--interface lan \
			--server 1.1.1.1 \
			--server 8.8.8.8 \
			--port 0 \
			--no-resolv \
			--dhcp-range="$modem_ip,${modem_ip}00,12h"
}

_dhcp_server_stop() {
	modem_name=$1
	ip netns exec "$modem_name" lsof -i -n | grep dnsmasq | awk '{ print $2 }' | xargs kill
}

_modem_up() {
	modem_name=$1
	# shellcheck source=/dev/null
	.  "$CURRENT_PROFILE/$modem_name"

	[ "$MODEM_PUBLIC_IP" ] || _log_err "Missing modem public_ip in profile:$profile file:$filename"
	[ "$MODEM_PRIVATE_IP" ] || _log_err "Missing modem private_ip in profile:$profile file:$filename"

	script=${MODEM_NETWORK_SCRIPT:-default}

	netns_path="/var/run/netns/$modem_name"
	[ -f "$netns_path" ] && _log_error "$modem_name already exists"

	_setup_sysctl

	_log_info "Creating namespace for $modem_name"
	ip netns add "$modem_name"

	# Configure the WAN
	_log_info "Adding $MODEM_PUBLIC_IP in container $modem_name using the $script script"
	"./modem.wan.d/$script" "$modem_name" "$MODEM_PUBLIC_IP"

	# Configure the LAN
	_log_info "Configuring the lan interface"
	lan_ifname=${modem_name}_lan
	ip link set "$lan_ifname" netns "$modem_name"
	ip -n "$modem_name" link set "$lan_ifname" name lan
	ip -n "$modem_name" link set lo up
	ip -n "$modem_name" link set lan up

	ip -n "$modem_name" addr add "$MODEM_PRIVATE_IP" dev lan
	ip netns exec "$modem_name" iptables -t nat -A POSTROUTING -s "$MODEM_PRIVATE_IP" -o wan -j MASQUERADE

	_dhcp_server_start "$modem_name"
}

_modem_down() {
	modem_name=$1
	# shellcheck source=/dev/null
	.  "$CURRENT_PROFILE/$modem_name"

	_log_info "Deleting namespace for $modem_name"
	ip -n "$modem_name" link del lan
	_dhcp_server_stop "$modem_name"
	ip netns del "$modem_name"
}

_namespace_enter() {
	ns=$1
	[ "$ns" ] || _log_error "Invalid namespace $ns"
	PS1="[$ns] # " sudo ip netns exec "$ns" sh
}

_modem_show() {
	profile=$1
	filename=$2
	modem_conf="$PROFILE_DIR/$profile/$filename"
	[ -f "$modem_conf" ] || _log_err "Modem $filename not found in $profile"
	echo "* $filename:"
	cat "$modem_conf"
}

_lan_up() {
	ip link add name "$BRIDGE_NAME" type bridge
	ip link set "$BRIDGE_NAME" up
	ip link set "$1" master "$BRIDGE_NAME" up
	ip addr add 192.168.100.10/24 dev "$BRIDGE_NAME"
}

_lan_down() {
	ip link del "$1"
	ip link del "$BRIDGE_NAME"
}

_profile_list() {
	echo "Profiles:"

	selected_name=$(basename "$(readlink "$PROFILE_DIR/current")")

	for profile in "$PROFILE_DIR"/*; do
		name=$(basename "$profile")
		sign=" *"
		[ "$name" == "current" ] && continue
		[ "$name" == "$selected_name" ] && sign="->"
		echo "$sign $name"
	done
}

_profile_show() {
	shift
	profile=$1
	[ "$profile" ] || _log_error "Missing profile name"
	profile_dir="$PROFILE_DIR/$profile"

	echo "Configuration for profile $profile:"
	for file in "$profile_dir"/*; do
		name=$(basename "$file")
		case "$name" in
			modem*) _modem_show "$profile" "$name" ;;
		esac
	done
}

_profile_use() {
	shift
	profile=$1
	[ "$profile" ] || _log_error "Missing profile name"

	ln -sf "$PROFILE_DIR/$profile" "$CURRENT_PROFILE" || true
	_log_info "Using $profile as the current profile for qemu"
}

_qemu_default_net_params() {
	ifname=$1
	echo "-netdev tap,id=$ifname,ifname=$ifname,script=$QEMU_UP_SCRIPT,downscript=$QEMU_DOWN_SCRIPT -device e1000,netdev=$ifname"
}

_qemu_start() {
	# Default lan
	net_params=$(_qemu_default_net_params "vlab_lan")
	for file in "$CURRENT_PROFILE"/*; do
		name=$(basename "$file")
		case "$name" in
			modem*)
				# shellcheck source=/dev/null
				.  "$file"
				ifname="${name}_lan"
				net_params="$net_params $(_qemu_default_net_params "$ifname")"
				;;
		esac
	done

	# shellcheck disable=2086
	qemu-system-x86_64 \
		-enable-kvm \
		-M q35 \
		-m size=1024M \
		-smp cpus=1,cores=1,threads=1 \
		-drive format=raw,file="$QEMU_IMAGE",id=d0,if=none,bus=0,unit=0 -device ide-hd,drive=d0,bus=ide.0 \
		$net_params \
		-nographic
}

_images_list() {
	echo "Images: "

	selected_name=$(basename "$(readlink "$IMG_DIR/otb.img")")

	for file in "$IMG_DIR"/*.img; do
		[ -f "$file" ] || break
		name=$(basename "$file")
		sign=" *"
		[ "$name" == "otb.img" ] && continue
		[ "$name" == "$selected_name" ] && sign="->"
		echo "$sign $name"
	done
}

_images_download() {
	shift
	case "$1" in
		http*img.gz)
			filename="latest.img"
			url=$1
			;;
		develop|stable|unstable|testing)
			filename="latest-$1.img"
			url="http://downloads.overthebox.net/$1/targets/x86/64/latest.img.gz"
			;;
		*)
			_log_error "Invalid input $1"
			;;
	esac

	mkdir -p "$IMG_DIR" || true

	_log_info "Downloading $url"
	curl -Ss "$url" | gunzip -c > "$IMG_DIR/$filename"
	_log_info "File $filename created"
}

_images_delete() {
	shift
	file="$IMG_DIR/$1"
	[ -f "$file" ] || _log_error "Invalid image: $1"
	rm "$file"
}

_images_use() {
	shift
	file="$IMG_DIR/$1"
	[ -f "$file" ] || _log_error "Invalid image: $1"
	[ -f "$QEMU_IMAGE" ] && rm "$QEMU_IMAGE"
	ln -s "$file" "$QEMU_IMAGE"
	_log_info "Using $file as the default qemu image"
}

_client_start() {
	shift
	client_name="$1"
	[ "$client_name" ] || _log_error "Missing client name"

	_log_info "Creating client namespace"
	ip netns add "$client_name"

	_log_info "Creating client interfaces"
	pseudo_random_name=$(date +%N)
	ip link add "$client_name" type veth peer name "$pseudo_random_name"
	ip link set "$client_name" up
	ip link set "$pseudo_random_name" netns "$client_name"
	ip link set "$client_name" master "$BRIDGE_NAME" up
	ip -n "$client_name" link set "$pseudo_random_name" name wan

	_log_info "Getting a DHCP lease"
	ip netns exec "$client_name" dhclient -4 -v -cf /dev/null wan

	_log_info "Starting a shell"
	_namespace_enter "$client_name"

	_log_info "Removing client"
	ip link del "$client_name"
	ip netns del "$client_name"
}

####################################################################
#
# TODO: refactoring
#
####################################################################

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
