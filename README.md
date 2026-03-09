# DNS Tunnel Server — Censorship-Resistant Setup

**Languages:** English | [فارسی](#راهنمای-فارسی)

A complete, managed DNS tunnel server for Ubuntu VPS with **DoH (DNS-over-HTTPS)** transport — the key to bypassing modern DPI-based censorship.

---

## Why Existing Methods Stopped Working

Both `dnstt-deploy` and `dnstm-setup` tunnel traffic via **plain DNS on UDP port 53**.
Iran's censorship has evolved to detect and block this:

| Detection | What the censor does |
|---|---|
| **DPI** | Detects encoded/random subdomains in DNS queries |
| **UDP/53 blocking** | Intercepts or drops DNS to public resolvers |
| **Frequency analysis** | Flags abnormally high DNS query rates |
| **ISP differences** | Each ISP (MCI, Irancell, Shatel, etc.) filters differently |

**This is why it works for you but not your friend** — different ISP, different DPI.

## The Fix: DoH (DNS-over-HTTPS)

Instead of raw DNS on port 53, your tunnel traffic goes inside **normal HTTPS requests** to Google or Cloudflare. The censor sees HTTPS to `dns.google` — indistinguishable from web browsing.

```
Phone/PC  →  HTTPS to dns.google (port 443)  →  Google DoH  →  Your VPS (port 53)  →  Internet
              (looks like normal browsing)
```

| Transport | Client flag | Detectability | Speed |
|---|---|---|---|
| UDP DNS | `-udp 8.8.8.8:53` | HIGH — easily detected | Fast |
| DoT | `-dot dns.google:853` | MEDIUM — port 853 can be blocked | Medium |
| **DoH** | **`-doh https://dns.google/dns-query`** | **LOW — looks like HTTPS** | **Slower but works** |

---

# Step-by-Step Guide

## What You Need

1. **An Ubuntu VPS** (20.04 / 22.04 / 24.04) with root access and a public IP
2. **A domain name** (cheap ones like `.xyz`, `.live` work fine)
3. **Cloudflare account** (free plan) to manage DNS records

## Step 1 — Buy a Domain & Set Up DNS Records

Buy a domain (e.g. `example.com`), then add it to Cloudflare.

In the Cloudflare dashboard, create these DNS records:

| Type | Name | Value | Proxy |
|---|---|---|---|
| **A** | `ns` | `YOUR_SERVER_IP` | **OFF** (grey cloud) |
| **NS** | `t` | `ns.example.com` | — |

> Replace `example.com` with your domain and `YOUR_SERVER_IP` with your VPS IP.
>
> The **A record proxy MUST be OFF** (grey cloud, not orange).
>
> Wait 5–10 minutes for DNS propagation.

## Step 2 — SSH Into Your VPS and Run the Server Script

```bash
# Download the script
curl -fsSL -o dns-tunnel-server.sh https://raw.githubusercontent.com/YOUR_REPO/dns-tunnel-solution/dns-tunnel-server.sh

# Run it
sudo bash dns-tunnel-server.sh
```

Or if you already have the file:

```bash
sudo bash dns-tunnel-server.sh
```

This opens an **interactive menu**:

```
  ╔══════════════════════════════════════════════╗
  ║     DNS Tunnel Server Manager  v1.0.0        ║
  ║     Optimized for censored networks          ║
  ╚══════════════════════════════════════════════╝

  Status: ● NOT INSTALLED

  1)  Install & Setup          ← start here
  2)  Show Status
  3)  Show Configuration       (connection info + share)
  4)  View Logs

  5)  Start Services
  6)  Stop Services
  7)  Restart Services

  8)  Reconfigure              (change MTU, mode, domain...)
  9)  Uninstall

  0)  Exit
```

**Choose 1** to start the setup wizard.

## Step 3 — Follow the Setup Wizard (9 Steps)

The wizard walks you through everything:

| Step | What it does |
|---|---|
| 1. Pre-flight | Checks root, OS, detects server IP and SSH port |
| 2. Domain | Enter your tunnel subdomain (e.g. `t.example.com`) |
| 3. DNS records | Shows which records you need, confirms you created them |
| 4. Tunnel mode | **SOCKS** (no password, simpler) or **SSH** (per-user auth) |
| 5. MTU | Choose 512 for max compatibility in censored networks |
| 6. Install | Downloads dnstt-server, creates system user, frees port 53 |
| 7. Mode setup | Installs Dante SOCKS proxy (SOCKS mode) or configures SSH |
| 8. Start | Creates systemd service, configures iptables, starts tunnel |
| 9. Summary | Shows **all client connection commands ready to copy** |

At the end you get the **public key** and **connection commands** for your friends.

## Step 4 — Connect from Your Phone or PC (Client Side)

Download `dnstt-client` for your platform from [dnstt.network](https://dnstt.network).

Save the server's public key as `server.pub`, then run:

```bash
# RECOMMENDED — DoH via Google (hardest to detect)
dnstt-client -doh https://dns.google/dns-query -pubkey-file server.pub t.example.com 127.0.0.1:7000

# If Google doesn't work, try Cloudflare
dnstt-client -doh https://cloudflare-dns.com/dns-query -pubkey-file server.pub t.example.com 127.0.0.1:7000

# If DoH doesn't work at all, try DoT
dnstt-client -dot dns.google:853 -pubkey-file server.pub t.example.com 127.0.0.1:7000
```

Then set your browser/app SOCKS5 proxy to `127.0.0.1:7000`.

**Windows users** — use the included script for automatic resolver fallback:
```powershell
.\connect.ps1 -Domain "t.example.com" -PubKey "your_64char_hex_key"
```

**Linux/Mac users:**
```bash
./connect.sh -d t.example.com -k your_64char_hex_key
```

## Step 5 — Share With Friends

**Simplest method:** copy the "Quick Share" block from menu option **3) Show Configuration** and send it via any messenger.

**Or** generate a config package:
```bash
python config-generator.py --domain t.example.com --pubkey YOUR_KEY --save
```
This creates a folder with `server.pub`, instructions, and a ready-to-run `.bat` file for Windows.

**Or** edit `quick-connect.bat`:
1. Open it in Notepad
2. Change `DOMAIN=` and `PUBKEY=` to your values
3. Send the `.bat` + `dnstt-client-windows-amd64.exe` to your friend
4. They double-click the `.bat`, pick a resolver, done

---

# Server Management

After setup, run the script again anytime for the management menu:

```bash
sudo bash dns-tunnel-server.sh
```

| Menu | Action |
|---|---|
| **1) Install & Setup** | Re-run the full setup wizard |
| **2) Show Status** | Service status, ports, PID, memory, uptime |
| **3) Show Configuration** | Full connection info + shareable text block |
| **4) View Logs** | Live logs, last 50 lines, Dante logs, or combined |
| **5) Start Services** | Start dnstt-server (and Dante if SOCKS mode) |
| **6) Stop Services** | Stop all tunnel services |
| **7) Restart Services** | Restart everything |
| **8) Reconfigure** | Change MTU, mode, domain, user/pass, or regenerate keys |
| **9) Uninstall** | Remove everything cleanly |

