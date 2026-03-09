#!/usr/bin/env bash
#
# DNS Tunnel Client with DoH/DoT/UDP fallback for censored networks
# Usage: ./connect.sh -d t.example.com -k <64-char-hex-pubkey>
#        ./connect.sh -d t.example.com -f server.pub
#        ./connect.sh -d s2.example.com -k <key> --ssh-user tunnel --ssh-pass secret
#        ./connect.sh --config config.json

set -euo pipefail

# --- Defaults ---
DOMAIN=""
PUBKEY=""
PUBKEY_FILE=""
LOCAL_PORT=7000
TRANSPORT="auto"          # auto, doh, dot, udp
RESOLVER=""
MTU=512
SSH_MODE=false
SSH_USER=""
SSH_PASS=""
CONFIG_FILE=""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY_PATH=""
PUBKEY_PATH="$SCRIPT_DIR/server.pub"

# DoH resolvers (ordered by availability in Iran)
DOH_RESOLVERS=(
    "https://dns.google/dns-query"
    "https://cloudflare-dns.com/dns-query"
    "https://dns.quad9.net/dns-query"
    "https://dns.adguard-dns.com/dns-query"
    "https://dns.nextdns.io/dns-query"
    "https://dns.mullvad.net/dns-query"
    "https://doh.opendns.com/dns-query"
)

# DoT resolvers (fallback)
DOT_RESOLVERS=(
    "dns.google:853"
    "cloudflare-dns.com:853"
    "dns.quad9.net:853"
    "dns.adguard-dns.com:853"
)

# UDP resolvers (last resort)
UDP_RESOLVERS=(
    "8.8.8.8:53"
    "1.1.1.1:53"
    "9.9.9.9:53"
    "208.67.222.222:53"
    "94.140.14.14:53"
    "185.228.168.9:53"
)

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# --- Functions ---

log() {
    local level="$1"; shift
    local msg="$*"
    local timestamp
    timestamp=$(date +%H:%M:%S)
    local color="$NC"
    case "$level" in
        INFO) color="$CYAN" ;;
        OK)   color="$GREEN" ;;
        WARN) color="$YELLOW" ;;
        ERR)  color="$RED" ;;
        TRY)  color="$MAGENTA" ;;
    esac
    echo -e "${GRAY}[$timestamp]${NC} ${color}[$level]${NC} $msg"
}

usage() {
    cat << 'EOF'
Usage: ./connect.sh [OPTIONS]

Required:
  -d, --domain DOMAIN       Tunnel domain (e.g., t.example.com)
  -k, --pubkey KEY          Server public key (64-char hex string)
  -f, --pubkey-file FILE    Path to server public key file

Optional:
  -p, --port PORT           Local SOCKS port (default: 7000)
  -t, --transport TYPE      Transport: auto|doh|dot|udp (default: auto)
  -r, --resolver ADDR       Force specific resolver
  -m, --mtu MTU             MTU value (default: 512)
  --ssh                     Enable SSH tunnel mode
  --ssh-user USER           SSH username
  --ssh-pass PASS           SSH password
  --config FILE             Load config from JSON file
  -h, --help                Show this help

Examples:
  ./connect.sh -d t.example.com -k abcdef1234...
  ./connect.sh -d d2.example.com -f server.pub -t doh
  ./connect.sh -d s2.example.com -k KEY --ssh --ssh-user tunnel --ssh-pass secret
  ./connect.sh --config tunnel-config.json
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domain)    DOMAIN="$2"; shift 2 ;;
            -k|--pubkey)    PUBKEY="$2"; shift 2 ;;
            -f|--pubkey-file) PUBKEY_FILE="$2"; shift 2 ;;
            -p|--port)      LOCAL_PORT="$2"; shift 2 ;;
            -t|--transport) TRANSPORT="$2"; shift 2 ;;
            -r|--resolver)  RESOLVER="$2"; shift 2 ;;
            -m|--mtu)       MTU="$2"; shift 2 ;;
            --ssh)          SSH_MODE=true; shift ;;
            --ssh-user)     SSH_USER="$2"; shift 2 ;;
            --ssh-pass)     SSH_PASS="$2"; shift 2 ;;
            --config)       CONFIG_FILE="$2"; shift 2 ;;
            -h|--help)      usage ;;
            *) log ERR "Unknown option: $1"; usage ;;
        esac
    done
}

