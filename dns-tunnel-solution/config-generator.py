#!/usr/bin/env python3
"""
DNS Tunnel Config Generator
Generates shareable configs for friends to easily connect.
Outputs: JSON config, dnstt:// URI, connection commands, and optional QR code.

Usage:
    python config-generator.py --domain t.example.com --pubkey <64-char-hex>
    python config-generator.py --domain s2.example.com --pubkey <key> --ssh-user tunnel --ssh-pass secret
    python config-generator.py --import-uri "dnstt://base64..."
    python config-generator.py --interactive
"""

import argparse
import base64
import json
import os
import sys
import textwrap


# DoH resolvers ranked by availability
DOH_RESOLVERS = [
    "https://dns.google/dns-query",
    "https://cloudflare-dns.com/dns-query",
    "https://dns.quad9.net/dns-query",
    "https://dns.adguard-dns.com/dns-query",
    "https://dns.nextdns.io/dns-query",
    "https://dns.mullvad.net/dns-query",
]

DOT_RESOLVERS = [
    "dns.google:853",
    "cloudflare-dns.com:853",
    "dns.quad9.net:853",
]

UDP_RESOLVERS = [
    "8.8.8.8:53",
    "1.1.1.1:53",
    "9.9.9.9:53",
]


def create_config(domain, pubkey, ssh_user=None, ssh_pass=None,
                  profile_name="tunnel", mtu=512, resolvers=None):
    """Create a tunnel configuration dictionary."""
    config = {
        "version": 2,
        "profile": profile_name,
        "domain": domain,
        "pubkey": pubkey,
        "mtu": mtu,
        "transport": "doh",
        "doh_resolvers": resolvers or DOH_RESOLVERS[:3],
        "dot_resolvers": DOT_RESOLVERS[:2],
        "udp_resolvers": UDP_RESOLVERS[:2],
    }

    if ssh_user:
        config["ssh_user"] = ssh_user
    if ssh_pass:
        config["ssh_pass"] = ssh_pass

    return config


def config_to_uri(config):
    """Encode config as a dnstt:// URI for easy sharing."""
    # Compact JSON for shorter URI
    compact = {
        "v": config.get("version", 2),
        "p": config.get("profile", "tunnel"),
        "d": config["domain"],
        "k": config["pubkey"],
        "m": config.get("mtu", 512),
        "t": "doh",
        "r": config.get("doh_resolvers", DOH_RESOLVERS[:3]),
    }
    if config.get("ssh_user"):
        compact["u"] = config["ssh_user"]
    if config.get("ssh_pass"):
        compact["pw"] = config["ssh_pass"]

    json_str = json.dumps(compact, separators=(",", ":"))
    b64 = base64.urlsafe_b64encode(json_str.encode()).decode().rstrip("=")
    return f"dnstt://{b64}"


def uri_to_config(uri):
    """Decode a dnstt:// URI back to config."""
    if uri.startswith("dnstt://"):
        b64 = uri[8:]
    elif uri.startswith("dns://"):
        b64 = uri[6:]
    else:
        b64 = uri

    # Add padding if needed
    padding = 4 - len(b64) % 4
    if padding != 4:
        b64 += "=" * padding

    try:
        json_str = base64.urlsafe_b64decode(b64).decode()
    except Exception:
        json_str = base64.b64decode(b64).decode()

    data = json.loads(json_str)

    # Handle both compact and full formats
    config = {
        "version": data.get("v", data.get("version", 2)),
        "profile": data.get("p", data.get("ps", data.get("profile", "tunnel"))),
        "domain": data.get("d", data.get("ns", data.get("domain", ""))),
        "pubkey": data.get("k", data.get("pubkey", "")),
        "mtu": data.get("m", data.get("mtu", 512)),
        "transport": data.get("t", data.get("transport", "doh")),
        "doh_resolvers": data.get("r", data.get("doh_resolvers", DOH_RESOLVERS[:3])),
    }

    ssh_user = data.get("u", data.get("user", data.get("ssh_user")))
    ssh_pass = data.get("pw", data.get("pass", data.get("ssh_pass")))
    if ssh_user:
        config["ssh_user"] = ssh_user
    if ssh_pass:
        config["ssh_pass"] = ssh_pass

    return config


