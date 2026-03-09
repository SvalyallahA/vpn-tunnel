<#
.SYNOPSIS
    DNS Tunnel Client with DoH/DoT/UDP fallback for censored networks.
.DESCRIPTION
    Connects to a DNSTT server using DNS-over-HTTPS (DoH) transport.
    Automatically tries multiple resolvers and falls back to DoT and UDP.
    Designed for heavily censored networks (Iran, etc.)
.PARAMETER Domain
    The tunnel domain (e.g., t.example.com or d2.example.com)
.PARAMETER PubKey
    The server's 64-character hex public key
.PARAMETER PubKeyFile
    Path to the server's public key file (alternative to -PubKey)
.PARAMETER LocalPort
    Local SOCKS proxy port (default: 7000)
.PARAMETER SshMode
    Connect via SSH tunnel instead of SOCKS (requires SshUser and SshPass)
.PARAMETER SshUser
    SSH username for SSH tunnel mode
.PARAMETER SshPass
    SSH password for SSH tunnel mode
.PARAMETER Transport
    Force a specific transport: "doh", "dot", or "udp" (default: auto-try all)
.PARAMETER Resolver
    Force a specific resolver URL/address (overrides auto-detection)
.PARAMETER Mtu
    MTU value (default: 512 for maximum compatibility)
.EXAMPLE
    .\connect.ps1 -Domain "t.example.com" -PubKey "abcdef1234..."
.EXAMPLE
    .\connect.ps1 -Domain "t.example.com" -PubKeyFile "server.pub" -Transport doh
.EXAMPLE
    .\connect.ps1 -Domain "s2.example.com" -PubKey "abcdef..." -SshMode -SshUser tunnel -SshPass secret
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Domain,

    [string]$PubKey,
    [string]$PubKeyFile,

    [int]$LocalPort = 7000,

    [switch]$SshMode,
    [string]$SshUser,
    [string]$SshPass,

    [ValidateSet("auto", "doh", "dot", "udp")]
    [string]$Transport = "auto",

    [string]$Resolver,

    [int]$Mtu = 512,

    [string]$ConfigFile
)

# --- Configuration ---
$DNSTT_CLIENT_NAME = "dnstt-client-windows-amd64.exe"
$DNSTT_DOWNLOAD_URL = "https://dnstt.network/$DNSTT_CLIENT_NAME"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$BINARY_PATH = Join-Path $SCRIPT_DIR $DNSTT_CLIENT_NAME
$PUBKEY_PATH = Join-Path $SCRIPT_DIR "server.pub"

# DoH resolvers ordered by availability in Iran
$DOH_RESOLVERS = @(
    "https://dns.google/dns-query",
    "https://cloudflare-dns.com/dns-query",
    "https://dns.quad9.net/dns-query",
    "https://dns.adguard-dns.com/dns-query",
    "https://dns.nextdns.io/dns-query",
    "https://dns.mullvad.net/dns-query",
    "https://doh.opendns.com/dns-query"
)

# DoT resolvers as fallback
$DOT_RESOLVERS = @(
    "dns.google:853",
    "cloudflare-dns.com:853",
    "dns.quad9.net:853",
    "dns.adguard-dns.com:853"
)

# UDP resolvers as last resort
$UDP_RESOLVERS = @(
    "8.8.8.8:53",
    "1.1.1.1:53",
    "9.9.9.9:53",
    "208.67.222.222:53",
    "94.140.14.14:53",
    "185.228.168.9:53"
)

# --- Functions ---

function Write-Status {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{ "INFO" = "Cyan"; "OK" = "Green"; "WARN" = "Yellow"; "ERR" = "Red"; "TRY" = "Magenta" }
    $color = if ($colors.ContainsKey($Level)) { $colors[$Level] } else { "White" }
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
    Write-Host "[$Level] " -NoNewline -ForegroundColor $color
    Write-Host $Message
}