load_config() {
    if [[ -z "$CONFIG_FILE" ]]; then return; fi
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log ERR "Config file not found: $CONFIG_FILE"
        exit 1
    fi

    local content
    content=$(cat "$CONFIG_FILE")

    # Handle dnstt:// or dns:// URI format
    if echo "$content" | grep -qE '^(dnstt|dns)://'; then
        local b64
        b64=$(echo "$content" | sed 's/^dnstt:\/\///;s/^dns:\/\///')
        content=$(echo "$b64" | base64 -d 2>/dev/null || echo "$b64" | base64 -D 2>/dev/null)
    fi

    # Parse JSON (requires jq or python)
    if command -v jq &>/dev/null; then
        [[ -z "$DOMAIN" ]] && DOMAIN=$(echo "$content" | jq -r '.ns // .domain // empty')
        [[ -z "$PUBKEY" ]] && PUBKEY=$(echo "$content" | jq -r '.pubkey // empty')
        local user pass
        user=$(echo "$content" | jq -r '.user // empty')
        pass=$(echo "$content" | jq -r '.pass // empty')
        if [[ -n "$user" ]]; then SSH_USER="$user"; SSH_MODE=true; fi
        if [[ -n "$pass" ]]; then SSH_PASS="$pass"; fi
    elif command -v python3 &>/dev/null; then
        [[ -z "$DOMAIN" ]] && DOMAIN=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('ns',d.get('domain','')))" <<< "$content")
        [[ -z "$PUBKEY" ]] && PUBKEY=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pubkey',''))" <<< "$content")
        local user pass
        user=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('user',''))" <<< "$content")
        pass=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pass',''))" <<< "$content")
        if [[ -n "$user" ]]; then SSH_USER="$user"; SSH_MODE=true; fi
        if [[ -n "$pass" ]]; then SSH_PASS="$pass"; fi
    else
        log ERR "Need jq or python3 to parse config files"
        exit 1
    fi

    log OK "Config loaded: domain=$DOMAIN"
}

find_binary() {
    # Check script directory
    local os_name arch_name binary_name
    os_name=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch_name=$(uname -m)

    case "$os_name" in
        linux)  os_name="linux" ;;
        darwin) os_name="darwin" ;;
        *)      os_name="linux" ;;
    esac

    case "$arch_name" in
        x86_64|amd64)   arch_name="amd64" ;;
        aarch64|arm64)  arch_name="arm64" ;;
        armv7l|armhf)   arch_name="arm" ;;
        *)              arch_name="amd64" ;;
    esac

    binary_name="dnstt-client-${os_name}-${arch_name}"

    # Search order
    local search_paths=(
        "$SCRIPT_DIR/$binary_name"
        "$SCRIPT_DIR/dnstt-client"
        "./$binary_name"
        "./dnstt-client"
        "$HOME/Downloads/$binary_name"
        "$HOME/Desktop/$binary_name"
    )

    for p in "${search_paths[@]}"; do
        if [[ -f "$p" ]]; then
            BINARY_PATH="$p"
            chmod +x "$BINARY_PATH"
            log OK "Found dnstt-client: $BINARY_PATH"
            return 0
        fi
    done

    # Check PATH
    if command -v dnstt-client &>/dev/null; then
        BINARY_PATH=$(command -v dnstt-client)
        log OK "Found dnstt-client in PATH: $BINARY_PATH"
        return 0
    fi

    # Try downloading
    local url="https://dnstt.network/$binary_name"
    log INFO "Downloading dnstt-client from $url ..."
    BINARY_PATH="$SCRIPT_DIR/$binary_name"

    if curl -fsSL --connect-timeout 30 "$url" -o "$BINARY_PATH" 2>/dev/null; then
        chmod +x "$BINARY_PATH"
        log OK "Downloaded: $BINARY_PATH"
        return 0
    fi

    log ERR "Could not find or download dnstt-client"
    log ERR "Download manually from: https://dnstt.network"
    log ERR "Place in: $SCRIPT_DIR"
    return 1
}

setup_pubkey() {
    if [[ -n "$PUBKEY_FILE" && -f "$PUBKEY_FILE" ]]; then
        PUBKEY_PATH="$PUBKEY_FILE"
        log OK "Using public key file: $PUBKEY_PATH"
        return 0
    fi

    if [[ -n "$PUBKEY" ]]; then
        echo -n "$PUBKEY" > "$PUBKEY_PATH"
        log OK "Public key written to: $PUBKEY_PATH"
        return 0
    fi

    if [[ -f "$PUBKEY_PATH" ]]; then
        log OK "Using existing public key: $PUBKEY_PATH"
        return 0
    fi

    log ERR "No public key specified. Use -k or -f"
    return 1
}

