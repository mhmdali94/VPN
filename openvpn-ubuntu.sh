#!/bin/bash
# OpenVPN installer for Debian, Ubuntu and CentOS
# Wrote by "Road Warrior", Repo by "Kashif H Khan".
# Updated automation by Mohammed Ali (PrismaTechwork.com)
# https://github.com/mhmdali94

# This script will work on Debian, Ubuntu, CentOS and probably other distros
# of the same families, although no support is offered for them. It isn't
# bulletproof but it will probably work if you simply want to setup a VPN on
# your Debian/Ubuntu/CentOS box. It has been designed to be as unobtrusive and
# universal as possible.

# ─────────────────────────────────────────────
#  Color & Style Helpers
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

ok()   { echo -e "  ${GREEN}✔${NC}  $*"; }
err()  { echo -e "  ${RED}✖${NC}  $*"; }
info() { echo -e "  ${CYAN}ℹ${NC}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }

step() {
	echo ""
	echo -e "${BOLD}${BLUE}┌─────────────────────────────────────────────┐${NC}"
	echo -e "${BOLD}${BLUE}│  ${CYAN}Step $1/${TOTAL_STEPS}${BLUE} · ${NC}${BOLD}$2${BLUE}$(printf '%*s' $((42 - ${#2} - ${#1} - ${#TOTAL_STEPS} - 7)) '')│${NC}"
	echo -e "${BOLD}${BLUE}└─────────────────────────────────────────────┘${NC}"
}

banner() {
	echo -e "${CYAN}"
	echo '  ██████╗ ██████╗ ███████╗███╗   ██╗██╗   ██╗██████╗ ███╗   ██╗'
	echo ' ██╔═══██╗██╔══██╗██╔════╝████╗  ██║██║   ██║██╔══██╗████╗  ██║'
	echo ' ██║   ██║██████╔╝█████╗  ██╔██╗ ██║██║   ██║██████╔╝██╔██╗ ██║'
	echo ' ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║'
	echo ' ╚██████╔╝██║     ███████╗██║ ╚████║ ╚████╔╝ ██║     ██║ ╚████║'
	echo '  ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝  ╚═══╝  ╚═╝     ╚═╝  ╚═══╝'
	echo -e "${NC}"
	echo -e "  ${DIM}Auto Installer · by Mohammed Ali · github.com/mhmdali94${NC}"
	echo ""
}

divider() {
	echo -e "${DIM}  ─────────────────────────────────────────────────────────${NC}"
}

# ─────────────────────────────────────────────
#  Spinner
# ─────────────────────────────────────────────
spinner() {
	local pid=$1
	local msg="${2:-Working...}"
	local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
	local i=0
	while kill -0 "$pid" 2>/dev/null; do
		i=$(( (i+1) % 10 ))
		printf "\r  ${CYAN}${spin:$i:1}${NC}  ${DIM}${msg}${NC}   "
		sleep 0.1
	done
	printf "\r  ${GREEN}✔${NC}  ${msg}   \n"
}

run_with_spinner() {
	local msg="$1"
	shift
	"$@" &>/dev/null &
	spinner $! "$msg"
	wait $!
	return $?
}

# ─────────────────────────────────────────────
#  Preflight Checks
# ─────────────────────────────────────────────

# Detect Debian users running the script with "sh" instead of bash
if readlink /proc/$$/exe | grep -qs "dash"; then
	err "This script needs to be run with bash, not sh"
	exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
	banner
	err "Please run this script as ${BOLD}root${NC}"
	info "Try: ${CYAN}sudo bash $0${NC}"
	exit 2
fi

if [[ ! -e /dev/net/tun ]]; then
	banner
	err "The TUN device is not available"
	info "You need to enable TUN before running this script"
	exit 3
fi

if grep -qs "CentOS release 5" "/etc/redhat-release"; then
	banner
	err "CentOS 5 is too old and not supported"
	exit 4
fi

if [[ -e /etc/debian_version ]]; then
	OS=debian
	GROUPNAME=nogroup
	RCLOCAL='/etc/rc.local'
elif [[ -e /etc/centos-release || -e /etc/redhat-release ]]; then
	OS=centos
	GROUPNAME=nobody
	RCLOCAL='/etc/rc.d/rc.local'
else
	banner
	err "Unsupported OS — only Debian, Ubuntu and CentOS are supported"
	exit 5
fi

newclient () {
	# Generates the custom client.ovpn
	cp /etc/openvpn/client-common.txt ~/$1.ovpn
	echo "<ca>" >> ~/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/ca.crt >> ~/$1.ovpn
	echo "</ca>" >> ~/$1.ovpn
	echo "<cert>" >> ~/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/issued/$1.crt >> ~/$1.ovpn
	echo "</cert>" >> ~/$1.ovpn
	echo "<key>" >> ~/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/private/$1.key >> ~/$1.ovpn
	echo "</key>" >> ~/$1.ovpn
	echo "<tls-auth>" >> ~/$1.ovpn
	cat /etc/openvpn/ta.key >> ~/$1.ovpn
	echo "</tls-auth>" >> ~/$1.ovpn
}

# Try to get our IP from the system and fallback to the Internet.
# I do this to make the script compatible with NATed servers (lowendspirit.com)
# and to avoid getting an IPv6.
IP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -o -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
if [[ "$IP" = "" ]]; then
	IP=$(wget -4qO- "http://whatismyip.akamai.com/")
fi

# ─────────────────────────────────────────────
#  Management Menu (already installed)
# ─────────────────────────────────────────────
if [[ -e /etc/openvpn/server.conf ]]; then
	while :
	do
	clear
	banner
	echo -e "  ${BOLD}${GREEN}OpenVPN is already installed and running.${NC}"
	divider
	echo ""
	echo -e "  ${BOLD}What would you like to do?${NC}"
	echo ""
	echo -e "  ${CYAN}[1]${NC}  👤  Add a new VPN user"
	echo -e "  ${CYAN}[2]${NC}  🚫  Revoke an existing user"
	echo -e "  ${CYAN}[3]${NC}  🗑️   Remove OpenVPN completely"
	echo -e "  ${CYAN}[4]${NC}  🚪  Exit"
	echo ""
	divider
	echo ""

	while true; do
		read -p "$(echo -e "  ${BOLD}Select an option [1-4]:${NC} ")" option
		case $option in
			1|2|3|4) break ;;
			*) warn "Invalid choice. Please enter 1, 2, 3, or 4." ;;
		esac
	done

	case $option in
		1)
		echo ""
		echo -e "  ${BOLD}${CYAN}Add a New VPN User${NC}"
		divider
		echo ""
		info "Client name must be a single word with no special characters."
		echo ""
		while true; do
			read -p "$(echo -e "  ${BOLD}Client name:${NC} ")" -e -i client CLIENT
			if [[ -z "$CLIENT" ]]; then
				warn "Client name cannot be empty."
			elif [[ "$CLIENT" =~ [^a-zA-Z0-9_-] ]]; then
				warn "Use only letters, numbers, hyphens, or underscores."
			else
				break
			fi
		done
		echo ""
		info "Generating certificate for ${BOLD}$CLIENT${NC}..."
		cd /etc/openvpn/easy-rsa/
		./easyrsa build-client-full "$CLIENT" nopass &>/dev/null
		newclient "$CLIENT"
		echo ""
		ok "Client ${BOLD}$CLIENT${NC} added!"
		ok "Config file: ${CYAN}~/$CLIENT.ovpn${NC}"
		info "Copy this file to your device and import it into your OpenVPN client."
		echo ""
		exit
		;;

		2)
		NUMBEROFCLIENTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c "^V")
		if [[ "$NUMBEROFCLIENTS" = '0' ]]; then
			echo ""
			warn "There are no active clients to revoke."
			exit 6
		fi
		echo ""
		echo -e "  ${BOLD}${CYAN}Revoke a VPN User${NC}"
		divider
		echo ""
		echo -e "  ${BOLD}Active clients:${NC}"
		echo ""
		tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') ' | sed 's/^/    /'
		echo ""
		while true; do
			if [[ "$NUMBEROFCLIENTS" = '1' ]]; then
				read -p "$(echo -e "  ${BOLD}Select client [1]:${NC} ")" CLIENTNUMBER
				[[ "$CLIENTNUMBER" = "1" ]] && break
				warn "Enter 1 to select the only client."
			else
				read -p "$(echo -e "  ${BOLD}Select client [1-$NUMBEROFCLIENTS]:${NC} ")" CLIENTNUMBER
				if [[ "$CLIENTNUMBER" =~ ^[0-9]+$ ]] && (( CLIENTNUMBER >= 1 && CLIENTNUMBER <= NUMBEROFCLIENTS )); then
					break
				fi
				warn "Please enter a number between 1 and $NUMBEROFCLIENTS."
			fi
		done
		CLIENT=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "${CLIENTNUMBER}p")
		echo ""
		echo -e "  ${YELLOW}${BOLD}⚠  You are about to revoke access for: ${RED}$CLIENT${NC}"
		echo ""
		while true; do
			read -p "$(echo -e "  ${BOLD}Are you sure? [y/N]:${NC} ")" -e CONFIRM
			case "${CONFIRM,,}" in
				y|yes) break ;;
				n|no|"") echo ""; warn "Revocation cancelled."; exit ;;
				*) warn "Please enter y or n." ;;
			esac
		done
		echo ""
		info "Revoking certificate for ${BOLD}$CLIENT${NC}..."
		cd /etc/openvpn/easy-rsa/
		./easyrsa --batch revoke "$CLIENT" &>/dev/null
		EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl &>/dev/null
		rm -rf pki/reqs/$CLIENT.req
		rm -rf pki/private/$CLIENT.key
		rm -rf pki/issued/$CLIENT.crt
		rm -rf /etc/openvpn/crl.pem
		cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/crl.pem
		chown nobody:$GROUPNAME /etc/openvpn/crl.pem
		echo ""
		ok "Certificate for ${BOLD}$CLIENT${NC} has been revoked."
		info "They will no longer be able to connect to the VPN."
		echo ""
		exit
		;;

		3)
		echo ""
		echo -e "  ${BOLD}${RED}Remove OpenVPN${NC}"
		divider
		echo ""
		warn "This will ${BOLD}permanently${NC} remove OpenVPN and all its configuration."
		echo ""
		while true; do
			read -p "$(echo -e "  ${BOLD}Type '${RED}yes${NC}${BOLD}' to confirm removal:${NC} ")" -e REMOVE
			case "${REMOVE,,}" in
				yes) break ;;
				no|"") echo ""; info "Removal cancelled. Nothing was changed."; exit ;;
				*) warn "Type 'yes' to confirm or press Enter to cancel." ;;
			esac
		done
		echo ""
		info "Removing OpenVPN..."
		PORT=$(grep '^port ' /etc/openvpn/server.conf | cut -d " " -f 2)
		PROTOCOL=$(grep '^proto ' /etc/openvpn/server.conf | cut -d " " -f 2)
		if pgrep firewalld; then
			IP=$(firewall-cmd --direct --get-rules ipv4 nat POSTROUTING | grep '\-s 10.8.0.0/24 ''!'' -d 10.8.0.0/24 -j SNAT --to ' | cut -d " " -f 10)
			firewall-cmd --zone=public --remove-port=$PORT/$PROTOCOL
			firewall-cmd --zone=trusted --remove-source=10.8.0.0/24
			firewall-cmd --permanent --zone=public --remove-port=$PORT/$PROTOCOL
			firewall-cmd --permanent --zone=trusted --remove-source=10.8.0.0/24
			firewall-cmd --direct --remove-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP
			firewall-cmd --permanent --direct --remove-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP
		else
			IP=$(grep 'iptables -t nat -A POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to ' $RCLOCAL | cut -d " " -f 14)
			iptables -t nat -D POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP
			sed -i '/iptables -t nat -A POSTROUTING -s 10.8.0.0\/24 ! -d 10.8.0.0\/24 -j SNAT --to /d' $RCLOCAL
			if iptables -L -n | grep -qE '^ACCEPT'; then
				iptables -D INPUT -p $PROTOCOL --dport $PORT -j ACCEPT
				iptables -D FORWARD -s 10.8.0.0/24 -j ACCEPT
				iptables -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
				sed -i "/iptables -I INPUT -p $PROTOCOL --dport $PORT -j ACCEPT/d" $RCLOCAL
				sed -i "/iptables -I FORWARD -s 10.8.0.0\/24 -j ACCEPT/d" $RCLOCAL
				sed -i "/iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT/d" $RCLOCAL
			fi
		fi
		if hash sestatus 2>/dev/null; then
			if sestatus | grep "Current mode" | grep -qs "enforcing"; then
				if [[ "$PORT" != '1194' || "$PROTOCOL" = 'tcp' ]]; then
					semanage port -d -t openvpn_port_t -p $PROTOCOL $PORT
				fi
			fi
		fi
		if [[ "$OS" = 'debian' ]]; then
			run_with_spinner "Uninstalling OpenVPN packages..." apt-get remove --purge -y openvpn
		else
			run_with_spinner "Uninstalling OpenVPN packages..." yum remove openvpn -y
		fi
		rm -rf /etc/openvpn
		echo ""
		ok "OpenVPN has been completely removed."
		echo ""
		exit
		;;

		4)
		echo ""
		info "Bye! 👋"
		echo ""
		exit
		;;
	esac
	done