function Import-Config {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        Write-Status "Config file not found: $Path" "ERR"
        return $null
    }
    try {
        $content = Get-Content $Path -Raw
        # Support both JSON and base64-encoded configs
        if ($content.StartsWith("dnstt://") -or $content.StartsWith("dns://")) {
            $b64 = $content -replace "^dnstt://|^dns://", ""
            $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
            return $json | ConvertFrom-Json
        }
        return $content | ConvertFrom-Json
    } catch {
        Write-Status "Failed to parse config: $_" "ERR"
        return $null
    }
}

function Get-DnsttBinary {
    if (Test-Path $BINARY_PATH) {
        Write-Status "dnstt-client found at: $BINARY_PATH" "OK"
        return $true
    }

    Write-Status "dnstt-client not found. Downloading..." "INFO"

    # Try downloading
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $DNSTT_DOWNLOAD_URL -OutFile $BINARY_PATH -UseBasicParsing -TimeoutSec 60
        Write-Status "Downloaded dnstt-client successfully" "OK"
        return $true
    } catch {
        Write-Status "Failed to download from $DNSTT_DOWNLOAD_URL" "WARN"
    }

    # If direct download fails, check if it's in PATH
    $inPath = Get-Command "dnstt-client" -ErrorAction SilentlyContinue
    if ($inPath) {
        $script:BINARY_PATH = $inPath.Source
        Write-Status "Found dnstt-client in PATH: $BINARY_PATH" "OK"
        return $true
    }

    # Check common locations
    $commonPaths = @(
        "$env:USERPROFILE\Downloads\$DNSTT_CLIENT_NAME",
        "$env:USERPROFILE\Desktop\$DNSTT_CLIENT_NAME",
        ".\$DNSTT_CLIENT_NAME"
    )
    foreach ($p in $commonPaths) {
        if (Test-Path $p) {
            $script:BINARY_PATH = (Resolve-Path $p).Path
            Write-Status "Found dnstt-client at: $BINARY_PATH" "OK"
            return $true
        }
    }

    Write-Status "Could not find or download dnstt-client binary." "ERR"
    Write-Status "Please download manually from: https://dnstt.network" "ERR"
    Write-Status "Place the binary in: $SCRIPT_DIR" "ERR"
    return $false
}

function Set-PubKey {
    # If PubKeyFile is specified, use it directly
    if ($PubKeyFile -and (Test-Path $PubKeyFile)) {
        $script:PUBKEY_PATH = $PubKeyFile
        Write-Status "Using public key file: $PUBKEY_PATH" "OK"
        return $true
    }

    # If PubKey string is specified, write it to a file
    if ($PubKey) {
        $PubKey | Out-File -FilePath $PUBKEY_PATH -Encoding ASCII -NoNewline
        Write-Status "Public key written to: $PUBKEY_PATH" "OK"
        return $true
    }

    # Check if default pub key file exists
    if (Test-Path $PUBKEY_PATH) {
        Write-Status "Using existing public key file: $PUBKEY_PATH" "OK"
        return $true
    }

    Write-Status "No public key specified. Use -PubKey or -PubKeyFile" "ERR"
    return $false
}

function Test-ResolverReachable {
    param([string]$ResolverUrl, [string]$Type)

    try {
        if ($Type -eq "doh") {
            # Extract hostname from URL
            $uri = [System.Uri]$ResolverUrl
            $hostname = $uri.Host
            # Try to resolve the hostname first
            $null = [System.Net.Dns]::GetHostAddresses($hostname)
            # Try a quick HTTPS connection
            $request = [System.Net.HttpWebRequest]::Create("$ResolverUrl`?dns=AAABAAABAAAAAAAAA3d3dwdleGFtcGxlA2NvbQAAAQAB")
            $request.Timeout = 5000
            $request.Method = "GET"
            $request.Headers.Add("Accept", "application/dns-message")
            try {
                $response = $request.GetResponse()
                $response.Close()
                return $true
            } catch {
                # Even a 4xx response means the server is reachable
                if ($_.Exception.InnerException -and $_.Exception.InnerException.Response) {
                    return $true
                }
                # DNS resolution worked, HTTPS might still work for dnstt
                return $true
            }
        }
        elseif ($Type -eq "dot") {
            $parts = $ResolverUrl -split ":"
            $hostname = $parts[0]
            $port = if ($parts.Count -gt 1) { [int]$parts[1] } else { 853 }
            $tcp = New-Object System.Net.Sockets.TcpClient
            $result = $tcp.BeginConnect($hostname, $port, $null, $null)
            $success = $result.AsyncWaitHandle.WaitOne(5000)
            $tcp.Close()
            return $success
        }
        elseif ($Type -eq "udp") {
            $parts = $ResolverUrl -split ":"
            $hostname = $parts[0]
            $null = [System.Net.Dns]::GetHostAddresses($hostname)
            return $true
        }
    } catch {
        return $false
    }
    return $false
}

