<div dir="rtl">

# DARK REALM PRO

[فارسی](README.fa.md) · [English](README.md)

</div>

```text
╭──────────────────────────────────────────────────────────────────╮
│ ██████╗  █████╗ ██████╗ ██╗  ██╗                                │
│ ██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝                                │
│ ██║  ██║███████║██████╔╝█████╔╝                                 │
│ ██║  ██║██╔══██║██╔══██╗██╔═██╗                                 │
│ ██████╔╝██║  ██║██║  ██║██║  ██╗                                │
│ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝                                │
│ R E A L M  ·  Native high-performance relay                     │
╰──────────────────────────────────────────────────────────────────╯
```

<div dir="rtl">

**DARK REALM PRO v1.0.0** لایه مدیریتی مستقل ما برای هسته رسمی
[Realm](https://github.com/zhboner/realm) است.

معماری و فایل کانفیگ Realm دست‌کاری نمی‌شود. لایه DARK تجربه کاربری یکسان پروژه‌های ما را اضافه می‌کند: نصب آسان، ساخت مرحله‌ای ایران و خارج، Pair Code نسخه‌دار، Multi-Port، صدور خودکار گواهی، systemd مجزا، داشبورد، عیب‌یابی، تست واقعی سرعت خود تونل، آپدیت، بکاپ و Rollback.

> ظاهر و مدیریت یکسان DARK؛ منطق داخلی کاملاً Native خود Realm.

توسعه‌دهنده و پشتیبانی: **@mikakhadm**

## معماری واقعی

Realm یک **Direct Relay** است و مثل Backhaul تونل Reverse/Mux اختصاصی نیست.

</div>

```text
USER
  │
  ▼
IRAN Realm Edge
پورت‌های عمومی کاربران
  │
  │ TCP / TLS / WS / WSS
  ▼
KHAREJ Realm Gateway
پورت‌های شنونده ترنسپورت
  │
  ▼
127.0.0.1:<Xray / Panel / Application Port>
```

<div dir="rtl">

سمت ایران Pair Code با پیشوند `DR1` می‌سازد و سمت خارج آن را دریافت می‌کند. Pair Code فقط اطلاعات معتبر استقرار را دارد و هیچ Private Key یا رمز عبوری داخل آن قرار نمی‌گیرد.

## نصب سریع

</div>

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/darktunnelmika/dark-realm/main/install.sh)
```

<div dir="rtl">

برای اجرای بعدی:

</div>

```bash
darkrealm
```

<div dir="rtl">

پلتفرم‌های اصلی:

- لینوکس مدرن روی `amd64/x86_64`
- لینوکس مدرن روی `arm64/aarch64`
- نصب وابستگی با `apt`، `dnf`، `yum` و در حد امکان `apk`

Manager نسخه کامل Realm را دانلود می‌کند، SHA-256 رسمی Asset گیت‌هاب را بررسی می‌کند، نسخه باینری را می‌سنجد و نصب را به‌صورت اتمیک انجام می‌دهد. هسته اولیه تأییدشده **Realm v2.9.6** است.

## منوی اصلی

</div>

```text
SETUP
  [1] Core
  [2] New Tunnel — IRAN
  [3] New Tunnel — KHAREJ

OPERATE
  [4] Manage Tunnels
  [5] Dashboard
  [6] Diagnostics

MAINTENANCE
  [7] Update
  [8] Backup / Restore
  [9] Uninstall