else

# ─────────────────────────────────────────────
#  Fresh Installation
# ─────────────────────────────────────────────
TOTAL_STEPS=6

clear
banner
echo -e "  ${BOLD}Welcome to the OpenVPN Quick Setup Wizard${NC}"
echo -e "  ${DIM}Answer a few questions and your VPN server will be ready in minutes.${NC}"
divider
echo ""

# ── Step 1: IP Address ──────────────────────
step 1 "Server IP Address"
echo ""
info "Detected local IP: ${BOLD}${IP}${NC}"
info "For NATed servers, enter your internal IP — you'll set the external one later."
echo ""
while true; do
	read -p "$(echo -e "  ${BOLD}IP address [${IP}]:${NC} ")" -e -i "$IP" INPUT_IP
	if [[ "$INPUT_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
		IP="$INPUT_IP"
		break
	fi
	warn "Please enter a valid IPv4 address."
done
echo ""

# ── Step 2: Protocol ────────────────────────
step 2 "VPN Protocol"
echo ""
echo -e "  ${CYAN}[1]${NC}  UDP  ${DIM}(recommended — faster, lower overhead)${NC}"
echo -e "  ${CYAN}[2]${NC}  TCP  ${DIM}(more reliable through restrictive firewalls)${NC}"
echo ""
while true; do
	read -p "$(echo -e "  ${BOLD}Protocol [1-2, default: 1]:${NC} ")" -e -i 1 PROTOCOL
	case $PROTOCOL in
		1) PROTOCOL=udp; break ;;
		2) PROTOCOL=tcp; break ;;
		*) warn "Please enter 1 or 2." ;;
	esac