**CLI shortcuts** (no menu):
```bash
sudo bash dns-tunnel-server.sh status
sudo bash dns-tunnel-server.sh logs
sudo bash dns-tunnel-server.sh start
sudo bash dns-tunnel-server.sh stop
sudo bash dns-tunnel-server.sh restart
sudo bash dns-tunnel-server.sh config
```

---

# DoH Resolvers (Ranked for Iran)

| # | Provider | DoH URL | DoT Address |
|---|---|---|---|
| 1 | Google | `https://dns.google/dns-query` | `dns.google:853` |
| 2 | Cloudflare | `https://cloudflare-dns.com/dns-query` | `cloudflare-dns.com:853` |
| 3 | Quad9 | `https://dns.quad9.net/dns-query` | `dns.quad9.net:853` |
| 4 | AdGuard | `https://dns.adguard-dns.com/dns-query` | `dns.adguard-dns.com:853` |
| 5 | NextDNS | `https://dns.nextdns.io/dns-query` | `dns.nextdns.io:853` |
| 6 | Mullvad | `https://dns.mullvad.net/dns-query` | `dns.mullvad.net:853` |

Try different resolvers if one doesn't work — each ISP blocks different ones.

---

# MTU Guide

| MTU | When to use |
|---|---|
| **512** | Heavy censorship, mobile networks, Iran shutdowns |
| 800 | Unstable connections |
| 1024 | Moderate censorship |
| 1232 | Default — may fail under heavy filtering |