def generate_connection_commands(config):
    """Generate ready-to-use connection commands."""
    domain = config["domain"]
    pubkey = config["pubkey"]
    resolvers = config.get("doh_resolvers", DOH_RESOLVERS[:3])
    ssh_user = config.get("ssh_user")
    ssh_pass = config.get("ssh_pass")

    commands = []

    # Primary: DoH
    for resolver in resolvers:
        commands.append({
            "transport": "DoH",
            "resolver": resolver,
            "command": f'dnstt-client -doh {resolver} -pubkey-file server.pub {domain} 127.0.0.1:7000',
        })

    # Fallback: DoT
    for resolver in config.get("dot_resolvers", DOT_RESOLVERS[:2]):
        commands.append({
            "transport": "DoT",
            "resolver": resolver,
            "command": f'dnstt-client -dot {resolver} -pubkey-file server.pub {domain} 127.0.0.1:7000',
        })

    # Last resort: UDP
    for resolver in config.get("udp_resolvers", UDP_RESOLVERS[:2]):
        commands.append({
            "transport": "UDP",
            "resolver": resolver,
            "command": f'dnstt-client -udp {resolver} -pubkey-file server.pub {domain} 127.0.0.1:7000',
        })

    ssh_command = None
    if ssh_user:
        ssh_command = f'ssh -N -D 127.0.0.1:8000 -p 7000 {ssh_user}@127.0.0.1'

    return commands, ssh_command


def generate_text_qr(data, quiet=True):
    """Generate a simple text-based QR representation (if qrcode is available)."""
    try:
        import qrcode
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=1,
            border=1,
        )
        qr.add_data(data)
        qr.make(fit=True)

        lines = []
        matrix = qr.get_matrix()
        for row in matrix:
            line = ""
            for cell in row:
                line += "██" if cell else "  "
            lines.append(line)
        return "\n".join(lines)
    except ImportError:
        return None