done
echo ""

# ── Step 3: Port ────────────────────────────
step 3 "Listening Port"
echo ""
info "Default OpenVPN port is ${BOLD}1194${NC}. You can use any port from 1 to 65535."
echo ""
while true; do
	read -p "$(echo -e "  ${BOLD}Port [1194]:${NC} ")" -e -i 1194 PORT
	if [[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )); then
		break
	fi
	warn "Port must be a number between 1 and 65535."
done
echo ""

# ── Step 4: DNS ─────────────────────────────
step 4 "DNS Server"
echo ""
echo -e "  ${CYAN}[1]${NC}  System resolvers    ${DIM}(/etc/resolv.conf)${NC}"
echo -e "  ${CYAN}[2]${NC}  Google              ${DIM}(8.8.8.8 / 8.8.4.4)${NC}"
echo -e "  ${CYAN}[3]${NC}  OpenDNS             ${DIM}(208.67.222.222 / 208.67.220.220)${NC}"
echo -e "  ${CYAN}[4]${NC}  NTT                 ${DIM}(129.250.35.250 / 129.250.35.251)${NC}"
echo -e "  ${CYAN}[5]${NC}  Hurricane Electric  ${DIM}(74.82.42.42)${NC}"
echo -e "  ${CYAN}[6]${NC}  Verisign            ${DIM}(64.6.64.6 / 64.6.65.6)${NC}"
echo ""
while true; do
	read -p "$(echo -e "  ${BOLD}DNS choice [1-6, default: 1]:${NC} ")" -e -i 1 DNS
	if [[ "$DNS" =~ ^[1-6]$ ]]; then
		break
	fi
	warn "Please enter a number from 1 to 6."