test_resolver() {
    local resolver="$1"
    local type="$2"

    case "$type" in
        doh)
            local host
            host=$(echo "$resolver" | sed 's|https://||;s|/.*||')
            # Try DNS resolution of the DoH host
            if ! host "$host" &>/dev/null 2>&1 && ! nslookup "$host" &>/dev/null 2>&1; then
                # Try with getent as fallback
                if ! getent hosts "$host" &>/dev/null 2>&1; then
                    return 1
                fi
            fi
            # Try HTTPS connection
            if curl -fsSL --connect-timeout 5 -o /dev/null "$resolver?dns=AAABAAABAAAAAAAAA3d3dwdleGFtcGxlA2NvbQAAAQAB" -H "Accept: application/dns-message" 2>/dev/null; then
                return 0
            fi
            # Even if curl fails, DNS resolution worked — dnstt might still work
            return 0
            ;;
        dot)
            local host port
            host=$(echo "$resolver" | cut -d: -f1)
            port=$(echo "$resolver" | cut -d: -f2)
            if timeout 5 bash -c "echo | openssl s_client -connect $host:$port 2>/dev/null" | grep -q "CONNECTED"; then
                return 0
            fi
            # Fallback: try TCP connection
            if timeout 5 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
                return 0
            fi
            return 1
            ;;
        udp)
            # Can't easily test UDP, assume reachable
            return 0
            ;;
    esac
    return 1
}

DNSTT_PID=""
SSH_PID=""

start_dnstt() {
    local flag="$1"
    local resolver="$2"
    local type="$3"

    log TRY "Starting: $BINARY_PATH $flag $resolver -pubkey-file $PUBKEY_PATH $DOMAIN 127.0.0.1:$LOCAL_PORT"

    "$BINARY_PATH" "$flag" "$resolver" -pubkey-file "$PUBKEY_PATH" "$DOMAIN" "127.0.0.1:$LOCAL_PORT" &
    DNSTT_PID=$!

    # Wait and check if process is alive
    sleep 3

    if ! kill -0 "$DNSTT_PID" 2>/dev/null; then
        log ERR "dnstt-client died immediately"
        DNSTT_PID=""
        return 1
    fi

    # Check if local port is listening
    sleep 2
    if ss -tln 2>/dev/null | grep -q ":$LOCAL_PORT " || netstat -tln 2>/dev/null | grep -q ":$LOCAL_PORT "; then
        log OK "Local proxy listening on 127.0.0.1:$LOCAL_PORT"
    else
        log WARN "Local proxy not yet ready (may take a moment)"
    fi

    return 0
}

start_ssh_tunnel() {
    if [[ -z "$SSH_USER" || -z "$SSH_PASS" ]]; then
        log ERR "SSH mode requires --ssh-user and --ssh-pass"
        return 1
    fi

    local socks_port=$((LOCAL_PORT + 1000))
    log INFO "Setting up SSH SOCKS proxy on 127.0.0.1:$socks_port"

    if command -v sshpass &>/dev/null; then
        sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -N -D "127.0.0.1:$socks_port" -p "$LOCAL_PORT" "$SSH_USER@127.0.0.1" &
        SSH_PID=$!
        sleep 2
        if kill -0 "$SSH_PID" 2>/dev/null; then
            log OK "SSH tunnel established! SOCKS proxy: 127.0.0.1:$socks_port"
            return 0
        fi
    fi

    log WARN "sshpass not installed. Connect manually:"
    log INFO "  ssh -N -D 127.0.0.1:$socks_port -p $LOCAL_PORT $SSH_USER@127.0.0.1"
    log INFO "  Password: $SSH_PASS"
    return 0
}

cleanup() {
    echo ""
    log INFO "Shutting down..."
    [[ -n "$SSH_PID" ]] && kill "$SSH_PID" 2>/dev/null && log INFO "SSH tunnel stopped"
    [[ -n "$DNSTT_PID" ]] && kill "$DNSTT_PID" 2>/dev/null && log INFO "dnstt-client stopped"
    exit 0
}

# --- Main ---

trap cleanup INT TERM

parse_args "$@"
load_config

echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}  DNS Tunnel Client (DoH/DoT/UDP)${NC}"
echo -e "${CYAN}  Designed for censored networks${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

# Validate
if [[ -z "$DOMAIN" ]]; then
    log ERR "Domain is required. Use -d <domain>"
    usage
fi

# Step 1: Find binary
log INFO "Step 1: Checking dnstt-client binary..."
find_binary || exit 1

# Step 2: Setup pubkey
log INFO "Step 2: Setting up public key..."
setup_pubkey || exit 1