def print_config_output(config, uri):
    """Print formatted output with all connection info."""
    commands, ssh_cmd = generate_connection_commands(config)

    print("\n" + "=" * 70)
    print("  DNS TUNNEL CONFIGURATION")
    print("=" * 70)

    print(f"\n  Profile:    {config.get('profile', 'tunnel')}")
    print(f"  Domain:     {config['domain']}")
    print(f"  Public Key: {config['pubkey']}")
    print(f"  MTU:        {config.get('mtu', 512)}")
    print(f"  Transport:  DoH (DNS-over-HTTPS)")

    if config.get("ssh_user"):
        print(f"\n  SSH User:   {config['ssh_user']}")
        print(f"  SSH Pass:   {config.get('ssh_pass', 'N/A')}")

    print("\n" + "-" * 70)
    print("  SHAREABLE URI (send this to your friend):")
    print("-" * 70)
    print(f"\n  {uri}\n")

    # QR code
    qr_text = generate_text_qr(uri)
    if qr_text:
        print("-" * 70)
        print("  QR CODE (scan with phone):")
        print("-" * 70)
        print(qr_text)
        print()

    print("-" * 70)
    print("  CONNECTION COMMANDS (try in order):")
    print("-" * 70)

    for i, cmd in enumerate(commands, 1):
        priority = "RECOMMENDED" if i == 1 else f"Fallback #{i-1}"
        print(f"\n  [{priority}] {cmd['transport']} via {cmd['resolver']}")
        print(f"  $ {cmd['command']}")

    if ssh_cmd:
        print(f"\n  Then create SSH SOCKS proxy:")
        print(f"  $ {ssh_cmd}")
        print(f"  Password: {config.get('ssh_pass', 'N/A')}")
        print(f"\n  Configure browser SOCKS5 proxy: 127.0.0.1:8000")
    else:
        print(f"\n  Configure browser SOCKS5 proxy: 127.0.0.1:7000")

    print("\n" + "-" * 70)
    print("  QUICK START (using the provided scripts):")
    print("-" * 70)

    pubkey = config["pubkey"]
    domain = config["domain"]

    print(f"\n  Windows PowerShell:")
    if config.get("ssh_user"):
        print(f'  .\\connect.ps1 -Domain "{domain}" -PubKey "{pubkey}" -SshMode -SshUser "{config["ssh_user"]}" -SshPass "{config.get("ssh_pass", "")}"')
    else:
        print(f'  .\\connect.ps1 -Domain "{domain}" -PubKey "{pubkey}"')

    print(f"\n  Linux/Mac:")
    if config.get("ssh_user"):
        print(f'  ./connect.sh -d {domain} -k {pubkey} --ssh --ssh-user {config["ssh_user"]} --ssh-pass {config.get("ssh_pass", "")}')
    else:
        print(f'  ./connect.sh -d {domain} -k {pubkey}')

    print("\n" + "-" * 70)
    print("  PUBLIC KEY FILE")
    print("-" * 70)
    print(f"\n  Save this as 'server.pub' (same directory as dnstt-client):")
    print(f"  {pubkey}")

    print("\n" + "-" * 70)
    print("  INSTRUCTIONS FOR YOUR FRIEND")
    print("-" * 70)
    print(textwrap.dedent(f"""
    1. Download dnstt-client for your OS from: https://dnstt.network
    2. Save this public key as 'server.pub':
       {pubkey}
    3. Run this command:
       dnstt-client -doh https://dns.google/dns-query -pubkey-file server.pub {domain} 127.0.0.1:7000
    4. If Google doesn't work, try:
       dnstt-client -doh https://cloudflare-dns.com/dns-query -pubkey-file server.pub {domain} 127.0.0.1:7000
    5. Set your browser SOCKS5 proxy to: 127.0.0.1:7000
    """))

    if config.get("ssh_user"):
        print(f"    6. Then connect SSH: ssh -N -D 127.0.0.1:8000 -p 7000 {config['ssh_user']}@127.0.0.1")
        print(f"       Password: {config.get('ssh_pass', '')}")
        print(f"    7. Set browser SOCKS5 proxy to: 127.0.0.1:8000")

    print("=" * 70 + "\n")


