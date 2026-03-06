# QQ-Tunnel Server

A deployable DNS tunnel server based on [QQ-Tunnel](https://github.com/user/QQ-Tunnel). Install on your Linux server, run the interactive setup wizard to configure, and manage via CLI.

## Quick Start

### 1. DNS Setup (Cloudflare)

Create these records in your Cloudflare dashboard:

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | `ns1` | `YOUR_SERVER_IP` | DNS only (grey cloud) |
| NS | `tunnel` | `ns1.yourdomain.com` | - |

### 2. Install on Server

```bash
# Upload the QQ-Tunnel-Server folder to your server, then:
cd QQ-Tunnel-Server
sudo bash install.sh
```

### 3. Configure

```bash
sudo qq-tunnel setup
```

The interactive wizard will ask for:
- **Receive domain** — must match your NS record (e.g. `tunnel.yourdomain.com`)
- **Send domain** — usually same as receive domain
- **DNS server IPs** — public resolvers like `8.8.8.8`
- **Backend address** — where decoded traffic goes (e.g. `127.0.0.1:8080` for v2ray)
- **Checksum password** — shared secret (auto-generated if left blank)
- **Advanced settings** — domain length, retries, query type, etc.

### 4. Start

```bash
sudo qq-tunnel start
```

## CLI Commands

| Command | Description |
|---------|-------------|
| `sudo qq-tunnel setup` | Interactive configuration wizard |
| `sudo qq-tunnel start` | Start the tunnel service |
| `sudo qq-tunnel stop` | Stop the tunnel service |
| `sudo qq-tunnel restart` | Restart the tunnel service |
| `sudo qq-tunnel status` | Show tunnel status and config summary |
| `sudo qq-tunnel logs` | Follow live logs |
| `sudo qq-tunnel uninstall` | Remove QQ-Tunnel completely |

## Client Setup

After running `setup`, the wizard prints a client `config.json` you can copy directly. Example:

```json
{
  "dns_ips": ["8.8.8.8", "1.1.1.1"],
  "send_interface_ip": "0.0.0.0",
  "receive_interface_ip": "0.0.0.0",
  "receive_port": 5353,
  "send_domain": "tunnel.yourdomain.com",
  "recv_domain": "tunnel.yourdomain.com",
  "h_in_address": "127.0.0.1:10443",
  "h_out_address": "",
  "max_domain_len": 99,
  "max_sub_len": 63,
  "retries": 0,
  "send_query_type_int": 1,
  "recv_query_type_int": 1,
  "chksum_pass": "YOUR_SHARED_SECRET",
  "send_sock_numbers": 8192,
  "assemble_time": 3
}
```

### Using with VPN Apps (v2ray, HTTP Injector)

1. Run v2ray/Xray on the server listening on `127.0.0.1:8080`
2. Set `h_out_address` to `127.0.0.1:8080` during setup
3. On client, point your VPN app to `127.0.0.1:10443`

### Using on Android (Termux)

```bash
pkg install python
# Copy the original QQ-Tunnel project + client config.json
python3 main.py
```

Then configure your VPN app to connect to `127.0.0.1:10443`.

## Requirements

- Linux (Debian/Ubuntu, RHEL/CentOS/Fedora)
- Python 3.7+
- Root access
- Domain with NS records pointing to the server

## License

Same as the original QQ-Tunnel project.