done
echo ""

# ── Step 5: Client Name ─────────────────────
step 5 "Client Certificate Name"
echo ""
info "One word only — letters, numbers, hyphens, and underscores allowed."
echo ""
while true; do
	read -p "$(echo -e "  ${BOLD}Client name [client]:${NC} ")" -e -i client CLIENT
	if [[ -z "$CLIENT" ]]; then
		warn "Client name cannot be empty."
	elif [[ "$CLIENT" =~ [^a-zA-Z0-9_-] ]]; then
		warn "Invalid characters. Use only letters, numbers, hyphens, or underscores."
	else
		break
	fi
done
echo ""

# ── Pre-Install Summary ─────────────────────
clear
banner

echo -e "  ${BOLD}${GREEN}✔  All set! Here's your configuration summary:${NC}"
echo ""
echo -e "  ${BOLD}${BLUE}╔═══════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}${BLUE}║${NC}  ${BOLD}Server IP   ${NC}  ${CYAN}$IP${NC}$(printf '%*s' $((26 - ${#IP})) '')${BOLD}${BLUE}║${NC}"
echo -e "  ${BOLD}${BLUE}║${NC}  ${BOLD}Protocol    ${NC}  ${CYAN}${PROTOCOL^^}${NC}$(printf '%*s' $((26 - ${#PROTOCOL})) '')${BOLD}${BLUE}║${NC}"
echo -e "  ${BOLD}${BLUE}║${NC}  ${BOLD}Port        ${NC}  ${CYAN}$PORT${NC}$(printf '%*s' $((26 - ${#PORT})) '')${BOLD}${BLUE}║${NC}"
echo -e "  ${BOLD}${BLUE}║${NC}  ${BOLD}DNS         ${NC}  ${CYAN}Option $DNS${NC}$(printf '%*s' $((18)) '')${BOLD}${BLUE}║${NC}"
echo -e "  ${BOLD}${BLUE}║${NC}  ${BOLD}Client name ${NC}  ${CYAN}$CLIENT${NC}$(printf '%*s' $((26 - ${#CLIENT})) '')${BOLD}${BLUE}║${NC}"
echo -e "  ${BOLD}${BLUE}╚═══════════════════════════════════════════╝${NC}"
echo ""