def save_config_files(config, uri, output_dir="."):
    """Save config to multiple formats for easy distribution."""
    os.makedirs(output_dir, exist_ok=True)
    profile = config.get("profile", "tunnel")

    # JSON config
    json_path = os.path.join(output_dir, f"{profile}-config.json")
    with open(json_path, "w") as f:
        json.dump(config, f, indent=2)
    print(f"  Saved: {json_path}")

    # URI file
    uri_path = os.path.join(output_dir, f"{profile}-uri.txt")
    with open(uri_path, "w") as f:
        f.write(uri)
    print(f"  Saved: {uri_path}")

    # Public key file
    pub_path = os.path.join(output_dir, "server.pub")
    with open(pub_path, "w") as f:
        f.write(config["pubkey"])
    print(f"  Saved: {pub_path}")

    # Ready-to-use batch file (Windows)
    bat_path = os.path.join(output_dir, f"{profile}-connect.bat")
    domain = config["domain"]
    with open(bat_path, "w") as f:
        f.write(f'@echo off\n')
        f.write(f'echo Connecting to DNS tunnel...\n')
        f.write(f'echo Trying DoH (Google)...\n')
        f.write(f'dnstt-client-windows-amd64.exe -doh https://dns.google/dns-query -pubkey-file server.pub {domain} 127.0.0.1:7000\n')
        f.write(f'if %ERRORLEVEL% NEQ 0 (\n')
        f.write(f'  echo Google failed, trying Cloudflare...\n')
        f.write(f'  dnstt-client-windows-amd64.exe -doh https://cloudflare-dns.com/dns-query -pubkey-file server.pub {domain} 127.0.0.1:7000\n')
        f.write(f')\n')
        f.write(f'pause\n')
    print(f"  Saved: {bat_path}")

    # Instructions text file
    instructions_path = os.path.join(output_dir, f"{profile}-instructions.txt")
    commands, ssh_cmd = generate_connection_commands(config)
    with open(instructions_path, "w", encoding="utf-8") as f:
        f.write("DNS Tunnel Connection Instructions\n")
        f.write("=" * 50 + "\n\n")
        f.write(f"Domain: {domain}\n")
        f.write(f"Public Key: {config['pubkey']}\n")
        f.write(f"MTU: {config.get('mtu', 512)}\n\n")

        if config.get("ssh_user"):
            f.write(f"SSH Username: {config['ssh_user']}\n")
            f.write(f"SSH Password: {config.get('ssh_pass', 'N/A')}\n\n")

        f.write("STEP 1: Download dnstt-client\n")
        f.write("-" * 30 + "\n")
        f.write("Go to: https://dnstt.network\n")
        f.write("Download the version for your OS (Windows/Linux/Mac)\n\n")

        f.write("STEP 2: Save the public key\n")
        f.write("-" * 30 + "\n")
        f.write(f"Create a file called 'server.pub' with this content:\n")
        f.write(f"{config['pubkey']}\n\n")

        f.write("STEP 3: Connect (try commands in order)\n")
        f.write("-" * 30 + "\n")
        for i, cmd in enumerate(commands, 1):
            f.write(f"\nOption {i} ({cmd['transport']} via {cmd['resolver']}):\n")
            f.write(f"  {cmd['command']}\n")

        if ssh_cmd:
            f.write(f"\nSTEP 4: SSH tunnel\n")
            f.write(f"-" * 30 + "\n")
            f.write(f"  {ssh_cmd}\n")
            f.write(f"  Password: {config.get('ssh_pass', 'N/A')}\n")
            f.write(f"\nSTEP 5: Browser proxy\n")
            f.write(f"  Set SOCKS5 proxy to: 127.0.0.1:8000\n")
        else:
            f.write(f"\nSTEP 4: Browser proxy\n")
            f.write(f"-" * 30 + "\n")
            f.write(f"  Set SOCKS5 proxy to: 127.0.0.1:7000\n")

        # Farsi instructions
        f.write("\n\n" + "=" * 50 + "\n")
        f.write("راهنمای اتصال تانل DNS\n")
        f.write("=" * 50 + "\n\n")
        f.write(f"دامنه: {domain}\n")
        f.write(f"کلید عمومی: {config['pubkey']}\n\n")
        f.write("مرحله 1: دانلود dnstt-client از https://dnstt.network\n")
        f.write("مرحله 2: یک فایل به نام server.pub بسازید و کلید عمومی رو توش بذارید\n")
        f.write(f"مرحله 3: این دستور رو اجرا کنید:\n")
        f.write(f"  dnstt-client -doh https://dns.google/dns-query -pubkey-file server.pub {domain} 127.0.0.1:7000\n")
        f.write(f"اگر کار نکرد:\n")
        f.write(f"  dnstt-client -doh https://cloudflare-dns.com/dns-query -pubkey-file server.pub {domain} 127.0.0.1:7000\n")

        if config.get("ssh_user"):
            f.write(f"مرحله 4: تانل SSH بزنید:\n")
            f.write(f"  ssh -N -D 127.0.0.1:8000 -p 7000 {config['ssh_user']}@127.0.0.1\n")
            f.write(f"  رمز: {config.get('ssh_pass', '')}\n")
            f.write(f"مرحله 5: پروکسی مرورگر: SOCKS5 127.0.0.1:8000\n")
        else:
            f.write(f"مرحله 4: پروکسی مرورگر: SOCKS5 127.0.0.1:7000\n")

    print(f"  Saved: {instructions_path}")


