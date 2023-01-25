#!/bin/bash

RED='\033[0;31m'
ORANGE='\033[0;33m'
NC='\033[0m'

function isRoot() {
	if [ "${EUID}" -ne 0 ]; then
		echo "You need to run this script as root"
		exit 1
	fi
}

function checkVirt() {
	if [ "$(systemd-detect-virt)" == "openvz" ]; then
		echo "OpenVZ is not supported"
		exit 1
	fi

	if [ "$(systemd-detect-virt)" == "lxc" ]; then
		echo "LXC is not supported."
		exit 1
	fi
}

function checkOS() {
	# Check OS version
	if [[ -e /etc/debian_version ]]; then
		source /etc/os-release
		OS="${ID}" # debian or ubuntu
		if [[ ${ID} == "debian" || ${ID} == "raspbian" ]]; then
			if [[ ${VERSION_ID} -ne 10 ]] && [[ ${VERSION_ID} -ne 11 ]]; then
				echo "Your version of Debian (${VERSION_ID}) is not supported. Please use Debian 10 Buster or Debian 11 Bullseye"
				exit 1
			fi
		elif [[ ${ID} == "ubuntu" ]]; then
			if [[ ${VERSION_ID%.*} -lt 16 ]]; then
				echo "Your version of Ubuntu (${VERSION_ID}) is too low."
				exit 1
			fi
		fi
	else
		echo "Unsupported Os"
		exit 1
	fi
}

function initialCheck() {
	isRoot
	checkVirt
	checkOS
}

