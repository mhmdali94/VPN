# 🔐 OpenVPN Auto Installer

An automated Bash script to quickly set up a fully functional **OpenVPN server** on Debian, Ubuntu, and CentOS/RHEL systems — with zero manual configuration hassle.

> Originally by [Road Warrior](https://github.com/Nyr/openvpn-install), repo by [Kashif H Khan](https://github.com/kashifhkhan).  
> Updated automation by **Mohammed Ali** — [PrismaTechwork.com](https://prismatechwork.com) · [GitHub @mhmdali94](https://github.com/mhmdali94)

---

## ✨ Features

- 🚀 **One-command setup** — installs and configures OpenVPN from scratch
- 👤 **Client management** — add or revoke VPN clients interactively
- 🌐 **Multiple DNS options** — Google, OpenDNS, NTT, Hurricane Electric, Verisign, or your system's own resolvers
- 🔒 **Strong security defaults** — AES-256-CBC cipher, SHA512 auth, TLS-auth key
- 📦 **EasyRSA v3.2.1** — automatic PKI setup, CA, DH params, and certificate generation
- 🔁 **LZ4 compression** — fast and modern (replaces deprecated `comp-lzo`)
- 🛡️ **Firewall support** — works with both `firewalld` and `iptables`
- 🖥️ **NAT-aware** — detects NATed servers and prompts for the correct external IP
- 🔌 **UDP & TCP** — choose your preferred protocol during setup

---

## 📋 Requirements

| Requirement | Details |
|---|---|
| **OS** | Debian, Ubuntu, CentOS 6+, RHEL |
| **Shell** | `bash` (not `sh`) |
| **Privileges** | Must be run as `root` |
| **TUN device** | `/dev/net/tun` must be available |

---

## 🚀 Quick Start

### Ubuntu / Debian

```bash
wget https://raw.githubusercontent.com/mhmdali94/VPN/main/openvpn-ubuntu.sh
chmod +x openvpn-ubuntu.sh
sudo bash openvpn-ubuntu.sh
```

### CentOS / RHEL

```bash
wget https://raw.githubusercontent.com/mhmdali94/VPN/main/centos.sh
chmod +x centos.sh
sudo bash centos.sh
```

---

## ⚙️ Installation Walkthrough

When you run the script for the first time, it will interactively ask you:

1. **Server IP** — the IPv4 address OpenVPN will listen on
2. **Protocol** — UDP *(recommended)* or TCP
3. **Port** — default `1194`
4. **DNS** — choose from 6 options:
   - System resolvers
   - Google (`8.8.8.8`, `8.8.4.4`)
   - OpenDNS (`208.67.222.222`, `208.67.220.220`)
   - NTT (`129.250.35.250`, `129.250.35.251`)
   - Hurricane Electric (`74.82.42.42`)
   - Verisign (`64.6.64.6`, `64.6.65.6`)
5. **Client name** — a name for your first VPN client certificate

After answering, the script will:
- Install OpenVPN and dependencies
- Download EasyRSA and build the PKI infrastructure
- Generate server & client certificates
- Configure and start the OpenVPN service
- Output a ready-to-use `.ovpn` client config file in your home directory (`~/<client-name>.ovpn`)

---

## 📂 Generated Files

| File | Location | Description |
|---|---|---|
| `server.conf` | `/etc/openvpn/` | OpenVPN server configuration |
| `ca.crt` | `/etc/openvpn/` | Certificate Authority |
| `server.crt/key` | `/etc/openvpn/` | Server certificate & key |
| `ta.key` | `/etc/openvpn/` | TLS-auth key |
| `dh.pem` | `/etc/openvpn/` | Diffie-Hellman params |
| `<client>.ovpn` | `~/` | Importable client config file |

---

## 👥 Managing Clients

Running the script **again on a server where OpenVPN is already installed** opens a management menu:

```
What do you want to do?
   1) Add a new user
   2) Revoke an existing user
   3) Remove OpenVPN
   4) Exit
```

- **Add a user** → generates a new `.ovpn` file in `~/`
- **Revoke a user** → invalidates their certificate so they can no longer connect
- **Remove OpenVPN** → uninstalls OpenVPN and cleans up all configs and firewall rules

---

## 🔒 Security Configuration

The server is configured with the following security settings by default:

| Setting | Value |
|---|---|
| Cipher | `AES-256-CBC` |
| Auth | `SHA512` |
| TLS Auth | Enabled (`ta.key`) |
| CRL expiry | 10 years (3650 days) |
| Compression | `lz4-v2` |
| Certificate type | RSA (via EasyRSA 3.2.1) |

---

## 🌍 NAT / Cloud Server Support

If your server sits behind a NAT (e.g., AWS EC2, DigitalOcean with private IP), the script will automatically detect the mismatch between the local and external IP and prompt you to enter the correct public IP for client configuration.

---

## 📄 License

This project is based on the original [openvpn-install](https://github.com/Nyr/openvpn-install) by Nyr, distributed under the MIT License.

---

## 🤝 Author

**Mohammed Ali**  
🌐 [PrismaTechwork.com](https://prismatechwork.com) · 🐙 [GitHub @mhmdali94](https://github.com/mhmdali94)
