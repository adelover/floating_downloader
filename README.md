# Floating Downloader 3.0

یک دانلودر اندرویدی مدرن با:

- دانلود واقعی فایل‌های HTTP/HTTPS
- ذخیره استاندارد در `Downloads` با Android MediaStore
- پنجره شناور برای دانلود سریع
- مرورگر داخلی با تشخیص لینک‌های مستقیم رسانه
- تاریخچه دانلودهای تکمیل‌شده
- صف دانلود با محدودیت هم‌زمانی و کنترل مکث/ادامه/لغو/تلاش دوباره
- رابط کاربری RTL و Dark حرفه‌ای
- GitHub Actions برای `flutter analyze` و ساخت APK

## نکته مهم درباره «واقعی بودن»

این پروژه لینک‌های مستقیم فایل را واقعاً دانلود و در Downloads ذخیره می‌کند. دیگر از مسیر ثابت
`/storage/emulated/0/Download` یا مجوزهای قدیمی Storage استفاده نمی‌شود.

لینک‌های HLS مثل `.m3u8` و محتوای DRM عمداً به عنوان MP4 جعلی ذخیره نمی‌شوند. برای تبدیل HLS به MP4
باید یک موتور remux/segment downloader جداگانه اضافه شود و برای DRM نیز محدودیت‌های فنی و حقوقی وجود دارد.

## اجرای پروژه

```bash
flutter pub get
dart run flutter_launcher_icons
flutter analyze
flutter build apk --release
```

حداقل Android SDK این نسخه 29 است.

## معماری ذخیره‌سازی

Dart فایل را ابتدا در cache موقت دانلود می‌کند، سپس با MethodChannel به Android native می‌فرستد.
Android با `MediaStore.Downloads` فایل را در پوشه Downloads عمومی ثبت می‌کند و بعد فایل موقت حذف می‌شود.

`DownloadQueueController` صف را خارج از `main.dart` مدیریت می‌کند و سرویس دانلود مسئول
اعتبارسنجی لینک، پاک‌سازی نام فایل و انتقال امن به MediaStore است. دانلودهای در حال اجرا
در پس‌زمینه‌ی Flutter ادامه پیدا می‌کنند؛ برای تداوم پس از کشته‌شدن کامل process، یک
foreground download service بومی (خارج از وابستگی‌های فعلی) لازم است.

## تست

قبل از انتشار APK روی یک دستگاه واقعی این موارد را تست کنید:

1. دانلود یک MP4 عمومی.
2. دانلود یک MP3 عمومی.
3. باز کردن مرورگر و شناسایی یک لینک MP4 مستقیم.
4. فعال‌سازی Overlay و دانلود از پنجره شناور.
5. بررسی فایل در برنامه Files > Downloads.
6. اجرای `flutter analyze` بدون خطا.


## yt-dlp Backend

این نسخه یک Backend واقعی Flask + yt-dlp داخل پوشه `python_backend/` دارد. برای YouTube، Instagram، TikTok و SoundCloud، برنامه ابتدا اطلاعات و کیفیت‌های واقعی را از Backend می‌گیرد و سپس فایل خروجی yt-dlp را به Downloads اندروید منتقل می‌کند.

برای راه‌اندازی:
1. وارد `python_backend/` شوید.
2. `pip install -r requirements.txt` را اجرا کنید.
3. `python server.py` را اجرا کنید.
4. در برنامه به `تنظیمات → Backend استخراج → سرویس yt-dlp` بروید و آدرس سرور را وارد کنید، مثلاً `http://192.168.1.10:8000`.
5. برای MP3 و ادغام video+audio، FFmpeg باید روی سرور نصب باشد.

این Backend عمداً داخل APK به‌صورت Python interpreter بسته‌بندی نشده است؛ بنابراین برنامه Android و Backend باید از طریق شبکه به هم دسترسی داشته باشند.
