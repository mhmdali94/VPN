#!/bin/bash
# WireGuard installer for Debian, Ubuntu and CentOS
# By Mohammed Ali (PrismaTechwork.com)
# https://github.com/mhmdali94

# ─────────────────────────────────────────────
#  Color & Style Helpers
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

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
	echo ' ██╗    ██╗██╗██████╗ ███████╗ ██████╗ ██╗   ██╗ █████╗ ██████╗ ██████╗ '
	echo ' ██║    ██║██║██╔══██╗██╔════╝██╔════╝ ██║   ██║██╔══██╗██╔══██╗██╔══██╗'
	echo ' ██║ █╗ ██║██║██████╔╝█████╗  ██║  ███╗██║   ██║███████║██████╔╝██║  ██║'
	echo ' ██║███╗██║██║██╔══██╗██╔══╝  ██║   ██║██║   ██║██╔══██║██╔══██╗██║  ██║'
	echo ' ╚███╔███╔╝██║██║  ██║███████╗╚██████╔╝╚██████╔╝██║  ██║██║  ██║██████╔╝'
	echo '  ╚══╝╚══╝ ╚═╝╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝'
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

if [[ -e /etc/debian_version ]]; then
	OS=debian
elif [[ -e /etc/centos-release || -e /etc/redhat-release ]]; then
	OS=centos
else
	banner
	err "Unsupported OS — only Debian, Ubuntu and CentOS are supported"
	exit 5
fi

# Detect local IP and primary NIC
IP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -o -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
if [[ -z "$IP" ]]; then
	IP=$(wget -4qO- "http://whatismyip.akamai.com/")
fi
NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)

# Load saved params if already installed
PARAMS_FILE="/etc/wireguard/params"
[[ -f "$PARAMS_FILE" ]] && source "$PARAMS_FILE"

# ─────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────
newclient() {
	local CLIENT="$1"
	local CLIENT_IP="$2"
	local DNS_IPS="$3"

	local CLIENT_PRIVATE_KEY CLIENT_PUBLIC_KEY CLIENT_PSK
	CLIENT_PRIVATE_KEY=$(wg genkey)
	CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)
	CLIENT_PSK=$(wg genpsk)

	cat >> /etc/wireguard/wg0.conf <<EOF

[Peer]
# $CLIENT
PublicKey = $CLIENT_PUBLIC_KEY
PresharedKey = $CLIENT_PSK
AllowedIPs = $CLIENT_IP/32
EOF

	# Hot-reload without dropping existing connections
	wg syncconf wg0 <(wg-quick strip /etc/wireguard/wg0.conf) 2>/dev/null || true

	cat > ~/"$CLIENT".conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/24
DNS = $DNS_IPS

[Peer]
PublicKey = $SERVER_PUB_KEY
PresharedKey = $CLIENT_PSK
Endpoint = $SERVER_PUB_IP:$SERVER_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
}

get_next_ip() {
	local last_octet
	last_octet=$(grep -oP 'AllowedIPs = 10\.8\.0\.\K\d+' /etc/wireguard/wg0.conf | sort -n | tail -1)
	if [[ -z "$last_octet" ]]; then
		echo "10.8.0.2"
	else
		echo "10.8.0.$((last_octet + 1))"
	fi
}

remove_peer_block() {
	local CLIENT="$1"
	python3 - "$CLIENT" /etc/wireguard/wg0.conf <<'PYEOF'
import re, sys

client = sys.argv[1]
path   = sys.argv[2]

with open(path, 'r') as f:
    conf = f.read()

pattern = r'\n\[Peer\]\n# ' + re.escape(client) + r'\n(?:.+\n)*'
conf = re.sub(pattern, '\n', conf)

with open(path, 'w') as f:
    f.write(conf)
PYEOF
}

