#!/usr/bin/env python3
"""
QQ-Tunnel Server Interactive Setup
Collects configuration from the user and generates config.json
"""

import json
import os
import sys
import secrets
import string
import subprocess
import shutil

INSTALL_DIR = "/opt/qq-tunnel"
SERVICE_NAME = "qq-tunnel"
CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json")

BOLD = "\033[1m"
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
CYAN = "\033[96m"
RESET = "\033[0m"


def print_header():
    print(f"""
{CYAN}{BOLD}============================================
       QQ-Tunnel Server Setup
============================================{RESET}
""")


def prompt(text, default=None, required=True):
    if default is not None:
        display = f"{BOLD}{text}{RESET} [{GREEN}{default}{RESET}]: "
    else:
        display = f"{BOLD}{text}{RESET}: "
    while True:
        value = input(display).strip()
        if not value and default is not None:
            return default
        if not value and required:
            print(f"{RED}  This field is required.{RESET}")
            continue
        return value


def prompt_int(text, default=None, min_val=None, max_val=None):
    while True:
        value = prompt(text, default=str(default) if default is not None else None)
        try:
            num = int(value)
            if min_val is not None and num < min_val:
                print(f"{RED}  Minimum value is {min_val}.{RESET}")
                continue
            if max_val is not None and num > max_val:
                print(f"{RED}  Maximum value is {max_val}.{RESET}")
                continue
            return num
        except ValueError:
            print(f"{RED}  Please enter a valid number.{RESET}")


def prompt_list(text, default=None):
    value = prompt(text, default=default)
    return [item.strip() for item in value.split(",") if item.strip()]


def prompt_choice(text, choices, default=None):
    choices_str = "/".join(choices)
    while True:
        value = prompt(f"{text} ({choices_str})", default=default)
        if value in choices:
            return value
        print(f"{RED}  Please choose one of: {choices_str}{RESET}")


def generate_password(length=16):
    chars = string.ascii_letters + string.digits
    return "".join(secrets.choice(chars) for _ in range(length))


def detect_server_ip():
    try:
        result = subprocess.run(
            ["hostname", "-I"], capture_output=True, text=True, timeout=5
        )
        ips = result.stdout.strip().split()
        if ips:
            return ips[0]
    except Exception:
        pass
    return ""


def load_existing_config():
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH) as f:
                return json.load(f)
        except Exception:
            pass
    return None


