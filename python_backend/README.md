# Floating Downloader — yt-dlp Backend

این پوشه Backend پایتونی‌ای است که منطق `yt-dlp` اسکریپت شما را وارد پروژه Flutter می‌کند.

## معماری

- Flutter: رابط کاربری، صف دانلود، MediaStore، History و Floating Window
- Flask + yt-dlp: استخراج واقعی عنوان/کاور/مدت/کیفیت و تولید فایل نهایی
- Android: فایل خروجی Backend را به `Downloads` منتقل می‌کند.
- لینک‌های مستقیم فایل همچنان با موتور بومی Flutter دانلود می‌شوند.

## راه‌اندازی Backend

Python 3.10+ توصیه می‌شود:

```bash
cd python_backend
python -m venv .venv
# Linux/macOS:
source .venv/bin/activate
# Windows:
# .venv\Scripts\activate

pip install -r requirements.txt
python server.py
```

سرویس روی پورت `8000` اجرا می‌شود و این endpoint برای تست دارد:

`GET /health`

### FFmpeg

برای انتخاب‌های `bestvideo+bestaudio` و تبدیل MP3 باید FFmpeg روی همان ماشینی که Backend اجرا می‌شود نصب باشد و `ffmpeg` در PATH باشد.

### کوکی

برای سایت‌هایی که به کوکی معتبر نیاز دارند:

```bash
YTDLP_COOKIEFILE=/absolute/path/cookies.txt python server.py
```

### Proxy پیش‌فرض

چند Proxy را می‌توان با کاما جدا کرد:

```bash
YTDLP_PROXIES=http://proxy1:8080,http://proxy2:8080 python server.py
```

## اتصال Android

در برنامه:

`تنظیمات → Backend استخراج → سرویس yt-dlp`

مثلاً اگر کامپیوتر و گوشی روی یک Wi-Fi هستند:

```text
http://192.168.1.10:8000
```

**نکته:** `localhost` روی گوشی به خود گوشی اشاره می‌کند، نه کامپیوتر شما.

## نکات مهم

- Backend را بدون احراز هویت روی اینترنت عمومی قرار ندهید؛ این سرویس endpoint دانلود/Proxy دارد.
- DRM، محتوای خصوصی و محدودیت‌های خود پلتفرم‌ها قابل تضمین نیستند.
- این پروژه هیچ فایل ساختگی برای موفق‌نشان‌دادن دانلود ایجاد نمی‌کند؛ اگر yt-dlp استخراج را نتواند انجام دهد، خطا به Flutter برمی‌گردد.
