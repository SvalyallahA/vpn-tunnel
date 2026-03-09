# DNS Tunnel Server — Config Generator for HTTP Injector & SlipNet

Generates **20 config strings** with different DNS resolvers for HTTP Injector (`dns://`) and SlipNet (`slipnet://`). Each ISP in Iran blocks different resolvers — send your friend several configs until one works.

---

## Why Old Configs Stop Working

- Each config uses one DNS resolver (e.g. `8.8.8.8:53`)
- Iran blocks resolvers differently per ISP (MCI, Irancell, Shatel, etc.)
- DoH (DNS-over-HTTPS) is **SNI-blocked** — doesn't work at all
- **Solution:** generate configs with **many different UDP resolvers** and try them

---

# How to Use

## Step 1 — Set Up Server (Ubuntu VPS)

```bash
curl -fsSL -o dns-tunnel-server.sh https://raw.githubusercontent.com/SvalyallahA/vpn-tunnel/main/dns-tunnel-solution/dns-tunnel-server.sh
sudo bash dns-tunnel-server.sh
```

Choose **1) Install & Setup** → follow the wizard.

## Step 2 — Get Config Strings

Choose **3) Show Configuration**. It generates **20 configs per app** using these resolvers:

| Provider | Resolver 1 | Resolver 2 |
|---|---|---|
| Google | `8.8.8.8:53` | `8.8.4.4:53` |
| Cloudflare | `1.1.1.1:53` | `1.0.0.1:53` |
| Quad9 | `9.9.9.9:53` | `149.112.112.112:53` |
| OpenDNS | `208.67.222.222:53` | `208.67.220.220:53` |
| AdGuard | `94.140.14.14:53` | `94.140.15.15:53` |
| CleanBrowsing | `185.228.168.9:53` | `185.228.169.9:53` |
| ControlD | `76.76.19.19:53` | `76.76.2.0:53` |
| Verisign | `64.6.64.6:53` | `64.6.65.6:53` |
| Yandex | `77.88.8.8:53` | `77.88.8.1:53` |
| Neustar | `156.154.70.1:53` | `156.154.71.1:53` |

## Step 3 — Share with Friend

1. Copy 3-4 `dns://` strings (different resolvers)
2. Send via messenger
3. Friend imports in **HTTP Injector** → tries each until one connects

For SlipNet (Android): send the `slipnet://` strings instead.

## Step 4 — If It Doesn't Work

- **Try a different resolver** — that's the whole strategy
- **Lower MTU** — reconfigure with menu **8)** → set MTU to 512
- **Check server** — menu **2)** for status, **4)** for logs

---

# Server Management

```bash
sudo bash dns-tunnel-server.sh
```

| Menu | Action |
|---|---|
| **1) Install & Setup** | Setup wizard |
| **2) Show Status** | Service status |
| **3) Show Configuration** | **Config strings to share** |
| **4) View Logs** | Troubleshooting |
| **5/6/7)** | Start / Stop / Restart |
| **8) Reconfigure** | Change MTU, mode, domain |
| **9) Uninstall** | Clean removal |

---

<div dir="rtl">

# راهنمای فارسی

## مشکل
هر ISP (همراه اول، ایرانسل، شاتل و ...) resolver های مختلفی رو بلاک می‌کنه. DoH هم کلا بلاکه.

## راه‌حل
این اسکریپت **۲۰ کانفیگ** با resolver های مختلف تولید می‌کنه. چندتا بفرستید تا یکیشون کار کنه.

## نحوه استفاده
1. سرور: `sudo bash dns-tunnel-server.sh` → گزینه 1
2. گزینه **3)** → کانفیگ‌ها نشون داده میشه
3. ۳-۴ تا رشته `dns://` رو کپی و برای دوستتون بفرستید
4. دوستتون توی HTTP Injector امتحان می‌کنه — هرکدوم وصل شد همون

## نکات
- MTU رو **512** بذارید
- اگر یکی کار نکرد، با resolver بعدی امتحان کنید
- کند ولی **کار می‌کنه**

</div>