function installQuestions() {
	echo "Welcome to the WireGuard installer!"
	echo ""
	echo "I need to ask you a few questions before starting the setup."
	echo "You can leave the default options and just press enter if you are ok with them."
	echo ""

	# Detect public IPv4 or IPv6 address and pre-fill for the user
	SERVER_PUB_IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
	if [[ -z ${SERVER_PUB_IP} ]]; then
		# Detect public IPv6 address
		SERVER_PUB_IP=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)
	fi
	read -rp "IPv4 or IPv6 public address: " -e -i "${SERVER_PUB_IP}" SERVER_PUB_IP

	# Add dedicated IPv4 Address
	read -rp "IPv4 dedicated address (leave empty to skip): " -e -i "${DEDICATED_PUB_IP}" DEDICATED_PUB_IP
	
	# Detect public interface and pre-fill for the user
	SERVER_NIC="$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)"
	until [[ ${SERVER_PUB_NIC} =~ ^[a-zA-Z0-9_]+$ ]]; do
		read -rp "Public interface: " -e -i "${SERVER_NIC}" SERVER_PUB_NIC
	done

	until [[ ${SERVER_WG_NIC} =~ ^[a-zA-Z0-9_]+$ && ${#SERVER_WG_NIC} -lt 16 ]]; do
		read -rp "WireGuard interface name: " -e -i wg0 SERVER_WG_NIC
	done

	until [[ ${SERVER_WG_IPV4} =~ ^([0-9]{1,3}\.){3} ]]; do
		read -rp "Server's WireGuard IPv4: " -e -i 10.0.0.1 SERVER_WG_IPV4
	done

	until [[ ${SERVER_WG_IPV6} =~ ^([a-f0-9]{1,4}:){3,4}: ]]; do
		read -rp "Server's WireGuard IPv6: " -e -i fd42:42:42::1 SERVER_WG_IPV6
	done
	

	# Generate random number within private ports range
	RANDOM_PORT=$(shuf -i65523-65535 -n1)
	until [[ ${SERVER_PORT} =~ ^[0-9]+$ && "${SERVER_PORT}" -ge 1 && "${SERVER_PORT}" -le 65535 && ${SERVER_PORT} -ne 65522 ]]; do
		read -rp "Server's WireGuard port [1-65535]: " -e -i "${RANDOM_PORT}" SERVER_PORT
	done

	# cloudflare and google dns by default
	until [[ ${CLIENT_DNS_1} =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
		read -rp "First DNS resolver to use for the clients: " -e -i 1.1.1.1 CLIENT_DNS_1
	done
	until [[ ${CLIENT_DNS_2} =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
		read -rp "Second DNS resolver to use for the clients (optional): " -e -i 8.8.8.8 CLIENT_DNS_2
		if [[ ${CLIENT_DNS_2} == "" ]]; then
			CLIENT_DNS_2="${CLIENT_DNS_1}"
		fi
	done

	echo ""
	echo "Okay, that was all I needed. We are ready to setup your WireGuard server now."
	echo "You will be able to generate a client at the end of the installation."
	read -n1 -r -p "Press any key to continue..."
}

function installWireGuard() {
	# Run setup questions first
	installQuestions

	# Install WireGuard tools and module
	if [[ ${OS} == 'ubuntu' ]]; then
		apt-get update
		apt-get install -y wireguard iptables resolvconf qrencode
	elif [[ ${OS} == 'debian' ]]; then
		if [[ ${VERSION_ID} -eq 10 ]]; then
			if ! grep -rqs "^deb .* buster-backports" /etc/apt/; then
				echo "deb http://deb.debian.org/debian buster-backports main" >/etc/apt/sources.list.d/backports.list
			fi
			apt-get update
			apt-get install -y -t buster-backports wireguard
		elif [[ ${VERSION_ID} -eq 11 ]]; then
			apt-get update
			apt-get install -y wireguard
		fi
		apt-get install -y iptables resolvconf qrencode
	fi

	# Make sure the directory exists (this does not seem the be the case on fedora)
	mkdir /etc/wireguard >/dev/null 2>&1

	chmod 600 -R /etc/wireguard/

	# Server keygen
	SERVER_PRIV_KEY=$(wg genkey)
	SERVER_PUB_KEY=$(echo "${SERVER_PRIV_KEY}" | wg pubkey)
	# Client keygen
	CLIENT_PRIV_KEY=$(wg genkey)
	CLIENT_PUB_KEY=$(echo "${CLIENT_PRIV_KEY}" | wg pubkey)
	CLIENT_PRE_SHARED_KEY=$(wg genpsk)

	# Peer param auto generation
	ENDPOINT="${SERVER_PUB_IP}:${SERVER_PORT}"

	CLIENT_NAME="local"
	BASE_IP=$(echo "$SERVER_WG_IPV4" | awk -F '.' '{ print $1"."$2"."$3 }')
	CLIENT_WG_IPV4="${BASE_IP}.2"
	BASE_IP=$(echo "$SERVER_WG_IPV6" | awk -F '::' '{ print $1 }')
	CLIENT_WG_IPV6="${BASE_IP}::2"
	HOME_DIR="/root"

	# Save WireGuard settings
	echo "SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=${SERVER_WG_NIC}
SERVER_WG_IPV4=${SERVER_WG_IPV4}
SERVER_WG_IPV6=${SERVER_WG_IPV6}
SERVER_PORT=${SERVER_PORT}
SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
SERVER_PUB_KEY=${SERVER_PUB_KEY}
CLIENT_DNS_1=${CLIENT_DNS_1}
CLIENT_DNS_2=${CLIENT_DNS_2}
DEDICATED_PUB_IP=${DEDICATED_PUB_IP}" > "/etc/wireguard/params"

if [[ $DEDICATED_PUB_IP  =~ (([01]{,1}[0-9]{1,2}|2[0-4][0-9]|25[0-5])\.([01]{,1}[0-9]{1,2}|2[0-4][0-9]|25[0-5])\.([01]{,1}[0-9]{1,2}|2[0-4][0-9]|25[0-5])\.([01]{,1}[0-9]{1,2}|2[0-4][0-9]|25[0-5]))$ ]]; then 

	# Add server interface
	echo "[Interface]
Address = ${SERVER_WG_IPV4}/24,${SERVER_WG_IPV6}/64
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}
PostUp = /etc/wireguard/add-proxy.sh
PostDown = /etc/wireguard/del-proxy.sh

[Peer]
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
AllowedIPs = ${DEDICATED_PUB_IP}/32,${CLIENT_WG_IPV4}/32,${CLIENT_WG_IPV6}/128" > "/etc/wireguard/${SERVER_WG_NIC}.conf"

# add-proxy.sh and del-proxy.sh
	echo "#!/bin/bash

ip neigh add proxy ${DEDICATED_PUB_IP} dev ${SERVER_PUB_NIC}" > "/etc/wireguard/add-proxy.sh"

echo "#!/bin/bash

ip neigh del proxy ${DEDICATED_PUB_IP}" > "/etc/wireguard/del-proxy.sh"

	# Add exec permission
	chmod u+x /etc/wireguard/add-proxy.sh
	chmod u+x /etc/wireguard/del-proxy.sh

else

	# Add server interface
	echo "[Interface]
Address = ${SERVER_WG_IPV4}/24,${SERVER_WG_IPV6}/64
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}
PostUp = /etc/wireguard/add-fullcone-nat.sh
PostDown = /etc/wireguard/rm-fullcone-nat.sh

[Peer]
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
AllowedIPs = ${CLIENT_WG_IPV4}/32,${CLIENT_WG_IPV6}/128" > "/etc/wireguard/${SERVER_WG_NIC}.conf"

# add-fullcone-nat.sh and rm-fullcone-nat.sh
	echo "#!/bin/bash

iptables -A FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
iptables -A FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE

echo "#!/bin/bash

iptables -D FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT
iptables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT
iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE

	# Add exec permission
	chmod u+x /etc/wireguard/add-fullcone-nat.sh
	chmod u+x /etc/wireguard/rm-fullcone-nat.sh

fi

	# Create client file and add the server as a peer
	echo "[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_WG_IPV4}/32,${CLIENT_WG_IPV6}/128
DNS = ${CLIENT_DNS_1},${CLIENT_DNS_2}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
Endpoint = ${ENDPOINT}
AllowedIPs = 0.0.0.0/0,::/0" > "${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"

	# Enable routing on the server
	echo "net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1" >/etc/sysctl.d/wg.conf

	sysctl --system

	systemctl start "wg-quick@${SERVER_WG_NIC}"
	systemctl enable "wg-quick@${SERVER_WG_NIC}"

	# Check if WireGuard is running
	systemctl is-active --quiet "wg-quick@${SERVER_WG_NIC}"
	WG_RUNNING=$?

	# WireGuard might not work if we updated the kernel. Tell the user to reboot
	if [[ ${WG_RUNNING} -ne 0 ]]; then
		echo -e "\n${RED}WARNING: WireGuard does not seem to be running might need a reboot.${NC}"
	else
		echo -e "\nHere is your client config file as a QR Code:"
		qrencode -t ansiutf8 -l L <"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"
		echo "It is also available in ${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"
	fi
}


function uninstallWg() {
	echo ""
	read -rp "Do you really want to remove WireGuard? [y/n]: " -e -i n REMOVE
	if [[ $REMOVE == 'y' ]]; then

		systemctl stop "wg-quick@${SERVER_WG_NIC}"
		systemctl disable "wg-quick@${SERVER_WG_NIC}"

		apt-get autoremove --purge -y wireguard qrencode

		rm -rf /etc/wireguard
		rm -f /etc/sysctl.d/wg.conf

		# Reload sysctl
		sysctl --system

		# Check if WireGuard is running
		systemctl is-active --quiet "wg-quick@${SERVER_WG_NIC}"
		WG_RUNNING=$?

		if [[ ${WG_RUNNING} -eq 0 ]]; then
			echo "WireGuard failed to uninstall properly."
			exit 1
		else
			echo "WireGuard uninstalled successfully."
			exit 0
		fi
	else
		echo ""
		echo "Removal aborted!"
	fi
}

function manageMenu() {
	echo "Welcome to WireGuard-install!"
	echo ""
	echo "It looks like WireGuard is already installed."
	echo ""
	echo "What do you want to do?"
	echo "   1) Stop WireGuard"
	echo "   2) Restart WireGuard"
	echo "   3) Uninstall WireGuard"
	echo "   4) Exit"
	until [[ ${MENU_OPTION} =~ ^[1-4]$ ]]; do
		read -rp "Select an option [1-4]: " MENU_OPTION
	done
	case "${MENU_OPTION}" in
	1)
		systemctl stop "wg-quick@${SERVER_WG_NIC}"
		;;
	2)
		systemctl restart "wg-quick@${SERVER_WG_NIC}"
		;;
	3)
		uninstallWg
		;;
	4)
		exit 0
		;;
	esac
}

# Check for root, virt, OS...
initialCheck

# Check if WireGuard is already installed and load params
if [[ -e /etc/wireguard/params ]]; then
	source /etc/wireguard/params
	manageMenu
else
	installWireGuard
fi