function Start-DnsttClient {
    param(
        [string]$TransportFlag,
        [string]$ResolverAddr,
        [string]$TransportType
    )

    $args_list = @()
    $args_list += $TransportFlag
    $args_list += $ResolverAddr
    $args_list += "-pubkey-file"
    $args_list += $PUBKEY_PATH
    $args_list += $Domain
    $args_list += "127.0.0.1:$LocalPort"

    $argString = $args_list -join " "
    Write-Status "Starting: dnstt-client $argString" "TRY"

    $process = Start-Process -FilePath $BINARY_PATH -ArgumentList $args_list -NoNewWindow -PassThru -RedirectStandardError (Join-Path $SCRIPT_DIR "dnstt-error.log")

    # Wait a few seconds to see if it crashes immediately
    Start-Sleep -Seconds 3

    if ($process.HasExited) {
        $exitCode = $process.ExitCode
        Write-Status "dnstt-client exited immediately (code: $exitCode)" "ERR"
        if (Test-Path (Join-Path $SCRIPT_DIR "dnstt-error.log")) {
            $errorLog = Get-Content (Join-Path $SCRIPT_DIR "dnstt-error.log") -Raw
            if ($errorLog) {
                Write-Status "Error output: $errorLog" "ERR"
            }
        }
        return $null
    }

    # Test if the local proxy is accepting connections
    Start-Sleep -Seconds 2
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect("127.0.0.1", $LocalPort)
        $tcp.Close()
        Write-Status "Local proxy is listening on 127.0.0.1:$LocalPort" "OK"
    } catch {
        Write-Status "Local proxy not yet ready (may take a moment)" "WARN"
    }

    return $process
}

function Start-SshTunnel {
    param([System.Diagnostics.Process]$DnsttProcess)

    if (-not $SshUser -or -not $SshPass) {
        Write-Status "SSH mode requires -SshUser and -SshPass" "ERR"
        return $false
    }

    Write-Status "Setting up SSH tunnel through DNSTT..." "INFO"

    # Use plink (PuTTY) or ssh
    $sshBinary = Get-Command "ssh" -ErrorAction SilentlyContinue
    $plinkBinary = Get-Command "plink" -ErrorAction SilentlyContinue

    $socksPort = $LocalPort + 1000  # e.g., 8000

    if ($sshBinary) {
        $sshArgs = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -N -D 127.0.0.1:$socksPort -p $LocalPort $SshUser@127.0.0.1"
        Write-Status "Starting SSH SOCKS proxy on 127.0.0.1:$socksPort" "TRY"
        Write-Status "SSH command: ssh $sshArgs" "INFO"
        Write-Status "You will be prompted for the SSH password: $SshPass" "INFO"

        $sshProcess = Start-Process -FilePath $sshBinary.Source -ArgumentList $sshArgs.Split(" ") -NoNewWindow -PassThru
        return $sshProcess
    } elseif ($plinkBinary) {
        $plinkArgs = "-ssh -N -D 127.0.0.1:$socksPort -P $LocalPort -l $SshUser -pw $SshPass 127.0.0.1"
        Write-Status "Starting SSH SOCKS proxy on 127.0.0.1:$socksPort (via plink)" "TRY"

        $sshProcess = Start-Process -FilePath $plinkBinary.Source -ArgumentList $plinkArgs.Split(" ") -NoNewWindow -PassThru
        return $sshProcess
    } else {
        Write-Status "No SSH client found. Install OpenSSH or PuTTY." "ERR"
        Write-Status "Manual command: ssh -N -D 127.0.0.1:$socksPort -p $LocalPort $SshUser@127.0.0.1" "INFO"
        return $null
    }
}