# ─────────────────────────────────────────────
#  Management Menu (already installed)
# ─────────────────────────────────────────────
if [[ -f /etc/wireguard/wg0.conf ]]; then
	while :; do
		clear
		banner
		echo -e "  ${BOLD}${GREEN}WireGuard is already installed and running.${NC}"
		divider
		echo ""
		echo -e "  ${BOLD}What would you like to do?${NC}"
		echo ""
		echo -e "  ${CYAN}[1]${NC}  👤  Add a new VPN user"
		echo -e "  ${CYAN}[2]${NC}  🚫  Remove an existing user"
		echo -e "  ${CYAN}[3]${NC}  📱  Show QR code for a user"
		echo -e "  ${CYAN}[4]${NC}  🗑️   Remove WireGuard completely"
		echo -e "  ${CYAN}[5]${NC}  🚪  Exit"
		echo ""
		divider
		echo ""

		while true; do
			read -p "$(echo -e "  ${BOLD}Select an option [1-5]:${NC} ")" option
			case $option in
				1|2|3|4|5) break ;;
				*) warn "Invalid choice. Please enter 1, 2, 3, 4, or 5." ;;
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
				elif grep -q "^# ${CLIENT}$" /etc/wireguard/wg0.conf; then
					warn "A client named '${CLIENT}' already exists."
				else
					break
				fi
			done
			CLIENT_IP=$(get_next_ip)
			echo ""
			info "Generating config for ${BOLD}$CLIENT${NC} → ${CYAN}$CLIENT_IP${NC}..."
			newclient "$CLIENT" "$CLIENT_IP" "${SERVER_DNS:-8.8.8.8, 8.8.4.4}"
			echo ""
			ok "Client ${BOLD}$CLIENT${NC} added!"
			ok "Config file: ${CYAN}~/$CLIENT.conf${NC}"
			echo ""
			if hash qrencode 2>/dev/null; then
				info "QR Code (scan with WireGuard mobile app):"
				echo ""
				qrencode -t ansiutf8 < ~/"$CLIENT".conf
				echo ""
			fi
			info "Copy ${CYAN}~/$CLIENT.conf${NC} to your device or import into the WireGuard client."
			echo ""
			exit
			;;

			2)
			CLIENTS=$(grep -oP '^# \K.+' /etc/wireguard/wg0.conf)
			if [[ -z "$CLIENTS" ]]; then
				echo ""
				warn "There are no active clients to remove."
				exit 6
			fi
			NUMBEROFCLIENTS=$(echo "$CLIENTS" | wc -l)
			echo ""
			echo -e "  ${BOLD}${CYAN}Remove a VPN User${NC}"
			divider
			echo ""
			echo -e "  ${BOLD}Active clients:${NC}"
			echo ""
			echo "$CLIENTS" | nl -s ') ' | sed 's/^/    /'
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
			CLIENT=$(echo "$CLIENTS" | sed -n "${CLIENTNUMBER}p")
			echo ""
			echo -e "  ${YELLOW}${BOLD}⚠  You are about to remove: ${RED}$CLIENT${NC}"
			echo ""
			while true; do
				read -p "$(echo -e "  ${BOLD}Are you sure? [y/N]:${NC} ")" -e CONFIRM
				case "${CONFIRM,,}" in
					y|yes) break ;;
					n|no|"") echo ""; warn "Removal cancelled."; exit ;;
					*) warn "Please enter y or n." ;;
				esac
			done
			echo ""
			info "Removing client ${BOLD}$CLIENT${NC}..."
			CLIENT_PUBKEY=$(awk "/^# ${CLIENT}$/{found=1} found && /^PublicKey/{print \$3; found=0}" /etc/wireguard/wg0.conf)
			remove_peer_block "$CLIENT"
			if [[ -n "$CLIENT_PUBKEY" ]]; then
				wg set wg0 peer "$CLIENT_PUBKEY" remove 2>/dev/null || true
			fi
			rm -f ~/"$CLIENT".conf
			echo ""
			ok "Client ${BOLD}$CLIENT${NC} has been removed."
			echo ""
			exit
			;;

			3)
			if ! hash qrencode 2>/dev/null; then
				echo ""
				warn "${BOLD}qrencode${NC} is not installed."
				if [[ "$OS" = 'debian' ]]; then
					info "Install with: ${CYAN}apt-get install qrencode${NC}"
				else
					info "Install with: ${CYAN}yum install qrencode${NC}"
				fi
				echo ""
				exit
			fi
			CLIENTS=$(grep -oP '^# \K.+' /etc/wireguard/wg0.conf)
			if [[ -z "$CLIENTS" ]]; then
				echo ""
				warn "There are no clients."
				exit 6
			fi
			NUMBEROFCLIENTS=$(echo "$CLIENTS" | wc -l)
			echo ""
			echo -e "  ${BOLD}${CYAN}Show QR Code${NC}"
			divider
			echo ""
			echo -e "  ${BOLD}Available clients:${NC}"
			echo ""
			echo "$CLIENTS" | nl -s ') ' | sed 's/^/    /'
			echo ""
			while true; do
				read -p "$(echo -e "  ${BOLD}Select client [1-$NUMBEROFCLIENTS]:${NC} ")" CLIENTNUMBER
				if [[ "$CLIENTNUMBER" =~ ^[0-9]+$ ]] && (( CLIENTNUMBER >= 1 && CLIENTNUMBER <= NUMBEROFCLIENTS )); then
					break
				fi
				warn "Please enter a number between 1 and $NUMBEROFCLIENTS."
			done
			CLIENT=$(echo "$CLIENTS" | sed -n "${CLIENTNUMBER}p")
			echo ""
			if [[ -f ~/"$CLIENT".conf ]]; then
				info "QR Code for ${BOLD}$CLIENT${NC}:"
				echo ""
				qrencode -t ansiutf8 < ~/"$CLIENT".conf
				echo ""
			else
				warn "Config file ${CYAN}~/$CLIENT.conf${NC} not found."
				info "The config may have been generated in a previous session."
			fi
			exit
			;;

			4)
			echo ""
			echo -e "  ${BOLD}${RED}Remove WireGuard${NC}"
			divider
			echo ""
			warn "This will ${BOLD}permanently${NC} remove WireGuard and all its configuration."
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
			run_with_spinner "Stopping WireGuard service..." bash -c "wg-quick down wg0 2>/dev/null; systemctl disable wg-quick@wg0 2>/dev/null; true"
			if [[ "$OS" = 'debian' ]]; then
				run_with_spinner "Removing packages..." apt-get remove --purge -y wireguard wireguard-tools qrencode
			else
				run_with_spinner "Removing packages..." yum remove -y wireguard-tools
			fi
			rm -rf /etc/wireguard
			echo ""
			ok "WireGuard has been completely removed."
			echo ""
			exit
			;;

			5)
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
TOTAL_STEPS=5