def interactive_mode():
    """Interactive config creation."""
    print("\n  DNS Tunnel Config Generator - Interactive Mode\n")

    domain = input("  Tunnel domain (e.g., t.example.com): ").strip()
    if not domain:
        print("  Error: domain is required")
        sys.exit(1)

    pubkey = input("  Server public key (64-char hex): ").strip()
    if not pubkey:
        print("  Error: public key is required")
        sys.exit(1)

    profile = input("  Profile name [tunnel]: ").strip() or "tunnel"
    mtu = input("  MTU [512]: ").strip() or "512"

    ssh_user = input("  SSH username (leave blank for SOCKS-only mode): ").strip()
    ssh_pass = ""
    if ssh_user:
        ssh_pass = input("  SSH password: ").strip()

    save = input("  Save config files to disk? [y/N]: ").strip().lower()

    config = create_config(
        domain=domain,
        pubkey=pubkey,
        ssh_user=ssh_user or None,
        ssh_pass=ssh_pass or None,
        profile_name=profile,
        mtu=int(mtu),
    )

    uri = config_to_uri(config)
    print_config_output(config, uri)

    if save == "y":
        output_dir = input("  Output directory [./configs]: ").strip() or "./configs"
        save_config_files(config, uri, output_dir)
        print(f"\n  All files saved to: {output_dir}")
        print("  Send the entire folder to your friend!")


def main():
    parser = argparse.ArgumentParser(
        description="DNS Tunnel Config Generator - Create shareable configs for friends",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""
Examples:
  %(prog)s --domain t.example.com --pubkey abcdef1234...
  %(prog)s --domain s2.example.com --pubkey KEY --ssh-user tunnel --ssh-pass secret
  %(prog)s --import-uri "dnstt://base64encoded..."
  %(prog)s --interactive
  %(prog)s --domain t.example.com --pubkey KEY --save --output ./friend-config
        """)
    )

    parser.add_argument("-d", "--domain", help="Tunnel domain (e.g., t.example.com)")
    parser.add_argument("-k", "--pubkey", help="Server public key (64-char hex)")
    parser.add_argument("-p", "--profile", default="tunnel", help="Profile name (default: tunnel)")
    parser.add_argument("-m", "--mtu", type=int, default=512, help="MTU value (default: 512)")
    parser.add_argument("--ssh-user", help="SSH username (for SSH tunnel mode)")
    parser.add_argument("--ssh-pass", help="SSH password")
    parser.add_argument("--import-uri", help="Import and decode a dnstt:// URI")
    parser.add_argument("--save", action="store_true", help="Save config files to disk")
    parser.add_argument("--output", default="./configs", help="Output directory for saved files")
    parser.add_argument("--interactive", "-i", action="store_true", help="Interactive mode")
    parser.add_argument("--json", action="store_true", help="Output config as JSON only")

    args = parser.parse_args()

    if args.interactive:
        interactive_mode()
        return

    if args.import_uri:
        config = uri_to_config(args.import_uri)
        uri = config_to_uri(config)
        if args.json:
            print(json.dumps(config, indent=2))
        else:
            print_config_output(config, uri)
        if args.save:
            save_config_files(config, uri, args.output)
        return

    if not args.domain or not args.pubkey:
        parser.print_help()
        print("\nError: --domain and --pubkey are required (or use --interactive / --import-uri)")
        sys.exit(1)

    config = create_config(
        domain=args.domain,
        pubkey=args.pubkey,
        ssh_user=args.ssh_user,
        ssh_pass=args.ssh_pass,
        profile_name=args.profile,
        mtu=args.mtu,
    )

    uri = config_to_uri(config)

    if args.json:
        print(json.dumps(config, indent=2))
    else:
        print_config_output(config, uri)

    if args.save:
        print("\nSaving config files...")
        save_config_files(config, uri, args.output)
        print(f"\nAll files saved to: {args.output}")
        print("Send the entire folder to your friend!")


if __name__ == "__main__":
    main()