**Start with 512.** Increase if connection is stable.

---

# Included Files

| File | What it does |
|---|---|
| `dns-tunnel-server.sh` | **Main script** — server setup + management menu (run on VPS) |
| `connect.ps1` | Windows client — auto-tries DoH/DoT/UDP resolvers |
| `connect.sh` | Linux/Mac client — same smart fallback |
| `quick-connect.bat` | Simple Windows batch — edit 2 lines, share with friends |
| `config-generator.py` | Generate shareable config packages |

---

# Troubleshooting

### Connection fails on all DoH endpoints
- The DoH hostname might be DNS-blocked. Temporarily set system DNS to `10.202.10.202` (Shecan) or `178.22.122.100` (403.online)
- Try DoT instead (`-dot dns.google:853`)
- Try lesser-known resolvers: AdGuard, NextDNS, Mullvad

### Very slow
- **This is expected** — DoH adds ~30-50% overhead, but reliability matters more
- Lower MTU to 512
- Try different resolvers (latency varies)
- Close bandwidth-heavy apps

### Works for me, not my friend
- Different ISP = different blocking. Try different resolvers.
- The `connect.ps1` / `connect.sh` scripts auto-cycle through resolvers

### "FORMERR: payload size too small"
- Server MTU is too high. Reconfigure with menu option **8)** → MTU = 512

### Server won't start
- Check logs: menu option **4)** or `sudo bash dns-tunnel-server.sh logs`
- Verify port 53 is free: `ss -ulnp | grep :53`
- Verify DNS records propagated: `dig NS t.example.com`

---

<div dir="rtl">

# راهنمای فارسی

## خلاصه مشکل

ابزارهای قبلی (`dnstt-deploy` و `dnstm-setup`) ترافیک رو از **پورت UDP/53** می‌فرستن. فیلترینگ ایران حالا این رو تشخیص میده.

## راه‌حل

به جای DNS ساده، ترافیک رو داخل **HTTPS عادی** به Google می‌فرستیم (DoH). فیلتر فقط ترافیک HTTPS به google.com می‌بینه.

## نصب سرور (VPS اوبونتو)

</div>

```bash
sudo bash dns-tunnel-server.sh
# گزینه 1 رو انتخاب کنید (Install & Setup)
# مراحل رو دنبال کنید
```

<div dir="rtl">

## اتصال کلاینت (تغییر اصلی)

</div>

```bash
# DoH از طریق Google (پیشنهادی)
dnstt-client -doh https://dns.google/dns-query -pubkey-file server.pub t.example.com 127.0.0.1:7000

# اگر Google کار نکرد
dnstt-client -doh https://cloudflare-dns.com/dns-query -pubkey-file server.pub t.example.com 127.0.0.1:7000
```

<div dir="rtl">

## ارسال به دوستان

از منوی سرور گزینه **3)** رو بزنید — بلوک متنی آماده کپی نشون میده. یا فایل `quick-connect.bat` رو ویرایش و ارسال کنید.

## نکات
- MTU رو **512** بذارید
- resolverهای مختلف امتحان کنید (هر ISP یکی رو بلاک میکنه)
- کندتره ولی **کار میکنه**

</div>