clear
banner
echo -e "  ${BOLD}Welcome to the WireGuard Quick Setup Wizard${NC}"
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

# ── Step 2: Port ────────────────────────────
step 2 "Listening Port"
echo ""
info "Default WireGuard port is ${BOLD}51820${NC} (UDP only). You can use any port from 1 to 65535."
echo ""
while true; do
	read -p "$(echo -e "  ${BOLD}Port [51820]:${NC} ")" -e -i 51820 PORT
	if [[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )); then
		break
	fi
	warn "Port must be a number between 1 and 65535."
done
echo ""

# ── Step 3: DNS ─────────────────────────────
step 3 "DNS Server"
echo ""
echo -e "  ${CYAN}[1]${NC}  System resolvers    ${DIM}(/etc/resolv.conf)${NC}"
echo -e "  ${CYAN}[2]${NC}  Google              ${DIM}(8.8.8.8 / 8.8.4.4)${NC}"
echo -e "  ${CYAN}[3]${NC}  OpenDNS             ${DIM}(208.67.222.222 / 208.67.220.220)${NC}"
echo -e "  ${CYAN}[4]${NC}  Cloudflare          ${DIM}(1.1.1.1 / 1.0.0.1)${NC}"
echo -e "  ${CYAN}[5]${NC}  Quad9               ${DIM}(9.9.9.9 / 149.112.112.112)${NC}"
echo ""
while true; do
	read -p "$(echo -e "  ${BOLD}DNS choice [1-5, default: 2]:${NC} ")" -e -i 2 DNS
	if [[ "$DNS" =~ ^[1-5]$ ]]; then
		break
	fi
	warn "Please enter a number from 1 to 5."
done

case $DNS in
	1)
	DNS_IPS=$(grep -v '#' /etc/resolv.conf | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | tr '\n' ',' | sed 's/,$//')
	[[ -z "$DNS_IPS" ]] && DNS_IPS="8.8.8.8"
	;;
	2) DNS_IPS="8.8.8.8, 8.8.4.4" ;;
	3) DNS_IPS="208.67.222.222, 208.67.220.220" ;;
	4) DNS_IPS="1.1.1.1, 1.0.0.1" ;;
	5) DNS_IPS="9.9.9.9, 149.112.112.112" ;;
esac
echo ""

# ── Step 4: First Client Name ───────────────
step 4 "First Client Name"
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
echo -e "  ${BOLD}${BLUE}║${NC}  ${BOLD}Protocol    ${NC}  ${CYAN}UDP${NC}$(printf '%*s' 23 '')${BOLD}${BLUE}║${NC}"
echo -e "  ${BOLD}${BLUE}║${NC}  ${BOLD}Port        ${NC}  ${CYAN}$PORT${NC}$(printf '%*s' $((26 - ${#PORT})) '')${BOLD}${BLUE}║${NC}"
echo -e "  ${BOLD}${BLUE}║${NC}  ${BOLD}DNS         ${NC}  ${CYAN}Option $DNS${NC}$(printf '%*s' 18 '')${BOLD}${BLUE}║${NC}"
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