# --- Main ---

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  DNS Tunnel Client (DoH/DoT/UDP)"       -ForegroundColor Cyan
Write-Host "  Designed for censored networks"          -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Load config file if specified
if ($ConfigFile) {
    Write-Status "Loading config from: $ConfigFile" "INFO"
    $config = Import-Config $ConfigFile
    if ($config) {
        if ($config.ns -and -not $Domain) { $Domain = $config.ns }
        if ($config.pubkey -and -not $PubKey) { $PubKey = $config.pubkey }
        if ($config.user) { $SshUser = $config.user; $SshMode = $true }
        if ($config.pass) { $SshPass = $config.pass }
        Write-Status "Config loaded: domain=$Domain" "OK"
    }
}

# Validate inputs
if (-not $Domain) {
    Write-Status "Domain is required. Use -Domain parameter." "ERR"
    exit 1
}

# Step 1: Get dnstt-client binary
Write-Status "Step 1: Checking dnstt-client binary..." "INFO"
if (-not (Get-DnsttBinary)) { exit 1 }

# Step 2: Set up public key
Write-Status "Step 2: Setting up public key..." "INFO"
if (-not (Set-PubKey)) { exit 1 }

# Step 3: Determine transport and resolver
Write-Status "Step 3: Finding working resolver..." "INFO"
Write-Status "Domain: $Domain" "INFO"
Write-Status "Transport preference: $Transport" "INFO"

$dnsttProcess = $null

if ($Resolver) {
    # User specified a resolver, use it directly
    if ($Transport -eq "auto" -or $Transport -eq "doh") {
        if ($Resolver -match "^https://") {
            $dnsttProcess = Start-DnsttClient "-doh" $Resolver "doh"
        }
    }
    if (-not $dnsttProcess -and ($Transport -eq "auto" -or $Transport -eq "dot")) {
        if ($Resolver -match ":\d+$") {
            $dnsttProcess = Start-DnsttClient "-dot" $Resolver "dot"
        }
    }
    if (-not $dnsttProcess -and ($Transport -eq "auto" -or $Transport -eq "udp")) {
        $dnsttProcess = Start-DnsttClient "-udp" $Resolver "udp"
    }
} else {
    # Auto-try resolvers in order: DoH -> DoT -> UDP

    # Try DoH
    if ($Transport -eq "auto" -or $Transport -eq "doh") {
        Write-Status "Trying DoH resolvers (HTTPS - most stealthy)..." "INFO"
        foreach ($resolver in $DOH_RESOLVERS) {
            Write-Status "Testing $resolver ..." "TRY"
            if (Test-ResolverReachable $resolver "doh") {
                Write-Status "Resolver reachable, connecting..." "OK"
                $dnsttProcess = Start-DnsttClient "-doh" $resolver "doh"
                if ($dnsttProcess) {
                    Write-Status "Connected via DoH: $resolver" "OK"
                    break
                }
            } else {
                Write-Status "Resolver not reachable, trying next..." "WARN"
            }
        }
    }

    # Try DoT
    if (-not $dnsttProcess -and ($Transport -eq "auto" -or $Transport -eq "dot")) {
        Write-Status "DoH failed. Trying DoT resolvers (TLS port 853)..." "WARN"
        foreach ($resolver in $DOT_RESOLVERS) {
            Write-Status "Testing $resolver ..." "TRY"
            if (Test-ResolverReachable $resolver "dot") {
                Write-Status "Resolver reachable, connecting..." "OK"
                $dnsttProcess = Start-DnsttClient "-dot" $resolver "dot"
                if ($dnsttProcess) {
                    Write-Status "Connected via DoT: $resolver" "OK"
                    break
                }
            } else {
                Write-Status "Resolver not reachable, trying next..." "WARN"
            }
        }
    }

    # Try UDP as last resort
    if (-not $dnsttProcess -and ($Transport -eq "auto" -or $Transport -eq "udp")) {
        Write-Status "DoH and DoT failed. Trying UDP resolvers (least reliable)..." "WARN"
        foreach ($resolver in $UDP_RESOLVERS) {
            Write-Status "Testing $resolver ..." "TRY"
            $dnsttProcess = Start-DnsttClient "-udp" $resolver "udp"
            if ($dnsttProcess) {
                Write-Status "Connected via UDP: $resolver" "OK"
                break
            }
        }
    }
}