# Step 3: Find working resolver
log INFO "Step 3: Finding working resolver..."
log INFO "Domain: $DOMAIN"
log INFO "Transport preference: $TRANSPORT"

connected=false

if [[ -n "$RESOLVER" ]]; then
    # User specified a resolver
    if [[ "$TRANSPORT" == "auto" || "$TRANSPORT" == "doh" ]] && [[ "$RESOLVER" == https://* ]]; then
        start_dnstt "-doh" "$RESOLVER" "doh" && connected=true
    fi
    if ! $connected && [[ "$TRANSPORT" == "auto" || "$TRANSPORT" == "dot" ]] && [[ "$RESOLVER" == *:* ]]; then
        start_dnstt "-dot" "$RESOLVER" "dot" && connected=true
    fi
    if ! $connected && [[ "$TRANSPORT" == "auto" || "$TRANSPORT" == "udp" ]]; then
        start_dnstt "-udp" "$RESOLVER" "udp" && connected=true
    fi
else
    # Auto-try: DoH -> DoT -> UDP

    if [[ "$TRANSPORT" == "auto" || "$TRANSPORT" == "doh" ]]; then
        log INFO "Trying DoH resolvers (HTTPS - most stealthy)..."
        for resolver in "${DOH_RESOLVERS[@]}"; do
            log TRY "Testing $resolver ..."
            if test_resolver "$resolver" "doh"; then
                log OK "Resolver reachable, connecting..."
                if start_dnstt "-doh" "$resolver" "doh"; then
                    log OK "Connected via DoH: $resolver"
                    connected=true
                    break
                fi
            else
                log WARN "Resolver not reachable, trying next..."
            fi
        done
    fi

    if ! $connected && [[ "$TRANSPORT" == "auto" || "$TRANSPORT" == "dot" ]]; then
        log WARN "DoH failed. Trying DoT resolvers (TLS port 853)..."
        for resolver in "${DOT_RESOLVERS[@]}"; do
            log TRY "Testing $resolver ..."
            if test_resolver "$resolver" "dot"; then
                log OK "Resolver reachable, connecting..."
                if start_dnstt "-dot" "$resolver" "dot"; then
                    log OK "Connected via DoT: $resolver"
                    connected=true
                    break
                fi
            else
                log WARN "Resolver not reachable, trying next..."
            fi
        done
    fi

    if ! $connected && [[ "$TRANSPORT" == "auto" || "$TRANSPORT" == "udp" ]]; then
        log WARN "DoH and DoT failed. Trying UDP resolvers (least reliable)..."
        for resolver in "${UDP_RESOLVERS[@]}"; do
            log TRY "Trying $resolver ..."
            if start_dnstt "-udp" "$resolver" "udp"; then
                log OK "Connected via UDP: $resolver"
                connected=true
                break
            fi
        done
    fi
fi

if ! $connected; then
    echo ""
    log ERR "ALL RESOLVERS FAILED"
    log ERR "Possible causes:"
    log ERR "  1. Server is not running or domain DNS not propagated"
    log ERR "  2. All DoH/DoT endpoints are blocked by your ISP"
    log ERR "  3. Public key mismatch"
    log ERR "  4. Firewall blocking outbound HTTPS"
    echo ""
    log INFO "Try:"
    log INFO "  - Different WiFi/mobile network"
    log INFO "  - Lower MTU (current: $MTU)"
    log INFO "  - Manually: $BINARY_PATH -doh https://dns.google/dns-query -pubkey-file $PUBKEY_PATH $DOMAIN 127.0.0.1:$LOCAL_PORT"
    exit 1
fi

# Step 4: Connected!
echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  CONNECTION ESTABLISHED!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""

if $SSH_MODE; then
    start_ssh_tunnel
    socks_port=$((LOCAL_PORT + 1000))
    echo ""
    log INFO "Configure your browser/apps to use:"
    log INFO "  SOCKS5 proxy: 127.0.0.1:$socks_port"
else
    log OK "DNSTT tunnel active on 127.0.0.1:$LOCAL_PORT"
    echo ""
    log INFO "If server is in SOCKS mode:"
    log INFO "  Configure browser SOCKS5 proxy: 127.0.0.1:$LOCAL_PORT"
    echo ""
    log INFO "If server is in SSH mode, run separately:"
    log INFO "  ssh -N -D 127.0.0.1:8000 -p $LOCAL_PORT user@127.0.0.1"
fi

echo ""
log INFO "Press Ctrl+C to disconnect"
echo ""

# Keep running
wait "$DNSTT_PID" 2>/dev/null
log WARN "dnstt-client process ended"
cleanup