```

<div dir="rtl">

## ترنسپورت‌های Native

| ترنسپورت | دامنه | گواهی | کاربرد |
|---|---:|---:|---|
| TCP | لازم نیست | لازم نیست | کمترین سربار و بیشترین سرعت خام |
| TLS | لازم است | روی سرور خارج | ارتباط رمزنگاری‌شده |
| WS | Host و Path | لازم نیست | WebSocket |
| WSS | دامنه، Host و Path | روی سرور خارج | WebSocket روی TLS معتبر |

هیچ گزینه جعلی Backhaul مثل Pool، Channel یا `tcpmux` به Realm اضافه نشده است.

### محل صحیح گواهی

گواهی باید روی سمتی باشد که Realm در آن `listen_transport` اجرا می‌کند. در معماری استاندارد ما این سمت **KHAREJ Gateway** است.

هنگام واردکردن Pair Code با TLS یا WSS روی خارج، بخش زیر خودکار باز می‌شود:

</div>

```text
[1] Select an existing certificate
[2] Get a Let's Encrypt certificate now
[3] Create a self-signed certificate (test mode only)
[4] Enter certificate/key paths manually
```

<div dir="rtl">

مدیریت گواهی شامل موارد زیر است:

- شناسایی گواهی‌های DARK، Let's Encrypt و مسیرهای رایج پنل‌ها
- بررسی تطابق Certificate و Private Key
- بررسی SAN/Wildcard و تاریخ انقضا
- تطبیق DNS دامنه با IP سرور Gateway
- نمایش دقیق برنامه‌ای که پورت 80 را اشغال کرده
- نصب `acme.sh` فقط هنگام نیاز
- صدور گواهی واقعی Let's Encrypt
- ذخیره داخل `/etc/dark-realm/certs/<domain>/`
- تمدید خودکار و Restart فقط تونل‌های وابسته
- جلوگیری از نمایش Private Key در Pair Code، لاگ و Diagnostics

حالت Trusted TLS پیش‌فرض Production است. Self-signed فقط برای تست بوده و باعث فعال‌شدن `insecure` سمت کلاینت می‌شود.

## Multi-Port و Port Mapping

فرمت‌های قابل قبول:

</div>

```text
443
443,2053,2083,8443
2000-2100
443>8000,2053>8000,8443>8443
```

<div dir="rtl">

معنای داخلی:

</div>

```text
public-port > kharej-target-port @ kharej-backbone-port
```

<div dir="rtl">

هر Mapping به یک `[[endpoints]]` واقعی Realm تبدیل می‌شود. پورت‌های تکراری، مقادیر نامعتبر و تداخل‌های محلی رد می‌شوند. سقف پیش‌فرض گسترش، ۲۵۶ Endpoint است.

## پروفایل‌های سرعت

| پروفایل | کاربرد |
|---|---|
| Stable | مسیرهای پرافت و ناپایدار |
| Balanced | حالت عمومی و پیش‌فرض |
| Low Ping | ترافیک حساس به تأخیر |
| Turbo | یوزر و Connection زیاد |
| Custom | تنظیم دستی مقادیر واقعی |

پروفایل‌ها فقط پارامترهای واقعی را تغییر می‌دهند: TCP timeout، Keepalive، تعداد Probe، Log Level، `LimitNOFILE` و Restart Delay.

## مدیریت تونل

هر تونل کانفیگ و سرویس مستقل دارد:

</div>

```text
/etc/dark-realm/tunnels/turkey/config.toml
/etc/dark-realm/tunnels/turkey/meta.conf
dark-realm@turkey.service
```

<div dir="rtl">

قابلیت‌ها:

- Start، Stop و Restart
- نمایش Pair Code روی ایران و Import روی خارج
- تغییر Mapping، پروفایل، Endpoint و Transport
- تعویض گواهی TLS
- Scheduled Restart
- نمایش Config و Fingerprint
- Live Log، لاگ اخیر و Connectionهای کرنل
- بازسازی تراکنشی کانفیگ و Rollback خودکار
- Backup/Restore برای هر تونل
- ویرایش محافظت‌شده TOML
- حذف امن با حفظ گواهی‌های مشترک

## داشبورد و عیب‌یابی

داشبورد اطلاعات واقعی زیر را نمایش می‌دهد:

- وضعیت سرویس، PID و Uptime
- نقش، ترنسپورت، پروفایل و تعداد Endpoint
- Sessionهای فعال
- RX/TX استخراج‌شده از TCP Counterهای کرنل
- دامنه TLS و روزهای باقی‌مانده گواهی

Diagnostics شامل:

- بررسی سرویس، Process و Listener
- بررسی ساختار TOML
- تست دسترسی و تأخیر TCP تا Gateway
- تست TLS و SNI
- بررسی Listener مقصد روی خارج
- بررسی Cert/Key/SAN/Expiry
- Fingerprint دوطرفه
- خروجی عیب‌یابی بدون اطلاعات حساس

### تست واقعی سرعت خود تونل

این بخش Speedtest اینترنت نیست.

۱. روی Gateway خارج، **Tunnel throughput** را اجرا کن تا Realm موقت و `iperf3` یک‌بارمصرف ساخته شود و کد `DRS1` بدهد.
۲. روی Edge ایران همان بخش را باز کن و کد را وارد کن.
۳. تست از داخل ترنسپورت انتخابی Realm عبور می‌کند و Processهای موقت بعد از پایان پاک می‌شوند.

## امنیت

- Pair Code و `meta.conf` هیچ‌وقت با Shell اجرا یا `source` نمی‌شوند.
- تمام فیلدها Whitelist و اعتبارسنجی دارند.
- Checksum Pair Code فقط خرابی داده را تشخیص می‌دهد و Authentication محسوب نمی‌شود.
- کاراکتر کنترلی، Path ناامن و Shell Injection رد می‌شود.
- تمام فایل‌های موقت با `mktemp` ساخته می‌شوند.
- دانلود Core فقط از HTTPS و با SHA-256 رسمی انجام می‌شود.
- آپدیت و تغییر کانفیگ دارای Backup و Rollback است.
- Private Key سطح دسترسی `0600` دارد.
- بکاپ معمولی کلید خصوصی را خارج می‌کند.
- عملیات حذف نیاز به تأیید متنی دارد.

برای جزئیات بیشتر [SECURITY.md](SECURITY.md) را ببین.

## بکاپ و حذف

بکاپ کامل به‌صورت پیش‌فرض Private Keyها را شامل نمی‌شود. برای خروجی گرفتن از کلیدها باید تأیید جداگانه وارد شود.

Uninstall سه حالت دارد:

۱. فقط حذف Manager
۲. حذف Tunnelها و Core با حفظ Certificateها
۳. حذف کامل DARK Realm

اسکریپت به فایل‌های پنل، سرویس‌های تونل دیگر یا تنظیمات نامرتبط دست نمی‌زند.

## مسیرهای سرور

</div>

```text
/etc/dark-realm/
├── tunnels/<name>/
│   ├── config.toml
│   ├── meta.conf
│   └── backups/
├── certs/<domain>/
│   ├── fullchain.pem
│   └── privkey.pem
├── runtime/
├── backups/
├── core.version
└── update.url

/usr/local/bin/realm
/usr/local/bin/darkrealm
/etc/systemd/system/dark-realm@.service
/etc/systemd/system/dark-realm-restart@.service
/etc/systemd/system/dark-realm-restart@.timer
```

<div dir="rtl">

## تست توسعه

</div>

```bash
bash -n dark-realm.sh install.sh
./tests/test.sh
shellcheck --severity=error -e SC1090 dark-realm.sh install.sh tests/test.sh
```

<div dir="rtl">

تست‌ها شامل Mapping Parser، دست‌کاری و Injection در Pair Code، عدم اجرای `meta.conf`، ساخت Native کانفیگ TCP/WSS و اعتبارسنجی Certificate/Key/SAN هستند.

## پروژه بالادست و مجوز

Realm توسط توسعه‌دهندگان مستقل پروژه بالادست ساخته می‌شود. DARK REALM PRO فقط Manager مستقل ماست و پروژه رسمی Realm محسوب نمی‌شود.

Manager و Realm هر دو تحت MIT License منتشر شده‌اند.

</div>