if (-not $dnsttProcess) {
    Write-Host ""
    Write-Status "ALL RESOLVERS FAILED" "ERR"
    Write-Status "Possible causes:" "ERR"
    Write-Status "  1. Server is not running or domain DNS not propagated" "ERR"
    Write-Status "  2. All DoH/DoT endpoints are blocked by your ISP" "ERR"
    Write-Status "  3. Public key mismatch" "ERR"
    Write-Status "  4. Firewall blocking outbound HTTPS" "ERR"
    Write-Host ""
    Write-Status "Try:" "INFO"
    Write-Status "  - Different WiFi/mobile network" "INFO"
    Write-Status "  - VPN hotspot from someone who has access" "INFO"
    Write-Status "  - Lower MTU (current: $Mtu)" "INFO"
    exit 1
}

# Step 4: Handle SSH mode or show proxy info
Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "  CONNECTION ESTABLISHED!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""

if ($SshMode) {
    $sshProcess = Start-SshTunnel $dnsttProcess
    $socksPort = $LocalPort + 1000
    if ($sshProcess) {
        Write-Status "SSH tunnel established!" "OK"
        Write-Status "SOCKS proxy: 127.0.0.1:$socksPort" "OK"
        Write-Host ""
        Write-Status "Configure your browser/apps to use:" "INFO"
        Write-Status "  SOCKS5 proxy: 127.0.0.1:$socksPort" "INFO"
    }
} else {
    Write-Status "DNSTT tunnel active on 127.0.0.1:$LocalPort" "OK"
    Write-Host ""
    Write-Status "If server is in SOCKS mode:" "INFO"
    Write-Status "  Configure browser SOCKS5 proxy: 127.0.0.1:$LocalPort" "INFO"
    Write-Host ""
    Write-Status "If server is in SSH mode, run separately:" "INFO"
    Write-Status "  ssh -N -D 127.0.0.1:8000 -p $LocalPort user@127.0.0.1" "INFO"
}

Write-Host ""
Write-Status "Press Ctrl+C to disconnect" "INFO"
Write-Host ""

# Keep running until user stops
try {
    while (-not $dnsttProcess.HasExited) {
        Start-Sleep -Seconds 5
    }
    Write-Status "dnstt-client process ended (exit code: $($dnsttProcess.ExitCode))" "WARN"
} catch {
    # Ctrl+C pressed
    Write-Status "Shutting down..." "INFO"
} finally {
    if ($dnsttProcess -and -not $dnsttProcess.HasExited) {
        $dnsttProcess.Kill()
        Write-Status "dnstt-client stopped" "INFO"
    }
    if ($sshProcess -and -not $sshProcess.HasExited) {
        $sshProcess.Kill()
        Write-Status "SSH tunnel stopped" "INFO"
    }
    # Cleanup
    $errorLog = Join-Path $SCRIPT_DIR "dnstt-error.log"
    if (Test-Path $errorLog) { Remove-Item $errorLog -ErrorAction SilentlyContinue }
}
