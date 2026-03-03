
#!/bin/bash
# PrismaTech Secure OpenVPN Installer (Ubuntu 22/24)
# Based on MIT licensed script by Kashif H Khan (2017)
# Modernized & secured by Mohammed Ali - PrismaTechWork (2026)

set -euo pipefail
IFS=$'\n\t'

# ---- Root Check ----
if [[ "$EUID" -ne 0 ]]; then
    echo "Run as root."
    exit 1
fi

# ---- Ubuntu Version Check ----
source /etc/os-release
if [[ "$ID" != "ubuntu" ]]; then
    echo "This installer supports Ubuntu only."
    exit 1
fi

if [[ "$VERSION_ID" != "22.04" && "$VERSION_ID" != "24.04" ]]; then
    echo "Only Ubuntu 22.04 and 24.04 supported."
    exit 1
fi

echo "Detected Ubuntu $VERSION_ID ✔"

# ---- Install Packages ----
apt update
apt install -y openvpn easy-rsa ufw curl

# ---- Basic Variables ----
read -p "OpenVPN Port [1194]: " PORT
PORT=${PORT:-1194}

PROTO="udp"
VPN_SUBNET="10.8.0.0"
VPN_NETMASK="255.255.255.0"

PUBLIC_IP=$(curl -4s https://api.ipify.org)

echo "Detected Public IP: $PUBLIC_IP"

# ---- Setup PKI ----
make-cadir /etc/openvpn/easy-rsa
cd /etc/openvpn/easy-rsa

./easyrsa init-pki
./easyrsa --batch build-ca nopass
./easyrsa build-server-full server nopass
./easyrsa gen-dh
./easyrsa gen-crl

cp pki/ca.crt pki/private/server.key pki/issued/server.crt pki/dh.pem pki/crl.pem /etc/openvpn/

chown nobody:nogroup /etc/openvpn/crl.pem

# ---- TLS-Crypt Key ----
openvpn --genkey secret /etc/openvpn/tls-crypt.key

# ---- Server Config ----
cat > /etc/openvpn/server.conf <<EOF
port $PORT
proto $PROTO
dev tun

user nobody
group nogroup
persist-key
persist-tun

topology subnet
server $VPN_SUBNET $VPN_NETMASK

tls-version-min 1.2
tls-crypt tls-crypt.key

data-ciphers AES-256-GCM:AES-128-GCM
data-ciphers-fallback AES-256-GCM
auth SHA256

keepalive 10 120

push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

crl-verify crl.pem
verb 3
EOF

# ---- Enable IP Forward ----
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# ---- UFW Rules ----
ufw allow $PORT/$PROTO
ufw allow OpenSSH

echo "Configuring NAT..."
NIC=$(ip route | grep default | awk '{print $5}')

cat >> /etc/ufw/before.rules <<NAT
# START OPENVPN RULES
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s $VPN_SUBNET/24 -o $NIC -j MASQUERADE
COMMIT
# END OPENVPN RULES
NAT

sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

ufw disable
ufw enable

# ---- Start OpenVPN ----
systemctl enable openvpn-server@server
systemctl start openvpn-server@server

# ---- Create First Client ----
read -p "Client name: " CLIENT

cd /etc/openvpn/easy-rsa
./easyrsa build-client-full $CLIENT nopass

cat > /root/$CLIENT.ovpn <<EOF
client
dev tun
proto $PROTO
remote $PUBLIC_IP $PORT
resolv-retry infinite
nobind
persist-key
persist-tun

remote-cert-tls server
tls-version-min 1.2
tls-crypt tls-crypt.key

data-ciphers AES-256-GCM:AES-128-GCM
auth SHA256

verb 3
EOF

echo "<ca>" >> /root/$CLIENT.ovpn
cat /etc/openvpn/ca.crt >> /root/$CLIENT.ovpn
echo "</ca>" >> /root/$CLIENT.ovpn

echo "<cert>" >> /root/$CLIENT.ovpn
cat pki/issued/$CLIENT.crt >> /root/$CLIENT.ovpn
echo "</cert>" >> /root/$CLIENT.ovpn

echo "<key>" >> /root/$CLIENT.ovpn
cat pki/private/$CLIENT.key >> /root/$CLIENT.ovpn
echo "</key>" >> /root/$CLIENT.ovpn

echo "<tls-crypt>" >> /root/$CLIENT.ovpn
cat /etc/openvpn/tls-crypt.key >> /root/$CLIENT.ovpn
echo "</tls-crypt>" >> /root/$CLIENT.ovpn

echo ""
echo "✔ Installation Complete"
echo "Client file: /root/$CLIENT.ovpn"