# ── Step 5: Install ─────────────────────────
step 5 "Installing WireGuard"
echo ""

if [[ "$OS" = 'debian' ]]; then
	run_with_spinner "Updating package lists..." apt-get update
	run_with_spinner "Installing WireGuard & tools..." apt-get install -y wireguard wireguard-tools qrencode
else
	run_with_spinner "Installing EPEL release..." yum install -y epel-release
	run_with_spinner "Installing WireGuard & tools..." yum install -y wireguard-tools qrencode
fi

mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

# Generate server key pair
info "Generating server keys..."
SERVER_PRIVATE_KEY=$(wg genkey)
SERVER_PUB_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)

# Build server config
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.8.0.1/24
ListenPort = $PORT
PrivateKey = $SERVER_PRIVATE_KEY
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $NIC -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $NIC -j MASQUERADE
EOF
chmod 600 /etc/wireguard/wg0.conf
ok "Server config created"

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
if pgrep firewalld &>/dev/null; then
	firewall-cmd --zone=public --add-port="$PORT"/udp
	firewall-cmd --permanent --zone=public --add-port="$PORT"/udp
	firewall-cmd --zone=trusted --add-source=10.8.0.0/24
	firewall-cmd --permanent --zone=trusted --add-source=10.8.0.0/24
else
	if iptables -L -n | grep -qE '^(REJECT|DROP)'; then
		iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT
		iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT
		iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
	fi
fi
ok "Firewall configured"

# Start WireGuard
run_with_spinner "Starting WireGuard service..." bash -c "
systemctl enable wg-quick@wg0 &>/dev/null
systemctl start wg-quick@wg0
"
ok "WireGuard service started"

# Detect NAT
SERVER_PUB_IP=$IP
EXTERNALIP=$(wget -4qO- "http://whatismyip.akamai.com/")
if [[ "$IP" != "$EXTERNALIP" ]]; then
	echo ""
	echo -e "  ${YELLOW}${BOLD}⚠  NAT Detected!${NC}"
	divider
	info "Local IP: ${BOLD}$IP${NC} | External IP: ${BOLD}$EXTERNALIP${NC}"
	info "Clients must connect using the external IP."
	echo ""
	read -p "$(echo -e "  ${BOLD}External IP [${EXTERNALIP}]:${NC} ")" -e -i "$EXTERNALIP" USEREXTERNALIP
	[[ -n "$USEREXTERNALIP" ]] && SERVER_PUB_IP="$USEREXTERNALIP"
fi
SERVER_PORT=$PORT

# Save params for future script runs
cat > "$PARAMS_FILE" <<EOF
SERVER_PUB_IP=$SERVER_PUB_IP
SERVER_PORT=$SERVER_PORT
SERVER_PUB_KEY=$SERVER_PUB_KEY
SERVER_PUB_NIC=$NIC
SERVER_DNS=$DNS_IPS
EOF
chmod 600 "$PARAMS_FILE"

# Generate first client config
info "Generating client config for ${BOLD}$CLIENT${NC}..."
newclient "$CLIENT" "10.8.0.2" "$DNS_IPS"

# ── Completion Screen ────────────────────────
clear
banner
echo -e "  ${BOLD}${GREEN}🎉  WireGuard is installed and ready!${NC}"
divider
echo ""
echo -e "  ${BOLD}Your client config file is ready at:${NC}"
echo ""
echo -e "  ${CYAN}${BOLD}  ~/$CLIENT.conf${NC}"
echo ""

if hash qrencode 2>/dev/null; then
	info "QR Code (scan with WireGuard mobile app):"
	echo ""
	qrencode -t ansiutf8 < ~/"$CLIENT".conf
	echo ""
fi

divider
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo ""
echo -e "  ${CYAN}1.${NC} Copy ${BOLD}~/$CLIENT.conf${NC} to your device"
echo -e "  ${CYAN}2.${NC} Import it into the WireGuard client app"
echo -e "  ${CYAN}3.${NC} Connect and enjoy your VPN! 🚀"
echo ""
echo -e "  ${DIM}Run this script again on the same server to add/remove users.${NC}"
divider
echo ""

fi
