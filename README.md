# VPN Auto Installers

Automated Bash scripts to set up a fully functional **OpenVPN** or **WireGuard** server on Debian, Ubuntu, and CentOS — with zero manual configuration.

> By **Mohammed Ali** — [PrismaTechwork.com](https://prismatechwork.com) · [GitHub @mhmdali94](https://github.com/mhmdali94)

---

## Scripts

| Script | Protocol | File |
| --- | --- | --- |
| OpenVPN | UDP or TCP, port 1194 | `openvpn-ubuntu.sh` |
| WireGuard | UDP only, port 51820 | `wireguard-ubuntu.sh` |

---

## Requirements

| Requirement | OpenVPN | WireGuard |
| --- | --- | --- |
| **OS** | Debian 10+, Ubuntu 18.04+, CentOS 7+ | Debian 11+, Ubuntu 20.04+, CentOS 8+ |
| **Shell** | `bash` (not `sh`) | `bash` (not `sh`) |
| **Privileges** | `root` | `root` |
| **TUN device** | `/dev/net/tun` required | Not required |

---

## Quick Start

### OpenVPN

```bash
wget https://raw.githubusercontent.com/mhmdali94/VPN/main/openvpn-ubuntu.sh
chmod +x openvpn-ubuntu.sh
sudo bash openvpn-ubuntu.sh
```

### WireGuard

```bash
wget https://raw.githubusercontent.com/mhmdali94/VPN/main/wireguard-ubuntu.sh
chmod +x wireguard-ubuntu.sh
sudo bash wireguard-ubuntu.sh
```

---

## OpenVPN

### Setup Wizard

The script asks 5 questions, then installs everything automatically:

1. **Server IP** — auto-detected, confirm or override
2. **Protocol** — UDP *(recommended)* or TCP
3. **Port** — default `1194`
4. **DNS** — choose from 6 options (Google, OpenDNS, Cloudflare, etc.)
5. **Client name** — name for the first `.ovpn` profile

After setup, your client config is at `~/<client>.ovpn`. Import it into any OpenVPN app.

### Management Menu

Run the script again on the same server:

```
[1]  Add a new VPN user
[2]  Revoke an existing user
[3]  Remove OpenVPN completely
[4]  Exit
```

### Security Configuration

| Setting | Value |
| --- | --- |
| Cipher | `AES-256-GCM` / `AES-128-GCM` / `AES-256-CBC` (NCP negotiated) |
| Auth | `SHA512` |
| TLS Auth | Enabled (`ta.key`, key-direction 1) |
| PKI | EasyRSA 3.2.1 |
| CRL expiry | 3650 days |

### Generated Files

| File | Location |
| --- | --- |
| `server.conf` | `/etc/openvpn/` |
| `ca.crt`, `ta.key`, `dh.pem` | `/etc/openvpn/` |
| `server.crt` / `server.key` | `/etc/openvpn/` |
| `<client>.ovpn` | `~/` |

---

## WireGuard

### Setup Wizard

1. **Server IP** — auto-detected, confirm or override
2. **Port** — default `51820` (UDP only)
3. **DNS** — choose from 5 options (Google, Cloudflare, Quad9, etc.)
4. **Client name** — name for the first `.conf` profile

After setup, your client config is at `~/<client>.conf`. A QR code is displayed for mobile import.

### Management Menu

Run the script again on the same server:

```
[1]  Add a new VPN user
[2]  Remove an existing user
[3]  Show QR code for a user
[4]  Remove WireGuard completely
[5]  Exit
```

### Security Configuration

| Setting | Value |
| --- | --- |
| Encryption | ChaCha20-Poly1305 (built-in to WireGuard) |
| Key exchange | Curve25519 |
| Preshared key | Per-client PSK for post-quantum resistance |
| Handshake | Every 180 seconds |
| Keepalive | 25 seconds |

### Generated Files

| File | Location |
| --- | --- |
| `wg0.conf` | `/etc/wireguard/` |
| `params` | `/etc/wireguard/` (server settings for future runs) |
| `<client>.conf` | `~/` |

---

## NAT / Cloud Server Support

Both scripts detect when the server is behind a NAT (e.g., AWS EC2, DigitalOcean with private networking) and prompt for the correct public IP to embed in client configs.

---

## OpenVPN vs WireGuard

| | OpenVPN | WireGuard |
| --- | --- | --- |
| Speed | Moderate | Fast |
| Setup complexity | Higher (PKI/CA required) | Simple (key pairs only) |
| Protocol | UDP or TCP | UDP only |
| Mobile QR import | No | Yes |
| Audit history | Mature, widely audited | Newer, clean codebase |
| Best for | Bypassing restrictive firewalls (TCP mode) | Speed and simplicity |

---

## License

OpenVPN script based on [openvpn-install](https://github.com/Nyr/openvpn-install) by Nyr (MIT).

---

## Author

**Mohammed Ali**
[PrismaTechwork.com](https://prismatechwork.com) · [GitHub @mhmdali94](https://github.com/mhmdali94)
