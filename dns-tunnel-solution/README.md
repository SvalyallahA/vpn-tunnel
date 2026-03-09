# DNS Tunnel Server — DoH Config Generator

Improved DNS tunnel server setup that generates **HTTP Injector** and **SlipNet** compatible config strings using **DoH (DNS-over-HTTPS)** instead of plain UDP — the fix for when old configs stop working.

---

## The Problem

Old configs use `"addr":"8.8.8.8:53"` (plain UDP DNS). Iran's DPI detects and blocks this. Different ISPs block differently — that's why it works for you but not your friend.

## The Fix

Same config format, but with **DoH resolvers** instead of UDP:
- `"addr":"https://dns.google/dns-query"` instead of `"addr":"8.8.8.8:53"`
- `slipnet://` configs with `dnsTransport=doh` instead of `udp`

Traffic now looks like normal HTTPS to Google. Slower, but works.

---

# How to Use

## Step 1 — Set Up Server on Ubuntu VPS

```bash
curl -fsSL -o dns-tunnel-server.sh https://raw.githubusercontent.com/SvalyallahA/vpn-tunnel/main/dns-tunnel-solution/dns-tunnel-server.sh
sudo bash dns-tunnel-server.sh
```

Choose **1) Install & Setup** and follow the 9-step wizard.

## Step 2 — Get Config Strings

Choose **3) Show Configuration** from the menu. It outputs:

**For HTTP Injector** — `dns://` config strings with DoH:
```
dns://eyJwcyI6Ikdvb2dsZS1Eb0giLCJhZGRyIjoiaHR0cHM6Ly9kbnMuZ29vZ2xlL2Rucy1xdWVyeSIsIm5zIjoidC5leGFtcGxlLmNvbSIsInB1YmtleSI6IjY0Y2hhcmhleCIsInVzZXIiOiIiLCJwYXNzIjoiIn0=
```

**For SlipNet (Android)** — `slipnet://` config strings with DoH:
```
slipnet://MTZ8ZG5zdHR8R29vZ2xlLURvSHx0LmV4YW1wbGUuY29tfDguOC44Ljg6NTM6MHwwfDUwMDB8YmJyfDEwODB8MTI3LjAuMC4xfDB8NjRjaGFyaGV4fHx8fHx8MjJ8MHwxMjcuMC4wLjF8MHxodHRwczovL2Rucy5nb29nbGUvZG5zLXF1ZXJ5fGRvaHxwYXNzd29yZHx8fDB8MHw0NDN8fHwwfHwwfDB8
```

Multiple resolvers are generated (Google, Cloudflare, Quad9, AdGuard). Send your friend whichever works on their ISP.

## Step 3 — Share Config String with Friend

1. Copy the `dns://` or `slipnet://` string from the menu
2. Send it to your friend via any messenger
3. They import it in their app — done

**HTTP Injector:** Paste the `dns://` string in the import field
**SlipNet:** Tap the `slipnet://` link on Android — auto-imports

## Step 4 — If One Resolver is Blocked, Try Another

Each ISP blocks different resolvers. The script generates configs for 4 DoH resolvers:

| Config | Resolver | Try order |
|---|---|---|
| **Google DoH** | `https://dns.google/dns-query` | First |
| **Cloudflare DoH** | `https://cloudflare-dns.com/dns-query` | Second |
| **Quad9 DoH** | `https://dns.quad9.net/dns-query` | Third |
| **AdGuard DoH** | `https://dns.adguard-dns.com/dns-query` | Fourth |

Send your friend 2-3 configs with different resolvers so they can try until one works.

---

# Server Management

```bash
sudo bash dns-tunnel-server.sh
```

| Menu | Action |
|---|---|
| **1) Install & Setup** | Setup wizard |
| **2) Show Status** | Service status, ports, uptime |
| **3) Show Configuration** | **Config strings to share** (dns:// + slipnet://) |
| **4) View Logs** | Live or recent logs |
| **5/6/7) Start/Stop/Restart** | Service control |
| **8) Reconfigure** | Change MTU, mode, domain, keys |
| **9) Uninstall** | Clean removal |

---

# Troubleshooting

- **Works for me, not friend** → send them a config with a different DoH resolver
- **Very slow** → expected with DoH, lower MTU to 512
- **"FORMERR: payload size too small"** → reconfigure server MTU to 512
- **Server won't start** → menu **4)** to check logs, verify port 53 is free

---

<div dir="rtl">

# راهنمای فارسی

## مشکل
کانفیگ‌های قبلی از `8.8.8.8:53` (UDP ساده) استفاده می‌کنن. فیلترینگ ایران این رو تشخیص میده.

## راه‌حل
همون فرمت کانفیگ، ولی با **DoH** به جای UDP. ترافیک شبیه HTTPS عادی به Google میشه.

## نحوه استفاده
1. سرور رو نصب کنید: `sudo bash dns-tunnel-server.sh` → گزینه 1
2. از منو گزینه **3)** رو بزنید تا کانفیگ‌ها نشون داده بشه
3. رشته `dns://` رو کپی کنید و برای دوستتون بفرستید
4. دوستتون توی HTTP Injector وارد می‌کنه — تمام

اگر یک resolver کار نکرد، کانفیگ با resolver دیگه بفرستید (Google، Cloudflare، Quad9، AdGuard).

</div>