while true; do
	read -p "$(echo -e "  ${BOLD}Proceed with installation? [Y/n]:${NC} ")" -e CONFIRM
	case "${CONFIRM,,}" in
		y|yes|"") break ;;
		n|no) echo ""; warn "Installation cancelled. Nothing was changed."; exit ;;
		*) warn "Please enter y or n." ;;
	esac
done
echo ""

# ── Step 6: Install ─────────────────────────
step 6 "Installing OpenVPN"
echo ""

if [[ "$OS" = 'debian' ]]; then
	run_with_spinner "Updating package lists..." apt-get update
	run_with_spinner "Installing OpenVPN & dependencies..." apt-get install openvpn iptables openssl ca-certificates -y
else
	run_with_spinner "Installing EPEL release..." yum install epel-release -y
	run_with_spinner "Installing OpenVPN & dependencies..." yum install openvpn iptables openssl wget ca-certificates -y
fi

# Remove old easy-rsa if present
if [[ -d /etc/openvpn/easy-rsa/ ]]; then
	rm -rf /etc/openvpn/easy-rsa/
fi

# Download EasyRSA v3.2.1
EASYRSA_VERSION="3.2.1"
run_with_spinner "Downloading EasyRSA ${EASYRSA_VERSION}..." \
	wget -O ~/EasyRSA-${EASYRSA_VERSION}.tgz "https://github.com/OpenVPN/easy-rsa/releases/download/v${EASYRSA_VERSION}/EasyRSA-${EASYRSA_VERSION}.tgz"