def run_setup():
    print_header()

    existing = load_existing_config()
    if existing:
        print(f"{YELLOW}Existing config.json found. Values shown as defaults.{RESET}\n")

    server_ip = detect_server_ip()

    # --- Section 1: DNS & Domain ---
    print(f"\n{CYAN}{BOLD}--- DNS & Domain Configuration ---{RESET}")
    print(f"{YELLOW}These must match your Cloudflare NS record setup.{RESET}\n")

    recv_domain = prompt(
        "Receive domain (e.g. tunnel.yourdomain.com)",
        default=existing.get("recv_domain") if existing else None,
    )

    send_domain = prompt(
        "Send domain (e.g. tunnel.yourdomain.com)",
        default=existing.get("send_domain", recv_domain) if existing else recv_domain,
    )

    dns_ips_str = prompt(
        "DNS server IPs (comma-separated, e.g. 8.8.8.8,1.1.1.1)",
        default=",".join(existing["dns_ips"]) if existing and existing.get("dns_ips") else "8.8.8.8,1.1.1.1",
    )
    dns_ips = [ip.strip() for ip in dns_ips_str.split(",") if ip.strip()]

    # --- Section 2: Network Interfaces ---
    print(f"\n{CYAN}{BOLD}--- Network Interfaces ---{RESET}")

    receive_interface_ip = prompt(
        "Receive interface IP (0.0.0.0 = all interfaces)",
        default=existing.get("receive_interface_ip", "0.0.0.0") if existing else "0.0.0.0",
    )

    receive_port = prompt_int(
        "Receive port (DNS port)",
        default=existing.get("receive_port", 53) if existing else 53,
        min_val=1,
        max_val=65535,
    )

    send_interface_ip = prompt(
        "Send interface IP (usually 0.0.0.0)",
        default=existing.get("send_interface_ip", "0.0.0.0") if existing else "0.0.0.0",
    )

    # --- Section 3: Backend (where decoded traffic goes) ---
    print(f"\n{CYAN}{BOLD}--- Backend Configuration ---{RESET}")
    print(f"{YELLOW}Where should decoded tunnel traffic be forwarded to?{RESET}\n")

    h_out_address = prompt(
        "Backend address (e.g. 127.0.0.1:8080 for v2ray, or leave empty for dynamic)",
        default=existing.get("h_out_address", "") if existing else "",
        required=False,
    )

    h_in_address = prompt(
        "Inbound listen address (local UDP socket for apps to send data into the tunnel)",
        default=existing.get("h_in_address", "127.0.0.1:10443") if existing else "127.0.0.1:10443",
    )

    # --- Section 4: Security ---
    print(f"\n{CYAN}{BOLD}--- Security ---{RESET}")

    default_pass = existing.get("chksum_pass", "") if existing else ""
    if not default_pass:
        default_pass = generate_password()
        print(f"{YELLOW}Auto-generated checksum password: {GREEN}{default_pass}{RESET}")

    chksum_pass = prompt(
        "Checksum password (shared secret between client & server)",
        default=default_pass,
    )

    # --- Section 5: Advanced ---
    print(f"\n{CYAN}{BOLD}--- Advanced Settings ---{RESET}")
    print(f"{YELLOW}Press Enter to accept defaults for most of these.{RESET}\n")

    max_domain_len = prompt_int(
        "Max domain length",
        default=existing.get("max_domain_len", 99) if existing else 99,
        min_val=20,
        max_val=253,
    )

    max_sub_len = prompt_int(
        "Max subdomain label length",
        default=existing.get("max_sub_len", 63) if existing else 63,
        min_val=10,
        max_val=63,
    )

    retries = prompt_int(
        "Retries (0 = no retries)",
        default=existing.get("retries", 0) if existing else 0,
        min_val=0,
        max_val=10,
    )

    query_type_map = {"A": 1, "AAAA": 28, "CNAME": 5, "TXT": 16}
    print(f"  Query type options: A=1, AAAA=28, CNAME=5, TXT=16")

    send_query_type_int = prompt_int(
        "Send query type (integer)",
        default=existing.get("send_query_type_int", 1) if existing else 1,
    )

    recv_query_type_int = prompt_int(
        "Receive query type (integer)",
        default=existing.get("recv_query_type_int", 1) if existing else 1,
    )

    send_sock_numbers = prompt_int(
        "Number of send sockets",
        default=existing.get("send_sock_numbers", 8192) if existing else 8192,
        min_val=1,
        max_val=32768,
    )

    assemble_time = prompt_int(
        "Assemble timeout (seconds)",
        default=int(existing.get("assemble_time", 3)) if existing else 3,
        min_val=1,
        max_val=30,
    )

    # --- Build config ---
    config = {
        "dns_ips": dns_ips,
        "send_interface_ip": send_interface_ip,
        "receive_interface_ip": receive_interface_ip,
        "receive_port": receive_port,
        "send_domain": send_domain,
        "recv_domain": recv_domain,
        "h_in_address": h_in_address,
        "h_out_address": h_out_address,
        "max_domain_len": max_domain_len,
        "max_sub_len": max_sub_len,
        "retries": retries,
        "send_query_type_int": send_query_type_int,
        "recv_query_type_int": recv_query_type_int,
        "chksum_pass": chksum_pass,
        "send_sock_numbers": send_sock_numbers,
        "assemble_time": assemble_time,
    }

    # --- Review ---
    print(f"\n{CYAN}{BOLD}--- Configuration Summary ---{RESET}")
    print(json.dumps(config, indent=2))

    confirm = prompt_choice("\nSave this configuration?", ["yes", "no"], default="yes")
    if confirm != "yes":
        print(f"{RED}Setup cancelled.{RESET}")
        sys.exit(1)

    with open(CONFIG_PATH, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")

    print(f"\n{GREEN}{BOLD}config.json saved to: {CONFIG_PATH}{RESET}")

    # --- Print client config hint ---
    print(f"\n{CYAN}{BOLD}--- Client Configuration ---{RESET}")
    print(f"{YELLOW}Use these values in your client's config.json:{RESET}\n")

    client_config = {
        "dns_ips": ["8.8.8.8", "1.1.1.1"],
        "send_interface_ip": "0.0.0.0",
        "receive_interface_ip": "0.0.0.0",
        "receive_port": 5353,
        "send_domain": recv_domain,
        "recv_domain": send_domain,
        "h_in_address": "127.0.0.1:10443",
        "h_out_address": "",
        "max_domain_len": max_domain_len,
        "max_sub_len": max_sub_len,
        "retries": retries,
        "send_query_type_int": recv_query_type_int,
        "recv_query_type_int": send_query_type_int,
        "chksum_pass": chksum_pass,
        "send_sock_numbers": send_sock_numbers,
        "assemble_time": assemble_time,
    }
    print(json.dumps(client_config, indent=2))

    print(f"\n{GREEN}{BOLD}Setup complete!{RESET}")
    print(f"  Start the tunnel:  {CYAN}sudo qq-tunnel start{RESET}")
    print(f"  Check status:      {CYAN}sudo qq-tunnel status{RESET}")
    print(f"  View logs:         {CYAN}sudo qq-tunnel logs{RESET}")
    print(f"  Reconfigure:       {CYAN}sudo qq-tunnel setup{RESET}")


if __name__ == "__main__":
    run_setup()