tar xzf ~/EasyRSA-${EASYRSA_VERSION}.tgz -C ~/
mv ~/EasyRSA-${EASYRSA_VERSION}/ /etc/openvpn/easy-rsa/
chown -R root:root /etc/openvpn/easy-rsa/
rm -f ~/EasyRSA-${EASYRSA_VERSION}.tgz

cd /etc/openvpn/easy-rsa/

# Build PKI, CA, DH, server and client certs
run_with_spinner "Initializing PKI..." ./easyrsa init-pki
run_with_spinner "Building Certificate Authority..." ./easyrsa --batch build-ca nopass
run_with_spinner "Generating Diffie-Hellman parameters (this may take a minute)..." ./easyrsa gen-dh
run_with_spinner "Building server certificate..." ./easyrsa build-server-full server nopass
run_with_spinner "Building client certificate for '${CLIENT}'..." ./easyrsa build-client-full "$CLIENT" nopass
run_with_spinner "Generating Certificate Revocation List..." env EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl

# Copy required files to /etc/openvpn
cp pki/ca.crt pki/private/ca.key pki/dh.pem pki/issued/server.crt pki/private/server.key pki/crl.pem /etc/openvpn
chown nobody:$GROUPNAME /etc/openvpn/crl.pem

# Generate TLS auth key
openvpn --genkey secret /etc/openvpn/ta.key

# Generate server.conf
cat > /etc/openvpn/server.conf <<EOF
port $PORT
proto $PROTOCOL
dev tun
sndbuf 0
rcvbuf 0
ca ca.crt
cert server.crt
key server.key
dh dh.pem
auth SHA512
tls-auth ta.key 0
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
EOF

# Append DNS settings
case $DNS in
	1)
	grep -v '#' /etc/resolv.conf | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read line; do
		echo "push \"dhcp-option DNS $line\"" >> /etc/openvpn/server.conf
	done
	;;
	2)
	echo 'push "dhcp-option DNS 8.8.8.8"' >> /etc/openvpn/server.conf
	echo 'push "dhcp-option DNS 8.8.4.4"' >> /etc/openvpn/server.conf
	;;
	3)
	echo 'push "dhcp-option DNS 208.67.222.222"' >> /etc/openvpn/server.conf
	echo 'push "dhcp-option DNS 208.67.220.220"' >> /etc/openvpn/server.conf
	;;
	4)
	echo 'push "dhcp-option DNS 129.250.35.250"' >> /etc/openvpn/server.conf
	echo 'push "dhcp-option DNS 129.250.35.251"' >> /etc/openvpn/server.conf
	;;
	5)
	echo 'push "dhcp-option DNS 74.82.42.42"' >> /etc/openvpn/server.conf
	;;
	6)
	echo 'push "dhcp-option DNS 64.6.64.6"' >> /etc/openvpn/server.conf
	echo 'push "dhcp-option DNS 64.6.65.6"' >> /etc/openvpn/server.conf
	;;
esac

# Append remaining server settings
cat >> /etc/openvpn/server.conf <<EOF
keepalive 10 120
cipher AES-256-CBC
compress lz4-v2
push "compress lz4-v2"
user nobody
group $GROUPNAME
persist-key
persist-tun
status openvpn-status.log
verb 3
crl-verify crl.pem
EOF

# Enable IP forwarding
run_with_spinner "Enabling IP forwarding..." bash -c "
sed -i '/\<net.ipv4.ip_forward\>/c\\net.ipv4.ip_forward=1' /etc/sysctl.conf
if ! grep -q '\<net.ipv4.ip_forward\>' /etc/sysctl.conf; then
	echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi
echo 1 > /proc/sys/net/ipv4/ip_forward
"

# Configure firewall
info "Configuring firewall rules..."
if pgrep firewalld; then
	firewall-cmd --zone=public --add-port=$PORT/$PROTOCOL
	firewall-cmd --zone=trusted --add-source=10.8.0.0/24
	firewall-cmd --permanent --zone=public --add-port=$PORT/$PROTOCOL
	firewall-cmd --permanent --zone=trusted --add-source=10.8.0.0/24
	firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP
	firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP
else
	if [[ "$OS" = 'debian' && ! -e $RCLOCAL ]]; then
		echo '#!/bin/sh -e
exit 0' > $RCLOCAL
	fi
	chmod +x $RCLOCAL
	iptables -t nat -A POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP
	sed -i "1 a\iptables -t nat -A POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP" $RCLOCAL
	if iptables -L -n | grep -qE '^(REJECT|DROP)'; then
		iptables -I INPUT -p $PROTOCOL --dport $PORT -j ACCEPT
		iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT
		iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
		sed -i "1 a\iptables -I INPUT -p $PROTOCOL --dport $PORT -j ACCEPT" $RCLOCAL
		sed -i "1 a\iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT" $RCLOCAL
		sed -i "1 a\iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" $RCLOCAL
	fi
fi
ok "Firewall configured"

# SELinux handling
if hash sestatus 2>/dev/null; then
	if sestatus | grep "Current mode" | grep -qs "enforcing"; then
		if [[ "$PORT" != '1194' || "$PROTOCOL" = 'tcp' ]]; then
			if ! hash semanage 2>/dev/null; then
				run_with_spinner "Installing SELinux policy tools..." yum install policycoreutils-python -y
			fi
			semanage port -a -t openvpn_port_t -p $PROTOCOL $PORT
			ok "SELinux port policy applied"
		fi
	fi
fi

# Start and enable OpenVPN
info "Starting OpenVPN service..."
if [[ "$OS" = 'debian' ]]; then
	if pgrep systemd-journal; then
		systemctl restart openvpn@server.service
	else
		/etc/init.d/openvpn restart
	fi
else
	if pgrep systemd-journal; then
		systemctl restart openvpn@server.service
		systemctl enable openvpn@server.service
	else
		service openvpn restart
		chkconfig openvpn on
	fi
fi
ok "OpenVPN service started"

# Detect NAT
EXTERNALIP=$(wget -4qO- "http://whatismyip.akamai.com/")
if [[ "$IP" != "$EXTERNALIP" ]]; then
	echo ""
	echo -e "  ${YELLOW}${BOLD}⚠  NAT Detected!${NC}"
	divider
	info "Your server appears to be behind a NAT (local: ${BOLD}$IP${NC}, external: ${BOLD}$EXTERNALIP${NC})"
	info "If clients need to connect using the external IP, enter it below."
	info "Otherwise, just press Enter to skip."
	echo ""
	read -p "$(echo -e "  ${BOLD}External IP (or Enter to skip):${NC} ")" -e USEREXTERNALIP
	if [[ "$USEREXTERNALIP" != "" ]]; then
		IP=$USEREXTERNALIP
	fi
fi

# Generate client-common.txt template
cat > /etc/openvpn/client-common.txt <<EOF
client
dev tun
proto $PROTOCOL
sndbuf 0
rcvbuf 0
remote $IP $PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA512
cipher AES-256-CBC
compress lz4-v2
setenv opt block-outside-dns
key-direction 1
verb 3
EOF

# Generate the client .ovpn file
newclient "$CLIENT"

# ── Completion Screen ────────────────────────
echo ""
clear
banner
echo -e "  ${BOLD}${GREEN}🎉  OpenVPN is installed and ready!${NC}"
divider
echo ""
echo -e "  ${BOLD}Your client config file is ready at:${NC}"
echo ""
echo -e "  ${CYAN}${BOLD}  ~/$CLIENT.ovpn${NC}"
echo ""
divider
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo ""
echo -e "  ${CYAN}1.${NC} Copy ${BOLD}~/$CLIENT.ovpn${NC} to your device"
echo -e "  ${CYAN}2.${NC} Import it into your OpenVPN client app"
echo -e "  ${CYAN}3.${NC} Connect and enjoy your VPN! 🚀"
echo ""
echo -e "  ${DIM}Run this script again on the same server to add/revoke users.${NC}"
divider
echo ""

fi
